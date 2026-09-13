import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/constants/default_categories.dart';
import 'package:vi_nha_minh/domain/entities/family_member.dart';
import 'package:vi_nha_minh/domain/entities/savings_destination.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/usecases/compute_expense_breakdown.dart';
import 'package:vi_nha_minh/domain/usecases/compute_financial_summary.dart';
import 'package:vi_nha_minh/domain/usecases/compute_member_financials.dart';
import 'package:vi_nha_minh/domain/usecases/compute_status_breakdown.dart';

Transaction _tx({
  required String categoryId,
  required int amount,
  FamilyMember spender = FamilyMember.vo,
  String? status,
  SavingsDestination? savingsDestination,
}) {
  return Transaction(
    id: '$categoryId-$amount-${spender.name}',
    categoryId: categoryId,
    amount: amount,
    date: DateTime(2026, 9, 1),
    spender: spender,
    status: status,
    savingsDestination: savingsDestination,
  );
}

void main() {
  group('computeFinancialSummary', () {
    test('tính đúng thu, chi, số dư và tỷ lệ tiết kiệm', () {
      final transactions = [
        _tx(categoryId: 'thu_nhap', amount: 10000000),
        _tx(categoryId: 'sinh_hoat', amount: 3000000),
        _tx(categoryId: 'dau_tu', amount: 2000000),
      ];

      final summary = computeFinancialSummary(transactions);

      expect(summary.totalIncome, 10000000);
      expect(summary.totalExpense, 5000000);
      expect(summary.balance, 5000000);
      expect(summary.savingsRatePercent, 50);
    });

    test('tỷ lệ tiết kiệm bằng 0 khi không có thu nhập', () {
      final transactions = [_tx(categoryId: 'sinh_hoat', amount: 100000)];

      final summary = computeFinancialSummary(transactions);

      expect(summary.savingsRatePercent, 0);
    });

    test('hạng mục Tiết kiệm không bị tính là chi tiêu', () {
      final transactions = [
        _tx(categoryId: 'thu_nhap', amount: 5000000),
        _tx(categoryId: 'tiet_kiem', amount: 1000000),
      ];

      final summary = computeFinancialSummary(transactions);

      expect(summary.totalExpense, 0);
    });
  });

  group('computeExpenseBreakdown', () {
    test('gộp theo hạng mục, bỏ qua thu nhập/tiết kiệm, sắp xếp giảm dần', () {
      final transactions = [
        _tx(categoryId: 'sinh_hoat', amount: 100000),
        _tx(categoryId: 'sinh_hoat', amount: 50000),
        _tx(categoryId: 'dau_tu', amount: 200000),
        _tx(categoryId: 'thu_nhap', amount: 5000000),
        _tx(categoryId: 'tiet_kiem', amount: 500000),
      ];

      final breakdown = computeExpenseBreakdown(transactions);

      expect(breakdown.length, 2);
      expect(breakdown.first.categoryId, 'dau_tu');
      expect(breakdown.first.total, 200000);
      expect(breakdown.last.categoryId, 'sinh_hoat');
      expect(breakdown.last.total, 150000);
    });

    test('percentOf tính đúng phần trăm trên tổng', () {
      const item = CategoryTotal(categoryId: 'sinh_hoat', total: 250000);
      expect(item.percentOf(1000000), 25);
      expect(item.percentOf(0), 0);
    });
  });

  group('computeMemberFinancials', () {
    test('số dư chỉ tính giao dịch của đúng người, chuyển khoản đổi cả hai bên', () {
      final transactions = [
        _tx(categoryId: 'thu_nhap', amount: 10000000, spender: FamilyMember.chong),
        _tx(categoryId: 'sinh_hoat', amount: 1000000, spender: FamilyMember.vo),
        _tx(categoryId: 'chong_dua_vo', amount: 500000, spender: FamilyMember.chong),
      ];

      final vo = computeMemberFinancials(FamilyMember.vo, transactions);
      final chong = computeMemberFinancials(FamilyMember.chong, transactions);

      expect(vo.balance, -1000000 + 500000);
      expect(chong.balance, 10000000 - 500000);
    });

    test('tiết kiệm trừ số dư và cộng đúng quỹ hiện tại/ngân hàng', () {
      final transactions = [
        _tx(
          categoryId: 'tiet_kiem',
          amount: 300000,
          savingsDestination: SavingsDestination.onHand,
        ),
        _tx(
          categoryId: 'tiet_kiem',
          amount: 700000,
          savingsDestination: SavingsDestination.bank,
        ),
      ];

      final vo = computeMemberFinancials(FamilyMember.vo, transactions);

      expect(vo.balance, -1000000);
      expect(vo.savingsOnHand, 300000);
      expect(vo.savingsInBank, 700000);
      expect(vo.savingsTotal, 1000000);
    });
  });

  group('computeStatusBreakdown', () {
    test('gộp theo trạng thái, giao dịch chưa có status tính vào bước đầu tiên', () {
      final transactions = [
        _tx(categoryId: 'cho_di', amount: 100000, status: 'Chưa chuẩn bị'),
        _tx(categoryId: 'cho_di', amount: 50000),
        _tx(categoryId: 'cho_di', amount: 200000, status: 'Đã chuẩn bị'),
        _tx(categoryId: 'cho_di', amount: 300000, status: 'Đã gửi'),
        _tx(categoryId: 'dang_hien', amount: 999999, status: 'Đã dâng'),
      ];

      final breakdown = computeStatusBreakdown(transactions, DefaultCategories.choDi);

      expect(breakdown.totals['Chưa chuẩn bị'], 150000);
      expect(breakdown.totals['Đã chuẩn bị'], 200000);
      expect(breakdown.totals['Đã gửi'], 300000);
      expect(breakdown.total, 650000);
    });

    test('hạng mục không có statuses trả về breakdown rỗng', () {
      final breakdown = computeStatusBreakdown([], DefaultCategories.sinhHoat);
      expect(breakdown.totals, isEmpty);
      expect(breakdown.total, 0);
    });
  });
}
