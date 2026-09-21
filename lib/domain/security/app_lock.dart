/// Khoá ứng dụng (App Lock) — CHỈ bảo vệ THIẾT BỊ này.
///
/// Không phải xác thực Account, không phải quyền Wallet, không phải mã hoá DB.
/// Sinh trắc học chỉ chứng minh "người đang cầm máy" — không bao giờ được dùng để
/// xác định Account/Owner/Membership hay thay Firebase Auth sau này. Cấu hình này
/// thuộc về thiết bị và KHÔNG BAO GIỜ đồng bộ.
library;

/// Độ dài PIN cố định.
const int kPinLength = 6;

/// Ở nền lâu hơn ngưỡng này thì phải mở khoá lại khi quay về.
const Duration kBackgroundLockTimeout = Duration(seconds: 30);

bool isValidPin(String pin) =>
    pin.length == kPinLength && RegExp(r'^[0-9]+$').hasMatch(pin);

/// Trạng thái máy trạng thái khoá. Xem `app_lock_provider.dart` cho bảng chuyển.
enum AppLockPhase { disabled, locked, unlocking, unlocked, tempLockout }

/// Ảnh chụp cấu hình khoá do native trả về.
class AppLockStatus {
  const AppLockStatus({
    required this.enabled,
    this.biometricEnabled = false,
    this.failedAttempts = 0,
    this.lockoutRemaining = Duration.zero,
    this.credentialBroken = false,
  });

  static const disabled = AppLockStatus(enabled: false);

  final bool enabled;
  final bool biometricEnabled;
  final int failedAttempts;
  final Duration lockoutRemaining;

  /// Có verifier nhưng khoá Keystore đã mất (vd. dữ liệu bị chép sang máy khác):
  /// PIN không thể kiểm tra nữa → chỉ còn đường xác minh chủ máy để đặt PIN mới.
  final bool credentialBroken;
}

enum PinVerifyOutcome { ok, wrong, lockedOut, noCredential, broken }

class PinVerifyResult {
  const PinVerifyResult(
    this.outcome, {
    this.lockoutRemaining = Duration.zero,
    this.failedAttempts = 0,
  });

  final PinVerifyOutcome outcome;
  final Duration lockoutRemaining;
  final int failedAttempts;

  bool get isOk => outcome == PinVerifyOutcome.ok;
}

/// Cổng tới native (verifier PIN, Keystore, đồng hồ đơn điệu). Không có logic nghiệp vụ
/// tài chính; không bao giờ log tham số.
abstract class AppLockPlatform {
  Future<AppLockStatus> status();

  /// Ghi verifier mới nguyên tử (cái cũ còn hiệu lực tới khi cái mới ghi xong).
  Future<void> setPin(String pin, {bool rotateKey = false});
  Future<PinVerifyResult> verifyPin(String pin);
  Future<void> setBiometricEnabled(bool enabled);
  Future<void> clearAttempts();

  /// Xoá verifier + khoá Keystore. KHÔNG đụng dữ liệu tài chính.
  Future<void> disable();

  /// Đồng hồ đơn điệu tính cả lúc máy ngủ (ms).
  Future<int> elapsedRealtimeMs();
}

enum BiometricOutcome {
  success,

  /// Không nhận diện được / người dùng huỷ → quay về PIN.
  failedOrCancelled,

  /// Không có phần cứng, chưa đăng ký vân tay/khuôn mặt, hoặc máy không hỗ trợ.
  unavailable,

  /// Khoá tạm/vĩnh viễn của hệ thống sau nhiều lần sai.
  lockedOut,
}

/// Xác thực của hệ điều hành (BiometricPrompt / khoá màn hình).
abstract class DeviceAuthenticator {
  Future<bool> canUseBiometric();
  Future<BiometricOutcome> authenticateBiometric(String reason);

  /// Xác minh chủ máy qua khoá màn hình hệ thống (PIN/hình/mật khẩu của điện thoại)
  /// hoặc sinh trắc — dùng cho luồng quên PIN.
  Future<BiometricOutcome> authenticateDeviceOwner(String reason);
}
