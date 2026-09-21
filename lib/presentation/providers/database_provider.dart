import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/local_wallet_identity_repository.dart';
import '../../domain/entities/wallet_identity.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Danh tính tường minh của Wallet đang mở (P2). Chưa có màn hình nào dùng — chỉ để
/// các phase Account/Membership sau này gắn vào, không đổi hành vi hiện tại.
final walletIdentityProvider = FutureProvider<WalletIdentity>((ref) {
  return LocalWalletIdentityRepository(ref.watch(appDatabaseProvider)).read();
});
