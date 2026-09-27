import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/app_environment.dart';
import '../../core/config/cloud_policy.dart';
import '../../core/config/firebase_env_config.dart';
import '../../domain/auth/auth_repository.dart';
import 'firebase_auth_repository.dart';

import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/auth/cloud_session.dart';
import 'session_storage.dart';
import 'session_transport.dart';

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
      debugPrint(
        '[auth] ${environment.flavor}: chưa cấu hình Firebase, Auth tắt',
      );
    }
    return const UnavailableAuthRepository();
  }
  // Bản DEV không bao giờ khởi tạo Firebase trỏ vào cloud production (chỉ emulator);
  // PROD chỉ trỏ vào đúng dự án production.
  if (!CloudPolicy.firebaseTargetAllowed(environment, config: config)) {
    if (kDebugMode) {
      debugPrint(
        '[auth] ${environment.flavor}: đích Firebase không được phép, Auth tắt',
      );
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
    final repository = FirebaseAuthRepository(
      googleServerClientId: config.googleServerClientId,
    );
    if (config.isEmulator) {
      await FirebaseAuth.instance.useAuthEmulator(config.emulatorHost, 9099);
    }
    if (CloudPolicy.enabledIn(environment, config: config)) {
      final auth = FirebaseAuth.instance;
      repository.cloudSession = CloudSession(
        KeystoreSessionStorage(),
        SessionTransportClient(
          auth,
          config.projectId,
          environment: environment,
          emulatorHost: config.isEmulator ? config.emulatorHost : null,
        ).call,
        () => auth.currentUser?.uid,
      );
    }
    return repository;
  } on Object catch (e) {
    if (kDebugMode) {
      debugPrint('[auth] khởi tạo Firebase lỗi: ${e.runtimeType}');
    }
    return const UnavailableAuthRepository();
  }
}
