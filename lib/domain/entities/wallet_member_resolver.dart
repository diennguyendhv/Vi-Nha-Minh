import 'family_member.dart';
import 'wallet_identity.dart';

/// Lớp tương thích duy nhất giữa mã hiện tại (enum [FamilyMember] Vợ/Chồng) và danh
/// tính tài chính tường minh ([FinancialMember]) của Wallet — để phase Account sau
/// này gắn tài khoản vào `memberId` mà KHÔNG phải viết lại Financial Core.
///
/// Với Wallet di sản, `memberId` của [FamilyMember.vo] / [FamilyMember.chong] chính là
/// `'vo'` / `'chong'` (giữ nguyên). Đây là quyết định TƯƠNG THÍCH DI SẢN, không phải
/// chiến lược ID chung: Wallet mới sẽ có `memberId` mờ và đi qua bảng thành viên
/// (phase "thành viên là dữ liệu"), khi enum được thay thế.
class WalletMemberResolver {
  const WalletMemberResolver(this._identity);

  final WalletIdentity _identity;

  /// `memberId` lưu trong cột ref cho [member] (Wallet di sản: `member.name`).
  static String legacyMemberId(FamilyMember member) => member.name;

  /// [FamilyMember] tương ứng với `memberId` di sản, hoặc null nếu không phải `vo`/`chong`.
  static FamilyMember? legacyMemberFor(String memberId) {
    for (final m in FamilyMember.values) {
      if (m.name == memberId) return m;
    }
    return null;
  }

  /// Danh tính tài chính tường minh của [member]; null nếu Wallet không có thành
  /// viên đó (không xảy ra với Wallet di sản).
  FinancialMember? resolve(FamilyMember member) =>
      _identity.memberById(legacyMemberId(member));

  WalletIdentity get identity => _identity;
}
