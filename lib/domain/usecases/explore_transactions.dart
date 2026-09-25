import '../../core/utils/text_search.dart';
import '../engine/financial_engine.dart';
import '../entities/category.dart';
import '../entities/transaction.dart';
import '../entities/transaction_type.dart';
import '../entities/pool_kind.dart';
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

/// Khóa sắp xếp của Transaction Explorer (chỉ có 2).
enum SortKey {
  date('Ngày'),
  amount('Số tiền');

  const SortKey(this.label);
  final String label;
}

/// 1 điều kiện sắp xếp: khóa + đúng 1 chiều.
class SortRule {
  const SortRule(this.key, {this.ascending = false});

  final SortKey key;
  final bool ascending;

  SortRule flipped() => SortRule(key, ascending: !ascending);

  @override
  bool operator ==(Object other) =>
      other is SortRule && other.key == key && other.ascending == ascending;

  @override
  int get hashCode => Object.hash(key, ascending);
}

/// Sắp xếp của Transaction Explorer, kiểu Excel "Sort by / Then by": danh sách
/// [rules] theo THỨ TỰ ƯU TIÊN (phần tử đầu = ưu tiên 1). Người dùng chọn Ngày
/// và/hoặc Số tiền — **luôn có ít nhất 1 khóa**, mỗi khóa tối đa 1 lần, mỗi khóa
/// đúng 1 chiều (↑/↓). Khóa không bật KHÔNG được ngầm làm khóa phụ.
///
/// Khóa Ngày so theo NGÀY LỊCH (giờ trong ngày không lấn khóa sau). Khi mọi khóa
/// bật đều bằng nhau dùng thời điểm nhập, rồi id, theo chiều Ngày (hoặc
/// chiều khóa đầu nếu không bật Ngày).
///
/// Mặc định: chỉ Ngày ↓ (mới nhất trước).
class ExplorerSort {
  const ExplorerSort(this.rules);

  /// Mặc định: chỉ Ngày ↓.
  static const defaultSort = ExplorerSort([SortRule(SortKey.date)]);

  final List<SortRule> rules;

  bool get isDefault => this == defaultSort;

  /// Có khóa [key] đang bật không.
  bool uses(SortKey key) => rules.any((r) => r.key == key);

  /// Chiều của khóa [key] nếu đang bật.
  bool? ascendingOf(SortKey key) {
    for (final r in rules) {
      if (r.key == key) return r.ascending;
    }
    return null;
  }

  /// Dạng lưu bền: "date:desc,amount:asc" (theo thứ tự ưu tiên).
  String encode() =>
      [for (final r in rules) '${r.key.name}:${r.ascending ? 'asc' : 'desc'}']
          .join(',');

  /// Đọc lại [encode]. Sai định dạng / rỗng / trùng khóa → [defaultSort].
  static ExplorerSort decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return defaultSort;
    final rules = <SortRule>[];
    for (final part in raw.split(',')) {
      final kv = part.split(':');
      if (kv.length != 2) return defaultSort;
      final key = SortKey.values.where((k) => k.name == kv[0]).firstOrNull;
      if (key == null || (kv[1] != 'asc' && kv[1] != 'desc'))
        return defaultSort;
      if (rules.any((r) => r.key == key)) return defaultSort;
      rules.add(SortRule(key, ascending: kv[1] == 'asc'));
    }
    return rules.isEmpty ? defaultSort : ExplorerSort(rules);
  }

  @override
  bool operator ==(Object other) =>
      other is ExplorerSort && encode() == other.encode();

  @override
  int get hashCode => encode().hashCode;
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
    this.memberId,
    this.categoryIds = const {},
    this.statusIds = const {},
    this.types = const {},
    this.poolKinds = const {},
    this.fundIds = const {},
    this.includeNoStatus = false,
    this.query = '',
    this.sort = ExplorerSort.defaultSort,
  });

  /// Khoảng ngày (bao gồm 2 đầu, so theo NGÀY). `null` = không giới hạn.
  final DateTime? from;
  final DateTime? to;
  final String? memberId;
  final Set<String> categoryIds;
  final Set<String> statusIds;

  /// Main financial type, kept distinct from report category groups.
  final Set<TransactionType> types;

  /// Contextual source/destination filter (Fund, Savings, …). A transaction
  /// matches when either endpoint uses one of these pools.
  final Set<PoolKind> poolKinds;

  /// Specific Fund identifiers. Kept separate from [poolKinds] so a user can
  /// find one Fund without hiding other canonical transfer rows by default.
  final Set<String> fundIds;

  /// Chọn cả các giao dịch KHÔNG có trạng thái (`statusId == null`).
  final bool includeNoStatus;
  final String query;

  /// Sắp xếp (Ngày và/hoặc Số tiền, theo thứ tự ưu tiên); mặc định chỉ Ngày ↓.
  final ExplorerSort sort;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static const _keep = Object();

  TransactionFilter copyWith({
    Object? from = _keep,
    Object? to = _keep,
    Object? memberId = _keep,
    Set<String>? categoryIds,
    Set<String>? statusIds,
    Set<TransactionType>? types,
    Set<PoolKind>? poolKinds,
    Set<String>? fundIds,
    bool? includeNoStatus,
    String? query,
    ExplorerSort? sort,
  }) => TransactionFilter(
    from: identical(from, _keep) ? this.from : from as DateTime?,
    to: identical(to, _keep) ? this.to : to as DateTime?,
    memberId: identical(memberId, _keep) ? this.memberId : memberId as String?,
    categoryIds: categoryIds ?? this.categoryIds,
    statusIds: statusIds ?? this.statusIds,
    types: types ?? this.types,
    poolKinds: poolKinds ?? this.poolKinds,
    fundIds: fundIds ?? this.fundIds,
    includeNoStatus: includeNoStatus ?? this.includeNoStatus,
    query: query ?? this.query,
    sort: sort ?? this.sort,
  );

  TransactionFilter withRange(DateTime? from, DateTime? to) => copyWith(
    from: from == null ? null : _day(from),
    to: to == null ? null : _day(to),
  );

  TransactionFilter withMember(String? value) => copyWith(memberId: value);

  TransactionFilter withCategories(Set<String> value) =>
      copyWith(categoryIds: {...value});

  TransactionFilter withStatuses(Set<String> ids, {bool includeNone = false}) =>
      copyWith(statusIds: {...ids}, includeNoStatus: includeNone);

  TransactionFilter withTypes(Set<TransactionType> value) =>
      copyWith(types: {...value});

  TransactionFilter withPoolKinds(Set<PoolKind> value) =>
      copyWith(poolKinds: {...value});

  TransactionFilter withFunds(Set<String> value) =>
      copyWith(fundIds: {...value});

  TransactionFilter withQuery(String value) => copyWith(query: value);

  TransactionFilter withSort(ExplorerSort value) => copyWith(sort: value);

  bool get hasStatusFilter => statusIds.isNotEmpty || includeNoStatus;

  /// Đang có điều kiện nào ngoài khoảng ngày không (để hiện "Xoá bộ lọc").
  bool get hasNonDateFilter =>
      memberId != null ||
      categoryIds.isNotEmpty ||
      types.isNotEmpty ||
      poolKinds.isNotEmpty ||
      fundIds.isNotEmpty ||
      hasStatusFilter ||
      query.trim().isNotEmpty ||
      !sort.isDefault;

  /// Số điều kiện "nâng cao" (danh mục/trạng thái) — hiện trên nút Bộ lọc.
  int get advancedCount =>
      (categoryIds.isNotEmpty ? 1 : 0) +
      (hasStatusFilter ? 1 : 0) +
      (types.isNotEmpty ? 1 : 0) +
      (poolKinds.isNotEmpty ? 1 : 0) +
      (fundIds.isNotEmpty ? 1 : 0);
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
bool involvesMember(Transaction t, String memberId) {
  switch (t.type) {
    case TransactionType.income:
      return incomeRecipient(t) == memberId;
    case TransactionType.expense:
      return expenseSpender(t) == memberId;
    case TransactionType.transfer:
      return expenseSpender(t) == memberId || incomeRecipient(t) == memberId;
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
    if (filter.memberId != null && !involvesMember(t, filter.memberId!))
      continue;
    if (filter.types.isNotEmpty && !filter.types.contains(t.type)) continue;
    if (filter.poolKinds.isNotEmpty &&
        !filter.poolKinds.contains(t.sourceKind) &&
        !filter.poolKinds.contains(t.destinationKind)) {
      continue;
    }
    if (filter.fundIds.isNotEmpty &&
        !((t.sourceKind == PoolKind.fund &&
                filter.fundIds.contains(t.sourceRefId)) ||
            (t.destinationKind == PoolKind.fund &&
                filter.fundIds.contains(t.destinationRefId)))) {
      continue;
    }
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

/// Sắp xếp theo [ExplorerSort.rules] theo đúng thứ tự ưu tiên. Chỉ các khóa ĐANG BẬT
/// tham gia; khi tất cả bằng nhau dùng createdAt rồi id theo chiều Ngày,
/// hoặc chiều khóa đầu nếu không bật Ngày. Giờ phát sinh không phải giờ nhập.
void _sortRows(List<Transaction> rows, ExplorerSort sort) {
  DateTime dayOf(Transaction t) => DateTime(
    t.transactionDate.year,
    t.transactionDate.month,
    t.transactionDate.day,
  );

  rows.sort((a, b) {
    for (final rule in sort.rules) {
      final c = switch (rule.key) {
        SortKey.date => dayOf(a).compareTo(dayOf(b)),
        SortKey.amount => a.amountMinor.compareTo(b.amountMinor),
      };
      if (c != 0) return rule.ascending ? c : -c;
    }
    final byCreated = a.createdAt.compareTo(b.createdAt);
    final tie = byCreated != 0 ? byCreated : a.id.compareTo(b.id);
    final ascending = sort.ascendingOf(SortKey.date) ??
        (sort.rules.isEmpty ? false : sort.rules.first.ascending);
    return ascending ? tie : -tie;
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

/// Danh mục có thể lọc: mọi danh mục ĐANG DÙNG (danh mục hệ thống nâng cao chỉ khi còn giao dịch)
/// + danh mục đã ngừng nhưng còn giao dịch (để tìm lại lịch sử). Danh mục ngừng
/// không còn giao dịch thì không hiện để đỡ rối. Nhóm hiển thị theo nhóm chính.
List<ExplorerOption> explorerCategoryOptions(
  List<Category> categories,
  List<Transaction> transactions, {
  Set<String> hiddenCategoryIds = const {},
}) {
  final used = {
    for (final t in transactions)
      if (isVisible(t)) t.categoryId,
  };
  final out = <ExplorerOption>[];
  for (final c in categories) {
    // Danh mục hệ thống nâng cao chỉ hiện khi CÒN giao dịch dùng nó (để không có
    // lịch sử nào không tìm lại được); không dùng thì ẩn cho khỏi rối.
    if (hiddenCategoryIds.contains(c.id) && !used.contains(c.id)) continue;
    if (!c.isActive && !used.contains(c.id)) continue;
    final group = categoryGroupOf(c, hiddenCategoryIds);
    out.add(
      ExplorerOption(
        id: c.id,
        label: c.isActive ? c.name : '${c.name} (đã ngừng)',
        groupLabel:
            group?.label ??
            (hiddenCategoryIds.contains(c.id) ? 'Nâng cao' : 'Chuyển'),
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
  String memberId,
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
  memberId: memberId,
).netIncome;
