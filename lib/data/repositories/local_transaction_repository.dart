import 'package:drift/drift.dart';
import 'package:drift/native.dart' show SqliteException;

import '../../core/utils/id_generator.dart';
import '../../domain/engine/financial_engine.dart';
import '../../domain/entities/pool_kind.dart';
import '../../domain/entities/transaction.dart' as domain;
import '../../domain/entities/transaction_type.dart';
import '../../domain/entities/transfer_kind.dart';
import '../../domain/errors/domain_exceptions.dart';
import '../../domain/repositories/transaction_repository.dart';
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
    String? statusId,
  }) async {
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
          // amountMinor hoặc người tiêu đổi — 2 field này ảnh hưởng balance,
          // bắt buộc qua reversal ledger (mục 21). categoryId/note/
          // transactionDate/statusId "đi kèm" luôn vào bản thay thế.
          final result = buildCorrection(
            original,
            newAmountMinor: amountMinor ?? original.amountMinor,
            newCategoryId: categoryId,
            newNote: note,
            newSourceRefId: newSourceRefId,
            newDestinationRefId: newDestinationRefId,
            newTransactionDate: transactionDate,
            newStatusId: statusId,
            reversalId: IdGenerator.generate(),
            replacementId: IdGenerator.generate(),
            clientTxId: IdGenerator.generate(),
            now: DateTime.now(),
          );

          // Áp hiệu ứng reversal trước để check số dư đúng với trạng thái SAU
          // khi hoàn tác bản gốc (khớp Test 10: chỉ phần chênh lệch bị chặn).
          final balances = computeAllPoolBalances(existing);
          applyEffect(result.reversal, 1, balances);
          _assertWontGoNegative(result.replacement, balances);

          await _db
              .into(_db.transactionRows)
              .insert(_toCompanion(result.reversal));
          await _db
              .into(_db.transactionRows)
              .insert(_toCompanion(result.replacement));
          await (_db.update(
            _db.transactionRows,
          )..where((r) => r.id.equals(transactionId))).write(
            TransactionRowsCompanion(reversedByTxId: Value(result.reversal.id)),
          );
          return;
        }

        // Không field nào ảnh hưởng balance đổi — update thẳng tại chỗ.
        if (categoryId == null &&
            note == null &&
            transactionDate == null &&
            statusId == null) {
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
            statusId: statusId != null ? Value(statusId) : const Value.absent(),
            statusUpdatedAt: statusId != null
                ? Value(DateTime.now())
                : const Value.absent(),
          ),
        );
      });
    } on SqliteException catch (e) {
      throw _mapSqliteException(e);
    }
  }
}
