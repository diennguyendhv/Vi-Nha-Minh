import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/security/method_channel_app_lock_platform.dart';
import 'presentation/features/security/lock_gate.dart';
import 'presentation/providers/app_lock_provider.dart';
import 'presentation/providers/explorer_sort_provider.dart';
import 'presentation/providers/primary_fund_provider.dart';
import 'presentation/widgets/tap_guard.dart';

import 'package:google_fonts/google_fonts.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

// Firebase.initializeApp() sẽ được bật ở đây khi có project Firebase thật
// (chạy `flutterfire configure` để sinh firebase_options.dart) — xem spec.md
// Giai đoạn B. Hiện tại (Giai đoạn A) app chạy hoàn toàn local-first qua
// LocalTransactionRepository/LocalFundRepository (SQLite), không cần mạng.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // App local-first không được phụ thuộc mạng để hiển thị đúng — tắt việc
  // google_fonts tự tải font qua mạng lúc chạy (mặc định của package), nếu
  // không sẽ ném Unhandled Exception khi máy không có internet (đã bắt được
  // lỗi này khi chạy thật trên điện thoại lúc không có mạng). Font sẽ dùng
  // font hệ thống thay Manrope cho tới khi bundle file font tĩnh vào app.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Quỹ chính của Trang chủ lưu bền vững (thiết lập hiển thị, không phải sổ cái).
  final prefs = await SharedPreferences.getInstance();

  // Khoá ứng dụng: đọc trạng thái từ native TRƯỚC `runApp` để nếu đã bật thì khung hình
  // đầu tiên là màn khoá (không có khung hình UI tài chính nào lộ ra).
  // Lỗi đọc ⇒ coi như bật + khoá (fail-closed) chỉ khi native báo bật; nếu không đọc được
  // hoàn toàn thì rơi về "tắt" sẽ mở app — nên ném lỗi thay vì đoán.
  final lockPlatform = MethodChannelAppLockPlatform();
  final lockStatus = await lockPlatform.status();

  runApp(
    ProviderScope(
      overrides: [
        appLockPlatformProvider.overrideWithValue(lockPlatform),
        deviceAuthenticatorProvider.overrideWithValue(
          LocalAuthDeviceAuthenticator(),
        ),
        appLockInitialStatusProvider.overrideWithValue(lockStatus),
        primaryFundIdProvider.overrideWith(
          (ref) => createPersistentPrimaryFundController(prefs),
        ),
        explorerSortProvider.overrideWith(
          (ref) => createPersistentExplorerSortController(prefs),
        ),
      ],
      child: const ViNhaMinhApp(),
    ),
  );
}

class ViNhaMinhApp extends StatelessWidget {
  const ViNhaMinhApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'HomeWallet',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: appRouter,
      builder: (context, child) =>
          LockGate(child: TapGuardScope(child: child ?? const SizedBox.shrink())),
    );
  }
}
