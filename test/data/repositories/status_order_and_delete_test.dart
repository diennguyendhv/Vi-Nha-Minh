import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/seed_defaults.dart';
import 'package:vi_nha_minh/data/repositories/local_category_repository.dart';
import 'package:vi_nha_minh/data/repositories/local_status_repository.dart';
import 'package:vi_nha_minh/data/repositories/local_transaction_repository.dart';
import 'package:vi_nha_minh/domain/engine/financial_engine.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/status.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart' as domain;
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/errors/domain_exceptions.dart';

/// Xóa trạng thái (gỡ tham chiếu nguyên tử) + thứ tự tuỳ chỉnh (DB Drift thật): xoá trạng thái chưa dùng, xoá trạng
/// thái đang dùng (gỡ tham chiếu nguyên tử), thứ tự tuỳ chỉnh theo từng danh mục.
void main() {
  late AppDatabase db;
  late LocalCategoryRepository categories;
  late LocalStatusRepository statuses;
  late LocalTransactionRepository transactions;

  Future<void> open(AppDatabase database) async {
    db = database;
    categories = LocalCategoryRepository(db);
    statuses = LocalStatusRepository(db);
    transactions = LocalTransactionRepository(db);
  }

  setUp(() async {
    await open(AppDatabase.forTesting(NativeDatabase.memory(), seed: SeedProfile.fresh));
    await categories.addCategory(
      Category(id: 'cat1', name: 'Cat 1', color: Colors.teal, type: TransactionType.expense, isDefault: false),
    );
    await categories.addCategory(
      Category(id: 'cat2', name: 'Cat 2', color: Colors.teal, type: TransactionType.expense, isDefault: false),
    );
    await categories.addCategory(
      Category(id: 'thu', name: 'Thu', color: Colors.teal, type: TransactionType.income, isDefault: false),
    );
    // Cat1: A B C (theo thứ tự tạo). Cat2 có bước CÙNG TÊN "A".
    await statuses.addStatus(const Status(id: 'a1', categoryId: 'cat1', name: 'A', sortOrder: 0));
    await statuses.addStatus(const Status(id: 'b1', categoryId: 'cat1', name: 'B', sortOrder: 1));
    await statuses.addStatus(const Status(id: 'c1', categoryId: 'cat1', name: 'C', sortOrder: 2));
    await statuses.addStatus(const Status(id: 'a2', categoryId: 'cat2', name: 'A', sortOrder: 0));
    await transactions.addTransaction(
      domain.Transaction(
        id: 'open',
        type: TransactionType.income,
        categoryId: 'thu',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 1000000,
        transactionDate: DateTime(2026, 9, 1),
        createdAt: DateTime(2026, 9, 1),
        clientTxId: 'client-open',
      ),
    );
  });

  tearDown(() async => db.close());

  domain.Transaction spend(String id, String categoryId, String? statusId, {int amount = 1000, int day = 2}) =>
      domain.Transaction(
        id: id,
        type: TransactionType.expense,
        categoryId: categoryId,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: amount,
        statusId: statusId,
        note: 'ghi chú $id',
        transactionDate: DateTime(2026, 9, day),
        createdAt: DateTime(2026, 9, day),
        clientTxId: 'client-$id',
      );

  Future<List<String>> orderIds(String categoryId) async =>
      [for (final s in await statuses.watchStatuses(categoryId).first) s.id];
  Future<List<int>> sortOrders(String categoryId) async =>
      [for (final s in await statuses.watchStatuses(categoryId).first) s.sortOrder];
  Future<bool> statusExists(String id) async =>
      (await (db.select(db.statusRows)..where((r) => r.id.equals(id))).get()).isNotEmpty;
  Future<Map<String, Map<String, Object?>>> txSnapshot() async {
    final rows = await db.customSelect('SELECT * FROM transaction_rows').get();
    return {for (final r in rows) r.read<String>('id'): Map.of(r.data)};
  }

  Future<Map<PoolRef, int>> balances() async =>
      computeAllPoolBalances(await transactions.watchTransactions().first);

  test('A — bước KHÔNG ai dùng → xoá hẳn: dòng biến mất; thứ tự còn lại liền mạch 0,1', () async {
    await statuses.deleteStatusPermanently('b1');
    expect(await statusExists('b1'), isFalse);
    expect(await orderIds('cat1'), ['a1', 'c1']);
    expect(await sortOrders('cat1'), [0, 1]);
  });

  test('B/D/E — bước đang dùng bởi nhiều giao dịch: trả về đúng số dòng, MỌI dòng về NULL, bước biến mất, giao dịch còn nguyên', () async {
    await transactions.addTransaction(spend('t1', 'cat1', 'a1', day: 2));
    await transactions.addTransaction(spend('t2', 'cat1', 'a1', day: 3));
    await transactions.addTransaction(spend('t3', 'cat1', 'a1', day: 4));
    await transactions.addTransaction(spend('t4', 'cat1', 'b1', day: 5));

    final cleared = await statuses.clearAndDeleteStatus('a1');

    expect(cleared, 3);
    expect(await statusExists('a1'), isFalse);
    final now = await txSnapshot();
    expect(now.length, 5, reason: 'không giao dịch nào bị xoá');
    for (final id in ['t1', 't2', 't3']) {
      expect(now[id]!['status_id'], isNull, reason: id);
    }
    expect(now['t4']!['status_id'], 'b1', reason: 'giao dịch dùng bước khác không bị đụng');
  });

  test('F/13 — chỉ status_id đổi: mọi cột khác + số dư y hệt trước/sau', () async {
    await transactions.addTransaction(spend('t1', 'cat1', 'a1', amount: 12345));
    await transactions.addTransaction(spend('t2', 'cat1', 'a1', amount: 6789, day: 9));
    final before = await txSnapshot();
    final balBefore = await balances();

    await statuses.clearAndDeleteStatus('a1');

    final after = await txSnapshot();
    expect(after.keys, before.keys);
    for (final id in before.keys) {
      final b = Map.of(before[id]!)..remove('status_id');
      final a = Map.of(after[id]!)..remove('status_id');
      expect(a, b, reason: 'giao dịch $id chỉ được đổi status_id');
    }
    expect(await balances(), balBefore, reason: 'trạng thái không có ảnh hưởng tài chính');
  });

  test('G — lỗi giữa chừng → HOÀN TÁC toàn bộ: bước còn, tham chiếu còn, thứ tự còn', () async {
    await transactions.addTransaction(spend('t1', 'cat1', 'a1'));
    await transactions.addTransaction(spend('t2', 'cat1', 'a1', day: 3));
    // Trigger ép DELETE trên đúng bước này thất bại SAU khi UPDATE đã chạy.
    await db.customStatement(
      "CREATE TRIGGER boom BEFORE DELETE ON status_rows WHEN old.id = 'a1' "
      "BEGIN SELECT RAISE(ABORT, 'boom'); END",
    );
    final before = await txSnapshot();

    await expectLater(statuses.clearAndDeleteStatus('a1'), throwsA(anything));

    expect(await statusExists('a1'), isTrue);
    expect(await txSnapshot(), before, reason: 'không dòng nào bị đổi status_id');
    expect(await orderIds('cat1'), ['a1', 'b1', 'c1']);
  });

  test('H — bước CÙNG TÊN ở danh mục khác không bị ảnh hưởng', () async {
    await transactions.addTransaction(spend('t1', 'cat1', 'a1'));
    await transactions.addTransaction(spend('t2', 'cat2', 'a2', day: 3));

    await statuses.clearAndDeleteStatus('a1');

    expect(await statusExists('a2'), isTrue);
    expect((await txSnapshot())['t2']!['status_id'], 'a2');
    expect(await orderIds('cat2'), ['a2']);
  });

  test('deleteStatusPermanently vẫn chặn khi còn giao dịch dùng (phải qua clearAndDelete)', () async {
    await transactions.addTransaction(spend('t1', 'cat1', 'a1'));
    await expectLater(
      statuses.deleteStatusPermanently('a1'),
      throwsA(isA<StatusNotDeletableException>()),
    );
    expect(await statusExists('a1'), isTrue);
  });

  test('xoá bước giữa dãy A,B,C,D → chuẩn hoá liền mạch A,C,D = 0,1,2', () async {
    await statuses.addStatus(const Status(id: 'd1', categoryId: 'cat1', name: 'D', sortOrder: 3));
    await transactions.addTransaction(spend('t1', 'cat1', 'b1'));

    await statuses.clearAndDeleteStatus('b1');

    expect(await orderIds('cat1'), ['a1', 'c1', 'd1']);
    expect(await sortOrders('cat1'), [0, 1, 2]);
  });

  test('J — kéo A,B,C → C,A,B: thứ tự lưu bền; L — Category.statuses/activeStatuses theo đúng thứ tự (picker)', () async {
    await statuses.reorderStatuses('cat1', ['c1', 'a1', 'b1']);

    expect(await orderIds('cat1'), ['c1', 'a1', 'b1']);
    final cat1 = (await categories.watchCategories().first).firstWhere((c) => c.id == 'cat1');
    expect([for (final s in cat1.statuses) s.id], ['c1', 'a1', 'b1']);
    expect([for (final s in cat1.activeStatuses) s.name], ['C', 'A', 'B'], reason: 'KHÔNG sắp xếp lại theo bảng chữ cái');
    // Danh mục khác có thứ tự độc lập.
    final cat2 = (await categories.watchCategories().first).firstWhere((c) => c.id == 'cat2');
    expect([for (final s in cat2.statuses) s.id], ['a2']);
  });

  test('M — bước ngừng sử dụng: giữ thứ tự khi quản lý, bị loại khỏi picker giao dịch mới', () async {
    await statuses.reorderStatuses('cat1', ['c1', 'a1', 'b1']);
    await statuses.softDeleteStatus('a1');

    final cat1 = (await categories.watchCategories().first).firstWhere((c) => c.id == 'cat1');
    expect([for (final s in cat1.statuses) s.id], ['c1', 'a1', 'b1'], reason: 'quản lý: vẫn giữ chỗ');
    expect([for (final s in cat1.activeStatuses) s.id], ['c1', 'b1'], reason: 'picker: bỏ bước ngừng');
  });

  test('tie-break xác định: cùng sortOrder → theo id', () async {
    await db.customStatement("UPDATE status_rows SET sort_order = 0 WHERE category_id = 'cat1'");
    expect(await orderIds('cat1'), ['a1', 'b1', 'c1']);
    final cat1 = (await categories.watchCategories().first).firstWhere((c) => c.id == 'cat1');
    expect([for (final s in cat1.statuses) s.id], ['a1', 'b1', 'c1']);
  });

  test('K — đóng/mở lại DB trên đĩa: thứ tự C,A,B vẫn còn', () async {
    final dir = Directory.systemTemp.createTempSync('status_order_');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final file = File('${dir.path}/t.sqlite');
    await db.close();
    await open(AppDatabase.forTesting(NativeDatabase(file), seed: SeedProfile.fresh));
    await categories.addCategory(
      Category(id: 'catk', name: 'K', color: Colors.teal, type: TransactionType.expense, isDefault: false),
    );
    await statuses.addStatus(const Status(id: 'ka', categoryId: 'catk', name: 'A', sortOrder: 0));
    await statuses.addStatus(const Status(id: 'kb', categoryId: 'catk', name: 'B', sortOrder: 1));
    await statuses.addStatus(const Status(id: 'kc', categoryId: 'catk', name: 'C', sortOrder: 2));
    await statuses.reorderStatuses('catk', ['kc', 'ka', 'kb']);
    await db.close();

    await open(AppDatabase.forTesting(NativeDatabase(file), seed: SeedProfile.fresh));
    expect(await orderIds('catk'), ['kc', 'ka', 'kb']);
  });
}
