import '../engine/financial_engine.dart';
import '../entities/category.dart';
import '../entities/transaction.dart';

class StatusBreakdown {
  const StatusBreakdown(this.totals);

  /// Tổng tiền theo từng bước trạng thái, khoá bằng `Status.id`, thứ tự
  /// đúng như `category.statuses` (đã sắp theo `sortOrder`).
  final Map<String, int> totals;

  int get total => totals.values.fold(0, (sum, v) => sum + v);
}

/// Tổng tiền theo từng bước trạng thái của MỘT hạng mục — số bước, tên bước
/// hoàn toàn do `category.statuses` quyết định, không giới hạn cứng. Giao
/// dịch chưa gán `statusId` được tính vào bước đầu tiên. Chỉ đếm transaction
/// đang hiệu lực (`isVisible`).
StatusBreakdown computeStatusBreakdown(
  List<Transaction> transactions,
  Category category,
) {
  if (category.statuses.isEmpty) return const StatusBreakdown({});

  final totals = {for (final s in category.statuses) s.id: 0};
  final firstStepId = category.statuses.first.id;
  for (final t in transactions) {
    if (!isVisible(t) || t.categoryId != category.id) continue;
    final key = t.statusId != null && totals.containsKey(t.statusId)
        ? t.statusId!
        : firstStepId;
    totals[key] = totals[key]! + t.amountMinor;
  }
  return StatusBreakdown(totals);
}
