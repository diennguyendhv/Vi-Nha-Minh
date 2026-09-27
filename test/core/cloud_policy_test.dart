import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/config/app_environment.dart';
import 'package:vi_nha_minh/core/config/cloud_policy.dart';
import 'package:vi_nha_minh/core/config/firebase_env_config.dart';
import 'package:vi_nha_minh/data/auth/session_transport.dart';

const _prod = CloudPolicy.productionProjectId;

FirebaseEnvConfig _cfg(
  String env,
  String project, {
  String emulatorHost = '',
}) => FirebaseEnvConfig(
  envName: env,
  apiKey: 'k',
  appId: 'a',
  messagingSenderId: 's',
  projectId: project,
  googleServerClientId: 'g',
  emulatorHost: emulatorHost,
);

/// Quyết định 2026-09-27: MỘT dự án Firebase (`vi-nha-minh-55c60`) = PRODUCTION.
/// Bản DEV chỉ dùng Emulator Suite; không có override.
void main() {
  group('đích Firebase được phép khởi tạo', () {
    test(
      'DEV: CHỈ emulator (project demo-* + host); cloud production bị từ chối',
      () {
        expect(
          CloudPolicy.firebaseTargetAllowed(
            AppEnvironment.dev,
            config: _cfg('dev', _prod),
          ),
          isFalse,
        );
        // Kể cả khi có host emulator mà project là production.
        expect(
          CloudPolicy.firebaseTargetAllowed(
            AppEnvironment.dev,
            config: _cfg('dev', _prod, emulatorHost: '10.0.2.2'),
          ),
          isFalse,
        );
        expect(
          CloudPolicy.firebaseTargetAllowed(
            AppEnvironment.dev,
            config: _cfg('dev', 'demo-homewallet-p7', emulatorHost: '10.0.2.2'),
          ),
          isTrue,
        );
        expect(
          CloudPolicy.firebaseTargetAllowed(
            AppEnvironment.dev,
            config: _cfg('dev', 'demo-homewallet-p7'),
          ),
          isFalse,
        );
      },
    );

    test('PROD: CHỈ dự án production, không emulator; PILOT: không', () {
      expect(
        CloudPolicy.firebaseTargetAllowed(
          AppEnvironment.prod,
          config: _cfg('prod', _prod),
        ),
        isTrue,
      );
      expect(
        CloudPolicy.firebaseTargetAllowed(
          AppEnvironment.prod,
          config: _cfg('prod', 'other'),
        ),
        isFalse,
      );
      expect(
        CloudPolicy.firebaseTargetAllowed(
          AppEnvironment.prod,
          config: _cfg('prod', _prod, emulatorHost: '10.0.2.2'),
        ),
        isFalse,
      );
      expect(
        CloudPolicy.firebaseTargetAllowed(
          AppEnvironment.pilot,
          config: _cfg('pilot', _prod),
        ),
        isFalse,
      );
    });
  });

  test('logic cloud PROD cần ĐỦ: CLOUD_ENABLED + cấu hình PROD + đúng dự án production', () {
    final prod = _cfg('prod', _prod);
    expect(
      CloudPolicy.enabledIn(AppEnvironment.prod, config: prod, optIn: true),
      isTrue,
    );
    expect(
      CloudPolicy.enabledIn(AppEnvironment.prod, config: prod, optIn: false),
      isFalse,
    );
    expect(
      CloudPolicy.enabledIn(
        AppEnvironment.prod,
        config: _cfg('prod', 'other'),
        optIn: true,
      ),
      isFalse,
    );
    expect(
      CloudPolicy.enabledIn(
        AppEnvironment.prod,
        config: _cfg('dev', _prod),
        optIn: true,
      ),
      isFalse,
    );
    expect(
      CloudPolicy.enabledIn(
        AppEnvironment.prod,
        config: _cfg('prod', 'REPLACE_ME'),
        optIn: true,
      ),
      isFalse,
    );
    expect(
      CloudPolicy.enabledIn(AppEnvironment.pilot, config: prod, optIn: true),
      isFalse,
    );
    // flutter test không có CLOUD_ENABLED ⇒ PROD tắt theo mặc định.
    expect(CloudPolicy.enabledIn(AppEnvironment.prod), isFalse);
  });

  test(
    'transport chặn lần 2: DEV chỉ gọi emulator; PROD không gọi emulator',
    () {
      bool allowed(AppEnvironment e, String p, String? h) =>
          SessionTransportClient.targetAllowed(e, p, h);
      expect(allowed(AppEnvironment.dev, _prod, null), isFalse);
      expect(allowed(AppEnvironment.dev, _prod, '10.0.2.2'), isFalse);
      expect(
        allowed(AppEnvironment.dev, 'demo-homewallet-p7', '10.0.2.2'),
        isTrue,
      );
      expect(allowed(AppEnvironment.prod, _prod, null), isTrue);
      expect(
        allowed(AppEnvironment.prod, 'demo-homewallet-p7', '10.0.2.2'),
        isFalse,
      );
    },
  );
}
