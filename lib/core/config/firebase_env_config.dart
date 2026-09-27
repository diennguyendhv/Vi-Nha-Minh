import 'app_environment.dart';

/// Cấu hình Firebase CLIENT (công khai, không phải bí mật) cho một môi trường.
/// Nạp từ `--dart-define-from-file=env/<env>.json`. KHÔNG bao giờ chứa service
/// account/khoá Admin. Thiếu/sai/khác môi trường ⇒ [isUsable] = false ⇒ Auth tắt,
/// app vẫn chạy local bình thường.
class FirebaseEnvConfig {
  const FirebaseEnvConfig({
    required this.envName,
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.projectId,
    required this.googleServerClientId,
    this.emulatorHost = '',
  });

  final String envName;
  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;

  /// OAuth *Web* client ID của dự án Firebase (dùng để lấy idToken cho FirebaseAuth).
  final String googleServerClientId;

  /// Host của Firebase Emulator Suite (vd `10.0.2.2` từ AVD). Rỗng = cloud thật.
  final String emulatorHost;

  /// Trỏ tới Emulator Suite: có host VÀ project `demo-*` (Firebase quy ước project
  /// `demo-` không bao giờ chạm tài nguyên thật).
  bool get isEmulator =>
      emulatorHost.isNotEmpty && projectId.startsWith('demo-');

  /// Đọc từ `--dart-define`. Phải là const-evaluated ở đây (String.fromEnvironment).
  static const FirebaseEnvConfig fromDartDefine = FirebaseEnvConfig(
    envName: String.fromEnvironment('APP_ENV'),
    apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
    appId: String.fromEnvironment('FIREBASE_APP_ID'),
    messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
    googleServerClientId: String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID'),
    emulatorHost: String.fromEnvironment('FIREBASE_EMULATOR_HOST'),
  );

  static bool _placeholder(String v) =>
      v.isEmpty || v.startsWith('REPLACE_') || v.contains('<');

  /// Đủ trường, không phải giá trị mẫu, và `APP_ENV` của file KHỚP môi trường
  /// build (DEV không thể vô tình khởi tạo cấu hình PROD, và ngược lại).
  bool isUsableFor(AppEnvironment env) =>
      envName == env.flavor &&
      ![
        apiKey,
        appId,
        messagingSenderId,
        projectId,
        googleServerClientId,
      ].any(_placeholder);

  bool get isUsable => isUsableFor(AppEnvironment.current);
}
