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
      ..orderBy([
        (r) => OrderingTerm.asc(r.sortOrder),
        (r) => OrderingTerm.asc(r.id),
      ]);
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

  /// Số dòng giao dịch (kể cả dòng ẩn từ cơ chế cũ) còn tham chiếu [statusId].
  Future<int> _referenceCount(String statusId) async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM transaction_rows WHERE status_id = ?',
          variables: [Variable<String>(statusId)],
          readsFrom: {_db.transactionRows},
        )
        .getSingle();
    return row.read<int>('c');
  }

  /// Đánh lại thứ tự liền mạch 0..n-1 cho các bước còn lại của 1 danh mục, giữ
  /// đúng thứ tự hiện có (sortOrder rồi id làm tie-break xác định).
  Future<void> _normalizeOrder(String categoryId) async {
    final rows =
        await (_db.select(_db.statusRows)
              ..where((r) => r.categoryId.equals(categoryId))
              ..orderBy([
                (r) => OrderingTerm.asc(r.sortOrder),
                (r) => OrderingTerm.asc(r.id),
              ]))
            .get();
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].sortOrder == i) continue;
      await (_db.update(_db.statusRows)..where((r) => r.id.equals(rows[i].id)))
          .write(StatusRowsCompanion(sortOrder: Value(i)));
    }
  }

  @override
  Stream<Set<String>> watchDeletableStatusIds() {
    return _db
        .customSelect(
          'SELECT s.id AS id FROM status_rows s WHERE NOT EXISTS '
          '(SELECT 1 FROM transaction_rows t WHERE t.status_id = s.id)',
          readsFrom: {_db.statusRows, _db.transactionRows},
        )
        .watch()
        .map((rows) => {for (final r in rows) r.read<String>('id')});
  }

  @override
  Future<void> deleteStatusPermanently(String statusId) async {
    await _db.transaction(() async {
      final row = await (_db.select(
        _db.statusRows,
      )..where((r) => r.id.equals(statusId))).getSingleOrNull();
      if (row == null) return;
      if (await _referenceCount(statusId) > 0) {
        throw StatusNotDeletableException(statusId);
      }
      await (_db.delete(
        _db.statusRows,
      )..where((r) => r.id.equals(statusId))).go();
      await _normalizeOrder(row.categoryId);
    });
  }

  @override
  Future<int> clearAndDeleteStatus(String statusId) async {
    return _db.transaction(() async {
      final row = await (_db.select(
        _db.statusRows,
      )..where((r) => r.id.equals(statusId))).getSingleOrNull();
      if (row == null) return 0;
      // CHỈ đổi status_id → NULL (trạng thái không có ảnh hưởng tài chính): không
      // đụng số tiền, danh mục, ngày, ghi chú, nguồn/đích, siêu dữ liệu hoàn tác.
      final cleared = await _db.customUpdate(
        'UPDATE transaction_rows SET status_id = NULL WHERE status_id = ?',
        variables: [Variable<String>(statusId)],
        updates: {_db.transactionRows},
        updateKind: UpdateKind.update,
      );
      await (_db.delete(
        _db.statusRows,
      )..where((r) => r.id.equals(statusId))).go();
      await _normalizeOrder(row.categoryId);
      return cleared;
    });
  }
}
