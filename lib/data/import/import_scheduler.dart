import '../../domain/engine/financial_engine.dart';
import '../../domain/entities/pool_kind.dart';
import 'legacy_import_plan.dart';

/// Kết quả lập lịch GHI (không phải ngày giao dịch).
class ScheduleReport {
  const ScheduleReport({
    required this.order,
    required this.total,
    required this.skipAheadPlacements,
    required this.delayedTransactions,
    required this.minBalances,
  });

  /// Thứ tự GHI.
  final List<PlannedTransaction> order;
  final int total;

  /// Số lần lịch phải bỏ qua giao dịch sớm hơn (đang làm âm pool) để ghi giao dịch
  /// muộn hơn trước.
  final int skipAheadPlacements;

  /// Số giao dịch được ghi MUỘN hơn vị trí theo thứ tự ngày.
  final int delayedTransactions;

  /// Số dư nhỏ nhất của từng pool bảo vệ trong suốt lịch (luôn ≥ 0).
  final Map<String, int> minBalances;
}

/// Lập lịch GHI tất định để mọi lần ghi qua repository đều không làm pool bảo vệ
/// nào âm — KHÔNG đổi ngày giao dịch, KHÔNG tắt/bỏ qua kiểm tra của Financial Core.
///
/// **Quy tắc (không ngẫu nhiên, không thử lại):** sắp toàn bộ giao dịch theo
/// `(ngày, số dòng nguồn, id)`; lặp lại: duyệt từ đầu danh sách còn lại, ghi
/// giao dịch ĐẦU TIÊN mà pool nguồn đủ tiền ([wouldGoNegative] = false, dùng đúng
/// hàm của Financial Core); nếu không có giao dịch nào ghi được → [StateError]
/// (không có thứ tự an toàn — dừng, KHÔNG nhập).
ScheduleReport scheduleImport(List<PlannedTransaction> planned) {
  final pending = [...planned]
    ..sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      final byRow = a.sourceRow.compareTo(b.sourceRow);
      return byRow != 0 ? byRow : a.id.compareTo(b.id);
    });
  final chronoIndex = {for (var i = 0; i < pending.length; i++) pending[i].id: i};

  final balances = <PoolRef, int>{};
  final minBal = <String, int>{};
  final order = <PlannedTransaction>[];
  var skipAhead = 0;

  while (pending.isNotEmpty) {
    var picked = -1;
    for (var i = 0; i < pending.length; i++) {
      final t = pending[i];
      final violates = t.sourceKind != PoolKind.external &&
          wouldGoNegative(
            currentBalances: balances,
            kind: t.sourceKind,
            refId: t.sourceRefId,
            delta: -t.amountMinor,
          );
      if (!violates) {
        picked = i;
        break;
      }
    }
    if (picked < 0) {
      throw StateError(
        'Không có thứ tự ghi an toàn: ${pending.length} giao dịch còn lại đều làm '
        'pool nguồn âm (đầu tiên: dòng ${pending.first.sourceRow}).',
      );
    }
    if (picked > 0) skipAhead++;
    final t = pending.removeAt(picked);
    applyEffect(t.toDomain(), 1, balances);
    for (final e in balances.entries) {
      final k = '${e.key.$1.name}|${e.key.$2}';
      final cur = minBal[k];
      if (cur == null || e.value < cur) minBal[k] = e.value;
    }
    order.add(t);
  }

  var delayed = 0;
  for (var pos = 0; pos < order.length; pos++) {
    if (pos > chronoIndex[order[pos].id]!) delayed++;
  }
  return ScheduleReport(
    order: order,
    total: order.length,
    skipAheadPlacements: skipAhead,
    delayedTransactions: delayed,
    minBalances: minBal,
  );
}
