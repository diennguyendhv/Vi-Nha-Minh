import 'package:flutter_riverpod/flutter_riverpod.dart';

// 4 tab thật (Cài đặt chuyển vào avatar ở Trang chủ, xem `app_shell.dart`).
// Nút [+] ở giữa bottom-nav không phải 1 tab — nó mở thẳng
// `showAddTransactionSheet`, đúng nguyên tắc "1 nơi tạo giao dịch duy nhất".
enum AppTab { home, transactions, categories, summary }

final currentTabProvider = StateProvider<AppTab>((ref) => AppTab.home);

final biometricLockProvider = StateProvider<bool>((ref) => true);
