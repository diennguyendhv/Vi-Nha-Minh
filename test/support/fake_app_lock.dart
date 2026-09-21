import 'package:vi_nha_minh/domain/security/app_lock.dart';

/// Giả lập native `AppLockBridge` (cùng lịch chặn: từ lần sai thứ 5 → 30 s...).
/// Đồng hồ do test điều khiển bằng [nowMs] (thay cho elapsedRealtime).
class FakeAppLockPlatform implements AppLockPlatform {
  String? _pin; // chỉ là giả lập trong test; bản thật lưu verifier, không lưu PIN
  bool _biometric = false;
  int failed = 0;
  int? _lockoutUntilMs;
  int nowMs = 1000000;
  bool breakCredential = false;
  bool failNextSetPin = false;
  int setPinCalls = 0;
  bool disabled = false;

  @override
  Future<AppLockStatus> status() async => AppLockStatus(
    enabled: _pin != null,
    biometricEnabled: _biometric,
    failedAttempts: failed,
    lockoutRemaining: _remaining,
    credentialBroken: _pin != null && breakCredential,
  );

  Duration get _remaining {
    final u = _lockoutUntilMs;
    if (u == null || u <= nowMs) return Duration.zero;
    return Duration(milliseconds: u - nowMs);
  }

  @override
  Future<void> setPin(String pin, {bool rotateKey = false}) async {
    setPinCalls++;
    if (failNextSetPin) {
      failNextSetPin = false;
      throw StateError('persist failed'); // PIN cũ phải còn nguyên
    }
    _pin = pin;
    failed = 0;
    _lockoutUntilMs = null;
    if (rotateKey) breakCredential = false;
  }

  @override
  Future<PinVerifyResult> verifyPin(String pin) async {
    if (_pin == null) return const PinVerifyResult(PinVerifyOutcome.noCredential);
    if (_remaining > Duration.zero) {
      return PinVerifyResult(
        PinVerifyOutcome.lockedOut,
        lockoutRemaining: _remaining,
        failedAttempts: failed,
      );
    }
    if (breakCredential) return const PinVerifyResult(PinVerifyOutcome.broken);
    failed++;
    if (pin == _pin) {
      failed = 0;
      _lockoutUntilMs = null;
      return const PinVerifyResult(PinVerifyOutcome.ok);
    }
    final delay = switch (failed) {
      < 5 => 0,
      5 => 30000,
      6 => 60000,
      7 => 300000,
      8 => 900000,
      _ => 1800000,
    };
    if (delay > 0) _lockoutUntilMs = nowMs + delay;
    return PinVerifyResult(
      PinVerifyOutcome.wrong,
      lockoutRemaining: _remaining,
      failedAttempts: failed,
    );
  }

  @override
  Future<void> setBiometricEnabled(bool enabled) async {
    if (_pin != null) _biometric = enabled;
  }

  @override
  Future<void> clearAttempts() async {
    failed = 0;
    _lockoutUntilMs = null;
  }

  @override
  Future<void> disable() async {
    _pin = null;
    _biometric = false;
    failed = 0;
    _lockoutUntilMs = null;
    disabled = true;
  }

  @override
  Future<int> elapsedRealtimeMs() async => nowMs;
}

class FakeDeviceAuthenticator implements DeviceAuthenticator {
  bool biometricAvailable = true;
  BiometricOutcome biometricResult = BiometricOutcome.success;
  BiometricOutcome deviceOwnerResult = BiometricOutcome.success;
  int biometricCalls = 0;

  @override
  Future<bool> canUseBiometric() async => biometricAvailable;

  @override
  Future<BiometricOutcome> authenticateBiometric(String reason) async {
    biometricCalls++;
    return biometricResult;
  }

  @override
  Future<BiometricOutcome> authenticateDeviceOwner(String reason) async =>
      deviceOwnerResult;
}
