import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/auth/auth_repository.dart';
import '../../providers/auth_providers.dart';
import '../../providers/session_provider.dart';
import 'session_controls.dart';

/// Thẻ Tài khoản (P5). Đăng nhập là TUỲ CHỌN: app cục bộ hoạt động đầy đủ khi chưa
/// đăng nhập. Đăng nhập KHÔNG tải dữ liệu, KHÔNG gắn Vợ/Chồng, KHÔNG sao lưu/đồng bộ.
class AccountSettingsCard extends ConsumerWidget {
  const AccountSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(authRepositoryProvider);
    final account = ref.watch(accountProvider).valueOrNull;
    final action = ref.watch(authActionProvider);
    final controller = ref.read(authActionProvider.notifier);

    return Container(
      key: const Key('account_card'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  account == null
                      ? Icons.person_outline_rounded
                      : Icons.person_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account == null ? 'Chưa đăng nhập' : account.label,
                      key: const Key('account_title'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    Text(
                      account == null
                          ? 'Dữ liệu của bạn đang lưu trên máy này. Đăng nhập là tuỳ chọn.'
                          : (account.email ?? 'Tài khoản Google'),
                      key: const Key('account_subtitle'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (account != null)
            const Text(
              'Đăng nhập chỉ xác nhận danh tính. Dữ liệu tài chính vẫn chỉ nằm trên máy này; chưa được sao lưu hay đồng bộ.',
              key: Key('account_local_note'),
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          if (action.failure != null) ...[
            const SizedBox(height: 8),
            Text(
              _failureText(action.failure!),
              key: const Key('account_error'),
              style: const TextStyle(fontSize: 12.5, color: Colors.redAccent),
            ),
          ],
          const SizedBox(height: 10),
          if (account != null && ref.watch(cloudSessionProvider) != null)
            SessionControls(
              key: ValueKey(account.uid),
              session: ref.watch(cloudSessionProvider)!,
            ),
          if (account == null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('google_sign_in_button'),
                onPressed: !repo.isAvailable || action.busy
                    ? null
                    : controller.signIn,
                icon: action.busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login_rounded, size: 18),
                label: Text(
                  repo.isAvailable
                      ? 'Đăng nhập bằng Google'
                      : 'Đăng nhập chưa khả dụng ở bản này',
                ),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const Key('sign_out_button'),
                onPressed: action.busy
                    ? null
                    : () => _confirmSignOut(context, controller),
                child: const Text('Đăng xuất'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(
    BuildContext context,
    AuthActionController controller,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng xuất?'),
        content: const Text(
          'Chỉ đăng xuất tài khoản. Dữ liệu tài chính trên máy này được giữ nguyên.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            key: const Key('confirm_sign_out'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
    if (ok == true) await controller.signOut();
  }

  static String _failureText(AuthFailureReason r) => switch (r) {
    AuthFailureReason.network => 'Không có kết nối mạng. Vui lòng thử lại.',
    AuthFailureReason.providerFailure =>
      'Không đăng nhập được bằng Google. Vui lòng thử lại.',
    AuthFailureReason.authFailure =>
      'Đăng nhập không thành công. Vui lòng thử lại.',
    AuthFailureReason.notConfigured => 'Đăng nhập chưa khả dụng ở bản này.',
    AuthFailureReason.cancelled => '',
  };
}
