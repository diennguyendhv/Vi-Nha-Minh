import 'package:drift/native.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/entities/field_update.dart';
import 'package:vi_nha_minh/core/constants/default_savings_asset_types.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/repositories/local_category_repository.dart';
import 'package:vi_nha_minh/data/repositories/local_status_repository.dart';
import 'package:vi_nha_minh/data/repositories/local_transaction_repository.dart';
import 'package:vi_nha_minh/domain/engine/financial_engine.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/savings_asset_type.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/status.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart' as domain;
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/entities/transfer_kind.dart';
import 'package:vi_nha_minh/domain/errors/domain_exceptions.dart';

import '../../support/legacy_correction.dart';

/// "Sửa giao dịch" = THAY dòng cũ bằng dòng mới trong 1 DB transaction (không
/// tạo hoàn tác / bản thay thế), rollback nếu không hợp lệ; chặn nếu làm pool âm
/// và chỉ ra giao dịch đang cản; dọn lịch sử ẩn (dữ liệu cũ) giải phóng danh mục.
void main() {
  late AppDatabase db;
  late LocalTransactionRepository repo;
  late LocalCategoryRepository cats;
  var seq = 0;
  const vo = 'vo';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LocalTransactionRepository(db);
    cats = LocalCategoryRepository(db);
    seq = 0;
  });

  tearDown(() async => db.close());

  domain.Transaction tx({
    required String id,
    required TransactionType type,
    TransferKind? kind,
    String category = 'sinh_hoat',
    String? statusId,
    required PoolKind from,
    String? fromRef,
    required PoolKind to,
    String? toRef,
    required int amount,
    int day = 1,
  }) {
    seq++;
    return domain.Transaction(
      id: id,
      type: type,
      transferKind: kind,
      categoryId: category,
      statusId: statusId,
      sourceKind: from,
      sourceRefId: fromRef,
      destinationKind: to,
      destinationRefId: toRef,
      amountMinor: amount,
      transactionDate: DateTime(2026, 9, day),
      createdAt: DateTime(2026, 9, day),
      clientTxId: 'c-$seq',
    );
  }

  domain.Transaction income(String id, int amount, {int day = 1}) => tx(
    id: id,
    type: TransactionType.income,
    category: 'thu_nhap',
    from: PoolKind.external,
    to: PoolKind.memberAvailable,
    toRef: vo,
    amount: amount,
    day: day,
  );

  domain.Transaction expense(String id, int amount, {String category = 'sinh_hoat', String? statusId, int day = 2}) => tx(
    id: id,
    type: TransactionType.expense,
    category: category,
    statusId: statusId,
    from: PoolKind.memberAvailable,
    fromRef: vo,
    to: PoolKind.external,
    amount: amount,
    day: day,
  );

  Future<List<domain.Transaction>> all() => repo.watchTransactions().first;

  Future<int> avail() async =>
      poolBalance(computeAllPoolBalances(await all()), PoolKind.memberAvailable, vo);

  Future<void> addCategoryWithStatuses() async {
    await cats.addCategory(
      Category(
        id: 'zz_edit',
        name: 'ZZ Edit',
        color: const Color(0xFF00AA00),
        type: TransactionType.expense,
        isDefault: false,
      ),
    );
    final st = LocalStatusRepository(db);
    await st.addStatus(const Status(id: 'zz_todo', categoryId: 'zz_edit', name: 'Chưa xử lý', sortOrder: 0));
    await st.addStatus(const Status(id: 'zz_done', categoryId: 'zz_edit', name: 'Đã xử lý', sortOrder: 1));
  }

  group('Sửa = thay dòng cũ bằng dòng mới (atomic)', () {
    test('A — sửa số tiền: dòng cũ mất, dòng mới tồn tại, số dư đúng, không hoàn tác/lịch sử ẩn', () async {
      await repo.addTransaction(income('i1', 1000000));
      await repo.addTransaction(expense('e1', 100000));

      await repo.updateTransaction('e1', amountMinor: 250000);

      final list = await all();
      expect(list.any((t) => t.id == 'e1'), isFalse);
      expect(list.length, 2);
      expect(list.every((t) => t.reversalOfTxId == null && t.reversedByTxId == null && t.correctsTxId == null), isTrue);
      expect(await avail(), 750000);
    });

    test('B/C — đổi danh mục kèm trạng thái mới hợp lệ: chỉ còn tham chiếu MỚI trong DB', () async {
      await addCategoryWithStatuses();
      await repo.addTransaction(income('i1', 1000000));
      await repo.addTransaction(expense('e1', 10000, category: 'cho_di', statusId: 'cho_di_da_gui'));

      await repo.updateTransaction('e1', categoryId: 'zz_edit', status: const FieldUpdate.set('zz_todo'), amountMinor: 20000);

      final list = await all();
      final moved = list.firstWhere((t) => t.type == TransactionType.expense);
      expect(moved.categoryId, 'zz_edit');
      expect(moved.statusId, 'zz_todo');
      expect(list.any((t) => t.categoryId == 'cho_di'), isFalse);
      expect(list.any((t) => t.statusId == 'cho_di_da_gui'), isFalse);
    });

    test('C2 — trạng thái thuộc danh mục KHÁC danh mục đích bị từ chối, dòng cũ nguyên vẹn (rollback)', () async {
      await addCategoryWithStatuses();
      await repo.addTransaction(income('i1', 1000000));
      await repo.addTransaction(expense('e1', 10000));

      await expectLater(
        repo.updateTransaction('e1', categoryId: 'zz_edit', status: const FieldUpdate.set('cho_di_da_gui'), amountMinor: 20000),
        throwsA(isA<InvalidStatusForCategoryException>()),
      );

      final list = await all();
      expect(list.length, 2);
      expect(list.firstWhere((t) => t.id == 'e1').amountMinor, 10000);
      expect(list.firstWhere((t) => t.id == 'e1').categoryId, 'sinh_hoat');
    });

    test('E — sửa làm pool âm → CHẶN, dòng cũ y nguyên, chỉ ra giao dịch đang cản', () async {
      await repo.addTransaction(income('i1', 1000000, day: 1));
      await repo.addTransaction(expense('e1', 800000, day: 3));

      await expectLater(
        repo.updateTransaction('i1', amountMinor: 100000),
        throwsA(
          isA<ChangeWouldOverdrawException>().having(
            (e) => e.blockingTransactionIds,
            'giao dịch cản',
            ['e1'],
          ),
        ),
      );

      final list = await all();
      expect(list.length, 2);
      expect(list.firstWhere((t) => t.id == 'i1').amountMinor, 1000000);
      expect(await avail(), 200000);
    });

    test('G — bấm Lưu liên tiếp nhiều lần: đúng 1 giao dịch mới (các lần sau báo không còn tồn tại, không nhân đôi)', () async {
      await repo.addTransaction(income('i1', 1000000));
      await repo.addTransaction(expense('e1', 100000));

      final results = await Future.wait([
        for (var i = 0; i < 4; i++)
          repo.updateTransaction('e1', amountMinor: 300000).then((_) => 'ok').catchError((_) => 'err'),
      ]);

      expect(results.where((r) => r == 'ok').length, 1);
      final list = await all();
      expect(list.where((t) => t.type == TransactionType.expense).length, 1);
      expect(await avail(), 700000);
    });

    test('H — mở lại DB (đọc lại từ đầu): chỉ còn dòng mới', () async {
      await repo.addTransaction(income('i1', 1000000));
      await repo.addTransaction(expense('e1', 100000));
      await repo.updateTransaction('e1', amountMinor: 150000);

      final reopened = LocalTransactionRepository(db);
      final list = await reopened.watchTransactions().first;
      expect(list.map((t) => t.amountMinor).toList()..sort(), [150000, 1000000]);
    });

    test('Chỉ đổi ghi chú/ngày/trạng thái: không hoàn tác, không tạo lịch sử ẩn', () async {
      await repo.addTransaction(income('i1', 1000000));
      await repo.addTransaction(expense('e1', 100000));

      await repo.updateTransaction('e1', note: 'mới', transactionDate: DateTime(2026, 9, 5));

      final list = await all();
      expect(list.length, 2);
      expect(list.firstWhere((t) => t.id == 'e1').note, 'mới');
      expect(list.every((t) => t.reversalOfTxId == null && t.correctsTxId == null), isTrue);
    });

    test('Sửa họ giao dịch KIỂU CŨ (gốc → hoàn tác → thay thế): cả họ được thay bằng 1 dòng mới, không nửa chuỗi', () async {
      await repo.addTransaction(income('i1', 1000000));
      await repo.addTransaction(expense('e1', 100000));
      final head = await legacyCorrect(repo, 'e1', amount: 200000);
      expect((await all()).length, 4);

      await repo.updateTransaction(head.id, amountMinor: 300000);

      final list = await all();
      expect(list.length, 2, reason: 'khoản thu + 1 dòng mới');
      expect(list.every((t) => t.reversalOfTxId == null && t.reversedByTxId == null && t.correctsTxId == null), isTrue);
      expect(await avail(), 700000);
    });

    test('Vay / Cho vay: không thay dòng (chặn, không ghi gì)', () async {
      await repo.addTransaction(income('i1', 1000000));
      await repo.addTransaction(
        domain.Transaction(
          id: 'loan1',
          type: TransactionType.income,
          categoryId: 'vay_no',
          sourceKind: PoolKind.external,
          destinationKind: PoolKind.memberAvailable,
          destinationRefId: vo,
          amountMinor: 500000,
          settlementGroupId: 'grp1',
          transactionDate: DateTime(2026, 9, 1),
          createdAt: DateTime(2026, 9, 1),
          clientTxId: 'loan-c',
        ),
      );

      await expectLater(
        repo.updateTransaction('loan1', amountMinor: 400000),
        throwsA(isA<TransactionDeleteBlockedException>()),
      );
      expect((await all()).firstWhere((t) => t.id == 'loan1').amountMinor, 500000);
    });
  });

  group('Xóa: chỉ ra giao dịch đang cản', () {
    test('Xóa khoản thu đã được dùng → DeleteWouldOverdraw kèm id giao dịch dùng sau (mới nhất trước)', () async {
      await repo.addTransaction(income('i1', 1000000, day: 1));
      await repo.addTransaction(expense('e1', 300000, day: 3));
      await repo.addTransaction(expense('e2', 400000, day: 5));

      await expectLater(
        repo.deleteTransaction('i1'),
        throwsA(
          isA<DeleteWouldOverdrawException>().having(
            (e) => e.blockingTransactionIds,
            'cản',
            ['e2', 'e1'],
          ),
        ),
      );
      expect((await all()).length, 3);
    });
  });

  group('Dọn lịch sử ẩn cũ giải phóng danh mục/trạng thái', () {
    test('Họ đã sửa kiểu cũ + đã đổi danh mục: dọn giữ lại dòng hiệu lực, bỏ correctsTxId treo, số dư không đổi, danh mục cũ xóa hẳn được', () async {
      await repo.addTransaction(income('i1', 1000000));
      await repo.addTransaction(expense('e1', 100000, category: 'sinh_hoat'));
      await cats.addCategory(
        Category(
          id: 'old_cat',
          name: 'Cũ',
          color: const Color(0xFF111111),
          type: TransactionType.expense,
          isDefault: false,
        ),
      );
      // Họ cũ: gốc thuộc "Cũ" → hoàn tác → thay thế đã sang Sinh hoạt.
      await db.customStatement("UPDATE transaction_rows SET category_id = 'old_cat' WHERE id = 'e1'");
      final head = await legacyCorrect(repo, 'e1', amount: 100000, categoryId: 'sinh_hoat');
      await cats.softDeleteCategory('old_cat');
      final balanceBefore = await avail();

      expect(await cats.watchDeletableCategoryIds().first, isNot(contains('old_cat')), reason: 'lịch sử ẩn còn giữ');

      final removed = await repo.purgeDeletedHistory('old_cat');

      expect(removed, 2, reason: 'gốc + hoàn tác');
      final list = await all();
      final survivor = list.firstWhere((t) => t.id == head.id);
      expect(survivor.correctsTxId, isNull, reason: 'không tham chiếu treo');
      expect(await avail(), balanceBefore);
      expect(await cats.watchDeletableCategoryIds().first, contains('old_cat'));
      await cats.deleteCategoryPermanently('old_cat');
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    });

    test('Trạng thái: giao dịch mới nhất đổi danh mục → xóa hẳn trạng thái cũ được ngay sau khi hết tham chiếu', () async {
      await addCategoryWithStatuses();
      await repo.addTransaction(income('i1', 1000000));
      await repo.addTransaction(expense('e1', 10000, category: 'zz_edit', statusId: 'zz_todo'));

      await repo.updateTransaction('e1', categoryId: 'sinh_hoat');

      final list = await all();
      expect(list.any((t) => t.statusId == 'zz_todo'), isFalse);
      expect(list.any((t) => t.categoryId == 'zz_edit'), isFalse);
    });
  });

  test('Savings: xóa lần nạp đã phân bổ bị chặn và chỉ ra giao dịch phân bổ', () async {
    const unalloc = SystemSavingsAssets.unallocatedId;
    const gold = DefaultSavingsAssetTypes.goldId;
    await repo.addTransaction(income('i1', 5000000));
    await repo.addTransaction(
      tx(
        id: 't1',
        type: TransactionType.transfer,
        kind: TransferKind.savingsTopup,
        category: 'tiet_kiem',
        from: PoolKind.memberAvailable,
        fromRef: vo,
        to: PoolKind.memberSavingsAsset,
        toRef: savingsAssetRefId(unalloc, vo),
        amount: 1000000,
        day: 2,
      ),
    );
    await repo.addTransaction(
      tx(
        id: 'a1',
        type: TransactionType.transfer,
        kind: TransferKind.savingsConvert,
        category: 'tiet_kiem',
        from: PoolKind.memberSavingsAsset,
        fromRef: savingsAssetRefId(unalloc, vo),
        to: PoolKind.memberSavingsAsset,
        toRef: savingsAssetRefId(gold, vo),
        amount: 600000,
        day: 3,
      ),
    );

    await expectLater(
      repo.deleteTransaction('t1'),
      throwsA(
        isA<DeleteWouldOverdrawException>().having((e) => e.blockingTransactionIds, 'cản', ['a1']),
      ),
    );
    // Xóa phân bổ trước → xóa lần nạp được.
    await repo.deleteTransaction('a1');
    await repo.deleteTransaction('t1');
    expect((await all()).map((t) => t.id), ['i1']);
  });
}
