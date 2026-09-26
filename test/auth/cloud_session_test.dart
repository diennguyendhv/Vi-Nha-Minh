import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/auth/cloud_session.dart';
import 'package:vi_nha_minh/data/auth/session_storage.dart';

class MemoryStorage implements SessionStorage {
  String? owner;
  Map<String, dynamic>? value;
  @override
  Future<String> installationId() async =>
      '11111111-1111-4111-8111-111111111111';
  @override
  Future<Map<String, dynamic>?> read(String uid) async =>
      uid == owner ? value : null;
  @override
  Future<void> write(String uid, Map<String, dynamic> credential) async {
    owner = uid;
    value = credential;
  }

  @override
  Future<void> clear() async {
    owner = null;
    value = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('reopen reads existing credential; refresh does not activate; accounts isolated', () async {
    final storage = MemoryStorage();
    String? uid = 'a';
    final calls = <String>[];
    Future<Map<String, dynamic>> transport(
      String op,
      Map<String, dynamic> data,
    ) async {
      calls.add(op);
      if (op == 'activateSession') return {'generation': 1, 'secret': 'a' * 43};
      return {'allowed': true};
    }

    final session = CloudSession(storage, transport, () => uid);
    await session.activate();
    final reopened = CloudSession(storage, transport, () => uid);
    await reopened.check();
    await reopened.check();
    expect(calls.where((c) => c == 'activateSession').length, 1);
    uid = 'b';
    await expectLater(reopened.check(), throwsA(isA<SessionFailure>()));
    expect(await storage.read('b'), isNull);
  });
  test('logout serializes behind activation, clears secret and preserves installation', () async {
    final storage = MemoryStorage();
    final gate = Completer<Map<String, dynamic>>();
    String? uid = 'a';
    final installation = await storage.installationId();
    final session = CloudSession(storage, (op, data) async {
      if (op == 'activateSession') return gate.future;
      throw const SessionFailure(
        true,
      ); // stale A cannot revoke B; logout still works
    }, () => uid);
    final activation = session.activate();
    final logout = session.signOut(() async => uid = null);
    gate.complete({'generation': 1, 'secret': 'a' * 43});
    await activation;
    await logout;
    expect(storage.value, isNull);
    expect(uid, isNull);
    expect(await storage.installationId(), installation);
  });
  test(
    'account changes during activation cannot save old credential',
    () async {
      final storage = MemoryStorage();
      String? uid = 'a';
      final session = CloudSession(storage, (op, data) async {
        uid = 'b';
        return {'generation': 1, 'secret': 'a' * 43};
      }, () => uid);
      await expectLater(session.activate(), throwsA(isA<SessionFailure>()));
      expect(storage.value, isNull);
    },
  );
  test(
    'offline logout clears credential without modifying independent state',
    () async {
      final storage = MemoryStorage();
      await storage.write('a', {'secret': 'a' * 43});
      var signedOut = false;
      final session = CloudSession(
        storage,
        (_, _) async => throw const SessionFailure(false),
        () => 'a',
      );
      await session.signOut(() async => signedOut = true);
      expect(signedOut, true);
      expect(storage.value, isNull);
    },
  );
  test(
    'method channel delegates credential persistence to native secure storage',
    () async {
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(KeystoreSessionStorage.channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'installationId') return 'stable-installation';
        if (call.method == 'read') return jsonEncode({'secret': 'test'});
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          KeystoreSessionStorage.channel,
          null,
        ),
      );
      final storage = KeystoreSessionStorage();
      expect(await storage.installationId(), await storage.installationId());
      await storage.write('a', {'secret': 'test'});
      expect((await storage.read('a'))!['secret'], 'test');
      await storage.clear();
      expect(calls.map((c) => c.method), [
        'installationId',
        'installationId',
        'write',
        'read',
        'clear',
      ]);
    },
  );
  test('native storage encrypts before persistence; no secret logs or financial dependencies', () {
    final native = File(
      'android/app/src/main/kotlin/com/vinhamimh/vi_nha_minh/SessionBridge.kt',
    ).readAsStringSync();
    expect(native, contains('AndroidKeyStore'));
    expect(native, contains('AES/GCM/NoPadding'));
    expect(native, contains('cipher.doFinal(value.toByteArray'));
    expect(native, contains('cipher.updateAAD(uid.toByteArray'));
    expect(native, isNot(contains('putString("credential", value)')));
    expect(native, isNot(matches(RegExp(r'Log\.|println|app_lock|sqlite'))));
    for (final path in [
      'lib/domain/auth/cloud_session.dart',
      'lib/data/auth/session_storage.dart',
      'lib/data/auth/session_transport.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        isNot(
          matches(
            RegExp(
              r'print\(|debugPrint\(|shared_preferences|database_provider|boundAccountId|cloud_firestore',
            ),
          ),
        ),
      );
    }
  });
}
