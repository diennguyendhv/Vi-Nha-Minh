import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vi_nha_minh/core/constants/default_categories.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/presentation/features/category/category_list_screen.dart';
import 'package:vi_nha_minh/presentation/providers/category_providers.dart';

Category _custom(
  String id,
  String name,
  TransactionType type, {
  bool exclude = false,
  String? group,
  bool active = true,
}) => Category(
  id: id,
  name: name,
  color: Colors.teal,
  type: type,
  excludeFromTotals: exclude,
  groupKey: group,
  isDefault: false,
  isActive: active,
);

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  final categories = <Category>[
    ...DefaultCategories.all,
    _custom('hoc_phi', 'Học phí', TransactionType.income),
    _custom('luong_gv', 'Lương giáo viên', TransactionType.expense,
        group: CategoryGroupKey.businessExpense),
    // Danh mục Chi cũ chưa phân nhóm (groupKey null) → Chi tiêu.
    _custom('cu_chua_phan_nhom', 'Vận hành cũ', TransactionType.expense),
    _custom('da_ngung', 'Đã ngừng', TransactionType.expense, active: false),
  ];

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoriesStreamProvider.overrideWith((ref) => Stream.value(categories)),
        ],
        child: const MaterialApp(home: CategoryListScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder inGroup(String key, String text) => find.descendant(
    of: find.byKey(Key('category_group_$key')),
    matching: find.text(text),
  );

  testWidgets('2 tầng: 4 nhóm chính cố định, danh mục con nằm đúng nhóm', (tester) async {
    await pump(tester);
    expect(find.text('THU'), findsOneWidget);
    expect(find.text('CHI'), findsOneWidget);
    for (final key in ['revenue', 'other_inflow', 'spending', 'business_expense']) {
      expect(find.byKey(Key('category_group_$key')), findsOneWidget);
    }

    expect(inGroup('revenue', 'Thu nhập'), findsOneWidget);
    expect(inGroup('revenue', 'Học phí'), findsOneWidget);
    expect(inGroup('other_inflow', 'Số dư ban đầu'), findsOneWidget);
    expect(inGroup('other_inflow', 'Thu nhập'), findsNothing);

    expect(inGroup('spending', 'Sinh hoạt'), findsOneWidget);
    expect(inGroup('spending', 'Vận hành cũ'), findsOneWidget, reason: 'groupKey null = Chi tiêu');
    expect(inGroup('business_expense', 'Chi phí kinh doanh'), findsNWidgets(2), reason: 'tiêu đề nhóm + danh mục seed cùng tên');
    expect(inGroup('business_expense', 'Lương giáo viên'), findsOneWidget);
    expect(inGroup('spending', 'Lương giáo viên'), findsNothing);
  });

  testWidgets('Ẩn: Vay/Hoàn tiền/Trả nợ/Lãi cho vay, mọi danh mục Chuyển và danh mục đã ngừng', (tester) async {
    await pump(tester);
    for (final hidden in [
      'Cho vay',
      'Đi vay',
      'Trả nợ',
      'Lãi cho vay',
      'Hoàn tiền / Thu hồi',
      'Nạp quỹ',
      'Tiết kiệm',
      'Chuyển tiền cho thành viên khác',
      'Đã ngừng',
    ]) {
      expect(find.text(hidden), findsNothing, reason: '"$hidden" phải ẩn');
    }
    expect(find.textContaining('Chuyển'), findsNothing);
  });

  testWidgets('Mỗi nhóm có nút "+ Thêm danh mục" mở màn Thêm với nhóm điền sẵn', (tester) async {
    await pump(tester);
    expect(find.text('+ Thêm danh mục'), findsNWidgets(4));

    await tester.tap(find.byKey(const Key('add_category_business_expense')));
    await tester.pumpAndSettle();
    expect(find.text('Thêm danh mục'), findsOneWidget);
    expect(
      tester.widget<SegmentedButton<bool>>(find.byKey(const Key('category_group'))).selected,
      {true},
    );
    expect(find.text('Chi phí kinh doanh'), findsWidgets);
  });

  testWidgets('Chạm 1 danh mục mở màn Sửa đúng danh mục', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('category_row_luong_gv')));
    await tester.pumpAndSettle();
    expect(find.text('Sửa danh mục'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const Key('category_name'))).controller!.text,
      'Lương giáo viên',
    );
  });
}
