import '../entities/obligation.dart';
import '../entities/transaction.dart';

/// Metadata queries and atomic creation of a loan and its opening ledger row.
/// Settlement remains owned by TransactionRepository.
abstract class ObligationRepository {
  Stream<List<Obligation>> watchObligations();

  Future<void> addObligation(Obligation obligation);

  /// Commit both records or neither. Retry the same identity/payload returns
  /// the persisted opening; a reused clientTxId with changed payload conflicts.
  /// Counterparty is an independent entity and must already exist.
  Future<Transaction> createObligationWithOpeningTransaction(
    Obligation obligation,
    Transaction opening,
  );

  /// Không cho sửa `direction` (đổi chiều 1 khoản vay đã tạo là vô nghĩa —
  /// tạo `Obligation` mới nếu nhập sai chiều mà CHƯA có giao dịch gốc nào).
  Future<void> updateObligation(Obligation obligation);
}
