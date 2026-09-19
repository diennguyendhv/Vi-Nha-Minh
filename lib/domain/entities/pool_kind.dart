import 'family_member.dart';

/// Mọi nơi giữ tiền trong hệ thống là một "pool", xác định bằng
/// `(PoolKind, refId)` (`docs/financial-core-v2.md` mục 4). `external` là
/// bên ngoài hệ thống (lương công ty, tiền trả người bán...) — `refId` luôn
/// null khi `kind == external`.
enum PoolKind {
  /// refId = FamilyMember.name — tiền có thể chi của 1 thành viên.
  memberAvailable,

  /// 1 loại tài sản tiết kiệm CỦA 1 thành viên cụ thể (Gửi ngân hàng, Vàng,
  /// Chứng khoán, Bất động sản...) — không còn cố định 2 pool cash/bank
  /// như bản trước. refId là khoá ghép `savingsAssetRefId(assetTypeId,
  /// member)`, xem hàm bên dưới. Tạo được bao nhiêu loại tài sản tuỳ gia
  /// đình (`SavingsAssetType`, tương tự cách `Fund` là dữ liệu tự tạo).
  memberSavingsAsset,

  /// refId = Fund.id — 1 quỹ cụ thể, DÙNG CHUNG cả nhà (khác savings, vốn
  /// tách riêng cho từng thành viên).
  fund,

  /// Phase 8.7 — refId = Obligation.id (`direction == receivable`): tiền đã
  /// cho vay, vẫn là TÀI SẢN của gia đình (chỉ đổi hình thái từ tiền mặt
  /// sang "quyền đòi nợ") — KHÔNG phải Expense (`docs/financial-core-v2.md`
  /// nguyên tắc mới, xem audit Phase 8.7). Cho vay = TRANSFER
  /// `memberAvailable → receivable`; thu hồi = TRANSFER ngược lại
  /// (+ 1 dòng INCOME riêng nếu thu vượt gốc — phần lãi). Pool này LUÔN
  /// được cộng vào `totalAssets` (đã tự động đúng nhờ `totalAssets` là tổng
  /// mọi pool — xem `compute_financial_summary.dart`).
  ///
  /// Payable (đi vay) CỐ TÌNH KHÔNG có PoolKind riêng — mô hình hoá bằng 1
  /// dòng INCOME/EXPENSE thường + `Transaction.obligationId`, vì Total
  /// Assets ĐƯỢC PHÉP tăng khi đi vay (khác Receivable) nên không cần bảo
  /// toàn qua 1 pool nội bộ — xem `docs/domain/obligation_settlement.dart`
  /// và audit Phase 8.7 (mục D).
  receivable,

  /// Bên ngoài hệ thống — refId luôn null.
  external,
}

/// Ghép `assetTypeId` + thành viên thành 1 khoá pool duy nhất — dùng cho
/// `PoolKind.memberSavingsAsset.refId`. Ký tự `|` không xuất hiện trong id
/// (id sinh bởi `IdGenerator`/enum name), an toàn để làm dấu phân cách.
String savingsAssetRefId(String assetTypeId, FamilyMember member) {
  return '$assetTypeId|${member.name}';
}

/// Tách ngược `savingsAssetRefId` — trả về null nếu chuỗi không đúng định
/// dạng (vd refId của 1 pool kind khác lỡ truyền nhầm vào).
({String assetTypeId, FamilyMember member})? parseSavingsAssetRefId(
  String refId,
) {
  final parts = refId.split('|');
  if (parts.length != 2) return null;
  for (final m in FamilyMember.values) {
    if (m.name == parts[1]) {
      return (assetTypeId: parts[0], member: m);
    }
  }
  return null;
}
