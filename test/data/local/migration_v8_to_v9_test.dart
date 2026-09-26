import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3_pkg;
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/seed_defaults.dart';

/// Schema v8 → v9: thêm cột nullable `actor_member_id`; dòng cũ giữ nguyên từng
/// trường và có actor = null; ID giao dịch không đổi; wallet không đổi.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vnm_migration_v9_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  TransactionRowsCompanion tx(
    String id,
    String type,
    String category,
    int amount, {
    String source = 'memberAvailable',
    String? sourceRef = 'vo',
    String destination = 'external',
    String? destinationRef,
  }) => TransactionRowsCompanion.insert(
    id: id,
    type: type,
    categoryId: category,
    sourceKind: source,
    sourceRefId: Value(sourceRef),
    destinationKind: destination,
    destinationRefId: Value(destinationRef),
    amountMinor: amount,
    transactionDate: DateTime(2026, 9, 5, 8, 30),
    createdAt: DateTime(2026, 9, 5, 8, 31),
    clientTxId: 'client-$id',
  );

  test('v8 → v9: giữ nguyên mọi dòng cũ, actor = null, id/ví không đổi', () async {
    final file = File('${dir.path}/v8.sqlite');
    final seed = AppDatabase.forTesting(NativeDatabase(file), seed: SeedProfile.demo);
    final t = seed.into(seed.transactionRows);
    await t.insert(tx('inc', 'income', 'thu_nhap', 900000,
        source: 'external', sourceRef: null, destination: 'memberAvailable', destinationRef: 'vo'));
    await t.insert(tx('fund-in', 'transfer', 'nap_quy', 300000,
        destination: 'fund', destinationRef: 'an_uong'));
    await t.insert(tx('fund-out', 'expense', 'sinh_hoat', 100000,
        source: 'fund', sourceRef: 'an_uong'));
    final walletBefore = (await seed.select(seed.walletMeta).getSingle()).walletId;
    await seed.close();

    final raw = sqlite3_pkg.sqlite3.open(file.path);
    raw.execute('ALTER TABLE transaction_rows DROP COLUMN actor_member_id');
    raw.execute('PRAGMA user_version = 8;');
    final before = [
      for (final r in raw.select('SELECT * FROM transaction_rows ORDER BY id')) Map<String, Object?>.of(r),
    ];
    expect(before.first.containsKey('actor_member_id'), isFalse);
    raw.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    expect((await db.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version'), 9);
    final after = await db.customSelect('SELECT * FROM transaction_rows ORDER BY id').get();
    expect(after, hasLength(before.length));
    for (var i = 0; i < before.length; i++) {
      final row = Map<String, Object?>.of(after[i].data);
      expect(row.remove('actor_member_id'), isNull);
      expect(row, before[i]);
    }
    expect((await db.select(db.walletMeta).getSingle()).walletId, walletBefore);
    expect((await db.customSelect('PRAGMA integrity_check').getSingle()).data.values.single, 'ok');
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    await db.close();
  });
}
