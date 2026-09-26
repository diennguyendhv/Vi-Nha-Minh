import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/config/app_environment.dart';
import 'package:vi_nha_minh/core/crypto/backup_crypto.dart';
import 'package:vi_nha_minh/data/backup/backup_key_store.dart';
import 'package:vi_nha_minh/data/backup/backup_service.dart';
import 'package:vi_nha_minh/domain/auth/cloud_session.dart';

import '../auth/cloud_session_test.dart' show MemoryStorage;

const fast = KdfParams(memoryKib: 19456, iterations: 2, parallelism: 1);

class MemoryKeyStore implements BackupKeyStore {
  final Map<String, ({String walletId, Uint8List bmk})> values = {};
  @override
  Future<({String walletId, Uint8List bmk})?> load(String uid) async => values[uid];
  @override
  Future<void> store(String uid, String walletId, Uint8List bmk) async =>
      values[uid] = (walletId: walletId, bmk: bmk);
  @override
  Future<void> clear() async => values.clear();
}

/// In-memory stand-in for the Functions API (the real one is covered by the
/// emulator suite). Records every payload the client would send over the wire.
class FakeServer {
  final wire = <String>[];
  final calls = <String>[];
  Map<String, Object?>? keyring;
  final proofs = <String, String>{};
  final entities = <String, Map<String, Object?>>{};
  var head = 0;
  var generation = 0;

  Future<Map<String, dynamic>> call(String op, Map<String, dynamic> data) async {
    calls.add(op);
    wire.add(jsonEncode(data));
    switch (op) {
      case 'activateSession' || 'recoverSession':
        if (op == 'recoverSession' && proofs[data['proofKind']] != data['proof']) {
          throw const SessionFailure(true);
        }
        return {'generation': ++generation, 'epoch': 1, 'secret': 'S' * 43};
      case 'putBackupKeyring':
        if (data['mode'] == 'create') {
          keyring = {'rev': 1, 'password': data['password'], 'recovery': data['recovery']};
          proofs['recovery'] = data['recoveryProof'] as String;
        } else {
          if (data['oldPasswordProof'] != null &&
              data['oldPasswordProof'] != proofs['password']) {
            throw const SessionFailure(true);
          }
          keyring = {...keyring!, 'rev': (keyring!['rev']! as int) + 1, 'password': data['password']};
        }
        proofs['password'] = data['passwordProof'] as String;
        return {'rev': keyring!['rev']};
      case 'getBackupKeyring':
        return jsonDecode(jsonEncode(keyring)) as Map<String, dynamic>;
      case 'getEncryptedChanges':
        return {'headRev': head, 'envelopes': entities.values.toList()};
      case 'putEncryptedBatch':
        if (data['baseHeadRev'] != head) throw const SessionFailure(false, 'HEAD_MOVED');
        head++;
        for (final e in data['envelopes'] as List) {
          entities[(e as Map)['id'] as String] = Map<String, Object?>.from(e);
        }
        return {'headRev': head};
    }
    throw StateError(op);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({FakeServer server, BackupService service, MemoryKeyStore keys})> device(
    FakeServer server, {
    AppEnvironment env = AppEnvironment.dev,
    String installation = '11111111-1111-4111-8111-111111111111',
  }) async {
    final keys = MemoryKeyStore();
    final session = CloudSession(MemoryStorage(), server.call, () => 'uid-1');
    await session.activate();
    return (
      server: server,
      keys: keys,
      service: BackupService(
        session: session,
        transport: server.call,
        keyStore: keys,
        kdf: fast,
        env: env,
      ),
    );
  }

  test('setup → upload → verify; wire + logs carry no password/key/plaintext', () async {
    final logs = <String>[];
    final previous = debugPrint;
    debugPrint = (m, {wrapWidth}) => logs.add('$m');
    addTearDown(() => debugPrint = previous);
    await runZoned(
      () async {
        final a = await device(FakeServer());
        const password = 'Backup-Password-123';
        final setup = await a.service.enableFixture(password);
        expect(setup.recoveryKey, startsWith('HW1-'));
        final local = (await a.keys.load('uid-1'))!;
        expect(local.bmk.length, 32);
        expect(await a.service.uploadFixture(), 1);
        expect(await a.service.verifyFixture(), devBackupFixture.length);
        final forbidden = [
          password,
          setup.recoveryKey,
          setup.recoveryKey.substring(4, 14),
          base64.encode(local.bmk),
          base64Url.encode(local.bmk),
          '1234567',
          '9876543',
          'Tiền chợ',
          'Quỹ du lịch',
          'Ăn uống',
          'fixture-tx-1',
          'fixture-member-a',
          'amount',
          'note',
        ];
        final everything = [...a.server.wire, ...logs].join('\n');
        for (final value in forbidden) {
          expect(everything.contains(value), isFalse, reason: value);
        }
      },
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => logs.add(line),
      ),
    );
  });

  test('password change: same BMK, only keyring calls, no envelope re-upload', () async {
    final a = await device(FakeServer());
    await a.service.enableFixture('old-password-1');
    await a.service.uploadFixture();
    final before = Map.of(a.server.entities);
    final bmk = (await a.keys.load('uid-1'))!.bmk;
    a.server.calls.clear();
    await expectLater(
      a.service.changePassword(oldPassword: 'wrong-password', newPassword: 'new-password-2'),
      throwsA(isA<BackupKeyException>()),
    );
    await a.service.changePassword(oldPassword: 'old-password-1', newPassword: 'new-password-2');
    expect(a.server.calls.toSet(), {'getBackupKeyring', 'putBackupKeyring'});
    expect(a.server.entities, before);
    expect((await a.keys.load('uid-1'))!.bmk, bmk);
    expect(await a.service.verifyFixture(), devBackupFixture.length);
  });

  test('lost device: new device recovers BMK with Recovery Key or new password only', () async {
    final server = FakeServer();
    final a = await device(server);
    final setup = await a.service.enableFixture('password-one-1');
    await a.service.uploadFixture();
    await a.service.changePassword(oldPassword: 'password-one-1', newPassword: 'password-two-2');
    final b = await device(server);
    await expectLater(
      b.service.recoverOnThisDevice(walletId: setup.walletId, password: 'password-one-1'),
      throwsA(isA<BackupKeyException>()),
    );
    await expectLater(
      b.service.recoverOnThisDevice(
        walletId: setup.walletId,
        recoveryKey: await RecoveryKey.generate().display(),
      ),
      throwsA(isA<BackupKeyException>()),
    );
    expect(b.keys.values, isEmpty);
    await b.service.recoverOnThisDevice(walletId: setup.walletId, recoveryKey: setup.recoveryKey);
    expect((await b.keys.load('uid-1'))!.bmk, (await a.keys.load('uid-1'))!.bmk);
    expect(await b.service.verifyFixture(), devBackupFixture.length);
    final c = await device(server);
    await c.service.recoverOnThisDevice(walletId: setup.walletId, password: 'password-two-2');
    expect(server.calls.where((op) => op == 'recoverSession').length, 2);
  });

  test('revoked device: BMK and P7 credential wiped on DEVICE_REVOKED', () async {
    final server = FakeServer();
    final a = await device(server);
    await a.service.enableFixture('password-one-1');
    expect(a.keys.values, isNotEmpty);
    final revoked = BackupService(
      session: a.service.session,
      transport: (op, data) async => throw const SessionFailure(true, 'DEVICE_REVOKED'),
      keyStore: a.keys,
      kdf: fast,
      env: AppEnvironment.dev,
    );
    await expectLater(revoked.uploadFixture(), throwsA(isA<SessionFailure>()));
    expect(a.keys.values, isEmpty);
    expect(await (a.service.session.storage as MemoryStorage).read('uid-1'), isNull);
  });

  test('SQLCipher gate: non-DEV environments are hard-blocked', () async {
    for (final env in [AppEnvironment.pilot, AppEnvironment.prod]) {
      final a = await device(FakeServer(), env: env);
      await expectLater(a.service.enableFixture('long-enough-pw'), throwsA(isA<BackupBlocked>()));
      await expectLater(a.service.uploadFixture(), throwsA(isA<BackupBlocked>()));
      expect(a.server.calls, ['activateSession']);
    }
    expect(BackupGate.localDbEncryptionPassed, isFalse);
  });

  test('Keystore bridge: BMK wrapped natively, never logged; channel delegation', () async {
    final native = File(
      'android/app/src/main/kotlin/com/vinhamimh/vi_nha_minh/BackupKeyBridge.kt',
    ).readAsStringSync();
    expect(native, contains('AndroidKeyStore'));
    expect(native, contains('AES/GCM/NoPadding'));
    expect(native, contains('cipher.updateAAD(aad(uid, walletId))'));
    expect(native, isNot(matches(RegExp(r'Log\.|println|putString\("bmk", bmk'))));
    for (final path in [
      'lib/core/crypto/backup_crypto.dart',
      'lib/core/crypto/envelope_cipher.dart',
      'lib/data/backup/backup_service.dart',
      'lib/data/backup/backup_key_store.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        isNot(matches(RegExp(r'print\(|debugPrint\(|shared_preferences|cloud_firestore|drift'))),
        reason: path,
      );
    }
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(KeystoreBackupKeyStore.channel, (call) async {
      calls.add(call);
      return call.method == 'load' ? {'walletId': 'fixture-w', 'bmk': base64.encode(List.filled(32, 9))} : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(KeystoreBackupKeyStore.channel, null));
    final store = KeystoreBackupKeyStore();
    await store.store('u', 'fixture-w', Uint8List(32));
    expect((await store.load('u'))!.bmk, List.filled(32, 9));
    await store.clear();
    expect(calls.map((c) => c.method), ['store', 'load', 'clear']);
  });
}
