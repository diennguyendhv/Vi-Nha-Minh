import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/constants/default_categories.dart';
import 'package:vi_nha_minh/core/constants/default_funds.dart';
import 'package:vi_nha_minh/core/constants/default_savings_asset_types.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/repositories/local_transaction_repository.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart' as domain;
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/entities/transfer_kind.dart';
import 'package:vi_nha_minh/domain/errors/domain_exceptions.dart';
import 'package:vi_nha_minh/domain/usecases/compute_grouped_totals.dart';
import 'package:vi_nha_minh/domain/usecases/explore_transactions.dart';

/// Canonical transaction semantics on a real in-memory DB: every flow stays
/// visible to Summary's explorer, only Income/Expense feed Thu/Chi, one
/// Transaction.id is shared by every entry point, and the main group is fixed.
void main() {
  late AppDatabase db;
  late LocalTransactionRepository repo;
  var seq = 0;

  const fund = DefaultFunds.anUongId;
  const bank = DefaultSavingsAssetTypes.bankId;
  const gold = DefaultSavingsAssetTypes.goldId;
  final categories = DefaultCategories.all;
  final day = DateTime(2026, 9, 10);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LocalTransactionRepository(db);
    seq = 0;
  });
  tearDown(() async => db.close());

  Future<domain.Transaction> add({
    required TransactionType type,
    required String category,
    required PoolKind from,
    String? fromRef,
    required PoolKind to,
    String? toRef,
    required int amount,
    TransferKind? kind,
  }) {
    seq++;
    return repo.addTransaction(
      domain.Transaction(
        id: 'tx-$seq',
        type: type,
        transferKind: kind,
        categoryId: category,
        sourceKind: from,
        sourceRefId: fromRef,
        destinationKind: to,
        destinationRefId: toRef,
        amountMinor: amount,
        transactionDate: day,
        createdAt: day,
        clientTxId: 'c-$seq',
      ),
    );
  }

  Future<domain.Transaction> income(String member, int amount) => add(
    type: TransactionType.income,
    category: 'thu_nhap',
    from: PoolKind.external,
    to: PoolKind.memberAvailable,
    toRef: member,
    amount: amount,
  );

  Future<List<domain.Transaction>> ledger() => repo.watchTransactions().first;

  ExplorerResult explore(
    List<domain.Transaction> all, [
    TransactionFilter filter = const TransactionFilter(),
  ]) => exploreTransactions(all, categories, filter);

  GroupedTotals totals(List<domain.Transaction> all) =>
      computeGroupedTotals(all, categories, from: day, to: day);

  test('1 — Chồng → Quỹ: hiện trong Tổng hợp, lọc Quỹ khớp, không phồng Thu/Chi', () async {
    await income('chong', 1000000);
    final before = totals(await ledger());
    final topup = await add(
      type: TransactionType.transfer,
      kind: TransferKind.fundTopup,
      category: 'nap_quy',
      from: PoolKind.memberAvailable,
      fromRef: 'chong',
      to: PoolKind.fund,
      toRef: fund,
      amount: 300000,
    );
    final all = await ledger();
    expect(explore(all).rows.map((t) => t.id), contains(topup.id));
    expect(
      explore(all, const TransactionFilter(fundIds: {fund})).rows.map((t) => t.id),
      [topup.id],
    );
    final after = totals(all);
    expect(after.spending, before.spending);
    expect(after.revenue, before.revenue);
    expect(after.businessExpense, before.businessExpense);
    expect(explore(all).outflow, 0);
  });

  test('2 — Chi từ Quỹ: là Expense thường, hiện, lọc Quỹ khớp, đếm đúng 1 lần', () async {
    await income('chong', 1000000);
    final topup = await add(
      type: TransactionType.transfer,
      kind: TransferKind.fundTopup,
      category: 'nap_quy',
      from: PoolKind.memberAvailable,
      fromRef: 'chong',
      to: PoolKind.fund,
      toRef: fund,
      amount: 300000,
    );
    final spend = await add(
      type: TransactionType.expense,
      category: 'sinh_hoat',
      from: PoolKind.fund,
      fromRef: fund,
      to: PoolKind.external,
      amount: 120000,
    );
    final all = await ledger();
    expect(spend.categoryId, 'sinh_hoat');
    expect(explore(all).rows.map((t) => t.id), containsAll([topup.id, spend.id]));
    final byFund = explore(all, const TransactionFilter(fundIds: {fund}));
    expect(byFund.rows.map((t) => t.id).toSet(), {topup.id, spend.id});
    expect(byFund.outflow, 120000);
    expect(totals(all).spending, 120000);
    final onlyExpenses = explore(
      all,
      const TransactionFilter(types: {TransactionType.expense}, fundIds: {fund}),
    );
    expect(onlyExpenses.rows.map((t) => t.id), [spend.id]);
  });

  test('3 — Vợ → Chồng và Chồng → Vợ: hiện, không phồng Thu/Chi', () async {
    await income('vo', 500000);
    await income('chong', 500000);
    final before = totals(await ledger());
    final a = await add(
      type: TransactionType.transfer,
      kind: TransferKind.memberToMember,
      category: 'chuyen_tien_thanh_vien',
      from: PoolKind.memberAvailable,
      fromRef: 'vo',
      to: PoolKind.memberAvailable,
      toRef: 'chong',
      amount: 100000,
    );
    final b = await add(
      type: TransactionType.transfer,
      kind: TransferKind.memberToMember,
      category: 'chuyen_tien_thanh_vien',
      from: PoolKind.memberAvailable,
      fromRef: 'chong',
      to: PoolKind.memberAvailable,
      toRef: 'vo',
      amount: 40000,
    );
    final all = await ledger();
    expect(explore(all).rows.map((t) => t.id), containsAll([a.id, b.id]));
    expect(
      explore(all, const TransactionFilter(memberId: 'vo')).rows.map((t) => t.id),
      containsAll([a.id, b.id]),
    );
    final after = totals(all);
    expect(after.spending, before.spending);
    expect(after.revenue, before.revenue);
    expect(after.cashFlow, before.cashFlow);
  });

  test('4 — Tiết kiệm: nạp / rút / chuyển loại đều hiện, không có Thu/Chi giả', () async {
    await income('vo', 1000000);
    final before = totals(await ledger());
    final topup = await add(
      type: TransactionType.transfer,
      kind: TransferKind.savingsTopup,
      category: 'tiet_kiem',
      from: PoolKind.memberAvailable,
      fromRef: 'vo',
      to: PoolKind.memberSavingsAsset,
      toRef: savingsAssetRefId(bank, 'vo'),
      amount: 400000,
    );
    final convert = await add(
      type: TransactionType.transfer,
      kind: TransferKind.savingsConvert,
      category: 'tiet_kiem',
      from: PoolKind.memberSavingsAsset,
      fromRef: savingsAssetRefId(bank, 'vo'),
      to: PoolKind.memberSavingsAsset,
      toRef: savingsAssetRefId(gold, 'vo'),
      amount: 100000,
    );
    final withdraw = await add(
      type: TransactionType.transfer,
      kind: TransferKind.savingsWithdraw,
      category: 'tiet_kiem',
      from: PoolKind.memberSavingsAsset,
      fromRef: savingsAssetRefId(gold, 'vo'),
      to: PoolKind.memberAvailable,
      toRef: 'vo',
      amount: 50000,
    );
    final all = await ledger();
    final savings = explore(
      all,
      const TransactionFilter(poolKinds: {PoolKind.memberSavingsAsset}),
    );
    expect(
      savings.rows.map((t) => t.id).toSet(),
      {topup.id, convert.id, withdraw.id},
    );
    expect(savings.inflow, 0);
    expect(savings.outflow, 0);
    final after = totals(all);
    expect(after.spending, before.spending);
    expect(after.revenue, before.revenue);
    expect(after.cashFlow, before.cashFlow);
  });

  test('5 — cùng Transaction.id ở mọi nơi (Tổng hợp / Quỹ / Tiết kiệm / lịch sử)', () async {
    await income('vo', 1000000);
    final topup = await add(
      type: TransactionType.transfer,
      kind: TransferKind.fundTopup,
      category: 'nap_quy',
      from: PoolKind.memberAvailable,
      fromRef: 'vo',
      to: PoolKind.fund,
      toRef: fund,
      amount: 200000,
    );
    final all = await ledger();
    final ids = <String>{for (final t in all) t.id};
    final fromSummary = explore(all).rows.map((t) => t.id).toSet();
    final fromFund = explore(
      all,
      const TransactionFilter(fundIds: {fund}),
    ).rows.map((t) => t.id).toSet();
    expect(fromSummary, ids);
    expect(fromFund, {topup.id});
    expect(fromFund.difference(ids), isEmpty);
    expect(all.where((t) => t.id == topup.id), hasLength(1));
  });

  test('6 — sửa 1 giao dịch quỹ/tiết kiệm đi qua updateTransaction chuẩn, giữ nguyên nhóm chính', () async {
    await income('vo', 1000000);
    final topup = await add(
      type: TransactionType.transfer,
      kind: TransferKind.fundTopup,
      category: 'nap_quy',
      from: PoolKind.memberAvailable,
      fromRef: 'vo',
      to: PoolKind.fund,
      toRef: fund,
      amount: 200000,
    );
    final spend = await add(
      type: TransactionType.expense,
      category: 'sinh_hoat',
      from: PoolKind.fund,
      fromRef: fund,
      to: PoolKind.external,
      amount: 50000,
    );
    await repo.updateTransaction(topup.id, amountMinor: 300000, note: 'nạp thêm');
    await repo.updateTransaction(spend.id, amountMinor: 70000);
    final all = await ledger();
    final visible = all.where(isVisibleForTest).toList();
    final t = visible.singleWhere((x) => x.note == 'nạp thêm');
    expect(t.type, TransactionType.transfer);
    expect(t.amountMinor, 300000);
    expect(t.destinationKind, PoolKind.fund);
    final s = visible.singleWhere(
      (x) => x.type == TransactionType.expense && x.sourceKind == PoolKind.fund,
    );
    expect(s.amountMinor, 70000);
    expect(totals(all).spending, 70000);
  });

  test('7 — xóa đúng 1 giao dịch 1 lần, mọi góc nhìn cập nhật', () async {
    await income('vo', 1000000);
    final topup = await add(
      type: TransactionType.transfer,
      kind: TransferKind.fundTopup,
      category: 'nap_quy',
      from: PoolKind.memberAvailable,
      fromRef: 'vo',
      to: PoolKind.fund,
      toRef: fund,
      amount: 200000,
    );
    final spend = await add(
      type: TransactionType.expense,
      category: 'sinh_hoat',
      from: PoolKind.fund,
      fromRef: fund,
      to: PoolKind.external,
      amount: 50000,
    );
    await repo.deleteTransaction(spend.id);
    var all = await ledger();
    expect(all.map((t) => t.id), isNot(contains(spend.id)));
    expect(all.map((t) => t.id), contains(topup.id));
    expect(totals(all).spending, 0);
    expect(
      explore(all, const TransactionFilter(fundIds: {fund})).rows.map((t) => t.id),
      [topup.id],
    );
    await expectLater(
      repo.deleteTransaction(spend.id),
      throwsA(isA<TransactionNotFoundException>()),
    );
    all = await ledger();
    expect(all.map((t) => t.id), contains(topup.id));
  });

  test('9 — sửa Chuyển: số tiền/ngày/ghi chú được; memberRefId không đổi đầu nguồn/đích', () async {
    await income('vo', 1000000);
    final x = await add(
      type: TransactionType.transfer,
      kind: TransferKind.memberToMember,
      category: 'chuyen_tien_thanh_vien',
      from: PoolKind.memberAvailable,
      fromRef: 'vo',
      to: PoolKind.memberAvailable,
      toRef: 'chong',
      amount: 20000,
    );
    await repo.updateTransaction(x.id, amountMinor: 30000, note: 'sửa', memberRefId: 'chong');
    final t = (await ledger()).singleWhere((e) => e.note == 'sửa');
    expect(t.type, TransactionType.transfer);
    expect(t.amountMinor, 30000);
    expect((t.sourceRefId, t.destinationRefId), ('vo', 'chong'));
  });

  test('8 — nhóm chính bất biến: không đổi Thu/Chi/Chuyển qua danh mục khác nhóm', () async {
    final inc = await income('vo', 500000);
    final exp = await add(
      type: TransactionType.expense,
      category: 'sinh_hoat',
      from: PoolKind.memberAvailable,
      fromRef: 'vo',
      to: PoolKind.external,
      amount: 10000,
    );
    final xfer = await add(
      type: TransactionType.transfer,
      kind: TransferKind.memberToMember,
      category: 'chuyen_tien_thanh_vien',
      from: PoolKind.memberAvailable,
      fromRef: 'vo',
      to: PoolKind.memberAvailable,
      toRef: 'chong',
      amount: 20000,
    );
    Matcher blocked() => throwsA(isA<MainGroupChangeException>());
    await expectLater(repo.updateTransaction(inc.id, categoryId: 'sinh_hoat'), blocked());
    await expectLater(repo.updateTransaction(exp.id, categoryId: 'thu_nhap'), blocked());
    await expectLater(repo.updateTransaction(exp.id, categoryId: 'tiet_kiem'), blocked());
    await expectLater(repo.updateTransaction(xfer.id, categoryId: 'sinh_hoat'), blocked());
    // Cùng nhóm vẫn được phép.
    await repo.updateTransaction(exp.id, categoryId: 'tu_thuong');
    final all = await ledger();
    expect(all.singleWhere((t) => t.categoryId == 'tu_thuong').type, TransactionType.expense);
    expect(all.where((t) => t.id == inc.id).single.type, TransactionType.income);
  });
}

bool isVisibleForTest(domain.Transaction t) =>
    t.reversedByTxId == null && t.reversalOfTxId == null;
