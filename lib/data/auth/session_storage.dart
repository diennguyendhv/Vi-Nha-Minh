import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/auth/cloud_session.dart';

class KeystoreSessionStorage implements SessionStorage {
  static const channel = MethodChannel('homewallet/session');
  @override
  Future<String> installationId() async =>
      (await channel.invokeMethod<String>('installationId'))!;
  @override
  Future<Map<String, dynamic>?> read(String uid) async {
    final raw = await channel.invokeMethod<String>('read', {'uid': uid});
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  @override
  Future<void> write(String uid, Map<String, dynamic> credential) =>
      channel.invokeMethod<void>('write', {
        'uid': uid,
        'value': jsonEncode(credential),
      });
  @override
  Future<void> clear() => channel.invokeMethod<void>('clear');
}
