import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/db_encryption/sqlcipher_wallet.dart';
import '../../../l10n/session_localizations.dart';
import '../../providers/database_provider.dart';

/// Informational line: on-device SQLCipher state of the active Wallet.
/// Independent of App Lock (PIN/biometric never re-key the database).
class DbEncryptionStatusLine extends ConsumerWidget {
  const DbEncryptionStatusLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = SessionLocalizations.of(context);
    final status =
        lastDbEncryptionStatus[ref.watch(activeWalletProvider).dbFileName];
    if (text == null || status == null) return const SizedBox.shrink();
    return Padding(
      key: const Key('db_encryption_status'),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Text(
        status == DbEncryptionStatus.encrypted
            ? text.dbEncryptionOn
            : text.dbEncryptionPending,
        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
      ),
    );
  }
}
