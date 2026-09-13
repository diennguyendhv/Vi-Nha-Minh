import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/usecases/compute_expense_breakdown.dart';
import 'package:vi_nha_minh/domain/usecases/compute_financial_summary.dart';

Transaction _tx({
  required TransactionType type,
  required String categoryId,
  required int amount,
}) {
  return Transaction(
    id: '$categoryId-$amount',
    type: type,
    categoryId: categoryId,
    amount: amount,
    date: DateTime(2026, 9, 1),
  );
}

void main() {
  group('computeFinancialSummary', () {
    test('tính đúng thu, chi, số dư và tỷ lệ tiết kiệm', () {
      final transactions = [
        _tx(type: TransactionType.income, categoryId: 'luong', amount: 10000000),
        _tx(type: TransactionType.expense, categoryId: 'anuong', amount: 3000000),
        _tx(type: TransactionType.expense, categoryId: 'dichuyen', amount: 2000000),
      ];

      final summary = computeFinancialSummary(transactions);

      expect(summary.totalIncome, 10000000);
      expect(summary.totalExpense, 5000000);
      expect(summary.balance, 5000000);
      expect(summary.savingsRatePercent, 50);
    });

    test('tỷ lệ tiết kiệm bằng 0 khi không có thu nhập', () {
      final transactions = [
        _tx(type: TransactionType.expense, categoryId: 'anuong', amount: 100000),
      ];

      final summary = computeFinancialSummary(transactions);

      expect(summary.savingsRatePercent, 0);
    });
  });

  group('computeExpenseBreakdown', () {
    test('gộp theo hạng mục, bỏ qua thu nhập, sắp xếp giảm dần', () {
      final transactions = [
        _tx(type: TransactionType.expense, categoryId: 'anuong', amount: 100000),
        _tx(type: TransactionType.expense, categoryId: 'anuong', amount: 50000),
        _tx(type: TransactionType.expense, categoryId: 'dichuyen', amount: 200000),
        _tx(type: TransactionType.income, categoryId: 'luong', amount: 5000000),
      ];

      final breakdown = computeExpenseBreakdown(transactions);

      expect(breakdown.length, 2);
      expect(breakdown.first.categoryId, 'dichuyen');
      expect(breakdown.first.total, 200000);
      expect(breakdown.last.categoryId, 'anuong');
      expect(breakdown.last.total, 150000);
    });

    test('percentOf tính đúng phần trăm trên tổng', () {
      const item = CategoryTotal(categoryId: 'anuong', total: 250000);
      expect(item.percentOf(1000000), 25);
      expect(item.percentOf(0), 0);
    });
  });
}
