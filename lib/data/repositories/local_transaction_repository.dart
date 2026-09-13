import 'package:drift/drift.dart';

import '../../domain/entities/family_member.dart';
import '../../domain/entities/savings_destination.dart';
import '../../domain/entities/transaction.dart' as domain;
import '../../domain/repositories/transaction_repository.dart';
import '../local/app_database.dart';

/// Lưu giao dịch bằng SQLite trên máy (Giai đoạn A — local-first). Được
/// thay bằng `FirestoreTransactionRepository` khi gia đình chuyển sang
/// `syncMode: "cloud"` (Giai đoạn B, phase 27-28) — interface không đổi.
class LocalTransactionRepository implements TransactionRepository {
  LocalTransactionRepository(this._db);

  final AppDatabase _db;

  domain.Transaction _toDomain(TransactionRow row) {
    return domain.Transaction(
      id: row.id,
      categoryId: row.categoryId,
      amount: row.amount,
      date: row.date,
      spender: FamilyMember.values.byName(row.spender),
      note: row.note,
      status: row.status,
      savingsDestination: row.savingsDestination == null
          ? null
          : SavingsDestination.values.byName(row.savingsDestination!),
    );
  }

  TransactionRowsCompanion _toCompanion(domain.Transaction t) {
    return TransactionRowsCompanion(
      id: Value(t.id),
      categoryId: Value(t.categoryId),
      amount: Value(t.amount),
      date: Value(t.date),
      spender: Value(t.spender.name),
      note: Value(t.note),
      status: Value(t.status),
      savingsDestination: Value(t.savingsDestination?.name),
    );
  }

  @override
  Stream<List<domain.Transaction>> watchTransactions() {
    return _db.select(_db.transactionRows).watch().map(
      (rows) => rows.map(_toDomain).toList(),
    );
  }

  @override
  Future<void> addTransaction(domain.Transaction transaction) async {
    await _db.into(_db.transactionRows).insert(_toCompanion(transaction));
  }

  @override
  Future<void> updateTransaction(domain.Transaction transaction) async {
    await _db.update(_db.transactionRows).replace(_toCompanion(transaction));
  }

  @override
  Future<void> deleteTransaction(String id) async {
    await (_db.delete(
      _db.transactionRows,
    )..where((row) => row.id.equals(id))).go();
  }
}
