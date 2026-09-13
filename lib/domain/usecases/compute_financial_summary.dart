import '../entities/transaction.dart';
import '../entities/transaction_type.dart';

class FinancialSummary {
  const FinancialSummary({required this.totalIncome, required this.totalExpense});

  final int totalIncome;
  final int totalExpense;

  int get balance => totalIncome - totalExpense;

  /// (Thu - Chi) / Thu, rounded to a whole percent. 0 when there is no income.
  int get savingsRatePercent =>
      totalIncome > 0 ? ((balance / totalIncome) * 100).round() : 0;
}

FinancialSummary computeFinancialSummary(List<Transaction> transactions) {
  var income = 0;
  var expense = 0;
  for (final t in transactions) {
    if (t.type == TransactionType.income) {
      income += t.amount;
    } else {
      expense += t.amount;
    }
  }
  return FinancialSummary(totalIncome: income, totalExpense: expense);
}
