import 'package:drift/drift.dart';

import '../../core/utils/opaque_id.dart';
import '../../domain/entities/wallet_identity.dart';
import '../../domain/repositories/member_repository.dart';
import '../local/app_database.dart';

class LocalMemberRepository implements MemberRepository {
  LocalMemberRepository(this._db);

  final AppDatabase _db;

  static FinancialMember _map(FinancialMemberRow r) => FinancialMember(
    memberId: r.memberId,
    label: r.label,
    displayOrder: r.displayOrder,
  );

  SimpleSelectStatement<$FinancialMemberRowsTable, FinancialMemberRow> _ordered() =>
      _db.select(_db.financialMemberRows)..orderBy([
        (r) => OrderingTerm.asc(r.displayOrder),
        (r) => OrderingTerm.asc(r.memberId),
      ]);

  @override
  Stream<List<FinancialMember>> watchMembers() =>
      _ordered().watch().map((rows) => rows.map(_map).toList());

  @override
  Future<List<FinancialMember>> getMembers() async =>
      (await _ordered().get()).map(_map).toList();

  @override
  Future<FinancialMember?> getMemberById(String memberId) async {
    final row = await (_db.select(_db.financialMemberRows)
          ..where((r) => r.memberId.equals(memberId)))
        .getSingleOrNull();
    return row == null ? null : _map(row);
  }

  @override
  Future<FinancialMember> createMember({required String label}) {
    return _db.transaction(() async {
      final existing = await getMembers();
      final next = existing.isEmpty ? 0 : existing.last.displayOrder + 1;
      final memberId = OpaqueId.generate();
      await _db.into(_db.financialMemberRows).insert(
        FinancialMemberRowsCompanion.insert(
          memberId: memberId,
          label: label,
          displayOrder: next,
          createdAt: DateTime.now(),
        ),
      );
      return FinancialMember(
        memberId: memberId,
        label: label,
        displayOrder: next,
      );
    });
  }
}
