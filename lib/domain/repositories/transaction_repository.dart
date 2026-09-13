import '../entities/transaction.dart';

abstract class TransactionRepository {
  Stream<List<Transaction>> watchTransactions();

  Future<void> addTransaction(Transaction transaction);
}
