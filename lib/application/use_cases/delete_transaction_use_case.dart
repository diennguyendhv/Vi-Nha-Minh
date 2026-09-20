import '../../domain/repositories/transaction_repository.dart';

/// "Xóa giao dịch" của người dùng = XOÁ THẬT (không tạo giao dịch hoàn tác).
/// Wrapper mỏng quanh [TransactionRepository.deleteTransaction]; mọi lỗi nghiệp
/// vụ (`DeleteWouldOverdrawException`, `TransactionDeleteBlockedException`,
/// `TransactionNotFoundException`) propagate nguyên vẹn để Presentation ánh xạ
/// thành thông điệp dễ hiểu.
class DeleteTransactionUseCase {
  const DeleteTransactionUseCase(this._repository);

  final TransactionRepository _repository;

  Future<void> call(String transactionId) {
    return _repository.deleteTransaction(transactionId);
  }
}
