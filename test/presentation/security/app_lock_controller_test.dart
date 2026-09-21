import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/security/app_lock.dart';
import 'package:vi_nha_minh/presentation/providers/app_lock_provider.dart';

import '../../support/fake_app_lock.dart';

const _pin = '123456';

Future<AppLockController> _coldStart(
  FakeAppLockPlatform platform,
  FakeDeviceAuthenticator auth,
) async {
  // Mô phỏng process chết/khởi động lại: trạng thái mở khoá KHÔNG được lưu,
  // chỉ đọc lại cấu hình từ "native".
  final c = AppLockController(
    platform: platform,
    authenticator: auth,
    initial: AppLockState.fromStatus(await platform.status()),
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  late FakeAppLockPlatform platform;
  late FakeDeviceAuthenticator auth;

  setUp(() {
    platform = FakeAppLockPlatform();
    auth = FakeDeviceAuthenticator();
  });

  Future<AppLockController> enabledController() async {
    final first = await _coldStart(platform, auth);
    await first.enable(_pin);
    return _coldStart(platform, auth); // khởi động lạnh sau khi bật
  }

  test('isValidPin: đúng 6 chữ số', () {
    expect(isValidPin('123456'), isTrue);
    expect(isValidPin('12345'), isFalse);
    expect(isValidPin('1234567'), isFalse);
    expect(isValidPin('12a456'), isFalse);
  });

  group('cài đặt PIN', () {
    test('PIN không hợp lệ bị từ chối, không ghi gì', () async {
      final c = await _coldStart(platform, auth);
      for (final bad in ['12345', '1234567', 'abcdef', '12 456', '']) {
        expect(() => c.enable(bad), throwsArgumentError);
      }
      expect(platform.setPinCalls, 0);
      expect(c.state.phase, AppLockPhase.disabled);
    });

    test('bật xong: phiên hiện tại mở khoá; khởi động lạnh ⇒ khoá', () async {
      final c = await _coldStart(platform, auth);
      await c.enable(_pin);
      expect(c.state.phase, AppLockPhase.unlocked);

      final cold = await _coldStart(platform, auth);
      expect(cold.state.phase, AppLockPhase.locked);
      expect(cold.state.contentHidden, isTrue);
    });

    test('PIN đúng mở khoá, PIN sai thì không', () async {
      final c = await enabledController();
      final bad = await c.submitPin('000000');
      expect(bad.outcome, PinVerifyOutcome.wrong);
      expect(c.state.phase, AppLockPhase.locked);
      final good = await c.submitPin(_pin);
      expect(good.isOk, isTrue);
      expect(c.state.phase, AppLockPhase.unlocked);
    });

    test('bấm gửi thừa khi đang xác minh chỉ tính 1 lần', () async {
      final c = await enabledController();
      final a = c.submitPin('000000');
      final b = c.submitPin('000000');
      await Future.wait([a, b]);
      expect(platform.failed, 1);
    });
  });

  group('đổi PIN / tắt khoá', () {
    test('PIN hiện tại sai ⇒ không xác minh được', () async {
      final c = await enabledController();
      expect((await c.verifyCurrentPin('999999')).isOk, isFalse);
    });

    test('đổi thành công: PIN cũ hết hiệu lực, PIN mới dùng được', () async {
      final c = await enabledController();
      expect((await c.verifyCurrentPin(_pin)).isOk, isTrue);
      await c.changePin('654321');
      expect((await c.verifyCurrentPin(_pin)).isOk, isFalse);
      expect((await c.verifyCurrentPin('654321')).isOk, isTrue);
    });

    test('ghi PIN mới lỗi ⇒ PIN cũ vẫn dùng được (không mất khoá)', () async {
      final c = await enabledController();
      platform.failNextSetPin = true;
      await expectLater(c.changePin('654321'), throwsStateError);
      expect((await c.verifyCurrentPin(_pin)).isOk, isTrue);
    });

    test('tắt khoá (sau xác minh) ⇒ khởi động lạnh không còn khoá', () async {
      final c = await enabledController();
      await c.submitPin(_pin);
      await c.disable();
      expect(c.state.phase, AppLockPhase.disabled);
      final cold = await _coldStart(platform, auth);
      expect(cold.state.phase, AppLockPhase.disabled);
    });
  });

  group('sinh trắc học', () {
    Future<AppLockController> withBiometric() async {
      final c = await enabledController();
      await c.submitPin(_pin);
      expect(await c.setBiometric(true), BiometricOutcome.success);
      return _coldStart(platform, auth);
    }

    test('chưa bật khoá thì không bật được sinh trắc', () async {
      final c = await _coldStart(platform, auth);
      expect(await c.setBiometric(true), BiometricOutcome.unavailable);
    });

    test('bật cần xác thực thành công; thất bại/không có ⇒ không bật', () async {
      final c = await enabledController();
      await c.submitPin(_pin);
      auth.biometricAvailable = false;
      expect(await c.setBiometric(true), BiometricOutcome.unavailable);
      expect(c.state.biometricEnabled, isFalse);
      auth.biometricAvailable = true;
      auth.biometricResult = BiometricOutcome.failedOrCancelled;
      await c.setBiometric(true);
      expect(c.state.biometricEnabled, isFalse);
      auth.biometricResult = BiometricOutcome.success;
      await c.setBiometric(true);
      expect(c.state.biometricEnabled, isTrue);
    });

    test('thành công ⇒ mở khoá phiên', () async {
      final c = await withBiometric();
      expect(c.state.biometricEnabled, isTrue);
      expect(await c.unlockWithBiometric(), BiometricOutcome.success);
      expect(c.state.phase, AppLockPhase.unlocked);
    });

    test(
      'thất bại / huỷ / khoá tạm / không khả dụng ⇒ vẫn khoá, PIN dùng được',
      () async {
        for (final o in [
          BiometricOutcome.failedOrCancelled,
          BiometricOutcome.lockedOut,
          BiometricOutcome.unavailable,
        ]) {
          auth.biometricResult = BiometricOutcome.success;
          final c = await withBiometric();
          auth.biometricResult = o;
          expect(await c.unlockWithBiometric(), o);
          expect(c.state.phase, AppLockPhase.locked);
          expect((await c.submitPin(_pin)).isOk, isTrue);
          expect(c.state.phase, AppLockPhase.unlocked);
        }
      },
    );

    test('tắt sinh trắc lưu bền qua khởi động lại', () async {
      final c = await withBiometric();
      await c.submitPin(_pin);
      await c.setBiometric(false);
      final cold = await _coldStart(platform, auth);
      expect(cold.state.biometricEnabled, isFalse);
    });
  });

  group('vòng đời (nền / khoá ngay)', () {
    Future<AppLockController> unlocked() async {
      final c = await enabledController();
      await c.submitPin(_pin);
      return c;
    }

    test('nền 10 giây ⇒ vẫn mở khoá', () async {
      final c = await unlocked();
      await c.onLifecycle(AppLifecycleState.inactive);
      await c.onLifecycle(AppLifecycleState.paused);
      platform.nowMs += 10000;
      await c.onLifecycle(AppLifecycleState.resumed);
      expect(c.state.phase, AppLockPhase.unlocked);
      expect(c.state.privacyCover, isFalse);
    });

    test('nền từ 30 giây trở lên ⇒ khoá', () async {
      for (final ms in [30000, 31000, 600000]) {
        final c = await unlocked();
        await c.onLifecycle(AppLifecycleState.paused);
        platform.nowMs += ms;
        await c.onLifecycle(AppLifecycleState.resumed);
        expect(c.state.phase, AppLockPhase.locked, reason: '$ms ms');
      }
    });

    test('nền 29,9 giây chưa khoá', () async {
      final c = await unlocked();
      await c.onLifecycle(AppLifecycleState.paused);
      platform.nowMs += 29900;
      await c.onLifecycle(AppLifecycleState.resumed);
      expect(c.state.phase, AppLockPhase.unlocked);
    });

    test('đồng hồ đi lùi (âm) ⇒ khoá cho an toàn', () async {
      final c = await unlocked();
      await c.onLifecycle(AppLifecycleState.paused);
      platform.nowMs -= 5000;
      await c.onLifecycle(AppLifecycleState.resumed);
      expect(c.state.phase, AppLockPhase.locked);
    });

    test('che nội dung ngay khi rời foreground, gỡ khi quay lại', () async {
      final c = await unlocked();
      await c.onLifecycle(AppLifecycleState.inactive);
      expect(c.state.privacyCover, isTrue);
      await c.onLifecycle(AppLifecycleState.resumed);
      expect(c.state.privacyCover, isFalse);
    });

    test('"Khóa ngay" khoá tức thì', () async {
      final c = await unlocked();
      c.lockNow();
      expect(c.state.phase, AppLockPhase.locked);
    });

    test('không bật khoá thì vòng đời không làm gì', () async {
      final c = await _coldStart(platform, auth);
      await c.onLifecycle(AppLifecycleState.paused);
      platform.nowMs += 999999;
      await c.onLifecycle(AppLifecycleState.resumed);
      expect(c.state.phase, AppLockPhase.disabled);
      expect(c.state.privacyCover, isFalse);
    });
  });

  group('chống dò PIN', () {
    test('5 lần sai ⇒ chặn tạm; PIN đúng cũng bị từ chối lúc chặn', () async {
      final c = await enabledController();
      for (var i = 0; i < 5; i++) {
        await c.submitPin('000000');
      }
      expect(c.state.phase, AppLockPhase.tempLockout);
      expect(c.state.lockoutRemaining, const Duration(seconds: 30));
      final r = await c.verifyCurrentPin(_pin);
      expect(r.outcome, PinVerifyOutcome.lockedOut);
    });

    test('force-stop không reset: khởi động lạnh vẫn đang bị chặn', () async {
      final c = await enabledController();
      for (var i = 0; i < 5; i++) {
        await c.submitPin('000000');
      }
      final cold = await _coldStart(platform, auth);
      expect(cold.state.phase, AppLockPhase.tempLockout);
      expect(cold.state.lockoutRemaining, greaterThan(Duration.zero));
      expect(
        (await platform.verifyPin(_pin)).outcome,
        PinVerifyOutcome.lockedOut,
      );
    });

    test('hết chặn ⇒ PIN đúng mở được; sai tiếp thì chặn lâu hơn', () async {
      final c = await enabledController();
      for (var i = 0; i < 5; i++) {
        await c.submitPin('000000');
      }
      platform.nowMs += 31000;
      final cold = await _coldStart(platform, auth);
      expect(cold.state.phase, AppLockPhase.locked);
      await cold.submitPin('000000'); // lần sai thứ 6
      expect(cold.state.lockoutRemaining, const Duration(seconds: 60));
      platform.nowMs += 61000;
      final again = await _coldStart(platform, auth);
      expect((await again.submitPin(_pin)).isOk, isTrue);
      expect(platform.failed, 0, reason: 'thành công xoá bộ đếm');
    });
  });

  group('quên PIN — không có cửa hậu', () {
    test('chưa xác minh chủ máy thì không đặt lại được', () async {
      final c = await enabledController();
      await expectLater(c.completeRecovery('654321'), throwsStateError);
      expect((await platform.verifyPin(_pin)).isOk, isTrue);
    });

    test('xác minh chủ máy ⇒ đặt PIN mới, gỡ chặn', () async {
      final c = await enabledController();
      for (var i = 0; i < 5; i++) {
        await c.submitPin('000000');
      }
      expect(await c.verifyDeviceOwnerForRecovery(), BiometricOutcome.success);
      await c.completeRecovery('654321');
      expect(c.state.phase, AppLockPhase.unlocked);
      expect((await platform.verifyPin('654321')).isOk, isTrue);
      expect((await platform.verifyPin(_pin)).isOk, isFalse);
    });

    test('máy không có khóa màn hình ⇒ không khôi phục, không wipe', () async {
      final c = await enabledController();
      auth.deviceOwnerResult = BiometricOutcome.unavailable;
      expect(
        await c.verifyDeviceOwnerForRecovery(),
        BiometricOutcome.unavailable,
      );
      await expectLater(c.completeRecovery('654321'), throwsStateError);
      expect(c.state.phase, AppLockPhase.locked);
      expect((await platform.verifyPin(_pin)).isOk, isTrue);
      expect(platform.disabled, isFalse);
    });

    test('khoá Keystore mất ⇒ báo hỏng, chỉ còn đường xác minh chủ máy', () async {
      final c = await enabledController();
      platform.breakCredential = true;
      final r = await c.submitPin(_pin);
      expect(r.outcome, PinVerifyOutcome.broken);
      expect(c.state.credentialBroken, isTrue);
      expect(await c.verifyDeviceOwnerForRecovery(), BiometricOutcome.success);
      await c.completeRecovery('654321');
      expect(c.state.credentialBroken, isFalse);
    });
  });
}
