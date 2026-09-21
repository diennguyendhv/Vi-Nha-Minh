import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/constants/default_categories.dart';
import 'package:vi_nha_minh/core/constants/default_savings_asset_types.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/repositories/local_transaction_repository.dart';
import 'package:vi_nha_minh/domain/engine/financial_engine.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart' as domain;
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/entities/transfer_kind.dart';
import 'package:vi_nha_minh/domain/errors/domain_exceptions.dart';
import 'package:vi_nha_minh/domain/usecases/compute_three_totals.dart';

/// F11 (Pixel 7a acceptance, 2026-09-19): bộ `SavingsAssetType` mặc định là
/// Gửi ngân hàng / Vàng / Chứng khoán / Khác — tiền mặt và tiền tài khoản
/// ngân hàng dùng hằng ngày là tiền khả dụng, KHÔNG phải loại tiết kiệm.
///
/// Test qua `LocalTransactionRepository` thật trên DB in-memory thật (đã
/// seed bằng `seedDefaults`), không mock. Chỉ kiểm tra hành vi Savings với
/// bộ seed mới — không test lại logic Engine thuần (đã có ở
/// `test/domain/financial_engine_test.dart`).
void main() {
  late AppDatabase db;
  late LocalTransactionRepository repo;
  var seq = 0;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LocalTransactionRepository(db);
    seq = 0;
  });

  tearDown(() async {
    await db.close();
  });

  String bankRef(String m) => savingsAssetRefId(DefaultSavingsAssetTypes.bankId, m);
  String goldRef(String m) => savingsAssetRefId(DefaultSavingsAssetTypes.goldId, m);

  domain.Transaction tx({
    required TransactionType type,
    TransferKind? transferKind,
    required String categoryId,
    required PoolKind sourceKind,
    String? sourceRefId,
    required PoolKind destinationKind,
    String? destinationRefId,
    required int amountMinor,
  }) {
    final n = seq++;
    final now = DateTime(2026, 9, 1);
    return domain.Transaction(
      id: 'tx-$n',
      type: type,
      transferKind: transferKind,
      categoryId: categoryId,
      sourceKind: sourceKind,
      sourceRefId: sourceRefId,
      destinationKind: destinationKind,
      destinationRefId: destinationRefId,
      amountMinor: amountMinor,
      transactionDate: now,
      createdAt: now,
      clientTxId: 'client-$n',
    );
  }

  Future<void> openingAvailable(int amount) async {
    await repo.addTransaction(
      tx(
        type: TransactionType.income,
        categoryId: DefaultCategories.soDuBanDau.id,
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: amount,
      ),
    );
  }

  Future<void> topup(String destRef, int amount) async {
    await repo.addTransaction(
      tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.savingsTopup,
        categoryId: DefaultCategories.tietKiem.id,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.memberSavingsAsset,
        destinationRefId: destRef,
        amountMinor: amount,
      ),
    );
  }

  Future<List<domain.Transaction>> allTx() => repo.watchTransactions().first;

  /// Mọi pool cộng lại = Total Assets. Transfer tự cân bằng nội bộ nên phần
  /// cộng thêm này KHÔNG được đổi sau bất kỳ lệnh Savings nào.
  Future<int> totalAssets() async {
    final balances = computeAllPoolBalances(await allTx());
    return balances.values.fold<int>(0, (s, v) => s + v);
  }

  Future<({int income, int expense})> incomeExpense() async {
    final totals = computeThreeTotals(await allTx(), DefaultCategories.all);
    return (income: totals.totalIncome, expense: totals.totalExpense);
  }

  Future<int> balance(PoolKind kind, String refId) async =>
      poolBalance(computeAllPoolBalances(await allTx()), kind, refId);

  group('Seed mặc định — F11', () {
    test('DB mới seed đúng 4 loại: Gửi ngân hàng / Vàng / Chứng khoán / Khác, không còn Tiền mặt/Ngân hàng', () async {
      final rows = await db.select(db.savingsAssetTypeRows).get();
      expect(
        rows.map((r) => r.name).toSet(),
        {'Gửi ngân hàng', 'Vàng', 'Chứng khoán', 'Khác'},
      );
      expect(rows, hasLength(4), reason: 'không tạo bản trùng');
      expect(rows.map((r) => r.id).toSet(), {
        DefaultSavingsAssetTypes.bankId,
        DefaultSavingsAssetTypes.goldId,
        DefaultSavingsAssetTypes.stocksId,
        DefaultSavingsAssetTypes.otherId,
      });
      expect(rows.every((r) => r.isActive), isTrue);
    });

    test('ID cũ savings_bank được giữ ổn định (chỉ đổi tên hiển thị) để tương thích dữ liệu đã có', () {
      expect(DefaultSavingsAssetTypes.bankId, 'savings_bank');
      expect(DefaultSavingsAssetTypes.bank.name, 'Gửi ngân hàng');
    });
  });

  group('Luồng Savings với bộ seed mới — Total Assets bất biến, không tạo Thu/Chi', () {
    test('1 — Available → Gửi ngân hàng', () async {
      await openingAvailable(10000000);
      final totalBefore = await totalAssets();
      final ieBefore = await incomeExpense();

      await topup(bankRef('vo'), 4000000);

      expect(await balance(PoolKind.memberAvailable, 'vo'), 6000000);
      expect(await balance(PoolKind.memberSavingsAsset, bankRef('vo')), 4000000);
      expect(await totalAssets(), totalBefore);
      final ieAfter = await incomeExpense();
      expect(ieAfter.income, ieBefore.income);
      expect(ieAfter.expense, ieBefore.expense);
    });

    test('2 — Available → Vàng', () async {
      await openingAvailable(10000000);
      final totalBefore = await totalAssets();
      final ieBefore = await incomeExpense();

      await topup(goldRef('vo'), 3000000);

      expect(await balance(PoolKind.memberAvailable, 'vo'), 7000000);
      expect(await balance(PoolKind.memberSavingsAsset, goldRef('vo')), 3000000);
      expect(await totalAssets(), totalBefore);
      final ieAfter = await incomeExpense();
      expect(ieAfter.income, ieBefore.income);
      expect(ieAfter.expense, ieBefore.expense);
    });

    test('3 — Gửi ngân hàng → Vàng (SAVINGS_CONVERT): tổng Savings, Available, Total Assets không đổi', () async {
      await openingAvailable(10000000);
      await topup(bankRef('vo'), 4000000);
      final totalBefore = await totalAssets();
      final availableBefore = await balance(PoolKind.memberAvailable, 'vo');
      final ieBefore = await incomeExpense();

      await repo.addTransaction(
        tx(
          type: TransactionType.transfer,
          transferKind: TransferKind.savingsConvert,
          categoryId: DefaultCategories.tietKiem.id,
          sourceKind: PoolKind.memberSavingsAsset,
          sourceRefId: bankRef('vo'),
          destinationKind: PoolKind.memberSavingsAsset,
          destinationRefId: goldRef('vo'),
          amountMinor: 1500000,
        ),
      );

      final bank = await balance(PoolKind.memberSavingsAsset, bankRef('vo'));
      final gold = await balance(PoolKind.memberSavingsAsset, goldRef('vo'));
      expect(bank, 2500000);
      expect(gold, 1500000);
      expect(bank + gold, 4000000, reason: 'tổng Savings không đổi');
      expect(await balance(PoolKind.memberAvailable, 'vo'), availableBefore);
      expect(await totalAssets(), totalBefore);
      final ieAfter = await incomeExpense();
      expect(ieAfter.income, ieBefore.income);
      expect(ieAfter.expense, ieBefore.expense);
    });

    test('4 — Vàng → Available (SAVINGS_WITHDRAW): Savings giảm, Available tăng, Total Assets không đổi', () async {
      await openingAvailable(10000000);
      await topup(goldRef('vo'), 3000000);
      final totalBefore = await totalAssets();
      final ieBefore = await incomeExpense();

      await repo.addTransaction(
        tx(
          type: TransactionType.transfer,
          transferKind: TransferKind.savingsWithdraw,
          categoryId: DefaultCategories.tietKiem.id,
          sourceKind: PoolKind.memberSavingsAsset,
          sourceRefId: goldRef('vo'),
          destinationKind: PoolKind.memberAvailable,
          destinationRefId: 'vo',
          amountMinor: 1200000,
        ),
      );

      expect(await balance(PoolKind.memberSavingsAsset, goldRef('vo')), 1800000);
      expect(await balance(PoolKind.memberAvailable, 'vo'), 8200000);
      expect(await totalAssets(), totalBefore);
      final ieAfter = await incomeExpense();
      expect(ieAfter.income, ieBefore.income);
      expect(ieAfter.expense, ieBefore.expense);
    });

    test('5 — rút/chuyển vượt số dư bị chặn (InsufficientBalanceException), không ghi gì', () async {
      await openingAvailable(10000000);
      await topup(bankRef('vo'), 500000);
      final countBefore = (await allTx()).length;

      // rút 700k khi Gửi ngân hàng chỉ còn 500k
      await expectLater(
        repo.addTransaction(
          tx(
            type: TransactionType.transfer,
            transferKind: TransferKind.savingsWithdraw,
            categoryId: DefaultCategories.tietKiem.id,
            sourceKind: PoolKind.memberSavingsAsset,
            sourceRefId: bankRef('vo'),
            destinationKind: PoolKind.memberAvailable,
            destinationRefId: 'vo',
            amountMinor: 700000,
          ),
        ),
        throwsA(isA<InsufficientBalanceException>()),
      );
      // chuyển đổi 700k Gửi ngân hàng → Vàng cũng phải bị chặn
      await expectLater(
        repo.addTransaction(
          tx(
            type: TransactionType.transfer,
            transferKind: TransferKind.savingsConvert,
            categoryId: DefaultCategories.tietKiem.id,
            sourceKind: PoolKind.memberSavingsAsset,
            sourceRefId: bankRef('vo'),
            destinationKind: PoolKind.memberSavingsAsset,
            destinationRefId: goldRef('vo'),
            amountMinor: 700000,
          ),
        ),
        throwsA(isA<InsufficientBalanceException>()),
      );

      expect((await allTx()).length, countBefore, reason: 'không ghi nửa giao dịch');
      expect(await balance(PoolKind.memberSavingsAsset, bankRef('vo')), 500000);
      expect(await balance(PoolKind.memberSavingsAsset, goldRef('vo')), 0);
    });

    test('6 — Vợ và Chồng có Savings riêng cho cùng 1 loại (Vàng)', () async {
      await openingAvailable(10000000);
      await repo.addTransaction(
        tx(
          type: TransactionType.income,
          categoryId: DefaultCategories.soDuBanDau.id,
          sourceKind: PoolKind.external,
          destinationKind: PoolKind.memberAvailable,
          destinationRefId: 'chong',
          amountMinor: 5000000,
        ),
      );
      await topup(goldRef('vo'), 2000000);
      await repo.addTransaction(
        tx(
          type: TransactionType.transfer,
          transferKind: TransferKind.savingsTopup,
          categoryId: DefaultCategories.tietKiem.id,
          sourceKind: PoolKind.memberAvailable,
          sourceRefId: 'chong',
          destinationKind: PoolKind.memberSavingsAsset,
          destinationRefId: goldRef('chong'),
          amountMinor: 3000000,
        ),
      );

      expect(await balance(PoolKind.memberSavingsAsset, goldRef('vo')), 2000000);
      expect(await balance(PoolKind.memberSavingsAsset, goldRef('chong')), 3000000);
    });
  });
}
