import '../../domain/repositories/transaction_repository.dart';

/// Wrapper mỏng quanh [TransactionRepository.reverseTransaction] — Phase 4
/// mục 15.
///
/// Không tự build reversal ở Application — Repository (dùng
/// `buildReversal` từ Financial Engine, đã freeze) chịu trách nhiệm toàn bộ
/// orchestration. `TransactionNotFoundException`/`AlreadyReversedException`
/// propagate nguyên vẹn, không bị bắt/đổi thành string ở đây (mục 15/21).
class ReverseTransactionUseCase {
  const ReverseTransactionUseCase(this._repository);

  final TransactionRepository _repository;

  Future<void> call(String transactionId) {
    return _repository.reverseTransaction(transactionId);
  }
}
