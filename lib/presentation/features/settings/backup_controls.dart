import 'package:flutter/material.dart';

import '../../../data/backup/backup_service.dart';
import '../../../domain/auth/cloud_session.dart';
import '../../../l10n/session_localizations.dart';

/// DEV-only zero-knowledge backup controls. Uploads the synthetic fixture only
/// (SQLCipher gate); the real local Wallet has no upload path.
class BackupControls extends StatefulWidget {
  const BackupControls({super.key, required this.backup, this.stepUp});
  final BackupService backup;

  /// Required before changing the Backup Password.
  final StepUp? stepUp;
  @override
  State<BackupControls> createState() => _BackupControlsState();
}

class _BackupControlsState extends State<BackupControls> {
  bool _busy = false;
  bool? _enabled;
  String? _result;

  SessionLocalizations get _text => SessionLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    // Revoked by lost-device recovery ⇒ BMK wiped; reflect it immediately.
    widget.backup.session.revokedHandlers.add(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    widget.backup.session.revokedHandlers.remove(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final key = await widget.backup.localKey();
      if (mounted) setState(() => _enabled = key != null);
    } on Object {
      if (mounted) setState(() => _enabled = false);
    }
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
      await _refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<String>?> _askPasswords({required bool change}) async {
    final labels = [
      if (change) _text.backupOldPassword,
      _text.backupPassword,
      _text.backupPasswordRepeat,
    ];
    final values = await showDialog<List<String>>(
      context: context,
      builder: (_) => BackupPasswordDialog(
        title: change ? _text.backupChangePassword : _text.backupEnable,
        hint: _text.backupPasswordHint,
        labels: labels,
        cancel: _text.cancelSession,
        done: _text.done,
      ),
    );
    if (values == null) return null;
    final next = values[values.length - 2];
    if (next != values.last || next.length < BackupService.minPasswordLength) {
      throw ArgumentError('password');
    }
    return values;
  }

  Future<void> _showRecoveryKey(String key) =>
      showRecoveryKeyOnce(context, _text, key);

  @override
  Widget build(BuildContext context) {
    final text = _text;
    final enabled = _enabled ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text.backupTitle,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(enabled ? text.backupOn : text.backupOff),
        if (_result != null) Text(_result!, key: const Key('backup_result')),
        Wrap(
          spacing: 8,
          children: [
            if (!enabled)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        final values = await _askPasswords(change: false);
                        if (values == null) return null;
                        final setup = await widget.backup.enableFixture(
                          values.first,
                        );
                        if (mounted) await _showRecoveryKey(setup.recoveryKey);
                        return null;
                      }),
                child: Text(text.backupEnable),
              ),
            if (enabled) ...[
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () async =>
                            'headRev ${await widget.backup.uploadFixture()}',
                      ),
                child: Text(text.backupUpload),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () async =>
                            '${await widget.backup.verifyFixture()}/${devBackupFixture.length} OK',
                      ),
                child: Text(text.backupVerify),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        final values = await _askPasswords(change: true);
                        if (values == null) return null;
                        if (!await (widget.stepUp?.call() ??
                            Future.value(true))) {
                          return _text.stepUpFailed;
                        }
                        await widget.backup.changePassword(
                          oldPassword: values.first.isEmpty
                              ? null
                              : values.first,
                          newPassword: values[1],
                        );
                        return 'OK';
                      }),
                child: Text(text.backupChangePassword),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Recovery Key hiện ĐÚNG 1 lần; không đóng được trước khi xác nhận đã lưu.
Future<void> showRecoveryKeyOnce(
  BuildContext context,
  SessionLocalizations text,
  String key,
) async {
  var saved = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => PopScope(
        canPop: saved,
        child: AlertDialog(
          title: Text(text.recoveryKeyTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text.recoveryKeyBody),
              const SizedBox(height: 12),
              SelectableText(
                key,
                key: const Key('recovery_key_text'),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              CheckboxListTile(
                key: const Key('recovery_key_saved'),
                value: saved,
                onChanged: (v) => setLocal(() => saved = v ?? false),
                title: Text(text.recoveryKeySaved),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: saved ? () => Navigator.pop(ctx) : null,
              child: Text(text.done),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Owns its controllers: disposed only when the route is gone, never while a
/// TextField can still rebuild during the exit animation (keyboard closing).
class BackupPasswordDialog extends StatefulWidget {
  const BackupPasswordDialog({
    super.key,
    required this.title,
    required this.hint,
    required this.labels,
    required this.cancel,
    required this.done,
  });
  final String title;
  final String hint;
  final List<String> labels;
  final String cancel;
  final String done;
  @override
  State<BackupPasswordDialog> createState() => BackupPasswordDialogState();
}

class BackupPasswordDialogState extends State<BackupPasswordDialog> {
  late final _fields = [for (final _ in widget.labels) TextEditingController()];

  @override
  void dispose() {
    for (final f in _fields) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.hint),
          for (var i = 0; i < _fields.length; i++)
            TextField(
              key: Key('backup_password_$i'),
              controller: _fields[i],
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: widget.labels[i]),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.cancel),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.pop(context, [for (final f in _fields) f.text]),
        child: Text(widget.done),
      ),
    ],
  );
}
