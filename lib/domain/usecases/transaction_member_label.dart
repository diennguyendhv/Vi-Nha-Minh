import '../entities/pool_kind.dart';
import '../entities/transaction.dart';
import '../entities/transaction_type.dart';
import '../entities/wallet_identity.dart';

/// Nhãn thành viên của 1 giao dịch: tên của [FinancialMember] (vd "Vợ"/"Chồng");
/// Chuyển giữa 2 thành viên hiện "Vợ → Chồng". `null` khi giao dịch không thuộc
/// thành viên nào (vd chỉ liên quan Quỹ) hoặc `memberId` không có trong [members].
///
/// Nhãn là DỮ LIỆU của thành viên — không suy ra từ chuỗi `memberId`.
///
/// Nguồn DUY NHẤT cho mọi nơi hiển thị "giao dịch của ai" (danh sách, Tổng hợp,
/// hộp thoại chặn xóa/sửa) — không viết lại logic này ở màn khác.
String? transactionMemberLabel(
  Transaction t,
  Iterable<FinancialMember> members,
) {
  String? labelOf(PoolKind kind, String? refId) {
    if (refId == null) return null;
    final String? memberId;
    switch (kind) {
      case PoolKind.memberAvailable:
        memberId = refId;
      case PoolKind.memberSavingsAsset:
        // Pool tiết kiệm `loạiTàiSản|thànhViên` → tên thành viên.
        memberId = parseSavingsAssetRefId(refId)?.memberId;
      default:
        return null;
    }
    if (memberId == null) return null;
    for (final m in members) {
      if (m.memberId == memberId) return m.label;
    }
    return null;
  }

  final from = t.type == TransactionType.expense && t.sourceKind == PoolKind.fund
      ? labelOf(PoolKind.memberAvailable, t.actorMemberId)
      : labelOf(t.sourceKind, t.sourceRefId);
  final to = labelOf(t.destinationKind, t.destinationRefId);
  if (from != null && to != null) {
    // Nạp / rút / phân bổ tiết kiệm luôn cùng 1 người → chỉ hiện 1 tên.
    return from == to ? from : '$from → $to';
  }
  return from ?? to;
}
