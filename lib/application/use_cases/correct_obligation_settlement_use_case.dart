import '../../core/utils/id_generator.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';

/// Wrapper quanh [TransactionRepository.correctObligationSettlement] — sinh
/// id/clientTxId mới cho bản thay thế mỗi lần gọi (giống
/// `UpdateTransactionUseCase`/`buildCorrection`, KHÔNG freeze như command
/// tạo mới — 1 lần sửa luôn là 1 hành động MỚI, không phải retry của hành
/// động cũ).
class CorrectObligationSettlementUseCase {
  const CorrectObligationSettlementUseCase(this._repository);

  final TransactionRepository _repository;

  Future<({Transaction principal, Transaction? interest})> call(
    String anyLegTransactionId, {
    required int newAmountMinor,
    required String categoryId,
    required String interestCategoryId,
  }) {
    return _repository.correctObligationSettlement(
      anyLegTransactionId,
      newAmountMinor: newAmountMinor,
      categoryId: categoryId,
      interestCategoryId: interestCategoryId,
      newPrincipalId: IdGenerator.generate(),
      newPrincipalClientTxId: IdGenerator.generate(),
      newInterestId: IdGenerator.generate(),
      newInterestClientTxId: IdGenerator.generate(),
    );
  }
}
