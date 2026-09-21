import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/security/app_lock.dart';

/// Máy trạng thái khoá ứng dụng (MEMORY-ONLY — trạng thái mở khoá KHÔNG bao giờ được lưu):
///
/// ```
/// disabled ──enable(pin)──────────────▶ unlocked
/// locked ──submitPin ok / biometric ok──▶ unlocked
/// locked ──submitPin──▶ unlocking ──wrong──▶ locked (hoặc tempLockout nếu vượt ngưỡng)
/// unlocked ──lockNow / nền ≥ 30 s / process chết──▶ locked
/// tempLockout ──hết giờ──▶ locked
/// locked|unlocked ──disable (đã xác thực PIN)──▶ disabled
/// ```
/// Khởi động lạnh: `initial` = locked nếu đã bật, disabled nếu chưa.
class AppLockState {
  const AppLockState({
    required this.phase,
    this.biometricEnabled = false,
    this.credentialBroken = false,
    this.lockoutRemaining = Duration.zero,
    this.privacyCover = false,
  });

  final AppLockPhase phase;
  final bool biometricEnabled;
  final bool credentialBroken;
  final Duration lockoutRemaining;

  /// Che nội dung trong lúc app không ở foreground (chống lộ khung hình cũ khi quay lại).
  final bool privacyCover;

  bool get enabled => phase != AppLockPhase.disabled;

  /// Nội dung tài chính TUYỆT ĐỐI không được dựng khi đang khoá.
  bool get contentHidden =>
      phase == AppLockPhase.locked ||
      phase == AppLockPhase.unlocking ||
      phase == AppLockPhase.tempLockout;

  AppLockState copyWith({
    AppLockPhase? phase,
    bool? biometricEnabled,
    bool? credentialBroken,
    Duration? lockoutRemaining,
    bool? privacyCover,
  }) => AppLockState(
    phase: phase ?? this.phase,
    biometricEnabled: biometricEnabled ?? this.biometricEnabled,
    credentialBroken: credentialBroken ?? this.credentialBroken,
    lockoutRemaining: lockoutRemaining ?? this.lockoutRemaining,
    privacyCover: privacyCover ?? this.privacyCover,
  );

  static AppLockState fromStatus(AppLockStatus s) {
    if (!s.enabled) return const AppLockState(phase: AppLockPhase.disabled);
    final lockedOut = s.lockoutRemaining > Duration.zero;
    return AppLockState(
      phase: lockedOut ? AppLockPhase.tempLockout : AppLockPhase.locked,
      biometricEnabled: s.biometricEnabled,
      credentialBroken: s.credentialBroken,
      lockoutRemaining: s.lockoutRemaining,
    );
  }
}

/// Bắt buộc override (ở `main` và trong test). Không có mặc định "giả".
final appLockPlatformProvider = Provider<AppLockPlatform>(
  (ref) => throw UnimplementedError('appLockPlatformProvider chưa được cấp'),
);
final deviceAuthenticatorProvider = Provider<DeviceAuthenticator>(
  (ref) => throw UnimplementedError('deviceAuthenticatorProvider chưa được cấp'),
);

/// Trạng thái lúc khởi động lạnh (đọc từ native trước `runApp`, để không có khung hình
/// nào của UI tài chính hiện ra trước cổng khoá).
final appLockInitialStatusProvider = Provider<AppLockStatus>(
  (ref) => AppLockStatus.disabled,
);

final appLockProvider = StateNotifierProvider<AppLockController, AppLockState>(
  (ref) => AppLockController(
    platform: ref.watch(appLockPlatformProvider),
    authenticator: ref.watch(deviceAuthenticatorProvider),
    initial: AppLockState.fromStatus(ref.watch(appLockInitialStatusProvider)),
  ),
);

class AppLockController extends StateNotifier<AppLockState> {
  AppLockController({
    required AppLockPlatform platform,
    required DeviceAuthenticator authenticator,
    required AppLockState initial,
  }) :
       // ignore: prefer_initializing_formals, tham số tên công khai + trường riêng tư
       _platform = platform,
       _auth = authenticator,
       super(initial) {
    if (initial.phase == AppLockPhase.tempLockout) _startLockoutTimer();
  }

  final AppLockPlatform _platform;
  final DeviceAuthenticator _auth;
  Timer? _lockoutTimer;
  Future<int>? _backgroundedAt;
  bool _recoveryVerified = false;

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------- mở khoá

  /// Nhập PIN ở màn khoá. Bỏ qua lần bấm thừa khi đang xác minh.
  Future<PinVerifyResult> submitPin(String pin) async {
    if (state.phase != AppLockPhase.locked) {
      return const PinVerifyResult(PinVerifyOutcome.wrong);
    }
    state = state.copyWith(phase: AppLockPhase.unlocking);
    PinVerifyResult r;
    try {
      r = await _platform.verifyPin(pin);
    } catch (_) {
      r = const PinVerifyResult(PinVerifyOutcome.broken);
    }
    switch (r.outcome) {
      case PinVerifyOutcome.ok:
        _lockoutTimer?.cancel();
        state = state.copyWith(
          phase: AppLockPhase.unlocked,
          lockoutRemaining: Duration.zero,
        );
      case PinVerifyOutcome.lockedOut:
        _enterLockout(r.lockoutRemaining);
      case PinVerifyOutcome.wrong:
        if (r.lockoutRemaining > Duration.zero) {
          _enterLockout(r.lockoutRemaining);
        } else {
          state = state.copyWith(phase: AppLockPhase.locked);
        }
      case PinVerifyOutcome.broken || PinVerifyOutcome.noCredential:
        state = state.copyWith(
          phase: AppLockPhase.locked,
          credentialBroken: true,
        );
    }
    return r;
  }

  Future<BiometricOutcome> unlockWithBiometric() async {
    if (state.phase != AppLockPhase.locked || !state.biometricEnabled) {
      return BiometricOutcome.failedOrCancelled;
    }
    state = state.copyWith(phase: AppLockPhase.unlocking);
    BiometricOutcome o;
    try {
      o = await _auth.authenticateBiometric('Mở khóa Ví Nhà Mình');
    } catch (_) {
      o = BiometricOutcome.failedOrCancelled;
    }
    state = state.copyWith(
      phase: o == BiometricOutcome.success
          ? AppLockPhase.unlocked
          : AppLockPhase.locked,
    );
    return o;
  }

  // ------------------------------------------------- xác minh trong Cài đặt

  /// Kiểm tra PIN hiện tại (đổi PIN / tắt khoá) mà KHÔNG đổi phase. Vẫn tính lần sai
  /// và chịu chặn tạm thời như màn khoá.
  Future<PinVerifyResult> verifyCurrentPin(String pin) async {
    try {
      return await _platform.verifyPin(pin);
    } catch (_) {
      return const PinVerifyResult(PinVerifyOutcome.broken);
    }
  }

  // ------------------------------------------------------------ cấu hình

  /// Bật khoá với PIN đã xác nhận. Phiên hiện tại coi như đã mở khoá.
  Future<void> enable(String pin) async {
    if (!isValidPin(pin)) throw ArgumentError('PIN không hợp lệ');
    await _platform.setPin(pin, rotateKey: true);
    state = const AppLockState(phase: AppLockPhase.unlocked);
  }

  /// Gọi SAU khi PIN hiện tại đã được xác minh. Nguyên tử: lỗi ⇒ PIN cũ giữ nguyên.
  Future<void> changePin(String newPin) async {
    if (!isValidPin(newPin)) throw ArgumentError('PIN không hợp lệ');
    await _platform.setPin(newPin);
  }

  /// Gọi SAU khi PIN hiện tại đã được xác minh. Chỉ xoá verifier + khoá Keystore.
  Future<void> disable() async {
    await _platform.disable();
    _lockoutTimer?.cancel();
    state = const AppLockState(phase: AppLockPhase.disabled);
  }

  /// Bật/tắt sinh trắc. Bật cần 1 lần xác thực thành công ngay lúc đó.
  Future<BiometricOutcome> setBiometric(bool enabled) async {
    if (!state.enabled) return BiometricOutcome.unavailable;
    if (!enabled) {
      await _platform.setBiometricEnabled(false);
      state = state.copyWith(biometricEnabled: false);
      return BiometricOutcome.success;
    }
    if (!await _auth.canUseBiometric()) return BiometricOutcome.unavailable;
    final o = await _auth.authenticateBiometric('Bật mở khóa bằng sinh trắc học');
    if (o == BiometricOutcome.success) {
      await _platform.setBiometricEnabled(true);
      state = state.copyWith(biometricEnabled: true);
    }
    return o;
  }

  void lockNow() {
    if (!state.enabled) return;
    _lockoutTimer?.cancel();
    state = state.copyWith(phase: AppLockPhase.locked, privacyCover: false);
    unawaited(_refreshLockout());
  }

  // ------------------------------------------------------------ quên PIN

  /// Không có cửa hậu "bỏ qua": chỉ chủ máy (khoá màn hình hệ thống) mới đặt lại được.
  /// Không có khoá màn hình an toàn ⇒ `unavailable` và KHÔNG có đường khôi phục —
  /// dữ liệu tài chính không bị xoá.
  Future<BiometricOutcome> verifyDeviceOwnerForRecovery() async {
    BiometricOutcome o;
    try {
      o = await _auth.authenticateDeviceOwner('Xác minh chủ máy để đặt lại mã PIN');
    } catch (_) {
      o = BiometricOutcome.failedOrCancelled;
    }
    _recoveryVerified = o == BiometricOutcome.success;
    return o;
  }

  Future<void> completeRecovery(String newPin) async {
    if (!_recoveryVerified) throw StateError('Chưa xác minh chủ máy');
    if (!isValidPin(newPin)) throw ArgumentError('PIN không hợp lệ');
    _recoveryVerified = false;
    await _platform.setPin(newPin, rotateKey: true);
    await _platform.clearAttempts();
    _lockoutTimer?.cancel();
    state = state.copyWith(
      phase: AppLockPhase.unlocked,
      credentialBroken: false,
      lockoutRemaining: Duration.zero,
    );
  }

  // ------------------------------------------------------------ vòng đời

  /// Chuyển tiếp `AppLifecycleState`. Đo thời gian ở nền bằng đồng hồ native
  /// (elapsedRealtime, gồm cả lúc máy ngủ) — không dùng giờ tường, không âm.
  Future<void> onLifecycle(AppLifecycleState s) async {
    if (!state.enabled) return;
    if (s == AppLifecycleState.resumed) {
      final pending = _backgroundedAt;
      _backgroundedAt = null;
      if (pending != null && state.phase == AppLockPhase.unlocked) {
        var lock = true; // lỗi đo ⇒ khoá (an toàn)
        try {
          final start = await pending;
          final now = await _platform.elapsedRealtimeMs();
          final away = now - start;
          lock = away < 0 || away >= kBackgroundLockTimeout.inMilliseconds;
        } catch (_) {}
        if (lock) {
          lockNow();
        }
      }
      if (state.privacyCover) state = state.copyWith(privacyCover: false);
      return;
    }
    // inactive / hidden / paused: che nội dung và ghi mốc thời gian lần đầu.
    if (state.phase == AppLockPhase.unlocked) {
      if (!state.privacyCover) state = state.copyWith(privacyCover: true);
      _backgroundedAt ??= _platform.elapsedRealtimeMs();
    }
  }

  // ------------------------------------------------------------ nội bộ

  Future<void> _refreshLockout() async {
    try {
      final s = await _platform.status();
      if (s.lockoutRemaining > Duration.zero &&
          state.phase == AppLockPhase.locked) {
        _enterLockout(s.lockoutRemaining);
      }
    } catch (_) {}
  }

  void _enterLockout(Duration remaining) {
    state = state.copyWith(
      phase: AppLockPhase.tempLockout,
      lockoutRemaining: remaining,
    );
    _startLockoutTimer();
  }

  void _startLockoutTimer() {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = state.lockoutRemaining - const Duration(seconds: 1);
      if (left <= Duration.zero) {
        t.cancel();
        state = state.copyWith(
          phase: AppLockPhase.locked,
          lockoutRemaining: Duration.zero,
        );
      } else {
        state = state.copyWith(lockoutRemaining: left);
      }
    });
  }
}
