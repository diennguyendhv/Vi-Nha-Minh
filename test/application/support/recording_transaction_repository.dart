import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/repositories/transaction_repository.dart';

/// Fake `TransactionRepository` dùng cho test Application layer thuần
/// (không đụng Drift/SQLite) — chứng minh Use Case chỉ phụ thuộc INTERFACE
/// (`TransactionRepository`), không phụ thuộc `LocalTransactionRepository`
/// cụ thể (Phase 4 mục 32). Ghi lại transaction gần nhất được truyền vào
/// `addTransaction` để assert mapping command → domain Transaction, và cho
/// phép cấu hình throw sẵn để test error propagation không bị Application
/// nuốt/biến đổi.
class RecordingTransactionRepository implements TransactionRepository {
  Transaction? lastAdded;
  Object? throwOnAdd;

  @override
  Future<Transaction> addTransaction(Transaction transaction) async {
    if (throwOnAdd != null) throw throwOnAdd!;
    lastAdded = transaction;
    return transaction;
  }

  @override
  Future<Transaction?> getTransactionById(String id) async => null;

  @override
  Future<Transaction?> getTransactionByClientTxId(String clientTxId) async =>
      null;

  @override
  Future<void> reverseTransaction(String transactionId) async {}

  @override
  Future<void> updateTransaction(
    String transactionId, {
    int? amountMinor,
    String? categoryId,
    String? note,
    String? memberRefId,
    DateTime? transactionDate,
    String? statusId,
  }) async {}

  @override
  Stream<List<Transaction>> watchTransactions() => const Stream.empty();
}
