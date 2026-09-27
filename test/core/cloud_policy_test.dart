import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/config/app_environment.dart';
import 'package:vi_nha_minh/core/config/cloud_policy.dart';
import 'package:vi_nha_minh/core/config/firebase_env_config.dart';

FirebaseEnvConfig _cfg(String env, String project) => FirebaseEnvConfig(
  envName: env,
  apiKey: 'k',
  appId: 'a',
  messagingSenderId: 's',
  projectId: project,
  googleServerClientId: 'g',
);

/// Quyết định 2026-09-27: mở cổng cloud cho PROD CHỈ bằng cấu hình tường minh,
/// không bao giờ cho dữ liệu thật vào dự án Firebase DEV.
void main() {
  test('DEV bật; PILOT tắt', () {
    expect(CloudPolicy.enabledIn(AppEnvironment.dev), isTrue);
    expect(
      CloudPolicy.enabledIn(AppEnvironment.pilot, config: _cfg('pilot', 'p'), optIn: true),
      isFalse,
    );
  });

  test('PROD cần ĐỦ: CLOUD_ENABLED + cấu hình PROD dùng được + không phải dự án DEV', () {
    final prod = _cfg('prod', 'vi-nha-minh-prod');
    expect(CloudPolicy.enabledIn(AppEnvironment.prod, config: prod, optIn: true), isTrue);
    expect(CloudPolicy.enabledIn(AppEnvironment.prod, config: prod, optIn: false), isFalse);
    expect(
      CloudPolicy.enabledIn(AppEnvironment.prod,
          config: _cfg('prod', CloudPolicy.devProjectId), optIn: true),
      isFalse,
    );
    expect(
      CloudPolicy.enabledIn(AppEnvironment.prod, config: _cfg('dev', 'x'), optIn: true),
      isFalse,
    );
    expect(
      CloudPolicy.enabledIn(AppEnvironment.prod,
          config: _cfg('prod', 'REPLACE_ME'), optIn: true),
      isFalse,
    );
    // Bản build này (flutter test) không có CLOUD_ENABLED ⇒ PROD tắt theo mặc định.
    expect(CloudPolicy.enabledIn(AppEnvironment.prod), isFalse);
  });
}
