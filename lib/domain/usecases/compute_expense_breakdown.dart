import '../entities/transaction.dart';
import '../entities/transaction_type.dart';

class CategoryTotal {
  const CategoryTotal({required this.categoryId, required this.total});

  final String categoryId;
  final int total;

  int percentOf(int grandTotal) =>
      grandTotal > 0 ? ((total / grandTotal) * 100).round() : 0;
}

/// Sums expense transactions per category, largest first. Categories with
/// no spending this period are omitted.
List<CategoryTotal> computeExpenseBreakdown(List<Transaction> transactions) {
  final totals = <String, int>{};
  for (final t in transactions) {
    if (t.type != TransactionType.expense) continue;
    totals.update(t.categoryId, (v) => v + t.amount, ifAbsent: () => t.amount);
  }
  final result = totals.entries
      .map((e) => CategoryTotal(categoryId: e.key, total: e.value))
      .toList()
    ..sort((a, b) => b.total.compareTo(a.total));
  return result;
}
