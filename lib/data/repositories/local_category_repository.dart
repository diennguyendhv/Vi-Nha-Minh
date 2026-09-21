import 'package:drift/drift.dart';
import 'package:flutter/material.dart';

import '../../core/constants/advanced_system_categories.dart';
import '../../domain/entities/category.dart' as domain;
import '../../domain/entities/status.dart' as domain;
import '../../domain/entities/transaction_type.dart';
import '../../domain/errors/domain_exceptions.dart';
import '../../domain/repositories/category_repository.dart';
import '../local/app_database.dart';

/// Lưu danh mục bằng SQLite trên máy (Giai đoạn A). `watchCategories()` kèm
/// sẵn `statuses` — dùng `customSelect` dummy để Drift theo dõi được cả 2
/// bảng `CategoryRows`/`StatusRows` mà không cần viết JOIN tay.
class LocalCategoryRepository implements CategoryRepository {
  LocalCategoryRepository(this._db);

  final AppDatabase _db;

  domain.Status _statusToDomain(StatusRow row) {
    return domain.Status(
      id: row.id,
      categoryId: row.categoryId,
      name: row.name,
      sortOrder: row.sortOrder,
      isActive: row.isActive,
    );
  }

  domain.Category _categoryToDomain(
    CategoryRow row,
    List<domain.Status> statuses,
  ) {
    return domain.Category(
      id: row.id,
      name: row.name,
      color: Color(row.colorValue),
      type: TransactionType.values.byName(row.type),
      statuses: statuses,
      statsEnabled: row.statsEnabled,
      excludeFromTotals: row.excludeFromTotals,
      linkedExpenseCategoryId: row.linkedExpenseCategoryId,
      groupKey: row.groupKey,
      isDefault: row.isDefault,
      isActive: row.isActive,
    );
  }

  CategoryRowsCompanion _toCompanion(domain.Category c) {
    return CategoryRowsCompanion.insert(
      id: c.id,
      name: c.name,
      colorValue: c.color.value,
      type: c.type.name,
      statsEnabled: Value(c.statsEnabled),
      excludeFromTotals: Value(c.excludeFromTotals),
      linkedExpenseCategoryId: Value(c.linkedExpenseCategoryId),
      groupKey: Value(c.groupKey),
      isDefault: Value(c.isDefault),
      isActive: Value(c.isActive),
    );
  }

  Future<List<domain.Category>> _loadAll() async {
    final categoryRows = await _db.select(_db.categoryRows).get();
    final statusRows = await _db.select(_db.statusRows).get();
    final statusesByCategory = <String, List<domain.Status>>{};
    for (final s in statusRows) {
      (statusesByCategory[s.categoryId] ??= <domain.Status>[]).add(
        _statusToDomain(s),
      );
    }
    return categoryRows.map((c) {
      final statuses = (statusesByCategory[c.id] ?? <domain.Status>[])
        ..sort((a, b) {
          final byOrder = a.sortOrder.compareTo(b.sortOrder);
          return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
        });
      return _categoryToDomain(c, statuses);
    }).toList();
  }

  @override
  Stream<List<domain.Category>> watchCategories() {
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.categoryRows, _db.statusRows},
        )
        .watch()
        .asyncMap((_) => _loadAll());
  }

  @override
  Future<void> addCategory(domain.Category category) async {
    await _db.into(_db.categoryRows).insert(_toCompanion(category));
  }

  @override
  Future<void> updateCategory(domain.Category category) async {
    await (_db.update(
      _db.categoryRows,
    )..where((r) => r.id.equals(category.id))).write(
      CategoryRowsCompanion(
        name: Value(category.name),
        colorValue: Value(category.color.value),
        statsEnabled: Value(category.statsEnabled),
        excludeFromTotals: Value(category.excludeFromTotals),
        linkedExpenseCategoryId: Value(category.linkedExpenseCategoryId),
        groupKey: Value(category.groupKey),
        isActive: Value(category.isActive),
      ),
    );
  }

  @override
  Future<void> softDeleteCategory(String categoryId) async {
    await (_db.update(
      _db.categoryRows,
    )..where((r) => r.id.equals(categoryId))).write(
      const CategoryRowsCompanion(isActive: Value(false)),
    );
  }

  /// Id danh mục đã ngừng + an toàn để xoá hẳn. Dùng chung cho luồng xem
  /// ([watchDeletableCategoryIds]) và luồng ghi ([deleteCategoryPermanently]),
  /// nên UI và DB luôn dùng đúng 1 định nghĩa "an toàn".
  ///
  /// Danh mục KHÔNG xoá hẳn khi: còn dùng; loại Chuyển hoặc danh mục hệ thống
  /// của tính năng nâng cao; có ≥ 1 giao dịch tham chiếu (mọi dòng sổ, kể cả
  /// đã hoàn tác); hoặc 1 bước con của nó đã từng được giao dịch nào dùng.
  Future<Set<String>> _deletableIds() async {
    final categories = await _db.select(_db.categoryRows).get();
    final statuses = await _db.select(_db.statusRows).get();
    final usedCategories = {
      for (final r in await _db
          .customSelect('SELECT DISTINCT category_id AS id FROM transaction_rows')
          .get())
        r.read<String>('id'),
    };
    final usedStatuses = {
      for (final r in await _db
          .customSelect(
            'SELECT DISTINCT status_id AS id FROM transaction_rows '
            'WHERE status_id IS NOT NULL',
          )
          .get())
        r.read<String>('id'),
    };
    final statusesByCategory = <String, List<StatusRow>>{};
    for (final s in statuses) {
      (statusesByCategory[s.categoryId] ??= []).add(s);
    }

    return {
      for (final c in categories)
        if (!c.isActive &&
            c.type != TransactionType.transfer.name &&
            !AdvancedSystemCategories.contains(c.id) &&
            !usedCategories.contains(c.id) &&
            (statusesByCategory[c.id] ?? const <StatusRow>[]).every(
              (s) => !usedStatuses.contains(s.id),
            ))
          c.id,
    };
  }

  @override
  Stream<Set<String>> watchDeletableCategoryIds() {
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.categoryRows, _db.statusRows, _db.transactionRows},
        )
        .watch()
        .asyncMap((_) => _deletableIds());
  }

  @override
  Future<void> deleteCategoryPermanently(String categoryId) async {
    await _db.transaction(() async {
      if (!(await _deletableIds()).contains(categoryId)) {
        throw CategoryNotDeletableException(categoryId);
      }
      // `linkedExpenseCategoryId` chỉ còn là metadata cũ đã ẩn khỏi giao diện —
      // không được chặn xóa; gỡ mọi liên kết trỏ tới danh mục này (cùng 1 DB
      // transaction) để không để lại tham chiếu treo.
      await (_db.update(_db.categoryRows)
            ..where((r) => r.linkedExpenseCategoryId.equals(categoryId)))
          .write(
        const CategoryRowsCompanion(linkedExpenseCategoryId: Value(null)),
      );
      await (_db.delete(
        _db.statusRows,
      )..where((r) => r.categoryId.equals(categoryId))).go();
      await (_db.delete(
        _db.categoryRows,
      )..where((r) => r.id.equals(categoryId))).go();
    });
  }
}
