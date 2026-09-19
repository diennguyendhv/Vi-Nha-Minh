import '../../core/utils/text_search.dart';
import '../engine/financial_engine.dart';
import '../entities/category.dart';
import '../entities/family_member.dart';
import '../entities/transaction.dart';
import '../entities/transaction_type.dart';
import 'compute_grouped_totals.dart';
import 'compute_reportable_income.dart';

/// 4 nhóm chính Thu/Chi (xem `Category.groupKey` / `excludeFromTotals`).
enum MainGroup {
  revenue('Doanh thu'),
  otherInflow('Khoản thu khác'),
  spending('Chi tiêu'),
  businessExpense('Chi phí kinh doanh');

  const MainGroup(this.label);
  final String label;

  bool get isIncome => this == revenue || this == otherInflow;
}

/// Nhóm chính của 1 giao dịch. `null` cho Chuyển và cho danh mục thuộc tính
/// năng nâng cao ([hiddenCategoryIds], vd Vay/Hoàn tiền — chỉ hiện khi KHÔNG
/// chọn nhóm nào). Nhóm luôn suy từ cờ của Category, không từ tên/Ghi chú.
MainGroup? mainGroupOf(
  Transaction t,
  Category? category, {
  Set<String> hiddenCategoryIds = const {},
}) {
  if (category == null || hiddenCategoryIds.contains(category.id)) return null;
  switch (t.type) {
    case TransactionType.income:
      return category.excludeFromTotals
          ? MainGroup.otherInflow
          : MainGroup.revenue;
    case TransactionType.expense:
      return category.isBusinessExpense
          ? MainGroup.businessExpense
          : MainGroup.spending;
    case TransactionType.transfer:
      return null;
  }
}

/// Bộ lọc của Transaction Explorer. Mọi điều kiện KẾT HỢP bằng AND (giao).
/// Bất biến: danh mục phải thuộc nhóm đang chọn, trạng thái phải thuộc danh
/// mục đang chọn — các hàm `with*` tự xoá lựa chọn cũ không còn hợp lệ.
class TransactionFilter {
  const TransactionFilter({
    this.from,
    this.to,
    this.member,
    this.group,
    this.categoryId,
    this.statusId,
    this.query = '',
  });

  /// Khoảng ngày (bao gồm 2 đầu, so theo NGÀY). `null` = không giới hạn.
  final DateTime? from;
  final DateTime? to;
  final FamilyMember? member;
  final MainGroup? group;
  final String? categoryId;
  final String? statusId;
  final String query;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  TransactionFilter withRange(DateTime? from, DateTime? to) =>
      TransactionFilter(
        from: from == null ? null : _day(from),
        to: to == null ? null : _day(to),
        member: member,
        group: group,
        categoryId: categoryId,
        statusId: statusId,
        query: query,
      );

  TransactionFilter withMember(FamilyMember? value) => TransactionFilter(
    from: from,
    to: to,
    member: value,
    group: group,
    categoryId: categoryId,
    statusId: statusId,
    query: query,
  );

  /// Đổi nhóm chính: nếu danh mục đang chọn không thuộc nhóm mới thì xoá cả
  /// danh mục lẫn trạng thái.
  TransactionFilter withGroup(
    MainGroup? value,
    Map<String, Category> categoryById, {
    Set<String> hiddenCategoryIds = const {},
  }) {
    var keepCategory = categoryId;
    var keepStatus = statusId;
    final current = keepCategory == null ? null : categoryById[keepCategory];
    if (value != null && current != null) {
      final belongs = categoryGroupOf(current, hiddenCategoryIds) == value;
      if (!belongs) {
        keepCategory = null;
        keepStatus = null;
      }
    }
    return TransactionFilter(
      from: from,
      to: to,
      member: member,
      group: value,
      categoryId: keepCategory,
      statusId: keepStatus,
      query: query,
    );
  }

  /// Đổi danh mục: nếu trạng thái đang chọn không thuộc danh mục mới (hoặc
  /// danh mục mới không có trạng thái) thì xoá trạng thái.
  TransactionFilter withCategory(
    String? value,
    Map<String, Category> categoryById,
  ) {
    var keepStatus = statusId;
    if (value == null || categoryById[value]?.statusById(statusId) == null) {
      keepStatus = null;
    }
    return TransactionFilter(
      from: from,
      to: to,
      member: member,
      group: group,
      categoryId: value,
      statusId: keepStatus,
      query: query,
    );
  }

  TransactionFilter withStatus(String? value) => TransactionFilter(
    from: from,
    to: to,
    member: member,
    group: group,
    categoryId: categoryId,
    statusId: value,
    query: query,
  );

  TransactionFilter withQuery(String value) => TransactionFilter(
    from: from,
    to: to,
    member: member,
    group: group,
    categoryId: categoryId,
    statusId: statusId,
    query: value,
  );

  /// Đang có điều kiện nào ngoài khoảng ngày không (để hiện "Xoá bộ lọc").
  bool get hasNonDateFilter =>
      member != null ||
      group != null ||
      categoryId != null ||
      statusId != null ||
      query.trim().isNotEmpty;

  /// Số điều kiện "nâng cao" (nhóm/danh mục/trạng thái) — hiện trên nút Bộ lọc.
  int get advancedCount =>
      (group != null ? 1 : 0) +
      (categoryId != null ? 1 : 0) +
      (statusId != null ? 1 : 0);
}

/// Nhóm chính của 1 DANH MỤC (dùng để lọc danh sách danh mục theo nhóm).
MainGroup? categoryGroupOf(Category c, Set<String> hiddenCategoryIds) {
  if (hiddenCategoryIds.contains(c.id)) return null;
  switch (c.type) {
    case TransactionType.income:
      return c.excludeFromTotals ? MainGroup.otherInflow : MainGroup.revenue;
    case TransactionType.expense:
      return c.isBusinessExpense
          ? MainGroup.businessExpense
          : MainGroup.spending;
    case TransactionType.transfer:
      return null;
  }
}

/// Kết quả Explorer: các dòng khớp (mới nhất lên đầu) + tổng của CHÍNH tập
/// đang xem. `inflow` = tổng các dòng Thu, `outflow` = tổng các dòng Chi;
/// Chuyển chỉ được đếm vào [count], không vào Thu/Chi.
class ExplorerResult {
  const ExplorerResult({
    required this.rows,
    required this.inflow,
    required this.outflow,
  });

  final List<Transaction> rows;
  final int inflow;
  final int outflow;

  int get count => rows.length;
}

/// Người liên quan tới giao dịch (để lọc theo Vợ/Chồng): Thu → người nhận,
/// Chi → người chi, Chuyển → người gửi HOẶC người nhận.
bool involvesMember(Transaction t, FamilyMember member) {
  switch (t.type) {
    case TransactionType.income:
      return incomeRecipient(t) == member;
    case TransactionType.expense:
      return expenseSpender(t) == member;
    case TransactionType.transfer:
      return expenseSpender(t) == member || incomeRecipient(t) == member;
  }
}

/// Lọc + tổng cho Transaction Explorer. Chỉ đọc dữ liệu đã có: chỉ đếm giao
/// dịch đang hiệu lực (`isVisible`), không sửa gì, không parse Note (chỉ
/// khớp chuỗi con không phân biệt hoa/thường và dấu tiếng Việt — xem
/// `foldForSearch`).
ExplorerResult exploreTransactions(
  List<Transaction> transactions,
  List<Category> categories,
  TransactionFilter filter, {
  Set<String> hiddenCategoryIds = const {},
}) {
  final categoryById = {for (final c in categories) c.id: c};
  final q = foldForSearch(filter.query);
  final rows = <Transaction>[];
  var inflow = 0;
  var outflow = 0;

  for (final t in transactions) {
    if (!isVisible(t)) continue;
    final day = DateTime(
      t.transactionDate.year,
      t.transactionDate.month,
      t.transactionDate.day,
    );
    if (filter.from != null && day.isBefore(filter.from!)) continue;
    if (filter.to != null && day.isAfter(filter.to!)) continue;
    if (filter.member != null && !involvesMember(t, filter.member!)) continue;
    if (filter.group != null &&
        mainGroupOf(
              t,
              categoryById[t.categoryId],
              hiddenCategoryIds: hiddenCategoryIds,
            ) !=
            filter.group) {
      continue;
    }
    if (filter.categoryId != null && t.categoryId != filter.categoryId) {
      continue;
    }
    if (filter.statusId != null && t.statusId != filter.statusId) continue;
    if (q.isNotEmpty && !foldForSearch(t.note).contains(q)) continue;

    rows.add(t);
    if (t.type == TransactionType.income) {
      inflow += t.amountMinor;
    } else if (t.type == TransactionType.expense) {
      outflow += t.amountMinor;
    }
  }

  rows.sort((a, b) {
    final byDate = b.transactionDate.compareTo(a.transactionDate);
    return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
  });
  return ExplorerResult(rows: rows, inflow: inflow, outflow: outflow);
}

/// Thu nhập ròng của 1 thành viên trong [month] = Doanh thu người đó nhận −
/// Chi phí kinh doanh người đó chi. KHÔNG trừ Chi tiêu, KHÔNG cộng Khoản thu
/// khác, KHÔNG chia đôi số liệu cả nhà.
int computeMemberNetIncome(
  FamilyMember member,
  List<Transaction> transactions,
  List<Category> categories, {
  DateTime? month,
}) => computeGroupedTotals(
  transactions,
  categories,
  month: month,
  member: member,
).netIncome;
