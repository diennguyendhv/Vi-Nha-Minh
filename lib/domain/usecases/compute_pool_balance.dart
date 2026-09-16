import '../engine/financial_engine.dart';
import '../entities/family_member.dart';
import '../entities/pool_kind.dart';
import '../entities/transaction.dart';

/// Số dư 1 quỹ cụ thể — thay `computeFundBalance(List<FundEntry>)` của V1
/// (đã bỏ `FundEntry`, xem F-11). Tính động từ toàn bộ `Transaction` có
/// `sourceRefId`/`destinationRefId == fundId`.
int computeFundBalance(String fundId, List<Transaction> transactions) {
  final balances = computeAllPoolBalances(transactions);
  return poolBalance(balances, PoolKind.fund, fundId);
}

/// `MEMBER_AVAILABLE` của 1 thành viên — tiền có thể chi.
int computeMemberAvailableBalance(
  FamilyMember member,
  List<Transaction> transactions,
) {
  final balances = computeAllPoolBalances(transactions);
  return poolBalance(balances, PoolKind.memberAvailable, member.name);
}

/// `MEMBER_SAVINGS_CASH` của 1 thành viên — tiết kiệm hiện tại, chưa gửi NH.
int computeMemberSavingsCash(
  FamilyMember member,
  List<Transaction> transactions,
) {
  final balances = computeAllPoolBalances(transactions);
  return poolBalance(balances, PoolKind.memberSavingsCash, member.name);
}

/// `MEMBER_SAVINGS_BANK` của 1 thành viên — tiết kiệm đã gửi ngân hàng.
int computeMemberSavingsBank(
  FamilyMember member,
  List<Transaction> transactions,
) {
  final balances = computeAllPoolBalances(transactions);
  return poolBalance(balances, PoolKind.memberSavingsBank, member.name);
}
