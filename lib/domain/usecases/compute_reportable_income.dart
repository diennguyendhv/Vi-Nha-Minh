import '../engine/financial_engine.dart';
import '../entities/category.dart';
import '../entities/family_member.dart';
import '../entities/pool_kind.dart';
import '../entities/transaction.dart';
import '../entities/transaction_type.dart';
import 'compute_recovery_summary.dart';

/// 1 khoản INCOME đang hiệu lực và phần của nó được BÁO CÁO là thu nhập
/// (`amountMinor` có thể nhỏ hơn số tiền thật nhận vào, xem
/// [computeReportableIncomeEntries]).
class ReportableIncome {
  const ReportableIncome({
    required this.transaction,
    required this.amountMinor,
  });

  final Transaction transaction;

  /// Phần được tính là thu nhập báo cáo — luôn `> 0` (khoản không đóng góp
  /// gì sẽ không xuất hiện trong danh sách).
  final int amountMinor;
}

/// NGUỒN SỰ THẬT DUY NHẤT cho câu hỏi "khoản INCOME nào, bao nhiêu tiền,
/// được tính là thu nhập báo cáo được (reportable income)". Cả thu nhập của
/// gia đình ([computeThreeTotals]) lẫn thu nhập theo từng thành viên
/// ([computeMemberIncomeTotal]) cộng từ CÙNG danh sách này, nên tổng thu nhập
/// các thành viên luôn đối chiếu được với thu nhập gia đình trong cùng kỳ.
///
/// Không mọi INCOME đi vào ví đều là thu nhập (F25, Pixel 7a 2026-09-19):
///
/// - Payable — TẠO khoản đi vay (`obligationId != null` &&
///   `settlementGroupId == null`): tiền vay không phải thu nhập → không tính.
/// - Recovery (`recoveryOfTxId != null`): chỉ phần LỢI NHUẬN vượt chi phí gốc
///   ([computeRecoveryProfitPortions]), attribute vào tháng của chính
///   recovery đó; phần hoàn vốn không tính.
/// - Còn lại: theo `category.excludeFromTotals` (vd "Số dư ban đầu" tăng
///   Available/Total Assets nhưng không phải thu nhập).
///
/// Chỉ đếm giao dịch đang hiệu lực (`isVisible`) nên reversal/correction
/// không bao giờ đếm đôi. [month] lọc theo `transactionDate` (cùng quy tắc
/// với [computeThreeTotals]); bỏ trống để tính toàn bộ lịch sử.
/// Giao dịch ngày [date] có thuộc kỳ báo cáo không: [month] (cả tháng) HOẶC
/// khoảng ngày [from]..[to] (bao gồm 2 đầu, so theo NGÀY lịch; `null` = không
/// giới hạn phía đó). Không truyền gì = toàn bộ lịch sử. Dùng chung cho mọi số
/// báo cáo theo kỳ để Tổng quan và Explorer cùng 1 quy tắc.
bool inReportPeriod(
  DateTime date, {
  DateTime? month,
  DateTime? from,
  DateTime? to,
}) {
  if (month != null &&
      (date.year != month.year || date.month != month.month)) {
    return false;
  }
  final day = DateTime(date.year, date.month, date.day);
  if (from != null &&
      day.isBefore(DateTime(from.year, from.month, from.day))) {
    return false;
  }
  if (to != null && day.isAfter(DateTime(to.year, to.month, to.day))) {
    return false;
  }
  return true;
}

List<ReportableIncome> computeReportableIncomeEntries(
  List<Transaction> transactions,
  List<Category> categories, {
  DateTime? month,
  DateTime? from,
  DateTime? to,
}) {
  final categoryById = {for (final c in categories) c.id: c};
  final recoveryProfitPortions = computeRecoveryProfitPortions(transactions);
  final entries = <ReportableIncome>[];

  for (final t in transactions) {
    if (!isVisible(t) || t.type != TransactionType.income) continue;
    if (!inReportPeriod(t.transactionDate, month: month, from: from, to: to)) {
      continue;
    }
    final int amount;
    if (t.obligationId != null && t.settlementGroupId == null) {
      amount = 0;
    } else if (t.recoveryOfTxId != null) {
      amount = recoveryProfitPortions[t.id] ?? 0;
    } else {
      final excludeFromTotals =
          categoryById[t.categoryId]?.excludeFromTotals ?? false;
      amount = excludeFromTotals ? 0 : t.amountMinor;
    }
    if (amount > 0) {
      entries.add(ReportableIncome(transaction: t, amountMinor: amount));
    }
  }
  return entries;
}

/// Thành viên nhận khoản INCOME — theo ví khả dụng hoặc theo pool tiết kiệm
/// của họ; `null` nếu đích không thuộc 1 thành viên (vd Quỹ dùng chung).
FamilyMember? incomeRecipient(Transaction t) {
  final refId = t.destinationRefId;
  if (refId == null) return null;
  switch (t.destinationKind) {
    case PoolKind.memberAvailable:
      for (final m in FamilyMember.values) {
        if (m.name == refId) return m;
      }
      return null;
    case PoolKind.memberSavingsAsset:
      return parseSavingsAssetRefId(refId)?.member;
    default:
      return null;
  }
}

/// Tổng thu nhập BÁO CÁO ĐƯỢC của 1 thành viên trong kỳ — cùng ngữ nghĩa
/// với thu nhập gia đình ([computeThreeTotals]): loại Số dư ban đầu, gốc Đi
/// vay và phần hoàn vốn của recovery; chỉ tính lợi nhuận thật của recovery.
int computeMemberIncomeTotal(
  FamilyMember member,
  List<Transaction> transactions,
  List<Category> categories, {
  DateTime? month,
}) {
  var total = 0;
  for (final e in computeReportableIncomeEntries(
    transactions,
    categories,
    month: month,
  )) {
    if (incomeRecipient(e.transaction) == member) total += e.amountMinor;
  }
  return total;
}
