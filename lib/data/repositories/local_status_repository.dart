import 'package:drift/drift.dart';

import '../../domain/entities/status.dart' as domain;
import '../../domain/errors/domain_exceptions.dart';
import '../../domain/repositories/status_repository.dart';
import '../local/app_database.dart';

class LocalStatusRepository implements StatusRepository {
  LocalStatusRepository(this._db);

  final AppDatabase _db;

  domain.Status _toDomain(StatusRow row) {
    return domain.Status(
      id: row.id,
      categoryId: row.categoryId,
      name: row.name,
      sortOrder: row.sortOrder,
      isActive: row.isActive,
    );
  }

  @override
  Stream<List<domain.Status>> watchStatuses(String categoryId) {
    final query = _db.select(_db.statusRows)
      ..where((r) => r.categoryId.equals(categoryId))
      ..orderBy([(r) => OrderingTerm.asc(r.sortOrder)]);
    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  @override
  Future<void> addStatus(domain.Status status) async {
    await _db
        .into(_db.statusRows)
        .insert(
          StatusRowsCompanion.insert(
            id: status.id,
            categoryId: status.categoryId,
            name: status.name,
            sortOrder: status.sortOrder,
            isActive: Value(status.isActive),
          ),
        );
  }

  @override
  Future<void> renameStatus(String statusId, String newName) async {
    await (_db.update(
      _db.statusRows,
    )..where((r) => r.id.equals(statusId))).write(
      StatusRowsCompanion(name: Value(newName)),
    );
  }

  @override
  Future<void> reorderStatuses(
    String categoryId,
    List<String> orderedStatusIds,
  ) async {
    await _db.transaction(() async {
      for (var i = 0; i < orderedStatusIds.length; i++) {
        await (_db.update(
          _db.statusRows,
        )..where((r) => r.id.equals(orderedStatusIds[i]))).write(
          StatusRowsCompanion(sortOrder: Value(i)),
        );
      }
    });
  }

  @override
  Future<void> softDeleteStatus(String statusId) async {
    await (_db.update(
      _db.statusRows,
    )..where((r) => r.id.equals(statusId))).write(
      const StatusRowsCompanion(isActive: Value(false)),
    );
  }

  @override
  Future<void> reactivateStatus(String statusId) async {
    await (_db.update(
      _db.statusRows,
    )..where((r) => r.id.equals(statusId))).write(
      const StatusRowsCompanion(isActive: Value(true)),
    );
  }

  /// Bước đã ngừng + chưa từng được giao dịch nào tham chiếu (kể cả đã hoàn
  /// tác). Dùng chung cho luồng xem và luồng ghi.
  Future<Set<String>> _deletableIds() async {
    final rows = await _db
        .customSelect(
          'SELECT s.id AS id FROM status_rows s '
          'WHERE s.is_active = 0 AND NOT EXISTS '
          '(SELECT 1 FROM transaction_rows t WHERE t.status_id = s.id)',
        )
        .get();
    return {for (final r in rows) r.read<String>('id')};
  }

  @override
  Stream<Set<String>> watchDeletableStatusIds() {
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.statusRows, _db.transactionRows},
        )
        .watch()
        .asyncMap((_) => _deletableIds());
  }

  @override
  Future<void> deleteStatusPermanently(String statusId) async {
    await _db.transaction(() async {
      if (!(await _deletableIds()).contains(statusId)) {
        throw StatusNotDeletableException(statusId);
      }
      await (_db.delete(
        _db.statusRows,
      )..where((r) => r.id.equals(statusId))).go();
    });
  }
}
