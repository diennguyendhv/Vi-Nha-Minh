import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vi_nha_minh/core/constants/default_savings_asset_types.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/family_member.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/savings_asset_type.dart';
import 'package:vi_nha_minh/domain/entities/status.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/entities/transfer_kind.dart';
import 'package:vi_nha_minh/presentation/features/summary/summary_screen.dart';
import 'package:vi_nha_minh/presentation/features/transactions/transaction_detail_screen.dart';
import 'package:vi_nha_minh/presentation/providers/category_providers.dart';
import 'package:vi_nha_minh/presentation/providers/counterparty_providers.dart';
import 'package:vi_nha_minh/presentation/providers/obligation_providers.dart';
import 'package:vi_nha_minh/presentation/providers/savings_asset_type_providers.dart';
import 'package:vi_nha_minh/presentation/providers/transaction_providers.dart';

const _chua = Status(id: 'st_chua', categoryId: 'cho_di', name: 'CCB', sortOrder: 0);
const _gui = Status(id: 'st_gui', categoryId: 'cho_di', name: 'ĐG', sortOrder: 1);
const _cu = Status(id: 'st_cu', categoryId: 'cho_di', name: 'Cũ', sortOrder: 2, isActive: false);

Category _cat(
  String id,
  String name,
  TransactionType type, {
  bool exclude = false,
  String? group,
  List<Status> statuses = const [],
}) => Category(
  id: id,
  name: name,
  color: Colors.teal,
  type: type,
  excludeFromTotals: exclude,
  groupKey: group,
  statuses: statuses,
);

final _cats = <Category>[
  _cat('hoc_phi', 'Học phí', TransactionType.income),
  _cat('lap_trinh', 'Lập trình', TransactionType.income),
  _cat('so_du_ban_dau', 'Số dư ban đầu', TransactionType.income, exclude: true),
  _cat('thu_khac', 'Khác', TransactionType.income, exclude: true),
  _cat('sinh_hoat', 'Sinh hoạt', TransactionType.expense),
  _cat('cho_di', 'CĐ', TransactionType.expense, statuses: const [_chua, _gui, _cu]),
  _cat('luong_gv', 'Lương nhân viên', TransactionType.expense, group: CategoryGroupKey.businessExpense),
  _cat('chuyen_tien_thanh_vien', 'Chuyển tiền thành viên', TransactionType.transfer),
  _cat('tiet_kiem', 'Tiết kiệm', TransactionType.transfer),
  _cat('cho_vay', 'Cho vay', TransactionType.transfer),
  _cat('vay_no', 'Đi vay', TransactionType.income),
  _cat('hoan_tien_thu_hoi', 'Hoàn tiền / Thu hồi', TransactionType.income, exclude: true),
];

int _n = 0;
final _now = DateTime.now();
DateTime get _today => DateTime(_now.year, _now.month, _now.day);

Transaction _in(String cat, int amount, {String to = 'vo', DateTime? date, String note = '', String? obligation, String? recoveryOf}) {
  _n++;
  final d = date ?? _today;
  return Transaction(
    id: 'in-$_n',
    type: TransactionType.income,
    categoryId: cat,
    sourceKind: PoolKind.external,
    destinationKind: PoolKind.memberAvailable,
    destinationRefId: to,
    amountMinor: amount,
    note: note,
    obligationId: obligation,
    recoveryOfTxId: recoveryOf,
    transactionDate: d,
    createdAt: d.add(Duration(seconds: _n)),
    clientTxId: 'c-in-$_n',
  );
}

Transaction _out(String cat, int amount, {String from = 'vo', DateTime? date, String note = '', String? statusId, String? id}) {
  _n++;
  final d = date ?? _today;
  return Transaction(
    id: id ?? 'out-$_n',
    type: TransactionType.expense,
    categoryId: cat,
    sourceKind: PoolKind.memberAvailable,
    sourceRefId: from,
    destinationKind: PoolKind.external,
    amountMinor: amount,
    note: note,
    statusId: statusId,
    transactionDate: d,
    createdAt: d.add(Duration(seconds: _n)),
    clientTxId: 'c-out-$_n',
  );
}

Transaction _move(String cat, int amount, {String from = 'vo', String to = 'chong', PoolKind toKind = PoolKind.memberAvailable, String note = ''}) {
  _n++;
  return Transaction(
    id: 'mv-$_n',
    type: TransactionType.transfer,
    categoryId: cat,
    sourceKind: PoolKind.memberAvailable,
    sourceRefId: from,
    destinationKind: toKind,
    destinationRefId: to,
    amountMinor: amount,
    note: note,
    transactionDate: _today,
    createdAt: _today.add(Duration(seconds: _n)),
    clientTxId: 'c-mv-$_n',
  );
}

Future<void> _pump(WidgetTester tester, List<Transaction> ledger) async {
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        transactionsStreamProvider.overrideWith((ref) => Stream.value(ledger)),
        categoriesStreamProvider.overrideWith((ref) => Stream.value(_cats)),
        obligationsStreamProvider.overrideWith((ref) => Stream.value(const [])),
        savingsAssetTypesStreamProvider.overrideWith((ref) => Stream.value(DefaultSavingsAssetTypes.all)),
        counterpartiesStreamProvider.overrideWith((ref) => Stream.value(const [])),
      ],
      child: const MaterialApp(home: Scaffold(body: SummaryScreen())),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _scrollView() => find.byType(CustomScrollView);

Future<void> _tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _openFilters(WidgetTester tester) async => _tapKey(tester, 'summary_filter_toggle');

/// Mở bảng lọc → bộ chọn Danh mục / Trạng thái (đa chọn).
Future<void> _openPicker(WidgetTester tester, String pickerKey) async {
  if (find.byKey(Key(pickerKey)).evaluate().isEmpty) await _openFilters(tester);
  await _tapKey(tester, pickerKey);
}

Future<void> _toggleOption(WidgetTester tester, String optionId) async {
  final f = find.byKey(Key('multi_$optionId'));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _closeSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('multi_done')));
  await tester.pumpAndSettle();
}

Future<void> _pickCategories(WidgetTester tester, List<String> ids) async {
  await _openPicker(tester, 'summary_pick_categories');
  for (final id in ids) {
    await _toggleOption(tester, id);
  }
  await _closeSheet(tester);
}

Future<void> _pickStatuses(WidgetTester tester, List<String> ids, {bool none = false}) async {
  await _openPicker(tester, 'summary_pick_statuses');
  if (none) await _toggleOption(tester, 'none');
  for (final id in ids) {
    await _toggleOption(tester, id);
  }
  await _closeSheet(tester);
}

String _header(WidgetTester tester) {
  final texts = tester
      .widgetList<Text>(find.descendant(of: find.byKey(const Key('summary_result_header')), matching: find.byType(Text)))
      .map((t) => t.data!)
      .toList();
  return texts.join(' | ');
}

int _rowCount(WidgetTester tester) => find.byWidgetPredicate((w) => w.key is ValueKey<String> && ((w.key! as ValueKey<String>).value.startsWith('in-') || (w.key! as ValueKey<String>).value.startsWith('out-') || (w.key! as ValueKey<String>).value.startsWith('mv-'))).evaluate().length;

Text _valueText(WidgetTester tester, String cardKey, String startsWith) => tester
    .widgetList<Text>(find.descendant(of: find.byKey(Key(cardKey)), matching: find.byType(Text)))
    .firstWhere((t) => t.data!.endsWith(' đ'));

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  final base = <Transaction>[
    _in('hoc_phi', 10000000, to: 'vo', note: 'HP lớp Excel'),
    _in('lap_trinh', 5000000, to: 'chong', note: 'web bán hàng'),
    _in('so_du_ban_dau', 2000000, to: 'vo'),
    _in('thu_khac', 450000, to: 'chong', note: 'Bán lại quạt'),
    _out('sinh_hoat', 120000, from: 'vo', note: 'Đi chợ'),
    _out('sinh_hoat', 5000, from: 'chong', note: 'gửi xe'),
    _out('luong_gv', 4000000, from: 'vo', note: 'Lương cô Lam'),
    _out('cho_di', 300000, from: 'chong', statusId: 'st_chua', note: 'CĐ tháng này'),
    _out('cho_di', 200000, from: 'vo', statusId: 'st_gui', note: 'đã gửi'),
  ];

  testWidgets('Mặc định: chỉ Thu nhập ròng Vợ/Chồng + Chi tiêu gia đình (không lộ Total Assets/Doanh thu/Phải trả)', (tester) async {
    await _pump(tester, base);
    // Vợ: 10.000.000 doanh thu − 4.000.000 chi phí KD. Chồng: 5.000.000 − 0.
    expect(_valueText(tester, 'summary_net_vo', '').data, '6.000.000 đ');
    expect(_valueText(tester, 'summary_net_chong', '').data, '5.000.000 đ');
    // Chi tiêu gia đình: 120.000 + 5.000 + 300.000 + 200.000.
    expect(_valueText(tester, 'summary_household_spending', '').data, '625.000 đ');
    for (final hidden in ['Tổng tài sản', 'Tài sản ròng', 'Phải thu', 'Phải trả', 'Doanh thu']) {
      expect(find.text(hidden), findsNothing, reason: '"$hidden" không lộ ở Summary mặc định');
    }
  });

  testWidgets('Dòng giao dịch: ngày · Vợ/Chồng · Nhóm · Danh mục · số tiền · ghi chú · trạng thái', (tester) async {
    await _pump(tester, base);
    final d = '${_today.day.toString().padLeft(2, '0')}/${_today.month.toString().padLeft(2, '0')}';
    expect(find.text(d), findsWidgets, reason: 'ngày hiện ở từng dòng');
    expect(find.text('Vợ · Chi tiêu · Sinh hoạt'), findsOneWidget);
    expect(find.text('Đi chợ'), findsOneWidget);
    expect(find.text('- 120.000 đ'), findsOneWidget);
    expect(find.text('Chồng · Doanh thu · Lập trình'), findsOneWidget);
    expect(find.text('+ 5.000.000 đ'), findsOneWidget);
    expect(find.text('Chồng · Chi tiêu · CĐ'), findsOneWidget);
    expect(find.text('CCB'), findsOneWidget, reason: 'trạng thái hiện trên dòng');
    expect(find.text('Vợ · Chi phí kinh doanh · Lương nhân viên'), findsOneWidget);
    for (final leak in ['business_expense', 'excludeFromTotals', 'memberAvailable', 'group_key']) {
      expect(find.textContaining(leak), findsNothing);
    }
  });

  testWidgets('Đầu kết quả: số giao dịch, khoảng ngày, Thu/Chi (không còn Vào/Ra)', (tester) async {
    await _pump(tester, base);
    final h = _header(tester);
    expect(h, contains('9 giao dịch'));
    expect(h, contains('Thu 17.450.000 đ'));
    expect(h, contains('Chi 4.625.000 đ'));
    expect(h, isNot(contains('Vào')));
    expect(h, isNot(contains('Ra ')));
    expect(h, contains('Tháng ${_now.month}/${_now.year}'), reason: 'thời gian đang xem');
  });

  testWidgets('Chip thành viên: Tất cả / Vợ / Chồng → danh sách + tổng cập nhật; bấm liên tiếp không lệch trạng thái', (tester) async {
    await _pump(tester, base);
    await _tapKey(tester, 'summary_member_vo');
    expect(_header(tester), contains('5 giao dịch'));
    expect(find.text('Đi chợ'), findsOneWidget);
    expect(find.text('gửi xe'), findsNothing);

    await _tapKey(tester, 'summary_member_chong');
    expect(_header(tester), contains('4 giao dịch'));
    expect(find.text('gửi xe'), findsOneWidget);
    expect(find.text('Đi chợ'), findsNothing);

    for (final k in ['vo', 'chong', 'vo', 'all', 'chong', 'vo']) {
      await tester.tap(find.byKey(Key('summary_member_$k')));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(_header(tester), contains('5 giao dịch'), reason: 'trạng thái cuối = Vợ');

    await _tapKey(tester, 'summary_member_all');
    expect(_header(tester), contains('9 giao dịch'));
  });

  testWidgets('Nhiều danh mục (OR): Sinh hoạt + Lương nhân viên; bộ chọn nhóm theo Nhóm chính; bỏ riêng bằng chip', (tester) async {
    await _pump(tester, base);
    await _openPicker(tester, 'summary_pick_categories');
    for (final g in ['DOANH THU', 'KHOẢN THU KHÁC', 'CHI TIÊU', 'CHI PHÍ KINH DOANH', 'CHUYỂN']) {
      expect(find.text(g), findsOneWidget, reason: 'nhóm $g chỉ để nhìn cho dễ');
    }
    await _toggleOption(tester, 'sinh_hoat');
    expect(_header(tester), contains('2 giao dịch'));
    await _toggleOption(tester, 'luong_gv');
    expect(_header(tester), contains('3 giao dịch'), reason: 'OR trong cùng chiều');
    await _closeSheet(tester);

    expect(find.byKey(const Key('summary_chip_categories')), findsOneWidget);
    expect(find.text('Danh mục: 2'), findsOneWidget);
    expect(find.text('Bộ lọc (1)'), findsOneWidget);

    // Bỏ RIÊNG bộ lọc danh mục qua chip, không đụng chiều khác.
    await _tapKey(tester, 'summary_member_vo');
    await tester.tap(find.descendant(of: find.byKey(const Key('summary_chip_categories')), matching: find.byIcon(Icons.clear)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('summary_chip_categories')), findsNothing);
    expect(_header(tester), contains('5 giao dịch'), reason: 'Vợ vẫn giữ nguyên');
  });

  testWidgets('Trạng thái đa chọn ĐỘC LẬP với danh mục (chọn trạng thái trước); "Không có trạng thái" = OR với trạng thái khác', (tester) async {
    await _pump(tester, base);
    await _pickStatuses(tester, ['st_gui']);
    expect(_header(tester), contains('1 giao dịch'));
    expect(find.text('đã gửi'), findsOneWidget);
    expect(find.byKey(const Key('summary_chip_categories')), findsNothing, reason: 'không cần chọn danh mục');

    await _pickStatuses(tester, [], none: true);
    // 1 (ĐG) + 7 giao dịch không trạng thái = 8; CCB còn lại bị loại.
    expect(_header(tester), contains('8 giao dịch'));
    expect(find.text('CĐ tháng này'), findsNothing);
    expect(find.text('Trạng thái: 2'), findsOneWidget);
  });

  testWidgets('Trạng thái đã ẩn còn lịch sử → vẫn lọc được, nhãn kèm tên danh mục; không lịch sử thì không hiện', (tester) async {
    await _pump(tester, [
      _out('cho_di', 70000, statusId: 'st_cu', note: 'lịch sử cũ'),
      _out('cho_di', 1000, statusId: 'st_chua'),
    ]);
    await _openPicker(tester, 'summary_pick_statuses');
    expect(find.text('Cũ (đã ẩn) · CĐ'), findsOneWidget);
    expect(find.text('CCB · CĐ'), findsOneWidget);
    await _toggleOption(tester, 'st_cu');
    expect(_header(tester), contains('1 giao dịch'));
    expect(find.text('lịch sử cũ'), findsOneWidget);
  });

  testWidgets('Giao rỗng (Sinh hoạt + trạng thái ĐG): 0 kết quả, bộ lọc giữ nguyên, có [Xóa bộ lọc]', (tester) async {
    await _pump(tester, base);
    await _pickCategories(tester, ['sinh_hoat']);
    await _pickStatuses(tester, ['st_gui']);
    expect(find.text('Không tìm thấy giao dịch'), findsOneWidget);
    expect(_header(tester), contains('0 giao dịch'));
    expect(find.text('Danh mục: 1'), findsOneWidget, reason: 'không tự bỏ/đổi lựa chọn');
    expect(find.text('Trạng thái: 1'), findsOneWidget);
    expect(find.byKey(const Key('summary_empty_clear')), findsOneWidget);
  });

  testWidgets('Danh mục ngừng: chỉ hiện trong bộ chọn khi còn giao dịch; nhãn "(đã ngừng)"', (tester) async {
    final cats = [
      ..._cats,
      Category(id: 'cu_co_gd', name: 'Chi Phí Vận Hành', color: Colors.grey, type: TransactionType.expense, isActive: false),
      Category(id: 'cu_khong_gd', name: 'Danh mục bỏ', color: Colors.grey, type: TransactionType.expense, isActive: false),
    ];
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionsStreamProvider.overrideWith((ref) => Stream.value([_out('cu_co_gd', 5000, note: 'cũ')])),
          categoriesStreamProvider.overrideWith((ref) => Stream.value(cats)),
          obligationsStreamProvider.overrideWith((ref) => Stream.value(const [])),
          savingsAssetTypesStreamProvider.overrideWith((ref) => Stream.value(DefaultSavingsAssetTypes.all)),
          counterpartiesStreamProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MaterialApp(home: Scaffold(body: SummaryScreen())),
      ),
    );
    await tester.pumpAndSettle();
    await _openPicker(tester, 'summary_pick_categories');
    expect(find.text('Chi Phí Vận Hành (đã ngừng)'), findsOneWidget);
    expect(find.byKey(const Key('multi_cu_khong_gd')), findsNothing);
  });

  testWidgets('Bố cục: tiêu đề "Giao dịch" → khối tổng kết (N giao dịch · kỳ, Thu/Chi) → dòng kỳ ‹ Tháng › → hàng chip Ngày/Tháng/Năm/Tất cả → Vợ/Chồng', (tester) async {
    await _pump(tester, base);
    double top(String key) => tester.getTopLeft(find.byKey(Key(key))).dy;
    final title = tester.getTopLeft(find.text('Giao dịch').first).dy;
    expect(top('summary_result_header') > title, isTrue, reason: 'tổng kết nằm ngay dưới tiêu đề');
    expect(top('summary_time_label') > top('summary_result_header'), isTrue);
    expect(top('summary_time_prev') < top('summary_time_day'), isTrue, reason: 'dòng ‹ kỳ › nằm TRÊN hàng chip thời gian');
    expect(top('summary_time_label') < top('summary_time_month'), isTrue);
    expect(top('summary_time_day') < top('summary_member_all'), isTrue);
    // Khối tổng kết: số giao dịch + kỳ + Thu / Chi tách riêng.
    final header = find.byKey(const Key('summary_result_header'));
    expect(find.descendant(of: header, matching: find.text('9 giao dịch')), findsOneWidget);
    expect(find.byKey(const Key('summary_result_inflow')), findsOneWidget);
    expect(find.byKey(const Key('summary_result_outflow')), findsOneWidget);
  });

  testWidgets('Không còn lọc theo số tiền (chỉ còn SẮP XẾP theo số tiền)', (tester) async {
    await _pump(tester, base);
    await _openFilters(tester);
    expect(find.byKey(const Key('summary_amount_min')), findsNothing);
    expect(find.byKey(const Key('summary_amount_max')), findsNothing);
    expect(find.text('Số tiền'), findsNothing, reason: 'không có nhãn lọc "Số tiền"');
    expect(find.byKey(const Key('summary_sort_button')), findsOneWidget);
  });

  testWidgets('Tổng quan theo KỲ THỜI GIAN đang chọn (tháng / năm / ngày / tất cả), không theo bộ lọc Danh mục/Trạng thái', (tester) async {
    final lastYear = DateTime(_now.year - 1, 6, 10);
    await _pump(tester, [
      ...base,
      _in('hoc_phi', 1000000, to: 'vo', note: 'năm ngoái', date: lastYear),
    ]);
    // Tháng hiện tại (mặc định): Vợ 10.000.000 − 4.000.000 = 6.000.000; Chồng 5.000.000.
    expect(_valueText(tester, 'summary_net_vo', '').data, '6.000.000 đ');
    expect(find.text('Tổng quan · Tháng ${_now.month}/${_now.year}'), findsOneWidget);

    // Năm hiện tại: vẫn như tháng (dữ liệu mẫu chỉ trong tháng này), KHÔNG cộng doanh thu năm ngoái.
    await _tapKey(tester, 'summary_time_year');
    expect(find.text('Tổng quan · Năm ${_now.year}'), findsOneWidget);
    expect(_valueText(tester, 'summary_net_vo', '').data, '6.000.000 đ');

    // Lùi 1 năm: chỉ còn doanh thu năm ngoái của Vợ.
    await _tapKey(tester, 'summary_time_prev');
    expect(_valueText(tester, 'summary_net_vo', '').data, '1.000.000 đ');
    expect(_valueText(tester, 'summary_net_chong', '').data, '0 đ');
    expect(_valueText(tester, 'summary_household_spending', '').data, '0 đ');

    // Tất cả thời gian: cộng mọi kỳ.
    await _tapKey(tester, 'summary_time_all');
    expect(find.text('Tổng quan · Mọi thời gian'), findsOneWidget);
    expect(_valueText(tester, 'summary_net_vo', '').data, '7.000.000 đ');
    expect(_valueText(tester, 'summary_household_spending', '').data, '625.000 đ');

    // Bộ lọc Danh mục KHÔNG đổi số tổng quan (chỉ đổi tổng của Explorer).
    await _pickCategories(tester, ['sinh_hoat']);
    expect(_valueText(tester, 'summary_net_vo', '').data, '7.000.000 đ');
    expect(_header(tester), contains('2 giao dịch'));
  });

  testWidgets('Hàng chip thời gian không bị cắt: cả 4 kiểu (Ngày/Tháng/Năm/Tất cả) đều nằm trong màn hình', (tester) async {
    await _pump(tester, base);
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    for (final k in ['day', 'month', 'year', 'all']) {
      final rect = tester.getRect(find.byKey(Key('summary_time_$k')));
      expect(rect.left >= 0 && rect.right <= width, isTrue, reason: 'chip $k nằm trọn trong màn hình (${rect.left}..${rect.right} / $width)');
    }
    // Ở bề rộng điện thoại thật (Pixel 7a ≈ 411dp) vẫn thấy hết nhờ xuống dòng.
    tester.view.physicalSize = const Size(411, 3200);
    await tester.pumpAndSettle();
    tester.takeException(); // tràn của hàng khác do font test rộng — không thuộc phạm vi kiểm tra này.
    for (final k in ['day', 'month', 'year', 'all']) {
      final rect = tester.getRect(find.byKey(Key('summary_time_$k')));
      expect(rect.left >= 0 && rect.right <= 411, isTrue, reason: 'chip $k (411dp): ${rect.left}..${rect.right}');
    }
  });

  group('Sắp xếp 2 tầng: Ngày rồi Số tiền (áp dụng bằng OK)', () {
    // 19/09: 50.000, 800.000 — 20/09: 20.000, 100.000, 600.000 (cùng tháng hiện tại).
    List<Transaction> data() => [
      _out('sinh_hoat', 50000, id: 'd19-50', date: DateTime(_today.year, _today.month, 19, 9)),
      _out('sinh_hoat', 800000, id: 'd19-800', date: DateTime(_today.year, _today.month, 19, 15)),
      _out('sinh_hoat', 20000, id: 'd20-20', date: DateTime(_today.year, _today.month, 20, 8)),
      _out('sinh_hoat', 100000, id: 'd20-100', date: DateTime(_today.year, _today.month, 20, 12)),
      _out('sinh_hoat', 600000, id: 'd20-600', date: DateTime(_today.year, _today.month, 20, 18)),
    ];

    List<String> ids(WidgetTester tester) => [
      for (final w in tester.widgetList(find.byWidgetPredicate((w) {
        final k = w.key;
        return k is ValueKey<String> && (k.value.startsWith('d19-') || k.value.startsWith('d20-'));
      })))
        (w.key! as ValueKey<String>).value,
    ];

    Future<void> openSort(WidgetTester tester) => _tapKey(tester, 'summary_sort_button');
    bool showsArrow(String name) => find.byKey(Key(name)).evaluate().length == 1;

    testWidgets('Mặc định Ngày ↓ · Số tiền ↓; nhãn nút phản ánh; sheet có đúng 2 dòng, MỖI dòng ĐÚNG 1 mũi tên', (tester) async {
      await _pump(tester, data());
      expect(find.text('Ngày ↓ · Số tiền ↓'), findsOneWidget);
      expect(ids(tester), ['d20-600', 'd20-100', 'd20-20', 'd19-800', 'd19-50']);

      await openSort(tester);
      expect(find.byKey(const Key('sort_date_row')), findsOneWidget);
      expect(find.byKey(const Key('sort_amount_row')), findsOneWidget);
      expect(find.byKey(const Key('sort_cancel')), findsOneWidget);
      expect(find.byKey(const Key('sort_ok')), findsOneWidget);
      expect(showsArrow('sort_date_down'), isTrue);
      expect(showsArrow('sort_date_up'), isFalse);
      expect(showsArrow('sort_amount_down'), isTrue);
      expect(showsArrow('sort_amount_up'), isFalse);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsNWidgets(2));
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
      expect(find.text('Rồi theo'), findsNothing);
      expect(find.text('Danh mục'), findsNothing);
    });

    testWidgets('Chạm dòng đảo ↑↔↓ NGAY trong sheet nhưng danh sách CHƯA đổi cho tới khi OK', (tester) async {
      await _pump(tester, data());
      await openSort(tester);
      await tester.tap(find.byKey(const Key('sort_date_row')));
      await tester.pumpAndSettle();
      expect(showsArrow('sort_date_up'), isTrue);
      expect(showsArrow('sort_date_down'), isFalse);
      await tester.tap(find.byKey(const Key('sort_date_row')));
      await tester.pumpAndSettle();
      expect(showsArrow('sort_date_down'), isTrue);
      await tester.tap(find.byKey(const Key('sort_amount_row')));
      await tester.pumpAndSettle();
      expect(showsArrow('sort_amount_up'), isTrue);
      expect(showsArrow('sort_amount_down'), isFalse);
      expect(find.text('Ngày ↓ · Số tiền ↓'), findsOneWidget);
      expect(ids(tester), ['d20-600', 'd20-100', 'd20-20', 'd19-800', 'd19-50']);
    });

    Future<void> applyCombo(WidgetTester tester, {required bool dateUp, required bool amountUp}) async {
      await openSort(tester);
      if (showsArrow('sort_date_up') != dateUp) await tester.tap(find.byKey(const Key('sort_date_row')));
      await tester.pumpAndSettle();
      if (showsArrow('sort_amount_up') != amountUp) await tester.tap(find.byKey(const Key('sort_amount_row')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sort_ok')));
      await tester.pumpAndSettle();
    }

    testWidgets('4 tổ hợp áp dụng bằng OK cho đúng thứ tự (A–D) và nhãn nút', (tester) async {
      await _pump(tester, data());
      await applyCombo(tester, dateUp: false, amountUp: false);
      expect(ids(tester), ['d20-600', 'd20-100', 'd20-20', 'd19-800', 'd19-50']);
      await applyCombo(tester, dateUp: false, amountUp: true);
      expect(find.text('Ngày ↓ · Số tiền ↑'), findsOneWidget);
      expect(ids(tester), ['d20-20', 'd20-100', 'd20-600', 'd19-50', 'd19-800']);
      await applyCombo(tester, dateUp: true, amountUp: false);
      expect(find.text('Ngày ↑ · Số tiền ↓'), findsOneWidget);
      expect(ids(tester), ['d19-800', 'd19-50', 'd20-600', 'd20-100', 'd20-20']);
      await applyCombo(tester, dateUp: true, amountUp: true);
      expect(find.text('Ngày ↑ · Số tiền ↑'), findsOneWidget);
      expect(ids(tester), ['d19-50', 'd19-800', 'd20-20', 'd20-100', 'd20-600']);
    });

    testWidgets('Hủy / Back bỏ thay đổi đang chờ; mở lại thấy cấu hình ĐÃ ÁP DỤNG (không reset); OK mới áp dụng', (tester) async {
      await _pump(tester, data());
      await applyCombo(tester, dateUp: false, amountUp: true);
      final applied = ['d20-20', 'd20-100', 'd20-600', 'd19-50', 'd19-800'];
      expect(ids(tester), applied);

      await openSort(tester);
      await tester.tap(find.byKey(const Key('sort_date_row')));
      await tester.tap(find.byKey(const Key('sort_amount_row')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sort_cancel')));
      await tester.pumpAndSettle();
      expect(ids(tester), applied);
      expect(find.text('Ngày ↓ · Số tiền ↑'), findsOneWidget);

      await openSort(tester);
      expect(showsArrow('sort_date_down'), isTrue);
      expect(showsArrow('sort_amount_up'), isTrue);

      await tester.tap(find.byKey(const Key('sort_date_row')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute(); // Back hệ thống
      await tester.pumpAndSettle();
      expect(ids(tester), applied);
      await openSort(tester);
      expect(showsArrow('sort_date_down'), isTrue);
      expect(showsArrow('sort_amount_up'), isTrue);

      await tester.tap(find.byKey(const Key('sort_date_row')));
      await tester.tap(find.byKey(const Key('sort_amount_row')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sort_ok')));
      await tester.pumpAndSettle();
      // Từ (Ngày ↓, Số tiền ↑) đảo cả hai → (Ngày ↑, Số tiền ↓).
      expect(ids(tester), ['d19-800', 'd19-50', 'd20-600', 'd20-100', 'd20-20']);
    });

    testWidgets('Màn hẹp: nhãn sắp xếp dài + "Xóa bộ lọc" cùng hiện KHÔNG làm tràn hàng', (tester) async {
      await _pump(tester, data());
      await applyCombo(tester, dateUp: true, amountUp: false);
      expect(find.byKey(const Key('summary_clear_filters')), findsOneWidget);
      tester.view.physicalSize = const Size(411, 3200); // Pixel 7a ≈ 411dp
      await tester.pumpAndSettle();
      tester.takeException(); // font test rộng hơn font thật — chỉ kiểm bằng vị trí bên dưới.
      final sort = tester.getRect(find.byKey(const Key('summary_sort_button')));
      final clear = tester.getRect(find.byKey(const Key('summary_clear_filters')));
      final filter = tester.getRect(find.byKey(const Key('summary_filter_toggle')));
      expect(filter.right <= sort.left + 0.5, isTrue, reason: 'Bộ lọc không chồng nhãn sắp xếp');
      expect(sort.right <= clear.left + 0.5, isTrue, reason: 'nhãn sắp xếp co lại, không chồng "Xóa bộ lọc"');
      expect(clear.right <= 411.5, isTrue, reason: '"Xóa bộ lọc" nằm trọn trong màn hình (${clear.right})');
    });

    testWidgets('Sắp xếp không đổi số dòng/tổng Thu-Chi; sort còn nguyên sau khi đổi bộ lọc', (tester) async {
      await _pump(tester, data());
      final before = _header(tester);
      await applyCombo(tester, dateUp: true, amountUp: true);
      expect(_header(tester), before, reason: 'chỉ đổi thứ tự, không đổi số dòng/tổng');
      await _tapKey(tester, 'summary_member_vo');
      expect(ids(tester), ['d19-50', 'd19-800', 'd20-20', 'd20-100', 'd20-600'], reason: 'sort giữ nguyên khi đổi bộ lọc');
    });
  });

  testWidgets('Sửa/xóa khi đang lọc: dòng không còn khớp biến mất ngay, bộ lọc giữ nguyên, tổng cập nhật', (tester) async {
    final ledger = [
      _out('sinh_hoat', 120000, id: 'a', from: 'vo', note: 'Đi chợ'),
      _out('sinh_hoat', 30000, id: 'b', from: 'vo', note: 'cà phê'),
      _out('luong_gv', 500000, id: 'c', from: 'vo', note: 'Lương'),
    ];
    final controller = StreamController<List<Transaction>>();
    addTearDown(controller.close);
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionsStreamProvider.overrideWith((ref) => controller.stream),
          categoriesStreamProvider.overrideWith((ref) => Stream.value(_cats)),
          obligationsStreamProvider.overrideWith((ref) => Stream.value(const [])),
          savingsAssetTypesStreamProvider.overrideWith((ref) => Stream.value(DefaultSavingsAssetTypes.all)),
          counterpartiesStreamProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MaterialApp(home: Scaffold(body: SummaryScreen())),
      ),
    );
    controller.add(ledger);
    await tester.pumpAndSettle();
    await _pickCategories(tester, ['sinh_hoat']);
    expect(_header(tester), contains('2 giao dịch'));
    expect(_header(tester), contains('Chi 150.000 đ'));

    // Sửa "a" sang danh mục khác (dòng mới thay dòng cũ) → không còn khớp bộ lọc Sinh hoạt.
    controller.add([
      _out('luong_gv', 120000, id: 'a2', from: 'vo', note: 'Đi chợ'),
      ledger[1],
      ledger[2],
    ]);
    await tester.pumpAndSettle();
    expect(_header(tester), contains('1 giao dịch'));
    expect(_header(tester), contains('Chi 30.000 đ'));
    expect(find.text('Đi chợ'), findsNothing);
    expect(find.text('Danh mục: 1'), findsOneWidget, reason: 'bộ lọc không bị reset');

    // Xóa "b" → hết dòng, bộ lọc vẫn còn.
    controller.add([ledger[2]]);
    await tester.pumpAndSettle();
    expect(_header(tester), contains('0 giao dịch'));
    expect(find.text('Không tìm thấy giao dịch'), findsOneWidget);
    expect(find.text('Danh mục: 1'), findsOneWidget);
  });

  testWidgets('Thời gian: Ngày / Tháng / Năm / Tất cả; bấm chip luôn về kỳ HIỆN TẠI; không còn "Khoảng ngày"', (tester) async {
    final lastMonth = DateTime(_now.year, _now.month - 1, 15);
    final lastYear = DateTime(_now.year - 1, 6, 10);
    await _pump(tester, [
      ...base,
      _out('sinh_hoat', 7000, note: 'tháng trước', date: lastMonth),
      _out('sinh_hoat', 9000, note: 'năm ngoái', date: lastYear),
    ]);
    expect(find.text('Khoảng ngày'), findsNothing);
    expect(find.byKey(const Key('summary_time_range')), findsNothing);
    expect(_header(tester), contains('9 giao dịch'), reason: 'Tháng hiện tại mặc định');
    expect(find.text('Tháng ${_now.month}/${_now.year}'), findsWidgets);

    await _tapKey(tester, 'summary_time_prev');
    expect(_header(tester), contains('1 giao dịch'));
    expect(find.text('tháng trước'), findsOneWidget);

    // Đang xem tháng trước → bấm "Tháng" quay về THÁNG NÀY (không giữ mốc cũ).
    await _tapKey(tester, 'summary_time_month');
    expect(find.text('Tháng ${_now.month}/${_now.year}'), findsWidgets);
    expect(_header(tester), contains('9 giao dịch'));

    // Đang xem năm ngoái → bấm "Năm" về NĂM NAY; bấm "Ngày" về HÔM NAY.
    await _tapKey(tester, 'summary_time_year');
    await _tapKey(tester, 'summary_time_prev');
    expect(find.text('Năm ${_now.year - 1}'), findsWidgets);
    expect(find.text('năm ngoái'), findsOneWidget);
    await _tapKey(tester, 'summary_time_year');
    expect(find.text('Năm ${_now.year}'), findsWidgets);
    expect(find.text('năm ngoái'), findsNothing);

    await _tapKey(tester, 'summary_time_prev');
    await _tapKey(tester, 'summary_time_day');
    final t = DateTime.now();
    final todayLabel = '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year}';
    expect(find.text(todayLabel), findsWidgets, reason: 'Ngày → HÔM NAY, không phải ngày 1/1');
    expect(_header(tester), contains('9 giao dịch'), reason: 'mọi giao dịch mẫu đều ghi hôm nay');

    await _tapKey(tester, 'summary_time_all');
    expect(_header(tester), contains('11 giao dịch'));
    expect(_header(tester), contains('Mọi thời gian'));
  });

  testWidgets('Chuyển hiện đời thường; khoản nhỏ 5.000đ vẫn nhìn thấy', (tester) async {
    await _pump(tester, [
      ...base,
      _move('chuyen_tien_thanh_vien', 500000, note: 'gửi chồng tiền chợ'),
      _move('tiet_kiem', 300000, to: 'ngan_hang', toKind: PoolKind.memberSavingsAsset, note: 'gửi tiết kiệm'),
    ]);
    expect(find.text('Vợ → Chồng'), findsOneWidget);
    expect(find.text('gửi chồng tiền chợ'), findsOneWidget);
    expect(find.text('Vợ · Tiết kiệm'), findsOneWidget);
    expect(find.text('- 5.000 đ'), findsOneWidget);
  });

  testWidgets('Dòng Tiết kiệm đời thường: Thêm vào / Rút từ / Tiết kiệm · A → B (không lộ enum, id, pool)', (tester) async {
    Transaction sv(TransferKind kind, PoolKind from, String fromRef, PoolKind to, String toRef, int amount) {
      _n++;
      return Transaction(
        id: 'sv$_n',
        type: TransactionType.transfer,
        transferKind: kind,
        categoryId: 'tiet_kiem',
        sourceKind: from,
        sourceRefId: fromRef,
        destinationKind: to,
        destinationRefId: toRef,
        amountMinor: amount,
        transactionDate: _today,
        createdAt: _today.add(Duration(seconds: _n)),
        clientTxId: 'c-sv-$_n',
      );
    }

    await _pump(tester, [
      ...base,
      sv(TransferKind.savingsTopup, PoolKind.memberAvailable, 'chong', PoolKind.memberSavingsAsset,
          savingsAssetRefId(SystemSavingsAssets.unallocatedId, FamilyMember.chong), 111000),
      sv(TransferKind.savingsWithdraw, PoolKind.memberSavingsAsset, savingsAssetRefId('savings_gold', FamilyMember.vo),
          PoolKind.memberAvailable, 'vo', 222000),
      sv(TransferKind.savingsConvert, PoolKind.memberSavingsAsset, savingsAssetRefId('savings_gold', FamilyMember.vo),
          PoolKind.memberSavingsAsset, savingsAssetRefId('savings_bank', FamilyMember.vo), 333000),
    ]);
    expect(find.text('Chồng · Thêm vào tiết kiệm'), findsOneWidget);
    expect(find.text('Vợ · Rút từ tiết kiệm · Vàng'), findsOneWidget);
    expect(find.text('Vợ · Tiết kiệm · Vàng → Gửi ngân hàng'), findsOneWidget);
    for (final leak in ['savingsTopup', 'savingsConvert', 'savings_', '|', 'memberSavingsAsset']) {
      expect(find.textContaining(leak), findsNothing, reason: leak);
    }
  });

  testWidgets('Lọc theo Vợ: giao dịch Tiết kiệm của Vợ hiện, của Chồng ẩn (lọc theo thành viên vẫn đúng)', (tester) async {
    _n++;
    Transaction topupFor(String m) => Transaction(
      id: 'tp$m$_n',
      type: TransactionType.transfer,
      transferKind: TransferKind.savingsTopup,
      categoryId: 'tiet_kiem',
      sourceKind: PoolKind.memberAvailable,
      sourceRefId: m,
      destinationKind: PoolKind.memberSavingsAsset,
      destinationRefId: savingsAssetRefId(SystemSavingsAssets.unallocatedId, m == 'vo' ? FamilyMember.vo : FamilyMember.chong),
      amountMinor: m == 'vo' ? 123000 : 456000,
      transactionDate: _today,
      createdAt: _today,
      clientTxId: 'c-tp-$m-$_n',
    );
    await _pump(tester, [topupFor('vo'), topupFor('chong')]);
    await _tapKey(tester, 'summary_member_vo');
    expect(find.text('Vợ · Thêm vào tiết kiệm'), findsOneWidget);
    expect(find.text('Chồng · Thêm vào tiết kiệm'), findsNothing);
  });

  testWidgets('Có ghi chú / không ghi chú', (tester) async {
    await _pump(tester, [_out('sinh_hoat', 10000, note: ''), _out('sinh_hoat', 20000, note: 'có ghi chú')]);
    expect(find.text('có ghi chú'), findsOneWidget);
    expect(find.text('- 10.000 đ'), findsOneWidget);
    expect(_rowCount(tester), 2);
  });

  testWidgets('Lịch sử Vay/Hoàn tiền cũ (tính năng ẩn): hiển thị an toàn, tìm/lọc không crash', (tester) async {
    final buy = _out('sinh_hoat', 2000000, id: 'buy', note: 'mua quạt');
    await _pump(tester, [
      buy,
      _in('hoan_tien_thu_hoi', 450000, recoveryOf: 'buy', note: 'bán lại quạt'),
      _in('vay_no', 1000000, obligation: 'ob-1', note: 'vay tạm'),
      _move('cho_vay', 300000, to: 'ob-2', toKind: PoolKind.receivable, note: 'cho vay'),
    ]);
    expect(tester.takeException(), isNull);
    expect(_header(tester), contains('4 giao dịch'));
    expect(find.textContaining('Hoàn tiền / Thu hồi'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('summary_search')), 'quạt');
    await tester.pumpAndSettle();
    expect(_header(tester), contains('2 giao dịch'));
    await _openPicker(tester, 'summary_pick_categories');
    await _toggleOption(tester, 'hoc_phi');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Chạm 1 dòng → mở đúng chi tiết giao dịch', (tester) async {
    await _pump(tester, [_out('sinh_hoat', 120000, note: 'Đi chợ', id: 'tx-open')]);
    await _tapKey(tester, 'summary_member_vo');
    await tester.tap(find.text('Đi chợ'));
    await tester.pumpAndSettle();
    final detail = tester.widget<TransactionDetailScreen>(find.byType(TransactionDetailScreen));
    expect(detail.transactionId, 'tx-open');

    // Back → quay về Summary, bộ lọc (Vợ) vẫn còn nguyên.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(TransactionDetailScreen), findsNothing);
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('summary_member_vo'))).selected, isTrue);
  });

  testWidgets('Sắp xếp đã áp dụng còn nguyên sau Chi tiết → Back', (tester) async {
    await _pump(tester, [
      _out('sinh_hoat', 120000, note: 'Đi chợ', id: 'tx-a', date: DateTime(_today.year, _today.month, 5, 9)),
      _out('sinh_hoat', 30000, note: 'Cà phê', id: 'tx-b', date: DateTime(_today.year, _today.month, 5, 10)),
    ]);
    await _tapKey(tester, 'summary_sort_button');
    await tester.tap(find.byKey(const Key('sort_date_row')));
    await tester.tap(find.byKey(const Key('sort_amount_row')));
    await tester.tap(find.byKey(const Key('sort_ok')));
    await tester.pumpAndSettle();
    expect(find.text('Ngày ↑ · Số tiền ↑'), findsOneWidget);

    await tester.tap(find.text('Đi chợ'));
    await tester.pumpAndSettle();
    expect(find.byType(TransactionDetailScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Ngày ↑ · Số tiền ↑'), findsOneWidget);
  });

  testWidgets('~1.800 giao dịch: mở, đổi member/nhóm/danh mục/tìm/xoá, cuộn — không lỗi', (tester) async {
    final big = <Transaction>[];
    for (var i = 0; i < 1800; i++) {
      final d = DateTime(_now.year, _now.month, 1 + (i % 28));
      if (i % 3 == 0) {
        big.add(_in(i % 2 == 0 ? 'hoc_phi' : 'thu_khac', 1000 + i, to: i % 2 == 0 ? 'vo' : 'chong', date: d, note: 'thu $i'));
      } else {
        big.add(_out(i % 5 == 0 ? 'luong_gv' : 'sinh_hoat', 1000 + i, from: i % 2 == 0 ? 'vo' : 'chong', date: d, note: i % 7 == 0 ? 'đi chợ $i' : 'chi $i'));
      }
    }
    final sw = Stopwatch()..start();
    await _pump(tester, big);
    expect(_header(tester), contains('1800 giao dịch'));

    await _tapKey(tester, 'summary_member_vo');
    await tester.enterText(find.byKey(const Key('summary_search')), 'chợ');
    await tester.pumpAndSettle();
    await _pickCategories(tester, ['sinh_hoat', 'luong_gv']);
    expect(_header(tester), isNot(contains('1800 giao dịch')));
    await _tapKey(tester, 'summary_sort_button');
    await tester.tap(find.byKey(const Key('sort_amount_row')));
    await tester.tap(find.byKey(const Key('sort_ok')));
    await tester.pumpAndSettle();

    await tester.drag(_scrollView(), const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(_rowCount(tester), greaterThan(0), reason: 'cuộn xuống vẫn có dòng');
    await tester.drag(_scrollView(), const Offset(0, 4000));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'summary_clear_filters');
    // Khối tổng kết nằm phía trên (ngay dưới tiêu đề "Giao dịch") — cuộn về đầu để nó được dựng.
    await tester.drag(_scrollView(), const Offset(0, 4000));
    await tester.pumpAndSettle();
    expect(_header(tester), contains('1800 giao dịch'));
    sw.stop();
    expect(tester.takeException(), isNull);
    // ListView lười: số dòng đang dựng ≪ 1800.
    expect(_rowCount(tester), lessThan(200));
    expect(sw.elapsedMilliseconds, lessThan(20000));
  });
}
