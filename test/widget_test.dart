import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:vi_nha_minh/main.dart';

void main() {
  // Tránh google_fonts gọi mạng để tải font trong môi trường test, việc này
  // khiến pumpAndSettle chờ vô thời hạn không bao giờ ổn định khung hình.
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('Home screen shows the app title and bottom nav', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ViNhaMinhApp()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Ví Nhà Mình'), findsOneWidget);
    expect(find.text('Trang chủ'), findsOneWidget);
    expect(find.text('Tổng hợp'), findsOneWidget);
    expect(find.text('Cài đặt'), findsOneWidget);
  });
}
