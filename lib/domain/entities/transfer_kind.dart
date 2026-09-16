/// Chỉ có ý nghĩa khi `Transaction.type == TransactionType.transfer`
/// (`docs/financial-core-v2.md` mục 7, 8, 9). Thêm `transferKind` mới sau
/// này (vd chuyển giữa 2 quỹ) không cần đổi Financial Engine.
enum TransferKind {
  memberToMember,
  savingsTopup,
  savingsWithdraw,
  savingsToBank,
  fundTopup,
  fundWithdraw,
}
