import '../engine/financial_engine.dart';
import '../entities/category.dart';
import '../entities/family_member.dart';
import '../entities/fund.dart';
import '../entities/pool_kind.dart';
import '../entities/savings_asset_type.dart';
import '../entities/transaction.dart';
import 'compute_three_totals.dart';

/// Read model DUY NHẤT cho mọi màn hình tổng hợp tài sản (Trang chủ rút
/// gọn + Tổng hợp đầy đủ, Phase 8) — cả 2 màn PHẢI dùng chung 1 lần gọi
/// [computeFinancialSummary], không tự viết lại phép cộng/trừ nào khác.
///
/// Toàn bộ số liệu suy ra từ [computeAllPoolBalances] (Financial Engine,
/// `docs/financial-core-v2.md` mục 4/10) + [computeThreeTotals] (mục 17) —
/// không có nhánh if/else nào theo `transferKind`/category id cụ thể ở đây,
/// đúng nguyên tắc "1 Financial Engine duy nhất" (CLAUDE.md mục 9).
class FinancialSummary {
  const FinancialSummary({
    required this.availableByMember,
    required this.totalAvailable,
    required this.savingsByMemberAndAssetType,
    required this.savingsByMember,
    required this.totalSavings,
    required this.fundBalances,
    required this.totalFunds,
    required this.totalAssets,
    required this.monthlyIncome,
    required this.monthlyExpense,
  });

  final Map<FamilyMember, int> availableByMember;
  final int totalAvailable;

  /// `savingsByMemberAndAssetType[member][assetTypeId]` — chỉ chứa các
  /// [SavingsAssetType] còn `isActive` truyền vào (caller lọc trước, giống
  /// convention `activeFunds`/`activeAssetTypes` đã dùng ở
  /// `add_transaction_sheet.dart`). Loại đã soft-delete không hiện ở
  /// breakdown này, nhưng số dư của nó (luôn phải = 0 theo mục 8 — chỉ xoá
  /// được khi balance = 0) vẫn được cộng đúng vào [totalSavings] vì tổng đó
  /// quét TRỰC TIẾP trên `balances`, không qua danh sách này.
  final Map<FamilyMember, Map<String, int>> savingsByMemberAndAssetType;
  final Map<FamilyMember, int> savingsByMember;

  /// Tổng tiết kiệm CẢ NHÀ — quét toàn bộ `PoolKind.memberSavingsAsset`
  /// trực tiếp trên `balances` (Invariant 10: rebuild 100% từ transaction
  /// gốc), KHÔNG suy ra bằng cách cộng [savingsByMember] lại (2 nguồn tính
  /// độc lập cố ý, để không phụ thuộc danh sách `assetTypes` truyền vào có
  /// đầy đủ hay không).
  final int totalSavings;

  /// `fundBalances[fundId]` — chỉ chứa các [Fund] còn `isActive` truyền
  /// vào, cùng convention với `savingsByMemberAndAssetType` ở trên.
  final Map<String, int> fundBalances;

  /// Tổng số dư Quỹ CẢ NHÀ — quét trực tiếp `PoolKind.fund` trên
  /// `balances`, độc lập với danh sách `funds` truyền vào (lý do giống
  /// [totalSavings]).
  final int totalFunds;

  /// Tổng tài sản — tổng TOÀN BỘ pool nội bộ (`memberAvailable` +
  /// `memberSavingsAsset` + `fund`), đúng `docs/financial-core-v2.md` mục
  /// 17: `Total Assets = Available Money + Savings Assets + Fund Assets`.
  /// Cố tình lấy tổng `balances.values` thay vì cộng 3 field trên lại —
  /// tự động đúng cả khi domain thêm `PoolKind` mới sau này mà quên cập
  /// nhật hàm này, và khớp Invariant 2/3/4 (INCOME/EXPENSE đổi đúng
  /// amountMinor, TRANSFER tự triệt tiêu vì luôn chạm đúng 2 pool nội bộ).
  final int totalAssets;

  /// `Total Income` theo kỳ truyền vào (`month`, xem [computeThreeTotals])
  /// — bỏ qua category `excludeFromTotals` (vd "Số dư ban đầu").
  final int monthlyIncome;

  /// `Total External Expense` theo kỳ truyền vào.
  final int monthlyExpense;

  /// Phần còn lại/net của kỳ — mục 17: `balance = totalIncome −
  /// totalExpense`. KHÔNG lưu field riêng, luôn suy ra để không lệch với
  /// [ThreeTotals.balance].
  int get monthlyNet => monthlyIncome - monthlyExpense;
}

int _sumByKind(Map<PoolRef, int> balances, PoolKind kind) {
  var total = 0;
  for (final entry in balances.entries) {
    if (entry.key.$1 == kind) total += entry.value;
  }
  return total;
}

/// Tính [FinancialSummary] từ toàn bộ ledger — nguồn DUY NHẤT cho cả Trang
/// chủ (bản rút gọn) lẫn Tổng hợp (bản đầy đủ), Phase 8.
///
/// [funds]/[assetTypes] nên là danh sách đã lọc `isActive` (giống cách
/// `add_transaction_sheet.dart` tự lọc trước khi truyền) — chỉ ảnh hưởng
/// các breakdown hiển thị theo id, KHÔNG ảnh hưởng 3 tổng
/// (`totalSavings`/`totalFunds`/`totalAssets`), vốn luôn quét toàn bộ
/// `balances` bất kể danh sách này đầy đủ hay thiếu.
///
/// Truyền [month] để `monthlyIncome`/`monthlyExpense` chỉ tính trong 1
/// tháng cụ thể (theo `transactionDate`, KHÔNG theo `createdAt` — xem
/// `computeThreeTotals`); bỏ trống để tính toàn bộ lịch sử.
FinancialSummary computeFinancialSummary(
  List<Transaction> transactions, {
  required List<Category> categories,
  required List<Fund> funds,
  required List<SavingsAssetType> assetTypes,
  DateTime? month,
}) {
  final balances = computeAllPoolBalances(transactions);

  final availableByMember = <FamilyMember, int>{
    for (final m in FamilyMember.values)
      m: poolBalance(balances, PoolKind.memberAvailable, m.name),
  };
  final totalAvailable = availableByMember.values.fold<int>(0, (s, v) => s + v);

  final savingsByMemberAndAssetType = <FamilyMember, Map<String, int>>{
    for (final m in FamilyMember.values)
      m: {
        for (final a in assetTypes)
          a.id: poolBalance(balances, PoolKind.memberSavingsAsset, savingsAssetRefId(a.id, m)),
      },
  };
  final savingsByMember = <FamilyMember, int>{
    for (final m in FamilyMember.values)
      m: savingsByMemberAndAssetType[m]!.values.fold<int>(0, (s, v) => s + v),
  };

  final fundBalances = <String, int>{
    for (final f in funds) f.id: poolBalance(balances, PoolKind.fund, f.id),
  };

  final threeTotals = computeThreeTotals(transactions, categories, month: month);

  return FinancialSummary(
    availableByMember: availableByMember,
    totalAvailable: totalAvailable,
    savingsByMemberAndAssetType: savingsByMemberAndAssetType,
    savingsByMember: savingsByMember,
    totalSavings: _sumByKind(balances, PoolKind.memberSavingsAsset),
    fundBalances: fundBalances,
    totalFunds: _sumByKind(balances, PoolKind.fund),
    totalAssets: balances.values.fold<int>(0, (s, v) => s + v),
    monthlyIncome: threeTotals.totalIncome,
    monthlyExpense: threeTotals.totalExpense,
  );
}
