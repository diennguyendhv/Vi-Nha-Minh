import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/app_environment.dart';
import '../../core/config/firebase_env_config.dart';
import '../../domain/auth/auth_repository.dart';
import 'firebase_auth_repository.dart';

/// Khởi tạo Firebase (chỉ Auth) cho môi trường hiện tại. KHÔNG BAO GIỜ ném:
/// mọi thất bại ⇒ [UnavailableAuthRepository], app local vẫn khởi động bình thường
/// và không phụ thuộc mạng. `Firebase.initializeApp` với options tường minh không
/// gọi mạng.
Future<AuthRepository> bootstrapAuth({
  AppEnvironment? env,
  FirebaseEnvConfig config = FirebaseEnvConfig.fromDartDefine,
}) async {
  final environment = env ?? AppEnvironment.current;
  if (!config.isUsableFor(environment)) {
    if (kDebugMode) {
      debugPrint('[auth] ${environment.flavor}: chưa cấu hình Firebase, Auth tắt');
    }
    return const UnavailableAuthRepository();
  }
  try {
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: config.apiKey,
        appId: config.appId,
        messagingSenderId: config.messagingSenderId,
        projectId: config.projectId,
      ),
    );
    return FirebaseAuthRepository(
      googleServerClientId: config.googleServerClientId,
    );
  } on Object catch (e) {
    if (kDebugMode) debugPrint('[auth] khởi tạo Firebase lỗi: ${e.runtimeType}');
    return const UnavailableAuthRepository();
  }
}
