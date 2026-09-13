import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppTab { home, summary, settings }

final currentTabProvider = StateProvider<AppTab>((ref) => AppTab.home);

final biometricLockProvider = StateProvider<bool>((ref) => true);
