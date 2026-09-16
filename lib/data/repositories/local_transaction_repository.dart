import 'package:drift/drift.dart';

import '../../core/utils/id_generator.dart';
import '../../domain/engine/financial_engine.dart';
import '../../domain/entities/pool_kind.dart';
import '../../domain/entities/transaction.dart' as domain;
import '../../domain/entities/transaction_type.dart';
import '../../domain/entities/transfer_kind.dart';
import '../../domain/errors/domain_exceptions.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../local/app_database.dart';

/// Lưu giao dịch bằng SQLite trên máy (Giai đoạn A — local-first). Được
/// thay bằng `FirestoreTransactionRepository` khi gia đình chuyển sang
/// `syncMode: "cloud"` (Giai đoạn B) — interface không đổi.
///
/// Đây là nơi DUY NHẤT ghi `TransactionRows` — mọi validate (Invariant 7,
/// không cho pool âm) và cơ chế reversal ledger (mục 21) đều nằm ở đây,
/// dùng lại đúng `domain/engine/financial_engine.dart`.
class LocalTransactionRepository implements TransactionRepository {
  LocalTransactionRepository(this._db);

  final AppDatabase _db;

  domain.Transaction _toDomain(TransactionRow row) {
    return domain.Transaction(
      id: row.id,
      type: TransactionType.values.byName(row.type),
      transferKind: row.transferKind == null
          ? null
          : TransferKind.values.byName(row.transferKind!),
      categoryId: row.categoryId,
      sourceKind: PoolKind.values.byName(row.sourceKind),
      sourceRefId: row.sourceRefId,
      destinationKind: PoolKind.values.byName(row.destinationKind),
      destinationRefId: row.destinationRefId,
      amountMinor: row.amountMinor,
      currency: row.currency,
      note: row.note,
      statusId: row.statusId,
      statusUpdatedAt: row.statusUpdatedAt,
      transactionDate: row.transactionDate,
      createdAt: row.createdAt,
      reversalOfTxId: row.reversalOfTxId,
      correctsTxId: row.correctsTxId,
      reversedByTxId: row.reversedByTxId,
      clientTxId: row.clientTxId,
      version: row.version,
    );
  }

  TransactionRowsCompanion _toCompanion(domain.Transaction t) {
    return TransactionRowsCompanion.insert(
      id: t.id,
      type: t.type.name,
      transferKind: Value(t.transferKind?.name),
      categoryId: t.categoryId,
      sourceKind: t.sourceKind.name,
      sourceRefId: Value(t.sourceRefId),
      destinationKind: t.destinationKind.name,
      destinationRefId: Value(t.destinationRefId),
      amountMinor: t.amountMinor,
      currency: Value(t.currency),
      note: Value(t.note),
      statusId: Value(t.statusId),
      statusUpdatedAt: Value(t.statusUpdatedAt),
      transactionDate: t.transactionDate,
      createdAt: t.createdAt,
      reversalOfTxId: Value(t.reversalOfTxId),
      correctsTxId: Value(t.correctsTxId),
      reversedByTxId: Value(t.reversedByTxId),
      clientTxId: t.clientTxId,
      version: Value(t.version),
    );
  }

  Future<List<domain.Transaction>> _allTransactions() async {
    final rows = await _db.select(_db.transactionRows).get();
    return rows.map(_toDomain).toList();
  }

  void _assertWontGoNegative(domain.Transaction candidate, Map<PoolRef, int> balances) {
    if (wouldGoNegative(
      currentBalances: balances,
      kind: candidate.sourceKind,
      refId: candidate.sourceRefId,
      delta: -candidate.amountMinor,
    )) {
      throw InsufficientBalanceException(
        poolKind: candidate.sourceKind,
        refId: candidate.sourceRefId,
        currentBalance: poolBalance(balances, candidate.sourceKind, candidate.sourceRefId),
        requestedAmount: candidate.amountMinor,
      );
    }
  }

  @override
  Stream<List<domain.Transaction>> watchTransactions() {
    return _db
        .select(_db.transactionRows)
        .watch()
        .map((rows) => rows.map(_toDomain).toList());
  }

  @override
  Future<void> addTransaction(domain.Transaction transaction) async {
    final existing = await _allTransactions();
    final balances = computeAllPoolBalances(existing);
    _assertWontGoNegative(transaction, balances);
    await _db.into(_db.transactionRows).insert(_toCompanion(transaction));
  }

  @override
  Future<void> reverseTransaction(String transactionId) async {
    await _db.transaction(() async {
      final row = await (_db.select(
        _db.transactionRows,
      )..where((r) => r.id.equals(transactionId))).getSingle();
      final original = _toDomain(row);
      final reversal = buildReversal(
        original,
        newId: IdGenerator.generate(),
        clientTxId: IdGenerator.generate(),
        now: DateTime.now(),
      );
      await _db.into(_db.transactionRows).insert(_toCompanion(reversal));
      await (_db.update(
        _db.transactionRows,
      )..where((r) => r.id.equals(transactionId))).write(
        TransactionRowsCompanion(reversedByTxId: Value(reversal.id)),
      );
    });
  }

  /// Với INCOME, "người tiêu" = `destinationRefId`; với EXPENSE nguồn ví
  /// (`sourceKind == memberAvailable`), = `sourceRefId`. TRANSFER hoặc
  /// EXPENSE nguồn Quỹ không có khái niệm "người tiêu" đơn — trả về
  /// (null, null), báo hiệu bỏ qua [memberRefId] nếu có truyền vào.
  (String? sourceRefId, String? destinationRefId) _memberFieldTargets(
    domain.Transaction original,
    String memberRefId,
  ) {
    if (original.type == TransactionType.income) {
      return (null, memberRefId);
    }
    if (original.type == TransactionType.expense &&
        original.sourceKind == PoolKind.memberAvailable) {
      return (memberRefId, null);
    }
    return (null, null);
  }

  @override
  Future<void> updateTransaction(
    String transactionId, {
    int? amountMinor,
    String? categoryId,
    String? note,
    String? memberRefId,
    DateTime? transactionDate,
    String? statusId,
  }) async {
    await _db.transaction(() async {
      final existing = await _allTransactions();
      final original = existing.firstWhere((t) => t.id == transactionId);

      final amountChanged = amountMinor != null && amountMinor != original.amountMinor;
      String? newSourceRefId;
      String? newDestinationRefId;
      var memberChanged = false;
      if (memberRefId != null) {
        final (targetSource, targetDestination) = _memberFieldTargets(original, memberRefId);
        if (targetSource != null && targetSource != original.sourceRefId) {
          newSourceRefId = targetSource;
          memberChanged = true;
        }
        if (targetDestination != null && targetDestination != original.destinationRefId) {
          newDestinationRefId = targetDestination;
          memberChanged = true;
        }
      }

      if (amountChanged || memberChanged) {
        // amountMinor hoặc người tiêu đổi — 2 field này ảnh hưởng balance,
        // bắt buộc qua reversal ledger (mục 21). categoryId/note/
        // transactionDate/statusId "đi kèm" luôn vào bản thay thế.
        final result = buildCorrection(
          original,
          newAmountMinor: amountMinor ?? original.amountMinor,
          newCategoryId: categoryId,
          newNote: note,
          newSourceRefId: newSourceRefId,
          newDestinationRefId: newDestinationRefId,
          newTransactionDate: transactionDate,
          newStatusId: statusId,
          reversalId: IdGenerator.generate(),
          replacementId: IdGenerator.generate(),
          clientTxId: IdGenerator.generate(),
          now: DateTime.now(),
        );

        // Áp hiệu ứng reversal trước để check số dư đúng với trạng thái SAU
        // khi hoàn tác bản gốc (khớp Test 10: chỉ phần chênh lệch bị chặn).
        final balances = computeAllPoolBalances(existing);
        applyEffect(result.reversal, 1, balances);
        _assertWontGoNegative(result.replacement, balances);

        await _db.into(_db.transactionRows).insert(_toCompanion(result.reversal));
        await _db.into(_db.transactionRows).insert(_toCompanion(result.replacement));
        await (_db.update(
          _db.transactionRows,
        )..where((r) => r.id.equals(transactionId))).write(
          TransactionRowsCompanion(reversedByTxId: Value(result.reversal.id)),
        );
        return;
      }

      // Không field nào ảnh hưởng balance đổi — update thẳng tại chỗ.
      if (categoryId == null && note == null && transactionDate == null && statusId == null) {
        return;
      }
      await (_db.update(
        _db.transactionRows,
      )..where((r) => r.id.equals(transactionId))).write(
        TransactionRowsCompanion(
          categoryId: categoryId != null ? Value(categoryId) : const Value.absent(),
          note: note != null ? Value(note) : const Value.absent(),
          transactionDate: transactionDate != null
              ? Value(transactionDate)
              : const Value.absent(),
          statusId: statusId != null ? Value(statusId) : const Value.absent(),
          statusUpdatedAt: statusId != null
              ? Value(DateTime.now())
              : const Value.absent(),
        ),
      );
    });
  }
}
