import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/auth/firebase_auth_repository.dart';
import '../../../domain/auth/auth_repository.dart';
import '../../../domain/security/app_lock.dart';
import '../../../l10n/session_localizations.dart';
import '../../providers/app_lock_provider.dart';
import '../../providers/auth_providers.dart';
import '../../providers/session_provider.dart';
import 'backup_controls.dart';
import 'family_screen.dart';
import 'restore_flow.dart';
import 'wallet_backup_controls.dart';
import '../../providers/sync_provider.dart';
import 'session_controls.dart';
import 'wallet_claim_controls.dart';

/// Step-up: device credential/biometric where the phone has one, then a fresh
/// Google re-authentication (refreshes auth_time) without signing out.
Future<bool> _stepUp(BuildContext context, WidgetRef ref) async {
  final reason = SessionLocalizations.of(context)!.stepUpReason;
  final outcome = await ref
      .read(deviceAuthenticatorProvider)
      .authenticateDeviceOwner(reason);
  if (outcome != BiometricOutcome.success &&
      outcome != BiometricOutcome.unavailable) {
    return false;
  }
  final repo = ref.read(authRepositoryProvider);
  if (repo is! FirebaseAuthRepository) return false;
  try {
    await repo.reauthenticate();
    return true;
  } on AuthFailure {
    return false;
  }
}

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
              'Đăng nhập chỉ xác nhận danh tính và không tự gắn ví nào hay tự tải dữ liệu lên. Sao lưu chỉ bật khi bạn chọn tường minh.',
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
              backup: ref.watch(backupServiceProvider),
              stepUp: () => _stepUp(context, ref),
              onRecovered: (walletId, {password, recoveryKey}) =>
                  restoreWalletAndOpen(
                    context,
                    ref,
                    walletId,
                    password: password,
                    recoveryKey: recoveryKey,
                  ),
              pickWallet: (ids) => pickBackupWallet(context, ids),
            ),
          if (account != null &&
              ref.watch(walletClaimServiceProvider) != null) ...[
            const SizedBox(height: 10),
            WalletClaimControls(
              key: ValueKey('claim-${account.uid}'),
              service: ref.watch(walletClaimServiceProvider)!,
              accountLabel: account.email ?? account.label,
              stepUp: () => _stepUp(context, ref),
            ),
          ],
          if (account != null &&
              ref.watch(syncWorkerProvider) != null &&
              AppEnvironment.current == AppEnvironment.dev) ...[
            const SizedBox(height: 10),
            // Ví đang mở đã claim ⇒ sao lưu THẬT của ví này; chưa claim ⇒ công cụ
            // fixture DEV cũ (P8).
            WalletBackupControls(
              // Engine mới cho mỗi ví/Account ⇒ state widget không mang sang ví khác.
              key: ObjectKey(ref.watch(cloudSyncEngineProvider)),
              engine: ref.watch(cloudSyncEngineProvider)!,
              worker: ref.watch(syncWorkerProvider)!,
              backup: ref.watch(backupServiceProvider),
              stepUp: () => _stepUp(context, ref),
              // P10: Member Family không có keyring/Recovery Key riêng — chỉ Owner.
              ownerActions: !ref.watch(activeWalletIsFamilyMemberProvider),
              fallback: ref.watch(backupServiceProvider) == null
                  ? null
                  : BackupControls(
                      key: ValueKey('backup-${account.uid}'),
                      backup: ref.watch(backupServiceProvider)!,
                      stepUp: () => _stepUp(context, ref),
                    ),
            ),
            if (ref.watch(restoreEngineProvider) != null)
              RestoreWalletButton(stepUp: () => _stepUp(context, ref)),
          ],
          if (account != null && ref.watch(familyServiceProvider) != null)
            TextButton(
              key: const Key('family_entry'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      FamilyScreen(stepUp: () => _stepUp(context, ref)),
                ),
              ),
              child: Text(SessionLocalizations.of(context)!.familyEntry),
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
