import '../../domain/repositories/transaction_repository.dart';

/// Đổi status của 1 giao dịch — Phase 4 mục 16.
///
/// Status ≠ Financial State (Invariant 9): gọi thẳng
/// `TransactionRepository.updateTransaction(transactionId, statusId: ...)`
/// — đường update-thẳng-tại-chỗ đã có sẵn từ Phase 1/3 (KHÔNG đi qua
/// reversal ledger, KHÔNG đổi balance, chỉ update `statusId` +
/// `statusUpdatedAt`). Repository contract hiện tại đã đủ sạch cho use case
/// này — không cần thay đổi frozen contract.
class ChangeTransactionStatusUseCase {
  const ChangeTransactionStatusUseCase(this._repository);

  final TransactionRepository _repository;

  Future<void> call(String transactionId, String statusId) {
    return _repository.updateTransaction(transactionId, statusId: statusId);
  }
}
