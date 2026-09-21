/// Danh tính XÁC THỰC (Account) — KHÔNG phải danh tính tài chính.
/// Cố ý KHÔNG có walletId/memberId/vai trò Owner-Member/gói/familyId: đăng nhập
/// không thiết lập những khái niệm đó (chúng thuộc phase claim/membership sau).
class AccountIdentity {
  const AccountIdentity({
    required this.uid,
    required this.provider,
    this.email,
    this.displayName,
    this.photoUrl,
  });

  final String uid;
  final String provider;
  final String? email;
  final String? displayName;
  final String? photoUrl;

  static const providerGoogle = 'google';

  /// Nhãn hiển thị an toàn cho UI.
  String get label => (displayName?.trim().isNotEmpty ?? false)
      ? displayName!.trim()
      : (email ?? uid);

  @override
  bool operator ==(Object other) =>
      other is AccountIdentity &&
      other.uid == uid &&
      other.provider == provider &&
      other.email == email &&
      other.displayName == displayName &&
      other.photoUrl == photoUrl;

  @override
  int get hashCode => Object.hash(uid, provider, email, displayName, photoUrl);

  /// Không bao giờ in email/uid đầy đủ ra log.
  @override
  String toString() => 'AccountIdentity(${redactUid(uid)}, $provider)';
}

String redactUid(String uid) =>
    uid.length <= 4 ? '***' : '${uid.substring(0, 4)}***';

String redactEmail(String? email) {
  if (email == null || !email.contains('@')) return '***';
  final at = email.indexOf('@');
  return '${email[0]}***${email.substring(at)}';
}
