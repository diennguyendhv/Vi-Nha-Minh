import '../../domain/repositories/transaction_repository.dart';

/// Wrapper mỏng quanh [TransactionRepository.updateTransaction] — Phase 4
/// mục 14.
///
/// KHÔNG tự quyết định reversal effect: Repository (đã freeze từ Phase
/// 3/3.1) đã tự phân biệt field ảnh hưởng balance (`amountMinor`/
/// `memberRefId` → đi qua reversal ledger) và field không ảnh hưởng
/// (`categoryId`/`note`/`transactionDate`/`statusId` → update thẳng tại
/// chỗ). Application không lặp lại logic đó, chỉ forward nguyên tham số.
class UpdateTransactionUseCase {
  const UpdateTransactionUseCase(this._repository);

  final TransactionRepository _repository;

  Future<void> call(
    String transactionId, {
    int? amountMinor,
    String? categoryId,
    String? note,
    String? memberRefId,
    DateTime? transactionDate,
    String? statusId,
  }) {
    return _repository.updateTransaction(
      transactionId,
      amountMinor: amountMinor,
      categoryId: categoryId,
      note: note,
      memberRefId: memberRefId,
      transactionDate: transactionDate,
      statusId: statusId,
    );
  }
}
