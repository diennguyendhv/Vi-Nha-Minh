import '../../core/constants/advanced_system_categories.dart';
import '../entities/category.dart';
import '../entities/transaction.dart';
import '../entities/transaction_type.dart';

/// Vì sao 1 danh mục / trạng thái chưa xóa hẳn được.
enum DeletionBlockerKind {
  /// Một giao dịch đang hiệu lực còn dùng nó — người dùng mở và sửa/xóa được.
  transaction,

  /// Còn dòng "đã xóa/sửa" theo cơ chế cũ (đang ẩn) giữ nó — dọn được bằng
  /// "Dọn lịch sử đã xóa".
  hiddenHistory,

  /// Danh mục hệ thống (Chuyển / tính năng nâng cao) — không bao giờ xóa hẳn.
  systemCategory,
}

class DeletionBlocker {
  const DeletionBlocker({
    required this.kind,
    this.transactionId,
    this.date,
    this.amountMinor,
    this.categoryName,
    this.statusName,
    this.count = 1,
  });

  final DeletionBlockerKind kind;
  final String? transactionId;
  final DateTime? date;
  final int? amountMinor;
  final String? categoryName;
  final String? statusName;

  /// Số dòng (chỉ có nghĩa với [DeletionBlockerKind.hiddenHistory]).
  final int count;
}

/// Kết quả kiểm tra xóa hẳn: `canDelete` khi không còn blocker nào.
class DeletionCheckResult {
  const DeletionCheckResult(this.blockers);

  final List<DeletionBlocker> blockers;

  bool get canDelete => blockers.isEmpty;

  List<DeletionBlocker> get transactionBlockers => [
    for (final b in blockers)
      if (b.kind == DeletionBlockerKind.transaction) b,
  ];

  bool get hasHiddenHistory =>
      blockers.any((b) => b.kind == DeletionBlockerKind.hiddenHistory);

  /// Chỉ còn lịch sử ẩn (không giao dịch đang hiệu lực, không danh mục hệ thống).
  bool get onlyHiddenHistory =>
      blockers.isNotEmpty &&
      blockers.every((b) => b.kind == DeletionBlockerKind.hiddenHistory);
}

bool _hidden(Transaction t) => t.reversedByTxId != null || t.reversalOfTxId != null;

Iterable<DeletionBlocker> _blockersFor(
  bool Function(Transaction) holds,
  Iterable<Transaction> transactions,
  Map<String, Category> categoryById,
  Map<String, String> statusNameById,
) sync* {
  var hidden = 0;
  final live = <Transaction>[];
  for (final t in transactions) {
    if (!holds(t)) continue;
    if (_hidden(t)) {
      hidden++;
    } else {
      live.add(t);
    }
  }
  live.sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
  for (final t in live) {
    yield DeletionBlocker(
      kind: DeletionBlockerKind.transaction,
      transactionId: t.id,
      date: t.transactionDate,
      amountMinor: t.amountMinor,
      categoryName: categoryById[t.categoryId]?.name,
      statusName: t.statusId == null ? null : statusNameById[t.statusId!],
    );
  }
  if (hidden > 0) {
    yield DeletionBlocker(kind: DeletionBlockerKind.hiddenHistory, count: hidden);
  }
}

Map<String, String> _statusNames(Iterable<Category> categories) => {
  for (final c in categories)
    for (final s in c.statuses) s.id: s.name,
};

/// Chỉ xét DỮ LIỆU HIỆN TẠI (các dòng còn tồn tại). Không có khái niệm "đã từng
/// dùng": giao dịch đã xóa hẳn thì không còn giữ danh mục.
DeletionCheckResult checkCategoryDeletion(
  Category category,
  Iterable<Category> categories,
  Iterable<Transaction> transactions,
) {
  if (category.type == TransactionType.transfer ||
      AdvancedSystemCategories.contains(category.id)) {
    return const DeletionCheckResult([
      DeletionBlocker(kind: DeletionBlockerKind.systemCategory),
    ]);
  }
  final statusIds = {for (final s in category.statuses) s.id};
  return DeletionCheckResult(
    _blockersFor(
      (t) =>
          t.categoryId == category.id ||
          (t.statusId != null && statusIds.contains(t.statusId)),
      transactions,
      {for (final c in categories) c.id: c},
      _statusNames(categories),
    ).toList(),
  );
}

DeletionCheckResult checkStatusDeletion(
  String statusId,
  Iterable<Category> categories,
  Iterable<Transaction> transactions,
) {
  return DeletionCheckResult(
    _blockersFor(
      (t) => t.statusId == statusId,
      transactions,
      {for (final c in categories) c.id: c},
      _statusNames(categories),
    ).toList(),
  );
}
