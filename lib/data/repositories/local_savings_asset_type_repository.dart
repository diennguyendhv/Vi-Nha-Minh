import 'package:drift/drift.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/family_member.dart';
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
        isActive: Value(assetType.isActive),
      ),
    );
  }

  @override
  Future<void> softDeleteAssetType(String assetTypeId) async {
    final transactions = await _transactionRepository.watchTransactions().first;
    for (final member in FamilyMember.values) {
      final balance = computeMemberSavingsByAssetType(assetTypeId, member, transactions);
      if (balance != 0) {
        throw SavingsAssetTypeNotEmptyException(assetTypeId);
      }
    }
    await (_db.update(
      _db.savingsAssetTypeRows,
    )..where((r) => r.id.equals(assetTypeId))).write(
      const SavingsAssetTypeRowsCompanion(isActive: Value(false)),
    );
  }
}
