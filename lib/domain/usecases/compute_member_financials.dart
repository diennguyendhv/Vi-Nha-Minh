import '../entities/family_member.dart';
import '../entities/transaction.dart';
import 'compute_pool_balance.dart';

class MemberFinancials {
  const MemberFinancials({
    required this.member,
    required this.balance,
    required this.savingsOnHand,
    required this.savingsInBank,
  });

  final FamilyMember member;
  final int balance;
  final int savingsOnHand;
  final int savingsInBank;

  int get savingsTotal => savingsOnHand + savingsInBank;
}

/// Số dư & tiết kiệm riêng cho 1 người — Financial Core V2: đọc thẳng 3
/// pool (`MEMBER_AVAILABLE`/`MEMBER_SAVINGS_CASH`/`MEMBER_SAVINGS_BANK`) qua
/// Financial Engine, không còn switch theo `CategoryKind` như V1 (mọi loại
/// giao dịch — Thu/Chi/Chuyển cho thành viên khác/Nạp tiết kiệm — đều tự
/// động cộng/trừ đúng pool nhờ `applyEffect`).
MemberFinancials computeMemberFinancials(
  FamilyMember member,
  List<Transaction> transactions,
) {
  return MemberFinancials(
    member: member,
    balance: computeMemberAvailableBalance(member, transactions),
    savingsOnHand: computeMemberSavingsCash(member, transactions),
    savingsInBank: computeMemberSavingsBank(member, transactions),
  );
}
