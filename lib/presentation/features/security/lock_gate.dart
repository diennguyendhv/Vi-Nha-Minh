import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../providers/app_lock_provider.dart';
import 'lock_screen.dart';

/// Ranh giới bảo vệ nội dung của TOÀN app (đặt trong `MaterialApp.builder`).
///
/// Khi đang khoá, `child` (Navigator + mọi màn tài chính) KHÔNG được dựng — không chỉ bị
/// che — nên không thể lộ số dư bằng nút Back, khôi phục route hay khung hình thừa.
/// Nút Back khi khoá ⇒ không có Navigator để pop ⇒ thoát app.
class LockGate extends ConsumerStatefulWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(appLockProvider.notifier).onLifecycle(state);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appLockProvider);
    if (s.contentHidden) {
      // Overlay riêng: `builder` của MaterialApp nằm TRÊN Navigator nên không có sẵn Overlay.
      return Overlay(
        initialEntries: [OverlayEntry(builder: (_) => const LockScreen())],
      );
    }
    if (s.privacyCover) {
      return const ColoredBox(
        key: Key('privacy_cover'),
        color: AppColors.background,
        child: SizedBox.expand(),
      );
    }
    return widget.child;
  }
}
