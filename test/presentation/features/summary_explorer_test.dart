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
  statsEnabled: statuses.isNotEmpty,
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
    expect(h, contains(' – '), reason: 'khoảng ngày tháng này');
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

  testWidgets('Nhóm → Danh mục: chọn nhóm lọc danh sách danh mục; đổi nhóm xoá danh mục cũ không hợp lệ', (tester) async {
    await _pump(tester, base);
    await _openFilters(tester);
    await _tapKey(tester, 'summary_group_spending');
    expect(_header(tester), contains('4 giao dịch'));

    // Chọn danh mục Sinh hoạt qua dropdown.
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    expect(find.text('Lương nhân viên'), findsNothing, reason: 'không thuộc nhóm Chi tiêu');
    await tester.tap(find.text('Sinh hoạt').last);
    await tester.pumpAndSettle();
    expect(_header(tester), contains('2 giao dịch'));

    // Đổi sang nhóm khác → danh mục Sinh hoạt bị xoá.
    await _tapKey(tester, 'summary_group_businessExpense');
    expect(_header(tester), contains('1 giao dịch'));
    expect(find.text('Lương cô Lam'), findsOneWidget);
    expect(find.text('Bộ lọc (1)'), findsOneWidget, reason: 'chỉ còn nhóm, danh mục đã bị xoá');
  });

  testWidgets('Danh mục CĐ → hiện trạng thái (kể cả đã ẩn); chọn trạng thái lọc danh sách; đổi danh mục không trạng thái → xoá', (tester) async {
    await _pump(tester, base);
    await _openFilters(tester);
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CĐ').last);
    await tester.pumpAndSettle();
    expect(_header(tester), contains('2 giao dịch'));

    expect(find.byKey(const Key('summary_status_st_chua')), findsOneWidget);
    expect(find.byKey(const Key('summary_status_st_gui')), findsOneWidget);
    expect(find.text('Cũ (đã ẩn)'), findsNothing, reason: 'bước đã ẩn KHÔNG dùng → không làm rối bộ lọc');

    await _tapKey(tester, 'summary_status_st_gui');
    expect(_header(tester), contains('1 giao dịch'));
    expect(find.text('đã gửi'), findsOneWidget);
    expect(find.text('CĐ tháng này'), findsNothing);

    // Đổi sang danh mục không có trạng thái → nhóm trạng thái biến mất và điều kiện trạng thái bị xoá.
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sinh hoạt').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('summary_status_st_gui')), findsNothing);
    expect(_header(tester), contains('2 giao dịch'));
  });

  testWidgets('Bước trạng thái đã ẩn nhưng còn lịch sử → vẫn lọc được', (tester) async {
    await _pump(tester, [
      _out('cho_di', 70000, statusId: 'st_cu', note: 'lịch sử cũ'),
      _out('cho_di', 1000, statusId: 'st_chua'),
    ]);
    await _openFilters(tester);
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CĐ').last);
    await tester.pumpAndSettle();
    expect(find.text('Cũ (đã ẩn)'), findsOneWidget);
    await _tapKey(tester, 'summary_status_st_cu');
    expect(_header(tester), contains('1 giao dịch'));
    expect(find.text('lịch sử cũ'), findsOneWidget);
  });

  testWidgets('Tìm ghi chú: gõ → cập nhật ngay, không phân biệt hoa/thường; xoá ô → trả về đủ', (tester) async {
    await _pump(tester, base);
    await tester.enterText(find.byKey(const Key('summary_search')), 'LƯƠNG');
    await tester.pumpAndSettle();
    expect(_header(tester), contains('1 giao dịch'));
    expect(find.text('Lương cô Lam'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('summary_search')), '  hp  ');
    await tester.pumpAndSettle();
    expect(_header(tester), contains('1 giao dịch'));

    await tester.tap(find.byKey(const Key('summary_search_clear')));
    await tester.pumpAndSettle();
    expect(_header(tester), contains('9 giao dịch'));
  });

  testWidgets('Kết hợp 3+ bộ lọc = giao (Vợ + Chi tiêu + Sinh hoạt + "chợ")', (tester) async {
    final ledger = [
      ...base,
      _out('sinh_hoat', 80000, from: 'chong', note: 'đi chợ'),
      _out('sinh_hoat', 60000, from: 'vo', note: 'cà phê'),
    ];
    await _pump(tester, ledger);
    await _tapKey(tester, 'summary_member_vo');
    await _openFilters(tester);
    await _tapKey(tester, 'summary_group_spending');
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sinh hoạt').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('summary_search')), 'chợ');
    await tester.pumpAndSettle();

    expect(_header(tester), contains('1 giao dịch'));
    expect(_header(tester), contains('Chi 120.000 đ'));
    expect(find.text('Đi chợ'), findsOneWidget);
  });

  testWidgets('Tìm Ghi chú không dấu ↔ có dấu qua ô tìm; Thu/Chi header đổi theo', (tester) async {
    final ledger = [
      _out('sinh_hoat', 120000, from: 'vo', note: 'Đi chợ'),
      _out('sinh_hoat', 70000, from: 'chong', note: 'di cho'),
      _out('sinh_hoat', 5000, from: 'vo', note: 'cà phê'),
    ];
    await _pump(tester, ledger);
    await tester.enterText(find.byKey(const Key('summary_search')), 'DI CHO');
    await tester.pumpAndSettle();
    expect(_header(tester), contains('2 giao dịch'));
    expect(_header(tester), contains('Chi 190.000 đ'));
    expect(find.text('Đi chợ'), findsOneWidget);
    expect(find.text('di cho'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('summary_search')), 'cà phê');
    await tester.pumpAndSettle();
    expect(_header(tester), contains('1 giao dịch'));
    await tester.enterText(find.byKey(const Key('summary_search')), 'ca phe');
    await tester.pumpAndSettle();
    expect(_header(tester), contains('1 giao dịch'));
    expect(find.text('cà phê'), findsOneWidget);
  });

  testWidgets('Empty state + Xóa bộ lọc: về đúng mặc định trong 1 thao tác', (tester) async {
    await _pump(tester, base);
    await _tapKey(tester, 'summary_member_vo');
    await tester.enterText(find.byKey(const Key('summary_search')), 'xyzabc');
    await tester.pumpAndSettle();
    expect(find.text('Không tìm thấy giao dịch'), findsOneWidget);
    expect(_header(tester), contains('0 giao dịch'));

    await tester.ensureVisible(find.byKey(const Key('summary_empty_clear')));
    await tester.tap(find.byKey(const Key('summary_empty_clear')));
    await tester.pumpAndSettle();
    expect(find.text('Không tìm thấy giao dịch'), findsNothing);
    expect(_header(tester), contains('9 giao dịch'));
    expect(tester.widget<TextField>(find.byKey(const Key('summary_search'))).controller!.text, isEmpty);
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('summary_member_all'))).selected, isTrue);
    expect(find.byKey(const Key('summary_clear_filters')), findsNothing, reason: 'đã ở mặc định');
  });

  testWidgets('Xóa bộ lọc (nút thường) xoá member/nhóm/danh mục/trạng thái/ghi chú/thời gian', (tester) async {
    await _pump(tester, base);
    await _tapKey(tester, 'summary_member_chong');
    await _tapKey(tester, 'summary_time_last_month');
    expect(_header(tester), contains('0 giao dịch'));
    expect(find.byKey(const Key('summary_clear_filters')), findsOneWidget);
    await _tapKey(tester, 'summary_clear_filters');
    expect(_header(tester), contains('9 giao dịch'));
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('summary_time_this_month'))).selected, isTrue);
  });

  testWidgets('Thời gian: Hôm nay / Tháng trước dựa trên transactionDate', (tester) async {
    final lastMonth = DateTime(_now.year, _now.month - 1, 15);
    await _pump(tester, [
      ...base,
      _out('sinh_hoat', 7000, note: 'tháng trước', date: lastMonth),
    ]);
    expect(_header(tester), contains('9 giao dịch'), reason: 'Tháng này mặc định');

    await _tapKey(tester, 'summary_time_last_month');
    expect(_header(tester), contains('1 giao dịch'));
    expect(find.text('tháng trước'), findsOneWidget);

    await _tapKey(tester, 'summary_time_today');
    expect(_header(tester), contains('9 giao dịch'), reason: 'mọi giao dịch mẫu đều ghi hôm nay');
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
    await _openFilters(tester);
    await _tapKey(tester, 'summary_group_revenue');
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
    await _openFilters(tester);
    await _tapKey(tester, 'summary_group_spending');
    expect(_header(tester), isNot(contains('1800 giao dịch')));

    await tester.drag(_scrollView(), const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(_rowCount(tester), greaterThan(0), reason: 'cuộn xuống vẫn có dòng');
    await tester.drag(_scrollView(), const Offset(0, 4000));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'summary_clear_filters');
    expect(_header(tester), contains('1800 giao dịch'));
    sw.stop();
    expect(tester.takeException(), isNull);
    // ListView lười: số dòng đang dựng ≪ 1800.
    expect(_rowCount(tester), lessThan(200));
    expect(sw.elapsedMilliseconds, lessThan(20000));
  });
}
