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

/// Sắp xếp của Transaction Explorer — 2 TẦNG cố định, kiểu Excel:
/// **ưu tiên 1 = Ngày** (theo ngày LỊCH), **ưu tiên 2 = Số tiền** (chỉ để xếp các
/// giao dịch CÙNG ngày). Số tiền không bao giờ được xếp trước Ngày, không có tầng
/// thứ 3, không đổi thứ tự ưu tiên.
///
/// Mặc định: Ngày ↓ (mới nhất trước), Số tiền ↓ (lớn trước trong từng ngày).
class ExplorerSort {
  const ExplorerSort({this.dateAscending = false, this.amountAscending = false});

  final bool dateAscending;
  final bool amountAscending;

  bool get isDefault => !dateAscending && !amountAscending;

  ExplorerSort copyWith({bool? dateAscending, bool? amountAscending}) =>
      ExplorerSort(
        dateAscending: dateAscending ?? this.dateAscending,
        amountAscending: amountAscending ?? this.amountAscending,
      );

  @override
  bool operator ==(Object other) =>
      other is ExplorerSort &&
      other.dateAscending == dateAscending &&
      other.amountAscending == amountAscending;

  @override
  int get hashCode => Object.hash(dateAscending, amountAscending);
}

/// Bộ lọc của Transaction Explorer, kiểu Excel.
///
/// - **OR trong cùng 1 chiều** (nhiều danh mục / nhiều trạng thái), **AND giữa
///   các chiều** (thời gian, thành viên, danh mục, trạng thái, số tiền, ghi chú).
/// - Các chiều ĐỘC LẬP: không chiều nào tự xoá/đổi chiều khác, thứ tự chọn
///   không ảnh hưởng kết quả. Không giao nhau → 0 kết quả (bình thường).
/// - Chiều rỗng = không lọc chiều đó. Trạng thái: rỗng và không chọn "Không có
///   trạng thái" = mọi trạng thái.
class TransactionFilter {
  const TransactionFilter({
    this.from,
    this.to,
    this.member,
    this.categoryIds = const {},
    this.statusIds = const {},
    this.includeNoStatus = false,
    this.query = '',
    this.sort = const ExplorerSort(),
  });

  /// Khoảng ngày (bao gồm 2 đầu, so theo NGÀY). `null` = không giới hạn.
  final DateTime? from;
  final DateTime? to;
  final FamilyMember? member;
  final Set<String> categoryIds;
  final Set<String> statusIds;

  /// Chọn cả các giao dịch KHÔNG có trạng thái (`statusId == null`).
  final bool includeNoStatus;
  final String query;

  /// Thứ tự sắp xếp 2 tầng (Ngày rồi Số tiền); mặc định Ngày ↓ · Số tiền ↓.
  final ExplorerSort sort;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static const _keep = Object();

  TransactionFilter copyWith({
    Object? from = _keep,
    Object? to = _keep,
    Object? member = _keep,
    Set<String>? categoryIds,
    Set<String>? statusIds,
    bool? includeNoStatus,
    String? query,
    ExplorerSort? sort,
  }) => TransactionFilter(
    from: identical(from, _keep) ? this.from : from as DateTime?,
    to: identical(to, _keep) ? this.to : to as DateTime?,
    member: identical(member, _keep) ? this.member : member as FamilyMember?,
    categoryIds: categoryIds ?? this.categoryIds,
    statusIds: statusIds ?? this.statusIds,
    includeNoStatus: includeNoStatus ?? this.includeNoStatus,
    query: query ?? this.query,
    sort: sort ?? this.sort,
  );

  TransactionFilter withRange(DateTime? from, DateTime? to) => copyWith(
    from: from == null ? null : _day(from),
    to: to == null ? null : _day(to),
  );

  TransactionFilter withMember(FamilyMember? value) => copyWith(member: value);

  TransactionFilter withCategories(Set<String> value) =>
      copyWith(categoryIds: {...value});

  TransactionFilter withStatuses(Set<String> ids, {bool includeNone = false}) =>
      copyWith(statusIds: {...ids}, includeNoStatus: includeNone);

  TransactionFilter withQuery(String value) => copyWith(query: value);

  TransactionFilter withSort(ExplorerSort value) => copyWith(sort: value);

  bool get hasStatusFilter => statusIds.isNotEmpty || includeNoStatus;

  /// Đang có điều kiện nào ngoài khoảng ngày không (để hiện "Xoá bộ lọc").
  bool get hasNonDateFilter =>
      member != null ||
      categoryIds.isNotEmpty ||
      hasStatusFilter ||
      query.trim().isNotEmpty ||
      !sort.isDefault;

  /// Số điều kiện "nâng cao" (danh mục/trạng thái) — hiện trên nút Bộ lọc.
  int get advancedCount =>
      (categoryIds.isNotEmpty ? 1 : 0) + (hasStatusFilter ? 1 : 0);
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

/// Lọc + sắp xếp + tổng cho Transaction Explorer. Chỉ đọc dữ liệu đã có: chỉ
/// đếm giao dịch đang hiệu lực (`isVisible`), không sửa gì, không parse Note
/// (chỉ khớp chuỗi con không phân biệt hoa/thường và dấu tiếng Việt — xem
/// `foldForSearch`). Kết quả KHÔNG phụ thuộc thứ tự người dùng chọn điều kiện.
ExplorerResult exploreTransactions(
  List<Transaction> transactions,
  List<Category> categories,
  TransactionFilter filter, {
  Set<String> hiddenCategoryIds = const {},
}) {
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
    if (filter.categoryIds.isNotEmpty &&
        !filter.categoryIds.contains(t.categoryId)) {
      continue;
    }
    if (filter.hasStatusFilter) {
      final id = t.statusId;
      final ok = id == null
          ? filter.includeNoStatus
          : filter.statusIds.contains(id);
      if (!ok) continue;
    }
    if (q.isNotEmpty && !foldForSearch(t.note).contains(q)) continue;

    rows.add(t);
    if (t.type == TransactionType.income) {
      inflow += t.amountMinor;
    } else if (t.type == TransactionType.expense) {
      outflow += t.amountMinor;
    }
  }

  _sortRows(rows, filter.sort);
  return ExplorerResult(rows: rows, inflow: inflow, outflow: outflow);
}

/// Sắp xếp 2 tầng: (1) NGÀY LỊCH theo chiều Ngày; (2) trong CÙNG ngày, Số tiền theo
/// chiều Số tiền. Số tiền không bao giờ trộn lẫn các ngày. Khi Ngày và Số tiền
/// đều bằng nhau dùng tie-break CỐ ĐỊNH (giờ trong ngày ↑, giờ tạo ↑, id) — không
/// phụ thuộc chiều Ngày — nên cùng dữ liệu + cùng cấu hình luôn cho cùng thứ tự.
void _sortRows(List<Transaction> rows, ExplorerSort sort) {
  DateTime dayOf(Transaction t) => DateTime(
    t.transactionDate.year,
    t.transactionDate.month,
    t.transactionDate.day,
  );

  rows.sort((a, b) {
    final byDay = dayOf(a).compareTo(dayOf(b));
    if (byDay != 0) return sort.dateAscending ? byDay : -byDay;
    final byAmount = a.amountMinor.compareTo(b.amountMinor);
    if (byAmount != 0) return sort.amountAscending ? byAmount : -byAmount;
    final byTime = a.transactionDate.compareTo(b.transactionDate);
    if (byTime != 0) return byTime;
    final byCreated = a.createdAt.compareTo(b.createdAt);
    return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
  });
}

/// 1 lựa chọn trong bộ chọn Danh mục / Trạng thái.
class ExplorerOption {
  const ExplorerOption({
    required this.id,
    required this.label,
    this.groupLabel = '',
    this.active = true,
  });

  final String id;
  final String label;

  /// Tiêu đề nhóm để hiển thị (chỉ để nhìn cho dễ — không ảnh hưởng chọn nhiều).
  final String groupLabel;
  final bool active;
}

/// Danh mục có thể lọc: mọi danh mục ĐANG DÙNG (trừ danh mục hệ thống nâng cao)
/// + danh mục đã ngừng nhưng còn giao dịch (để tìm lại lịch sử). Danh mục ngừng
/// không còn giao dịch thì không hiện để đỡ rối. Nhóm hiển thị theo nhóm chính.
List<ExplorerOption> explorerCategoryOptions(
  List<Category> categories,
  List<Transaction> transactions, {
  Set<String> hiddenCategoryIds = const {},
}) {
  final used = {for (final t in transactions) if (isVisible(t)) t.categoryId};
  final out = <ExplorerOption>[];
  for (final c in categories) {
    if (hiddenCategoryIds.contains(c.id)) continue;
    if (!c.isActive && !used.contains(c.id)) continue;
    final group = categoryGroupOf(c, hiddenCategoryIds);
    out.add(
      ExplorerOption(
        id: c.id,
        label: c.isActive ? c.name : '${c.name} (đã ngừng)',
        groupLabel: group?.label ?? 'Chuyển',
        active: c.isActive,
      ),
    );
  }
  return out;
}

/// Trạng thái có thể lọc, ĐỘC LẬP với danh mục đã chọn. Nhãn luôn kèm tên danh
/// mục ("ĐD · Cho đi") vì 2 danh mục có thể có trạng thái trùng tên nhưng là 2
/// id khác nhau. Trạng thái đã ngừng chỉ hiện khi còn giao dịch dùng.
List<ExplorerOption> explorerStatusOptions(
  List<Category> categories,
  List<Transaction> transactions,
) {
  final used = {
    for (final t in transactions)
      if (isVisible(t) && t.statusId != null) t.statusId!,
  };
  final out = <ExplorerOption>[];
  for (final c in categories) {
    for (final s in c.statuses) {
      if (!s.isActive && !used.contains(s.id)) continue;
      out.add(
        ExplorerOption(
          id: s.id,
          label: '${s.name}${s.isActive ? '' : ' (đã ẩn)'} · ${c.name}',
          groupLabel: c.name,
          active: s.isActive,
        ),
      );
    }
  }
  return out;
}

/// Thu nhập ròng của 1 thành viên trong [month] = Doanh thu người đó nhận −
/// Chi phí kinh doanh người đó chi. KHÔNG trừ Chi tiêu, KHÔNG cộng Khoản thu
/// khác, KHÔNG chia đôi số liệu cả nhà.
int computeMemberNetIncome(
  FamilyMember member,
  List<Transaction> transactions,
  List<Category> categories, {
  DateTime? month,
  DateTime? from,
  DateTime? to,
}) => computeGroupedTotals(
  transactions,
  categories,
  month: month,
  from: from,
  to: to,
  member: member,
).netIncome;
