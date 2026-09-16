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

/// Số dư 1 thành viên ở 1 loại tài sản tiết kiệm cụ thể (Tiền mặt, Ngân
/// hàng, Chứng khoán...) — thay `computeMemberSavingsCash`/
/// `computeMemberSavingsBank` cố định của bản trước.
int computeMemberSavingsByAssetType(
  String assetTypeId,
  FamilyMember member,
  List<Transaction> transactions,
) {
  final balances = computeAllPoolBalances(transactions);
  return poolBalance(
    balances,
    PoolKind.memberSavingsAsset,
    savingsAssetRefId(assetTypeId, member),
  );
}

/// Tổng tiết kiệm của 1 thành viên, CỘNG DỒN mọi loại tài sản — quét thẳng
/// trên `Map<PoolRef,int>` thay vì cần biết trước danh sách asset type nào
/// tồn tại (kể cả loại đã soft-delete vẫn cộng đúng, khớp Invariant 10).
int computeMemberSavingsTotal(
  FamilyMember member,
  List<Transaction> transactions,
) {
  final balances = computeAllPoolBalances(transactions);
  var total = 0;
  for (final entry in balances.entries) {
    final (kind, refId) = entry.key;
    if (kind != PoolKind.memberSavingsAsset || refId == null) continue;
    final parsed = parseSavingsAssetRefId(refId);
    if (parsed != null && parsed.member == member) total += entry.value;
  }
  return total;
}
