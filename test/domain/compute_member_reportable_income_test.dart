import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/constants/default_categories.dart';
import 'package:vi_nha_minh/domain/engine/financial_engine.dart';
import 'package:vi_nha_minh/domain/entities/family_member.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/usecases/compute_financial_summary.dart';
import 'package:vi_nha_minh/domain/usecases/compute_reportable_income.dart';
import 'package:vi_nha_minh/domain/usecases/compute_three_totals.dart';

/// F25 (Pixel 7a acceptance, 2026-09-19): "Thu nhập của Vợ/Chồng" phải mang
/// CÙNG ngữ nghĩa reportable Income với thu nhập gia đình
/// (`computeThreeTotals`). Số dư ban đầu, gốc Đi vay và phần hoàn vốn của
/// recovery tăng Available nhưng KHÔNG phải thu nhập.
void main() {
  final categories = DefaultCategories.all;
  final sep = DateTime(2026, 9, 10);
  var seq = 0;

  Transaction incomeTx({
    required FamilyMember to,
    required int amount,
    String categoryId = 'thu_nhap',
    DateTime? date,
    String? obligationId,
    String? settlementGroupId,
    String? recoveryOfTxId,
    String? id,
    String? reversedByTxId,
    String? reversalOfTxId,
    PoolKind destinationKind = PoolKind.memberAvailable,
    String? destinationRefId,
  }) {
    final n = seq++;
    final d = date ?? sep;
    return Transaction(
      id: id ?? 'inc-$n',
      type: TransactionType.income,
      categoryId: categoryId,
      sourceKind: PoolKind.external,
      destinationKind: destinationKind,
      destinationRefId: destinationRefId ?? to.name,
      amountMinor: amount,
      transactionDate: d,
      createdAt: d.add(Duration(seconds: n)),
      clientTxId: 'c-$n',
      obligationId: obligationId,
      settlementGroupId: settlementGroupId,
      recoveryOfTxId: recoveryOfTxId,
      reversedByTxId: reversedByTxId,
      reversalOfTxId: reversalOfTxId,
    );
  }

  Transaction expenseTx({
    required String id,
    required FamilyMember from,
    required int amount,
    String categoryId = 'dau_tu',
  }) {
    final n = seq++;
    return Transaction(
      id: id,
      type: TransactionType.expense,
      categoryId: categoryId,
      sourceKind: PoolKind.memberAvailable,
      sourceRefId: from.name,
      destinationKind: PoolKind.external,
      amountMinor: amount,
      transactionDate: sep,
      createdAt: sep.add(Duration(seconds: n)),
      clientTxId: 'c-$n',
    );
  }

  int memberIncome(FamilyMember m, List<Transaction> tx, {DateTime? month}) =>
      computeMemberIncomeTotal(m, tx, categories, month: month ?? sep);

  int familyIncome(List<Transaction> tx, {DateTime? month}) =>
      computeThreeTotals(tx, categories, month: month ?? sep).totalIncome;

  int available(FamilyMember m, List<Transaction> tx) =>
      poolBalance(computeAllPoolBalances(tx), PoolKind.memberAvailable, m.name);

  test('A — Opening Balance 1.000.000: Available +1tr, memberIncome = 0, familyIncome = 0', () {
    final tx = [incomeTx(to: FamilyMember.vo, amount: 1000000, categoryId: 'so_du_ban_dau')];
    expect(available(FamilyMember.vo, tx), 1000000);
    expect(memberIncome(FamilyMember.vo, tx), 0);
    expect(familyIncome(tx), 0);
  });

  test('B — Income thật 1.000.000 của Vợ: memberIncome(Vợ) = 1tr, familyIncome = 1tr', () {
    final tx = [incomeTx(to: FamilyMember.vo, amount: 1000000)];
    expect(memberIncome(FamilyMember.vo, tx), 1000000);
    expect(memberIncome(FamilyMember.chong, tx), 0);
    expect(familyIncome(tx), 1000000);
  });

  test('C — Đi vay 700.000: Available +700k, memberIncome = 0, familyIncome = 0', () {
    final tx = [
      incomeTx(
        to: FamilyMember.vo,
        amount: 700000,
        categoryId: 'vay_no',
        obligationId: 'ob1',
      ),
    ];
    expect(available(FamilyMember.vo, tx), 700000);
    expect(memberIncome(FamilyMember.vo, tx), 0);
    expect(familyIncome(tx), 0);
  });

  test('D — Recovery lỗ (Chi 6tr, thu hồi 4,5tr): Available tăng, thu nhập báo cáo từ recovery = 0', () {
    final original = expenseTx(id: 'orig', from: FamilyMember.vo, amount: 6000000);
    final recovery = incomeTx(
      to: FamilyMember.vo,
      amount: 4500000,
      categoryId: 'hoan_tien_thu_hoi',
      recoveryOfTxId: 'orig',
    );
    final tx = [original, recovery];
    expect(available(FamilyMember.vo, tx), -1500000, reason: 'recovery làm Available tăng 4,5tr');
    expect(memberIncome(FamilyMember.vo, tx), 0);
    expect(familyIncome(tx), 0);
  });

  test('D2 — Recovery hoà vốn (Chi 6tr, thu hồi 6tr): thu nhập báo cáo = 0', () {
    final original = expenseTx(id: 'orig', from: FamilyMember.vo, amount: 6000000);
    final recovery = incomeTx(
      to: FamilyMember.vo,
      amount: 6000000,
      categoryId: 'hoan_tien_thu_hoi',
      recoveryOfTxId: 'orig',
    );
    expect(memberIncome(FamilyMember.vo, [original, recovery]), 0);
    expect(familyIncome([original, recovery]), 0);
  });

  test('E — Recovery có lãi (Chi 6tr, thu hồi 6,5tr): Available nhận đủ 6,5tr, thu nhập báo cáo chỉ +500.000', () {
    final original = expenseTx(id: 'orig', from: FamilyMember.vo, amount: 6000000);
    final recovery = incomeTx(
      to: FamilyMember.vo,
      amount: 6500000,
      categoryId: 'hoan_tien_thu_hoi',
      recoveryOfTxId: 'orig',
    );
    final tx = [original, recovery];
    expect(available(FamilyMember.vo, tx), 500000, reason: '−6tr + 6,5tr');
    expect(memberIncome(FamilyMember.vo, tx), 500000);
    expect(familyIncome(tx), 500000);
  });

  test('F — Nhiều thành viên: Σ memberIncome == familyIncome (kể cả khi có Opening/Đi vay/recovery xen kẽ)', () {
    final original = expenseTx(id: 'orig', from: FamilyMember.chong, amount: 2000000);
    final tx = [
      incomeTx(to: FamilyMember.vo, amount: 1000000),
      incomeTx(to: FamilyMember.chong, amount: 2500000),
      incomeTx(to: FamilyMember.vo, amount: 3000000, categoryId: 'so_du_ban_dau'),
      incomeTx(to: FamilyMember.chong, amount: 700000, categoryId: 'vay_no', obligationId: 'ob1'),
      original,
      incomeTx(
        to: FamilyMember.chong,
        amount: 2450000,
        categoryId: 'hoan_tien_thu_hoi',
        recoveryOfTxId: 'orig',
      ),
    ];
    final vo = memberIncome(FamilyMember.vo, tx);
    final chong = memberIncome(FamilyMember.chong, tx);
    expect(vo, 1000000);
    expect(chong, 2500000 + 450000, reason: 'thu nhập thật 2,5tr + lợi nhuận recovery 450k');
    expect(vo + chong, familyIncome(tx));
    // Cùng nguồn với monthlyIncome ở Trang chủ.
    final summary = computeFinancialSummary(
      tx,
      categories: categories,
      funds: const [],
      assetTypes: const [],
      month: sep,
    );
    expect(summary.monthlyIncome, vo + chong);
  });

  test('G — Lọc theo transactionDate giống thu nhập gia đình (không theo createdAt)', () {
    final aug = DateTime(2026, 8, 31);
    final tx = [
      incomeTx(to: FamilyMember.vo, amount: 1000000, date: sep),
      // Tạo (createdAt) hôm nay nhưng transactionDate thuộc tháng 8.
      incomeTx(to: FamilyMember.vo, amount: 400000, date: aug),
    ];
    expect(memberIncome(FamilyMember.vo, tx, month: sep), 1000000);
    expect(memberIncome(FamilyMember.vo, tx, month: aug), 400000);
    expect(familyIncome(tx, month: sep), 1000000);
    expect(familyIncome(tx, month: aug), 400000);
    // Không truyền tháng → toàn bộ lịch sử, vẫn khớp nhau.
    expect(computeMemberIncomeTotal(FamilyMember.vo, tx, categories), 1400000);
    expect(computeThreeTotals(tx, categories).totalIncome, 1400000);
  });

  test('H — Reversal/correction không đếm đôi', () {
    // Income 1tr bị hoàn tác (bản gốc + dòng reversal đều bị bỏ qua).
    final original = incomeTx(
      to: FamilyMember.vo,
      amount: 1000000,
      id: 'orig-inc',
      reversedByTxId: 'rev-inc',
    );
    final reversal = incomeTx(
      to: FamilyMember.vo,
      amount: 1000000,
      id: 'rev-inc',
      reversalOfTxId: 'orig-inc',
    );
    // Bản sửa (correction) 800k là bản mới nhất còn hiệu lực.
    final corrected = incomeTx(to: FamilyMember.vo, amount: 800000, id: 'corr-inc');
    final tx = [original, reversal, corrected];
    expect(memberIncome(FamilyMember.vo, tx), 800000);
    expect(familyIncome(tx), 800000);
  });

  test('H2 — Recovery bị hoàn tác: lợi nhuận không còn được đếm', () {
    final original = expenseTx(id: 'orig', from: FamilyMember.vo, amount: 6000000);
    final recovery = incomeTx(
      to: FamilyMember.vo,
      amount: 6500000,
      categoryId: 'hoan_tien_thu_hoi',
      recoveryOfTxId: 'orig',
      id: 'rec',
      reversedByTxId: 'rec-rev',
    );
    final recReversal = incomeTx(
      to: FamilyMember.vo,
      amount: 6500000,
      categoryId: 'hoan_tien_thu_hoi',
      recoveryOfTxId: 'orig',
      id: 'rec-rev',
      reversalOfTxId: 'rec',
    );
    final tx = [original, recovery, recReversal];
    expect(memberIncome(FamilyMember.vo, tx), 0);
    expect(familyIncome(tx), 0);
  });

  test('Lãi Cho vay (INCOME thật có obligationId + settlementGroupId) vẫn là thu nhập của người nhận', () {
    final interest = incomeTx(
      to: FamilyMember.chong,
      amount: 200000,
      categoryId: 'lai_cho_vay',
      obligationId: 'ob2',
      settlementGroupId: 'grp1',
    );
    expect(memberIncome(FamilyMember.chong, [interest]), 200000);
    expect(familyIncome([interest]), 200000);
  });

  test('Income vào pool tiết kiệm của 1 thành viên được gán đúng người (không mất khỏi tổng)', () {
    final tx = [
      incomeTx(
        to: FamilyMember.vo,
        amount: 500000,
        destinationKind: PoolKind.memberSavingsAsset,
        destinationRefId: savingsAssetRefId('savings_bank', FamilyMember.vo),
      ),
    ];
    expect(memberIncome(FamilyMember.vo, tx), 500000);
    expect(familyIncome(tx), 500000);
  });
}
