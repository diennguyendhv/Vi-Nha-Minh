import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/local/wallet_descriptor.dart';
import '../../data/local/wallet_registry.dart';
import '../../data/repositories/local_wallet_identity_repository.dart';
import '../../domain/entities/wallet_access_scope.dart';
import '../../domain/entities/wallet_identity.dart';
import 'auth_providers.dart';

/// Registry Wallet toàn ứng dụng. `main` override bằng bản đã nạp/đăng ký; mặc định
/// rỗng (test) ⇒ rơi về ví cục bộ mặc định.
final walletRegistryProvider = Provider<WalletRegistry>(
  (ref) => WalletRegistry.inMemory(),
);

/// Phạm vi truy cập của phiên: chưa đăng nhập = cục bộ, đã đăng nhập = Account.
/// CHỈ phụ thuộc uid — đổi tên/ảnh không làm đóng/mở lại DB. Đăng nhập KHÔNG tự
/// claim/gắn ví: nó chỉ đổi tập ví ĐƯỢC PHÉP mở.
final walletAccessScopeProvider = Provider<WalletAccessScope>((ref) {
  final uid = ref.watch(accountProvider.select((a) => a.valueOrNull?.uid));
  return uid == null
      ? const WalletAccessScope.local()
      : WalletAccessScope.account(uid);
});

/// Ví người dùng chọn TRONG PHIÊN (chỉ bộ nhớ). Tự về `null` khi phạm vi đổi
/// (đăng xuất/đổi Account) — không bao giờ sống sót qua ranh giới Account.
final selectedWalletIdProvider = StateProvider<String?>((ref) {
  ref.watch(walletAccessScopeProvider);
  return null;
});

/// Ví đang hoạt động (giải qua registry + phạm vi). Registry rỗng ⇒ ví cục bộ mặc định.
final activeWalletProvider = Provider<WalletDescriptor>((ref) {
  final scope = ref.watch(walletAccessScopeProvider);
  final entry = ref
      .watch(walletRegistryProvider)
      .resolveActive(scope, preferredWalletId: ref.watch(selectedWalletIdProvider));
  return entry?.toDescriptor() ?? WalletDescriptor.legacyLocal;
});

/// Khoá phiên ví: đổi ⇒ mọi state gắn với ví trước phải reset.
final walletSessionKeyProvider = Provider<String>(
  (ref) => ref.watch(activeWalletProvider.select((w) => w.dbFileName)),
);

/// Cách mở DB của 1 ví. Test override để dùng DB tạm.
final walletDatabaseFactoryProvider =
    Provider<AppDatabase Function(WalletDescriptor wallet)>(
      (ref) =>
          (wallet) => AppDatabase(wallet: wallet),
    );

/// DB của ví ĐANG hoạt động. Đổi ví/Account ⇒ provider này bị dựng lại: DB cũ được
/// đóng (`onDispose`) và MỌI repository/stream phụ thuộc nó bị huỷ + dựng lại trên DB
/// mới — không provider nào giữ dòng của ví trước.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  ref.watch(walletSessionKeyProvider);
  final db = ref.read(walletDatabaseFactoryProvider)(
    ref.read(activeWalletProvider),
  );
  ref.onDispose(db.close);
  return db;
});

/// Danh tính tường minh của Wallet đang mở (P2). Chưa có màn hình nào dùng — chỉ để
/// các phase Account/Membership sau này gắn vào, không đổi hành vi hiện tại.
final walletIdentityProvider = FutureProvider<WalletIdentity>((ref) {
  return LocalWalletIdentityRepository(ref.watch(appDatabaseProvider)).read();
});
