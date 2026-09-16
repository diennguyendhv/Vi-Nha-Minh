import 'package:drift/drift.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/category.dart' as domain;
import '../../domain/entities/status.dart' as domain;
import '../../domain/entities/transaction_type.dart';
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
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
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
}
