import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vi_nha_minh/core/constants/default_categories.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/repositories/category_repository.dart';
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

class _RecordingCategoryRepository implements CategoryRepository {
  _RecordingCategoryRepository(this.all, this.deletable);
  final List<Category> all;
  final Set<String> deletable;
  final calls = <String>[];
  @override
  Stream<List<Category>> watchCategories() => Stream.value(all);
  @override
  Stream<Set<String>> watchDeletableCategoryIds() => Stream.value(deletable);
  @override
  Future<void> updateCategory(Category category) async =>
      calls.add('update:${category.id}:active=${category.isActive}');
  @override
  Future<void> deleteCategoryPermanently(String categoryId) async =>
      calls.add('purge:$categoryId');
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

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

  group('Ngừng sử dụng — Sử dụng lại / Xóa hẳn (chỉ khi chưa từng dùng)', () {
    final stopped = <Category>[
      ...DefaultCategories.all,
      _custom('chua_dung', 'Test chưa dùng', TransactionType.expense, active: false),
      _custom('da_dung', 'Đã có lịch sử', TransactionType.expense, active: false),
    ];

    Future<_RecordingCategoryRepository> pumpStopped(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _RecordingCategoryRepository(stopped, {'chua_dung'});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [categoryRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(home: CategoryListScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('category_stopped_section')));
      await tester.tap(find.byKey(const Key('category_stopped_section')));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('Khu "Ngừng sử dụng (2)": Xóa hẳn CHỈ ở mục chưa dùng; mục đã dùng có giải thích dễ hiểu, không thuật ngữ kỹ thuật', (tester) async {
      await pumpStopped(tester);

      expect(find.text('Ngừng sử dụng (2)'), findsOneWidget);
      expect(find.byKey(const Key('delete_category_chua_dung')), findsOneWidget);
      expect(find.byKey(const Key('delete_category_da_dung')), findsNothing);
      expect(find.byKey(const Key('reuse_category_chua_dung')), findsOneWidget);
      expect(find.byKey(const Key('reuse_category_da_dung')), findsOneWidget);
      expect(find.text('Đã được dùng trong lịch sử nên không thể xóa.'), findsOneWidget);
      expect(find.textContaining('foreign'), findsNothing);
      expect(find.textContaining('reference'), findsNothing);
    });

    testWidgets('Không có danh mục ngừng → không hiện khu này', (tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _RecordingCategoryRepository(DefaultCategories.all, {});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [categoryRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(home: CategoryListScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('category_stopped_section')), findsNothing);
    });

    testWidgets('Danh mục hệ thống (Chuyển / Vay / Hoàn tiền) đã ngừng cũng không xuất hiện ở đây', (tester) async {
      final repo = _RecordingCategoryRepository([
        for (final c in DefaultCategories.all) c.copyWith(isActive: false),
      ], {});
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [categoryRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(home: CategoryListScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('category_stopped_section')));
      await tester.pumpAndSettle();
      for (final id in ['tiet_kiem', 'nap_quy', 'chuyen_tien_thanh_vien', 'cho_vay', 'vay_no', 'tra_no', 'lai_cho_vay', 'hoan_tien_thu_hoi']) {
        expect(find.byKey(Key('stopped_category_$id')), findsNothing, reason: id);
      }
      expect(find.byKey(const Key('stopped_category_sinh_hoat')), findsOneWidget);
    });

    testWidgets('Sử dụng lại → updateCategory cùng id, isActive=true; KHÔNG tạo mới', (tester) async {
      final repo = await pumpStopped(tester);
      await tester.tap(find.byKey(const Key('reuse_category_da_dung')));
      await tester.pumpAndSettle();
      expect(repo.calls, ['update:da_dung:active=true']);
    });

    testWidgets('Xóa hẳn: Huỷ → không xoá; Xác nhận → deleteCategoryPermanently đúng id', (tester) async {
      final repo = await pumpStopped(tester);

      await tester.tap(find.byKey(const Key('delete_category_chua_dung')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Huỷ'));
      await tester.pumpAndSettle();
      expect(repo.calls, isEmpty);

      await tester.tap(find.byKey(const Key('delete_category_chua_dung')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_delete_category')));
      await tester.pumpAndSettle();
      expect(repo.calls, ['purge:chua_dung']);
    });
  });
}
