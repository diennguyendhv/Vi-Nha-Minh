import 'package:drift/drift.dart';
import 'package:drift/native.dart' show SqliteException;

import '../../domain/engine/financial_engine.dart';
import '../../domain/engine/obligation_settlement.dart';
import '../../domain/entities/obligation.dart' as domain;
import '../../domain/entities/obligation_direction.dart';
import '../../domain/entities/pool_kind.dart';
import '../../domain/entities/transaction.dart' as domain;
import '../../domain/errors/domain_exceptions.dart';
import '../../domain/repositories/obligation_repository.dart';
import '../local/app_database.dart';
import 'local_transaction_repository.dart';

/// Metadata storage and the atomic creation boundary. Ledger writes reuse
/// LocalTransactionRepository on the SAME database/transaction context.
class LocalObligationRepository implements ObligationRepository {
  LocalObligationRepository(this._db);

  final AppDatabase _db;

  @override
  Future<domain.Transaction> createObligationWithOpeningTransaction(
    domain.Obligation obligation,
    domain.Transaction opening,
  ) async {
    final ledger = LocalTransactionRepository(_db);
    try {
      return await _db.transaction(() async {
        final existing = await ledger.getTransactionByClientTxId(
          opening.clientTxId,
        );
        final metadata = await (_db.select(
          _db.obligationRows,
        )..where((r) => r.id.equals(obligation.id))).getSingleOrNull();
        if (existing != null) {
          if (!isSameLogicalTransaction(existing, opening) ||
              metadata == null ||
              metadata.counterpartyId != obligation.counterpartyId ||
              metadata.direction != obligation.direction.name ||
              metadata.dueDate != obligation.dueDate ||
              metadata.note != obligation.note ||
              metadata.isActive != obligation.isActive) {
            throw ClientTxIdConflictException(
              clientTxId: opening.clientTxId,
              existing: existing,
              attempted: opening,
            );
          }
          return existing;
        }
        // A reused metadata identity without the matching opening is not a
        // retry: never silently attach another financial effect to that loan.
        if (metadata != null) {
          throw const PersistenceConstraintException(
            kind: PersistenceConstraintKind.uniqueViolation,
            message:
                'Loan identity already exists without the requested opening',
          );
        }
        final receivable =
            obligation.direction == ObligationDirection.receivable;
        if (opening.obligationId != obligation.id ||
            !isObligationCreationShape(opening, obligation.direction) ||
            opening.reversalOfTxId != null ||
            opening.correctsTxId != null ||
            opening.reversedByTxId != null ||
            opening.recoveryOfTxId != null ||
            opening.settlementGroupId != null ||
            (receivable
                ? opening.sourceKind != PoolKind.memberAvailable ||
                      opening.destinationRefId != obligation.id ||
                      opening.sourceRefId == null
                : opening.sourceKind != PoolKind.external ||
                      opening.destinationKind != PoolKind.memberAvailable ||
                      opening.destinationRefId == null)) {
          throw const PersistenceConstraintException(
            kind: PersistenceConstraintKind.other,
            message: 'Opening transaction does not match loan metadata',
          );
        }
        await _db.into(_db.obligationRows).insert(_toCompanion(obligation));
        // Nested Drift transaction uses a savepoint under this outer SQLite
        // transaction. Validation/insert errors propagate and roll back BOTH
        // records; stream notifications are published only after outer commit.
        return await ledger.addTransaction(opening);
      });
    } on SqliteException catch (error) {
      // Ledger failures are already mapped by LocalTransactionRepository.
      // Map metadata/FK errors here rather than exposing SQLite to callers.
      if (error.resultCode == 19) {
        throw PersistenceConstraintException(
          kind: error.extendedResultCode == 787
              ? PersistenceConstraintKind.foreignKey
              : PersistenceConstraintKind.other,
          message: 'Cannot persist loan metadata',
          cause: error,
        );
      }
      throw PersistenceException('Cannot persist loan', cause: error);
    }
  }

  domain.Obligation _toDomain(ObligationRow row) {
    return domain.Obligation(
      id: row.id,
      counterpartyId: row.counterpartyId,
      direction: ObligationDirection.values.byName(row.direction),
      dueDate: row.dueDate,
      note: row.note,
      isActive: row.isActive,
    );
  }

  ObligationRowsCompanion _toCompanion(domain.Obligation o) {
    return ObligationRowsCompanion.insert(
      id: o.id,
      counterpartyId: o.counterpartyId,
      direction: o.direction.name,
      dueDate: Value(o.dueDate),
      note: Value(o.note),
      isActive: Value(o.isActive),
    );
  }

  @override
  Stream<List<domain.Obligation>> watchObligations() {
    return _db
        .select(_db.obligationRows)
        .watch()
        .map((rows) => rows.map(_toDomain).toList());
  }

  @override
  Future<void> addObligation(domain.Obligation obligation) async {
    await _db.into(_db.obligationRows).insert(_toCompanion(obligation));
  }

  @override
  Future<void> updateObligation(domain.Obligation obligation) async {
    await (_db.update(
      _db.obligationRows,
    )..where((r) => r.id.equals(obligation.id))).write(
      ObligationRowsCompanion(
        counterpartyId: Value(obligation.counterpartyId),
        dueDate: Value(obligation.dueDate),
        note: Value(obligation.note),
        isActive: Value(obligation.isActive),
      ),
    );
  }
}
