import '../../core/constants/default_categories.dart';
import '../entities/category_kind.dart';
import '../entities/transaction.dart';

class FinancialSummary {
  const FinancialSummary({required this.totalIncome, required this.totalExpense});

  final int totalIncome;
  final int totalExpense;

  int get balance => totalIncome - totalExpense;

  /// (Thu - Chi) / Thu, rounded to a whole percent. 0 when there is no income.
  /// Tiết kiệm không tính là "chi" — chuyển tiền vào tiết kiệm là một cách
  /// dùng phần dư, không phải một khoản tiêu.
  int get savingsRatePercent =>
      totalIncome > 0 ? ((balance / totalIncome) * 100).round() : 0;
}

FinancialSummary computeFinancialSummary(List<Transaction> transactions) {
  var income = 0;
  var expense = 0;
  for (final t in transactions) {
    final kind = DefaultCategories.byId(t.categoryId).kind;
    if (kind == CategoryKind.income) {
      income += t.amount;
    } else if (kind == CategoryKind.expense) {
      expense += t.amount;
    }
  }
  return FinancialSummary(totalIncome: income, totalExpense: expense);
}
