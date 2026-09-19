import '../../domain/repositories/transaction_repository.dart';

/// Wrapper mỏng quanh [TransactionRepository.reverseObligationSettlement] —
/// cùng vai trò `ReverseTransactionUseCase` nhưng hoàn tác ATOMIC cả 2 leg
/// (nếu có) của 1 lần tất toán bằng 1 hành động người dùng duy nhất.
class ReverseObligationSettlementUseCase {
  const ReverseObligationSettlementUseCase(this._repository);

  final TransactionRepository _repository;

  Future<void> call(String anyLegTransactionId) {
    return _repository.reverseObligationSettlement(anyLegTransactionId);
  }
}
