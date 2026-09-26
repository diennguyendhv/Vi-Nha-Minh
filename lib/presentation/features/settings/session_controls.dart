import 'package:flutter/material.dart';

import '../../../data/backup/backup_service.dart';
import '../../../domain/auth/cloud_session.dart';
import '../../../l10n/session_localizations.dart';

/// P7/P7.1 session UI. Status is only the result of the last server call.
/// Firebase Auth alone never replaces an active device: the server answers
/// TAKEOVER_REQUIRED and this widget offers approval-based transfer or
/// lost-device recovery (Backup Password / Recovery Key, never the PIN).
class SessionControls extends StatefulWidget {
  const SessionControls({
    super.key,
    required this.session,
    this.backup,
    this.stepUp,
  });
  final CloudSession session;
  final BackupService? backup;

  /// Required before approving a takeover and before lost-device recovery.
  final StepUp? stepUp;
  @override
  State<SessionControls> createState() => _SessionControlsState();
}

class _SessionControlsState extends State<SessionControls> {
  bool _busy = false;
  String _status = 'unchecked';
  TakeoverTicket? _ticket;

  SessionLocalizations get _text => SessionLocalizations.of(context)!;

  Future<bool> _stepUp() async {
    final ok = await (widget.stepUp?.call() ?? Future.value(true));
    if (!ok && mounted) setState(() => _status = 'stepUpFailed');
    return ok;
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _attempt(action, followUp: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attempt(
    Future<void> Function() action, {
    required bool followUp,
  }) async {
    try {
      await action();
    } on SessionFailure catch (e) {
      if (!mounted) return;
      final status = switch (e.reason) {
        'TAKEOVER_REQUIRED' => 'takeover',
        'RECOVERY_REQUIRED' => 'recovery',
        'DEVICE_REVOKED' => 'revoked',
        'RECENT_LOGIN_REQUIRED' => 'recentLogin',
        'TAKEOVER_PENDING' => 'pending',
        _ => e.denied ? 'denied' : 'unknown',
      };
      setState(() => _status = status);
      if (!followUp) return;
      if (status == 'takeover') await _attempt(_offerTakeover, followUp: false);
      if (status == 'recovery') await _attempt(_lostDevice, followUp: false);
    } on Object {
      if (mounted) setState(() => _status = 'unknown');
    }
  }

  Future<bool> _confirm(String title, String body, String ok, {String? cancel}) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(cancel ?? _text.cancelSession),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ok),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _activate() => _guard(() async {
    if (!await _confirm(
      _text.activateSession,
      _text.confirmSession,
      _text.activateSession,
    )) {
      return;
    }
    if (!mounted) return;
    await widget.session.activate();
    await _check();
  });

  Future<void> _check() async {
    final pending = await widget.session.check();
    if (!mounted) return;
    setState(() => _status = 'ready');
    if (pending == null) return;
    final approve = await _confirm(
      _text.approveTitle,
      _text.approveBody(pending.code),
      _text.approve,
      cancel: _text.reject,
    );
    if (!approve) return widget.session.rejectTakeover(pending.requestId);
    if (!await _stepUp()) return;
    await widget.session.approveTakeover(pending.requestId);
  }

  Future<void> _offerTakeover() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_text.takeoverTitle),
        content: Text(_text.takeoverBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_text.cancelSession),
          ),
          if (widget.backup != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'lost'),
              child: Text(_text.takeoverLost),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'request'),
            child: Text(_text.takeoverRequest),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'request') {
      final ticket = await widget.session.requestTakeover();
      if (mounted) setState(() => _ticket = ticket);
    } else if (choice == 'lost') {
      await _lostDevice();
    }
  }

  Future<void> _finish() => _guard(() async {
    await widget.session.completeTakeover(_ticket!);
    if (!mounted) return;
    setState(() => _ticket = null);
    await _check();
  });

  Future<void> _lostDevice() async {
    final backup = widget.backup;
    if (backup == null) return;
    final wallets = await backup.cloudWallets();
    if (!mounted) return;
    if (wallets.isEmpty) {
      await _confirm(_text.lostTitle, _text.noBackup, _text.done);
      return;
    }
    final secret = TextEditingController();
    var useRecoveryKey = false;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(_text.lostTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_text.lostBody),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(_text.usePassword)),
                  ButtonSegment(value: true, label: Text(_text.useRecoveryKey)),
                ],
                selected: {useRecoveryKey},
                onSelectionChanged: (s) => setLocal(() => useRecoveryKey = s.first),
              ),
              TextField(
                key: const Key('lost_device_secret'),
                controller: secret,
                obscureText: !useRecoveryKey,
                autocorrect: false,
                enableSuggestions: false,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_text.cancelSession),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(_text.recover),
            ),
          ],
        ),
      ),
    );
    final value = secret.text.trim();
    secret.dispose();
    if (go != true || value.isEmpty || !mounted) return;
    if (!await _stepUp()) return;
    try {
      await backup.recoverOnThisDevice(
        walletId: wallets.first,
        password: useRecoveryKey ? null : value,
        recoveryKey: useRecoveryKey ? value : null,
      );
    } on SessionFailure {
      rethrow;
    } on Object {
      if (mounted) setState(() => _status = 'recoverFailed');
      return;
    }
    if (mounted) await _check();
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    final ticket = _ticket;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(switch (_status) {
          'ready' => text.sessionReady,
          'denied' => text.sessionDenied,
          'unknown' => text.sessionUnknown,
          'takeover' => text.takeoverBody,
          'recovery' => text.recoveryRequired,
          'recentLogin' => text.recentLoginRequired,
          'pending' => text.takeoverPending,
          'recoverFailed' => text.recoverFailed,
          'revoked' => text.deviceRevoked,
          'stepUpFailed' => text.stepUpFailed,
          _ => text.sessionUnchecked,
        }),
        if (ticket != null) ...[
          const SizedBox(height: 6),
          Text(text.takeoverWaiting(ticket.code), key: const Key('takeover_code')),
        ],
        Wrap(
          spacing: 8,
          children: [
            if (_status == 'recentLogin' && widget.stepUp != null)
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _guard(() async {
                        if (await _stepUp() && mounted) {
                          setState(() => _status = 'unchecked');
                        }
                      }),
                child: Text(text.reauthenticate),
              ),
            if (ticket != null)
              FilledButton(
                onPressed: _busy ? null : _finish,
                child: Text(text.takeoverFinish),
              ),
            TextButton(
              onPressed: _busy ? null : _activate,
              child: Text(text.activateSession),
            ),
            TextButton(
              onPressed: _busy ? null : () => _guard(_check),
              child: Text(text.checkSession),
            ),
          ],
        ),
      ],
    );
  }
}
