import 'package:drift/drift.dart';

import '../../domain/entities/fund_entry.dart' as domain;
import '../../domain/repositories/fund_repository.dart';
import '../local/app_database.dart';

/// Lưu các khoản nạp/mua của Quỹ bằng SQLite trên máy (Giai đoạn A —
/// local-first), thay bằng `FirestoreFundRepository` khi gia đình chuyển
/// sang `syncMode: "cloud"`.
class LocalFundRepository implements FundRepository {
  LocalFundRepository(this._db);

  final AppDatabase _db;

  domain.FundEntry _toDomain(FundEntryRow row) {
    return domain.FundEntry(
      id: row.id,
      fundId: row.fundId,
      kind: domain.FundEntryKind.values.byName(row.kind),
      amount: row.amount,
      date: row.date,
      note: row.note,
    );
  }

  FundEntryRowsCompanion _toCompanion(domain.FundEntry e) {
    return FundEntryRowsCompanion(
      id: Value(e.id),
      fundId: Value(e.fundId),
      kind: Value(e.kind.name),
      amount: Value(e.amount),
      date: Value(e.date),
      note: Value(e.note),
    );
  }

  @override
  Stream<List<domain.FundEntry>> watchEntries(String fundId) {
    final query = _db.select(_db.fundEntryRows)
      ..where((row) => row.fundId.equals(fundId));
    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  @override
  Future<void> addEntry(domain.FundEntry entry) async {
    await _db.into(_db.fundEntryRows).insert(_toCompanion(entry));
  }
}
