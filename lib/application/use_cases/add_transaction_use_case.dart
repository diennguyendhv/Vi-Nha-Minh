import '../../domain/entities/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../commands/create_transaction_command.dart';
import '../commands/transaction_from_command.dart';

/// Orchestration DUY NHẤT giữa 1 [CreateTransactionCommand] và
/// [TransactionRepository.addTransaction] — Phase 4 mục 11.
///
/// KHÔNG tính effect/validate financial invariant ở đây — `Transaction`
/// được build thẳng từ command rồi giao hết cho Repository (đã freeze từ
/// Phase 3: gọi `validateNewTransaction`, kiểm tra `InsufficientBalance`,
/// xử lý idempotency `clientTxId`). Lặp lại validate ở đây sẽ biến
/// Application thành "Financial Engine thứ hai" — đúng điều cấm ở mục 3.
///
/// **Retry-safe theo thiết kế:** gọi `call()` nhiều lần với CÙNG 1 instance
/// [command] (không tạo command mới cho mỗi lần gọi lại) sẽ luôn tạo ra
/// đúng 1 `Transaction` với cùng `id`/`clientTxId`/`transactionDate`/
/// `baseCurrencyCode`/payload — chỉ `createdAt` khác nhau giữa các lần gọi
/// (audit timestamp của riêng lần thử đó, KHÔNG phải 1 phần của "logical
/// request", nên không ảnh hưởng `isSameLogicalTransaction` ở Repository —
/// xem `docs/financial-core-v2.md` mục 14 + Phase 3.1/4.1).
///
/// **Cố tình KHÔNG inject/đọc `CurrencyContext` ở đây** (Phase 4.1 mục 7):
/// currency thuộc COMMAND CREATION lifecycle
/// (`CreateTransactionCommandFactory`), không thuộc execution-attempt
/// lifecycle. Nếu use case này tự đọc `CurrencyContext` mỗi lần `call()`
/// chạy, 1 retry có thể vô tình đổi currency giữa 2 lần thử — đúng
/// ambiguity đã phát hiện ở audit retry+currency Phase 4.1.
class AddTransactionUseCase {
  const AddTransactionUseCase(this._repository);

  final TransactionRepository _repository;

  Future<Transaction> call(CreateTransactionCommand command) {
    return _repository.addTransaction(transactionFromCommand(command));
  }
}
