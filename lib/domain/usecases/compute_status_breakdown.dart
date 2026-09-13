import '../entities/category.dart';
import '../entities/transaction.dart';

class StatusBreakdown {
  const StatusBreakdown(this.totals);

  /// Tổng tiền theo từng bước trạng thái, thứ tự đúng như `category.statuses`.
  final Map<String, int> totals;

  int get total => totals.values.fold(0, (sum, v) => sum + v);
}

/// Tổng tiền theo từng bước trạng thái của MỘT hạng mục — số bước, tên bước
/// hoàn toàn do `category.statuses` quyết định, không giới hạn cứng 3 bước.
/// Giao dịch chưa gán `status` được tính vào bước đầu tiên trong danh sách.
StatusBreakdown computeStatusBreakdown(
  List<Transaction> transactions,
  Category category,
) {
  if (category.statuses.isEmpty) return const StatusBreakdown({});

  final totals = {for (final s in category.statuses) s: 0};
  final firstStep = category.statuses.first;
  for (final t in transactions.where((t) => t.categoryId == category.id)) {
    final key = t.status != null && totals.containsKey(t.status)
        ? t.status!
        : firstStep;
    totals[key] = totals[key]! + t.amount;
  }
  return StatusBreakdown(totals);
}
