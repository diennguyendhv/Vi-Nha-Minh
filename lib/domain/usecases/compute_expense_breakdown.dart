import '../engine/financial_engine.dart';
import '../entities/transaction.dart';
import '../entities/transaction_type.dart';

class CategoryTotal {
  const CategoryTotal({required this.categoryId, required this.total});

  final String categoryId;
  final int total;

  int percentOf(int grandTotal) =>
      grandTotal > 0 ? ((total / grandTotal) * 100).round() : 0;
}

/// Tổng chi theo từng hạng mục (`type == expense`), sắp giảm dần. Hạng mục
/// không phát sinh chi kỳ này bị bỏ qua. Chỉ đếm transaction đang hiệu lực
/// (`isVisible`).
List<CategoryTotal> computeExpenseBreakdown(List<Transaction> transactions) {
  final totals = <String, int>{};
  for (final t in transactions) {
    if (!isVisible(t) || t.type != TransactionType.expense) continue;
    totals.update(
      t.categoryId,
      (v) => v + t.amountMinor,
      ifAbsent: () => t.amountMinor,
    );
  }
  final result =
      totals.entries
          .map((e) => CategoryTotal(categoryId: e.key, total: e.value))
          .toList()
        ..sort((a, b) => b.total.compareTo(a.total));
  return result;
}
