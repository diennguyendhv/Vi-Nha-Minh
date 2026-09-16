import '../entities/family_member.dart';
import '../entities/transaction.dart';
import 'compute_pool_balance.dart';

class MemberFinancials {
  const MemberFinancials({required this.member, required this.balance, required this.savingsTotal});

  final FamilyMember member;
  final int balance;

  /// Cộng dồn MỌI loại tài sản tiết kiệm (Tiền mặt, Ngân hàng, Chứng
  /// khoán...) — xem breakdown từng loại qua `savings_screen.dart` /
  /// `compute_pool_balance.computeMemberSavingsByAssetType`.
  final int savingsTotal;
}

/// Số dư & tổng tiết kiệm riêng cho 1 người — Financial Core V2: đọc thẳng
/// pool qua Financial Engine, không còn switch theo `CategoryKind` như V1
/// (mọi loại giao dịch — Thu/Chi/Chuyển cho thành viên khác/Nạp tiết kiệm —
/// đều tự động cộng/trừ đúng pool nhờ `applyEffect`).
MemberFinancials computeMemberFinancials(
  FamilyMember member,
  List<Transaction> transactions,
) {
  return MemberFinancials(
    member: member,
    balance: computeMemberAvailableBalance(member, transactions),
    savingsTotal: computeMemberSavingsTotal(member, transactions),
  );
}
