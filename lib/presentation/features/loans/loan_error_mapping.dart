import '../../../domain/errors/domain_exceptions.dart';

/// Phase 8.8 — ánh xạ exception (Domain/Repository/Application, đã frozen từ
/// Phase 8.7) sang message tiếng Việt cho người dùng, dùng chung cho mọi màn
/// "Vay & Cho vay". KHÔNG lộ SQLite/tên class/`PoolKind`/`obligationId`/
/// `settlementGroupId`/`clientTxId` (mục 22) — cùng nguyên tắc
/// `add_transaction_sheet.dart`/`transaction_detail_screen.dart` đã áp dụng
/// từ Phase 6/7, chỉ gộp chung 1 hàm vì nhiều màn Phase 8.8 cùng cần.
String mapLoanError(Object error) {
  if (error is InvalidAmountException) return 'Số tiền không hợp lệ.';
  if (error is InsufficientBalanceException) {
    return 'Không đủ số dư để thực hiện.';
  }
  if (error is SameSourceDestinationException) {
    return 'Nguồn và đích không được trùng nhau.';
  }
  if (error is ObligationCreationNotFoundException) {
    return 'Khoản vay không còn tồn tại.';
  }
  if (error is SettlementIntegrityException) {
    return 'Dữ liệu khoản vay không nhất quán, vui lòng tải lại.';
  }
  if (error is NotLatestSettlementException) {
    return 'Lần thanh toán này không thể sửa vì đã có lần thanh toán mới hơn.';
  }
  if (error is AlreadyReversedException) {
    return 'Khoản này đã được hoàn tác hoặc tất toán trước đó.';
  }
  if (error is TransactionNotFoundException) {
    return 'Khoản vay không còn tồn tại.';
  }
  if (error is CounterpartyHasOpenObligationsException) {
    return 'Người này vẫn còn khoản vay đang mở.';
  }
  if (error is ClientTxIdConflictException) {
    return 'Thao tác bị xung đột, vui lòng thử lại.';
  }
  if (error is PersistenceConstraintException) {
    return 'Dữ liệu tham chiếu không hợp lệ, vui lòng thử lại.';
  }
  if (error is PersistenceException) {
    return 'Có lỗi khi lưu dữ liệu, vui lòng thử lại.';
  }
  return 'Có lỗi xảy ra, vui lòng thử lại.';
}
