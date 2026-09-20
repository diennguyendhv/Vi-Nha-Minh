import 'package:flutter/painting.dart' show Color;

import '../../domain/entities/category.dart';
import '../../domain/entities/pool_kind.dart';
import '../../domain/entities/status.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/entities/transaction_type.dart';
import '../../domain/entities/transfer_kind.dart';

/// Kế hoạch nhập dữ liệu cũ (V2-2B) — đầu vào của [LegacyLedgerImporter]. Sinh ra
/// bởi `tool/legacy_import/plan.py` từ workbook; KHÔNG chứa công thức tài chính,
/// chỉ dữ liệu đã chuẩn hóa + danh tính tất định.
class ImportPlan {
  const ImportPlan({
    required this.importerVersion,
    required this.workbookSha256,
    required this.categories,
    required this.transactions,
    required this.requiredSystemCategories,
    required this.requiredSavingsAssets,
  });

  factory ImportPlan.fromJson(Map<String, dynamic> j) => ImportPlan(
    importerVersion: j['importerVersion'] as String,
    workbookSha256: j['workbookSha256'] as String,
    categories: [
      for (final c in (j['categories'] as List).cast<Map<String, dynamic>>())
        PlannedCategory.fromJson(c),
    ],
    transactions: [
      for (final t in (j['transactions'] as List).cast<Map<String, dynamic>>())
        PlannedTransaction.fromJson(t),
    ],
    requiredSystemCategories:
        (j['requiredSystemCategories'] as List).cast<String>(),
    requiredSavingsAssets: (j['requiredSavingsAssets'] as List).cast<String>(),
  );

  final String importerVersion;
  final String workbookSha256;
  final List<PlannedCategory> categories;
  final List<PlannedTransaction> transactions;

  /// Danh mục hệ thống PHẢI có sẵn (Chuyển, Tiết kiệm) — importer không tự tạo.
  final List<String> requiredSystemCategories;

  /// Loại tài sản tiết kiệm PHẢI có sẵn (vd "Gửi ngân hàng") — không tự tạo.
  final List<String> requiredSavingsAssets;
}

class PlannedCategory {
  const PlannedCategory({
    required this.id,
    required this.name,
    required this.type,
    required this.excludeFromTotals,
    required this.groupKey,
    required this.colorValue,
    required this.statuses,
  });

  factory PlannedCategory.fromJson(Map<String, dynamic> j) => PlannedCategory(
    id: j['id'] as String,
    name: j['name'] as String,
    type: TransactionType.values.byName(j['type'] as String),
    excludeFromTotals: j['excludeFromTotals'] as bool,
    groupKey: j['groupKey'] as String?,
    colorValue: j['colorValue'] as int,
    statuses: [
      for (final s in (j['statuses'] as List).cast<Map<String, dynamic>>())
        Status(
          id: s['id'] as String,
          categoryId: j['id'] as String,
          name: s['name'] as String,
          sortOrder: s['sortOrder'] as int,
        ),
    ],
  );

  final String id;
  final String name;
  final TransactionType type;
  final bool excludeFromTotals;
  final String? groupKey;
  final int colorValue;
  final List<Status> statuses;

  Category toDomain() => Category(
    id: id,
    name: name,
    color: Color(colorValue),
    type: type,
    excludeFromTotals: excludeFromTotals,
    groupKey: groupKey,
    isDefault: false,
    statuses: statuses,
  );
}

class PlannedTransaction {
  const PlannedTransaction({
    required this.id,
    required this.clientTxId,
    required this.role,
    required this.sourceRow,
    required this.type,
    required this.transferKind,
    required this.categoryId,
    required this.sourceKind,
    required this.sourceRefId,
    required this.destinationKind,
    required this.destinationRefId,
    required this.amountMinor,
    required this.date,
    required this.note,
    required this.statusId,
  });

  factory PlannedTransaction.fromJson(Map<String, dynamic> j) =>
      PlannedTransaction(
        id: j['id'] as String,
        clientTxId: j['clientTxId'] as String,
        role: j['role'] as String,
        sourceRow: j['sourceRow'] as int,
        type: TransactionType.values.byName(j['type'] as String),
        transferKind: j['transferKind'] == null
            ? null
            : TransferKind.values.byName(j['transferKind'] as String),
        categoryId: j['categoryId'] as String,
        sourceKind: PoolKind.values.byName(j['sourceKind'] as String),
        sourceRefId: j['sourceRefId'] as String?,
        destinationKind: PoolKind.values.byName(j['destinationKind'] as String),
        destinationRefId: j['destinationRefId'] as String?,
        amountMinor: j['amountMinor'] as int,
        date: _toSeconds(DateTime.parse(j['date'] as String)),
        note: j['note'] as String,
        statusId: j['statusId'] as String?,
      );

  final String id;
  final String clientTxId;

  /// `src` | `opening:<khóa>` | `migration:bank-allocation`.
  final String role;

  /// Dòng Excel nguồn (0 với giao dịch tổng hợp: số dư đầu kỳ, phân bổ Ngân hàng).
  final int sourceRow;
  final TransactionType type;
  final TransferKind? transferKind;
  final String categoryId;
  final PoolKind sourceKind;
  final String? sourceRefId;
  final PoolKind destinationKind;
  final String? destinationRefId;
  final int amountMinor;

  /// Ngày nguồn GIỮ NGUYÊN (chính xác tới giây — độ phân giải của DB).
  final DateTime date;
  final String note;
  final String? statusId;

  /// `createdAt` = ngày giao dịch (tất định, không dùng `DateTime.now()`).
  Transaction toDomain() => Transaction(
    id: id,
    type: type,
    transferKind: transferKind,
    categoryId: categoryId,
    sourceKind: sourceKind,
    sourceRefId: sourceRefId,
    destinationKind: destinationKind,
    destinationRefId: destinationRefId,
    amountMinor: amountMinor,
    note: note,
    statusId: statusId,
    transactionDate: date,
    createdAt: date,
    clientTxId: clientTxId,
  );

  static DateTime _toSeconds(DateTime d) =>
      DateTime(d.year, d.month, d.day, d.hour, d.minute, d.second);
}
