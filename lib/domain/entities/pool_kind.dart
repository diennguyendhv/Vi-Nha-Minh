/// Mọi nơi giữ tiền trong hệ thống là một "pool", xác định bằng
/// `(PoolKind, refId)` (`docs/financial-core-v2.md` mục 4). `external` là
/// bên ngoài hệ thống (lương công ty, tiền trả người bán...) — `refId` luôn
/// null khi `kind == external`.
enum PoolKind {
  /// refId = FamilyMember.name — tiền có thể chi của 1 thành viên.
  memberAvailable,

  /// refId = FamilyMember.name — tiết kiệm hiện tại (chưa gửi NH).
  memberSavingsCash,

  /// refId = FamilyMember.name — tiết kiệm đã gửi ngân hàng.
  memberSavingsBank,

  /// refId = Fund.id — 1 quỹ cụ thể.
  fund,

  /// Bên ngoài hệ thống — refId luôn null.
  external,
}
