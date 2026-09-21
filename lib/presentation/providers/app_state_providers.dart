import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database_provider.dart';

// 4 tab thật (Cài đặt chuyển vào avatar ở Trang chủ, xem `app_shell.dart`).
// Nút [+] ở giữa bottom-nav không phải 1 tab — nó mở thẳng
// `showAddTransactionSheet`, đúng nguyên tắc "1 nơi tạo giao dịch duy nhất".
enum AppTab { home, transactions, categories, summary }

final currentTabProvider = StateProvider<AppTab>((ref) {
  ref.watch(walletSessionKeyProvider); // đổi ví ⇒ về Trang chủ
  return AppTab.home;
});
