import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vi_nha_minh/core/constants/default_categories.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/status.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/repositories/category_repository.dart';
import 'package:vi_nha_minh/domain/repositories/status_repository.dart';
import 'package:vi_nha_minh/domain/repositories/transaction_repository.dart';
import 'package:vi_nha_minh/presentation/features/category/category_edit_screen.dart';
import 'package:vi_nha_minh/presentation/providers/category_providers.dart';
import 'package:vi_nha_minh/presentation/providers/status_providers.dart';
import 'package:vi_nha_minh/presentation/providers/transaction_providers.dart';

/// Màn Thêm/Sửa danh mục — SIMPLE BY DEFAULT, POWERFUL WHEN NEEDED.
/// Repository giả (không Drift in-memory thật trong widget test).
class _FakeCategoryRepository implements CategoryRepository {
  _FakeCategoryRepository(this._categories);
  final List<Category> _categories;
  final added = <Category>[];
  final updated = <Category>[];

  @override
  Stream<List<Category>> watchCategories() => Stream.value(_categories);
  @override
  Future<void> addCategory(Category category) async => added.add(category);
  @override
  Future<void> updateCategory(Category category) async => updated.add(category);
  @override
  Future<void> softDeleteCategory(String categoryId) async {}

  @override
  Stream<Set<String>> watchDeletableCategoryIds() => Stream.value(const {});

  @override
  Future<void> deleteCategoryPermanently(String categoryId) async {}
}

class _FakeStatusRepository implements StatusRepository {
  final calls = <String>[];
  @override
  Stream<List<Status>> watchStatuses(String categoryId) => Stream.value(const []);
  @override
  Future<void> addStatus(Status status) async => calls.add('add:${status.name}');
  @override
  Future<void> renameStatus(String statusId, String newName) async =>
      calls.add('rename:$statusId:$newName');
  @override
  Future<void> reorderStatuses(String categoryId, List<String> ids) async =>
      calls.add('reorder');
  @override
  Future<void> softDeleteStatus(String statusId) async => calls.add('hide:$statusId');
  @override
  Future<void> reactivateStatus(String statusId) async => calls.add('reuse:$statusId');

  /// Bước "an toàn để xoá hẳn" do test đặt (mặc định: không bước nào).
  Set<String> deletable = {};
  @override
  Stream<Set<String>> watchDeletableStatusIds() => Stream.value(deletable);
  @override
  Future<void> deleteStatusPermanently(String statusId) async =>
      calls.add('purge:$statusId');
}

/// Nếu màn này chạm vào ledger (ghi giao dịch) test sẽ ném lỗi ngay.
class _ReadOnlyTransactionRepository implements TransactionRepository {
  _ReadOnlyTransactionRepository([this.ledger = const []]);
  final List<Transaction> ledger;
  @override
  Stream<List<Transaction>> watchTransactions() => Stream.value(ledger);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Các test trạng thái bên dưới dựng trên 1 hạng mục có ĐÚNG 3 bước (CCB/ĐCB/ĐG)
/// — độc lập với seed DB mới (CĐ/DH nay có 4 bước, xem seed_statuses_test).
final _threeStepCategories = <Category>[
  for (final c in DefaultCategories.all)
    c.id == 'cho_di' ? c.copyWith(statuses: c.statuses.take(3).toList()) : c,
];

Transaction _txUsingStatus(String statusId) => Transaction(
  id: 'used-$statusId',
  type: TransactionType.expense,
  categoryId: 'cho_di',
  statusId: statusId,
  sourceKind: PoolKind.memberAvailable,
  sourceRefId: 'vo',
  destinationKind: PoolKind.external,
  amountMinor: 1000,
  transactionDate: DateTime(2026, 9, 1),
  createdAt: DateTime(2026, 9, 1),
  clientTxId: 'c-used-$statusId',
);

typedef _Repos = ({_FakeCategoryRepository cats, _FakeStatusRepository statuses});

Future<_Repos> _pump(
  WidgetTester tester, {
  String? categoryId,
  List<Category>? categories,
  TransactionType? initialType,
  bool initialSecondGroup = false,
  Set<String> usedStatusIds = const {},
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final cats = _FakeCategoryRepository(categories ?? _threeStepCategories);
  final statuses = _FakeStatusRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        categoryRepositoryProvider.overrideWithValue(cats),
        statusRepositoryProvider.overrideWithValue(statuses),
        transactionRepositoryProvider.overrideWithValue(
          _ReadOnlyTransactionRepository([
            // Giao dịch ĐANG TỒN TẠI dùng các bước này → không xóa hẳn được.
            for (final id in usedStatusIds) _txUsingStatus(id),
          ]),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CategoryEditScreen(
                  categoryId: categoryId,
                  initialType: initialType,
                  initialSecondGroup: initialSecondGroup,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (cats: cats, statuses: statuses);
}

const _advancedToggle = Key('category_advanced_toggle');

Future<void> _openAdvanced(WidgetTester tester) async {
  await tester.tap(find.byKey(_advancedToggle));
  await tester.pumpAndSettle();
}

Future<void> _tapSave(WidgetTester tester) async {
  final save = find.byKey(const Key('category_save'));
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

Future<void> _selectType(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const Key('category_type')),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

const _advancedTexts = [
  'Màu',
  'Theo dõi tiến độ',
  'Hiện ở màn Tổng hợp',
];

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('A — Thêm mặc định: chỉ Tên, Thu/Chi, Tuỳ chọn nâng cao, Lưu; KHÔNG thấy điều khiển nâng cao', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Thêm danh mục'), findsOneWidget);
    expect(find.byKey(const Key('category_name')), findsOneWidget);
    expect(find.text('Thu'), findsOneWidget);
    expect(find.text('Chi'), findsOneWidget);
    expect(find.text('Tuỳ chọn nâng cao'), findsOneWidget);
    expect(find.text('Lưu danh mục'), findsOneWidget);
    for (final t in _advancedTexts) {
      expect(find.text(t), findsNothing, reason: '"$t" phải ẩn khi thu gọn');
    }
    expect(find.textContaining('excludeFromTotals'), findsNothing);
    expect(find.textContaining('linkedExpenseCategoryId'), findsNothing);
    expect(find.textContaining('statsEnabled'), findsNothing);
  });

  testWidgets('A3 — Không còn cấu hình thu nhập ròng / chi phí liên kết ở bất kỳ chế độ nào (Thu/Chi, mở nâng cao)', (
    tester,
  ) async {
    await _pump(tester);
    await _openAdvanced(tester);

    for (final type in ['Chi', 'Thu']) {
      await _selectType(tester, type);
      expect(find.textContaining('thu nhập ròng'), findsNothing, reason: type);
      expect(find.textContaining('Thu nhập ròng'), findsNothing, reason: type);
      expect(find.textContaining('liên kết'), findsNothing, reason: type);
      expect(find.textContaining('Chi phí liên kết'), findsNothing, reason: type);
      expect(find.text('Không liên kết'), findsNothing, reason: type);
    }
  });

  testWidgets('A2 — Thu: nhóm là "Doanh thu | Khoản thu khác" ngay ở màn chính, không còn công tắc "không tính vào tổng thu nhập"', (
    tester,
  ) async {
    await _pump(tester);
    await _selectType(tester, 'Thu');

    expect(find.text('Thuộc nhóm'), findsOneWidget);
    expect(find.text('Doanh thu'), findsOneWidget);
    expect(find.text('Khoản thu khác'), findsOneWidget);
    expect(find.text('Không tính vào tổng thu nhập'), findsNothing);
    await _openAdvanced(tester);
    expect(find.text('Không tính vào tổng thu nhập'), findsNothing);
  });

  testWidgets('B — Tạo "Trả lương GV" = Chi: category expense đúng, không status/link, không đụng ledger', (
    tester,
  ) async {
    final repos = await _pump(tester);

    await tester.enterText(find.byKey(const Key('category_name')), 'Trả lương GV');
    await _tapSave(tester);

    final c = repos.cats.added.single;
    expect(c.name, 'Trả lương GV');
    expect(c.type, TransactionType.expense);
    expect(c.statuses, isEmpty);
    expect(c.linkedExpenseCategoryId, isNull);
    expect(c.statsEnabled, isFalse);
    expect(c.excludeFromTotals, isFalse);
    expect(c.color, const Color(0xFFE8A23E), reason: 'tự dùng màu mặc định, không bắt chọn màu');
    expect(c.isDefault, isFalse);
    expect(repos.statuses.calls, isEmpty, reason: 'không có status nào được ghi');
    // Màn đóng lại sau khi lưu.
    expect(find.text('Thêm danh mục'), findsNothing);
  });

  testWidgets('B2 — "Chi phí kinh doanh" mặc định là Expense bình thường (không status/link/loại trừ/thống kê)', (tester) async {
    final c = DefaultCategories.chiPhiKinhDoanh;
    expect(DefaultCategories.all.where((x) => x.id == 'chi_phi_kinh_doanh'), hasLength(1));
    expect(c.name, 'Chi phí kinh doanh');
    expect(c.type, TransactionType.expense);
    expect(c.statuses, isEmpty);
    expect(c.linkedExpenseCategoryId, isNull);
    expect(c.excludeFromTotals, isFalse);
    expect(c.statsEnabled, isFalse);
    // Sửa hạng mục này như hạng mục Chi bình thường: gọn, không nâng cao.
    final repos = await _pump(tester, categoryId: 'chi_phi_kinh_doanh');
    expect(find.text('Theo dõi tiến độ'), findsNothing);
    await _tapSave(tester);
    expect(repos.cats.updated.single.type, TransactionType.expense);
  });

  testWidgets('C — Mở nâng cao: thấy Màu + Theo dõi tiến độ; công tắc "không tính vào tổng thu nhập" đã bỏ (nhóm ở màn chính)', (
    tester,
  ) async {
    await _pump(tester);
    await _openAdvanced(tester);

    expect(find.text('Màu'), findsOneWidget);
    expect(find.text('Theo dõi tiến độ'), findsOneWidget);
    expect(find.text('Hiện ở màn Tổng hợp'), findsNothing, reason: 'chưa có bước nào');
    expect(find.text('Không tính vào tổng thu nhập'), findsNothing);

    await _selectType(tester, 'Thu');
    expect(find.text('Không tính vào tổng thu nhập'), findsNothing);
    expect(find.textContaining('excludeFromTotals'), findsNothing);
  });

  testWidgets('C2 — Thêm 1 bước trạng thái thì công tắc "Hiện ở màn Tổng hợp" mới xuất hiện', (tester) async {
    await _pump(tester);
    await _openAdvanced(tester);

    await tester.enterText(find.byKey(const Key('status_add_field')), 'Đã gửi');
    await tester.tap(find.byKey(const Key('status_add_button')));
    await tester.pumpAndSettle();

    expect(find.text('Đã gửi'), findsOneWidget);
    expect(find.text('Hiện ở màn Tổng hợp'), findsOneWidget);
  });

  testWidgets('D — Sửa CĐ: nâng cao tự mở, giữ nguyên 3 bước + thống kê; lưu không đổi thì không ghi gì thừa', (
    tester,
  ) async {
    final repos = await _pump(tester, categoryId: 'cho_di');

    expect(find.text('Theo dõi tiến độ'), findsOneWidget, reason: 'tự mở vì CĐ có workflow');
    expect(find.text('CCB'), findsOneWidget);
    expect(find.text('ĐCB'), findsOneWidget);
    expect(find.text('ĐG'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Hiện ở màn Tổng hợp')).value,
      isTrue,
    );

    await _tapSave(tester);
    final c = repos.cats.updated.single;
    expect(c.statuses.map((s) => s.name), ['CCB', 'ĐCB', 'ĐG']);
    expect(c.statsEnabled, isTrue);
    expect(repos.statuses.calls, ['reorder'], reason: 'không add/xoá/đổi tên nào');
  });

  testWidgets('E — Danh mục cũ có linkedExpenseCategoryId: KHÔNG hiện ra UI, và mở/lưu không làm mất giá trị', (
    tester,
  ) async {
    final hocPhi = Category(
      id: 'hoc_phi',
      name: 'Học phí',
      color: const Color(0xFF12805C),
      type: TransactionType.income,
      linkedExpenseCategoryId: 'sinh_hoat',
      isDefault: false,
    );
    final repos = await _pump(
      tester,
      categoryId: 'hoc_phi',
      categories: [...DefaultCategories.all, hocPhi],
    );

    // Không tự mở nâng cao chỉ vì có liên kết, và liên kết không hiện ở đâu cả.
    expect(find.text('Theo dõi tiến độ'), findsNothing);
    await _openAdvanced(tester);
    expect(find.textContaining('hu nhập ròng'), findsNothing);
    expect(find.textContaining('liên kết'), findsNothing);
    expect(find.text('Sinh hoạt'), findsNothing, reason: 'không còn dropdown danh mục chi liên kết');

    await _tapSave(tester);
    expect(repos.cats.updated.single.linkedExpenseCategoryId, 'sinh_hoat', reason: 'bảo toàn dữ liệu cũ');
    expect(repos.cats.updated.single.name, 'Học phí');
  });

  testWidgets('E2 — Danh mục cũ có liên kết, user đổi tên/màu rồi lưu: liên kết vẫn được giữ', (tester) async {
    final hocPhi = Category(
      id: 'hoc_phi',
      name: 'Học phí',
      color: const Color(0xFF12805C),
      type: TransactionType.income,
      linkedExpenseCategoryId: 'sinh_hoat',
      isDefault: false,
    );
    final repos = await _pump(
      tester,
      categoryId: 'hoc_phi',
      categories: [...DefaultCategories.all, hocPhi],
    );

    await tester.enterText(find.byKey(const Key('category_name')), 'Học phí lớp');
    await _openAdvanced(tester);
    await tester.tap(find.byType(CircleAvatar).at(2)); // đổi màu
    await tester.pumpAndSettle();
    await _tapSave(tester);

    final c = repos.cats.updated.single;
    expect(c.name, 'Học phí lớp');
    expect(c.linkedExpenseCategoryId, 'sinh_hoat');
  });

  testWidgets('F — Sửa danh mục excludeFromTotals (Số dư ban đầu): nhóm "Khoản thu khác" được chọn sẵn, cờ giữ nguyên khi lưu', (tester) async {
    final repos = await _pump(tester, categoryId: 'so_du_ban_dau');

    final group = tester.widget<SegmentedButton<bool>>(find.byKey(const Key('category_group')));
    expect(group.selected, {true}, reason: 'Khoản thu khác = excludeFromTotals');

    await _tapSave(tester);
    expect(repos.cats.updated.single.excludeFromTotals, isTrue);
  });

  testWidgets('Sửa danh mục bình thường (không nâng cao): thu gọn, và giữ màu cũ', (tester) async {
    final repos = await _pump(tester, categoryId: 'sinh_hoat');

    expect(find.text('Theo dõi tiến độ'), findsNothing);
    await _tapSave(tester);
    expect(repos.cats.updated.single.color, DefaultCategories.sinhHoat.color, reason: 'giữ nguyên màu cũ');
  });

  testWidgets('Thu gọn nâng cao KHÔNG làm mất cấu hình: mở, đóng lại, lưu vẫn giữ bước + thống kê', (
    tester,
  ) async {
    final repos = await _pump(tester, categoryId: 'cho_di');

    await tester.tap(find.byKey(_advancedToggle)); // đóng
    await tester.pumpAndSettle();
    expect(find.text('Theo dõi tiến độ'), findsNothing);

    await _tapSave(tester);
    final c = repos.cats.updated.single;
    expect(c.statuses, hasLength(3));
    expect(c.statsEnabled, isTrue);
  });

  Future<void> pickGroup(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('category_group')),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Nhóm CHI: mặc định Chi tiêu (groupKey = null); chọn Chi phí kinh doanh → business_expense, không đụng ledger', (tester) async {
    final repos = await _pump(tester);
    expect(find.text('Thuộc nhóm'), findsOneWidget);
    expect(
      tester.widget<SegmentedButton<bool>>(find.byKey(const Key('category_group'))).selected,
      {false},
    );
    await tester.enterText(find.byKey(const Key('category_name')), 'Quảng cáo');
    await _tapSave(tester);
    expect(repos.cats.added.single.groupKey, isNull, reason: 'Chi tiêu = null');
  });

  testWidgets('Nhóm CHI: chọn Chi phí kinh doanh → lưu groupKey = business_expense (Chi, excludeFromTotals=false)', (tester) async {
    final repos = await _pump(tester);
    await tester.enterText(find.byKey(const Key('category_name')), 'Quảng cáo');
    await pickGroup(tester, 'Chi phí kinh doanh');
    await _tapSave(tester);
    final c = repos.cats.added.single;
    expect(c.type, TransactionType.expense);
    expect(c.groupKey, CategoryGroupKey.businessExpense);
    expect(c.excludeFromTotals, isFalse);
    expect(c.isBusinessExpense, isTrue);
    expect(repos.statuses.calls, isEmpty);
  });

  testWidgets('Nhóm THU: chọn Khoản thu khác → excludeFromTotals = true (không có trường thứ hai), groupKey = null', (tester) async {
    final repos = await _pump(tester);
    await _selectType(tester, 'Thu');
    await tester.enterText(find.byKey(const Key('category_name')), 'Bán lại đồ');
    await pickGroup(tester, 'Khoản thu khác');
    await _tapSave(tester);
    final c = repos.cats.added.single;
    expect(c.type, TransactionType.income);
    expect(c.excludeFromTotals, isTrue);
    expect(c.groupKey, isNull);
  });

  testWidgets('Đổi Chi → Thu xoá lựa chọn nhóm cũ (không rò business_expense sang danh mục Thu)', (tester) async {
    final repos = await _pump(tester);
    await tester.enterText(find.byKey(const Key('category_name')), 'X');
    await pickGroup(tester, 'Chi phí kinh doanh');
    await _selectType(tester, 'Thu');
    expect(
      tester.widget<SegmentedButton<bool>>(find.byKey(const Key('category_group'))).selected,
      {false},
      reason: 'Thu mặc định Doanh thu',
    );
    await _tapSave(tester);
    final c = repos.cats.added.single;
    expect(c.type, TransactionType.income);
    expect(c.groupKey, isNull);
    expect(c.excludeFromTotals, isFalse);
  });

  testWidgets('Sửa danh mục Chi cũ (groupKey null): chuyển sang Chi phí kinh doanh → chỉ đổi groupKey, cùng id, không đụng giao dịch', (tester) async {
    final repos = await _pump(tester, categoryId: 'sinh_hoat');
    expect(
      tester.widget<SegmentedButton<bool>>(find.byKey(const Key('category_group'))).selected,
      {false},
    );
    await pickGroup(tester, 'Chi phí kinh doanh');
    await _tapSave(tester);
    final c = repos.cats.updated.single;
    expect(c.id, 'sinh_hoat');
    expect(c.name, 'Sinh hoạt', reason: 'chỉ đổi nhóm, không đổi tên/id');
    expect(c.groupKey, CategoryGroupKey.businessExpense);
  });

  testWidgets('Thêm từ nhóm "Chi phí kinh doanh" / "Khoản thu khác": điền sẵn loại + nhóm', (tester) async {
    var repos = await _pump(tester, initialType: TransactionType.expense, initialSecondGroup: true);
    expect(
      tester.widget<SegmentedButton<bool>>(find.byKey(const Key('category_group'))).selected,
      {true},
    );
    await tester.enterText(find.byKey(const Key('category_name')), 'Mặt bằng');
    await _tapSave(tester);
    expect(repos.cats.added.single.groupKey, CategoryGroupKey.businessExpense);

    repos = await _pump(tester, initialType: TransactionType.income, initialSecondGroup: true);
    expect(
      tester.widget<SegmentedButton<bool>>(find.byKey(const Key('category_group'))).selected,
      {true},
    );
    await tester.enterText(find.byKey(const Key('category_name')), 'Thưởng thêm');
    await _tapSave(tester);
    expect(repos.cats.added.single.excludeFromTotals, isTrue);
  });

  group('Tạo danh mục mới — chống trùng với danh mục đang dùng / đã ngừng', () {
    final stoppedSinhHoat = <Category>[
      for (final c in DefaultCategories.all)
        c.id == 'sinh_hoat' ? c.copyWith(isActive: false) : c,
    ];

    testWidgets('Tên trùng danh mục ĐANG DÙNG cùng loại → báo "Đã có", không tạo', (tester) async {
      final repos = await _pump(tester);
      await tester.enterText(find.byKey(const Key('category_name')), '  sinh HOẠT ');
      await _tapSave(tester);

      expect(find.text('Đã có danh mục tên này.'), findsOneWidget);
      expect(find.byKey(const Key('category_duplicate_reuse')), findsNothing);
      expect(repos.cats.added, isEmpty);
    });

    testWidgets('Tên trùng danh mục ĐÃ NGỪNG → gợi ý "Sử dụng lại": giữ NGUYÊN id, không tạo bản mới', (tester) async {
      final repos = await _pump(tester, categories: stoppedSinhHoat);
      await tester.enterText(find.byKey(const Key('category_name')), 'Sinh hoạt');
      await _tapSave(tester);

      expect(find.text('Danh mục này đã tồn tại nhưng đang ngừng sử dụng.'), findsOneWidget);
      expect(repos.cats.added, isEmpty, reason: 'không âm thầm tạo duplicate');

      await tester.tap(find.byKey(const Key('category_duplicate_reuse')));
      await tester.pumpAndSettle();
      expect(repos.cats.added, isEmpty);
      expect(repos.cats.updated.single.id, 'sinh_hoat', reason: 'reactivate cùng id');
      expect(repos.cats.updated.single.isActive, isTrue);
    });

    testWidgets('Cùng tên nhưng KHÁC loại (Thu ↔ Chi) không bị coi là trùng', (tester) async {
      final repos = await _pump(tester);
      await _selectType(tester, 'Thu');
      await tester.enterText(find.byKey(const Key('category_name')), 'Sinh hoạt');
      await _tapSave(tester);
      expect(repos.cats.added.single.name, 'Sinh hoạt');
      expect(repos.cats.added.single.type, TransactionType.income);
    });

    testWidgets('Thông báo trùng biến mất khi gõ lại tên', (tester) async {
      await _pump(tester);
      await tester.enterText(find.byKey(const Key('category_name')), 'Sinh hoạt');
      await _tapSave(tester);
      expect(find.text('Đã có danh mục tên này.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('category_name')), 'Sinh hoạt 2');
      await tester.pump();
      expect(find.text('Đã có danh mục tên này.'), findsNothing);
    });
  });

  testWidgets('G — Tên rỗng: hiện "Nhập tên danh mục", không lưu', (tester) async {
    final repos = await _pump(tester);

    await _tapSave(tester);

    expect(find.text('Nhập tên danh mục'), findsOneWidget);
    expect(repos.cats.added, isEmpty);
    expect(find.text('Thêm danh mục'), findsOneWidget, reason: 'vẫn ở màn hiện tại');

    // Gõ lại thì lỗi biến mất.
    await tester.enterText(find.byKey(const Key('category_name')), 'A');
    await tester.pump();
    expect(find.text('Nhập tên danh mục'), findsNothing);
  });

  group('Trạng thái — Đang sử dụng / Ngừng sử dụng / Sử dụng lại / Đổi tên (không xoá cứng, giữ ID)', () {
    Category choDiWith({Set<String> stopped = const {}}) => DefaultCategories.choDi.copyWith(
      statuses: [
        for (final s in DefaultCategories.choDi.statuses.take(3))
          stopped.contains(s.id) ? s.copyWith(isActive: false) : s,
      ],
    );

    Future<_Repos> pumpChoDi(
      WidgetTester tester, {
      Set<String> stopped = const {},
      Set<String> used = const {},
    }) => _pump(
      tester,
      categoryId: 'cho_di',
      usedStatusIds: used,
      categories: [for (final c in DefaultCategories.all) c.id == 'cho_di' ? choDiWith(stopped: stopped) : c],
    );

    testWidgets('Bố cục: "Đang sử dụng" với [Sửa] [Ngừng sử dụng] từng dòng; không có nhãn "Ngừng sử dụng (n)" khi chưa có', (
      tester,
    ) async {
      await pumpChoDi(tester);

      expect(find.text('Đang sử dụng'), findsOneWidget);
      expect(find.textContaining('Ngừng sử dụng ('), findsNothing);
      for (final id in ['cho_di_chua_chuan_bi', 'cho_di_da_chuan_bi', 'cho_di_da_gui']) {
        expect(find.byKey(Key('status_edit_$id')), findsOneWidget);
        expect(find.byKey(Key('status_stop_$id')), findsOneWidget);
      }
      expect(
        find.descendant(of: find.byType(ListView), matching: find.text('Ngừng sử dụng')),
        findsNWidgets(3),
        reason: 'nút ở 3 dòng, không còn chữ "Xoá" cho bước',
      );
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Ngừng sử dụng')),
        findsOneWidget,
        reason: 'nút ngừng sử dụng cả danh mục ở thanh trên',
      );
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('Ngừng sử dụng bước đã có → chuyển sang khu "Ngừng sử dụng (1)" với [Sử dụng lại]; lưu = softDelete, không mất bước', (
      tester,
    ) async {
      final repos = await pumpChoDi(tester);

      await tester.tap(find.byKey(const Key('status_stop_cho_di_da_gui')));
      await tester.pumpAndSettle();
      expect(find.text('Ngừng sử dụng (1)'), findsOneWidget);
      expect(find.byKey(const Key('status_reuse_cho_di_da_gui')), findsOneWidget);
      expect(find.byKey(const Key('status_stop_cho_di_da_gui')), findsNothing);

      await _tapSave(tester);
      expect(repos.statuses.calls, contains('hide:cho_di_da_gui'));
      expect(repos.statuses.calls.where((c) => c.startsWith('add:')), isEmpty);
      final saved = repos.cats.updated.single.statuses;
      expect(saved, hasLength(3), reason: 'không mất bước nào');
      expect(saved.where((s) => s.id == 'cho_di_da_gui').single.isActive, isFalse);
    });

    testWidgets('Sử dụng lại → giữ NGUYÊN id cũ (reactivate), không add status mới', (tester) async {
      final repos = await pumpChoDi(tester, stopped: {'cho_di_da_gui'});

      expect(find.text('Ngừng sử dụng (1)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('status_reuse_cho_di_da_gui')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ngừng sử dụng ('), findsNothing);
      await _tapSave(tester);

      expect(repos.statuses.calls, contains('reuse:cho_di_da_gui'));
      expect(repos.statuses.calls.where((c) => c.startsWith('add:')), isEmpty);
      expect(repos.cats.updated.single.statuses.where((s) => s.id == 'cho_di_da_gui').single.isActive, isTrue);
    });

    testWidgets('Xóa hẳn: chỉ hiện ở bước ĐÃ NGỪNG + chưa từng dùng; bước đã dùng chỉ có [Sử dụng lại] + 1 dòng giải thích', (tester) async {
      await pumpChoDi(
        tester,
        stopped: {'cho_di_chua_chuan_bi', 'cho_di_da_gui'},
        used: {'cho_di_chua_chuan_bi'},
      );

      expect(find.byKey(const Key('status_delete_cho_di_da_gui')), findsOneWidget);
      expect(find.byKey(const Key('status_delete_cho_di_chua_chuan_bi')), findsNothing, reason: 'đã dùng lịch sử');
      expect(find.byKey(const Key('status_reuse_cho_di_chua_chuan_bi')), findsOneWidget);
      expect(find.byKey(const Key('status_used_note')), findsOneWidget);
      expect(find.byKey(const Key('status_delete_cho_di_da_chuan_bi')), findsNothing, reason: 'còn đang dùng');
      expect(find.textContaining('foreign'), findsNothing);
      expect(find.textContaining('constraint'), findsNothing);
    });

    testWidgets('Xóa hẳn: xác nhận → purge đúng id, biến khỏi danh sách, KHÔNG ghi ledger; Huỷ thì không xoá', (tester) async {
      final repos = await pumpChoDi(
        tester,
        stopped: {'cho_di_da_gui'},
      );

      await tester.tap(find.byKey(const Key('status_delete_cho_di_da_gui')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Huỷ'));
      await tester.pumpAndSettle();
      expect(repos.statuses.calls.where((c) => c.startsWith('purge:')), isEmpty);
      expect(find.byKey(const Key('status_cho_di_da_gui')), findsOneWidget);

      await tester.tap(find.byKey(const Key('status_delete_cho_di_da_gui')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_delete_status')));
      await tester.pumpAndSettle();

      expect(repos.statuses.calls, contains('purge:cho_di_da_gui'));
      expect(find.byKey(const Key('status_cho_di_da_gui')), findsNothing);
      expect(find.textContaining('Ngừng sử dụng ('), findsNothing);

      await _tapSave(tester);
      expect(repos.statuses.calls.where((c) => c.contains('cho_di_da_gui') && !c.startsWith('purge:')), isEmpty);
      expect(repos.cats.updated.single.statuses.map((s) => s.id), isNot(contains('cho_di_da_gui')));
    });

    testWidgets('Bước vừa bấm "Ngừng sử dụng" trong bản nháp (chưa Lưu) KHÔNG có Xóa hẳn dù id nằm trong danh sách an toàn', (tester) async {
      await pumpChoDi(tester);

      await tester.tap(find.byKey(const Key('status_stop_cho_di_da_gui')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('status_reuse_cho_di_da_gui')), findsOneWidget);
      expect(find.byKey(const Key('status_delete_cho_di_da_gui')), findsNothing);
    });

    testWidgets('Đổi tên (Sửa) → chỉ renameStatus với ĐÚNG id cũ, không add/ngừng', (tester) async {
      final repos = await pumpChoDi(tester);

      await tester.tap(find.byKey(const Key('status_edit_cho_di_da_gui')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('status_rename_field')), 'Đã chuyển');
      await tester.tap(find.text('Lưu').last);
      await tester.pumpAndSettle();
      expect(find.text('Đã chuyển'), findsOneWidget);
      await _tapSave(tester);

      expect(repos.statuses.calls, contains('rename:cho_di_da_gui:Đã chuyển'));
      expect(repos.statuses.calls.where((c) => c.startsWith('add:') || c.startsWith('hide:')), isEmpty);
      expect(repos.cats.updated.single.statuses.map((s) => s.id), [
        'cho_di_chua_chuan_bi',
        'cho_di_da_chuan_bi',
        'cho_di_da_gui',
      ], reason: 'id và thứ tự giữ nguyên');
    });

    testWidgets('Đổi tên trùng tên bước khác (kể cả đã ngừng) → báo lỗi trong hộp thoại, không đổi', (tester) async {
      final repos = await pumpChoDi(tester, stopped: {'cho_di_da_gui'});

      await tester.tap(find.byKey(const Key('status_edit_cho_di_chua_chuan_bi')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('status_rename_field')), 'ĐG');
      await tester.tap(find.text('Lưu').last);
      await tester.pumpAndSettle();

      expect(find.text('Đã có trạng thái tên này'), findsOneWidget);
      await tester.tap(find.text('Huỷ'));
      await tester.pumpAndSettle();
      await _tapSave(tester);
      expect(repos.statuses.calls.where((c) => c.startsWith('rename:')), isEmpty);
    });

    testWidgets('Thêm trạng thái mới hợp lệ → add với id mới, nằm trong "Đang sử dụng"', (tester) async {
      final repos = await pumpChoDi(tester);

      await tester.enterText(find.byKey(const Key('status_add_field')), 'Chờ xác nhận');
      await tester.tap(find.byKey(const Key('status_add_button')));
      await tester.pumpAndSettle();
      expect(find.text('Chờ xác nhận'), findsOneWidget);
      expect(find.byKey(const Key('status_duplicate_notice')), findsNothing);
      await _tapSave(tester);

      expect(repos.statuses.calls, contains('add:Chờ xác nhận'));
    });

    testWidgets('Thêm tên TRÙNG bước đã ngừng sử dụng → KHÔNG tạo duplicate, hiện thông báo + [Sử dụng lại]', (tester) async {
      final repos = await pumpChoDi(tester, stopped: {'cho_di_da_gui'});

      // Khác hoa/thường và khoảng trắng thừa vẫn coi là cùng tên.
      await tester.enterText(find.byKey(const Key('status_add_field')), '  đg ');
      await tester.tap(find.byKey(const Key('status_add_button')));
      await tester.pumpAndSettle();

      expect(find.text('Trạng thái này đã tồn tại nhưng đang ngừng sử dụng.'), findsOneWidget);
      expect(find.byKey(const Key('status_duplicate_reuse')), findsOneWidget);
      expect(find.text('ĐG'), findsOneWidget, reason: 'không có dòng trùng mới');

      await tester.tap(find.byKey(const Key('status_duplicate_reuse')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('status_duplicate_notice')), findsNothing);
      expect(find.textContaining('Ngừng sử dụng ('), findsNothing);
      await _tapSave(tester);

      expect(repos.statuses.calls, contains('reuse:cho_di_da_gui'));
      expect(repos.statuses.calls.where((c) => c.startsWith('add:')), isEmpty, reason: 'tuyệt đối không tạo id mới');
    });

    testWidgets('Vừa ngừng sử dụng trong cùng phiên rồi thêm lại đúng tên → cũng bị chặn trùng', (tester) async {
      final repos = await pumpChoDi(tester);

      await tester.tap(find.byKey(const Key('status_stop_cho_di_da_gui')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('status_add_field')), 'ĐG');
      await tester.tap(find.byKey(const Key('status_add_button')));
      await tester.pumpAndSettle();

      expect(find.text('Trạng thái này đã tồn tại nhưng đang ngừng sử dụng.'), findsOneWidget);
      await _tapSave(tester);
      expect(repos.statuses.calls.where((c) => c.startsWith('add:')), isEmpty);
    });

    testWidgets('Thêm tên TRÙNG bước đang dùng → thông báo "đã có", không add, không có nút Sử dụng lại', (tester) async {
      final repos = await pumpChoDi(tester);

      await tester.enterText(find.byKey(const Key('status_add_field')), 'CCB');
      await tester.tap(find.byKey(const Key('status_add_button')));
      await tester.pumpAndSettle();

      expect(find.text('Trạng thái này đã có.'), findsOneWidget);
      expect(find.byKey(const Key('status_duplicate_reuse')), findsNothing);
      await _tapSave(tester);
      expect(repos.statuses.calls.where((c) => c.startsWith('add:')), isEmpty);
    });

    testWidgets('Gõ lại vào ô thêm thì thông báo trùng biến mất', (tester) async {
      await pumpChoDi(tester, stopped: {'cho_di_da_gui'});
      await tester.enterText(find.byKey(const Key('status_add_field')), 'ĐG');
      await tester.tap(find.byKey(const Key('status_add_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('status_duplicate_notice')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('status_add_field')), 'ĐGx');
      await tester.pump();
      expect(find.byKey(const Key('status_duplicate_notice')), findsNothing);
    });
  });
}
