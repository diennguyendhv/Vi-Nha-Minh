import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/config/app_environment.dart';
import 'package:vi_nha_minh/data/backup/backup_service.dart';
import 'package:vi_nha_minh/data/local/wallet_registry.dart';
import 'package:vi_nha_minh/data/sync/cloud_sync_engine.dart';
import 'package:vi_nha_minh/data/sync/restore_engine.dart';
import 'package:vi_nha_minh/data/sync/restore_storage.dart';
import 'package:vi_nha_minh/domain/auth/cloud_session.dart';

import '../support/fake_cloud.dart';
import '../support/memory_db_key_store.dart';

/// P8.5 — "Tạo lại Recovery Key": CÙNG BMK bọc dưới Recovery Key mới, slot recovery thay
/// nguyên tử (rev+1), Recovery Key cũ vô hiệu ngay, slot mật khẩu + mọi ciphertext giữ
/// nguyên, gửi lại sau mất phản hồi không xoay 2 lần, phiên cũ/thu hồi/sai Account/không
/// đăng nhập gần đây bị từ chối, gián đoạn ⇒ đúng 1 slot hợp lệ.
const _password = 'Mật khẩu sao lưu xoay RK';

/// Closure chỉ giữ [d] (gửi được sang isolate nền của Drift).
Future<Directory> Function() _dirOf(Directory d) =>
    () async => d;

void main() {
  late FakeCloud cloud;
  late FakeDevice a;
  late String walletId;
  late String oldRecoveryKey;

  Map<String, Object?> keyring() =>
      Map<String, Object?>.from(cloud.keyrings['uid-r/$walletId']!);
  String entitiesJson() => jsonEncode(cloud.entities[walletId]);

  setUp(() async {
    cloud = FakeCloud();
    a = FakeDevice(cloud);
    await a.signIn('uid-r');
    await a.claim();
    oldRecoveryKey = (await a.engine.enableBackup(_password))!;
    await a.engine.push();
    walletId = await a.walletId();
  });
  tearDown(() => a.db.close());

  test('Recovery Key mới mở CÙNG BMK; key cũ thất bại; slot mật khẩu + ciphertext giữ nguyên', () async {
    final bmk = (await a.keys.load('uid-r'))!.bmk;
    final before = keyring();
    final entitiesBefore = entitiesJson();
    final head = cloud.wallets[walletId]!['headRev'];
    final logBefore = cloud.log.length;

    final newKey = await a.engine.rotateRecoveryKey();

    expect(newKey, isNot(oldRecoveryKey));
    final after = keyring();
    expect(after['rev'], (before['rev']! as int) + 1);
    expect(jsonEncode(after['password']), jsonEncode(before['password']));
    expect(after['passwordProof'], before['passwordProof']);
    expect(
      jsonEncode(after['recovery']),
      isNot(jsonEncode(before['recovery'])),
    );
    expect(after['recoveryProof'], isNot(before['recoveryProof']));
    // BMK không đổi: key mới + mật khẩu đều mở ra đúng BMK cũ.
    expect(
      (await BackupService.unwrapRecovery(after, walletId, newKey)).bmk,
      bmk,
    );
    expect(
      (await BackupService.unwrapPassword(after, walletId, _password)).bmk,
      bmk,
    );
    await expectLater(
      BackupService.unwrapRecovery(after, walletId, oldRecoveryKey),
      throwsA(anything),
      reason: 'Recovery Key cũ vô hiệu ngay sau khi xoay',
    );
    // Không envelope nào bị ghi/mã hoá lại; chỉ đọc keyring + 1 trang kiểm BMK + ghi keyring.
    expect(entitiesJson(), entitiesBefore);
    expect(cloud.wallets[walletId]!['headRev'], head);
    expect(cloud.log.skip(logBefore).map((l) => l.split('#').first).toList(), [
      'getBackupKeyring',
      'getEncryptedChanges',
      'putBackupKeyring',
    ]);
    expect(await a.engine.backupState(), 'COMPLETE');
  });

  test('mất phản hồi sau commit ⇒ gửi lại cùng rotationId = biên nhận, chỉ xoay 1 lần', () async {
    final rev = keyring()['rev']! as int;
    cloud.dropNextResponseAfterCommit = true;
    final newKey = await a.engine.rotateRecoveryKey();
    expect(keyring()['rev'], rev + 1, reason: 'không xoay lần 2');
    expect(
      cloud.log.where((l) => l.startsWith('putBackupKeyring')).length,
      3,
      reason: 'create (setUp) + lần gửi mất phản hồi + lần gửi lại (biên nhận)',
    );
    final bmk = (await a.keys.load('uid-r'))!.bmk;
    expect(
      (await BackupService.unwrapRecovery(keyring(), walletId, newKey)).bmk,
      bmk,
    );
  });

  test(
    'gián đoạn (mất mạng mọi lần) ⇒ slot cũ vẫn là slot hợp lệ DUY NHẤT',
    () async {
      final before = keyring();
      cloud.offline = true;
      await expectLater(
        a.engine.rotateRecoveryKey(),
        throwsA(isA<SessionFailure>()),
      );
      cloud.offline = false;
      expect(jsonEncode(keyring()), jsonEncode(before));
      final bmk = (await a.keys.load('uid-r'))!.bmk;
      expect(
        (await BackupService.unwrapRecovery(
          keyring(),
          walletId,
          oldRecoveryKey,
        )).bmk,
        bmk,
      );
    },
  );

  test(
    'xoay đồng thời: yêu cầu với rev cũ ⇒ KEYRING_CHANGED, đúng 1 slot hợp lệ',
    () async {
      final staleRev = keyring()['rev'];
      final first = await a.engine.rotateRecoveryKey();
      final before = jsonEncode(keyring());
      final slot = await BackupService.newRecoverySlot(
        bmk: (await a.keys.load('uid-r'))!.bmk,
        walletId: walletId,
      );
      await expectLater(
        cloud.call('putBackupKeyring', {
          ...await a.session.credential(),
          'walletId': walletId,
          'mode': 'rotateRecovery',
          'expectedRev': staleRev,
          'recovery': slot.slot,
          'recoveryProof': slot.proof,
          'rotationId': 'x' * 43,
        }),
        throwsA(
          isA<SessionFailure>().having((e) => e.reason, 'r', 'KEYRING_CHANGED'),
        ),
      );
      expect(jsonEncode(keyring()), before);
      final bmk = (await a.keys.load('uid-r'))!.bmk;
      expect(
        (await BackupService.unwrapRecovery(keyring(), walletId, first)).bmk,
        bmk,
      );
      await expectLater(
        BackupService.unwrapRecovery(keyring(), walletId, slot.recoveryKey),
        throwsA(anything),
      );
    },
  );

  test('không đăng nhập gần đây / phiên cũ / thiết bị bị thu hồi / sai Account ⇒ từ chối, keyring không đổi', () async {
    final before = jsonEncode(keyring());

    cloud.recentAuth = false;
    await expectLater(
      a.engine.rotateRecoveryKey(),
      throwsA(
        isA<SessionFailure>().having(
          (e) => e.reason,
          'r',
          'RECENT_LOGIN_REQUIRED',
        ),
      ),
    );
    cloud.recentAuth = true;

    cloud.secrets['uid-r'] = 'stale'; // thiết bị khác đã kích hoạt
    await expectLater(
      a.engine.rotateRecoveryKey(),
      throwsA(isA<SessionFailure>().having((e) => e.denied, 'denied', isTrue)),
    );
    cloud.revoked.add('uid-r');
    await expectLater(
      a.engine.rotateRecoveryKey(),
      throwsA(
        isA<SessionFailure>().having((e) => e.reason, 'r', 'DEVICE_REVOKED'),
      ),
    );
    expect(jsonEncode(keyring()), before);

    a.account = 'uid-khac';
    await expectLater(
      a.engine.rotateRecoveryKey(),
      throwsA(
        isA<CloudSyncException>().having((e) => e.reason, 'r', 'other-account'),
      ),
    );
    expect(jsonEncode(keyring()), before);
  });

  test('máy không giữ BMK / chưa bật sao lưu ⇒ không xoay', () async {
    await a.keys.clear();
    await expectLater(
      a.engine.rotateRecoveryKey(),
      throwsA(isA<CloudSyncException>().having((e) => e.reason, 'r', 'no-key')),
    );

    final c = FakeDevice(
      cloud,
      installation: '55555555-5555-4555-8555-555555555555',
    );
    await c.signIn('uid-moi');
    await c.claim();
    await expectLater(
      c.engine.rotateRecoveryKey(),
      throwsA(
        isA<CloudSyncException>().having(
          (e) => e.reason,
          'r',
          'backup-not-enabled',
        ),
      ),
    );
    await c.db.close();
  });

  test('khôi phục trên máy mới: Recovery Key MỚI thành công, key CŨ bị từ chối trước khi tạo file', () async {
    final newKey = await a.engine.rotateRecoveryKey();
    final dir = Directory.systemTemp.createTempSync('vnm_rotate_restore_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final c = FakeDevice(
      cloud,
      installation: '66666666-6666-4666-8666-666666666666',
    );
    await c.signIn('uid-r');
    RestoreEngine engine() => RestoreEngine(
      session: c.session,
      transport: cloud.call,
      keyStore: c.keys,
      registry: WalletRegistry.inMemory(),
      storage: SqlcipherRestoreStorage(
        keyStore: MemoryDbKeyStore(),
        directory: _dirOf(dir),
      ),
      env: AppEnvironment.dev,
    );
    await expectLater(
      engine().restore(walletId: walletId, recoveryKey: oldRecoveryKey),
      throwsA(
        isA<RestoreException>().having((e) => e.reason, 'r', 'wrong-secret'),
      ),
    );
    expect(dir.listSync(), isEmpty);
    final result = await engine().restore(
      walletId: walletId,
      recoveryKey: newKey,
    );
    expect(result.walletId, walletId);
    await c.db.close();
  });
}
