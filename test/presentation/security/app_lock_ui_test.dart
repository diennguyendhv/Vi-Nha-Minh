import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/security/app_lock.dart';
import 'package:vi_nha_minh/presentation/features/security/lock_gate.dart';
import 'package:vi_nha_minh/presentation/features/security/security_settings_section.dart';
import 'package:vi_nha_minh/presentation/providers/app_lock_provider.dart';

import '../../support/fake_app_lock.dart';

const _pin = '123456';
const _secret = 'SO_DU_TUYET_MAT_9.999.999';

/// Dựng app tối giản có CÙNG cấu trúc cổng khoá như `ViNhaMinhApp`:
/// `LockGate` trong `MaterialApp.builder`, nội dung bí mật + mục Cài đặt bảo mật ở trong.
Future<void> _pump(
  WidgetTester tester,
  FakeAppLockPlatform platform,
  FakeDeviceAuthenticator auth,
) async {
  final status = await platform.status();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appLockPlatformProvider.overrideWithValue(platform),
        deviceAuthenticatorProvider.overrideWithValue(auth),
        appLockInitialStatusProvider.overrideWithValue(status),
      ],
      child: MaterialApp(
        builder: (context, child) => LockGate(child: child!),
        home: const Scaffold(
          body: Column(
            children: [Text(_secret), SecuritySettingsSection()],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _type(WidgetTester tester, String pin) async {
  await tester.enterText(find.byKey(const Key('pin_field')), pin);
  await tester.pump();
  await tester.pump();
}

void main() {
  late FakeAppLockPlatform platform;
  late FakeDeviceAuthenticator auth;

  setUp(() {
    platform = FakeAppLockPlatform();
    auth = FakeDeviceAuthenticator();
  });

  Future<void> enableViaPlatform() => platform.setPin(_pin);

  testWidgets('khởi động lạnh có khoá: chỉ màn khoá, KHÔNG dựng nội dung tài chính', (
    tester,
  ) async {
    await enableViaPlatform();
    await _pump(tester, platform, auth);
    expect(find.byKey(const Key('lock_screen')), findsOneWidget);
    // Không chỉ bị che — hoàn toàn không tồn tại trong cây widget (không "flash").
    expect(find.text(_secret), findsNothing);
    expect(find.byType(SecuritySettingsSection), findsNothing);
    expect(find.text('Nhập mã PIN'), findsOneWidget);
  });

  testWidgets('PIN sai ⇒ vẫn khoá, ô được xoá; PIN đúng ⇒ vào nội dung', (
    tester,
  ) async {
    await enableViaPlatform();
    await _pump(tester, platform, auth);

    await _type(tester, '000000');
    expect(find.text('Mã PIN không đúng.'), findsOneWidget);
    expect(find.text(_secret), findsNothing);
    expect(
      tester.widget<TextField>(find.byKey(const Key('pin_field'))).controller!.text,
      isEmpty,
    );

    await _type(tester, _pin);
    expect(find.byKey(const Key('lock_screen')), findsNothing);
    expect(find.text(_secret), findsOneWidget);
  });

  testWidgets('bị chặn tạm: hiện đếm ngược, ô nhập bị khoá', (tester) async {
    await enableViaPlatform();
    await _pump(tester, platform, auth);
    for (var i = 0; i < 5; i++) {
      await _type(tester, '000000');
    }
    expect(find.byKey(const Key('lockout_message')), findsOneWidget);
    expect(find.textContaining('00:30'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const Key('pin_field'))).enabled,
      isFalse,
    );
    // Dọn timer đếm ngược trước khi kết thúc test.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sinh trắc bật: tự hỏi 1 lần; huỷ ⇒ ở lại màn PIN, PIN vẫn dùng được', (
    tester,
  ) async {
    await enableViaPlatform();
    await platform.setBiometricEnabled(true);
    auth.biometricResult = BiometricOutcome.failedOrCancelled;
    await _pump(tester, platform, auth);
    expect(auth.biometricCalls, 1, reason: 'chỉ tự hỏi một lần, không lặp');
    expect(find.byKey(const Key('lock_screen')), findsOneWidget);
    expect(find.byKey(const Key('biometric_button')), findsOneWidget);
    await _type(tester, _pin);
    expect(find.text(_secret), findsOneWidget);
  });

  testWidgets('sinh trắc thành công ⇒ mở khoá', (tester) async {
    await enableViaPlatform();
    await platform.setBiometricEnabled(true);
    await _pump(tester, platform, auth);
    expect(find.text(_secret), findsOneWidget);
  });

  testWidgets('"Quên mã PIN?" ⇒ xác minh chủ máy ⇒ đặt PIN mới', (tester) async {
    await enableViaPlatform();
    await _pump(tester, platform, auth);
    await tester.tap(find.byKey(const Key('forgot_pin_button')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('pin_setup_prompt')), findsOneWidget);
    await _type(tester, '654321');
    await _type(tester, '654321');
    expect(find.text(_secret), findsOneWidget);
    expect((await platform.verifyPin('654321')).isOk, isTrue);
  });

  testWidgets('"Quên mã PIN?" khi máy không có khóa màn hình ⇒ thông báo, không mở', (
    tester,
  ) async {
    await enableViaPlatform();
    auth.deviceOwnerResult = BiometricOutcome.unavailable;
    await _pump(tester, platform, auth);
    await tester.tap(find.byKey(const Key('forgot_pin_button')));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('không bị xóa'), findsOneWidget);
    expect(find.text(_secret), findsNothing);
  });

  group('Cài đặt bảo mật', () {
    testWidgets('bật: 2 lần PIN lệch ⇒ báo lỗi, KHÔNG bật', (tester) async {
      await _pump(tester, platform, auth);
      await tester.tap(find.byKey(const Key('app_lock_switch')));
      await tester.pumpAndSettle();
      await _type(tester, _pin);
      await _type(tester, '111111');
      expect(find.byKey(const Key('pin_setup_error')), findsOneWidget);
      expect((await platform.status()).enabled, isFalse);
    });

    testWidgets('bật: xác nhận khớp ⇒ đã bật + hiện các dòng bảo mật', (tester) async {
      await _pump(tester, platform, auth);
      expect(find.byKey(const Key('change_pin_row')), findsNothing);
      await tester.tap(find.byKey(const Key('app_lock_switch')));
      await tester.pumpAndSettle();
      await _type(tester, _pin);
      await _type(tester, _pin);
      await tester.pumpAndSettle();
      expect((await platform.status()).enabled, isTrue);
      expect(find.byKey(const Key('biometric_switch')), findsOneWidget);
      expect(find.byKey(const Key('change_pin_row')), findsOneWidget);
      expect(find.byKey(const Key('lock_now_row')), findsOneWidget);
    });

    testWidgets('tắt khoá cần PIN: sai ⇒ vẫn bật; đúng ⇒ tắt', (tester) async {
      await enableViaPlatform();
      await _pump(tester, platform, auth);
      await _type(tester, _pin); // mở khoá
      await tester.tap(find.byKey(const Key('app_lock_switch')));
      await tester.pumpAndSettle();
      await _type(tester, '000000');
      expect(find.byKey(const Key('pin_verify_error')), findsOneWidget);
      expect((await platform.status()).enabled, isTrue);
      await _type(tester, _pin);
      await tester.pumpAndSettle();
      expect((await platform.status()).enabled, isFalse);
    });

    testWidgets('"Khóa ngay" ⇒ màn khoá', (tester) async {
      await enableViaPlatform();
      await _pump(tester, platform, auth);
      await _type(tester, _pin);
      await tester.tap(find.byKey(const Key('lock_now_row')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('lock_screen')), findsOneWidget);
      expect(find.text(_secret), findsNothing);
    });

    testWidgets('đổi PIN: PIN hiện tại sai ⇒ không vào bước đặt PIN mới', (
      tester,
    ) async {
      await enableViaPlatform();
      await _pump(tester, platform, auth);
      await _type(tester, _pin);
      await tester.tap(find.byKey(const Key('change_pin_row')));
      await tester.pumpAndSettle();
      await _type(tester, '000000');
      expect(find.byKey(const Key('pin_setup_prompt')), findsNothing);
      expect(find.byKey(const Key('pin_verify_error')), findsOneWidget);
    });
  });
}
