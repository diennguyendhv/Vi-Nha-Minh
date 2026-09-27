import 'dart:convert';

import 'package:flutter/services.dart';

import '../../core/crypto/family_key_crypto.dart';

/// Khoá thiết bị Family (X25519) của Account [uid] trên máy này, gắn với 1
/// installation P7.1. Mỗi Account 1 slot.
abstract class FamilyDeviceKeyStore {
  Future<({String installationId, FamilyDeviceKey key})?> load(String uid);
  Future<void> store(String uid, String installationId, FamilyDeviceKey key);
  Future<void> clear(String uid);
}

/// Seed private key bọc bằng khoá Android Keystore không xuất được
/// (`FamilyKeyBridge.kt`, alias riêng). Bản rõ không bao giờ vào SharedPreferences,
/// SQLite hay log.
class KeystoreFamilyDeviceKeyStore implements FamilyDeviceKeyStore {
  static const channel = MethodChannel('homewallet/family_key');

  @override
  Future<({String installationId, FamilyDeviceKey key})?> load(
    String uid,
  ) async {
    final raw = await channel.invokeMapMethod<String, String>('load', {
      'uid': uid,
    });
    if (raw == null) return null;
    return (
      installationId: raw['installationId']!,
      key: await FamilyDeviceKey.fromSeed(base64.decode(raw['seed']!)),
    );
  }

  @override
  Future<void> store(String uid, String installationId, FamilyDeviceKey key) =>
      channel.invokeMethod<void>('store', {
        'uid': uid,
        'installationId': installationId,
        'seed': base64.encode(key.seedForStorage()),
      });

  @override
  Future<void> clear(String uid) =>
      channel.invokeMethod<void>('clear', {'uid': uid});
}

/// Test / môi trường không có Keystore.
class MemoryFamilyDeviceKeyStore implements FamilyDeviceKeyStore {
  final _slots = <String, ({String installationId, FamilyDeviceKey key})>{};
  @override
  Future<({String installationId, FamilyDeviceKey key})?> load(
    String uid,
  ) async => _slots[uid];
  @override
  Future<void> store(
    String uid,
    String installationId,
    FamilyDeviceKey key,
  ) async => _slots[uid] = (installationId: installationId, key: key);
  @override
  Future<void> clear(String uid) async => _slots.remove(uid);
}
