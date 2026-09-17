import '../../domain/entities/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';

/// Query tối thiểu — Phase 4 mục 17. Trả `null` khi không tìm thấy, đúng
/// contract `TransactionRepository.getTransactionById` (không đổi thành
/// exception ở đây).
class GetTransactionByIdUseCase {
  const GetTransactionByIdUseCase(this._repository);

  final TransactionRepository _repository;

  Future<Transaction?> call(String id) {
    return _repository.getTransactionById(id);
  }
}
