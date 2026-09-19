import '../../core/constants/advanced_system_categories.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/family_member.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/entities/transaction_type.dart';

/// Nhóm chính (ngôn ngữ người dùng) của 1 danh mục Thu/Chi; `null` cho Chuyển
/// và các danh mục hệ thống của tính năng nâng cao (Vay, Hoàn tiền…) — lịch sử
/// cũ của chúng vẫn hiện tên gốc, không gán nhóm.
String? categoryGroupLabel(Category category) {
  if (AdvancedSystemCategories.contains(category.id)) return null;
  switch (category.type) {
    case TransactionType.income:
      return category.excludeFromTotals ? 'Khoản thu khác' : 'Doanh thu';
    case TransactionType.expense:
      return category.isBusinessExpense ? 'Chi phí kinh doanh' : 'Chi tiêu';
    case TransactionType.transfer:
      return null;
  }
}

/// Nhãn dòng giao dịch: "Doanh thu · Học phí", "Chi phí kinh doanh · Lương
/// nhân viên". Không lặp khi tên danh mục trùng tên nhóm; danh mục đã xoá →
/// "Đã xoá danh mục".
String categoryDisplayLabel(Category? category) {
  if (category == null) return 'Đã xoá danh mục';
  final group = categoryGroupLabel(category);
  if (group == null || group == category.name) return category.name;
  return '$group · ${category.name}';
}

/// Nhãn thành viên của 1 giao dịch: "Vợ" / "Chồng"; Chuyển giữa 2 thành viên
/// hiện "Vợ → Chồng". `null` khi giao dịch không thuộc thành viên nào (vd chỉ
/// liên quan Quỹ).
String? transactionMemberLabel(Transaction t) {
  String? labelOf(String? refId) {
    if (refId == null) return null;
    for (final m in FamilyMember.values) {
      if (m.name == refId) return m.label;
    }
    return null;
  }

  final from = labelOf(t.sourceRefId);
  final to = labelOf(t.destinationRefId);
  if (from != null && to != null) return '$from → $to';
  return from ?? to;
}
