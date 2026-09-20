import 'package:vi_nha_minh/domain/entities/field_update.dart';
import 'package:vi_nha_minh/domain/entities/obligation_direction.dart';
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
  Future<int> purgeDeletedHistory(String categoryId) async => 0;

  @override
  Future<int> purgeDeletedHistoryForStatus(String statusId) async => 0;

  @override
  Future<void> deleteTransaction(String transactionId) async {}

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
    FieldUpdate<String>? status,
  }) async {}

  @override
  Stream<List<Transaction>> watchTransactions() => const Stream.empty();

  @override
  Future<({Transaction principal, Transaction? interest})> settleObligation({
    required String obligationId,
    required ObligationDirection direction,
    required String memberRefId,
    required int amountMinor,
    required DateTime transactionDate,
    String note = '',
    required String categoryId,
    required String interestCategoryId,
    required String principalId,
    required String principalClientTxId,
    required String interestId,
    required String interestClientTxId,
  }) => throw UnimplementedError();

  @override
  Future<void> reverseObligationSettlement(String anyLegTransactionId) =>
      throw UnimplementedError();

  @override
  Future<({Transaction principal, Transaction? interest})> correctObligationSettlement(
    String anyLegTransactionId, {
    required int newAmountMinor,
    required String categoryId,
    required String interestCategoryId,
    required String newPrincipalId,
    required String newPrincipalClientTxId,
    required String newInterestId,
    required String newInterestClientTxId,
  }) => throw UnimplementedError();
}
