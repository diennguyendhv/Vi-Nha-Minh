import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_database.dart';
import '../wallet_descriptor.dart';
import 'db_key_store.dart';
import 'sqlcipher_wallet.dart';

/// Runs BEFORE any UI/registry opens the local Wallet: performs the one-time
/// plaintext → SQLCipher migration (verified, with rollback) or checks the key.
/// Returns the recovery state when the encrypted DB cannot be opened (key
/// lost) — the caller must then show recovery UI and never open/overwrite it.
Future<DbRecoveryRequired?> preflightLocalWalletDatabase({
  DbKeyStore keyStore = const KeystoreDbKeyStore(),
  Future<Directory> Function()? directory,
}) async {
  final name = WalletDescriptor.legacyLocal.dbFileName;
  try {
    final dir = await (directory ?? getApplicationDocumentsDirectory)();
    final plan = await WalletDbEncryption(keyStore).prepare(
      File(p.join(dir.path, name)),
      name,
    );
    lastDbEncryptionStatus[name] = plan.status;
    return null;
  } on DbRecoveryRequired catch (e) {
    return e;
  } on Object {
    // Unexpected: leave the file untouched; the normal open path re-evaluates.
    return null;
  }
}
