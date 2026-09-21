import '../engine/financial_engine.dart';
import '../entities/pool_kind.dart';
import '../entities/savings_asset_type.dart';
import '../entities/transaction.dart';

/// 1 dòng trong "Phân bổ" của Tiết kiệm 1 thành viên.
class SavingsAllocationRow {
  const SavingsAllocationRow({
    required this.assetTypeId,
    required this.asset,
    required this.balance,
    required this.isInactive,
  });

  final String assetTypeId;

  /// Loại tài sản đã resolve (hệ thống "Chưa phân bổ" / dòng DB) — null khi
  /// pool còn tiền nhưng không có định nghĩa (dữ liệu cũ/đã xoá); UI hiển thị
  /// tên chung, tiền vẫn phải THẤY được.
  final SavingsAssetType? asset;
  final int balance;

  /// Loại đã ngừng sử dụng nhưng vẫn còn số dư: cho rút / chuyển RA, không cho
  /// nạp / chuyển VÀO.
  final bool isInactive;

  bool get isSystem => SystemSavingsAssets.isSystem(assetTypeId);
}

/// Tầng 1 + tầng 2 của Tiết kiệm 1 thành viên. [total] LUÔN bằng tổng
/// `memberSavingsAsset` của thành viên (cùng nguồn với Trang chủ) và LUÔN bằng
/// tổng [rows] — không có tiền nào tồn tại trong Engine mà người dùng không
/// thấy.
class SavingsBreakdown {
  const SavingsBreakdown({required this.total, required this.rows});

  final int total;
  final List<SavingsAllocationRow> rows;
}

/// Tính breakdown cho [memberId]:
/// - "Chưa phân bổ" luôn ở đầu (kể cả 0 — đích mặc định của Thêm vào tiết kiệm);
/// - mọi loại ĐANG DÙNG (kể cả số dư 0);
/// - loại ĐÃ NGỪNG chỉ khi còn số dư ≠ 0 (isInactive = true);
/// - pool mồ côi (không có định nghĩa) còn số dư ≠ 0.
SavingsBreakdown computeMemberSavingsBreakdown(
  String memberId,
  List<Transaction> transactions,
  List<SavingsAssetType> assetTypes,
) {
  final balances = computeAllPoolBalances(transactions);
  final byAsset = <String, int>{};
  for (final e in balances.entries) {
    final (kind, refId) = e.key;
    if (kind != PoolKind.memberSavingsAsset || refId == null) continue;
    final parsed = parseSavingsAssetRefId(refId);
    if (parsed == null || parsed.memberId != memberId) continue;
    byAsset[parsed.assetTypeId] = (byAsset[parsed.assetTypeId] ?? 0) + e.value;
  }
  final total = byAsset.values.fold<int>(0, (a, b) => a + b);

  final rows = <SavingsAllocationRow>[
    SavingsAllocationRow(
      assetTypeId: SystemSavingsAssets.unallocatedId,
      asset: SystemSavingsAssets.unallocated,
      balance: byAsset[SystemSavingsAssets.unallocatedId] ?? 0,
      isInactive: false,
    ),
  ];
  final seen = {SystemSavingsAssets.unallocatedId};
  for (final a in assetTypes) {
    seen.add(a.id);
    final balance = byAsset[a.id] ?? 0;
    if (a.isActive) {
      rows.add(
        SavingsAllocationRow(
          assetTypeId: a.id,
          asset: a,
          balance: balance,
          isInactive: false,
        ),
      );
    } else if (balance != 0) {
      rows.add(
        SavingsAllocationRow(
          assetTypeId: a.id,
          asset: a,
          balance: balance,
          isInactive: true,
        ),
      );
    }
  }
  for (final e in byAsset.entries) {
    if (seen.contains(e.key) || e.value == 0) continue;
    rows.add(
      SavingsAllocationRow(
        assetTypeId: e.key,
        asset: null,
        balance: e.value,
        isInactive: true,
      ),
    );
  }
  return SavingsBreakdown(total: total, rows: rows);
}

/// Id loại tài sản đã từng xuất hiện ở BẤT KỲ chân nào của BẤT KỲ giao dịch nào
/// (kể cả giao dịch đã hoàn tác — vẫn là 1 dòng sổ). Tham chiếu là chuỗi
/// `loạiTàiSản|thànhViên` (không có khoá ngoại) nên phải quét sổ.
Set<String> savingsAssetTypeIdsInLedger(Iterable<Transaction> transactions) {
  final used = <String>{};
  void take(PoolKind kind, String? ref) {
    if (kind != PoolKind.memberSavingsAsset || ref == null) return;
    final parsed = parseSavingsAssetRefId(ref);
    if (parsed != null) used.add(parsed.assetTypeId);
  }

  for (final t in transactions) {
    take(t.sourceKind, t.sourceRefId);
    take(t.destinationKind, t.destinationRefId);
  }
  return used;
}

/// Loại tài sản ĐÃ NGỪNG, không phải hệ thống và CHƯA TỪNG có giao dịch nào
/// tham chiếu → an toàn để hiện "Xóa hẳn". Chỉ để hiển thị; việc xoá thật luôn
/// được kiểm tra lại trong DB (`deleteAssetTypePermanently`).
Set<String> computeDeletableAssetTypeIds(
  Iterable<SavingsAssetType> assetTypes,
  Iterable<Transaction> transactions,
) {
  final used = savingsAssetTypeIdsInLedger(transactions);
  return {
    for (final a in assetTypes)
      if (!a.isActive && !SystemSavingsAssets.isSystem(a.id) && !used.contains(a.id))
        a.id,
  };
}
