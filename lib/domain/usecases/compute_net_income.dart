import '../engine/financial_engine.dart';
import '../entities/category.dart';
import '../entities/transaction.dart';

/// "Thu nhập ròng" (`docs/financial-core-v2.md` mục 17) — CHỈ áp dụng cho
/// danh mục Thu có `linkedExpenseCategoryId` (vd "Học phí" liên kết "Trả
/// lương giáo viên"). Trả về `null` khi [incomeCategory] chưa liên kết gì.
///
/// = Tổng thu (`incomeCategory`) − Tổng chi (`linkedExpenseCategory`, MỌI
/// `statusId`, vì tiền đã bị trừ khỏi `availableBalance` ngay lúc tạo giao
/// dịch — status chỉ là nhãn tiến độ, không phải mốc tiền rời đi).
///
/// Đây thuần là số hiển thị thêm (report-only) — KHÔNG đổi Total
/// Income/Total External Expense/Total Assets ở `compute_three_totals.dart`.
///
/// Truyền [month] để xem theo từng tháng (vd "doanh thu hàng tháng") —
/// bỏ trống để tính suốt lịch sử (mặc định trong màn Danh mục).
int? computeNetIncome(
  Category incomeCategory,
  Category? linkedExpenseCategory,
  List<Transaction> transactions, {
  DateTime? month,
}) {
  if (linkedExpenseCategory == null) return null;

  var gross = 0;
  var linkedExpense = 0;
  for (final t in transactions) {
    if (!isVisible(t)) continue;
    if (month != null &&
        (t.transactionDate.year != month.year || t.transactionDate.month != month.month)) {
      continue;
    }
    if (t.categoryId == incomeCategory.id) gross += t.amountMinor;
    if (t.categoryId == linkedExpenseCategory.id) linkedExpense += t.amountMinor;
  }
  return gross - linkedExpense;
}
