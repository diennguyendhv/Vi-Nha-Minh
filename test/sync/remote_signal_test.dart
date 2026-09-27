import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vi_nha_minh/data/sync/remote_signal.dart';

import '../support/fake_cloud.dart';

/// P10 — đăng ký token FCM cho ví Family: chỉ gọi cloud khi token/installation/ví/
/// Account ĐỔI; mở app lại với cùng token ⇒ 0 lời gọi (không thăm dò).
void main() {
  test('cùng token ⇒ 0 lời gọi; token mới / ví khác / Account khác ⇒ đăng ký lại', () async {
    SharedPreferences.setMockInitialValues({});
    final sent = <Map<String, dynamic>>[];
    final device = FakeDevice(FakeCloud());
    await device.signIn('uid-a');
    final registrar = RemoteSignalRegistrar(
      session: device.session,
      transport: (op, data) async {
        expect(op, 'registerSyncSignal');
        sent.add(data);
        return {'registered': true};
      },
    );
    expect(await registrar.ensureRegistered('wallet-1', 'token-1'), isTrue);
    expect(sent.single['token'], 'token-1');
    expect(sent.single['installationId'], isNotNull);
    // Mở lại app nhiều lần: không gọi cloud.
    for (var i = 0; i < 5; i++) {
      expect(await registrar.ensureRegistered('wallet-1', 'token-1'), isFalse);
    }
    expect(registrar.calls, 1);
    expect(await registrar.ensureRegistered('wallet-1', 'token-2'), isTrue);
    expect(await registrar.ensureRegistered('wallet-2', 'token-2'), isTrue);
    await device.signIn('uid-b');
    expect(await registrar.ensureRegistered('wallet-2', 'token-2'), isTrue);
    expect(registrar.calls, 4);
    await device.db.close();
  });

  test('isolate nền chỉ ghi cờ bền cho tín hiệu head; tin khác bị bỏ qua', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await remoteSignalBackgroundHandler(const RemoteMessage(data: {'t': 'other'}));
    expect(prefs.getBool('hw_remote_head_pending'), isNull);
    await remoteSignalBackgroundHandler(const RemoteMessage(data: {'t': 'head'}));
    expect(prefs.getBool('hw_remote_head_pending'), isTrue);
  });
}
