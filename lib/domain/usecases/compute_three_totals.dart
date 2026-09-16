import '../engine/financial_engine.dart';
import '../entities/category.dart';
import '../entities/transaction.dart';
import '../entities/transaction_type.dart';

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
/// Truyền [month] để chỉ tính trong 1 tháng cụ thể (theo `transactionDate`,
/// khớp `months/{yearMonth}` — bỏ trống để tính toàn bộ lịch sử).
ThreeTotals computeThreeTotals(
  List<Transaction> transactions,
  List<Category> categories, {
  DateTime? month,
}) {
  final categoryById = {for (final c in categories) c.id: c};
  var income = 0;
  var expense = 0;
  var transfer = 0;

  for (final t in transactions) {
    if (!isVisible(t)) continue;
    if (month != null &&
        (t.transactionDate.year != month.year ||
            t.transactionDate.month != month.month)) {
      continue;
    }
    final excludeFromTotals = categoryById[t.categoryId]?.excludeFromTotals ?? false;
    switch (t.type) {
      case TransactionType.income:
        if (!excludeFromTotals) income += t.amountMinor;
      case TransactionType.expense:
        if (!excludeFromTotals) expense += t.amountMinor;
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
