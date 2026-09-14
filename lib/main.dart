import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

// Firebase.initializeApp() sẽ được bật ở đây khi có project Firebase thật
// (chạy `flutterfire configure` để sinh firebase_options.dart) — xem spec.md
// Giai đoạn B. Hiện tại (Giai đoạn A) app chạy hoàn toàn local-first qua
// LocalTransactionRepository/LocalFundRepository (SQLite), không cần mạng.

void main() {
  // App local-first không được phụ thuộc mạng để hiển thị đúng — tắt việc
  // google_fonts tự tải font qua mạng lúc chạy (mặc định của package), nếu
  // không sẽ ném Unhandled Exception khi máy không có internet (đã bắt được
  // lỗi này khi chạy thật trên điện thoại lúc không có mạng). Font sẽ dùng
  // font hệ thống thay Manrope cho tới khi bundle file font tĩnh vào app.
  GoogleFonts.config.allowRuntimeFetching = false;

  runApp(const ProviderScope(child: ViNhaMinhApp()));
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
    );
  }
}
