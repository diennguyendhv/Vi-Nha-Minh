import '../engine/financial_engine.dart';
import '../entities/category.dart';
import '../entities/fund.dart';
import '../entities/transaction.dart';
import 'deletion_check.dart';

/// Id các bước trạng thái ĐÃ NGỪNG và không có giao dịch nào (đang tồn tại
/// trong sổ) tham chiếu `statusId` — an toàn để hiện "Xóa hẳn". Chỉ để HIỂN
/// THỊ, suy ra từ dữ liệu đang xem nên luôn khớp màn hình ngay khi vừa xóa /
/// sửa / ngừng; việc xóa thật vẫn được kiểm tra lại trong DB.
Set<String> computeDeletableStatusIds(
  Iterable<Category> categories,
  Iterable<Transaction> transactions,
) {
  final used = {
    for (final t in transactions)
      if (t.statusId != null) t.statusId!,
  };
  return {
    for (final c in categories)
      for (final s in c.statuses)
        if (!s.isActive && !used.contains(s.id)) s.id,
  };
}

/// Id danh mục ĐÃ NGỪNG an toàn để hiện "Xóa hẳn": không phải Chuyển / danh mục
/// hệ thống nâng cao, không có dòng nào (đang tồn tại) tham chiếu danh mục hoặc
/// bước con của nó. `linkedExpenseCategoryId` là metadata cũ đã ẩn — KHÔNG chặn.
Set<String> computeDeletableCategoryIds(
  Iterable<Category> categories,
  Iterable<Transaction> transactions,
) {
  return {
    for (final c in categories)
      if (!c.isActive &&
          checkCategoryDeletion(c, categories, transactions).canDelete)
        c.id,
  };
}

/// Kết quả dọn lịch sử ẩn: [deleteIds] xoá hẳn; [relinkIds] là dòng đang hiệu lực
/// còn `correctsTxId` trỏ vào dòng bị xoá (phải đặt về null để không treo).
class HiddenHistoryPurge {
  const HiddenHistoryPurge(this.deleteIds, this.relinkIds);

  final Set<String> deleteIds;
  final Set<String> relinkIds;

  bool get isEmpty => deleteIds.isEmpty;
}

bool _isHiddenRow(Transaction t) => t.reversedByTxId != null || t.reversalOfTxId != null;

/// Các dòng ẩn (đã hoàn tác / bản hoàn tác — từ cơ chế cũ) đang giữ dữ liệu khớp
/// [holds]. Họ không còn dòng hiệu lực → xoá cả họ (giao dịch đã "xóa" từ trước).
/// Họ còn dòng hiệu lực (giao dịch đã sửa) → chỉ xoá các dòng ẩn của họ (gốc +
/// hoàn tác triệt tiêu nhau nên số dư không đổi), dòng hiệu lực được giữ.
HiddenHistoryPurge hiddenHistoryPurge(
  bool Function(Transaction) holds,
  List<Transaction> transactions,
) {
  final deleteIds = <String>{};
  final handled = <String>{};
  for (final t in transactions) {
    if (!_isHiddenRow(t) || !holds(t) || handled.contains(t.id)) continue;
    final family = transactionFamilyIds(t.id, transactions);
    handled.addAll(family);
    final members = [for (final x in transactions) if (family.contains(x.id)) x];
    final anyLive = members.any((x) => !_isHiddenRow(x));
    deleteIds.addAll(anyLive ? [for (final x in members) if (_isHiddenRow(x)) x.id] : family);
  }
  final relink = {
    for (final t in transactions)
      if (!deleteIds.contains(t.id) &&
          t.correctsTxId != null &&
          deleteIds.contains(t.correctsTxId))
        t.id,
  };
  return HiddenHistoryPurge(deleteIds, relink);
}

HiddenHistoryPurge hiddenHistoryPurgeForStatus(
  String statusId,
  List<Transaction> transactions,
) => hiddenHistoryPurge((t) => t.statusId == statusId, transactions);

/// Id quỹ ĐÃ NGỪNG an toàn để hiện "Xóa hẳn": không dòng nào (đang tồn tại hoặc
/// lịch sử ẩn) còn chạm quỹ. Dữ liệu HIỆN TẠI — xóa giao dịch cuối cùng của quỹ
/// thì "Xóa hẳn" xuất hiện ngay.
Set<String> computeDeletableFundIds(
  Iterable<Fund> funds,
  Iterable<Category> categories,
  List<Transaction> transactions,
) => {
  for (final f in funds)
    if (!f.isActive && checkFundDeletion(f.id, categories, transactions).canDelete)
      f.id,
};
