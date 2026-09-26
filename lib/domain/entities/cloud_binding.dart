/// Trạng thái ràng buộc Wallet ↔ cloud (P8.1). `none` = chưa claim (không có dòng).
enum CloudBindingState { none, claiming, active }

/// Ràng buộc cloud của Wallet đang mở. DB của ví là nguồn sự thật; registry chỉ cache.
/// [selfMemberId] = FinancialMember mà người dùng TỰ CHỌN là mình khi claim — không
/// bao giờ suy ra từ email/uid/đăng nhập.
class CloudBindingInfo {
  const CloudBindingInfo({
    required this.walletId,
    required this.accountId,
    required this.selfMemberId,
    required this.environment,
    required this.state,
    this.claimRequestId,
    this.cryptoVersion,
    this.keyringRev,
  });

  final String walletId;
  final String accountId;
  final String selfMemberId;
  final String environment;
  final CloudBindingState state;
  final String? claimRequestId;
  final int? cryptoVersion;
  final int? keyringRev;
}
