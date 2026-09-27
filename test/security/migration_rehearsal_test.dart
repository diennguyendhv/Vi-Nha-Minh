import 'dart:io';

import 'package:cryptography/dart.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:vi_nha_minh/core/crypto/backup_crypto.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/db_encryption/migration_rehearsal.dart';
import 'package:vi_nha_minh/data/local/db_encryption/sqlcipher_wallet.dart';
import 'package:vi_nha_minh/data/local/seed_defaults.dart';

/// Diễn tập di trú (quyết định chủ dự án 2026-09-27, phương án a): nguồn là ví THẬT
/// đã mã hoá ở schema cũ; bản sao mã hoá tạm được di trú + so sánh + xoá; file thật
/// không đổi 1 byte.
void main() {
  late Directory dir;
  late Directory scratch;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('vnm_rehearsal_');
    scratch = Directory('${dir.path}/scratch');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<List<int>> sha(File f) async =>
      (await const DartSha256().hash(await f.readAsBytes())).bytes;

  /// Ví demo có thu/chi/nạp quỹ, hạ về đúng hình dạng v10, rồi mã hoá bằng [key].
  Future<File> encryptedV10(Uint8List key, {int userVersion = 10}) async {
    final plain = File('${dir.path}/plain.sqlite');
    final db = AppDatabase.forTesting(NativeDatabase(plain), seed: SeedProfile.demo);
    final income = (await (db.select(db.categoryRows)
          ..where((c) => c.type.equals('income')))
        .get()).first.id;
    final expense = (await (db.select(db.categoryRows)
          ..where((c) => c.type.equals('expense')))
        .get()).first.id;
    for (var i = 0; i < 30; i++) {
      final d = DateTime(2026, 9, 1).add(Duration(days: i));
      await db.into(db.transactionRows).insert(TransactionRowsCompanion.insert(
        id: 'in-$i', type: 'income', categoryId: income, sourceKind: 'external',
        destinationKind: 'memberAvailable', destinationRefId: Value(i.isEven ? 'vo' : 'chong'),
        amountMinor: 100000 + i, note: Value('Ghi chú $i'), transactionDate: d,
        createdAt: d, clientTxId: 'c-in-$i'));
      await db.into(db.transactionRows).insert(TransactionRowsCompanion.insert(
        id: 'out-$i', type: 'expense', categoryId: expense, sourceKind: 'memberAvailable',
        sourceRefId: Value(i.isEven ? 'vo' : 'chong'), destinationKind: 'external',
        amountMinor: 1000 + i, transactionDate: d, createdAt: d, clientTxId: 'c-out-$i'));
    }
    await db.close();
    final raw = sqlite3.open(plain.path);
    raw.execute('DROP TABLE sync_conflicts');
    raw.execute('PRAGMA legacy_alter_table = ON');
    raw.execute('ALTER TABLE sync_state RENAME TO sync_state_v11');
    raw.execute('CREATE TABLE sync_state (singleton INTEGER NOT NULL DEFAULT 1 CHECK (singleton = 1), '
        'capture_suppressed INTEGER NOT NULL DEFAULT 0 CHECK (capture_suppressed IN (0, 1)), '
        'server_head_rev INTEGER NULL, last_push_at INTEGER NULL, last_pull_at INTEGER NULL, '
        'PRIMARY KEY (singleton))');
    raw.execute('DROP TABLE sync_state_v11');
    raw.close();

    final live = File('${dir.path}/vi_nha_minh.sqlite');
    final enc = sqlite3.open(live.path, uri: true);
    applySqlcipherKey(enc, key);
    enc.execute("ATTACH DATABASE ? AS plain KEY ''", [plain.path]);
    enc.select("SELECT sqlcipher_export('main', 'plain')");
    enc.execute('DETACH DATABASE plain');
    enc.userVersion = userVersion;
    enc.close();
    plain.deleteSync();
    return live;
  }

  test('v10 thật (mã hoá) → PASS; file thật không đổi, vẫn v10; bản sao đã xoá', () async {
    final key = BackupCrypto.randomBytes(32);
    final live = await encryptedV10(key);
    final shaBefore = await sha(live);

    final r = await rehearseWalletMigration(live: live, liveKey: key, scratch: scratch);

    expect(r.mismatches, isEmpty);
    expect(r.pass, isTrue);
    expect(r.report['fromVersion'], 10);
    expect(r.report['toVersion'], 11);
    expect(r.report['transactions'], 60);
    expect(r.report['memberIds'], ['chong', 'vo']);
    expect(r.report['liveUnchanged'], isTrue);
    expect(r.report['rehearsalFileDeleted'], isTrue);
    final tables = r.report['tables']! as Map;
    expect(tables['transaction_rows'], [60, 60, true]);
    expect(tables['sync_conflicts'], [-1, 0, false]);
    expect(scratch.listSync(), isEmpty);
    expect(await sha(live), shaBefore);
    final check = sqlite3.open(live.path, mode: OpenMode.readOnly);
    applySqlcipherKey(check, key);
    expect(check.userVersion, 10);
    check.close();
  });

  test('sai khoá ⇒ FAIL, không ghi gì, không để lại bản sao', () async {
    final live = await encryptedV10(BackupCrypto.randomBytes(32));
    final shaBefore = await sha(live);
    final r = await rehearseWalletMigration(
      live: live,
      liveKey: BackupCrypto.randomBytes(32),
      scratch: scratch,
    );
    expect(r.pass, isFalse);
    expect(r.report['liveUnchanged'], isTrue);
    expect(await sha(live), shaBefore);
    expect(scratch.existsSync() ? scratch.listSync() : const [], isEmpty);
  });

  test('phiên bản nguồn không khai báo thay đổi cho phép ⇒ từ chối (không đoán)', () async {
    final key = BackupCrypto.randomBytes(32);
    final live = await encryptedV10(key, userVersion: 9);
    final r = await rehearseWalletMigration(live: live, liveKey: key, scratch: scratch);
    expect(r.mismatches, contains('unsupported-source-version:9'));
    expect(r.report['liveUnchanged'], isTrue);
  });

  test('journal nóng cạnh file thật ⇒ không khôi phục (là 1 lần ghi), chỉ báo', () async {
    final key = BackupCrypto.randomBytes(32);
    final live = await encryptedV10(key);
    File('${live.path}-journal').writeAsBytesSync([1, 2, 3]);
    final r = await rehearseWalletMigration(live: live, liveKey: key, scratch: scratch);
    expect(r.mismatches, ['source-has-journal']);
    expect(File('${live.path}-journal').readAsBytesSync(), [1, 2, 3]);
  });
}
