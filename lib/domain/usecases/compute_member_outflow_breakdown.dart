import '../engine/financial_engine.dart';
import '../entities/family_member.dart';
import '../entities/pool_kind.dart';
import '../entities/transaction.dart';
import '../entities/transaction_type.dart';
import 'compute_expense_breakdown.dart';

/// Tổng "tiền ra" của 1 thành viên theo từng hạng mục — gộp cả EXPENSE
/// (Sinh hoạt, Đầu tư, Tự thưởng, CĐ, DH...) LẪN TRANSFER mà thành viên đó
/// là nguồn (Tiết kiệm nạp, Nạp quỹ, Chuyển tiền cho thành viên khác gửi
/// đi) — đúng nhu cầu xem "đầu tư, tự thưởng, cho đi, tiết kiệm, dâng
/// hiến, chồng đưa vợ bao nhiêu" trong 1 bảng Tổng hợp duy nhất, tách theo
/// từng người (`spec.md`). Không gộp INCOME — xem `computeMemberIncomeTotal`.
///
/// "Chồng đưa vợ" vs "Vợ đưa chồng" không tách thành 2 dòng riêng ở đây —
/// chuyển qua tab thành viên tương ứng (Vợ/Chồng) để xem đúng chiều tiền
/// của người đó, tránh phải thêm khái niệm "breakdown theo chiều" phức tạp
/// hơn cho 1 category duy nhất.
List<CategoryTotal> computeMemberOutflowBreakdown(
  FamilyMember member,
  List<Transaction> transactions, {
  DateTime? month,
}) {
  final totals = <String, int>{};
  for (final t in transactions) {
    if (!isVisible(t)) continue;
    if (t.type == TransactionType.income) continue;
    if (month != null &&
        (t.transactionDate.year != month.year || t.transactionDate.month != month.month)) {
      continue;
    }
    if (t.sourceKind != PoolKind.memberAvailable || t.sourceRefId != member.name) continue;
    totals.update(t.categoryId, (v) => v + t.amountMinor, ifAbsent: () => t.amountMinor);
  }
  final result =
      totals.entries
          .map((e) => CategoryTotal(categoryId: e.key, total: e.value))
          .toList()
        ..sort((a, b) => b.total.compareTo(a.total));
  return result;
}

/// Tổng thu nhập của 1 thành viên trong kỳ — Σ mọi giao dịch INCOME có
/// `destinationRefId == member`. Tách riêng khỏi `computeMemberOutflowBreakdown`
/// vì INCOME không có "hạng mục chi", chỉ cần 1 con số tổng.
int computeMemberIncomeTotal(
  FamilyMember member,
  List<Transaction> transactions, {
  DateTime? month,
}) {
  var total = 0;
  for (final t in transactions) {
    if (!isVisible(t) || t.type != TransactionType.income) continue;
    if (month != null &&
        (t.transactionDate.year != month.year || t.transactionDate.month != month.month)) {
      continue;
    }
    if (t.destinationRefId == member.name) total += t.amountMinor;
  }
  return total;
}
