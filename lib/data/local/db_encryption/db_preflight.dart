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
    final plan = await WalletDbEncryption(keyStore)
        .prepare(File(p.join(dir.path, name)), name);
    lastDbEncryptionStatus[name] = plan.status;
    return null;
  } on DbRecoveryRequired catch (e) {
    return e;
  } on Object {
    // Unexpected: leave the file untouched; the normal open path re-evaluates.
    return null;
  }
}

/// Ví ĐÃ ĐĂNG KÝ không phải ví di sản (vd ví khôi phục `wallet_<uuid>.sqlite`) sắp được
/// mở làm ví đang hoạt động. Khác ví di sản: file KHÔNG BAO GIỜ được coi là "cài mới" —
/// thiếu file hoặc thiếu/sai khoá ⇒ màn cần khôi phục, KHÔNG tạo DB/khoá mới và KHÔNG
/// lặng lẽ chuyển sang ví khác (dữ liệu sẽ trông như đã mất).
Future<DbRecoveryRequired?> preflightRegisteredWallet(
  String dbFileName, {
  DbKeyStore keyStore = const KeystoreDbKeyStore(),
  Future<Directory> Function()? directory,
}) async {
  if (dbFileName == WalletDescriptor.legacyLocal.dbFileName) return null;
  try {
    final dir = await (directory ?? getApplicationDocumentsDirectory)();
    final file = File(p.join(dir.path, dbFileName));
    if (probeDbFile(file) == DbFileState.absent) {
      return const DbRecoveryRequired('wallet-file-missing');
    }
    final plan = await WalletDbEncryption(keyStore).prepare(file, dbFileName);
    lastDbEncryptionStatus[dbFileName] = plan.status;
    return null;
  } on DbRecoveryRequired catch (e) {
    return e;
  } on Object {
    return null;
  }
}
