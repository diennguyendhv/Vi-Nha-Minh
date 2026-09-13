import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/local_transaction_repository.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';
import 'database_provider.dart';

// Giai đoạn A: luôn dùng LocalTransactionRepository (SQLite trên máy).
// Giai đoạn B sẽ đổi provider này để chọn Local hay Firestore dựa vào
// syncMode của gia đình hiện tại (xem spec.md, phase 28).
final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return LocalTransactionRepository(db);
});

final transactionsStreamProvider = StreamProvider<List<Transaction>>((ref) {
  final repository = ref.watch(transactionRepositoryProvider);
  return repository.watchTransactions();
});
