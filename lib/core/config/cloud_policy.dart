import 'app_environment.dart';
import 'firebase_env_config.dart';

/// Tính năng CLOUD (phiên P7.1, claim ví, sao lưu/đồng bộ mã hoá, Gia đình) theo môi
/// trường build — MỘT nơi quyết định (quyết định chủ dự án 2026-09-27):
/// - DEV: bật (dự án Firebase DEV, dữ liệu thử).
/// - PILOT: tắt.
/// - PROD: chỉ khi `env/prod.json` BẬT TƯỜNG MINH `"CLOUD_ENABLED": "true"`, cấu hình
///   Firebase PROD dùng được, và dự án KHÔNG phải dự án DEV (dữ liệu tài chính thật
///   không bao giờ đi vào Firebase DEV).
/// Backend có allowlist riêng theo project id (`functions/env.js`).
abstract final class CloudPolicy {
  static const devProjectId = 'vi-nha-minh-55c60';
  static const _optIn = bool.fromEnvironment('CLOUD_ENABLED');

  static bool enabledIn(
    AppEnvironment env, {
    FirebaseEnvConfig config = FirebaseEnvConfig.fromDartDefine,
    bool optIn = _optIn,
  }) => switch (env) {
    AppEnvironment.dev => true,
    AppEnvironment.pilot => false,
    AppEnvironment.prod =>
      optIn && config.isUsableFor(env) && config.projectId != devProjectId,
  };
}
