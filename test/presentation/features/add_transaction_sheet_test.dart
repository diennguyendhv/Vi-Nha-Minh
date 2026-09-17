import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/application/currency/currency_context.dart';
import 'package:vi_nha_minh/core/constants/default_categories.dart';
import 'package:vi_nha_minh/core/constants/default_funds.dart';
import 'package:vi_nha_minh/core/constants/default_savings_asset_types.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/family_member.dart';
import 'package:vi_nha_minh/domain/entities/fund.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/savings_asset_type.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/entities/transfer_kind.dart';
import 'package:vi_nha_minh/domain/errors/domain_exceptions.dart';
import 'package:vi_nha_minh/domain/repositories/category_repository.dart';
import 'package:vi_nha_minh/domain/repositories/fund_repository.dart';
import 'package:vi_nha_minh/domain/repositories/savings_asset_type_repository.dart';
import 'package:vi_nha_minh/domain/repositories/transaction_repository.dart';
import 'package:vi_nha_minh/presentation/features/add_transaction/add_transaction_sheet.dart';
import 'package:vi_nha_minh/presentation/providers/category_providers.dart';
import 'package:vi_nha_minh/presentation/providers/currency_providers.dart';
import 'package:vi_nha_minh/presentation/providers/fund_providers.dart';
import 'package:vi_nha_minh/presentation/providers/savings_asset_type_providers.dart';
import 'package:vi_nha_minh/presentation/providers/transaction_providers.dart';

/// Fake `TransactionRepository` điều khiển được — cho phép ép lỗi 1 lần
/// (mô phỏng transient/persistence failure), "treo" 1 lần lưu đang chạy
/// (double-tap), và ghi lại toàn bộ transaction đã CỐ GẮNG ghi (kể cả lần
/// fail) để verify retry giữ nguyên `clientTxId`. Dùng `StreamController`
/// Dart thuần (không phải Drift stream) — tránh vấn đề timer/fake-async khi
/// chạy trong widget test.
class _FakeTransactionRepository implements TransactionRepository {
  final _controller = StreamController<List<Transaction>>.broadcast();
  List<Transaction> _all = const [];

  Object? nextAddError;
  Completer<void>? pendingGate;

  final List<String> addedClientTxIds = [];
  Transaction? lastAdded;

  @override
  Future<Transaction> addTransaction(Transaction transaction) async {
    addedClientTxIds.add(transaction.clientTxId);
    if (pendingGate != null) {
      await pendingGate!.future;
    }
    if (nextAddError != null) {
      final err = nextAddError!;
      nextAddError = null;
      throw err;
    }
    lastAdded = transaction;
    _all = [..._all, transaction];
    _controller.add(_all);
    return transaction;
  }

  @override
  Stream<List<Transaction>> watchTransactions() => _controller.stream;

  @override
  Future<Transaction?> getTransactionById(String id) async => null;

  @override
  Future<Transaction?> getTransactionByClientTxId(String clientTxId) async =>
      null;

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

class _TestCurrencyContext implements CurrencyContext {
  const _TestCurrencyContext(this.value);
  final String value;
  @override
  Future<String> getBaseCurrencyCode() async => value;
}

List<Override> _formLookupOverrides() => [
  categoryRepositoryProvider.overrideWithValue(
    _StaticCategoryRepository(DefaultCategories.all),
  ),
  fundRepositoryProvider.overrideWithValue(
    _StaticFundRepository(DefaultFunds.all),
  ),
  savingsAssetTypeRepositoryProvider.overrideWithValue(
    _StaticSavingsAssetTypeRepository(DefaultSavingsAssetTypes.all),
  ),
];

Future<void> _pumpSheet(
  WidgetTester tester, {
  required _FakeTransactionRepository fakeRepo,
  CurrencyContext currencyContext = const _TestCurrencyContext('VND'),
  EntryType initialType = EntryType.chi,
}) async {
  // Sheet dài (DraggableScrollableSheet + keypad) không vừa viewport test
  // mặc định (800x600) — phóng to bề mặt test để mọi control (kể cả bàn
  // phím số dưới cùng) đều tap được mà không cần cuộn thủ công phức tạp.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._formLookupOverrides(),
        transactionRepositoryProvider.overrideWithValue(fakeRepo),
        currencyContextProvider.overrideWithValue(currencyContext),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            // Cố tình dùng TextButton (không phải ElevatedButton) — tránh
            // nhầm lẫn với nút "Lưu giao dịch" thật (ElevatedButton) khi
            // tìm theo `find.byType(ElevatedButton)` trong `_tapSave`.
            builder: (context) => TextButton(
              onPressed: () =>
                  showAddTransactionSheet(context, initialType: initialType),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _selectDropdown(
  WidgetTester tester,
  String hintOrCurrentText,
  String targetText,
) async {
  final field = find.text(hintOrCurrentText).first;
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field, warnIfMissed: false);
  await tester.pumpAndSettle();
  await tester.tap(find.text(targetText).last, warnIfMissed: false);
  await tester.pumpAndSettle();
}

Future<void> _typeDigits(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    final key = find.text(d).first;
    await tester.ensureVisible(key);
    await tester.tap(key);
    await tester.pump();
  }
}

Future<void> _tapSave(WidgetTester tester) async {
  // Dùng `find.byType` thay vì tìm theo text — khi đang submit, label đổi
  // thành "Đang lưu..." (xem mục 11), text-based finder sẽ không thấy nút.
  final button = find.byType(ElevatedButton).first;
  await tester.ensureVisible(button);
  await tester.tap(button, warnIfMissed: false);
}

Future<void> _tapSegment(WidgetTester tester, String label) async {
  final segment = find.text(label).first;
  await tester.ensureVisible(segment);
  await tester.tap(segment, warnIfMissed: false);
  await tester.pumpAndSettle();
}

/// Dùng cho `_FundPickRow` khi không có `walletLabel` (panel "Nạp quỹ") —
/// field đóng không hiện text nào (không có `hint`), nên phải mở bằng
/// `find.byType` thay vì tìm theo text.
Future<void> _selectFundByType(WidgetTester tester, String fundName) async {
  final field = find.byType(DropdownButtonFormField<String?>).first;
  await tester.ensureVisible(field);
  await tester.tap(field, warnIfMissed: false);
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining(fundName).last, warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  late _FakeTransactionRepository fakeRepo;

  setUp(() {
    fakeRepo = _FakeTransactionRepository();
  });

  tearDown(() async {
    await fakeRepo.dispose();
  });

  group('Flow mapping (Phase 6 mục 28/29)', () {
    testWidgets('1 — EXPENSE: category + amount map đúng', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chi);

      await _selectDropdown(tester, 'Chọn hạng mục', 'Sinh hoạt');
      await _typeDigits(tester, '200000');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(fakeRepo.lastAdded, isNotNull);
      final tx = fakeRepo.lastAdded!;
      expect(tx.type, TransactionType.expense);
      expect(tx.categoryId, 'sinh_hoat');
      expect(tx.sourceKind, PoolKind.memberAvailable);
      expect(tx.sourceRefId, 'vo');
      expect(tx.destinationKind, PoolKind.external);
      expect(tx.amountMinor, 200000);
      expect(tx.currency, 'VND');
    });

    testWidgets('2 — INCOME: category + amount map đúng', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.thu);

      await _selectDropdown(tester, 'Chọn hạng mục', 'Thu nhập');
      await _typeDigits(tester, '16000000');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      final tx = fakeRepo.lastAdded!;
      expect(tx.type, TransactionType.income);
      expect(tx.categoryId, 'thu_nhap');
      expect(tx.sourceKind, PoolKind.external);
      expect(tx.destinationKind, PoolKind.memberAvailable);
      expect(tx.destinationRefId, 'vo');
      expect(tx.amountMinor, 16000000);
    });

    testWidgets('3 — FUND_TOPUP: transfer → nạp quỹ map đúng', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chuyen);

      await _tapSegment(tester, 'Nạp quỹ');
      await _selectFundByType(tester, DefaultFunds.anUong.name);
      await _typeDigits(tester, '50000');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      final tx = fakeRepo.lastAdded!;
      expect(tx.type, TransactionType.transfer);
      expect(tx.transferKind, TransferKind.fundTopup);
      expect(tx.categoryId, DefaultCategories.napQuy.id);
      expect(tx.sourceKind, PoolKind.memberAvailable);
      expect(tx.sourceRefId, 'vo');
      expect(tx.destinationKind, PoolKind.fund);
      expect(tx.destinationRefId, DefaultFunds.anUongId);
      expect(tx.amountMinor, 50000);
    });

    testWidgets('4 — Fund-backed EXPENSE: source = FUND, không phải MEMBER_AVAILABLE', (
      tester,
    ) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chi);

      await _selectDropdown(tester, 'Chọn hạng mục', 'Sinh hoạt');
      // Chọn quỹ TRƯỚC khi gõ số tiền — balance quỹ = 0 lúc này nên item
      // dropdown còn "enabled" (xem `_FundPickRow._buildItems`).
      await _selectFundByType(tester, DefaultFunds.anUong.name);
      await _typeDigits(tester, '30000');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      final tx = fakeRepo.lastAdded!;
      expect(tx.type, TransactionType.expense);
      expect(tx.sourceKind, PoolKind.fund, reason: 'mục 14 — Chi từ Quỹ, KHÔNG phải ví thành viên');
      expect(tx.sourceRefId, DefaultFunds.anUongId);
      expect(tx.destinationKind, PoolKind.external);
      expect(tx.amountMinor, 30000);
    });

    testWidgets('5 — SAVINGS_TOPUP map đúng', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chuyen);

      await _tapSegment(tester, 'Tiết kiệm');
      await _selectDropdown(tester, 'Chọn loại tài sản', DefaultSavingsAssetTypes.cash.name);
      await _typeDigits(tester, '100000');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      final tx = fakeRepo.lastAdded!;
      expect(tx.type, TransactionType.transfer);
      expect(tx.transferKind, TransferKind.savingsTopup);
      expect(tx.sourceKind, PoolKind.memberAvailable);
      expect(tx.sourceRefId, 'vo');
      expect(tx.destinationKind, PoolKind.memberSavingsAsset);
      expect(tx.destinationRefId, savingsAssetRefId(DefaultSavingsAssetTypes.cashId, FamilyMember.vo));
      expect(tx.amountMinor, 100000);
    });

    testWidgets('6 — SAVINGS_WITHDRAW map đúng', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chuyen);

      await _tapSegment(tester, 'Tiết kiệm');
      await _tapSegment(tester, 'Rút về ví');
      await _selectDropdown(tester, 'Chọn loại tài sản', DefaultSavingsAssetTypes.cash.name);
      await _typeDigits(tester, '20000');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      final tx = fakeRepo.lastAdded!;
      expect(tx.type, TransactionType.transfer);
      expect(tx.transferKind, TransferKind.savingsWithdraw);
      expect(tx.sourceKind, PoolKind.memberSavingsAsset);
      expect(tx.sourceRefId, savingsAssetRefId(DefaultSavingsAssetTypes.cashId, FamilyMember.vo));
      expect(tx.destinationKind, PoolKind.memberAvailable);
      expect(tx.destinationRefId, 'vo');
      expect(tx.amountMinor, 20000);
    });

    testWidgets('7 — SAVINGS_CONVERT map đúng', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chuyen);

      await _tapSegment(tester, 'Tiết kiệm');
      await _tapSegment(tester, 'Chuyển đổi');
      await _selectDropdown(tester, 'Chọn loại tài sản', DefaultSavingsAssetTypes.cash.name);
      await _selectDropdown(tester, 'Chọn loại tài sản', DefaultSavingsAssetTypes.bank.name);
      await _typeDigits(tester, '70000');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      final tx = fakeRepo.lastAdded!;
      expect(tx.type, TransactionType.transfer);
      expect(tx.transferKind, TransferKind.savingsConvert);
      expect(tx.sourceKind, PoolKind.memberSavingsAsset);
      expect(tx.sourceRefId, savingsAssetRefId(DefaultSavingsAssetTypes.cashId, FamilyMember.vo));
      expect(tx.destinationKind, PoolKind.memberSavingsAsset);
      expect(tx.destinationRefId, savingsAssetRefId(DefaultSavingsAssetTypes.bankId, FamilyMember.vo));
      expect(tx.amountMinor, 70000);
    });

    testWidgets('8 — MEMBER_TO_MEMBER map đúng', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chuyen);

      // Mặc định "Thành viên khác" đã được chọn sẵn (initialTransferSubKind
      // null → TransferSubKind.member), người gửi mặc định Vợ, người nhận
      // mặc định Chồng — không cần đổi gì thêm để có 1 cặp source≠destination
      // hợp lệ.
      await _typeDigits(tester, '80000');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      final tx = fakeRepo.lastAdded!;
      expect(tx.type, TransactionType.transfer);
      expect(tx.transferKind, TransferKind.memberToMember);
      expect(tx.categoryId, DefaultCategories.chuyenTienThanhVien.id);
      expect(tx.sourceKind, PoolKind.memberAvailable);
      expect(tx.sourceRefId, 'vo');
      expect(tx.destinationKind, PoolKind.memberAvailable);
      expect(tx.destinationRefId, 'chong');
      expect(tx.amountMinor, 80000);
    });
  });

  group('Currency lifecycle (Phase 6 mục 30) — UI không tự chọn/hard-code currency', () {
    testWidgets('override CurrencyContext = USD → transaction persist đúng USD, UI không truyền gì', (
      tester,
    ) async {
      await _pumpSheet(
        tester,
        fakeRepo: fakeRepo,
        initialType: EntryType.thu,
        currencyContext: const _TestCurrencyContext('USD'),
      );

      await _selectDropdown(tester, 'Chọn hạng mục', 'Thu nhập');
      await _typeDigits(tester, '1000');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(fakeRepo.lastAdded!.currency, 'USD');
      expect(fakeRepo.lastAdded!.amountMinor, 1000, reason: 'không nhân/chia/convert theo currency');
    });

    testWidgets('override CurrencyContext = JPY → transaction persist đúng JPY', (tester) async {
      await _pumpSheet(
        tester,
        fakeRepo: fakeRepo,
        initialType: EntryType.thu,
        currencyContext: const _TestCurrencyContext('JPY'),
      );

      await _selectDropdown(tester, 'Chọn hạng mục', 'Thu nhập');
      await _typeDigits(tester, '1000');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(fakeRepo.lastAdded!.currency, 'JPY');
    });
  });

  group('Retry / clientTxId lifecycle (Phase 6 mục 31/32)', () {
    testWidgets('31 — retry sau lỗi transient, KHÔNG đổi form → giữ nguyên clientTxId', (
      tester,
    ) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.thu);
      await _selectDropdown(tester, 'Chọn hạng mục', 'Thu nhập');
      await _typeDigits(tester, '100000');

      fakeRepo.nextAddError = const PersistenceException('lỗi mô phỏng lần 1');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(fakeRepo.addedClientTxIds, hasLength(1));
      expect(fakeRepo.lastAdded, isNull, reason: 'lần đầu fail, chưa có gì persist');
      expect(find.text('Thêm giao dịch'), findsOneWidget, reason: 'sheet vẫn còn mở (chưa pop) sau lỗi');

      // KHÔNG đổi form — tap Save lại, lần này không ép lỗi.
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(fakeRepo.addedClientTxIds, hasLength(2));
      expect(
        fakeRepo.addedClientTxIds[0],
        fakeRepo.addedClientTxIds[1],
        reason: 'retry phải tái sử dụng đúng clientTxId cũ',
      );
      expect(fakeRepo.lastAdded, isNotNull, reason: 'lần 2 thành công');
      expect(fakeRepo.lastAdded!.amountMinor, 100000, reason: 'payload giữ nguyên qua retry');
    });

    testWidgets('32 — đổi amount sau khi fail → command/clientTxId MỚI, khác lần trước', (
      tester,
    ) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.thu);
      await _selectDropdown(tester, 'Chọn hạng mục', 'Thu nhập');
      await _typeDigits(tester, '100000');

      fakeRepo.nextAddError = const PersistenceException('lỗi mô phỏng');
      await _tapSave(tester);
      await tester.pumpAndSettle();
      final firstClientTxId = fakeRepo.addedClientTxIds.single;

      // Đổi số tiền — mục 10: pending command phải bị vô hiệu.
      await _typeDigits(tester, '1'); // 100000 -> 1000001

      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(fakeRepo.addedClientTxIds, hasLength(2));
      expect(
        fakeRepo.addedClientTxIds[1],
        isNot(firstClientTxId),
        reason: 'form đã đổi → phải là command mới, clientTxId khác',
      );
      expect(fakeRepo.lastAdded!.amountMinor, 1000001);
    });
  });

  group('Double-tap protection (Phase 6 mục 33)', () {
    testWidgets('tap Save 2 lần liên tiếp khi lần đầu còn đang treo → chỉ 1 request tới Repository', (
      tester,
    ) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.thu);
      await _selectDropdown(tester, 'Chọn hạng mục', 'Thu nhập');
      await _typeDigits(tester, '50000');

      fakeRepo.pendingGate = Completer<void>();
      await _tapSave(tester);
      await tester.pump(); // build lại với _submitting = true, KHÔNG settle (còn đang treo).

      // Tap thứ 2 trong lúc lần 1 còn đang "treo" — nút phải đã bị disable
      // (canSave = !_submitting && ...), nên tapSave lần 2 không kích hoạt gì.
      await _tapSave(tester);
      await tester.pump();

      expect(fakeRepo.addedClientTxIds, hasLength(1), reason: 'chỉ đúng 1 request tới Repository');

      fakeRepo.pendingGate!.complete();
      await tester.pumpAndSettle();
      expect(fakeRepo.lastAdded, isNotNull);
    });
  });

  group('Error presentation (Phase 6 mục 34)', () {
    Future<void> expectError(
      WidgetTester tester,
      Object error,
      String expectedMessage,
    ) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.thu);
      await _selectDropdown(tester, 'Chọn hạng mục', 'Thu nhập');
      await _typeDigits(tester, '50000');

      fakeRepo.nextAddError = error;
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(find.text(expectedMessage), findsOneWidget);
      // Không lộ raw class name/SQLite message nào.
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('Sqlite'), findsNothing);
      // Submitting reset — nút bấm lại được.
      expect(find.text('Lưu giao dịch'), findsOneWidget);
    }

    testWidgets('InsufficientBalanceException → message tiếng Việt đúng, không leak chi tiết', (
      tester,
    ) async {
      await expectError(
        tester,
        const InsufficientBalanceException(
          poolKind: PoolKind.memberAvailable,
          refId: 'vo',
          currentBalance: 0,
          requestedAmount: 50000,
        ),
        'Số dư không đủ để ghi giao dịch này.',
      );
    });

    testWidgets('SameSourceDestinationException → message đúng', (tester) async {
      await expectError(
        tester,
        const SameSourceDestinationException(PoolKind.memberAvailable, 'vo'),
        'Nguồn và đích không được trùng nhau.',
      );
    });

    testWidgets('InvalidAmountException → message đúng', (tester) async {
      await expectError(tester, const InvalidAmountException(0), 'Số tiền không hợp lệ.');
    });

    testWidgets('ClientTxIdConflictException → message an toàn, KHÔNG tự sinh clientTxId mới rồi retry', (
      tester,
    ) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.thu);
      await _selectDropdown(tester, 'Chọn hạng mục', 'Thu nhập');
      await _typeDigits(tester, '50000');

      final dummyTx = Transaction(
        id: 'x',
        type: TransactionType.income,
        categoryId: 'thu_nhap',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 999,
        transactionDate: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        clientTxId: 'other',
      );
      fakeRepo.nextAddError = ClientTxIdConflictException(
        clientTxId: 'x',
        existing: dummyTx,
        attempted: dummyTx,
      );
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(find.text('Giao dịch bị xung đột, vui lòng thử lưu lại.'), findsOneWidget);
      final firstClientTxId = fakeRepo.addedClientTxIds.single;

      // Lưu lại KHÔNG đổi form — vì command đã bị vô hiệu sau conflict, lần
      // này phải là command MỚI (clientTxId khác), KHÔNG lặp lại cùng id.
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(fakeRepo.addedClientTxIds, hasLength(2));
      expect(fakeRepo.addedClientTxIds[1], isNot(firstClientTxId));
    });

    testWidgets('PersistenceConstraintException → message đúng, không lộ chi tiết constraint', (
      tester,
    ) async {
      await expectError(
        tester,
        const PersistenceConstraintException(
          kind: PersistenceConstraintKind.foreignKey,
          message: 'chi tiết kỹ thuật không được lộ ra UI',
        ),
        'Dữ liệu tham chiếu không hợp lệ, vui lòng thử lại.',
      );
    });
  });
}
