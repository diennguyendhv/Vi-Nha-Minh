import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/presentation/providers/database_provider.dart';

void main() {
  // File này cố ý tạo nhiều AppDatabase (mỗi ProviderContainer 1 cái) trên
  // các file thật khác nhau (mỗi lần test chạy trên máy thật sẽ là file
  // riêng theo path_provider) — không phải race condition thật, chỉ tắt
  // cảnh báo debug-only của Drift cho gọn log test (giống pattern đã dùng ở
  // test/data/local/app_database_test.dart).
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('appDatabaseProvider lifecycle (Phase 5 mục 19/30)', () {
    test(
      '31/32/33 — resolve production DB provider trong container cô lập, dispose không lỗi/leak',
      () async {
        // Không chạy bất kỳ query nào — appDatabaseProvider dùng LazyDatabase
        // (xem lib/data/local/app_database.dart), nên đọc provider KHÔNG mở
        // kết nối SQLite/path_provider thật. Test behavior quan sát được
        // (resolve + dispose không throw), không hack state riêng tư của
        // AppDatabase/Drift.
        final container = ProviderContainer();

        expect(() => container.read(appDatabaseProvider), returnsNormally);

        // dispose() kích hoạt ref.onDispose(db.close) đã khai báo trong
        // appDatabaseProvider — verify không ném exception dù kết nối chưa
        // từng thật sự mở.
        expect(container.dispose, returnsNormally);
      },
    );

    test('mỗi ProviderContainer độc lập có 1 AppDatabase riêng, không chia sẻ instance', () {
      final containerA = ProviderContainer();
      addTearDown(containerA.dispose);
      final containerB = ProviderContainer();
      addTearDown(containerB.dispose);

      final dbA = containerA.read(appDatabaseProvider);
      final dbB = containerB.read(appDatabaseProvider);

      expect(identical(dbA, dbB), isFalse);
    });
  });
}
