import 'package:drift/drift.dart';
import 'package:drift/native.dart' show SqliteException;

import '../../core/utils/id_generator.dart';
import '../../domain/engine/financial_engine.dart';
import '../../domain/engine/obligation_settlement.dart';
import '../../domain/entities/field_update.dart';
import '../../domain/entities/obligation_direction.dart';
import '../../domain/entities/pool_kind.dart';
import '../../domain/entities/savings_asset_type.dart' show SystemSavingsAssets;
import '../../domain/entities/transaction.dart' as domain;
import '../../domain/entities/transaction_type.dart';
import '../../domain/entities/transfer_kind.dart';
import '../../domain/errors/domain_exceptions.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../../domain/usecases/compute_deletable_master_data.dart' show hiddenHistoryPurge, hiddenHistoryPurgeForStatus, HiddenHistoryPurge;
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
      recoveryOfTxId: row.recoveryOfTxId,
      obligationId: row.obligationId,
      settlementGroupId: row.settlementGroupId,
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
      recoveryOfTxId: Value(t.recoveryOfTxId),
      obligationId: Value(t.obligationId),
      settlementGroupId: Value(t.settlementGroupId),
      clientTxId: t.clientTxId,
      version: Value(t.version),
    );
  }

  Future<List<domain.Transaction>> _allTransactions() async {
    final rows = await _db.select(_db.transactionRows).get();
    return rows.map(_toDomain).toList();
  }

  void _assertWontGoNegative(
    domain.Transaction candidate,
    Map<PoolRef, int> balances,
  ) {
    if (wouldGoNegative(
      currentBalances: balances,
      kind: candidate.sourceKind,
      refId: candidate.sourceRefId,
      delta: -candidate.amountMinor,
    )) {
      throw InsufficientBalanceException(
        poolKind: candidate.sourceKind,
        refId: candidate.sourceRefId,
        currentBalance: poolBalance(
          balances,
          candidate.sourceKind,
          candidate.sourceRefId,
        ),
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

  Future<domain.Transaction?> _findByClientTxId(String clientTxId) async {
    final row = await (_db.select(
      _db.transactionRows,
    )..where((r) => r.clientTxId.equals(clientTxId))).getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  /// `true` chỉ khi [e] chắc chắn là vi phạm `UNIQUE(clientTxId)` — phân
  /// biệt bằng `extendedResultCode` (2067 = SQLITE_CONSTRAINT_UNIQUE, khác
  /// 787 = FOREIGN KEY, 1555 = PRIMARY KEY) VÀ nội dung message (SQLite trả
  /// nguyên văn `"UNIQUE constraint failed: <table>.<column>"`). Bắt buộc
  /// kiểm tra cả 2 điều kiện để KHÔNG nuốt nhầm lỗi FK/PK khác thành
  /// "trùng clientTxId" (mục 5/12 — không được nuốt mọi exception).
  bool _isClientTxIdUniqueViolation(SqliteException e) {
    const sqliteConstraintUnique = 2067;
    return e.extendedResultCode == sqliteConstraintUnique &&
        e.message.contains('transaction_rows.client_tx_id');
  }

  /// Dịch 1 `SqliteException` thô (KHÔNG PHẢI vi phạm `clientTxId` — case đó
  /// đã được xử lý riêng làm cơ chế idempotency, không phải lỗi) sang
  /// exception ở `domain/errors` — ranh giới của `TransactionRepository`
  /// không để lộ `SqliteException`/Drift internals ra ngoài (Phase 3.1 mục
  /// 4/5). Phân biệt bằng `extendedResultCode`:
  /// - 787 (SQLITE_CONSTRAINT_FOREIGNKEY) → `foreignKey`.
  /// - 2067/1555 (UNIQUE/PRIMARY KEY) → `uniqueViolation` (hiếm, không phải
  ///   `clientTxId` vì case đó không tới được đây).
  /// - Còn lại nhưng vẫn là 1 constraint (`resultCode == 19`) → `other`.
  /// - Không phải constraint nào cả → [PersistenceException] chung.
  Object _mapSqliteException(SqliteException e) {
    const constraintForeignKey = 787;
    const constraintUnique = 2067;
    const constraintPrimaryKey = 1555;
    const constraintBase = 19; // SQLITE_CONSTRAINT

    if (e.extendedResultCode == constraintForeignKey) {
      return PersistenceConstraintException(
        kind: PersistenceConstraintKind.foreignKey,
        message:
            'Vi phạm khoá ngoại khi ghi giao dịch — dữ liệu tham chiếu '
            '(categoryId/statusId) không tồn tại',
        cause: e,
      );
    }
    if (e.extendedResultCode == constraintUnique ||
        e.extendedResultCode == constraintPrimaryKey) {
      return PersistenceConstraintException(
        kind: PersistenceConstraintKind.uniqueViolation,
        message: 'Vi phạm ràng buộc duy nhất không phải clientTxId',
        cause: e,
      );
    }
    if (e.resultCode == constraintBase) {
      return PersistenceConstraintException(
        kind: PersistenceConstraintKind.other,
        message: 'Vi phạm ràng buộc dữ liệu không xác định',
        cause: e,
      );
    }
    return PersistenceException('Lỗi lưu trữ không mong đợi', cause: e);
  }

  /// Loại tài sản tiết kiệm ĐÃ NGỪNG không nhận thêm tiền (nạp / chuyển VÀO);
  /// chỉ cho rút hoặc chuyển RA. Tài sản hệ thống ("Chưa phân bổ") và loại
  /// không có dòng trong bảng (dữ liệu cũ) luôn được phép. Chỉ áp cho giao
  /// dịch MỚI — hoàn tác vẫn đưa tiền về đúng pool cũ dù loại đã ngừng.
  Future<void> _assertSavingsDestinationActive(
    domain.Transaction transaction,
  ) async {
    final kind = transaction.transferKind;
    if (kind != TransferKind.savingsTopup &&
        kind != TransferKind.savingsConvert) {
      return;
    }
    final ref = transaction.destinationRefId;
    if (transaction.destinationKind != PoolKind.memberSavingsAsset ||
        ref == null) {
      return;
    }
    final assetTypeId = parseSavingsAssetRefId(ref)?.assetTypeId;
    if (assetTypeId == null || SystemSavingsAssets.isSystem(assetTypeId)) {
      return;
    }
    final row = await (_db.select(
      _db.savingsAssetTypeRows,
    )..where((r) => r.id.equals(assetTypeId))).getSingleOrNull();
    if (row != null && !row.isActive) {
      throw SavingsAssetInactiveException(assetTypeId);
    }
  }

  @override
  Future<domain.Transaction> addTransaction(
    domain.Transaction transaction,
  ) async {
    validateNewTransaction(transaction);

    try {
      return await _db.transaction(() async {
        // Fast path — KHÔNG phải lớp bảo vệ duy nhất (xem catch bên dưới):
        // tránh chạy lại balance-check/insert cho 1 request lặp lại đã biết
        // trước là trùng, để không double-count hiệu ứng balance của chính
        // request cũ khi tính `computeAllPoolBalances`.
        final existingByClientTxId = await _findByClientTxId(
          transaction.clientTxId,
        );
        if (existingByClientTxId != null) {
          if (isSameLogicalTransaction(existingByClientTxId, transaction)) {
            return existingByClientTxId;
          }
          throw ClientTxIdConflictException(
            clientTxId: transaction.clientTxId,
            existing: existingByClientTxId,
            attempted: transaction,
          );
        }

        final existing = await _allTransactions();

        // Phase 8.6 — recovery relation validate TRƯỚC balance check: cần
        // đọc target từ DB (hàm domain thuần không tự tra được), nhưng phải
        // chặn SỚM trước khi insert, không phải sau.
        if (transaction.recoveryOfTxId != null) {
          // Self-link kiểm tra TRƯỚC tra DB: target = chính transaction này
          // (chưa insert) nên sẽ không bao giờ tìm thấy trong `existing`,
          // phải bắt case này riêng trước khi coi là "target không tồn tại".
          if (transaction.recoveryOfTxId == transaction.id) {
            throw InvalidRecoveryTargetException(
              reason: InvalidRecoveryReason.selfLink,
              targetId: transaction.id,
            );
          }
          domain.Transaction? target;
          for (final t in existing) {
            if (t.id == transaction.recoveryOfTxId) {
              target = t;
              break;
            }
          }
          if (target == null) {
            throw InvalidRecoveryTargetException(
              reason: InvalidRecoveryReason.targetNotFound,
              targetId: transaction.recoveryOfTxId!,
            );
          }
          validateRecoveryRelation(transaction, target);
        }

        await _assertSavingsDestinationActive(transaction);
        if (transaction.statusId != null) {
          await _assertStatusBelongs(
            transaction.statusId!,
            transaction.categoryId,
          );
        }

        final balances = computeAllPoolBalances(existing);
        _assertWontGoNegative(transaction, balances);

        try {
          await _db.into(_db.transactionRows).insert(_toCompanion(transaction));
          return transaction;
        } on SqliteException catch (e) {
          if (!_isClientTxIdUniqueViolation(e)) rethrow;
          // Race thật: 1 lệnh gọi khác cùng clientTxId đã insert xong giữa
          // lúc fast-path phía trên chạy xong và insert ở đây — DB UNIQUE là
          // lớp bảo vệ cuối cùng bắt lại đúng lúc này.
          final raced = await _findByClientTxId(transaction.clientTxId);
          if (raced == null) {
            rethrow; // không thể xảy ra, nhưng không nuốt lỗi nếu có.
          }
          if (isSameLogicalTransaction(raced, transaction)) return raced;
          throw ClientTxIdConflictException(
            clientTxId: transaction.clientTxId,
            existing: raced,
            attempted: transaction,
          );
        }
      });
    } on SqliteException catch (e) {
      throw _mapSqliteException(e);
    }
  }

  @override
  Future<domain.Transaction?> getTransactionById(String id) async {
    final row = await (_db.select(
      _db.transactionRows,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  @override
  Future<domain.Transaction?> getTransactionByClientTxId(String clientTxId) {
    return _findByClientTxId(clientTxId);
  }

  @override
  Future<void> reverseTransaction(String transactionId) async {
    try {
      await _db.transaction(() async {
        final row = await (_db.select(
          _db.transactionRows,
        )..where((r) => r.id.equals(transactionId))).getSingleOrNull();
        if (row == null) {
          throw TransactionNotFoundException(transactionId);
        }
        final original = _toDomain(row);
        final reversal = buildReversal(
          original,
          newId: IdGenerator.generate(),
          clientTxId: IdGenerator.generate(),
          now: DateTime.now(),
        );
        // Hoàn tác không được làm bất kỳ pool nào âm (vd hoàn tác lần nạp tiết
        // kiệm khi 1 phần đã phân bổ đi). Chặn TRƯỚC khi ghi: 0 dòng mới, số dư
        // không đổi; không cascade hoàn tác các giao dịch phát sinh sau.
        final overdrawn = poolOverdrawnByReversal(
          reversal,
          computeAllPoolBalances(await _allTransactions()),
        );
        if (overdrawn != null) {
          throw ReversalWouldOverdrawException(overdrawn.$1, overdrawn.$2);
        }
        await _db.into(_db.transactionRows).insert(_toCompanion(reversal));
        await (_db.update(
          _db.transactionRows,
        )..where((r) => r.id.equals(transactionId))).write(
          TransactionRowsCompanion(reversedByTxId: Value(reversal.id)),
        );
      });
    } on SqliteException catch (e) {
      throw _mapSqliteException(e);
    }
  }

  @override
  Future<void> deleteTransaction(String transactionId) async {
    await _db.transaction(() async {
      final all = await _allTransactions();
      if (!all.any((t) => t.id == transactionId)) {
        throw TransactionNotFoundException(transactionId);
      }
      final family = transactionFamilyIds(transactionId, all);
      final blocked = deleteBlockReason(family, all);
      if (blocked != null) throw TransactionDeleteBlockedException(blocked);
      final overdrawn = poolOverdrawnByRemoval(all, family);
      if (overdrawn != null) {
        throw DeleteWouldOverdrawException(
          overdrawn.$1,
          overdrawn.$2,
          blockingTransactionIds: blockingTransactionIds(
            overdrawn,
            all,
            family,
            since: _liveDate(all, family),
          ),
        );
      }
      await (_db.delete(
        _db.transactionRows,
      )..where((r) => r.id.isIn(family))).go();
    });
  }

  /// Ngày của dòng đang hiệu lực trong [family] (dùng để tìm giao dịch dùng SAU).
  DateTime? _liveDate(List<domain.Transaction> all, Set<String> family) {
    for (final t in all) {
      if (family.contains(t.id) && !t.isReversal && t.reversedByTxId == null) {
        return t.transactionDate;
      }
    }
    return null;
  }

  Future<int> _purge(HiddenHistoryPurge Function(List<domain.Transaction>) plan) {
    return _db.transaction(() async {
      final all = await _allTransactions();
      final p = plan(all);
      if (p.isEmpty) return 0;
      final blocked = deleteBlockReason(p.deleteIds, all);
      if (blocked != null) throw TransactionDeleteBlockedException(blocked);
      final overdrawn = poolOverdrawnByRemoval(all, p.deleteIds);
      if (overdrawn != null) {
        throw DeleteWouldOverdrawException(overdrawn.$1, overdrawn.$2);
      }
      if (p.relinkIds.isNotEmpty) {
        await (_db.update(_db.transactionRows)
              ..where((r) => r.id.isIn(p.relinkIds)))
            .write(const TransactionRowsCompanion(correctsTxId: Value(null)));
      }
      await (_db.delete(
        _db.transactionRows,
      )..where((r) => r.id.isIn(p.deleteIds))).go();
      return p.deleteIds.length;
    });
  }

  @override
  Future<int> purgeDeletedHistory(String categoryId) async {
    final statuses = await (_db.select(
      _db.statusRows,
    )..where((r) => r.categoryId.equals(categoryId))).get();
    final statusIds = {for (final s in statuses) s.id};
    return _purge(
      (all) => hiddenHistoryPurge(
        (t) =>
            t.categoryId == categoryId ||
            (t.statusId != null && statusIds.contains(t.statusId)),
        all,
      ),
    );
  }

  @override
  Future<int> purgeDeletedHistoryForStatus(String statusId) =>
      _purge((all) => hiddenHistoryPurgeForStatus(statusId, all));

  /// Lý do KHÔNG được thay dòng [family] khi sửa: thuộc Vay/Cho vay, hoặc có giao
  /// dịch hoàn tiền/thu hồi khác trỏ tới. Bản thân là giao dịch hoàn tiền (trỏ
  /// tới khoản chi gốc) thì được sửa — quan hệ đó được giữ ở dòng mới.
  DeleteBlockReason? _replaceBlockReason(
    Set<String> family,
    List<domain.Transaction> all,
  ) {
    for (final t in all) {
      if (family.contains(t.id)) {
        if (t.obligationId != null || t.settlementGroupId != null) {
          return DeleteBlockReason.linkedLoan;
        }
      } else if (t.recoveryOfTxId != null && family.contains(t.recoveryOfTxId)) {
        return DeleteBlockReason.linkedRecovery;
      }
    }
    return null;
  }

  /// Trạng thái [statusId] có thuộc danh mục [categoryId] không (Invariant:
  /// `status.categoryId == transaction.categoryId`).
  Future<bool> _statusBelongs(String statusId, String categoryId) async {
    final row = await (_db.select(
      _db.statusRows,
    )..where((r) => r.id.equals(statusId))).getSingleOrNull();
    // Trạng thái không tồn tại: để khoá ngoại báo lỗi tham chiếu như trước,
    // không tự coi là "sai danh mục".
    return row == null || row.categoryId == categoryId;
  }

  Future<void> _assertStatusBelongs(String statusId, String categoryId) async {
    if (!await _statusBelongs(statusId, categoryId)) {
      throw InvalidStatusForCategoryException(statusId, categoryId);
    }
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
    FieldUpdate<String>? status,
  }) async {
    // null = không đổi; set(id) = đặt; clear() = về null.
    final statusId = status?.value;
    final explicitClear = status?.isClear ?? false;
    try {
      await _db.transaction(() async {
        final existing = await _allTransactions();
        domain.Transaction? original;
        for (final t in existing) {
          if (t.id == transactionId) {
            original = t;
            break;
          }
        }
        if (original == null) {
          throw TransactionNotFoundException(transactionId);
        }

        // Invariant status.categoryId == transaction.categoryId. Đổi danh mục
        // (hoặc lưu lại 1 giao dịch cũ đã lệch) mà không chỉ định trạng thái
        // hợp lệ → XOÁ trạng thái cũ (không để nó "mắc kẹt" ở danh mục khác).
        final effectiveCategoryId = categoryId ?? original.categoryId;
        if (categoryId != null && categoryId != original.categoryId) {
          final target = await (_db.select(
            _db.categoryRows,
          )..where((r) => r.id.equals(categoryId))).getSingleOrNull();
          if (target != null && target.type != original.type.name) {
            throw MainGroupChangeException(transactionId, categoryId);
          }
        }
        // Xóa trạng thái vốn đã trống = không làm gì (không đụng statusUpdatedAt).
        var clearStatus = explicitClear && original.statusId != null;
        if (statusId != null) {
          await _assertStatusBelongs(statusId, effectiveCategoryId);
        } else if (!explicitClear &&
            original.statusId != null &&
            !await _statusBelongs(original.statusId!, effectiveCategoryId)) {
          clearStatus = true;
        }

        final amountChanged =
            amountMinor != null && amountMinor != original.amountMinor;
        String? newSourceRefId;
        String? newDestinationRefId;
        var memberChanged = false;
        if (memberRefId != null) {
          final (targetSource, targetDestination) = _memberFieldTargets(
            original,
            memberRefId,
          );
          if (targetSource != null && targetSource != original.sourceRefId) {
            newSourceRefId = targetSource;
            memberChanged = true;
          }
          if (targetDestination != null &&
              targetDestination != original.destinationRefId) {
            newDestinationRefId = targetDestination;
            memberChanged = true;
          }
        }

        if (amountChanged || memberChanged) {
          // Sửa số tiền / người = THAY dòng cũ bằng dòng mới trong cùng 1 DB
          // transaction (không tạo hoàn tác / bản thay thế → không để lại lịch
          // sử ẩn giữ danh mục/trạng thái cũ). Họ giao dịch cũ (nếu là dữ liệu
          // của phiên bản trước) bị xoá cả họ để không còn nửa chuỗi.
          final family = transactionFamilyIds(transactionId, existing);
          final live = existing.firstWhere(
            (t) => family.contains(t.id) && !t.isReversal && t.reversedByTxId == null,
            orElse: () => original!,
          );
          final blocked = _replaceBlockReason(family, existing);
          if (blocked != null) throw TransactionDeleteBlockedException(blocked);
          final replacement = buildReplacement(
            live,
            newAmountMinor: amountMinor ?? live.amountMinor,
            newCategoryId: categoryId,
            newNote: note,
            newSourceRefId: newSourceRefId,
            newDestinationRefId: newDestinationRefId,
            newTransactionDate: transactionDate,
            newStatusId: statusId,
            clearStatus: clearStatus,
            newId: IdGenerator.generate(),
            clientTxId: IdGenerator.generate(),
            now: DateTime.now(),
          );
          // Pool NGUỒN phải đủ tiền khi bỏ dòng cũ (báo thiếu số dư như khi thêm mới).
          _assertWontGoNegative(
            replacement,
            computeAllPoolBalances(existing.where((t) => !family.contains(t.id))),
          );
          // Sổ sau khi bỏ dòng cũ + thêm dòng mới không được làm pool nào âm.
          final overdrawn = poolOverdrawnByChange(
            existing,
            family,
            added: [replacement],
          );
          if (overdrawn != null) {
            throw ChangeWouldOverdrawException(
              overdrawn.$1,
              overdrawn.$2,
              blockingTransactionIds: blockingTransactionIds(
                overdrawn,
                existing,
                family,
                since: live.transactionDate,
              ),
            );
          }
          await (_db.delete(
            _db.transactionRows,
          )..where((r) => r.id.isIn(family))).go();
          await _db.into(_db.transactionRows).insert(_toCompanion(replacement));
          return;
        }

        // Không field nào ảnh hưởng balance đổi — update thẳng tại chỗ.
        if (categoryId == null &&
            note == null &&
            transactionDate == null &&
            statusId == null &&
            !clearStatus) {
          return;
        }
        await (_db.update(
          _db.transactionRows,
        )..where((r) => r.id.equals(transactionId))).write(
          TransactionRowsCompanion(
            categoryId: categoryId != null
                ? Value(categoryId)
                : const Value.absent(),
            note: note != null ? Value(note) : const Value.absent(),
            transactionDate: transactionDate != null
                ? Value(transactionDate)
                : const Value.absent(),
            statusId: statusId != null
                ? Value(statusId)
                : (clearStatus ? const Value(null) : const Value.absent()),
            statusUpdatedAt: (statusId != null || clearStatus)
                ? Value(DateTime.now())
                : const Value.absent(),
          ),
        );
      });
    } on SqliteException catch (e) {
      throw _mapSqliteException(e);
    }
  }

  /// Phase 8.7 — direction suy ra từ HÌNH DẠNG toàn bộ leg trong 1 group
  /// (không cần `ObligationRepository`): nếu bất kỳ leg nào chạm
  /// `PoolKind.receivable` → receivable, ngược lại → payable. Phải xét CẢ
  /// group (không chỉ 1 leg) vì leg lãi Receivable (income,
  /// external→memberAvailable) trùng hình dạng giao dịch TẠO Payable — chỉ
  /// phân biệt được khi nhìn thấy leg principal (sourceKind=receivable)
  /// trong cùng group.
  ObligationDirection _inferDirection(List<domain.Transaction> groupLegs) {
    final touchesReceivable = groupLegs.any(
      (t) =>
          t.sourceKind == PoolKind.receivable ||
          t.destinationKind == PoolKind.receivable,
    );
    return touchesReceivable
        ? ObligationDirection.receivable
        : ObligationDirection.payable;
  }

  @override
  Future<({domain.Transaction principal, domain.Transaction? interest})> settleObligation({
    required String obligationId,
    required ObligationDirection direction,
    required String memberRefId,
    required int amountMinor,
    required DateTime transactionDate,
    String note = '',
    required String categoryId,
    required String interestCategoryId,
    required String principalId,
    required String principalClientTxId,
    required String interestId,
    required String interestClientTxId,
  }) async {
    if (amountMinor <= 0) {
      throw InvalidAmountException(amountMinor);
    }
    try {
      return await _db.transaction(() async {
        final existing = await _allTransactions();

        final creation = findObligationCreationTransaction(
          direction,
          obligationId,
          existing,
        );
        if (creation == null) {
          throw ObligationCreationNotFoundException(obligationId);
        }

        final balances = computeAllPoolBalances(existing);
        final outstanding = computeObligationOutstanding(
          direction,
          obligationId,
          existing,
          balances,
        );

        final legs = buildObligationSettlementLegs(
          direction: direction,
          obligationId: obligationId,
          memberRefId: memberRefId,
          outstanding: outstanding,
          paymentAmount: amountMinor,
          categoryId: categoryId,
          interestCategoryId: interestCategoryId,
          currency: creation.currency,
          principalId: principalId,
          principalClientTxId: principalClientTxId,
          interestId: interestId,
          interestClientTxId: interestClientTxId,
          transactionDate: transactionDate,
          now: DateTime.now(),
          note: note,
        );

        // Idempotency + defensive half-state audit (mục "atomicity +
        // idempotency" Phase 8.7) — kiểm tra CẢ 2 clientTxId bất kể lần này
        // có tính ra leg interest hay không, để bắt được half-state hỏng từ
        // 1 lần chạy trước.
        //
        // QUAN TRỌNG: so khớp dựa vào field ỔN ĐỊNH của CHÍNH command
        // (`obligationId`/`amountMinor`) — KHÔNG so với `legs` (vừa build ở
        // trên từ `outstanding` ĐỌC HIỆN TẠI). Lý do: nếu lần gọi ĐẦU đã
        // thành công, outstanding lúc RETRY đã khác (bị chính lần ghi đó
        // làm giảm) → `legs` build lại ở retry sẽ KHÔNG khớp payload đã ghi
        // trước đó dù đây là 1 retry hợp lệ — bug đã phát hiện khi viết
        // test, sửa bằng cách so trực tiếp với input command (ổn định qua
        // mọi lần gọi lại), không phụ thuộc trạng thái ledger tại thời điểm
        // gọi.
        final existingPrincipalRow = await _findByClientTxId(
          principalClientTxId,
        );
        final existingInterestRow = await _findByClientTxId(
          interestClientTxId,
        );

        if (existingPrincipalRow != null && existingInterestRow != null) {
          final matches =
              existingPrincipalRow.obligationId == obligationId &&
              existingInterestRow.obligationId == obligationId &&
              existingInterestRow.settlementGroupId == existingPrincipalRow.id &&
              existingPrincipalRow.amountMinor + existingInterestRow.amountMinor ==
                  amountMinor;
          if (matches) {
            return (principal: existingPrincipalRow, interest: existingInterestRow);
          }
          throw ClientTxIdConflictException(
            clientTxId: principalClientTxId,
            existing: existingPrincipalRow,
            attempted: legs.principal,
          );
        }
        if (existingPrincipalRow != null && existingInterestRow == null) {
          final matchesSingleLeg =
              existingPrincipalRow.obligationId == obligationId &&
              existingPrincipalRow.settlementGroupId == null &&
              existingPrincipalRow.amountMinor == amountMinor;
          if (matchesSingleLeg) {
            return (principal: existingPrincipalRow, interest: null);
          }
          throw SettlementIntegrityException(
            obligationId: obligationId,
            clientTxId: principalClientTxId,
            missingLeg: 'interest',
          );
        }
        if (existingPrincipalRow == null && existingInterestRow != null) {
          throw SettlementIntegrityException(
            obligationId: obligationId,
            clientTxId: principalClientTxId,
            missingLeg: 'principal',
          );
        }

        // Neither leg tồn tại — ghi mới, atomic trong CHÍNH transaction này.
        _assertWontGoNegative(legs.principal, balances);
        try {
          await _db.into(_db.transactionRows).insert(_toCompanion(legs.principal));
          if (legs.interest != null) {
            await _db.into(_db.transactionRows).insert(_toCompanion(legs.interest!));
          }
          return (principal: legs.principal, interest: legs.interest);
        } on SqliteException catch (e) {
          if (!_isClientTxIdUniqueViolation(e)) rethrow;
          final racedPrincipal = await _findByClientTxId(principalClientTxId);
          final racedInterest = await _findByClientTxId(interestClientTxId);
          if (racedPrincipal != null &&
              isSameLogicalTransaction(racedPrincipal, legs.principal) &&
              (legs.interest == null ||
                  (racedInterest != null &&
                      isSameLogicalTransaction(racedInterest, legs.interest!)))) {
            return (principal: racedPrincipal, interest: racedInterest);
          }
          throw ClientTxIdConflictException(
            clientTxId: principalClientTxId,
            existing: racedPrincipal ?? legs.principal,
            attempted: legs.principal,
          );
        }
      });
    } on SqliteException catch (e) {
      throw _mapSqliteException(e);
    }
  }

  @override
  Future<void> reverseObligationSettlement(String anyLegTransactionId) async {
    try {
      await _db.transaction(() async {
        final existing = await _allTransactions();
        domain.Transaction? tx;
        for (final t in existing) {
          if (t.id == anyLegTransactionId) {
            tx = t;
            break;
          }
        }
        if (tx == null || tx.reversalOfTxId != null) {
          throw TransactionNotFoundException(anyLegTransactionId);
        }

        final groupId = tx.settlementGroupId ?? tx.id;
        final groupLegs = existing
            .where((t) => t.id == groupId || t.settlementGroupId == groupId)
            .toList();
        if (groupLegs.isEmpty) {
          throw TransactionNotFoundException(anyLegTransactionId);
        }
        for (final leg in groupLegs) {
          if (leg.reversedByTxId != null) {
            throw AlreadyReversedException(leg.id, leg.reversedByTxId!);
          }
        }

        final now = DateTime.now();
        final reversals = buildObligationSettlementReversal(
          groupLegs,
          newIds: [for (final _ in groupLegs) IdGenerator.generate()],
          clientTxIds: [for (final _ in groupLegs) IdGenerator.generate()],
          now: now,
        );

        for (var i = 0; i < groupLegs.length; i++) {
          await _db.into(_db.transactionRows).insert(_toCompanion(reversals[i]));
          await (_db.update(
            _db.transactionRows,
          )..where((r) => r.id.equals(groupLegs[i].id))).write(
            TransactionRowsCompanion(reversedByTxId: Value(reversals[i].id)),
          );
        }
      });
    } on SqliteException catch (e) {
      throw _mapSqliteException(e);
    }
  }

  @override
  Future<({domain.Transaction principal, domain.Transaction? interest})> correctObligationSettlement(
    String anyLegTransactionId, {
    required int newAmountMinor,
    required String categoryId,
    required String interestCategoryId,
    required String newPrincipalId,
    required String newPrincipalClientTxId,
    required String newInterestId,
    required String newInterestClientTxId,
  }) async {
    if (newAmountMinor <= 0) {
      throw InvalidAmountException(newAmountMinor);
    }
    try {
      return await _db.transaction(() async {
        final existing = await _allTransactions();
        domain.Transaction? tx;
        for (final t in existing) {
          if (t.id == anyLegTransactionId) {
            tx = t;
            break;
          }
        }
        if (tx == null || tx.reversalOfTxId != null || tx.obligationId == null) {
          throw TransactionNotFoundException(anyLegTransactionId);
        }

        final obligationId = tx.obligationId!;
        final groupId = tx.settlementGroupId ?? tx.id;
        final groupLegs = existing
            .where((t) => t.id == groupId || t.settlementGroupId == groupId)
            .toList();
        if (groupLegs.isEmpty) {
          throw TransactionNotFoundException(anyLegTransactionId);
        }
        for (final leg in groupLegs) {
          if (leg.reversedByTxId != null) {
            throw AlreadyReversedException(leg.id, leg.reversedByTxId!);
          }
        }

        final direction = _inferDirection(groupLegs);
        final anchors = listObligationSettlementAnchors(
          direction,
          obligationId,
          existing,
        );
        if (anchors.isEmpty || anchors.last.id != groupId) {
          throw NotLatestSettlementException(anyLegTransactionId, obligationId);
        }

        final memberRefId = direction == ObligationDirection.receivable
            ? groupLegs.firstWhere((t) => t.sourceKind == PoolKind.receivable).destinationRefId!
            : groupLegs.first.sourceRefId!;

        final now = DateTime.now();
        final reversals = buildObligationSettlementReversal(
          groupLegs,
          newIds: [for (final _ in groupLegs) IdGenerator.generate()],
          clientTxIds: [for (final _ in groupLegs) IdGenerator.generate()],
          now: now,
        );

        // Áp hiệu ứng reversal vào 1 bản sao working-list để tính LẠI
        // outstanding SAU khi khôi phục group cũ — chưa ghi DB, chỉ tính
        // toán thuần (giống pattern `updateTransaction` áp reversal vào
        // `balances` trước khi check số dư mới).
        final workingList = [...existing, ...reversals];
        final creation = findObligationCreationTransaction(
          direction,
          obligationId,
          workingList,
        );
        if (creation == null) {
          throw ObligationCreationNotFoundException(obligationId);
        }
        final workingBalances = computeAllPoolBalances(workingList);
        final restoredOutstanding = computeObligationOutstanding(
          direction,
          obligationId,
          workingList,
          workingBalances,
        );

        final newLegs = buildObligationSettlementLegs(
          direction: direction,
          obligationId: obligationId,
          memberRefId: memberRefId,
          outstanding: restoredOutstanding,
          paymentAmount: newAmountMinor,
          categoryId: categoryId,
          interestCategoryId: interestCategoryId,
          currency: creation.currency,
          principalId: newPrincipalId,
          principalClientTxId: newPrincipalClientTxId,
          interestId: newInterestId,
          interestClientTxId: newInterestClientTxId,
          transactionDate: tx.transactionDate,
          now: now,
          note: tx.note,
        );
        _assertWontGoNegative(newLegs.principal, workingBalances);

        for (var i = 0; i < groupLegs.length; i++) {
          await _db.into(_db.transactionRows).insert(_toCompanion(reversals[i]));
          await (_db.update(
            _db.transactionRows,
          )..where((r) => r.id.equals(groupLegs[i].id))).write(
            TransactionRowsCompanion(reversedByTxId: Value(reversals[i].id)),
          );
        }
        await _db.into(_db.transactionRows).insert(_toCompanion(newLegs.principal));
        if (newLegs.interest != null) {
          await _db.into(_db.transactionRows).insert(_toCompanion(newLegs.interest!));
        }
        return (principal: newLegs.principal, interest: newLegs.interest);
      });
    } on SqliteException catch (e) {
      throw _mapSqliteException(e);
    }
  }
}
