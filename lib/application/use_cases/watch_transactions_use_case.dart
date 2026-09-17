import '../../domain/entities/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';

/// Query tối thiểu — Phase 4 mục 17. Trả TOÀN BỘ transaction (kể cả bản đã
/// hoàn tác/bản reversal nội bộ), đúng contract
/// `TransactionRepository.watchTransactions` — lọc `isVisible`/theo tháng
/// vẫn là việc của tầng gọi (Presentation/use case tổng hợp khác), không
/// lọc sẵn ở đây để tránh giả định trước nhu cầu hiển thị.
class WatchTransactionsUseCase {
  const WatchTransactionsUseCase(this._repository);

  final TransactionRepository _repository;

  Stream<List<Transaction>> call() {
    return _repository.watchTransactions();
  }
}
