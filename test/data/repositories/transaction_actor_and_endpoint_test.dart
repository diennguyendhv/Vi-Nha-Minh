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

/// Schema v9 `actorMemberId` (Chi từ Quỹ) và sửa đầu nguồn/đích của Chuyển, trên
/// DB in-memory thật. Nhóm chính vẫn bất biến; id giao dịch giữ nguyên sau khi sửa.
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
    String? actor,
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
        actorMemberId: actor,
        clientTxId: 'c-$seq',
      ),
    );
  }

  Future<void> income(String member, int amount) => add(
    type: TransactionType.income,
    category: 'thu_nhap',
    from: PoolKind.external,
    to: PoolKind.memberAvailable,
    toRef: member,
    amount: amount,
  );

  Future<domain.Transaction> fundIn(String member, int amount) async {
    await income(member, amount);
    return add(
      type: TransactionType.transfer,
      kind: TransferKind.fundTopup,
      category: 'nap_quy',
      from: PoolKind.memberAvailable,
      fromRef: member,
      to: PoolKind.fund,
      toRef: fund,
      amount: amount,
    );
  }

  Future<domain.Transaction> fundSpend({String? actor, int amount = 120000}) => add(
    type: TransactionType.expense,
    category: 'sinh_hoat',
    from: PoolKind.fund,
    fromRef: fund,
    to: PoolKind.external,
    amount: amount,
    actor: actor,
  );

  Future<List<domain.Transaction>> ledger() => repo.watchTransactions().first;

  Set<String> ids(List<domain.Transaction> all, TransactionFilter f) =>
      exploreTransactions(all, categories, f).rows.map((t) => t.id).toSet();

  const expenses = {TransactionType.expense};

  test('Chi từ Quỹ lưu actor; Chi + Vợ + Quỹ + danh mục đều tìm ra đúng giao dịch, nguồn vẫn là Quỹ', () async {
    await fundIn('vo', 500000);
    final spend = await fundSpend(actor: 'vo');
    final all = await ledger();
    final stored = all.singleWhere((t) => t.id == spend.id);
    expect((stored.actorMemberId, stored.sourceKind, stored.sourceRefId), ('vo', PoolKind.fund, fund));
    for (final f in [
      const TransactionFilter(types: expenses),
      const TransactionFilter(memberId: 'vo'),
      const TransactionFilter(fundIds: {fund}),
      const TransactionFilter(categoryIds: {'sinh_hoat'}),
      const TransactionFilter(
        types: expenses,
        memberId: 'vo',
        fundIds: {fund},
        categoryIds: {'sinh_hoat'},
      ),
    ]) {
      expect(ids(all, f), contains(spend.id));
    }
    expect(ids(all, const TransactionFilter(memberId: 'chong', types: expenses)), isEmpty);
    final result = exploreTransactions(
      all,
      categories,
      const TransactionFilter(memberId: 'vo', types: expenses),
    );
    expect(result.outflow, 120000);
    expect(computeGroupedTotals(all, categories, from: day, to: day).spending, 120000);
  });

  test('Chi từ ví suy người chi từ nguồn; dòng Quỹ cũ actor=null hợp lệ; đặt actor giữ nguyên id', () async {
    await income('chong', 500000);
    final own = await add(
      type: TransactionType.expense,
      category: 'sinh_hoat',
      from: PoolKind.memberAvailable,
      fromRef: 'chong',
      to: PoolKind.external,
      amount: 10000,
    );
    expect(own.actorMemberId, isNull);
    expect(expenseSpender(own), 'chong');

    await fundIn('vo', 300000);
    final old = await fundSpend();
    expect(expenseSpender(old), isNull);
    expect(ids(await ledger(), const TransactionFilter(memberId: 'vo', types: expenses)), isEmpty);

    await repo.updateTransaction(old.id, memberRefId: 'vo');
    final after = await ledger();
    expect(after.where((t) => t.id == old.id), hasLength(1));
    expect(after.singleWhere((t) => t.id == old.id).actorMemberId, 'vo');
    expect(ids(after, const TransactionFilter(memberId: 'vo', types: expenses)), {old.id});
    await expectLater(
      repo.updateTransaction(old.id, memberRefId: 'nobody'),
      throwsA(isA<UnknownEndpointException>()),
    );
  });

  test('Chuyển giữa thành viên: đổi người gửi/nhận, giữ nguyên id; nguồn=đích hoặc người lạ bị từ chối', () async {
    await income('vo', 500000);
    await income('chong', 500000);
    final x = await add(
      type: TransactionType.transfer,
      kind: TransferKind.memberToMember,
      category: 'chuyen_tien_thanh_vien',
      from: PoolKind.memberAvailable,
      fromRef: 'vo',
      to: PoolKind.memberAvailable,
      toRef: 'chong',
      amount: 100000,
    );
    await repo.updateTransaction(x.id, sourceRefId: 'chong', destinationRefId: 'vo');
    var t = (await ledger()).singleWhere((e) => e.id == x.id);
    expect((t.sourceRefId, t.destinationRefId, t.type), ('chong', 'vo', TransactionType.transfer));
    await expectLater(
      repo.updateTransaction(x.id, destinationRefId: 'chong'),
      throwsA(isA<SameSourceDestinationException>()),
    );
    await expectLater(
      repo.updateTransaction(x.id, destinationRefId: 'nobody'),
      throwsA(isA<UnknownEndpointException>()),
    );
    t = (await ledger()).singleWhere((e) => e.id == x.id);
    expect((t.sourceRefId, t.destinationRefId), ('chong', 'vo'));
  });

  test('Nạp quỹ: đổi người nạp / quỹ; quỹ không tồn tại hoặc id thành viên ở đầu Quỹ bị từ chối', () async {
    await income('vo', 500000);
    await income('chong', 500000);
    await db.into(db.fundRows).insert(
      FundRowsCompanion.insert(id: 'fund2', name: 'Quỹ 2', colorValue: 1),
    );
    final x = await add(
      type: TransactionType.transfer,
      kind: TransferKind.fundTopup,
      category: 'nap_quy',
      from: PoolKind.memberAvailable,
      fromRef: 'vo',
      to: PoolKind.fund,
      toRef: fund,
      amount: 100000,
    );
    await repo.updateTransaction(x.id, sourceRefId: 'chong', destinationRefId: 'fund2');
    final t = (await ledger()).singleWhere((e) => e.id == x.id);
    expect((t.sourceRefId, t.destinationRefId, t.destinationKind), ('chong', 'fund2', PoolKind.fund));
    await expectLater(
      repo.updateTransaction(x.id, destinationRefId: 'no-such-fund'),
      throwsA(isA<UnknownEndpointException>()),
    );
    await expectLater(
      repo.updateTransaction(x.id, destinationRefId: 'vo'),
      throwsA(isA<UnknownEndpointException>()),
    );
  });

  test('Tiết kiệm: đổi loại / thành viên hợp lệ; lệch thành viên và chuyển loại trùng bị từ chối', () async {
    await income('vo', 800000);
    await income('chong', 800000);
    final topup = await add(
      type: TransactionType.transfer,
      kind: TransferKind.savingsTopup,
      category: 'tiet_kiem',
      from: PoolKind.memberAvailable,
      fromRef: 'vo',
      to: PoolKind.memberSavingsAsset,
      toRef: savingsAssetRefId(bank, 'vo'),
      amount: 300000,
    );
    await repo.updateTransaction(topup.id, destinationRefId: savingsAssetRefId(gold, 'vo'));
    var t = (await ledger()).singleWhere((e) => e.id == topup.id);
    expect(t.destinationRefId, savingsAssetRefId(gold, 'vo'));

    await repo.updateTransaction(
      topup.id,
      sourceRefId: 'chong',
      destinationRefId: savingsAssetRefId(gold, 'chong'),
    );
    t = (await ledger()).singleWhere((e) => e.id == topup.id);
    expect((t.sourceRefId, t.destinationRefId), ('chong', savingsAssetRefId(gold, 'chong')));

    await expectLater(
      repo.updateTransaction(topup.id, destinationRefId: savingsAssetRefId(gold, 'vo')),
      throwsA(isA<SavingsMemberMismatchException>()),
    );

    final convert = await add(
      type: TransactionType.transfer,
      kind: TransferKind.savingsConvert,
      category: 'tiet_kiem',
      from: PoolKind.memberSavingsAsset,
      fromRef: savingsAssetRefId(gold, 'chong'),
      to: PoolKind.memberSavingsAsset,
      toRef: savingsAssetRefId(bank, 'chong'),
      amount: 50000,
    );
    await expectLater(
      repo.updateTransaction(convert.id, destinationRefId: savingsAssetRefId(gold, 'chong')),
      throwsA(isA<SameSourceDestinationException>()),
    );
  });

  test('sửa đầu làm pool âm bị từ chối; giao dịch không phải Chuyển không sửa được đầu; xóa vẫn hoạt động', () async {
    final topup = await fundIn('vo', 200000);
    await db.into(db.fundRows).insert(
      FundRowsCompanion.insert(id: 'fund2', name: 'Quỹ 2', colorValue: 1),
    );
    final spend = await fundSpend(actor: 'vo', amount: 150000);
    await expectLater(
      repo.updateTransaction(topup.id, destinationRefId: 'fund2'),
      throwsA(isA<ChangeWouldOverdrawException>()),
    );
    expect((await ledger()).singleWhere((t) => t.id == topup.id).destinationRefId, fund);
    await expectLater(
      repo.updateTransaction(spend.id, sourceRefId: 'fund2'),
      throwsA(isA<InvalidTransferEditException>()),
    );
    await repo.deleteTransaction(spend.id);
    expect((await ledger()).any((t) => t.id == spend.id), isFalse);
  });
}
