import 'package:flutter/widgets.dart' show Key, Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vi_nha_minh/core/constants/default_categories.dart';
import 'package:vi_nha_minh/core/constants/default_funds.dart';
import 'package:vi_nha_minh/core/constants/default_savings_asset_types.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/fund.dart';
import 'package:vi_nha_minh/domain/entities/obligation.dart';
import 'package:vi_nha_minh/domain/entities/savings_asset_type.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/repositories/category_repository.dart';
import 'package:vi_nha_minh/domain/repositories/fund_repository.dart';
import 'package:vi_nha_minh/domain/repositories/obligation_repository.dart';
import 'package:vi_nha_minh/domain/repositories/savings_asset_type_repository.dart';
import 'package:vi_nha_minh/domain/repositories/transaction_repository.dart';
import 'package:vi_nha_minh/main.dart';
import 'package:vi_nha_minh/presentation/providers/app_lock_provider.dart';
import '../../support/fake_app_lock.dart';
import 'package:vi_nha_minh/presentation/features/fund/fund_list_screen.dart';
import 'package:vi_nha_minh/presentation/features/savings/savings_screen.dart';
import 'package:vi_nha_minh/presentation/features/settings/settings_screen.dart';
import 'package:vi_nha_minh/presentation/providers/category_providers.dart';
import 'package:vi_nha_minh/presentation/providers/fund_providers.dart';
import 'package:vi_nha_minh/presentation/providers/obligation_providers.dart';
import 'package:vi_nha_minh/presentation/providers/savings_asset_type_providers.dart';
import 'package:vi_nha_minh/presentation/providers/transaction_providers.dart';

// Repository giả chạy trên Stream.value — KHÔNG dùng Drift in-memory thật
// trong widget test (gotcha đã biết: `pumpAndSettle` treo vì timer nội bộ của
// Drift, xem `test/presentation/features/home_screen_test.dart`).
class _EmptyTransactionRepository implements TransactionRepository {
  @override
  Stream<List<Transaction>> watchTransactions() => Stream.value(const []);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _StaticObligationRepository implements ObligationRepository {
  @override
  Stream<List<Obligation>> watchObligations() => Stream.value(const []);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _StaticCategoryRepository implements CategoryRepository {
  @override
  Stream<List<Category>> watchCategories() => Stream.value(DefaultCategories.all);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _StaticFundRepository implements FundRepository {
  @override
  Stream<List<Fund>> watchFunds() => Stream.value(DefaultFunds.all);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _StaticSavingsAssetTypeRepository implements SavingsAssetTypeRepository {
  @override
  Stream<List<SavingsAssetType>> watchAssetTypes() =>
      Stream.value(DefaultSavingsAssetTypes.all);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// F23 (Pixel 7a acceptance, 2026-09-19): chạm avatar "GĐ" ở Trang chủ mở
/// `SettingsScreen` bằng `MaterialPageRoute` — route MỚI, không còn nằm dưới
/// `Scaffold` của `AppShell` — nhưng `SettingsScreen` trả về `ListView` trần
/// nên `InkWell` của từng dòng ném "No Material widget found" trên máy thật.
///
/// Test này chạy trên TOÀN BỘ app thật (`ViNhaMinhApp`, repository giả theo
/// bộ seed mặc định thật), không bọc thêm `Scaffold` nào, để tái hiện đúng đường đi của người
/// dùng. Các test cũ dựng `HomeScreen` bên trong `Scaffold(body: ...)` tự tạo
/// nên không bao giờ bắt được lỗi này.
void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLockPlatformProvider.overrideWithValue(FakeAppLockPlatform()),
          deviceAuthenticatorProvider.overrideWithValue(FakeDeviceAuthenticator()),
          transactionRepositoryProvider.overrideWithValue(_EmptyTransactionRepository()),
          categoryRepositoryProvider.overrideWithValue(_StaticCategoryRepository()),
          fundRepositoryProvider.overrideWithValue(_StaticFundRepository()),
          savingsAssetTypeRepositoryProvider.overrideWithValue(
            _StaticSavingsAssetTypeRepository(),
          ),
          obligationRepositoryProvider.overrideWithValue(_StaticObligationRepository()),
        ],
        child: const ViNhaMinhApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.text('GĐ'));
    await tester.pumpAndSettle();
  }

  testWidgets('Home → chạm avatar "GĐ" → Settings mở được, không có lỗi "No Material widget found"', (
    tester,
  ) async {
    await pumpApp(tester);
    await openSettings(tester);

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'không được có "No Material widget found"');
    // Các dòng cài đặt hiển thị bình thường (InkWell cần Material tổ tiên).
    expect(find.text('Quỹ'), findsOneWidget);
    expect(find.text('Tiết kiệm'), findsOneWidget);
    expect(find.text('Khóa ứng dụng'), findsOneWidget);
  });

  testWidgets('Settings → Tiết kiệm mở được; Back về Settings', (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpApp(tester);
    await openSettings(tester);

    await tester.tap(find.text('Tiết kiệm'));
    await tester.pumpAndSettle();
    expect(find.byType(SavingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Savings 2 tầng: "Chưa phân bổ" luôn ở đầu, rồi bộ loại tài sản mặc định (F11).
    expect(find.text('Chưa phân bổ'), findsOneWidget);
    expect(find.text('Gửi ngân hàng'), findsOneWidget);
    expect(find.text('Vàng'), findsOneWidget);
    expect(find.text('Chứng khoán'), findsOneWidget);
    expect(find.text('Khác'), findsOneWidget);
    expect(find.text('Tiền mặt'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SavingsScreen), findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('Settings → Quỹ mở được, có nút tạo quỹ mới; Back về Settings', (tester) async {
    await pumpApp(tester);
    await openSettings(tester);

    await tester.tap(find.text('Quỹ'));
    await tester.pumpAndSettle();
    expect(find.byType(FundListScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.text('Quỹ tiền ăn'), findsOneWidget);
    expect(find.text('+ Tạo quỹ mới'), findsOneWidget, reason: 'F13: UI tạo quỹ có sẵn');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(FundListScreen), findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('Back từ Settings về Trang chủ, điều hướng cũ (4 tab) vẫn hoạt động', (tester) async {
    await pumpApp(tester);
    await openSettings(tester);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byKey(const Key('home_household_spending')), findsOneWidget);

    for (final label in ['Giao dịch', 'Danh mục', 'Tổng hợp', 'Trang chủ']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'tab $label');
    }
    expect(find.byKey(const Key('home_household_spending')), findsOneWidget);
  });
}
