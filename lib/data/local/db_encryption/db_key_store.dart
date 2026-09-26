import 'dart:convert';

import 'package:flutter/services.dart';

/// Per-Wallet SQLCipher key (DEK-DB). Redacted in [toString]; never persisted
/// in plaintext by Dart code (the native Keystore bridge wraps it).
class DbKeyEntry {
  const DbKeyEntry(this.key, this.walletId, this.version);
  final Uint8List key;

  /// Wallet the key is bound to (null only for a freshly created DB before its
  /// first open wrote `wallet_meta`).
  final String? walletId;
  final int version;
  @override
  String toString() => 'DbKeyEntry(v$version, <redacted>)';
}

/// The key entry exists but cannot be unwrapped (Keystore key lost/invalidated).
class DbKeyUnavailable implements Exception {
  const DbKeyUnavailable();
  @override
  String toString() => 'DbKeyUnavailable';
}

abstract class DbKeyStore {
  /// null ⇒ no entry. Throws [DbKeyUnavailable] if an entry exists but cannot
  /// be unwrapped.
  Future<DbKeyEntry?> load(String dbFileName);

  /// Creates a NEW random key. Fails if one already exists (never overwrites).
  Future<DbKeyEntry> create(String dbFileName, {String? walletId});

  /// Binds a not-yet-bound key to [walletId]; mismatch ⇒ throws.
  Future<void> bindWallet(String dbFileName, String walletId);
}

/// Android Keystore-backed store (`DbKeyBridge.kt`).
class KeystoreDbKeyStore implements DbKeyStore {
  const KeystoreDbKeyStore();
  static const channel = MethodChannel('homewallet/db_key');

  static DbKeyEntry _entry(Map<Object?, Object?> raw) => DbKeyEntry(
    base64.decode(raw['key']! as String),
    raw['walletId'] as String?,
    raw['version']! as int,
  );

  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (e) {
      if (e.code == 'db_key_unavailable') throw const DbKeyUnavailable();
      rethrow;
    }
  }

  @override
  Future<DbKeyEntry?> load(String dbFileName) => _guard(() async {
    final raw = await channel.invokeMapMethod<Object?, Object?>('load', {
      'file': dbFileName,
    });
    return raw == null ? null : _entry(raw);
  });

  @override
  Future<DbKeyEntry> create(String dbFileName, {String? walletId}) =>
      _guard(() async => _entry(
        (await channel.invokeMapMethod<Object?, Object?>('create', {
          'file': dbFileName,
          'walletId': walletId,
        }))!,
      ));

  @override
  Future<void> bindWallet(String dbFileName, String walletId) => _guard(
    () => channel.invokeMethod<void>('bindWallet', {
      'file': dbFileName,
      'walletId': walletId,
    }),
  );
}
