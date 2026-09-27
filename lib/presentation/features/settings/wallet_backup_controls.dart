import 'package:drift/drift.dart' show QueryRow;
import 'package:flutter/material.dart';

import '../../../data/local/app_database.dart';

import '../../../data/backup/backup_service.dart';
import '../../../data/sync/cloud_sync_engine.dart';
import '../../../data/sync/sync_worker.dart';
import '../../../domain/auth/cloud_session.dart';
import '../../../l10n/session_localizations.dart';
import 'backup_controls.dart';

/// Trạng thái sao lưu của ví, đọc thuần từ SQLite cục bộ.
class WalletBackupStatus {
  const WalletBackupStatus({
    required this.binding,
    required this.state,
    required this.pending,
    required this.headRev,
    this.conflicts = 0,
  });
  final String? binding;
  final String? state;
  final int pending;
  final int? headRev;

  /// P10: thay đổi cục bộ bị bản máy chủ thay thế, chờ người dùng xem lại.
  final int conflicts;

  static const query =
      'SELECT (SELECT state FROM cloud_binding) AS b, '
      '(SELECT backup_state FROM sync_state) AS s, '
      '(SELECT server_head_rev FROM sync_state) AS h, '
      '(SELECT COUNT(*) FROM sync_outbox) AS n, '
      '(SELECT COUNT(*) FROM sync_conflicts WHERE resolved = 0) AS k';

  static WalletBackupStatus fromRow(QueryRow r) => WalletBackupStatus(
    binding: r.readNullable<String>('b'),
    state: r.readNullable<String>('s'),
    pending: r.read<int>('n'),
    headRev: r.readNullable<int>('h'),
    conflicts: r.read<int>('k'),
  );

  static Future<WalletBackupStatus> read(AppDatabase db) async =>
      fromRow(await db.customSelect(query).getSingle());
}

/// P8.3/P8.4 (DEV): sao lưu mã hoá của CHÍNH ví đang mở, chỉ khi ví đã claim ACTIVE.
/// Trạng thái đọc từ SQLite cục bộ (outbox/sync_state/binding) — không gọi mạng để
/// hiển thị. Ví chưa claim ⇒ hiện [fallback].
class WalletBackupControls extends StatefulWidget {
  const WalletBackupControls({
    super.key,
    required this.engine,
    required this.worker,
    this.backup,
    this.stepUp,
    this.fallback,
    this.status,
    this.ownerActions = true,
  });
  final CloudSyncEngine engine;
  final SyncWorker worker;

  /// Dùng cho "Đổi Mật khẩu sao lưu" (bọc lại cùng BMK).
  final BackupService? backup;
  final StepUp? stepUp;
  final Widget? fallback;

  /// P10: `false` trên máy Member Family — ẩn đổi Mật khẩu sao lưu / tạo lại Recovery
  /// Key (keyring thuộc Owner).
  final bool ownerActions;

  /// Test: nguồn trạng thái thay cho Drift `watch` (stream Drift treo trong
  /// `flutter_test`). Mặc định theo dõi SQLite cục bộ.
  final Stream<WalletBackupStatus>? status;

  @override
  State<WalletBackupControls> createState() => _WalletBackupControlsState();
}

class _WalletBackupControlsState extends State<WalletBackupControls> {
  bool _busy = false;
  String? _result;
  late Stream<WalletBackupStatus> _status;

  SessionLocalizations get _text => SessionLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _status = widget.status ?? _watch();
  }

  @override
  void didUpdateWidget(WalletBackupControls old) {
    super.didUpdateWidget(old);
    if (!identical(old.engine, widget.engine)) {
      _status = widget.status ?? _watch();
    }
  }

  Stream<WalletBackupStatus> _watch() {
    final db = widget.engine.db;
    return db
        .customSelect(
          WalletBackupStatus.query,
          readsFrom: {
            db.cloudBinding,
            db.syncState,
            db.syncOutbox,
            db.syncConflicts,
          },
        )
        .watchSingle()
        .map(WalletBackupStatus.fromRow);
  }

  Future<void> _run(Future<String?> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final result = await action();
      if (mounted) setState(() => _result = result);
    } on Object {
      if (mounted) setState(() => _result = _text.backupFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _enable() async {
    final values = await showDialog<List<String>>(
      context: context,
      builder: (_) => BackupPasswordDialog(
        title: _text.walletBackupEnable,
        hint: _text.backupPasswordHint,
        labels: [_text.backupPassword, _text.backupPasswordRepeat],
        cancel: _text.cancelSession,
        done: _text.done,
      ),
    );
    if (values == null) return null;
    // Dùng đúng như gõ (chỉ NFC khi dẫn khoá; không bao giờ trim).
    if (values[0] != values[1] ||
        values[0].length < BackupService.minPasswordLength) {
      throw ArgumentError('password');
    }
    final recoveryKey = await widget.engine.enableBackup(values[0]);
    if (recoveryKey != null && mounted) {
      await showRecoveryKeyOnce(context, _text, recoveryKey);
    }
    // Outbox đã có mốc nền ⇒ worker tải lên ngay (mã hoá trên máy).
    widget.worker.start();
    return null;
  }

  Future<String?> _changePassword() async {
    final backup = widget.backup;
    if (backup == null) return null;
    final values = await showDialog<List<String>>(
      context: context,
      builder: (_) => BackupPasswordDialog(
        title: _text.backupChangePassword,
        hint: _text.backupPasswordHint,
        labels: [
          _text.backupOldPassword,
          _text.backupPassword,
          _text.backupPasswordRepeat,
        ],
        cancel: _text.cancelSession,
        done: _text.done,
      ),
    );
    if (values == null) return null;
    if (values[1] != values[2] ||
        values[1].length < BackupService.minPasswordLength) {
      throw ArgumentError('password');
    }
    if (!await (widget.stepUp?.call() ?? Future.value(true))) {
      return _text.stepUpFailed;
    }
    await backup.changePassword(
      oldPassword: values[0].isEmpty ? null : values[0],
      newPassword: values[1],
    );
    return 'OK';
  }

  /// Tạo lại Recovery Key: xác nhận → step-up (xác minh chủ máy + đăng nhập lại) →
  /// xoay (cùng BMK) → hiện key mới ĐÚNG 1 lần. Key chỉ nằm trong bộ nhớ tới khi đóng.
  Future<String?> _rotateRecovery() async {
    final text = _text;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(text.rotateRecoveryConfirmTitle),
        content: Text(text.rotateRecoveryConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(text.cancelSession),
          ),
          FilledButton(
            key: const Key('rotate_recovery_confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(text.rotateRecoveryConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return null;
    if (!await (widget.stepUp?.call() ?? Future.value(true))) {
      return text.stepUpFailed;
    }
    final String recoveryKey;
    try {
      recoveryKey = await widget.engine.rotateRecoveryKey();
    } on Object {
      return text.rotateRecoveryFailed;
    }
    if (mounted) await showRecoveryKeyOnce(context, text, recoveryKey);
    return null;
  }

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: _status,
    builder: (context, snap) {
      final s = snap.data;
      if (s == null) return const SizedBox.shrink();
      if (s.binding != 'ACTIVE') {
        return widget.fallback ?? const SizedBox.shrink();
      }
      final text = _text;
      return Column(
        key: const Key('wallet_backup_controls'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.ownerActions ? text.walletBackupTitle : text.familySyncTitle,
            key: const Key('wallet_backup_title'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(switch (s.state) {
            'COMPLETE' when !widget.ownerActions => text.familySyncComplete,
            'COMPLETE' => text.walletBackupComplete,
            'SEEDING' => text.walletBackupSeeding,
            _ => text.walletBackupOff,
          }, key: const Key('wallet_backup_state')),
          if (s.state != null) ...[
            Text(
              text.walletBackupPending(s.pending),
              key: const Key('wallet_backup_pending'),
            ),
            Text(
              text.walletBackupDiag(widget.engine.calls, '${s.headRev ?? '-'}'),
              key: const Key('wallet_backup_diag'),
              style: const TextStyle(fontSize: 11.5),
            ),
          ],
          if (s.conflicts > 0)
            Text(
              text.familyConflicts(s.conflicts),
              key: const Key('wallet_backup_conflicts'),
            ),
          if (widget.engine.lastOverdrawnPools > 0)
            Text(
              text.familyOverdrawn(widget.engine.lastOverdrawnPools),
              key: const Key('wallet_backup_overdrawn'),
              style: const TextStyle(color: Colors.redAccent),
            ),
          if (_result != null)
            Text(_result!, key: const Key('wallet_backup_result')),
          Wrap(
            spacing: 8,
            children: [
              if (s.state == null)
                TextButton(
                  key: const Key('wallet_backup_enable'),
                  onPressed: _busy ? null : () => _run(_enable),
                  child: Text(text.walletBackupEnable),
                ),
              if (s.state != null) ...[
                TextButton(
                  key: const Key('wallet_backup_sync_now'),
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          widget.worker.requestPull();
                          return null;
                        }),
                  child: Text(text.walletBackupSyncNow),
                ),
                if (widget.backup != null && widget.ownerActions)
                  TextButton(
                    onPressed: _busy ? null : () => _run(_changePassword),
                    child: Text(text.backupChangePassword),
                  ),
                if (widget.ownerActions)
                  TextButton(
                    key: const Key('rotate_recovery_key'),
                    onPressed: _busy ? null : () => _run(_rotateRecovery),
                    child: Text(text.rotateRecoveryAction),
                  ),
              ],
            ],
          ),
        ],
      );
    },
  );
}
