/// Phạm vi truy cập Wallet của phiên hiện tại (P6). CHỈ trả lời "phiên này ĐƯỢC PHÉP
/// mở ví nào" — KHÔNG phải quyền sở hữu: đăng nhập không tự gắn/claim ví nào
/// (claim là luồng tường minh ở phase sau, xem `docs/account-wallet-security-foundation.md`).
sealed class WalletAccessScope {
  const WalletAccessScope();

  /// Chưa đăng nhập (chế độ cục bộ / khách).
  const factory WalletAccessScope.local() = LocalAccessScope;

  /// Đã đăng nhập Account [accountId] (uid Auth — KHÔNG phải memberId).
  const factory WalletAccessScope.account(String accountId) = AccountAccessScope;

  /// `null` ở phạm vi cục bộ.
  String? get accountId;
}

class LocalAccessScope extends WalletAccessScope {
  const LocalAccessScope();
  @override
  String? get accountId => null;

  @override
  bool operator ==(Object other) => other is LocalAccessScope;
  @override
  int get hashCode => 0;
}

class AccountAccessScope extends WalletAccessScope {
  const AccountAccessScope(this.accountId);
  @override
  final String accountId;

  @override
  bool operator ==(Object other) =>
      other is AccountAccessScope && other.accountId == accountId;
  @override
  int get hashCode => accountId.hashCode;
}
