import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

// Firebase.initializeApp() sẽ được bật ở đây khi có project Firebase thật
// (chạy `flutterfire configure` để sinh firebase_options.dart) — xem spec.md
// Phase 0. Hiện tại app chạy với MockTransactionRepository để dựng UI trước.

void main() {
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
