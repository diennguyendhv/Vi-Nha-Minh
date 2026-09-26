import 'package:flutter/material.dart';

import '../../../domain/auth/cloud_session.dart';
import '../../../l10n/session_localizations.dart';

class SessionControls extends StatefulWidget {
  const SessionControls({super.key, required this.session});
  final CloudSession session;
  @override
  State<SessionControls> createState() => _SessionControlsState();
}

class _SessionControlsState extends State<SessionControls> {
  bool _busy = false;
  String _status = 'unchecked';
  Future<void> _run(bool activate) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (activate) {
        final text = SessionLocalizations.of(context)!;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(text.activateSession),
            content: Text(text.confirmSession),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(text.cancelSession),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(text.activateSession),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        await widget.session.activate();
      }
      await widget.session.check();
      if (mounted) setState(() => _status = 'ready');
    } on SessionFailure catch (e) {
      if (mounted) setState(() => _status = e.denied ? 'denied' : 'unknown');
    } on Object {
      if (mounted) setState(() => _status = 'unknown');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = SessionLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(switch (_status) {
          'ready' => text.sessionReady,
          'denied' => text.sessionDenied,
          'unknown' => text.sessionUnknown,
          _ => text.sessionUnchecked,
        }),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: _busy ? null : () => _run(true),
              child: Text(text.activateSession),
            ),
            TextButton(
              onPressed: _busy ? null : () => _run(false),
              child: Text(text.checkSession),
            ),
          ],
        ),
      ],
    );
  }
}
