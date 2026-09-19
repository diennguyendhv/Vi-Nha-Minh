import 'obligation_direction.dart';

/// Phase 8.7 — neo giữ metadata của 1 khoản vay/cho vay (Cho Chị Hằng vay,
/// Mượn bạn...), giống hệt vai trò `Fund` cho quỹ: chỉ giữ IDENTITY, KHÔNG
/// cache số tiền gốc/đã trả/outstanding — mọi số liệu tài chính tính động
/// từ `Transaction` (`obligationId`), xem
/// `domain/engine/obligation_settlement.dart` + `compute_obligation_summary.dart`
/// (Invariant 10, cùng nguyên tắc Fund/Category).
///
/// KHÔNG lưu `creationTxId` — giao dịch "tạo khoản vay" tự suy ra được từ
/// hình dạng `Transaction` (`findObligationCreationTransaction`), không cần
/// field trỏ tay riêng (audit Phase 8.7 — giảm bề mặt schema khi không cần
/// thiết, khác `settlementGroupId` trên `Transaction`, vốn KHÔNG suy ra
/// được nên bắt buộc phải lưu — xem audit "atomicity + idempotency").
///
/// Phase 8.8 review: user-facing creation commits metadata and the opening
/// transaction atomically through ObligationRepository. Metadata-only APIs
/// remain for existing callers; the create form must not use a two-step write.
class Obligation {
  const Obligation({
    required this.id,
    required this.counterpartyId,
    required this.direction,
    this.dueDate,
    this.note = '',
    this.isActive = true,
  });

  final String id;
  final String counterpartyId;
  final ObligationDirection direction;

  /// Hẹn trả (nullable) — CHỈ chuẩn bị schema cho Phase 8.7, KHÔNG có
  /// notification/reminder logic ở phase này (audit mục J). `OVERDUE` sau
  /// này derive thuần từ `dueDate != null && dueDate.isBefore(now) &&
  /// outstanding > 0`, không lưu status riêng.
  final DateTime? dueDate;

  final String note;

  /// Soft delete/archive — KHÔNG dùng để suy ra trạng thái tài chính (đó là
  /// việc của `computeObligationSummary`, derived từ ledger).
  final bool isActive;

  Obligation copyWith({
    String? counterpartyId,
    Object? dueDate = _unset,
    String? note,
    bool? isActive,
  }) {
    return Obligation(
      id: id,
      counterpartyId: counterpartyId ?? this.counterpartyId,
      direction: direction,
      dueDate: identical(dueDate, _unset) ? this.dueDate : dueDate as DateTime?,
      note: note ?? this.note,
      isActive: isActive ?? this.isActive,
    );
  }
}

const _unset = Object();
