import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/security/app_lock.dart';
import '../../providers/app_lock_provider.dart';
import 'pin_field.dart';
import 'pin_setup_flow.dart';

enum _Mode { enter, recover }

/// Màn khoá tối giản: KHÔNG hiển thị số dư/giao dịch/ghi chú. Được dựng THAY cho toàn bộ
/// nội dung ứng dụng (xem `LockGate`), không phải phủ lên trên.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _controller = TextEditingController();
  _Mode _mode = _Mode.enter;
  String? _message;
  bool _biometricTried = false;

  @override
  void initState() {
    super.initState();
    // Chỉ TỰ hỏi sinh trắc 1 lần mỗi lần khoá; huỷ ⇒ ở lại màn PIN, không lặp vô hạn.
    SchedulerBinding.instance.addPostFrameCallback((_) => _autoBiometric());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _autoBiometric() async {
    if (!mounted || _biometricTried) return;
    final s = ref.read(appLockProvider);
    if (!s.biometricEnabled ||
        s.credentialBroken ||
        s.phase != AppLockPhase.locked) {
      return;
    }
    await _tryBiometric();
  }

  Future<void> _tryBiometric() async {
    _biometricTried = true;
    final o = await ref.read(appLockProvider.notifier).unlockWithBiometric();
    if (!mounted) return;
    switch (o) {
      case BiometricOutcome.success:
      case BiometricOutcome.failedOrCancelled:
        break;
      case BiometricOutcome.lockedOut:
        setState(
          () => _message =
              'Sinh trắc học đang bị khóa tạm thời. Hãy nhập mã PIN.',
        );
      case BiometricOutcome.unavailable:
        setState(
          () => _message = 'Sinh trắc học chưa dùng được. Hãy nhập mã PIN.',
        );
    }
  }

  Future<void> _submit(String pin) async {
    final r = await ref.read(appLockProvider.notifier).submitPin(pin);
    if (!mounted) return;
    _controller.clear();
    setState(() {
      _message = switch (r.outcome) {
        PinVerifyOutcome.ok => null,
        PinVerifyOutcome.wrong => 'Mã PIN không đúng.',
        PinVerifyOutcome.lockedOut => null,
        PinVerifyOutcome.broken || PinVerifyOutcome.noCredential =>
          'Không kiểm tra được mã PIN trên máy này. '
              'Dùng "Quên mã PIN?" để đặt lại.',
      };
    });
  }

  Future<void> _startRecovery() async {
    final o = await ref
        .read(appLockProvider.notifier)
        .verifyDeviceOwnerForRecovery();
    if (!mounted) return;
    switch (o) {
      case BiometricOutcome.success:
        setState(() {
          _mode = _Mode.recover;
          _message = null;
        });
      case BiometricOutcome.unavailable:
        setState(
          () => _message =
              'Điện thoại chưa đặt khóa màn hình nên không xác minh được chủ '
              'máy. Dữ liệu của bạn không bị xóa — hãy nhập đúng mã PIN.',
        );
      case BiometricOutcome.lockedOut:
        setState(
          () => _message =
              'Khóa màn hình đang bị khóa tạm thời. Vui lòng thử lại sau.',
        );
      case BiometricOutcome.failedOrCancelled:
        setState(() => _message = 'Chưa xác minh được chủ máy.');
    }
  }

  static String _mmss(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appLockProvider);
    final lockedOut = s.phase == AppLockPhase.tempLockout;
    final busy = s.phase == AppLockPhase.unlocking;

    return Scaffold(
      key: const Key('lock_screen'),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock_rounded,
                    size: 44,
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Ví Nhà Mình',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 28),
                  if (_mode == _Mode.recover)
                    _recoverBody()
                  else ...[
                    const Text(
                      'Nhập mã PIN',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    PinField(
                      controller: _controller,
                      enabled: !busy && !lockedOut,
                      onCompleted: _submit,
                    ),
                    if (lockedOut) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Nhập sai quá nhiều lần. Thử lại sau '
                        '${_mmss(s.lockoutRemaining)}',
                        key: const Key('lockout_message'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: kPinErrorColor,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                    if (_message != null && !lockedOut) ...[
                      const SizedBox(height: 14),
                      Text(
                        _message!,
                        key: const Key('lock_message'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: kPinErrorColor,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (s.biometricEnabled && !s.credentialBroken)
                      IconButton(
                        key: const Key('biometric_button'),
                        iconSize: 36,
                        color: AppColors.accent,
                        tooltip: 'Mở khóa bằng sinh trắc học',
                        onPressed: busy ? null : _tryBiometric,
                        icon: const Icon(Icons.fingerprint_rounded),
                      ),
                    TextButton(
                      key: const Key('forgot_pin_button'),
                      onPressed: busy ? null : _startRecovery,
                      child: const Text('Quên mã PIN?'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _recoverBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PinSetupFlow(
          firstPrompt: 'Đặt mã PIN mới (6 số)',
          onCompleted: (pin) =>
              ref.read(appLockProvider.notifier).completeRecovery(pin),
        ),
        TextButton(
          key: const Key('recover_cancel_button'),
          onPressed: () => setState(() => _mode = _Mode.enter),
          child: const Text('Hủy'),
        ),
      ],
    );
  }
}
