import '../engine/financial_engine.dart';
import '../entities/category.dart';
import '../entities/pool_kind.dart';
import '../entities/transaction.dart';
import '../entities/transaction_type.dart';
import 'compute_obligation_summary.dart';
import 'compute_reportable_income.dart';

/// 4 nhóm Thu/Chi theo góc nhìn người dùng — CHỈ LÀ SỐ BÁO CÁO, không đụng
/// số dư (`applyEffect`, Total Assets, Net Worth vẫn do Financial Engine).
///
/// - [revenue] Doanh thu: Thu "thật" (danh mục Thu không `excludeFromTotals`;
///   cùng nguồn sự thật với [computeReportableIncomeEntries] nên khớp
///   `ThreeTotals.totalIncome`).
/// - [otherInflow] Khoản thu khác: mọi khoản tiền vào KHÔNG phải doanh thu
///   (Số dư ban đầu, người khác trả lại, thu hồi vốn khi bán lại…).
/// - [spending] Chi tiêu: Chi thuộc danh mục `groupKey == null`.
/// - [businessExpense] Chi phí kinh doanh: Chi thuộc danh mục
///   `groupKey == business_expense`.
///
/// `spending + businessExpense` luôn bằng `ThreeTotals.totalExpense`.
class GroupedTotals {
  const GroupedTotals({
    required this.revenue,
    required this.otherInflow,
    required this.spending,
    required this.businessExpense,
  });

  final int revenue;
  final int otherInflow;
  final int spending;
  final int businessExpense;

  /// Thu nhập ròng = Doanh thu − Chi phí kinh doanh. KHÔNG trừ Chi tiêu, KHÔNG
  /// cộng Khoản thu khác.
  int get netIncome => revenue - businessExpense;

  /// Dòng tiền Thu/Chi ròng = Doanh thu + Khoản thu khác − Chi tiêu − Chi
  /// phí kinh doanh.
  int get cashFlow => revenue + otherInflow - spending - businessExpense;
}

/// Người chi (ví khả dụng hoặc pool tiết kiệm của thành viên); `null` nếu
/// nguồn là Quỹ mà chưa ghi người thực hiện. Chi từ Quỹ: người thực hiện là
/// `actorMemberId` (không suy từ Quỹ/ghi chú).
String? expenseSpender(Transaction t) {
  if (t.type == TransactionType.expense && t.sourceKind == PoolKind.fund) {
    return t.actorMemberId;
  }
  final refId = t.sourceRefId;
  if (refId == null) return null;
  switch (t.sourceKind) {
    case PoolKind.memberAvailable:
      return refId;
    case PoolKind.memberSavingsAsset:
      return parseSavingsAssetRefId(refId)?.memberId;
    default:
      return null;
  }
}

/// Tính [GroupedTotals] cho [month] hoặc khoảng ngày [from]..[to] (theo
/// `transactionDate`; bỏ trống = toàn bộ lịch sử) và tuỳ chọn [memberId] (1 FinancialMember). Chỉ đếm giao dịch đang hiệu
/// lực (`isVisible`) nên reversal/correction không bao giờ đếm đôi; đổi nhóm
/// của 1 danh mục chỉ đổi số báo cáo này, không đổi giao dịch nào.
GroupedTotals computeGroupedTotals(
  List<Transaction> transactions,
  List<Category> categories, {
  DateTime? month,
  DateTime? from,
  DateTime? to,
  String? memberId,
}) {
  final categoryById = {for (final c in categories) c.id: c};
  final interestPortions = computeObligationSettlementInterestPortions(
    transactions,
  );
  final reportable = {
    for (final e in computeReportableIncomeEntries(
      transactions,
      categories,
      month: month,
      from: from,
      to: to,
    ))
      e.transaction.id: e.amountMinor,
  };

  var revenue = 0;
  var otherInflow = 0;
  var spending = 0;
  var businessExpense = 0;

  for (final t in transactions) {
    if (!isVisible(t)) continue;
    if (!inReportPeriod(t.transactionDate, month: month, from: from, to: to)) {
      continue;
    }
    switch (t.type) {
      case TransactionType.income:
        if (memberId != null && incomeRecipient(t) != memberId) continue;
        final asRevenue = reportable[t.id] ?? 0;
        revenue += asRevenue;
        otherInflow += t.amountMinor - asRevenue;
      case TransactionType.expense:
        if (memberId != null && expenseSpender(t) != memberId) continue;
        final int amount;
        if (t.obligationId != null) {
          amount = interestPortions[t.id] ?? 0;
        } else if (categoryById[t.categoryId]?.excludeFromTotals ?? false) {
          amount = 0;
        } else {
          amount = t.amountMinor;
        }
        if (categoryById[t.categoryId]?.isBusinessExpense ?? false) {
          businessExpense += amount;
        } else {
          spending += amount;
        }
      case TransactionType.transfer:
        break; // Chuyển không bao giờ là Thu/Chi.
    }
  }

  return GroupedTotals(
    revenue: revenue,
    otherInflow: otherInflow,
    spending: spending,
    businessExpense: businessExpense,
  );
}
