import '../../core/constants/advanced_system_categories.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/pool_kind.dart';
import '../../domain/entities/savings_asset_type.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/entities/transaction_type.dart';
import '../../domain/entities/transfer_kind.dart';

// `transactionMemberLabel` nay nằm ở domain (dùng chung cả hộp thoại chặn xóa);
// re-export để các màn hiện có giữ nguyên import.
export '../../domain/usecases/transaction_member_label.dart'
    show transactionMemberLabel;

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
