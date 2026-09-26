import 'dart:convert';

import 'package:flutter/services.dart';

/// Local, device-only copy of the Wallet Backup Master Key.
abstract class BackupKeyStore {
  Future<({String walletId, Uint8List bmk})?> load(String uid);
  Future<void> store(String uid, String walletId, Uint8List bmk);
  Future<void> clear();
}

/// BMK wrapped by a non-exportable Android Keystore key (`BackupKeyBridge.kt`).
/// Plain BMK never touches SharedPreferences, SQLite or logs.
class KeystoreBackupKeyStore implements BackupKeyStore {
  static const channel = MethodChannel('homewallet/backup_key');
  @override
  Future<({String walletId, Uint8List bmk})?> load(String uid) async {
    final raw = await channel.invokeMapMethod<String, String>('load', {
      'uid': uid,
    });
    if (raw == null) return null;
    return (walletId: raw['walletId']!, bmk: base64.decode(raw['bmk']!));
  }

  @override
  Future<void> store(String uid, String walletId, Uint8List bmk) =>
      channel.invokeMethod<void>('store', {
        'uid': uid,
        'walletId': walletId,
        'bmk': base64.encode(bmk),
      });
  @override
  Future<void> clear() => channel.invokeMethod<void>('clear');
}
