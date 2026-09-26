import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3_pkg;
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/seed_defaults.dart';
import 'package:vi_nha_minh/data/local/sync/cloud_binding_store.dart';
import 'package:vi_nha_minh/data/local/sync/sync_capture.dart';

/// Schema v10 → v11 (P8.3): chỉ thêm cột nullable `sync_state.backup_state` + bảng
/// `sync_conflicts`. Không dòng nào (tài chính, binding, outbox, con trỏ) bị đổi.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vnm_migration_v11_'));
  tearDown(() => dir.deleteSync(recursive: true));

  List<Map<String, Object?>> dump(sqlite3_pkg.Database raw, String table) => [
    for (final r in raw.select('SELECT * FROM $table ORDER BY rowid')) Map.of(r),
  ];

  test('v10 → v11 giữ nguyên mọi dòng; trạng thái sao lưu = null; trigger vẫn chạy', () async {
    final file = File('${dir.path}/v10.sqlite');
    final seed = AppDatabase.forTesting(NativeDatabase(file), seed: SeedProfile.demo);
    await seed.into(seed.transactionRows).insert(TransactionRowsCompanion.insert(
      id: 'tx-1', type: 'income', categoryId: 'thu_nhap', sourceKind: 'external',
      destinationKind: 'memberAvailable', destinationRefId: const Value('vo'),
      amountMinor: 123, transactionDate: DateTime(2026, 9, 1), createdAt: DateTime(2026, 9, 1),
      clientTxId: 'c-1'));
    final store = CloudBindingStore(seed);
    await store.beginClaim(accountId: 'uid', selfMemberId: 'vo', environment: 'dev',
        claimRequestId: 'r-1');
    await store.activate(claimRequestId: 'r-1');
    await seed.into(seed.transactionRows).insert(TransactionRowsCompanion.insert(
      id: 'tx-2', type: 'income', categoryId: 'thu_nhap', sourceKind: 'external',
      destinationKind: 'external', amountMinor: 5, transactionDate: DateTime(2026, 9, 2),
      createdAt: DateTime(2026, 9, 2), clientTxId: 'c-2'));
    await seed.customStatement(
        'INSERT INTO sync_state (singleton, capture_suppressed, server_head_rev) VALUES (1, 0, 7)');
    await seed.close();

    // Hạ về đúng hình dạng v10: bỏ bảng mới, dựng lại sync_state không có cột mới.
    final raw = sqlite3_pkg.sqlite3.open(file.path);
    raw.execute('DROP TABLE sync_conflicts');
    raw.execute('PRAGMA legacy_alter_table = ON'); // trigger giữ tham chiếu sync_state
    raw.execute('ALTER TABLE sync_state RENAME TO sync_state_v11');
    raw.execute('CREATE TABLE sync_state (singleton INTEGER NOT NULL DEFAULT 1 CHECK (singleton = 1), '
        'capture_suppressed INTEGER NOT NULL DEFAULT 0 CHECK (capture_suppressed IN (0, 1)), '
        'server_head_rev INTEGER NULL, last_push_at INTEGER NULL, last_pull_at INTEGER NULL, '
        'PRIMARY KEY (singleton))');
    raw.execute('INSERT INTO sync_state SELECT singleton, capture_suppressed, server_head_rev, '
        'last_push_at, last_pull_at FROM sync_state_v11');
    raw.execute('DROP TABLE sync_state_v11');
    raw.execute('PRAGMA user_version = 10;');
    final tables = ['transaction_rows', 'category_rows', 'status_rows', 'fund_rows',
      'financial_member_rows', 'wallet_meta', 'cloud_binding', 'sync_outbox', 'wallet_settings'];
    final before = {for (final t in tables) t: dump(raw, t)};
    raw.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    expect((await db.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version'), 11);
    final state = await db.select(db.syncState).getSingle();
    expect(state.serverHeadRev, 7);
    expect(state.backupState, isNull);
    expect(await db.select(db.syncConflicts).get(), isEmpty);
    await db.close();
    final after = sqlite3_pkg.sqlite3.open(file.path);
    for (final t in tables) {
      expect(dump(after, t), before[t], reason: t);
    }
    after.close();

    // Trigger ghi nhận vẫn hoạt động sau migration.
    final again = AppDatabase.forTesting(NativeDatabase(file));
    final n = await SyncOutboxStore(again).count();
    await (again.update(again.transactionRows)..where((t) => t.id.equals('tx-1')))
        .write(const TransactionRowsCompanion(note: Value('sửa')));
    expect(await SyncOutboxStore(again).count(), n + 1);
    expect((await again.customSelect('PRAGMA integrity_check').getSingle()).data.values.first, 'ok');
    await again.close();
  });
}
