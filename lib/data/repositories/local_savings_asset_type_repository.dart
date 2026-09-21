import 'package:drift/drift.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/pool_kind.dart';
import '../../domain/entities/savings_asset_type.dart' as domain;
import '../../domain/errors/domain_exceptions.dart';
import '../../domain/repositories/savings_asset_type_repository.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../../domain/usecases/compute_pool_balance.dart';
import '../local/app_database.dart';

class LocalSavingsAssetTypeRepository implements SavingsAssetTypeRepository {
  LocalSavingsAssetTypeRepository(this._db, this._transactionRepository);

  final AppDatabase _db;
  final TransactionRepository _transactionRepository;

  domain.SavingsAssetType _toDomain(SavingsAssetTypeRow row) {
    return domain.SavingsAssetType(
      id: row.id,
      name: row.name,
      color: Color(row.colorValue),
      isActive: row.isActive,
    );
  }

  SavingsAssetTypeRowsCompanion _toCompanion(domain.SavingsAssetType a) {
    return SavingsAssetTypeRowsCompanion.insert(
      id: a.id,
      name: a.name,
      colorValue: a.color.value,
      isActive: Value(a.isActive),
    );
  }

  @override
  Stream<List<domain.SavingsAssetType>> watchAssetTypes() {
    return _db
        .select(_db.savingsAssetTypeRows)
        .watch()
        .map((rows) => rows.map(_toDomain).toList());
  }

  @override
  Future<void> addAssetType(domain.SavingsAssetType assetType) async {
    if (domain.SystemSavingsAssets.isSystem(assetType.id)) {
      throw ArgumentError.value(
        assetType.id,
        'assetType.id',
        'id dành riêng cho tài sản hệ thống',
      );
    }
    await _db.into(_db.savingsAssetTypeRows).insert(_toCompanion(assetType));
  }

  @override
  Future<void> updateAssetType(domain.SavingsAssetType assetType) async {
    await (_db.update(
      _db.savingsAssetTypeRows,
    )..where((r) => r.id.equals(assetType.id))).write(
      SavingsAssetTypeRowsCompanion(
        name: Value(assetType.name),
        colorValue: Value(assetType.color.value),
      ),
    );
  }

  @override
  Future<void> renameAssetType(String assetTypeId, String newName) async {
    await (_db.update(
      _db.savingsAssetTypeRows,
    )..where((r) => r.id.equals(assetTypeId))).write(
      SavingsAssetTypeRowsCompanion(name: Value(newName)),
    );
  }

  @override
  Future<void> reactivateAssetType(String assetTypeId) async {
    await (_db.update(
      _db.savingsAssetTypeRows,
    )..where((r) => r.id.equals(assetTypeId))).write(
      const SavingsAssetTypeRowsCompanion(isActive: Value(true)),
    );
  }

  @override
  Future<void> softDeleteAssetType(String assetTypeId) async {
    if (domain.SystemSavingsAssets.isSystem(assetTypeId)) {
      throw SavingsAssetTypeNotDeletableException(assetTypeId);
    }
    final transactions = await _transactionRepository.watchTransactions().first;
    if (computeSavingsAssetTypeBalance(assetTypeId, transactions) != 0) {
      throw SavingsAssetTypeNotEmptyException(assetTypeId);
    }
    await (_db.update(
      _db.savingsAssetTypeRows,
    )..where((r) => r.id.equals(assetTypeId))).write(
      const SavingsAssetTypeRowsCompanion(isActive: Value(false)),
    );
  }

  /// Id loại tài sản đã từng xuất hiện ở bất kỳ chân nào của bất kỳ giao dịch
  /// nào (kể cả đã hoàn tác) — quét THẲNG `transaction_rows`, nhận diện chính
  /// xác bằng `parseSavingsAssetRefId` (không dùng LIKE nên không nhầm tiền tố).
  Future<Set<String>> _usedAssetTypeIds() async {
    final rows = await _db
        .customSelect(
          'SELECT source_kind, source_ref_id, destination_kind, destination_ref_id '
          'FROM transaction_rows '
          "WHERE source_kind = 'memberSavingsAsset' "
          "OR destination_kind = 'memberSavingsAsset'",
        )
        .get();
    final used = <String>{};
    void take(String kind, String? ref) {
      if (kind != PoolKind.memberSavingsAsset.name || ref == null) return;
      final parsed = parseSavingsAssetRefId(ref);
      if (parsed != null) used.add(parsed.assetTypeId);
    }

    for (final r in rows) {
      take(r.read<String>('source_kind'), r.read<String?>('source_ref_id'));
      take(
        r.read<String>('destination_kind'),
        r.read<String?>('destination_ref_id'),
      );
    }
    return used;
  }

  Future<Set<String>> _deletableIds() async {
    final used = await _usedAssetTypeIds();
    final rows = await _db.select(_db.savingsAssetTypeRows).get();
    return {
      for (final r in rows)
        if (!r.isActive &&
            !domain.SystemSavingsAssets.isSystem(r.id) &&
            !used.contains(r.id))
          r.id,
    };
  }

  @override
  Stream<Set<String>> watchDeletableAssetTypeIds() {
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.savingsAssetTypeRows, _db.transactionRows},
        )
        .watch()
        .asyncMap((_) => _deletableIds());
  }

  @override
  Future<void> deleteAssetTypePermanently(String assetTypeId) async {
    await _db.transaction(() async {
      if (!(await _deletableIds()).contains(assetTypeId)) {
        throw SavingsAssetTypeNotDeletableException(assetTypeId);
      }
      await (_db.delete(
        _db.savingsAssetTypeRows,
      )..where((r) => r.id.equals(assetTypeId))).go();
    });
  }
}

