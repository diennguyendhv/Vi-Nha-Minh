import 'package:vi_nha_minh/core/crypto/backup_crypto.dart';
import 'package:vi_nha_minh/data/local/db_encryption/db_key_store.dart';

/// In-memory stand-in for the Keystore bridge (same contract: never
/// overwrites, can simulate a lost/unwrappable key).
class MemoryDbKeyStore implements DbKeyStore {
  final entries = <String, DbKeyEntry>{};
  bool unavailable = false;
  int creates = 0;
  @override
  Future<DbKeyEntry?> load(String f) async {
    if (unavailable && entries.containsKey(f)) throw const DbKeyUnavailable();
    return entries[f];
  }

  @override
  Future<DbKeyEntry> create(String f, {String? walletId}) async {
    if (entries.containsKey(f)) throw StateError('db_key_exists');
    creates++;
    return entries[f] = DbKeyEntry(BackupCrypto.randomBytes(32), walletId, 1);
  }

  @override
  Future<void> bindWallet(String f, String walletId) async {
    final e = entries[f]!;
    if (e.walletId != null && e.walletId != walletId) throw StateError('mismatch');
    entries[f] = DbKeyEntry(e.key, walletId, e.version);
  }
}

