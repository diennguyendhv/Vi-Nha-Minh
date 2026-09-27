import 'app_environment.dart';
import 'firebase_env_config.dart';

/// Cloud theo môi trường build — quyết định chủ dự án 2026-09-27: MỘT dự án Firebase
/// duy nhất, `vi-nha-minh-55c60`, là cloud PRODUCTION. DEV làm việc bằng Firebase
/// Emulator Suite (project `demo-*`), không bao giờ ghi vào cloud production.
///
/// Hai câu hỏi tách bạch:
/// - [firebaseTargetAllowed]: bản build này có được KHỞI TẠO Firebase trỏ tới đích
///   cấu hình không (cửa duy nhất tới cloud thật — không có phiên cloud ⇒ không có
///   thao tác cloud nào). DEV: CHỈ emulator. PROD: CHỈ dự án production. PILOT: không.
///   KHÔNG có cờ override cho DEV (quyết định: không override trong phát triển thường).
/// - [enabledIn]: logic cloud (claim/sao lưu/đồng bộ/Gia đình) có bật cho môi trường
///   này không. PROD cần thêm `"CLOUD_ENABLED": "true"` trong `env/prod.json`.
/// Máy chủ kiểm lại lần nữa: mọi lời gọi mang `clientEnv` phải khớp môi trường của
/// dự án (`functions/env.js`) ⇒ bản DEV (kể cả bản cũ) không thể ghi vào production.
abstract final class CloudPolicy {
  static const productionProjectId = 'vi-nha-minh-55c60';
  static const _optIn = bool.fromEnvironment('CLOUD_ENABLED');

  static bool firebaseTargetAllowed(
    AppEnvironment env, {
    FirebaseEnvConfig config = FirebaseEnvConfig.fromDartDefine,
  }) => switch (env) {
    AppEnvironment.dev => config.isEmulator,
    AppEnvironment.pilot => false,
    AppEnvironment.prod =>
      !config.isEmulator &&
          config.emulatorHost.isEmpty &&
          config.projectId == productionProjectId,
  };

  static bool enabledIn(
    AppEnvironment env, {
    FirebaseEnvConfig config = FirebaseEnvConfig.fromDartDefine,
    bool optIn = _optIn,
  }) => switch (env) {
    // Chỉ tới được cloud qua phiên do bootstrap dựng, mà bootstrap DEV chỉ nhận emulator.
    AppEnvironment.dev => true,
    AppEnvironment.pilot => false,
    AppEnvironment.prod =>
      optIn &&
          config.isUsableFor(env) &&
          firebaseTargetAllowed(env, config: config),
  };
}
