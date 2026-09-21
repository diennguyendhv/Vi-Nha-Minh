import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/security/app_lock.dart';
import '../../providers/app_lock_provider.dart';
import 'pin_setup_flow.dart';
import 'pin_verify_dialog.dart';

/// Mục "Bảo mật" trong Cài đặt: Khóa ứng dụng (PIN) → sinh trắc → đổi PIN → khóa ngay.
/// Toàn bộ là cấu hình THIẾT BỊ, không đồng bộ, không liên quan Account.
class SecuritySettingsSection extends ConsumerWidget {
  const SecuritySettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appLockProvider);
    return Column(
      children: [
        _SwitchRow(
          switchKey: const Key('app_lock_switch'),
          title: 'Khóa ứng dụng',
          subtitle: 'Yêu cầu mã PIN khi mở app',
          value: s.enabled,
          onChanged: (v) => v ? _enable(context, ref) : _disable(context, ref),
        ),
        if (s.enabled) ...[
          const Divider(height: 1, color: AppColors.divider),
          _SwitchRow(
            switchKey: const Key('biometric_switch'),
            title: 'Mở khóa bằng sinh trắc học',
            subtitle: 'Vân tay hoặc khuôn mặt; luôn có thể dùng mã PIN',
            value: s.biometricEnabled,
            onChanged: (v) => _toggleBiometric(context, ref, v),
          ),
          const Divider(height: 1, color: AppColors.divider),
          _ActionRow(
            rowKey: const Key('change_pin_row'),
            label: 'Đổi mã PIN',
            onTap: () => _changePin(context, ref),
          ),
          const Divider(height: 1, color: AppColors.divider),
          _ActionRow(
            rowKey: const Key('lock_now_row'),
            label: 'Khóa ngay',
            onTap: () => ref.read(appLockProvider.notifier).lockNow(),
          ),
        ],
      ],
    );
  }

  Future<void> _enable(BuildContext context, WidgetRef ref) async {
    final pin = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const PinSetupScreen(title: 'Đặt mã PIN'),
      ),
    );
    if (pin == null) return;
    await ref.read(appLockProvider.notifier).enable(pin);
    if (!context.mounted) return;
    _toast(context, 'Đã bật khóa ứng dụng.');
  }

  Future<void> _disable(BuildContext context, WidgetRef ref) async {
    final ok = await showPinVerifyDialog(context, title: 'Tắt khóa ứng dụng');
    if (!ok) return;
    await ref.read(appLockProvider.notifier).disable();
    if (!context.mounted) return;
    _toast(context, 'Đã tắt khóa ứng dụng.');
  }

  Future<void> _changePin(BuildContext context, WidgetRef ref) async {
    final ok = await showPinVerifyDialog(context, title: 'Đổi mã PIN');
    if (!ok || !context.mounted) return;
    final pin = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const PinSetupScreen(title: 'Đổi mã PIN'),
      ),
    );
    if (pin == null) return;
    await ref.read(appLockProvider.notifier).changePin(pin);
    if (!context.mounted) return;
    _toast(context, 'Đã đổi mã PIN.');
  }

  Future<void> _toggleBiometric(
    BuildContext context,
    WidgetRef ref,
    bool on,
  ) async {
    final o = await ref.read(appLockProvider.notifier).setBiometric(on);
    if (!context.mounted) return;
    switch (o) {
      case BiometricOutcome.success:
      case BiometricOutcome.failedOrCancelled:
        break;
      case BiometricOutcome.unavailable:
        _toast(
          context,
          'Máy chưa có hoặc chưa cài vân tay/khuôn mặt để dùng tính năng này.',
        );
      case BiometricOutcome.lockedOut:
        _toast(context, 'Sinh trắc học đang bị khóa tạm thời.');
    }
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.switchKey,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Key switchKey;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            key: switchKey,
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.accent,
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.rowKey,
    required this.label,
    required this.onTap,
  });

  final Key rowKey;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: rowKey,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
