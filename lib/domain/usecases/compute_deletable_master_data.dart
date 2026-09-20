import '../../core/constants/advanced_system_categories.dart';
import '../engine/financial_engine.dart';
import '../entities/category.dart';
import '../entities/transaction.dart';
import '../entities/transaction_type.dart';

/// Id các bước trạng thái ĐÃ NGỪNG và không có giao dịch nào (đang tồn tại
/// trong sổ) tham chiếu `statusId` — an toàn để hiện "Xóa hẳn". Chỉ để HIỂN
/// THỊ, suy ra từ dữ liệu đang xem nên luôn khớp màn hình ngay khi vừa xóa /
/// sửa / ngừng; việc xóa thật vẫn được kiểm tra lại trong DB.
Set<String> computeDeletableStatusIds(
  Iterable<Category> categories,
  Iterable<Transaction> transactions,
) {
  final used = {
    for (final t in transactions)
      if (t.statusId != null) t.statusId!,
  };
  return {
    for (final c in categories)
      for (final s in c.statuses)
        if (!s.isActive && !used.contains(s.id)) s.id,
  };
}

/// Id danh mục ĐÃ NGỪNG an toàn để hiện "Xóa hẳn": không phải Chuyển / danh mục
/// hệ thống nâng cao, không có giao dịch nào tham chiếu, không danh mục khác
/// trỏ `linkedExpenseCategoryId`, và không bước con nào đang được giao dịch dùng.
Set<String> computeDeletableCategoryIds(
  Iterable<Category> categories,
  Iterable<Transaction> transactions,
) {
  final usedCategories = {for (final t in transactions) t.categoryId};
  final usedStatuses = {
    for (final t in transactions)
      if (t.statusId != null) t.statusId!,
  };
  final referenced = {
    for (final c in categories)
      if (c.linkedExpenseCategoryId != null &&
          c.linkedExpenseCategoryId != c.id)
        c.linkedExpenseCategoryId!,
  };
  return {
    for (final c in categories)
      if (!c.isActive &&
          c.type != TransactionType.transfer &&
          !AdvancedSystemCategories.contains(c.id) &&
          !usedCategories.contains(c.id) &&
          !referenced.contains(c.id) &&
          c.statuses.every((s) => !usedStatuses.contains(s.id)))
        c.id,
  };
}

/// Id mọi dòng thuộc các "họ giao dịch ĐÃ XÓA theo cơ chế cũ" (gốc + hoàn tác,
/// KHÔNG còn dòng nào đang hiệu lực) có ÍT NHẤT 1 dòng dùng [categoryId]. Đây là
/// lịch sử ẩn — không hiện ở danh sách nhưng vẫn giữ danh mục ở trạng thái "đã
/// dùng". Họ còn dòng đang hiệu lực (giao dịch thật) KHÔNG nằm trong kết quả.
Set<String> deletedHistoryIdsForCategory(
  String categoryId,
  List<Transaction> transactions,
) {
  bool live(Transaction t) => t.reversedByTxId == null && t.reversalOfTxId == null;
  final result = <String>{};
  final handled = <String>{};
  for (final t in transactions) {
    if (t.categoryId != categoryId || handled.contains(t.id)) continue;
    final family = transactionFamilyIds(t.id, transactions);
    handled.addAll(family);
    final anyLive = transactions.any((x) => family.contains(x.id) && live(x));
    if (!anyLive) result.addAll(family);
  }
  return result;
}

/// Danh mục đã ngừng mà CHỈ còn bị giữ bởi lịch sử ẩn đã xóa (dọn xong là xóa
/// hẳn được) — để hiện nút "Dọn lịch sử đã xóa".
bool categoryHeldOnlyByDeletedHistory(
  Category category,
  List<Transaction> transactions,
  Iterable<Category> categories,
) {
  final ids = deletedHistoryIdsForCategory(category.id, transactions);
  if (ids.isEmpty) return false;
  final rest = transactions.where((t) => !ids.contains(t.id)).toList();
  return computeDeletableCategoryIds(categories, rest).contains(category.id);
}
