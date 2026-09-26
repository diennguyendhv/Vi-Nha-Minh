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
    _refresh();
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
    final fields = [
      if (change) TextEditingController(),
      TextEditingController(),
      TextEditingController(),
    ];
    final labels = [
      if (change) _text.backupOldPassword,
      _text.backupPassword,
      _text.backupPasswordRepeat,
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(change ? _text.backupChangePassword : _text.backupEnable),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_text.backupPasswordHint),
              for (var i = 0; i < fields.length; i++)
                TextField(
                  key: Key('backup_password_$i'),
                  controller: fields[i],
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(labelText: labels[i]),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_text.cancelSession),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_text.done),
          ),
        ],
      ),
    );
    final values = [for (final f in fields) f.text];
    for (final f in fields) {
      f.dispose();
    }
    if (ok != true) return null;
    final next = values[values.length - 2];
    if (next != values.last || next.length < BackupService.minPasswordLength) {
      throw ArgumentError('password');
    }
    return values;
  }

  Future<void> _showRecoveryKey(String key) async {
    var saved = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => PopScope(
          canPop: saved,
          child: AlertDialog(
            title: Text(_text.recoveryKeyTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_text.recoveryKeyBody),
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
                  title: Text(_text.recoveryKeySaved),
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: saved ? () => Navigator.pop(ctx) : null,
                child: Text(_text.done),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    final enabled = _enabled ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text.backupTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
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
                        final setup = await widget.backup.enableFixture(values.first);
                        if (mounted) await _showRecoveryKey(setup.recoveryKey);
                        return null;
                      }),
                child: Text(text.backupEnable),
              ),
            if (enabled) ...[
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async => 'headRev ${await widget.backup.uploadFixture()}'),
                child: Text(text.backupUpload),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async =>
                          '${await widget.backup.verifyFixture()}/${devBackupFixture.length} OK'),
                child: Text(text.backupVerify),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        final values = await _askPasswords(change: true);
                        if (values == null) return null;
                        if (!await (widget.stepUp?.call() ?? Future.value(true))) {
                          return _text.stepUpFailed;
                        }
                        await widget.backup.changePassword(
                          oldPassword: values.first.isEmpty ? null : values.first,
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
