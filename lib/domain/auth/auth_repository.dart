import 'account_identity.dart';

enum AuthFailureReason {
  /// Người dùng đóng hộp thoại chọn tài khoản — không phải lỗi.
  cancelled,
  network,
  providerFailure,
  authFailure,

  /// Môi trường build chưa có cấu hình Firebase hợp lệ.
  notConfigured,
}

class AuthFailure implements Exception {
  const AuthFailure(this.reason);
  final AuthFailureReason reason;

  /// Không đính kèm token/email/lỗi gốc để không rò vào log.
  @override
  String toString() => 'AuthFailure(${reason.name})';
}

/// Ranh giới Auth độc lập nhà cung cấp. UI/domain KHÔNG phụ thuộc `User` của
/// FirebaseAuth. Chỉ lo danh tính xác thực; không đụng dữ liệu tài chính.
abstract class AuthRepository {
  /// Có cấu hình hợp lệ để đăng nhập trong môi trường này không.
  bool get isAvailable;

  Stream<AccountIdentity?> watchAuthState();
  AccountIdentity? currentAccount();

  /// Ném [AuthFailure] khi thất bại/huỷ.
  Future<AccountIdentity> signInWithGoogle();

  /// Chỉ xoá phiên xác thực. KHÔNG xoá Wallet cục bộ.
  Future<void> signOut();
}
