import '../entities/transaction.dart';

abstract class TransactionRepository {
  Stream<List<Transaction>> watchTransactions();

  Future<void> addTransaction(Transaction transaction);

  Future<void> updateTransaction(Transaction transaction);

  Future<void> deleteTransaction(String id);
}
