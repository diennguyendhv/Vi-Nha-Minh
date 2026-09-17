import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/commands/create_transaction_command_factory.dart';
import '../../application/use_cases/add_transaction_use_case.dart';
import '../../application/use_cases/change_transaction_status_use_case.dart';
import '../../application/use_cases/get_transaction_by_id_use_case.dart';
import '../../application/use_cases/reverse_transaction_use_case.dart';
import '../../application/use_cases/update_transaction_use_case.dart';
import '../../application/use_cases/watch_transactions_use_case.dart';
import '../../data/repositories/local_transaction_repository.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';
import 'currency_providers.dart';
import 'database_provider.dart';

// Giai đoạn A: luôn dùng LocalTransactionRepository (SQLite trên máy).
// Giai đoạn B sẽ đổi provider này để chọn Local hay Firestore dựa vào
// syncMode của gia đình hiện tại. Application/Presentation phụ thuộc
// abstraction `TransactionRepository`, không phụ thuộc type cụ thể này.
final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return LocalTransactionRepository(db);
});

/// Đường tạo `CreateTransactionCommand` chuẩn (Phase 5 mục 7) — đọc
/// `CurrencyContext` đúng 1 lần lúc TẠO command (không phải lúc execute),
/// snapshot `baseCurrencyCode` cùng lúc với `clientTxId`/`transactionDate`.
/// Presentation phase sau phải gọi qua provider này để tạo command, không
/// tự generate `clientTxId`/currency theo kiểu ad-hoc.
final createTransactionCommandFactoryProvider =
    Provider<CreateTransactionCommandFactory>((ref) {
      final currencyContext = ref.watch(currencyContextProvider);
      return CreateTransactionCommandFactory(currencyContext);
    });

/// **Cố tình KHÔNG phụ thuộc `currencyContextProvider`** (Phase 5 mục 15) —
/// đúng invariant Phase 4.1: currency resolve ở command-creation lifecycle
/// (`createTransactionCommandFactoryProvider`), không phải ở
/// execution-attempt lifecycle. Nếu provider này đọc `CurrencyContext`, 1
/// retry (gọi lại cùng command) có thể vô tình đổi currency giữa 2 lần thử.
final addTransactionUseCaseProvider = Provider<AddTransactionUseCase>((ref) {
  final repository = ref.watch(transactionRepositoryProvider);
  return AddTransactionUseCase(repository);
});

final updateTransactionUseCaseProvider = Provider<UpdateTransactionUseCase>((
  ref,
) {
  final repository = ref.watch(transactionRepositoryProvider);
  return UpdateTransactionUseCase(repository);
});

final reverseTransactionUseCaseProvider = Provider<ReverseTransactionUseCase>((
  ref,
) {
  final repository = ref.watch(transactionRepositoryProvider);
  return ReverseTransactionUseCase(repository);
});

final changeTransactionStatusUseCaseProvider =
    Provider<ChangeTransactionStatusUseCase>((ref) {
      final repository = ref.watch(transactionRepositoryProvider);
      return ChangeTransactionStatusUseCase(repository);
    });

final getTransactionByIdUseCaseProvider = Provider<GetTransactionByIdUseCase>((
  ref,
) {
  final repository = ref.watch(transactionRepositoryProvider);
  return GetTransactionByIdUseCase(repository);
});

final watchTransactionsUseCaseProvider = Provider<WatchTransactionsUseCase>((
  ref,
) {
  final repository = ref.watch(transactionRepositoryProvider);
  return WatchTransactionsUseCase(repository);
});

/// TOÀN BỘ transaction (kể cả bản đã hoàn tác/bản reversal nội bộ) — cần
/// đủ để tính balance đúng qua `computeAllPoolBalances`. Dùng
/// `isVisible(tx)` (`domain/engine/financial_engine.dart`) khi cần danh
/// sách hiển thị cho người dùng (danh sách giao dịch, rollup, breakdown).
///
/// Nguồn: `WatchTransactionsUseCase` (Application layer) — Phase 5 mục 9.
/// Trước Phase 5, provider này đọc thẳng `transactionRepositoryProvider`;
/// đổi sang đi qua Use Case là refactor tối thiểu, KHÔNG đổi dữ liệu emit
/// (cùng gọi `TransactionRepository.watchTransactions()` bên dưới).
final transactionsStreamProvider = StreamProvider<List<Transaction>>((ref) {
  final watchTransactions = ref.watch(watchTransactionsUseCaseProvider);
  return watchTransactions();
});
