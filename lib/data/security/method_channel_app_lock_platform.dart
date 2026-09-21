import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../domain/security/app_lock.dart';

/// Cầu nối MethodChannel tới `AppLockBridge.kt`. Tham số (PIN) chỉ đi qua kênh này,
/// không bao giờ được log.
class MethodChannelAppLockPlatform implements AppLockPlatform {
  MethodChannelAppLockPlatform([MethodChannel? channel])
    : _channel =
          channel ?? const MethodChannel('com.vinhamimh.vi_nha_minh/app_lock');

  final MethodChannel _channel;

  @override
  Future<AppLockStatus> status() async {
    final m = await _channel.invokeMapMethod<String, Object?>('status');
    if (m == null) return AppLockStatus.disabled;
    return AppLockStatus(
      enabled: m['enabled'] == true,
      biometricEnabled: m['biometric'] == true,
      failedAttempts: (m['failedAttempts'] as int?) ?? 0,
      lockoutRemaining: Duration(
        milliseconds: (m['lockoutRemainingMs'] as num?)?.toInt() ?? 0,
      ),
      credentialBroken: m['credentialBroken'] == true,
    );
  }

  @override
  Future<void> setPin(String pin, {bool rotateKey = false}) =>
      _channel.invokeMethod<void>('setPin', {
        'pin': pin,
        'rotateKey': rotateKey,
      });

  @override
  Future<PinVerifyResult> verifyPin(String pin) async {
    final m = await _channel.invokeMapMethod<String, Object?>('verifyPin', {
      'pin': pin,
    });
    final outcome = switch (m?['result']) {
      'ok' => PinVerifyOutcome.ok,
      'wrong' => PinVerifyOutcome.wrong,
      'locked_out' => PinVerifyOutcome.lockedOut,
      'no_credential' => PinVerifyOutcome.noCredential,
      _ => PinVerifyOutcome.broken,
    };
    return PinVerifyResult(
      outcome,
      lockoutRemaining: Duration(
        milliseconds: (m?['remainingMs'] as num?)?.toInt() ?? 0,
      ),
      failedAttempts: (m?['failedAttempts'] as int?) ?? 0,
    );
  }

  @override
  Future<void> setBiometricEnabled(bool enabled) =>
      _channel.invokeMethod<void>('setBiometric', {'enabled': enabled});

  @override
  Future<void> clearAttempts() => _channel.invokeMethod<void>('clearAttempts');

  @override
  Future<void> disable() => _channel.invokeMethod<void>('disable');

  @override
  Future<int> elapsedRealtimeMs() async =>
      (await _channel.invokeMethod<num>('elapsedRealtime'))!.toInt();
}

/// `local_auth` (BiometricPrompt). Kết quả chỉ mở khoá phiên hiện tại.
class LocalAuthDeviceAuthenticator implements DeviceAuthenticator {
  LocalAuthDeviceAuthenticator([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> canUseBiometric() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<BiometricOutcome> authenticateBiometric(String reason) =>
      _authenticate(reason, biometricOnly: true);

  @override
  Future<BiometricOutcome> authenticateDeviceOwner(String reason) =>
      _authenticate(reason, biometricOnly: false);

  Future<BiometricOutcome> _authenticate(
    String reason, {
    required bool biometricOnly,
  }) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          biometricOnly: biometricOnly,
          stickyAuth: false,
          useErrorDialogs: false,
        ),
      );
      return ok
          ? BiometricOutcome.success
          : BiometricOutcome.failedOrCancelled;
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'LockedOut':
        case 'PermanentlyLockedOut':
          return BiometricOutcome.lockedOut;
        case 'NotAvailable':
        case 'NotEnrolled':
        case 'PasscodeNotSet':
          return BiometricOutcome.unavailable;
        default:
          return BiometricOutcome.failedOrCancelled;
      }
    }
  }
}
