import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/presentation/providers/database_provider.dart';

import 'package:vi_nha_minh/main.dart';

void main() {
  // Tránh google_fonts gọi mạng để tải font trong môi trường test, việc này
  // khiến pumpAndSettle chờ vô thời hạn không bao giờ ổn định khung hình.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Widget test không nên phụ thuộc file SQLite thật (path_provider không có
  // plugin thật trong môi trường flutter test) — override sang 1 AppDatabase
  // tạm trong bộ nhớ; seed mặc định (`seed_defaults.dart`) vẫn tự chạy vì nó
  // gắn ở `MigrationStrategy.beforeOpen`, không phụ thuộc executor thật.
  ProviderContainer buildOverrides() => ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(
        AppDatabase.forTesting(NativeDatabase.memory()),
      ),
    ],
  );

  testWidgets('Home screen shows the app title and bottom nav', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: buildOverrides(),
        child: const ViNhaMinhApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Ví Nhà Mình'), findsOneWidget);
    expect(find.text('Trang chủ'), findsOneWidget);
    expect(find.text('Giao dịch'), findsOneWidget);
    expect(find.text('Danh mục'), findsOneWidget);
    expect(find.text('Tổng hợp'), findsOneWidget);
  });
}
