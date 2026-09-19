import '../../domain/entities/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../commands/settle_obligation_command.dart';

/// Orchestration DUY NHẤT giữa 1 [SettleObligationCommand] và
/// [TransactionRepository.settleObligation] — cùng vai trò
/// `AddTransactionUseCase` nhưng cho tất toán khoản vay (có thể sinh 1 hoặc
/// 2 dòng atomic). KHÔNG tự tính split gốc/lãi ở đây — Repository làm hết
/// (đã freeze theo audit "atomicity + idempotency" Phase 8.7).
class SettleObligationUseCase {
  const SettleObligationUseCase(this._repository);

  final TransactionRepository _repository;

  Future<({Transaction principal, Transaction? interest})> call(
    SettleObligationCommand command,
  ) {
    return _repository.settleObligation(
      obligationId: command.obligationId,
      direction: command.direction,
      memberRefId: command.memberRefId,
      amountMinor: command.amountMinor,
      transactionDate: command.transactionDate,
      note: command.note,
      categoryId: command.categoryId,
      interestCategoryId: command.interestCategoryId,
      principalId: command.principalId,
      principalClientTxId: command.principalClientTxId,
      interestId: command.interestId,
      interestClientTxId: command.interestClientTxId,
    );
  }
}
