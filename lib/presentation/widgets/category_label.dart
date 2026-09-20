import '../../core/constants/advanced_system_categories.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/family_member.dart';
import '../../domain/entities/pool_kind.dart';
import '../../domain/entities/savings_asset_type.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/entities/transaction_type.dart';
import '../../domain/entities/transfer_kind.dart';

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
    // Pool tiết kiệm `loạiTàiSản|thànhViên` → tên thành viên.
    return parseSavingsAssetRefId(refId)?.member.label;
  }

  final from = labelOf(t.sourceRefId);
  final to = labelOf(t.destinationRefId);
  if (from != null && to != null) {
    // Nạp / rút / phân bổ tiết kiệm luôn cùng 1 người → chỉ hiện 1 tên.
    return from == to ? from : '$from → $to';
  }
  return from ?? to;
}

/// Mô tả đời thường của giao dịch tiết kiệm (không lộ enum/pool/id):
///   "Thêm vào tiết kiệm" · "Rút từ tiết kiệm · Vàng" ·
///   "Tiết kiệm · Vàng → Gửi ngân hàng".
/// Trả `null` nếu không phải giao dịch tiết kiệm. Loại tài sản resolve qua
/// [resolveSavingsAsset] (kể cả "Chưa phân bổ" và loại đã ngừng).
String? savingsTransferLabel(
  Transaction t,
  Iterable<SavingsAssetType> assetTypes,
) {
  String nameOf(PoolKind kind, String? ref) {
    final parsed = kind == PoolKind.memberSavingsAsset && ref != null
        ? parseSavingsAssetRefId(ref)
        : null;
    if (parsed == null) return 'Loại tài sản khác';
    return resolveSavingsAsset(parsed.assetTypeId, assetTypes)?.name ??
        'Loại tài sản khác';
  }

  switch (t.transferKind) {
    case TransferKind.savingsTopup:
      return 'Thêm vào tiết kiệm';
    case TransferKind.savingsWithdraw:
      return 'Rút từ tiết kiệm · ${nameOf(t.sourceKind, t.sourceRefId)}';
    case TransferKind.savingsConvert:
      return 'Tiết kiệm · ${nameOf(t.sourceKind, t.sourceRefId)} → '
          '${nameOf(t.destinationKind, t.destinationRefId)}';
    default:
      return null;
  }
}
