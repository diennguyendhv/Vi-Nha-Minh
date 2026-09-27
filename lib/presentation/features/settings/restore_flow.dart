import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/auth/cloud_session.dart';
import '../../../l10n/session_localizations.dart';
import '../../providers/database_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/sync_provider.dart';
import 'session_controls.dart';

/// Chọn 1 bản sao lưu (id ví mờ, rút gọn) — không bao giờ tự đoán.
Future<String?> pickBackupWallet(BuildContext context, List<String> ids) =>
    showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(SessionLocalizations.of(ctx)!.restorePick),
        children: [
          for (final id in ids)
            SimpleDialogOption(
              key: Key('restore_pick_${id.substring(0, 8)}'),
              onPressed: () => Navigator.pop(ctx, id),
              child: Text('${id.substring(0, 8)}…'),
            ),
        ],
      ),
    );

/// P8.5: khôi phục [walletId] vào ví MỚI rồi mở nó. Ví đã có trên máy ⇒ chỉ mở
/// (không bao giờ ghi đè/gộp). Lỗi ⇒ ví hiện tại không đổi (engine tự dọn file).
Future<void> restoreWalletAndOpen(
  BuildContext context,
  WidgetRef ref,
  String walletId, {
  String? password,
  String? recoveryKey,
}) async {
  final engine = ref.read(restoreEngineProvider);
  if (engine == null) return;
  final text = SessionLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (ref.read(walletRegistryProvider).byWalletId(walletId) != null) {
    ref.read(selectedWalletIdProvider.notifier).state = walletId;
    return;
  }
  try {
    final r = await engine.restore(
      walletId: walletId,
      password: password,
      recoveryKey: recoveryKey,
    );
    // Debug-only: id rút gọn + số lượng theo loại, không nội dung/khoá/bí mật.
    if (kDebugMode) {
      debugPrint(
        '[restore] ok wallet=${r.walletId.substring(0, 8)} file=${r.dbFileName} '
        'headRev=${r.headRev} checkpoint=${r.checkpointVerified} '
        'counts=${r.counts} calls=${engine.calls}',
      );
    }
    ref.read(selectedWalletIdProvider.notifier).state = r.walletId;
    messenger?.showSnackBar(SnackBar(content: Text(text.restoreDone)));
  } on Object catch (e) {
    if (kDebugMode) debugPrint('[restore] failed ${e.runtimeType} $e');
    messenger?.showSnackBar(SnackBar(content: Text(text.restoreFailed)));
  }
}

/// Nút "Khôi phục ví từ bản sao lưu" (thiết bị đã có phiên P7.1 hiện hành).
class RestoreWalletButton extends ConsumerStatefulWidget {
  const RestoreWalletButton({super.key, required this.stepUp});
  final StepUp stepUp;
  @override
  ConsumerState<RestoreWalletButton> createState() =>
      _RestoreWalletButtonState();
}

class _RestoreWalletButtonState extends ConsumerState<RestoreWalletButton> {
  bool _busy = false;

  Future<void> _start() async {
    final backup = ref.read(backupServiceProvider);
    if (backup == null) return;
    final text = SessionLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.maybeOf(context);
    // Danh sách bản sao lưu cần đăng nhập gần đây phía máy chủ.
    if (!await widget.stepUp()) return;
    final List<String> ids;
    try {
      final registry = ref.read(walletRegistryProvider);
      ids = [
        for (final id in await backup.cloudWallets())
          if (registry.byWalletId(id) == null) id,
      ];
    } on Object {
      messenger?.showSnackBar(SnackBar(content: Text(text.restoreFailed)));
      return;
    }
    if (!mounted) return;
    if (ids.isEmpty) {
      messenger?.showSnackBar(SnackBar(content: Text(text.noBackup)));
      return;
    }
    final walletId = ids.length == 1
        ? ids.first
        : await pickBackupWallet(context, ids);
    if (walletId == null || !mounted) return;
    final input = await showDialog<({bool recoveryKey, String value})>(
      context: context,
      builder: (_) => BackupSecretDialog(text: text),
    );
    if (input == null || input.value.isEmpty || !mounted) return;
    await restoreWalletAndOpen(
      context,
      ref,
      walletId,
      password: input.recoveryKey ? null : input.value,
      recoveryKey: input.recoveryKey ? input.value : null,
    );
  }

  @override
  Widget build(BuildContext context) => TextButton(
    key: const Key('restore_wallet_button'),
    onPressed: _busy
        ? null
        : () async {
            setState(() => _busy = true);
            try {
              await _start();
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
    child: Text(SessionLocalizations.of(context)!.restoreAction),
  );
}
