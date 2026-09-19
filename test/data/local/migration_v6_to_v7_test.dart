import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3_pkg;
import 'package:vi_nha_minh/data/local/app_database.dart';

/// Schema v6 → v7 chỉ `ADD COLUMN category_rows.group_key` (nullable). Test
/// dựng DB đúng shape v6 bằng cách tạo DB hiện tại, nhét dữ liệu đại diện
/// (có chuỗi reversal, giao dịch tham chiếu category), rồi BỎ cột mới và hạ
/// `user_version` về 6 — phần còn lại của v6 giữ nguyên vì v7 không đổi gì
/// khác. Mở lại bằng `AppDatabase` để chạy nâng cấp thật.
void main() {
  Future<CategoryRowsCompanion> cat(
    String id,
    String type, {
    bool exclude = false,
  }) async => CategoryRowsCompanion.insert(
    id: id,
    name: id,
    colorValue: 255,
    type: type,
    excludeFromTotals: Value(exclude),
  );

  TransactionRowsCompanion tx(
    String id,
    String type,
    String category,
    int amount, {
    String source = 'memberAvailable',
    String? sourceRef = 'vo',
    String destination = 'external',
    String? destinationRef,
    String? reversalOf,
    String? reversedBy,
  }) => TransactionRowsCompanion.insert(
    id: id,
    type: type,
    categoryId: category,
    sourceKind: source,
    sourceRefId: Value(sourceRef),
    destinationKind: destination,
    destinationRefId: Value(destinationRef),
    amountMinor: amount,
    transactionDate: DateTime(2026, 9, 5),
    createdAt: DateTime(2026, 9, 5),
    clientTxId: 'client-$id',
    reversalOfTxId: Value(reversalOf),
    reversedByTxId: Value(reversedBy),
  );

  test('migrate v6 → v7: thêm cột group_key = NULL, giữ nguyên MỌI dòng dữ liệu', () async {
    final dir = Directory.systemTemp.createTempSync('vnm_migration_v7_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/v6.sqlite');

    // 1) Dữ liệu đại diện (schema hiện tại).
    final seed = AppDatabase.forTesting(NativeDatabase(file));
    await seed.into(seed.categoryRows).insert(await cat('m_open', 'income', exclude: true));
    await seed.into(seed.categoryRows).insert(await cat('m_rev', 'income'));
    await seed.into(seed.categoryRows).insert(await cat('m_spend', 'expense'));
    await seed.into(seed.categoryRows).insert(await cat('m_kd', 'expense'));
    await seed.into(seed.transactionRows).insert(
      tx('t-open', 'income', 'm_open', 10000000,
          source: 'external', sourceRef: null, destination: 'memberAvailable', destinationRef: 'vo'),
    );
    await seed.into(seed.transactionRows).insert(tx('t-a', 'expense', 'm_kd', 700000));
    await seed.into(seed.transactionRows).insert(
      tx('t-b', 'expense', 'm_spend', 300000, reversedBy: 't-b-rev'),
    );
    await seed.into(seed.transactionRows).insert(
      tx('t-b-rev', 'income', 'm_spend', 300000,
          source: 'external', sourceRef: null, destination: 'memberAvailable', destinationRef: 'vo',
          reversalOf: 't-b'),
    );
    final before = await seed.select(seed.transactionRows).get();
    final beforeCats = await seed.select(seed.categoryRows).get();
    expect(before, hasLength(4));
    await seed.close();

    // 2) Hạ về shape v6: bỏ cột mới + user_version = 6.
    final raw = sqlite3_pkg.sqlite3.open(file.path);
    raw.execute('ALTER TABLE category_rows DROP COLUMN group_key');
    raw.execute('PRAGMA user_version = 6;');
    raw.close();

    // 3) Mở lại → onUpgrade v6 → v7.
    final migrated = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(migrated.close);

    final after = await migrated.select(migrated.transactionRows).get();
    expect(after, hasLength(before.length), reason: 'số giao dịch giữ nguyên');
    for (final b in before) {
      final a = after.firstWhere((t) => t.id == b.id);
      expect(a.amountMinor, b.amountMinor);
      expect(a.categoryId, b.categoryId, reason: 'tham chiếu category giữ nguyên');
      expect(a.reversalOfTxId, b.reversalOfTxId);
      expect(a.reversedByTxId, b.reversedByTxId);
      expect(a.clientTxId, b.clientTxId);
      expect(a.type, b.type);
      expect(a.sourceKind, b.sourceKind);
      expect(a.destinationKind, b.destinationKind);
    }

    final cats = await migrated.select(migrated.categoryRows).get();
    expect(cats.map((c) => c.id).toSet(), beforeCats.map((c) => c.id).toSet());
    expect(cats.every((c) => c.groupKey == null), isTrue,
        reason: 'mọi category cũ (kể cả Chi) mặc định NULL = Chi tiêu, không đoán theo tên');
    expect(cats.firstWhere((c) => c.id == 'm_open').excludeFromTotals, isTrue);
    expect(cats.length, greaterThanOrEqualTo(4));

    // 4) Cột mới ghi/đọc được và KHÔNG đụng giao dịch.
    await (migrated.update(migrated.categoryRows)..where((c) => c.id.equals('m_kd')))
        .write(const CategoryRowsCompanion(groupKey: Value('business_expense')));
    final updated = await (migrated.select(migrated.categoryRows)
          ..where((c) => c.id.equals('m_kd')))
        .getSingle();
    expect(updated.groupKey, 'business_expense');
    expect(await migrated.select(migrated.transactionRows).get(), hasLength(before.length));
  });
}
