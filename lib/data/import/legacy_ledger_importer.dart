import '../../domain/entities/category.dart';
import '../local/app_database.dart';
import '../repositories/local_category_repository.dart';
import '../repositories/local_status_repository.dart';
import '../repositories/local_transaction_repository.dart';
import 'import_scheduler.dart';
import 'legacy_import_plan.dart';

/// Kế hoạch nhập mâu thuẫn với dữ liệu đã có (cùng danh tính nhưng nội dung khác).
class LegacyImportConflictException implements Exception {
  const LegacyImportConflictException(this.message);
  final String message;
  @override
  String toString() => 'LegacyImportConflictException: $message';
}

class LegacyImportResult {
  const LegacyImportResult({
    required this.categoriesCreated,
    required this.categoriesExisting,
    required this.statusesCreated,
    required this.transactionsCreated,
    required this.transactionsExisting,
    required this.schedule,
  });

  final int categoriesCreated;
  final int categoriesExisting;
  final int statusesCreated;
  final int transactionsCreated;
  final int transactionsExisting;
  final ScheduleReport schedule;
}

/// Nhập kế hoạch dữ liệu cũ vào 1 [AppDatabase] qua CÁC REPOSITORY THẬT của app.
///
/// - **Không** raw-insert, **không** tắt kiểm tra: mọi giao dịch đi qua
///   `LocalTransactionRepository.addTransaction` (Financial Core: số tiền dương,
///   pool không âm, danh mục/trạng thái hợp lệ, `clientTxId` idempotent/xung đột).
/// - **Nguyên tử**: toàn bộ (danh mục + trạng thái + giao dịch) nằm trong 1
///   transaction ngoài; bất kỳ lỗi nào → rollback toàn bộ, không có DB nửa vời.
/// - **Idempotent**: chạy lại cùng kế hoạch không tạo bản ghi mới; nội dung khác
///   cùng danh tính → [LegacyImportConflictException] /
///   `ClientTxIdConflictException` (không ghi đè âm thầm).
class LegacyLedgerImporter {
  LegacyLedgerImporter(this._db)
    : _categories = LocalCategoryRepository(_db),
      _statuses = LocalStatusRepository(_db),
      _transactions = LocalTransactionRepository(_db);

  final AppDatabase _db;
  final LocalCategoryRepository _categories;
  final LocalStatusRepository _statuses;
  final LocalTransactionRepository _transactions;

  Future<LegacyImportResult> run(ImportPlan plan) {
    // Lập lịch TRƯỚC khi mở transaction: nếu không có thứ tự an toàn thì dừng ngay,
    // chưa đụng DB.
    final schedule = scheduleImport(plan.transactions);
    return _db.transaction(() async {
      final existing = await _categories.watchCategories().first;
      final byId = {for (final c in existing) c.id: c};

      for (final id in plan.requiredSystemCategories) {
        if (!byId.containsKey(id)) {
          throw LegacyImportConflictException('Thiếu danh mục hệ thống "$id".');
        }
      }
      final assetIds = {
        for (final a in await _db.select(_db.savingsAssetTypeRows).get()) a.id,
      };
      for (final id in plan.requiredSavingsAssets) {
        if (!assetIds.contains(id)) {
          throw LegacyImportConflictException('Thiếu loại tiết kiệm "$id".');
        }
      }

      var categoriesCreated = 0, categoriesExisting = 0, statusesCreated = 0;
      for (final planned in plan.categories) {
        final want = planned.toDomain();
        final have = byId[planned.id];
        if (have == null) {
          await _categories.addCategory(want);
          categoriesCreated++;
          for (final s in want.statuses) {
            await _statuses.addStatus(s);
            statusesCreated++;
          }
          continue;
        }
        _verifySameCategory(have, want);
        categoriesExisting++;
      }

      var created = 0, alreadyThere = 0;
      for (final planned in schedule.order) {
        final before = await _transactions.getTransactionByClientTxId(
          planned.clientTxId,
        );
        await _transactions.addTransaction(planned.toDomain());
        if (before == null) {
          created++;
        } else {
          alreadyThere++;
        }
      }

      return LegacyImportResult(
        categoriesCreated: categoriesCreated,
        categoriesExisting: categoriesExisting,
        statusesCreated: statusesCreated,
        transactionsCreated: created,
        transactionsExisting: alreadyThere,
        schedule: schedule,
      );
    });
  }

  void _verifySameCategory(Category have, Category want) {
    final sameStatuses =
        have.statuses.length == want.statuses.length &&
        [
          for (var i = 0; i < want.statuses.length; i++)
            have.statuses[i].id == want.statuses[i].id &&
                have.statuses[i].name == want.statuses[i].name,
        ].every((x) => x);
    if (have.name != want.name ||
        have.type != want.type ||
        have.excludeFromTotals != want.excludeFromTotals ||
        have.groupKey != want.groupKey ||
        !sameStatuses) {
      throw LegacyImportConflictException(
        'Danh mục "${want.id}" đã tồn tại nhưng nội dung khác kế hoạch.',
      );
    }
  }
}
