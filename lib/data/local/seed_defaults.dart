import 'package:drift/drift.dart';

import '../../core/constants/default_categories.dart';
import '../../core/constants/default_funds.dart';
import '../../core/constants/default_savings_asset_types.dart';
import 'app_database.dart';

/// Chạy đúng 1 lần — lúc file DB được tạo mới (`AppDatabase.migration`,
/// `beforeOpen` với `details.wasCreated`). Insert 10 category seed (+status
/// con), 1 quỹ mặc định, và 2 loại tài sản tiết kiệm mặc định, đúng bảng
/// seed trong `spec.md`.
Future<void> seedDefaults(AppDatabase db) async {
  await db.batch((batch) {
    batch.insertAll(db.categoryRows, [
      for (final c in DefaultCategories.all)
        CategoryRowsCompanion.insert(
          id: c.id,
          name: c.name,
          colorValue: c.color.value,
          type: c.type.name,
          statsEnabled: Value(c.statsEnabled),
          excludeFromTotals: Value(c.excludeFromTotals),
          linkedExpenseCategoryId: Value(c.linkedExpenseCategoryId),
          isDefault: const Value(true),
          isActive: const Value(true),
        ),
    ]);

    batch.insertAll(db.statusRows, [
      for (final c in DefaultCategories.all)
        for (final s in c.statuses)
          StatusRowsCompanion.insert(
            id: s.id,
            categoryId: s.categoryId,
            name: s.name,
            sortOrder: s.sortOrder,
            isActive: const Value(true),
          ),
    ]);

    batch.insertAll(db.fundRows, [
      for (final f in DefaultFunds.all)
        FundRowsCompanion.insert(
          id: f.id,
          name: f.name,
          colorValue: f.color.value,
          isActive: const Value(true),
        ),
    ]);

    batch.insertAll(db.savingsAssetTypeRows, [
      for (final a in DefaultSavingsAssetTypes.all)
        SavingsAssetTypeRowsCompanion.insert(
          id: a.id,
          name: a.name,
          colorValue: a.color.value,
          isActive: const Value(true),
        ),
    ]);
  });
}
