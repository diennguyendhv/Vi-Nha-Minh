import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/local_transaction_repository.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';
import 'database_provider.dart';

// Giai đoạn A: luôn dùng LocalTransactionRepository (SQLite trên máy).
// Giai đoạn B sẽ đổi provider này để chọn Local hay Firestore dựa vào
// syncMode của gia đình hiện tại.
final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return LocalTransactionRepository(db);
});

/// TOÀN BỘ transaction (kể cả bản đã hoàn tác/bản reversal nội bộ) — cần
/// đủ để tính balance đúng qua `computeAllPoolBalances`. Dùng
/// `isVisible(tx)` (`domain/engine/financial_engine.dart`) khi cần danh
/// sách hiển thị cho người dùng (danh sách giao dịch, rollup, breakdown).
final transactionsStreamProvider = StreamProvider<List<Transaction>>((ref) {
  final repository = ref.watch(transactionRepositoryProvider);
  return repository.watchTransactions();
});
