import '../entities/savings_asset_type.dart';
import '../entities/transaction.dart';
import 'compute_pool_balance.dart';

class MemberFinancials {
  const MemberFinancials({
    required this.memberId,
    required this.balance,
    required this.savingsTotal,
    required this.savingsUnallocated,
  });

  final String memberId;
  final int balance;

  /// Cộng dồn MỌI loại tài sản tiết kiệm (Gửi ngân hàng, Vàng, Chứng
  /// khoán...) — xem breakdown từng loại qua `savings_screen.dart` /
  /// `compute_pool_balance.computeMemberSavingsByAssetType`.
  final int savingsTotal;

  /// CHỈ phần "Chưa phân bổ" (`savings_unallocated`) của [savingsTotal]. Đây là con
  /// số Trang chủ hiển thị (chỉ để trình bày; [savingsTotal] và Tổng tài sản
  /// không đổi — tiền đã phân bổ vẫn là tài sản, xem ở màn Tiết kiệm).
  final int savingsUnallocated;
}

/// Số dư & tổng tiết kiệm riêng cho 1 người — Financial Core V2: đọc thẳng
/// pool qua Financial Engine, không còn switch theo `CategoryKind` như V1
/// (mọi loại giao dịch — Thu/Chi/Chuyển cho thành viên khác/Nạp tiết kiệm —
/// đều tự động cộng/trừ đúng pool nhờ `applyEffect`).
MemberFinancials computeMemberFinancials(
  String memberId,
  List<Transaction> transactions,
) {
  return MemberFinancials(
    memberId: memberId,
    balance: computeMemberAvailableBalance(memberId, transactions),
    savingsTotal: computeMemberSavingsTotal(memberId, transactions),
    savingsUnallocated: computeMemberSavingsByAssetType(
      SystemSavingsAssets.unallocatedId,
      memberId,
      transactions,
    ),
  );
}
