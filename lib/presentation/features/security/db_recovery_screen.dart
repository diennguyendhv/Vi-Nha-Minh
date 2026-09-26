import 'package:flutter/material.dart';

import '../../../l10n/session_localizations.dart';

/// Shown INSTEAD of the app when the local Wallet is encrypted but its key is
/// gone. Deliberately has no "reset"/"start over" action: the encrypted file
/// must be preserved for a future cloud restore.
class DbRecoveryRequiredApp extends StatelessWidget {
  const DbRecoveryRequiredApp({super.key, required this.reason});
  final String reason;

  @override
  Widget build(BuildContext context) => MaterialApp(
    localizationsDelegates: SessionLocalizations.localizationsDelegates,
    supportedLocales: SessionLocalizations.supportedLocales,
    home: Builder(
      builder: (context) {
        final text = SessionLocalizations.of(context)!;
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lock_outline, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    text.dbRecoveryTitle,
                    key: const Key('db_recovery_title'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(text.dbRecoveryBody),
                  const SizedBox(height: 12),
                  Text(reason, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
