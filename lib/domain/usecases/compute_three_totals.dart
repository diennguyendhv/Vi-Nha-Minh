import '../engine/financial_engine.dart';
import '../entities/category.dart';
import '../entities/transaction.dart';
import '../entities/transaction_type.dart';
import 'compute_obligation_summary.dart';
import 'compute_reportable_income.dart';

/// Thay `FinancialSummary` (V1, 2 tổng) — Financial Core V2 dùng **3 tổng
/// tách biệt** (`docs/financial-core-v2.md` mục 17): Transfer không bao giờ
/// được cộng vào Income/Expense, khác hẳn công thức cũ đã bị audit sai
/// (F-05).
class ThreeTotals {
  const ThreeTotals({
    required this.totalIncome,
    required this.totalExpense,
    required this.totalTransfer,
  });

  final int totalIncome;
  final int totalExpense;
  final int totalTransfer;

  int get balance => totalIncome - totalExpense;

  /// (Thu − Chi) / Thu, làm tròn %. 0 khi không có thu nhập. Đúng vì giờ
  /// `totalExpense` không còn lẫn tiết kiệm/chuyển khoản (F-02 đã sửa).
  int get savingsRatePercent =>
      totalIncome > 0 ? ((balance / totalIncome) * 100).round() : 0;
}

/// Tính 3 tổng cho 1 danh sách giao dịch, tôn trọng `category.excludeFromTotals`
/// (vd "Số dư ban đầu" không tính vào `totalIncome`) và chỉ đếm transaction
/// đang hiệu lực (`isVisible`, bỏ qua bản gốc đã bị hoàn tác/bản reversal nội
/// bộ — xem `docs/financial-core-v2.md` mục 21).
///
/// Phase 8.6B: giao dịch recovery (`recoveryOfTxId != null`) KHÔNG dùng
/// `category.excludeFromTotals` để quyết định đóng góp vào `totalIncome` —
/// dùng [computeRecoveryProfitPortions] để chỉ cộng đúng phần LỢI NHUẬN
/// (vượt chi phí gốc) vào tháng của chính recovery đó, phần bù chi phí gốc
/// vẫn không tính vào `totalIncome` (đúng ý nghĩa gốc của
/// `excludeFromTotals` trên category `hoanTienThuHoi`). Đây là quyết định
/// CẤU TRÚC dựa trên field quan hệ `recoveryOfTxId` (đã có từ Phase 8.6),
/// không phải nhánh if theo `categoryId` cụ thể (CLAUDE.md mục 9).
///
/// Phase 8.7: giao dịch Payable (`obligationId != null`) CŨNG dùng cấu trúc
/// thay vì `category.excludeFromTotals` — TẠO khoản vay (income,
/// `settlementGroupId == null`) không bao giờ là Income thật (tiền vay
/// không phải thu nhập); TẤT TOÁN (expense) chỉ phần LÃI
/// ([computeObligationSettlementInterestPortions]) mới report vào
/// `totalExpense`, phần gốc thì không (đúng Example D/E/F, audit Phase
/// 8.7). Receivable KHÔNG cần nhánh riêng ở đây: gốc là TRANSFER (không
/// đụng Income/Expense theo cấu trúc `switch` sẵn có), lãi đã là 1 dòng
/// INCOME thường (không `obligationId`-excluded — cộng thẳng như income
/// bình thường).
///
/// Truyền [month] để chỉ tính trong 1 tháng cụ thể (theo `transactionDate`,
/// khớp `months/{yearMonth}` — bỏ trống để tính toàn bộ lịch sử).
ThreeTotals computeThreeTotals(
  List<Transaction> transactions,
  List<Category> categories, {
  DateTime? month,
}) {
  final categoryById = {for (final c in categories) c.id: c};
  final obligationInterestPortions =
      computeObligationSettlementInterestPortions(transactions);
  // Income: cùng nguồn sự thật với thu nhập theo thành viên
  // ([computeMemberIncomeTotal]) — xem [computeReportableIncomeEntries] cho
  // quy tắc Payable-opening/recovery/`excludeFromTotals` (F25).
  final income = computeReportableIncomeEntries(
    transactions,
    categories,
    month: month,
  ).fold<int>(0, (s, e) => s + e.amountMinor);
  var expense = 0;
  var transfer = 0;

  for (final t in transactions) {
    if (!isVisible(t)) continue;
    if (month != null &&
        (t.transactionDate.year != month.year ||
            t.transactionDate.month != month.month)) {
      continue;
    }
    switch (t.type) {
      case TransactionType.income:
        break; // đã tính ở [computeReportableIncomeEntries] phía trên.
      case TransactionType.expense:
        if (t.obligationId != null) {
          // Payable — TẤT TOÁN: chỉ phần lãi report được như Expense.
          expense += obligationInterestPortions[t.id] ?? 0;
        } else {
          final excludeFromTotals =
              categoryById[t.categoryId]?.excludeFromTotals ?? false;
          if (!excludeFromTotals) expense += t.amountMinor;
        }
      case TransactionType.transfer:
        transfer += t.amountMinor;
    }
  }

  return ThreeTotals(
    totalIncome: income,
    totalExpense: expense,
    totalTransfer: transfer,
  );
}
