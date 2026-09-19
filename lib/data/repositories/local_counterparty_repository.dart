import 'package:drift/drift.dart';

import '../../domain/engine/financial_engine.dart';
import '../../domain/engine/obligation_settlement.dart';
import '../../domain/entities/counterparty.dart' as domain;
import '../../domain/entities/obligation_direction.dart';
import '../../domain/errors/domain_exceptions.dart';
import '../../domain/repositories/counterparty_repository.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../local/app_database.dart';

/// Phase 8.7 — CRUD thuần cho `Counterparty`, cùng pattern
/// `LocalFundRepository`. Cần [_transactionRepository] để kiểm tra "còn
/// khoản vay đang mở không" trước khi soft-delete (giống
/// `FundNotEmptyException`).
class LocalCounterpartyRepository implements CounterpartyRepository {
  LocalCounterpartyRepository(this._db, this._transactionRepository);

  final AppDatabase _db;
  final TransactionRepository _transactionRepository;

  domain.Counterparty _toDomain(CounterpartyRow row) {
    return domain.Counterparty(
      id: row.id,
      displayName: row.displayName,
      isActive: row.isActive,
    );
  }

  CounterpartyRowsCompanion _toCompanion(domain.Counterparty c) {
    return CounterpartyRowsCompanion.insert(
      id: c.id,
      displayName: c.displayName,
      isActive: Value(c.isActive),
    );
  }

  @override
  Stream<List<domain.Counterparty>> watchCounterparties() {
    return _db
        .select(_db.counterpartyRows)
        .watch()
        .map((rows) => rows.map(_toDomain).toList());
  }

  @override
  Future<void> addCounterparty(domain.Counterparty counterparty) async {
    await _db.into(_db.counterpartyRows).insert(_toCompanion(counterparty));
  }

  @override
  Future<void> updateCounterparty(domain.Counterparty counterparty) async {
    await (_db.update(
      _db.counterpartyRows,
    )..where((r) => r.id.equals(counterparty.id))).write(
      CounterpartyRowsCompanion(
        displayName: Value(counterparty.displayName),
        isActive: Value(counterparty.isActive),
      ),
    );
  }

  @override
  Future<void> softDeleteCounterparty(String counterpartyId) async {
    final obligationRows = await _db.select(_db.obligationRows).get();
    final transactions = await _transactionRepository.watchTransactions().first;
    final balances = computeAllPoolBalances(transactions);

    for (final row in obligationRows) {
      if (row.counterpartyId != counterpartyId) continue;
      final direction = ObligationDirection.values.byName(row.direction);
      final outstanding = computeObligationOutstanding(
        direction,
        row.id,
        transactions,
        balances,
      );
      if (outstanding > 0) {
        throw CounterpartyHasOpenObligationsException(counterpartyId);
      }
    }
    await (_db.update(
      _db.counterpartyRows,
    )..where((r) => r.id.equals(counterpartyId))).write(
      const CounterpartyRowsCompanion(isActive: Value(false)),
    );
  }
}
