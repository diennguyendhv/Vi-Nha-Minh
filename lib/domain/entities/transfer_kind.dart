/// Chỉ có ý nghĩa khi `Transaction.type == TransactionType.transfer`
/// (`docs/financial-core-v2.md` mục 7, 8, 9). Thêm `transferKind` mới sau
/// này (vd chuyển giữa 2 quỹ) không cần đổi Financial Engine.
enum TransferKind {
  memberToMember,

  /// MEMBER_AVAILABLE → memberSavingsAsset(loại X).
  savingsTopup,

  /// memberSavingsAsset(loại X) → MEMBER_AVAILABLE.
  savingsWithdraw,

  /// memberSavingsAsset(loại X) → memberSavingsAsset(loại Y) — vd "Tiền
  /// mặt" sang "Ngân hàng", hoặc "Ngân hàng" sang "Chứng khoán". Thay cho
  /// `savingsToBank` cố định ở bản trước — giờ chuyển được giữa BẤT KỲ 2
  /// loại tài sản tiết kiệm nào gia đình tự tạo.
  savingsConvert,

  fundTopup,
  fundWithdraw,
}
