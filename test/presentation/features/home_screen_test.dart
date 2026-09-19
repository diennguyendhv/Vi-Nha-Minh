import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/constants/default_categories.dart';
import 'package:vi_nha_minh/core/constants/default_funds.dart';
import 'package:vi_nha_minh/core/constants/default_savings_asset_types.dart';
import 'package:vi_nha_minh/core/utils/formatters.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/family_member.dart';
import 'package:vi_nha_minh/domain/entities/fund.dart';
import 'package:vi_nha_minh/domain/entities/transfer_kind.dart';
import 'package:vi_nha_minh/domain/entities/obligation.dart';
import 'package:vi_nha_minh/domain/entities/obligation_direction.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/savings_asset_type.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/repositories/category_repository.dart';
import 'package:vi_nha_minh/domain/repositories/fund_repository.dart';
import 'package:vi_nha_minh/domain/repositories/obligation_repository.dart';
import 'package:vi_nha_minh/domain/repositories/savings_asset_type_repository.dart';
import 'package:vi_nha_minh/domain/repositories/transaction_repository.dart';
import 'package:vi_nha_minh/domain/usecases/compute_grouped_totals.dart';
import 'package:vi_nha_minh/domain/usecases/explore_transactions.dart';
import 'package:vi_nha_minh/presentation/features/add_transaction/add_transaction_sheet.dart';
import 'package:vi_nha_minh/presentation/features/fund/fund_detail_screen.dart';
import 'package:vi_nha_minh/presentation/features/home/home_screen.dart';
import 'package:vi_nha_minh/presentation/providers/app_state_providers.dart';
import 'package:vi_nha_minh/presentation/providers/category_providers.dart';
import 'package:vi_nha_minh/presentation/providers/fund_providers.dart';
import 'package:vi_nha_minh/presentation/providers/obligation_providers.dart';
import 'package:vi_nha_minh/presentation/providers/savings_asset_type_providers.dart';
import 'package:vi_nha_minh/presentation/providers/feature_providers.dart';
import 'package:vi_nha_minh/presentation/providers/transaction_providers.dart';

/// Widget test cho Trang chủ tối giản: vòng đời render, số hiển thị KHỚP đúng
/// nguồn sự thật (Net Income / Chi tiêu gia đình / pool của Engine / quỹ tiền
/// ăn), các chỉ số kế toán nâng cao KHÔNG hiện, và từng sự kiện chạm.
class _FakeTransactionRepository implements TransactionRepository {
  final _controller = StreamController<List<Transaction>>.broadcast();
  List<Transaction> _all = const [];
  Object? errorToEmit;

  void emit(List<Transaction> transactions) {
    _all = transactions;
    if (errorToEmit != null) {
      _controller.addError(errorToEmit!);
    } else {
      _controller.add(_all);
    }
  }

  @override
  Future<Transaction> addTransaction(Transaction transaction) async {
    _all = [..._all, transaction];
    _controller.add(_all);
    return transaction;
  }

  @override
  Stream<List<Transaction>> watchTransactions() => _controller.stream;

  @override
  Future<Transaction?> getTransactionById(String id) async => null;

  @override
  Future<Transaction?> getTransactionByClientTxId(String clientTxId) async => null;

  @override
  Future<void> reverseTransaction(String transactionId) async {}

  @override
  Future<void> updateTransaction(
    String transactionId, {
    int? amountMinor,
    String? categoryId,
    String? note,
    String? memberRefId,
    DateTime? transactionDate,
    String? statusId,
  }) async {}

  Future<void> dispose() => _controller.close();

  @override
  Future<({Transaction principal, Transaction? interest})> settleObligation({
    required String obligationId,
    required ObligationDirection direction,
    required String memberRefId,
    required int amountMinor,
    required DateTime transactionDate,
    String note = '',
    required String categoryId,
    required String interestCategoryId,
    required String principalId,
    required String principalClientTxId,
    required String interestId,
    required String interestClientTxId,
  }) => throw UnimplementedError();

  @override
  Future<void> reverseObligationSettlement(String anyLegTransactionId) =>
      throw UnimplementedError();

  @override
  Future<({Transaction principal, Transaction? interest})> correctObligationSettlement(
    String anyLegTransactionId, {
    required int newAmountMinor,
    required String categoryId,
    required String interestCategoryId,
    required String newPrincipalId,
    required String newPrincipalClientTxId,
    required String newInterestId,
    required String newInterestClientTxId,
  }) => throw UnimplementedError();
}

/// Phase 8.8 — Home giờ cũng watch `obligationsStreamProvider` (thẻ "Vay &
/// Cho vay"). Fake rỗng, tương tự `_StaticCategoryRepository`.
class _StaticObligationRepository implements ObligationRepository {
  @override
  Future<Transaction> createObligationWithOpeningTransaction(Obligation obligation, Transaction opening) =>
      throw UnimplementedError();
  @override
  Stream<List<Obligation>> watchObligations() => Stream.value(const []);
  @override
  Future<void> addObligation(Obligation obligation) async {}
  @override
  Future<void> updateObligation(Obligation obligation) async {}
}

class _StaticCategoryRepository implements CategoryRepository {
  _StaticCategoryRepository(this._categories);
  final List<Category> _categories;
  @override
  Stream<List<Category>> watchCategories() => Stream.value(_categories);
  @override
  Future<void> addCategory(Category category) async {}
  @override
  Future<void> updateCategory(Category category) async {}
  @override
  Future<void> softDeleteCategory(String categoryId) async {}

  @override
  Stream<Set<String>> watchDeletableCategoryIds() => Stream.value(const {});

  @override
  Future<void> deleteCategoryPermanently(String categoryId) async {}
}

class _StaticFundRepository implements FundRepository {
  _StaticFundRepository(this._funds);
  final List<Fund> _funds;
  @override
  Stream<List<Fund>> watchFunds() => Stream.value(_funds);
  @override
  Future<void> addFund(Fund fund) async {}
  @override
  Future<void> updateFund(Fund fund) async {}
  @override
  Future<void> softDeleteFund(String fundId) async {}
}

class _StaticSavingsAssetTypeRepository implements SavingsAssetTypeRepository {
  _StaticSavingsAssetTypeRepository(this._assetTypes);
  final List<SavingsAssetType> _assetTypes;
  @override
  Stream<List<SavingsAssetType>> watchAssetTypes() => Stream.value(_assetTypes);
  @override
  Future<void> addAssetType(SavingsAssetType assetType) async {}
  @override
  Future<void> updateAssetType(SavingsAssetType assetType) async {}
  @override
  Future<void> softDeleteAssetType(String assetTypeId) async {}
}

int _seq = 0;

Transaction _tx({
  required TransactionType type,
  required String categoryId,
  required PoolKind from,
  String? fromRef,
  required PoolKind to,
  String? toRef,
  required int amount,
  TransferKind? transferKind,
  String? obligationId,
  String? recoveryOf,
}) {
  _seq++;
  return Transaction(
    id: 'tx-$_seq',
    type: type,
    transferKind: transferKind,
    categoryId: categoryId,
    sourceKind: from,
    sourceRefId: fromRef,
    destinationKind: to,
    destinationRefId: toRef,
    amountMinor: amount,
    obligationId: obligationId,
    recoveryOfTxId: recoveryOf,
    transactionDate: DateTime.now(),
    createdAt: DateTime.now(),
    clientTxId: 'client-$_seq',
  );
}

Transaction _income(int amount, {String memberRefId = 'vo'}) => _tx(
  type: TransactionType.income,
  categoryId: DefaultCategories.thuNhap.id,
  from: PoolKind.external,
  to: PoolKind.memberAvailable,
  toRef: memberRefId,
  amount: amount,
);

Transaction _expense(int amount, {required String category, String member = 'vo'}) => _tx(
  type: TransactionType.expense,
  categoryId: category,
  from: PoolKind.memberAvailable,
  fromRef: member,
  to: PoolKind.external,
  amount: amount,
);

/// Ledger mẫu (tháng hiện tại): Vợ thu 5tr, chi phí KD 1tr, gửi tiết kiệm 2tr,
/// nạp quỹ tiền ăn 500k; Chồng thu 3tr, chi tiêu (Sinh hoạt) 300k.
List<Transaction> _sampleLedger() => [
  _income(5000000, memberRefId: 'vo'),
  _income(3000000, memberRefId: 'chong'),
  _expense(1000000, category: DefaultCategories.chiPhiKinhDoanh.id, member: 'vo'),
  _expense(300000, category: DefaultCategories.sinhHoat.id, member: 'chong'),
  _tx(
    type: TransactionType.transfer,
    transferKind: TransferKind.savingsTopup,
    categoryId: DefaultCategories.tietKiem.id,
    from: PoolKind.memberAvailable,
    fromRef: 'vo',
    to: PoolKind.memberSavingsAsset,
    toRef: savingsAssetRefId(DefaultSavingsAssetTypes.all.first.id, FamilyMember.vo),
    amount: 2000000,
  ),
  _tx(
    type: TransactionType.transfer,
    transferKind: TransferKind.fundTopup,
    categoryId: DefaultCategories.napQuy.id,
    from: PoolKind.memberAvailable,
    fromRef: 'vo',
    to: PoolKind.fund,
    toRef: DefaultFunds.anUongId,
    amount: 500000,
  ),
];

Future<void> _pumpHome(
  WidgetTester tester, {
  required _FakeTransactionRepository fakeRepo,
  List<Category>? categories,
  List<Fund>? funds,
  bool advancedFeatures = false,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        advancedFeaturesEnabledProvider.overrideWithValue(advancedFeatures),
        transactionRepositoryProvider.overrideWithValue(fakeRepo),
        categoryRepositoryProvider.overrideWithValue(
          _StaticCategoryRepository(categories ?? DefaultCategories.all),
        ),
        fundRepositoryProvider.overrideWithValue(
          _StaticFundRepository(funds ?? DefaultFunds.all),
        ),
        savingsAssetTypeRepositoryProvider.overrideWithValue(
          _StaticSavingsAssetTypeRepository(DefaultSavingsAssetTypes.all),
        ),
        obligationRepositoryProvider.overrideWithValue(_StaticObligationRepository()),
      ],
      child: const MaterialApp(home: Scaffold(body: HomeScreen())),
    ),
  );
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  late _FakeTransactionRepository fakeRepo;

  setUp(() {
    fakeRepo = _FakeTransactionRepository();
  });

  tearDown(() async {
    await fakeRepo.dispose();
  });

  Future<void> pumpWith(WidgetTester tester, List<Transaction> ledger,
      {List<Fund>? funds, bool advanced = false}) async {
    await _pumpHome(tester, fakeRepo: fakeRepo, funds: funds, advancedFeatures: advanced);
    fakeRepo.emit(ledger);
    await tester.pumpAndSettle();
  }

  testWidgets('Loading state — hiện CircularProgressIndicator trước khi stream emit', (tester) async {
    await _pumpHome(tester, fakeRepo: fakeRepo);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('Error state — hiện thông báo lỗi, không crash app', (tester) async {
    await _pumpHome(tester, fakeRepo: fakeRepo);
    fakeRepo.errorToEmit = Exception('lỗi mô phỏng');
    fakeRepo.emit(const []);
    await tester.pumpAndSettle();
    expect(find.textContaining('Lỗi tải dữ liệu'), findsOneWidget);
  });

  testWidgets('Empty ledger: đủ 8 câu trả lời, mọi số 0 đ, quỹ "Đã hết", không crash', (tester) async {
    await pumpWith(tester, const []);

    expect(tester.takeException(), isNull);
    for (final m in ['vo', 'chong']) {
      expect(_text(tester, 'home_income_$m'), '0 đ');
      expect(_text(tester, 'home_balance_$m'), '0 đ');
      expect(_text(tester, 'home_savings_$m'), '0 đ');
    }
    expect(_text(tester, 'home_spending_amount'), '0 đ');
    expect(_text(tester, 'home_food_fund_amount'), 'Đã hết');
    expect(find.text('Nạp quỹ'), findsOneWidget);
  });

  testWidgets('Số liệu: mỗi số khớp ĐÚNG nguồn sự thật (Net Income, pool Engine, Chi tiêu gia đình, quỹ)', (tester) async {
    final ledger = _sampleLedger();
    await pumpWith(tester, ledger);
    final categories = DefaultCategories.all;
    final month = DateTime(DateTime.now().year, DateTime.now().month);

    // Thu nhập tháng này = Doanh thu − Chi phí kinh doanh (KHÔNG trừ chi tiêu, KHÔNG cộng Khoản thu khác).
    expect(_text(tester, 'home_income_vo'), '4.000.000 đ');
    expect(_text(tester, 'home_income_chong'), '3.000.000 đ');
    expect(_text(tester, 'home_income_vo'),
        Formatters.amount(computeMemberNetIncome(FamilyMember.vo, ledger, categories, month: month)));

    // Số dư hiện tại = pool khả dụng của Engine: 5tr − 1tr (KD) − 2tr (gửi tiết kiệm) − 500k (nạp quỹ).
    expect(_text(tester, 'home_balance_vo'), '1.500.000 đ',
        reason: 'KHÔNG phải Thu nhập (4tr): Chuyển/Tiết kiệm/Quỹ đã rời khỏi số dư');
    expect(_text(tester, 'home_balance_chong'), '2.700.000 đ');
    expect(_text(tester, 'home_savings_vo'), '2.000.000 đ');
    expect(_text(tester, 'home_savings_chong'), '0 đ');

    // Chi tiêu gia đình = CHỈ nhóm Chi tiêu: không Chi phí KD (1tr), không Chuyển/Tiết kiệm/Quỹ.
    expect(_text(tester, 'home_spending_amount'), '300.000 đ');
    expect(_text(tester, 'home_spending_amount'),
        Formatters.amount(computeGroupedTotals(ledger, categories, month: month).spending));

    expect(_text(tester, 'home_food_fund_amount'), '500.000 đ');
    expect(find.text('Còn lại'), findsOneWidget);
  });

  testWidgets('Ẩn khỏi Trang chủ mặc định: tài sản/net worth/vay/thu hồi/doanh thu/chi phí KD/khoản thu khác/giao dịch gần đây', (tester) async {
    await pumpWith(tester, _sampleLedger());
    for (final hidden in [
      'TỔNG TÀI SẢN', 'Tổng tài sản', 'Tài sản ròng', 'Net Worth', 'Phải thu', 'Phải trả',
      'Vay & Cho vay', 'Thu hồi', 'Hoàn tiền', 'Doanh thu', 'Chi phí kinh doanh',
      'Khoản thu khác', 'Số dư khả dụng', 'Giao dịch gần đây', 'Thu tháng', 'Chi tháng',
    ]) {
      expect(find.textContaining(hidden), findsNothing, reason: hidden);
    }
  });

  testWidgets('Vay & Cho vay: ẩn mặc định, chỉ có lối tắt đơn giản khi bật tính năng nâng cao (không hiện số phải thu/phải trả)', (tester) async {
    await pumpWith(tester, const []);
    expect(find.text('Vay & Cho vay'), findsNothing);

    await pumpWith(tester, const [], advanced: true);
    expect(find.text('Vay & Cho vay'), findsOneWidget);
    expect(find.textContaining('Phải thu'), findsNothing);
    expect(find.textContaining('Phải trả'), findsNothing);
  });

  testWidgets('Lịch sử Vay / Hoàn tiền cũ không làm Home vỡ và không lọt vào Chi tiêu gia đình', (tester) async {
    await pumpWith(tester, [
      _expense(100000, category: 'dau_tu'),
      _tx(type: TransactionType.transfer, categoryId: 'cho_vay', from: PoolKind.memberAvailable, fromRef: 'vo',
          to: PoolKind.receivable, toRef: 'ob-1', amount: 100000, obligationId: 'ob-1'),
      _tx(type: TransactionType.income, categoryId: 'vay_no', from: PoolKind.external,
          to: PoolKind.memberAvailable, toRef: 'vo', amount: 100000, obligationId: 'ob-2'),
    ]);
    expect(tester.takeException(), isNull);
    expect(_text(tester, 'home_spending_amount'), '100.000 đ', reason: 'chỉ khoản Đầu tư (Chi tiêu)');
  });

  group('Quỹ tiền ăn — nhận diện bằng id ổn định, không bằng tên', () {
    testWidgets('Không có quỹ → không hiện thẻ', (tester) async {
      await pumpWith(tester, const [], funds: const []);
      expect(find.byKey(const Key('home_food_fund')), findsNothing);
    });

    testWidgets('Quỹ đã ngừng (isActive=false) → không hiện', (tester) async {
      await pumpWith(tester, const [], funds: [DefaultFunds.anUong.copyWith(isActive: false)]);
      expect(find.byKey(const Key('home_food_fund')), findsNothing);
    });

    testWidgets('Quỹ tên "Quỹ tiền ăn" nhưng KHÁC id → không nhầm', (tester) async {
      await pumpWith(tester, const [], funds: [
        Fund(id: 'quy_khac', name: 'Quỹ tiền ăn', color: Colors.red),
      ]);
      expect(find.byKey(const Key('home_food_fund')), findsNothing);
    });

    testWidgets('Đổi tên quỹ (cùng id) → vẫn hiện, theo tên mới', (tester) async {
      await pumpWith(tester, const [], funds: [DefaultFunds.anUong.copyWith(name: 'Bữa cơm')]);
      expect(find.byKey(const Key('home_food_fund')), findsOneWidget);
      expect(find.text('BỮA CƠM'), findsOneWidget);
    });
  });

  group('Sự kiện chạm', () {
    testWidgets('Thẻ Vợ / Chồng chỉ là số: chạm không mở gì', (tester) async {
      await pumpWith(tester, _sampleLedger());
      await tester.tap(find.byKey(const Key('home_member_vo')));
      await tester.tap(find.byKey(const Key('home_member_chong')));
      await tester.pumpAndSettle();
      expect(find.byType(FundDetailScreen), findsNothing);
      expect(find.byType(AddTransactionSheet), findsNothing);
      expect(find.byKey(const Key('home_member_vo')), findsOneWidget);
    });

    testWidgets('"Xem chi tiết" → chuyển sang tab Tổng hợp', (tester) async {
      await pumpWith(tester, _sampleLedger());
      final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
      expect(container.read(currentTabProvider), AppTab.home);

      await tester.tap(find.byKey(const Key('home_spending_detail')));
      await tester.pumpAndSettle();

      expect(container.read(currentTabProvider), AppTab.summary);
    });

    testWidgets('Chạm thẻ Quỹ tiền ăn → màn chi tiết đúng quỹ; Back → về Trang chủ, đúng 1 màn', (tester) async {
      await pumpWith(tester, _sampleLedger());
      // Bấm liên tiếp trong CÙNG khung hình (nhanh hơn mọi thao tác thật).
      final onTap = tester
          .widget<InkWell>(find.descendant(of: find.byKey(const Key('home_food_fund')), matching: find.byType(InkWell)).first)
          .onTap!;
      onTap();
      onTap();
      onTap();
      await tester.pumpAndSettle();
      expect(find.byType(FundDetailScreen, skipOffstage: false), findsOneWidget, reason: 'bấm nhanh không mở trùng (đếm cả route bên dưới)');
      expect(find.text('Quỹ tiền ăn'), findsWidgets);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.byType(FundDetailScreen), findsNothing);
      expect(find.byKey(const Key('home_food_fund')), findsOneWidget);
    });

    testWidgets('Nạp quỹ → mở đúng 1 sheet Thêm giao dịch (điền sẵn quỹ); bấm nhanh không mở trùng', (tester) async {
      await pumpWith(tester, _sampleLedger());
      final onPressed = tester.widget<OutlinedButton>(find.byKey(const Key('home_food_fund_topup'))).onPressed!;
      onPressed();
      onPressed();
      onPressed();
      await tester.pumpAndSettle();

      expect(find.byType(AddTransactionSheet, skipOffstage: false), findsOneWidget, reason: 'bấm nhanh không mở trùng');
      final sheet = tester.widget<AddTransactionSheet>(find.byType(AddTransactionSheet));
      expect(sheet.initialFundId, DefaultFunds.anUongId);
      expect(sheet.initialType, EntryType.chuyen);
      expect(sheet.initialTransferSubKind, TransferSubKind.fund);
    });

    testWidgets('Nạp quỹ KHÔNG kích hoạt luôn thao tác mở màn chi tiết quỹ (nút riêng, không nổi bọt lên thẻ)', (tester) async {
      await pumpWith(tester, _sampleLedger());
      await tester.tap(find.byKey(const Key('home_food_fund_topup')));
      await tester.pumpAndSettle();
      expect(find.byType(FundDetailScreen), findsNothing);
    });
  });

  testWidgets('Stream update: Trang chủ tự cập nhật khi Repository emit list mới', (tester) async {
    await pumpWith(tester, [_income(1000000, memberRefId: 'vo')]);
    expect(_text(tester, 'home_income_vo'), '1.000.000 đ');
    expect(_text(tester, 'home_balance_vo'), '1.000.000 đ');

    fakeRepo.emit([_income(1000000, memberRefId: 'vo'), _income(4000000, memberRefId: 'chong')]);
    await tester.pumpAndSettle();
    expect(_text(tester, 'home_income_chong'), '4.000.000 đ');
    expect(_text(tester, 'home_balance_chong'), '4.000.000 đ');
  });

  testWidgets('Thu nhập tháng trước không lọt vào "Thu nhập tháng này" nhưng vẫn nằm trong Số dư hiện tại', (tester) async {
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1, 15);
    final old = Transaction(
      id: 'old',
      type: TransactionType.income,
      categoryId: DefaultCategories.thuNhap.id,
      sourceKind: PoolKind.external,
      destinationKind: PoolKind.memberAvailable,
      destinationRefId: 'vo',
      amountMinor: 7000000,
      transactionDate: lastMonth,
      createdAt: lastMonth,
      clientTxId: 'client-old',
    );
    await pumpWith(tester, [old, _income(1000000, memberRefId: 'vo')]);
    expect(_text(tester, 'home_income_vo'), '1.000.000 đ');
    expect(_text(tester, 'home_balance_vo'), '8.000.000 đ');
  });
}
