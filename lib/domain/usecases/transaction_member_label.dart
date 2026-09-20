import '../entities/family_member.dart';
import '../entities/pool_kind.dart';
import '../entities/transaction.dart';

/// Nhãn thành viên của 1 giao dịch: "Vợ" / "Chồng"; Chuyển giữa 2 thành viên
/// hiện "Vợ → Chồng". `null` khi giao dịch không thuộc thành viên nào (vd chỉ
/// liên quan Quỹ).
///
/// Nguồn DUY NHẤT cho mọi nơi hiển thị "giao dịch của ai" (danh sách, Tổng hợp,
/// hộp thoại chặn xóa/sửa) — không viết lại logic này ở màn khác.
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
