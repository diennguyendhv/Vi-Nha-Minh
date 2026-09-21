import '../../domain/entities/wallet_identity.dart';
import '../../domain/repositories/wallet_identity_repository.dart';
import '../local/app_database.dart';

class LocalWalletIdentityRepository implements WalletIdentityRepository {
  LocalWalletIdentityRepository(this._db);

  final AppDatabase _db;

  @override
  Future<WalletIdentity> read() async {
    final meta = await _db.select(_db.walletMeta).getSingle();
    final members = await _db.select(_db.financialMemberRows).get()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return WalletIdentity(
      walletId: meta.walletId,
      kind: WalletKind.values.byName(meta.kind),
      createdAt: meta.createdAt,
      members: [
        for (final m in members)
          FinancialMember(
            memberId: m.memberId,
            label: m.label,
            displayOrder: m.displayOrder,
          ),
      ],
    );
  }
}
