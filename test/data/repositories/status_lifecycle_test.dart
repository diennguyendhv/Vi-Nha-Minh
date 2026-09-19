import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/repositories/local_category_repository.dart';
import 'package:vi_nha_minh/data/repositories/local_status_repository.dart';
import 'package:vi_nha_minh/data/repositories/local_transaction_repository.dart';
import 'package:vi_nha_minh/domain/engine/financial_engine.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/status.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart' as domain;
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/usecases/compute_three_totals.dart';

/// F30 trên DB thật (Drift in-memory, không widget): MASTER DATA CHANGE !=
/// LEDGER CHANGE. Ẩn / sử dụng lại / đổi tên 1 bước trạng thái không sinh
/// giao dịch, không đổi `statusId` của giao dịch cũ, không đổi tài chính.
void main() {
  late AppDatabase db;
  late LocalCategoryRepository categories;
  late LocalStatusRepository statuses;
  late LocalTransactionRepository transactions;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    categories = LocalCategoryRepository(db);
    statuses = LocalStatusRepository(db);
    transactions = LocalTransactionRepository(db);
  });

  tearDown(() async => db.close());

  domain.Transaction tx({
    required String id,
    required TransactionType type,
    required String categoryId,
    required PoolKind source,
    String? sourceRef,
    required PoolKind destination,
    String? destinationRef,
    required int amount,
    String? statusId,
  }) => domain.Transaction(
    id: id,
    type: type,
    categoryId: categoryId,
    sourceKind: source,
    sourceRefId: sourceRef,
    destinationKind: destination,
    destinationRefId: destinationRef,
    amountMinor: amount,
    statusId: statusId,
    transactionDate: DateTime(2026, 9, 1),
    createdAt: DateTime(2026, 9, 1),
    clientTxId: 'client-$id',
  );

  Future<void> seedLedger() async {
    await transactions.addTransaction(
      tx(
        id: 'open',
        type: TransactionType.income,
        categoryId: 'thu_nhap',
        source: PoolKind.external,
        destination: PoolKind.memberAvailable,
        destinationRef: 'vo',
        amount: 1000000,
      ),
    );
    await transactions.addTransaction(
      tx(
        id: 'gift',
        type: TransactionType.expense,
        categoryId: 'cho_di',
        source: PoolKind.memberAvailable,
        sourceRef: 'vo',
        destination: PoolKind.external,
        amount: 250000,
        statusId: 'cho_di_da_chuan_bi',
      ),
    );
  }

  Future<({int rows, Map<PoolRef, int> balances, int income, int expense})> snapshot() async {
    final all = await transactions.watchTransactions().first;
    final cats = await categories.watchCategories().first;
    final totals = computeThreeTotals(all, cats);
    return (
      rows: (await db.select(db.transactionRows).get()).length,
      balances: computeAllPoolBalances(all),
      income: totals.totalIncome,
      expense: totals.totalExpense,
    );
  }

  Future<String?> giftStatusId() async =>
      (await (db.select(db.transactionRows)..where((r) => r.id.equals('gift'))).getSingle()).statusId;

  test('Ẩn 1 bước đang được giao dịch dùng: chỉ isActive=false, giao dịch + tài chính không đổi', () async {
    await seedLedger();
    final before = await snapshot();

    await statuses.softDeleteStatus('cho_di_da_chuan_bi');

    final cats = await categories.watchCategories().first;
    final choDi = cats.firstWhere((c) => c.id == 'cho_di');
    expect(choDi.statuses.map((s) => s.id), contains('cho_di_da_chuan_bi'), reason: 'không xoá cứng');
    expect(choDi.statusById('cho_di_da_chuan_bi')?.isActive, isFalse);
    expect(choDi.activeStatuses.map((s) => s.id), isNot(contains('cho_di_da_chuan_bi')));
    expect(choDi.statusById(await giftStatusId())?.name, 'ĐCB', reason: 'lịch sử vẫn resolve tên');

    final after = await snapshot();
    expect(after.rows, before.rows, reason: 'không sinh giao dịch nào');
    expect(after.balances, before.balances);
    expect(after.income, before.income);
    expect(after.expense, before.expense);
    expect(await giftStatusId(), 'cho_di_da_chuan_bi', reason: 'statusId của giao dịch cũ giữ nguyên');
  });

  test('Đổi tên bước: giao dịch cũ giữ statusId và thấy tên mới; không rewrite ledger', () async {
    await seedLedger();
    final before = await snapshot();

    await statuses.renameStatus('cho_di_da_chuan_bi', 'Đã soạn xong');

    final choDi = (await categories.watchCategories().first).firstWhere((c) => c.id == 'cho_di');
    expect(await giftStatusId(), 'cho_di_da_chuan_bi');
    expect(choDi.statusById(await giftStatusId())?.name, 'Đã soạn xong');

    final after = await snapshot();
    expect(after.rows, before.rows);
    expect(after.balances, before.balances);
    expect(after.expense, before.expense);
  });

  test('Sử dụng lại: bước ẩn quay lại danh sách đang dùng, cùng id', () async {
    await statuses.softDeleteStatus('cho_di_da_gui');
    var choDi = (await categories.watchCategories().first).firstWhere((c) => c.id == 'cho_di');
    expect(choDi.activeStatuses.map((s) => s.id), isNot(contains('cho_di_da_gui')));

    await statuses.reactivateStatus('cho_di_da_gui');

    choDi = (await categories.watchCategories().first).firstWhere((c) => c.id == 'cho_di');
    expect(choDi.activeStatuses.map((s) => s.id), contains('cho_di_da_gui'));
    expect(choDi.statuses.where((s) => s.id == 'cho_di_da_gui'), hasLength(1), reason: 'không tạo bản trùng');
  });

  test('Ẩn rồi ẩn lại / sử dụng lại nhiều lần vẫn idempotent, 0 giao dịch mới', () async {
    await seedLedger();
    final before = await snapshot();

    await statuses.softDeleteStatus('cho_di_chua_chuan_bi');
    await statuses.softDeleteStatus('cho_di_chua_chuan_bi');
    await statuses.reactivateStatus('cho_di_chua_chuan_bi');
    await statuses.reactivateStatus('cho_di_chua_chuan_bi');

    final after = await snapshot();
    expect(after.rows, before.rows);
    expect(after.balances, before.balances);
  });

  test('Vòng đời đầy đủ + KHỞI ĐỘNG LẠI: tạo → dùng → đổi tên → ngừng → sử dụng lại; cùng id, không thêm status nào, tài chính không đổi', () async {
    await seedLedger();
    final statusRowsBefore = (await db.select(db.statusRows).get()).length;
    final before = await snapshot();

    // tạo 1 bước mới rồi gán cho giao dịch mới
    await statuses.addStatus(const Status(id: 'st-new', categoryId: 'cho_di', name: 'Chờ xác nhận', sortOrder: 3));
    await transactions.addTransaction(
      tx(
        id: 'gift2',
        type: TransactionType.expense,
        categoryId: 'cho_di',
        source: PoolKind.memberAvailable,
        sourceRef: 'vo',
        destination: PoolKind.external,
        amount: 50000,
        statusId: 'st-new',
      ),
    );
    await statuses.renameStatus('st-new', 'Đã chuyển');
    await statuses.softDeleteStatus('st-new');

    // "Khởi động lại": repository mới trên cùng DB
    final categories2 = LocalCategoryRepository(db);
    var choDi = (await categories2.watchCategories().first).firstWhere((c) => c.id == 'cho_di');
    expect(choDi.statusById('st-new')?.name, 'Đã chuyển', reason: 'đổi tên bền, cùng id');
    expect(choDi.statusById('st-new')?.isActive, isFalse, reason: 'ngừng sử dụng bền');
    expect(choDi.activeStatuses.map((s) => s.id), isNot(contains('st-new')), reason: 'không còn trong selector mới');
    final gift2 = await (db.select(db.transactionRows)..where((r) => r.id.equals('gift2'))).getSingle();
    expect(gift2.statusId, 'st-new', reason: 'giao dịch lịch sử vẫn trỏ id cũ');
    expect(choDi.statusById(gift2.statusId)?.name, 'Đã chuyển', reason: 'lịch sử resolve tên mới của bước đã ngừng');

    await LocalStatusRepository(db).reactivateStatus('st-new');
    choDi = (await LocalCategoryRepository(db).watchCategories().first).firstWhere((c) => c.id == 'cho_di');
    expect(choDi.activeStatuses.map((s) => s.id), contains('st-new'));

    final statusRowsAfter = (await db.select(db.statusRows).get()).length;
    expect(statusRowsAfter, statusRowsBefore + 1, reason: 'chỉ đúng 1 bước được tạo, mọi thao tác sau đó không sinh thêm id');

    final after = await snapshot();
    // Chỉ khác `before` đúng bởi giao dịch gift2 (50k) đã ghi có chủ đích.
    expect(after.rows, before.rows + 1);
    expect(after.expense, before.expense + 50000);
  });
}
