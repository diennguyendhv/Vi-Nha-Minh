import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/engine/financial_engine.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/family_member.dart';
import 'package:vi_nha_minh/domain/entities/fund.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/savings_asset_type.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/entities/transfer_kind.dart';
import 'package:vi_nha_minh/domain/usecases/compute_financial_summary.dart';

/// Test cho Phase 8 — Dashboard/Financial Summary read model. Dùng chung
/// bộ builder transaction thuần Dart (không Drift/Flutter widget) đúng
/// nguyên tắc `docs/financial-core-v2.md`: mọi rollup phải rebuild lại
/// được 100% từ `Transaction` gốc (Invariant 10).
void main() {
  int seq = 0;

  Transaction tx({
    required TransactionType type,
    TransferKind? transferKind,
    String categoryId = 'test_cat',
    required PoolKind sourceKind,
    String? sourceRefId,
    required PoolKind destinationKind,
    String? destinationRefId,
    required int amountMinor,
    DateTime? transactionDate,
    DateTime? createdAt,
    String? statusId,
    String? reversalOfTxId,
    String? correctsTxId,
    String? reversedByTxId,
  }) {
    seq++;
    return Transaction(
      id: 'tx-$seq',
      type: type,
      transferKind: transferKind,
      categoryId: categoryId,
      sourceKind: sourceKind,
      sourceRefId: sourceRefId,
      destinationKind: destinationKind,
      destinationRefId: destinationRefId,
      amountMinor: amountMinor,
      statusId: statusId,
      transactionDate: transactionDate ?? DateTime(2026, 9, 1),
      createdAt: createdAt ?? DateTime(2026, 9, 1),
      reversalOfTxId: reversalOfTxId,
      correctsTxId: correctsTxId,
      reversedByTxId: reversedByTxId,
      clientTxId: 'client-$seq',
    );
  }

  const incomeCategory = Category(
    id: 'test_cat',
    name: 'Test',
    color: Color(0xFF000000),
    type: TransactionType.income,
  );
  const fundA = Fund(id: 'fund_a', name: 'Quỹ A', color: Color(0xFF111111));
  const fundB = Fund(id: 'fund_b', name: 'Quỹ B', color: Color(0xFF222222));
  const cashType = SavingsAssetType(id: 'cash', name: 'Tiền mặt', color: Color(0xFF333333));
  const bankType = SavingsAssetType(id: 'bank', name: 'Ngân hàng', color: Color(0xFF444444));

  FinancialSummary summarize(
    List<Transaction> txs, {
    List<Category> categories = const [],
    List<Fund> funds = const [],
    List<SavingsAssetType> assetTypes = const [],
    DateTime? month,
  }) {
    return computeFinancialSummary(
      txs,
      categories: categories,
      funds: funds,
      assetTypes: assetTypes,
      month: month,
    );
  }

  group('1/2 — Income/Expense đổi đúng available + Total Assets', () {
    test('Income vào member → available tăng, Total Assets tăng đúng amount', () {
      final t = tx(
        type: TransactionType.income,
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 1000000,
      );
      final s = summarize([t]);
      expect(s.availableByMember[FamilyMember.vo], 1000000);
      expect(s.totalAvailable, 1000000);
      expect(s.totalAssets, 1000000);
    });

    test('Expense từ member → available giảm, Total Assets giảm đúng amount', () {
      final income = tx(
        type: TransactionType.income,
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 1000000,
      );
      final expense = tx(
        type: TransactionType.expense,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: 300000,
      );
      final s = summarize([income, expense]);
      expect(s.availableByMember[FamilyMember.vo], 700000);
      expect(s.totalAssets, 700000);
    });
  });

  group('3/4/5/6/7/8/18 — Transfer nội bộ KHÔNG đổi Total Assets', () {
    int seedAndAssets(List<Transaction> transferTxs) {
      final seed = tx(
        type: TransactionType.income,
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 10000000,
      );
      final s = summarize([seed, ...transferTxs]);
      return s.totalAssets;
    }

    test('MEMBER_TO_MEMBER: A -amount, B +amount, Total Assets không đổi', () {
      final before = seedAndAssets([]);
      final transfer = tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.memberToMember,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'chong',
        amountMinor: 2000000,
      );
      final after = seedAndAssets([transfer]);
      expect(after, before);

      final s = summarize([
        tx(
          type: TransactionType.income,
          sourceKind: PoolKind.external,
          destinationKind: PoolKind.memberAvailable,
          destinationRefId: 'vo',
          amountMinor: 10000000,
        ),
        transfer,
      ]);
      expect(s.availableByMember[FamilyMember.vo], 8000000);
      expect(s.availableByMember[FamilyMember.chong], 2000000);
    });

    test('FUND_TOPUP: member -amount, fund +amount, Total Assets không đổi', () {
      final before = seedAndAssets([]);
      final topup = tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.fundTopup,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.fund,
        destinationRefId: fundA.id,
        amountMinor: 1500000,
      );
      final after = seedAndAssets([topup]);
      expect(after, before);
    });

    test('FUND_WITHDRAW: fund -amount, member +amount, Total Assets không đổi', () {
      final topup = tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.fundTopup,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.fund,
        destinationRefId: fundA.id,
        amountMinor: 1500000,
      );
      final before = seedAndAssets([topup]);
      final withdraw = tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.fundWithdraw,
        sourceKind: PoolKind.fund,
        sourceRefId: fundA.id,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'chong',
        amountMinor: 500000,
      );
      final after = seedAndAssets([topup, withdraw]);
      expect(after, before);
    });

    test('SAVINGS_TOPUP: member -amount, savings +amount, Total Assets không đổi', () {
      final before = seedAndAssets([]);
      final topup = tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.savingsTopup,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.memberSavingsAsset,
        destinationRefId: savingsAssetRefId(cashType.id, FamilyMember.vo),
        amountMinor: 1000000,
      );
      final after = seedAndAssets([topup]);
      expect(after, before);
    });

    test('SAVINGS_WITHDRAW: savings -amount, member +amount, Total Assets không đổi', () {
      final topup = tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.savingsTopup,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.memberSavingsAsset,
        destinationRefId: savingsAssetRefId(cashType.id, FamilyMember.vo),
        amountMinor: 1000000,
      );
      final before = seedAndAssets([topup]);
      final withdraw = tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.savingsWithdraw,
        sourceKind: PoolKind.memberSavingsAsset,
        sourceRefId: savingsAssetRefId(cashType.id, FamilyMember.vo),
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 400000,
      );
      final after = seedAndAssets([topup, withdraw]);
      expect(after, before);
    });

    test('SAVINGS_CONVERT: đổi loại tài sản, không đổi tổng tiết kiệm member lẫn Total Assets', () {
      final topup = tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.savingsTopup,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.memberSavingsAsset,
        destinationRefId: savingsAssetRefId(cashType.id, FamilyMember.vo),
        amountMinor: 1000000,
      );
      final beforeSummary = summarize(
        [
          tx(
            type: TransactionType.income,
            sourceKind: PoolKind.external,
            destinationKind: PoolKind.memberAvailable,
            destinationRefId: 'vo',
            amountMinor: 10000000,
          ),
          topup,
        ],
        assetTypes: [cashType, bankType],
      );
      final convert = tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.savingsConvert,
        sourceKind: PoolKind.memberSavingsAsset,
        sourceRefId: savingsAssetRefId(cashType.id, FamilyMember.vo),
        destinationKind: PoolKind.memberSavingsAsset,
        destinationRefId: savingsAssetRefId(bankType.id, FamilyMember.vo),
        amountMinor: 600000,
      );
      final afterSummary = summarize(
        [
          tx(
            type: TransactionType.income,
            sourceKind: PoolKind.external,
            destinationKind: PoolKind.memberAvailable,
            destinationRefId: 'vo',
            amountMinor: 10000000,
          ),
          topup,
          convert,
        ],
        assetTypes: [cashType, bankType],
      );

      expect(afterSummary.totalAssets, beforeSummary.totalAssets);
      expect(afterSummary.savingsByMember[FamilyMember.vo], beforeSummary.savingsByMember[FamilyMember.vo]);
      expect(afterSummary.savingsByMemberAndAssetType[FamilyMember.vo]![cashType.id], 400000);
      expect(afterSummary.savingsByMemberAndAssetType[FamilyMember.vo]![bankType.id], 600000);
    });
  });

  group('9 — Hai SavingsAssetType khác nhau được aggregate đúng', () {
    test('Cash + Bank của cùng 1 member cộng đúng vào savingsByMember/totalSavings', () {
      final cashTopup = tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.savingsTopup,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.memberSavingsAsset,
        destinationRefId: savingsAssetRefId(cashType.id, FamilyMember.vo),
        amountMinor: 1200000,
      );
      final bankTopup = tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.savingsTopup,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.memberSavingsAsset,
        destinationRefId: savingsAssetRefId(bankType.id, FamilyMember.vo),
        amountMinor: 8000000,
      );
      final s = summarize([cashTopup, bankTopup], assetTypes: [cashType, bankType]);

      expect(s.savingsByMemberAndAssetType[FamilyMember.vo]![cashType.id], 1200000);
      expect(s.savingsByMemberAndAssetType[FamilyMember.vo]![bankType.id], 8000000);
      expect(s.savingsByMember[FamilyMember.vo], 9200000);
      expect(s.totalSavings, 9200000);
    });
  });

  group('10 — Hai Funds khác nhau được aggregate riêng đúng', () {
    test('Fund A và Fund B giữ số dư riêng biệt, totalFunds = tổng cả 2', () {
      final topupA = tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.fundTopup,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.fund,
        destinationRefId: fundA.id,
        amountMinor: 2000000,
      );
      final topupB = tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.fundTopup,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'chong',
        destinationKind: PoolKind.fund,
        destinationRefId: fundB.id,
        amountMinor: 500000,
      );
      final s = summarize([topupA, topupB], funds: [fundA, fundB]);

      expect(s.fundBalances[fundA.id], 2000000);
      expect(s.fundBalances[fundB.id], 500000);
      expect(s.totalFunds, 2500000);
    });
  });

  group('11 — Reversal net-zero phản ánh đúng vào summary', () {
    test('Income + reversal của nó → available/Total Assets về lại như trước', () {
      final before = summarize([]);
      final income = tx(
        type: TransactionType.income,
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 1000000,
      );
      final reversal = buildReversal(
        income,
        newId: 'rev-1',
        clientTxId: 'client-rev-1',
        now: DateTime(2026, 9, 5),
      );
      final after = summarize([income, reversal]);

      expect(after.totalAssets, before.totalAssets);
      expect(after.availableByMember[FamilyMember.vo], 0);
    });
  });

  group('12 — Correction phản ánh đúng kết quả cuối vào summary', () {
    test('Expense 500k sửa thành 350k → summary cuối phản ánh đúng 350k, không phải 850k', () {
      final original = tx(
        type: TransactionType.expense,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: 500000,
      );
      final correction = buildCorrection(
        original,
        newAmountMinor: 350000,
        reversalId: 'rev-1',
        replacementId: 'replacement-1',
        clientTxId: 'client-correction-1',
        now: DateTime(2026, 9, 5),
      );
      final seed = tx(
        type: TransactionType.income,
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 1000000,
      );

      final s = summarize([seed, original, correction.reversal, correction.replacement]);
      expect(s.availableByMember[FamilyMember.vo], 650000, reason: '1.000.000 - 350.000, KHÔNG phải 1.000.000-500.000-350.000');
      expect(s.totalAssets, 650000);
    });
  });

  group('13 — Status-only không ảnh hưởng summary', () {
    test('2 giao dịch giống hệt nhau, khác statusId → summary giống hệt nhau', () {
      final withStatusA = tx(
        type: TransactionType.expense,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: 200000,
        statusId: 'status_a',
      );
      final sA = summarize([withStatusA]);

      final withStatusB = tx(
        type: TransactionType.expense,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: 200000,
        statusId: 'status_b',
      );
      final sB = summarize([withStatusB]);

      expect(sA.availableByMember[FamilyMember.vo], sB.availableByMember[FamilyMember.vo]);
      expect(sA.totalAssets, sB.totalAssets);
    });
  });

  group('14/15 — Monthly summary filter theo transactionDate, KHÔNG theo createdAt', () {
    test('transactionDate 31/08 nhưng createdAt 01/09 → thuộc tháng 8', () {
      final t = tx(
        type: TransactionType.income,
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 500000,
        transactionDate: DateTime(2026, 8, 31),
        createdAt: DateTime(2026, 9, 1),
      );
      final augustSummary = summarize(
        [t],
        categories: [incomeCategory],
        month: DateTime(2026, 8),
      );
      final septemberSummary = summarize(
        [t],
        categories: [incomeCategory],
        month: DateTime(2026, 9),
      );

      expect(augustSummary.monthlyIncome, 500000);
      expect(septemberSummary.monthlyIncome, 0, reason: 'createdAt không được quyết định tháng');
    });

    test('transactionDate 01/09 nhưng createdAt khác hẳn → thuộc tháng 9', () {
      final t = tx(
        type: TransactionType.income,
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 700000,
        transactionDate: DateTime(2026, 9, 1),
        createdAt: DateTime(2026, 8, 20),
      );
      final septemberSummary = summarize(
        [t],
        categories: [incomeCategory],
        month: DateTime(2026, 9),
      );
      expect(septemberSummary.monthlyIncome, 700000);
    });
  });

  group('16 — Empty ledger', () {
    test('Không có transaction nào → mọi số về 0, không crash', () {
      final s = summarize([], funds: [fundA, fundB], assetTypes: [cashType, bankType]);
      expect(s.totalAvailable, 0);
      expect(s.totalSavings, 0);
      expect(s.totalFunds, 0);
      expect(s.totalAssets, 0);
      expect(s.monthlyIncome, 0);
      expect(s.monthlyExpense, 0);
      expect(s.monthlyNet, 0);
      expect(s.fundBalances[fundA.id], 0);
      expect(s.fundBalances[fundB.id], 0);
      expect(s.savingsByMemberAndAssetType[FamilyMember.vo]![cashType.id], 0);
    });
  });

  group('19 — amountMinor giữ integer chính xác với số tiền lớn', () {
    test('Số tiền hàng tỷ đồng không mất độ chính xác', () {
      final bigIncome = tx(
        type: TransactionType.income,
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 9999999999,
      );
      final bigExpense = tx(
        type: TransactionType.expense,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: 1234567891,
      );
      final s = summarize([bigIncome, bigExpense]);
      expect(s.availableByMember[FamilyMember.vo], 9999999999 - 1234567891);
      expect(s.totalAssets, 9999999999 - 1234567891);
    });
  });

  group('Monthly income/expense — Total Income bỏ qua excludeFromTotals đúng mục 17', () {
    test('Category Số dư ban đầu (excludeFromTotals) cộng vào available nhưng KHÔNG vào monthlyIncome', () {
      const openingBalanceCategory = Category(
        id: 'so_du_ban_dau',
        name: 'Số dư ban đầu',
        color: Color(0xFF2F8F4F),
        type: TransactionType.income,
        excludeFromTotals: true,
      );
      final opening = tx(
        type: TransactionType.income,
        categoryId: 'so_du_ban_dau',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 5000000,
      );
      final salary = tx(
        type: TransactionType.income,
        categoryId: incomeCategory.id,
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 10000000,
      );
      final s = summarize(
        [opening, salary],
        categories: [openingBalanceCategory, incomeCategory],
        month: DateTime(2026, 9),
      );

      expect(s.totalAvailable, 15000000, reason: 'opening balance vẫn cộng đúng vào pool balance');
      expect(s.monthlyIncome, 10000000, reason: 'nhưng KHÔNG tính vào Total Income — mục 17');
      expect(s.totalAssets, 15000000);
    });
  });
}
