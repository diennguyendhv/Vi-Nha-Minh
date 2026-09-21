import '../entities/wallet_identity.dart';

/// Đọc danh tính tường minh của Wallet đang mở (P2: chỉ đọc — không có thao tác ghi,
/// không có Account/Membership).
abstract class WalletIdentityRepository {
  Future<WalletIdentity> read();
}
