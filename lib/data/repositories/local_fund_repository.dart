import 'package:drift/drift.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/fund.dart' as domain;
import '../../domain/errors/domain_exceptions.dart';
import '../../domain/repositories/fund_repository.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../../domain/usecases/compute_pool_balance.dart';
import '../local/app_database.dart';

/// Financial Core V2 (mục 8, F-11): Quỹ chỉ còn identity — không có
/// `FundEntry` riêng, lịch sử/số dư đọc thẳng từ `TransactionRepository`
/// (lọc theo `sourceRefId`/`destinationRefId == fundId`).
class LocalFundRepository implements FundRepository {
  LocalFundRepository(this._db, this._transactionRepository);

  final AppDatabase _db;
  final TransactionRepository _transactionRepository;

  domain.Fund _toDomain(FundRow row) {
    return domain.Fund(
      id: row.id,
      name: row.name,
      color: Color(row.colorValue),
      isActive: row.isActive,
    );
  }

  FundRowsCompanion _toCompanion(domain.Fund f) {
    return FundRowsCompanion.insert(
      id: f.id,
      name: f.name,
      colorValue: f.color.value,
      isActive: Value(f.isActive),
    );
  }

  @override
  Stream<List<domain.Fund>> watchFunds() {
    return _db
        .select(_db.fundRows)
        .watch()
        .map((rows) => rows.map(_toDomain).toList());
  }

  @override
  Future<void> addFund(domain.Fund fund) async {
    await _db.into(_db.fundRows).insert(_toCompanion(fund));
  }

  @override
  Future<void> updateFund(domain.Fund fund) async {
    await (_db.update(
      _db.fundRows,
    )..where((r) => r.id.equals(fund.id))).write(
      FundRowsCompanion(
        name: Value(fund.name),
        colorValue: Value(fund.color.value),
        isActive: Value(fund.isActive),
      ),
    );
  }

  @override
  Future<void> softDeleteFund(String fundId) async {
    final transactions = await _transactionRepository.watchTransactions().first;
    final balance = computeFundBalance(fundId, transactions);
    if (balance != 0) {
      throw FundNotEmptyException(fundId, balance);
    }
    await (_db.update(
      _db.fundRows,
    )..where((r) => r.id.equals(fundId))).write(
      const FundRowsCompanion(isActive: Value(false)),
    );
  }
}
