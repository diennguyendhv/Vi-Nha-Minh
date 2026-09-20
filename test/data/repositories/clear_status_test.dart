import 'package:drift/native.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/repositories/local_category_repository.dart';
import 'package:vi_nha_minh/data/repositories/local_status_repository.dart';
import 'package:vi_nha_minh/data/repositories/local_transaction_repository.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/field_update.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/status.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart' as domain;
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/errors/domain_exceptions.dart';
import 'package:vi_nha_minh/domain/usecases/explore_transactions.dart';

/// Trạng thái là TÙY CHỌN: sửa giao dịch phải phân biệt KHÔNG ĐỔI / ĐẶT / XÓA
/// (`FieldUpdate`), không dùng `null` cho cả hai. Repository thật (Drift in-memory).
void main() {
  late AppDatabase db;
  late LocalTransactionRepository repo;
  late List<Category> categories;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LocalTransactionRepository(db);
    final cats = LocalCategoryRepository(db);
    final st = LocalStatusRepository(db);
    for (final id in ['a', 'b']) {
      await cats.addCategory(Category(
        id: 'cat_$id',
        name: 'Cat $id',
        color: const Color(0xFF00AA00),
        type: TransactionType.expense,
        isDefault: false,
      ));
      await st.addStatus(Status(id: 'st_${id}_1', categoryId: 'cat_$id', name: '${id}1', sortOrder: 0));
      await st.addStatus(Status(id: 'st_${id}_2', categoryId: 'cat_$id', name: '${id}2', sortOrder: 1));
    }
    categories = await cats.watchCategories().first;
    await repo.addTransaction(domain.Transaction(
      id: 'inc',
      type: TransactionType.income,
      categoryId: 'thu_nhap',
      sourceKind: PoolKind.external,
      destinationKind: PoolKind.memberAvailable,
      destinationRefId: 'vo',
      amountMinor: 1000000,
      transactionDate: DateTime(2026, 9, 1),
      createdAt: DateTime(2026, 9, 1),
      clientTxId: 'c-inc',
    ));
  });

  tearDown(() async => db.close());

  Future<void> addExpense({String category = 'cat_a', String? statusId}) =>
      repo.addTransaction(domain.Transaction(
        id: 'e1',
        type: TransactionType.expense,
        categoryId: category,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: 10000,
        note: 'ghi chú',
        statusId: statusId,
        transactionDate: DateTime(2026, 9, 2),
        createdAt: DateTime(2026, 9, 2),
        clientTxId: 'c-e1',
      ));

  // Sửa số tiền THAY dòng (id mới) nên tìm theo loại, không theo id.
  Future<domain.Transaction> e1() async => (await repo.watchTransactions().first)
      .firstWhere((t) => t.type == TransactionType.expense);

  test('A — có trạng thái X, sửa ghi chú → X được giữ (status không truyền)', () async {
    await addExpense(statusId: 'st_a_1');
    await repo.updateTransaction('e1', note: 'mới');
    expect((await e1()).statusId, 'st_a_1');
    expect((await e1()).note, 'mới');
  });

  test('B — có trạng thái X, chọn "Không có trạng thái" (clear) → status_id = NULL', () async {
    await addExpense(statusId: 'st_a_1');
    await repo.updateTransaction('e1', status: const FieldUpdate.clear());
    expect((await e1()).statusId, isNull);
  });

  test('B2 — clear kèm đổi số tiền (đường thay dòng) → vẫn NULL, số tiền mới', () async {
    await addExpense(statusId: 'st_a_1');
    await repo.updateTransaction('e1', amountMinor: 20000, status: const FieldUpdate.clear());
    expect((await e1()).statusId, isNull);
    expect((await e1()).amountMinor, 20000);
  });

  test('C — trạng thái null, sửa trường khác → vẫn null; clear trên null cũng là no-op', () async {
    await addExpense();
    await repo.updateTransaction('e1', note: 'x');
    expect((await e1()).statusId, isNull);
    await repo.updateTransaction('e1', status: const FieldUpdate.clear());
    expect((await e1()).statusId, isNull);
    expect((await e1()).statusUpdatedAt, isNull, reason: 'clear trên giá trị đã trống không đụng thời điểm cập nhật');
  });

  test('D — trạng thái null, chọn X → lưu X', () async {
    await addExpense();
    await repo.updateTransaction('e1', status: const FieldUpdate.set('st_a_2'));
    expect((await e1()).statusId, 'st_a_2');
  });

  test('E/F — Category A + Status X → đổi sang Category B (không truyền status) → status tự về null (không tự chọn bước đầu của B)', () async {
    await addExpense(statusId: 'st_a_1');
    await repo.updateTransaction('e1', categoryId: 'cat_b');
    expect((await e1()).categoryId, 'cat_b');
    expect((await e1()).statusId, isNull);
  });

  test('G — cặp danh mục/trạng thái không hợp lệ bị từ chối, giao dịch nguyên vẹn', () async {
    await addExpense(statusId: 'st_a_1');
    await expectLater(
      repo.updateTransaction('e1', status: const FieldUpdate.set('st_b_1')),
      throwsA(isA<InvalidStatusForCategoryException>()),
    );
    await expectLater(
      repo.updateTransaction('e1', categoryId: 'cat_b', status: const FieldUpdate.set('st_a_1')),
      throwsA(isA<InvalidStatusForCategoryException>()),
    );
    expect((await e1()).statusId, 'st_a_1');
    expect((await e1()).categoryId, 'cat_a');
  });

  test('Đổi danh mục + đặt bước của danh mục mới trong cùng lần lưu → hợp lệ', () async {
    await addExpense(statusId: 'st_a_1');
    await repo.updateTransaction('e1', categoryId: 'cat_b', status: const FieldUpdate.set('st_b_2'));
    expect((await e1()).statusId, 'st_b_2');
  });

  test('H — Tổng hợp "Không có trạng thái" tìm thấy giao dịch sau khi xóa trạng thái', () async {
    await addExpense(statusId: 'st_a_1');
    final noStatus = const TransactionFilter(includeNoStatus: true);
    List<String> ids(List<domain.Transaction> l) =>
        exploreTransactions(l, categories, noStatus).rows.map((t) => t.type.name).toList();

    expect(ids(await repo.watchTransactions().first), isNot(contains('expense')));
    await repo.updateTransaction('e1', status: const FieldUpdate.clear());
    expect(ids(await repo.watchTransactions().first), contains('expense'));
  });
}
