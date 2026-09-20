import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/entities/field_update.dart';
import 'package:vi_nha_minh/application/currency/currency_context.dart';
import 'package:vi_nha_minh/core/constants/default_categories.dart';
import 'package:vi_nha_minh/core/constants/default_funds.dart';
import 'package:vi_nha_minh/core/constants/default_savings_asset_types.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/fund.dart';
import 'package:vi_nha_minh/domain/entities/obligation.dart';
import 'package:vi_nha_minh/domain/entities/obligation_direction.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/savings_asset_type.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/errors/domain_exceptions.dart';
import 'package:vi_nha_minh/domain/repositories/category_repository.dart';
import 'package:vi_nha_minh/domain/repositories/fund_repository.dart';
import 'package:vi_nha_minh/domain/repositories/savings_asset_type_repository.dart';
import 'package:vi_nha_minh/domain/repositories/transaction_repository.dart';
import 'package:vi_nha_minh/presentation/features/transactions/transaction_detail_screen.dart';
import 'package:vi_nha_minh/presentation/features/loans/loan_detail_screen.dart';
import 'package:vi_nha_minh/presentation/providers/obligation_providers.dart';
import 'package:vi_nha_minh/presentation/providers/counterparty_providers.dart';
import 'package:vi_nha_minh/presentation/providers/category_providers.dart';
import 'package:vi_nha_minh/presentation/providers/currency_providers.dart';
import 'package:vi_nha_minh/presentation/providers/fund_providers.dart';
import 'package:vi_nha_minh/presentation/providers/savings_asset_type_providers.dart';
import 'package:vi_nha_minh/presentation/providers/feature_providers.dart';
import 'package:vi_nha_minh/presentation/providers/transaction_providers.dart';

/// Ghi lại toàn bộ tham số 1 lần gọi `updateTransaction`.
class RecordedUpdateCall {
  RecordedUpdateCall({
    required this.transactionId,
    this.amountMinor,
    this.categoryId,
    this.note,
    this.memberRefId,
    this.transactionDate,
    this.status,
  });

  final String transactionId;
  final int? amountMinor;
  final String? categoryId;
  final String? note;
  final String? memberRefId;
  final DateTime? transactionDate;
  final FieldUpdate<String>? status;
}

class _FakeTransactionRepository implements TransactionRepository {
  final _controller = StreamController<List<Transaction>>.broadcast();
  List<Transaction> _current = const [];

  final List<RecordedUpdateCall> updateCalls = [];
  final List<String> reverseCalls = [];

  Object? nextUpdateError;
  Object? nextReverseError;
  Completer<void>? pendingGate;

  void seed(List<Transaction> list) {
    _current = list;
    _controller.add(_current);
  }

  @override
  Stream<List<Transaction>> watchTransactions() async* {
    // Mỗi subscriber mới (mỗi lần StreamProvider được tạo) phải thấy NGAY
    // snapshot hiện tại rồi mới tiếp tục nhận update — giống hệt hành vi
    // stream Drift thật. `_controller` (broadcast) không tự replay cho
    // subscriber tới sau, nên phải tự yield `_current` trước.
    yield _current;
    yield* _controller.stream;
  }

  @override
  Future<void> updateTransaction(
    String transactionId, {
    int? amountMinor,
    String? categoryId,
    String? note,
    String? memberRefId,
    DateTime? transactionDate,
    FieldUpdate<String>? status,
  }) async {
    updateCalls.add(
      RecordedUpdateCall(
        transactionId: transactionId,
        amountMinor: amountMinor,
        categoryId: categoryId,
        note: note,
        memberRefId: memberRefId,
        transactionDate: transactionDate,
        status: status,
      ),
    );
    if (pendingGate != null) await pendingGate!.future;
    if (nextUpdateError != null) {
      final err = nextUpdateError!;
      nextUpdateError = null;
      throw err;
    }
  }

  final List<String> deleteCalls = [];
  Object? nextDeleteError;

  @override
  Future<int> purgeDeletedHistory(String categoryId) async => 0;

  @override
  Future<int> purgeDeletedHistoryForStatus(String statusId) async => 0;

  @override
  Future<void> deleteTransaction(String transactionId) async {
    deleteCalls.add(transactionId);
    if (pendingGate != null) await pendingGate!.future;
    if (nextDeleteError != null) {
      final err = nextDeleteError!;
      nextDeleteError = null;
      throw err;
    }
    _current = _current.where((t) => t.id != transactionId).toList();
    _controller.add(_current);
  }

  @override
  Future<void> reverseTransaction(String transactionId) async {
    reverseCalls.add(transactionId);
    if (pendingGate != null) await pendingGate!.future;
    if (nextReverseError != null) {
      final err = nextReverseError!;
      nextReverseError = null;
      throw err;
    }
  }

  final List<Transaction> addedTransactions = [];

  @override
  Future<Transaction> addTransaction(Transaction transaction) async {
    addedTransactions.add(transaction);
    _current = [..._current, transaction];
    _controller.add(_current);
    return transaction;
  }

  @override
  Future<Transaction?> getTransactionById(String id) async => null;

  @override
  Future<Transaction?> getTransactionByClientTxId(String clientTxId) async =>
      null;

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
  Future<({Transaction principal, Transaction? interest})>
  correctObligationSettlement(
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

  @override
  Future<void> reactivateFund(String fundId) async {}

  @override
  Future<void> deleteFundPermanently(String fundId) async {}
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
  @override
  Future<void> renameAssetType(String assetTypeId, String newName) async {}
  @override
  Future<void> reactivateAssetType(String assetTypeId) async {}
  @override
  Stream<Set<String>> watchDeletableAssetTypeIds() => Stream.value(const {});
  @override
  Future<void> deleteAssetTypePermanently(String assetTypeId) async {}
}

class _TestCurrencyContext implements CurrencyContext {
  const _TestCurrencyContext(this.value);
  final String value;
  @override
  Future<String> getBaseCurrencyCode() async => value;
}

Transaction _expenseTx({
  String id = 'tx1',
  String categoryId = 'sinh_hoat',
  int amountMinor = 100000,
  String note = 'ghi chú cũ',
  String? statusId,
  String? reversedByTxId,
  String sourceRefId = 'vo',
}) {
  return Transaction(
    id: id,
    type: TransactionType.expense,
    categoryId: categoryId,
    sourceKind: PoolKind.memberAvailable,
    sourceRefId: sourceRefId,
    destinationKind: PoolKind.external,
    amountMinor: amountMinor,
    note: note,
    statusId: statusId,
    transactionDate: DateTime(2026, 9, 1),
    createdAt: DateTime(2026, 9, 1),
    clientTxId: 'client-$id',
    reversedByTxId: reversedByTxId,
  );
}

Transaction _incomeTx({String id = 'income1', int amountMinor = 100000}) {
  return Transaction(
    id: id,
    type: TransactionType.income,
    categoryId: 'thu_nhap',
    sourceKind: PoolKind.external,
    destinationKind: PoolKind.memberAvailable,
    destinationRefId: 'vo',
    amountMinor: amountMinor,
    transactionDate: DateTime(2026, 9, 1),
    createdAt: DateTime(2026, 9, 1),
    clientTxId: 'client-$id',
  );
}

Transaction _recoveryTx({
  String id = 'recovery1',
  required String recoveryOfTxId,
  int amountMinor = 450000,
}) {
  return Transaction(
    id: id,
    type: TransactionType.income,
    categoryId: 'hoan_tien_thu_hoi',
    sourceKind: PoolKind.external,
    destinationKind: PoolKind.memberAvailable,
    destinationRefId: 'chong',
    amountMinor: amountMinor,
    recoveryOfTxId: recoveryOfTxId,
    transactionDate: DateTime(2026, 9, 2),
    createdAt: DateTime(2026, 9, 2),
    clientTxId: 'client-$id',
  );
}

Future<void> _pumpDetail(
  WidgetTester tester, {
  required _FakeTransactionRepository fakeRepo,
  required String transactionId,
  List<Obligation> obligations = const [],
  List<Category>? categories,
  bool advancedFeatures = false,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        obligationsStreamProvider.overrideWith(
          (ref) => Stream.value(obligations),
        ),
        counterpartiesStreamProvider.overrideWith((ref) => Stream.value([])),
        advancedFeaturesEnabledProvider.overrideWithValue(advancedFeatures),
        transactionRepositoryProvider.overrideWithValue(fakeRepo),
        categoryRepositoryProvider.overrideWithValue(
          _StaticCategoryRepository(categories ?? DefaultCategories.all),
        ),
        fundRepositoryProvider.overrideWithValue(
          _StaticFundRepository(DefaultFunds.all),
        ),
        savingsAssetTypeRepositoryProvider.overrideWithValue(
          _StaticSavingsAssetTypeRepository(DefaultSavingsAssetTypes.all),
        ),
        currencyContextProvider.overrideWithValue(
          const _TestCurrencyContext('VND'),
        ),
      ],
      child: MaterialApp(
        home: TransactionDetailScreen(transactionId: transactionId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapSave(WidgetTester tester) async {
  final button =
      find.widgetWithText(ElevatedButton, 'Lưu thay đổi').evaluate().isNotEmpty
      ? find.widgetWithText(ElevatedButton, 'Lưu thay đổi')
      : find.byType(ElevatedButton);
  await tester.ensureVisible(button.first);
  await tester.tap(button.first, warnIfMissed: false);
}


/// F30: CĐ với bước "ĐCB" đã ẩn (`isActive == false`).
List<Category> _categoriesWithHiddenDcb() => [
  for (final c in DefaultCategories.all)
    c.id == 'cho_di'
        ? c.copyWith(
            statuses: [
              for (final s in c.statuses)
                s.id == 'cho_di_da_chuan_bi' ? s.copyWith(isActive: false) : s,
            ],
          )
        : c,
];

void main() {
  late _FakeTransactionRepository fakeRepo;

  setUp(() {
    fakeRepo = _FakeTransactionRepository();
  });

  tearDown(() async => fakeRepo.dispose());

  group('Phase 8.8 generic transaction containment', () {
    Transaction loanTransaction(String role, {String id = 'loan-tx'}) {
      final creation = role.endsWith('creation');
      final payable = role.startsWith('payable');
      final interest = role == 'receivable-interest';
      return Transaction(
        id: id,
        type: payable
            ? (creation ? TransactionType.income : TransactionType.expense)
            : (interest ? TransactionType.income : TransactionType.transfer),
        categoryId: payable
            ? (creation
                  ? DefaultCategories.vayNo.id
                  : DefaultCategories.traNo.id)
            : (interest
                  ? DefaultCategories.laiChoVay.id
                  : DefaultCategories.choVay.id),
        sourceKind: payable
            ? (creation ? PoolKind.external : PoolKind.memberAvailable)
            : (creation
                  ? PoolKind.memberAvailable
                  : (interest ? PoolKind.external : PoolKind.receivable)),
        sourceRefId: payable
            ? (creation ? null : 'vo')
            : (creation ? 'vo' : (interest ? null : 'loan-1')),
        destinationKind: payable
            ? (creation ? PoolKind.memberAvailable : PoolKind.external)
            : (creation ? PoolKind.receivable : PoolKind.memberAvailable),
        destinationRefId: payable
            ? (creation ? 'vo' : null)
            : (creation ? 'loan-1' : 'vo'),
        amountMinor: 100000,
        note: 'Loan history entry',
        obligationId: 'loan-1',
        settlementGroupId: creation ? null : 'settlement-1',
        transactionDate: DateTime(2026, 9, 1),
        createdAt: DateTime(2026, 9, 1),
        clientTxId: 'client-$id',
      );
    }

    for (final role in [
      'receivable-creation',
      'payable-creation',
      'receivable-principal',
      'receivable-interest',
      'payable-settlement',
    ]) {
      testWidgets('$role is read-only and navigates to its own loan', (
        tester,
      ) async {
        final direction = role.startsWith('payable')
            ? ObligationDirection.payable
            : ObligationDirection.receivable;
        fakeRepo.seed([loanTransaction(role)]);
        await _pumpDetail(
          tester,
          fakeRepo: fakeRepo,
          transactionId: 'loan-tx',
          obligations: [
            const Obligation(
              id: 'other-loan',
              counterpartyId: 'other',
              direction: ObligationDirection.payable,
            ),
            Obligation(
              id: 'loan-1',
              counterpartyId: 'person-1',
              direction: direction,
            ),
          ],
        );
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(EditableText), findsNothing);
        expect(find.text('Lưu thay đổi'), findsNothing);
        expect(find.text('Xóa giao dịch'), findsNothing);
        expect(find.text('Hoàn tiền / Thu hồi'), findsNothing);
        expect(find.text('Loan history entry'), findsOneWidget);
        expect(find.textContaining('obligationId'), findsNothing);
        await tester.tap(find.text('Xem khoản vay'));
        await tester.pumpAndSettle();
        final detail = tester.widget<LoanDetailScreen>(
          find.byType(LoanDetailScreen),
        );
        expect(detail.obligationId, 'loan-1');
        expect(detail.direction, direction);
        expect(fakeRepo.updateCalls, isEmpty);
        expect(fakeRepo.deleteCalls, isEmpty);
      });
    }

    testWidgets('stale Save/Delete/Recovery callbacks cannot mutate a loan', (
      tester,
    ) async {
      fakeRepo.seed([_expenseTx()]);
      await _pumpDetail(
        tester,
        fakeRepo: fakeRepo,
        transactionId: 'tx1',
        advancedFeatures: true,
      );
      final save = tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Lưu thay đổi'),
          )
          .onPressed!;
      final delete = tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Xóa giao dịch'),
          )
          .onPressed!;
      final recover = tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Hoàn tiền / Thu hồi'),
          )
          .onPressed!;
      // Simulate a new snapshot while an older frame's callbacks survive.
      fakeRepo.seed([loanTransaction('payable-creation', id: 'tx1')]);
      await tester.pumpAndSettle();
      save();
      delete();
      recover();
      await tester.pumpAndSettle();
      expect(fakeRepo.updateCalls, isEmpty);
      expect(fakeRepo.deleteCalls, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('Delete rechecks loan ownership after confirmation', (
      tester,
    ) async {
      fakeRepo.seed([_expenseTx()]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');
      await tester.tap(find.text('Xóa giao dịch'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      fakeRepo.seed([loanTransaction('receivable-creation', id: 'tx1')]);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xóa').last);
      await tester.pumpAndSettle();
      expect(fakeRepo.deleteCalls, isEmpty);
      expect(find.text('Xem khoản vay'), findsOneWidget);
    });

    testWidgets('missing loan metadata keeps transaction read-only', (
      tester,
    ) async {
      fakeRepo.seed([loanTransaction('receivable-interest')]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'loan-tx');
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Xem khoản vay'),
            )
            .onPressed,
        isNull,
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Lưu thay đổi'), findsNothing);
      expect(find.text('Xóa giao dịch'), findsNothing);
    });
  });

  group('Update path (Phase 7 mục 22)', () {
    testWidgets(
      '1 — note-only update: gọi UpdateTransactionUseCase với đúng id, amount giữ nguyên',
      (tester) async {
        fakeRepo.seed([_expenseTx()]);
        await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

        await tester.enterText(find.byType(TextField).at(1), 'ghi chú mới');
        await _tapSave(tester);
        await tester.pumpAndSettle();

        expect(fakeRepo.updateCalls, hasLength(1));
        final call = fakeRepo.updateCalls.single;
        expect(
          call.transactionId,
          'tx1',
          reason: 'Test 4 — đúng id tới Use Case',
        );
        expect(call.note, 'ghi chú mới');
        expect(
          call.amountMinor,
          100000,
          reason:
              'amount không đổi vẫn được truyền đủ (Repository tự quyết định)',
        );
      },
    );

    testWidgets('F30 — giao dịch lịch sử ở bước đã ẩn vẫn hiện đúng tên (kèm "đã ẩn"), không bị đổi ngầm', (
      tester,
    ) async {
      fakeRepo.seed([
        _expenseTx(categoryId: 'cho_di', statusId: 'cho_di_da_chuan_bi'),
      ]);
      await _pumpDetail(
        tester,
        fakeRepo: fakeRepo,
        transactionId: 'tx1',
        categories: _categoriesWithHiddenDcb(),
      );

      expect(find.text('ĐCB (ngừng sử dụng)'), findsOneWidget, reason: 'lịch sử resolve tên bước đã ẩn');

      // Lưu mà không đụng gì: statusId giữ nguyên bước lịch sử.
      await _tapSave(tester);
      await tester.pumpAndSettle();
      final call = fakeRepo.updateCalls.single;
      expect(call.status, isNull, reason: 'không đụng trạng thái → KHÔNG đổi (null), giữ bước lịch sử');
    });

    testWidgets('F30 — mở bộ chọn: bước đang dùng + bước lịch sử của chính giao dịch, không có bước ẩn khác', (
      tester,
    ) async {
      // Ẩn thêm ĐG; giao dịch đang ở CCB (đang dùng) → chỉ CCB, không thấy ĐCB/ĐG.
      final cats = [
        for (final c in _categoriesWithHiddenDcb())
          c.id == 'cho_di'
              ? c.copyWith(
                  statuses: [
                    for (final s in c.statuses)
                      s.id == 'cho_di_da_gui' ? s.copyWith(isActive: false) : s,
                  ],
                )
              : c,
      ];
      fakeRepo.seed([
        _expenseTx(categoryId: 'cho_di', statusId: 'cho_di_chua_chuan_bi'),
      ]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1', categories: cats);

      await tester.tap(find.text('CCB').first, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('ĐCB'), findsNothing);
      expect(find.text('ĐCB (ngừng sử dụng)'), findsNothing);
      expect(find.text('ĐG'), findsNothing);
      expect(find.text('CCB'), findsWidgets);
    });

    testWidgets('2 — status update (bundled trong Save) map đúng statusId', (
      tester,
    ) async {
      fakeRepo.seed([
        _expenseTx(categoryId: 'cho_di', statusId: 'cho_di_chua_chuan_bi'),
      ]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

      await tester.tap(
        find.text('CCB').first,
        warnIfMissed: false,
      ); // mở dropdown trạng thái
      await tester.pumpAndSettle();
      await tester.tap(find.text('ĐCB').last, warnIfMissed: false);
      await tester.pumpAndSettle();

      await _tapSave(tester);
      await tester.pumpAndSettle();

      final call = fakeRepo.updateCalls.single;
      expect(call.status, const FieldUpdate.set('cho_di_da_chuan_bi'));
      expect(
        call.amountMinor,
        100000,
        reason: 'status-only change vẫn qua UpdateTransactionUseCase (bundled), không mất field khác',
      );
    });

    testWidgets(
      '3 — financial amount update: amountMinor mới tới đúng Use Case',
      (tester) async {
        fakeRepo.seed([_expenseTx(amountMinor: 100000)]);
        await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

        await tester.enterText(find.byType(TextField).first, '250000');
        await _tapSave(tester);
        await tester.pumpAndSettle();

        final call = fakeRepo.updateCalls.single;
        expect(call.transactionId, 'tx1');
        expect(call.amountMinor, 250000);
      },
    );
  });

  group('R7 — ô số tiền khi sửa giao dịch', () {
    Finder amountField() => find.byKey(const Key('detail_amount_field'));
    String amountText(WidgetTester t) =>
        t.widget<TextField>(amountField()).controller!.text;
    ElevatedButton saveButton(WidgetTester t) =>
        t.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Lưu thay đổi'));

    testWidgets('bàn phím số hệ thống; chỉ chữ số; bỏ số 0 đầu; xem trước', (tester) async {
      fakeRepo.seed([_expenseTx(amountMinor: 100000)]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

      final field = tester.widget<TextField>(amountField());
      expect(field.keyboardType, TextInputType.number);
      expect(field.inputFormatters, isNotEmpty);
      expect(amountText(tester), '100000');
      expect(find.text('100.000 đ'), findsOneWidget);

      await tester.enterText(amountField(), 'a1-2.3,4 5');
      await tester.pump();
      expect(amountText(tester), '12345');

      await tester.enterText(amountField(), '0400000');
      await tester.pump();
      expect(amountText(tester), '400000');
      expect(find.text('400.000 đ'), findsOneWidget);
    });

    testWidgets('empty và 0 → Lưu bị khoá, không gọi Use Case', (tester) async {
      fakeRepo.seed([_expenseTx(amountMinor: 100000)]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

      await tester.enterText(amountField(), '');
      await tester.pump();
      expect(saveButton(tester).onPressed, isNull);
      await tester.enterText(amountField(), '0');
      await tester.pump();
      expect(saveButton(tester).onPressed, isNull);
      expect(fakeRepo.updateCalls, isEmpty);
    });

    testWidgets('007 → lưu amount = 7; bấm Lưu liên tiếp chỉ gọi Use Case 1 lần', (tester) async {
      fakeRepo.seed([_expenseTx(amountMinor: 100000)]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

      await tester.enterText(amountField(), '007');
      await tester.pump();
      final button = find.widgetWithText(ElevatedButton, 'Lưu thay đổi');
      await tester.ensureVisible(button);
      await tester.tap(button, warnIfMissed: false);
      await tester.tap(button, warnIfMissed: false);
      await tester.tap(button, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(fakeRepo.updateCalls, hasLength(1));
      expect(fakeRepo.updateCalls.single.amountMinor, 7);
    });
  });

  group('Xóa bị chặn vì làm pool âm / dính Vay-Hoàn tiền', () {
    testWidgets('DeleteWouldOverdrawException → thông báo dễ hiểu, giao dịch còn nguyên (không pop), không lộ chi tiết kỹ thuật', (tester) async {
      fakeRepo.seed([_expenseTx()]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');
      fakeRepo.nextDeleteError = const DeleteWouldOverdrawException(PoolKind.memberSavingsAsset, 'x|vo');

      await tester.tap(find.text('Xóa giao dịch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xóa').last);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Giao dịch này chưa thể xóa vì số tiền đã được sử dụng ở giao dịch sau.'),
        findsOneWidget,
      );
      expect(find.byType(TransactionDetailScreen), findsOneWidget, reason: 'ở lại màn chi tiết');
      for (final leak in ['memberSavingsAsset', 'x|vo', 'pool', 'ledger', 'foreign']) {
        expect(find.textContaining(leak), findsNothing, reason: leak);
      }
    });
  });

  group('Giao dịch đang cản (xóa/sửa làm số dư âm) → cho mở đúng giao dịch', () {
    testWidgets('Xóa bị chặn có danh sách cản: hiện ngày · số tiền và [Mở giao dịch] mở đúng giao dịch đó', (tester) async {
      fakeRepo.seed([_expenseTx(), _expenseTx(id: 'later', amountMinor: 600000)]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');
      fakeRepo.nextDeleteError = const DeleteWouldOverdrawException(
        PoolKind.memberAvailable,
        'vo',
        blockingTransactionIds: ['later'],
      );

      await tester.tap(find.text('Xóa giao dịch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xóa').last);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('blocking_transactions_dialog')), findsOneWidget);
      expect(find.textContaining('Giao dịch này chưa thể xóa vì số tiền đã được sử dụng ở giao dịch sau.'), findsOneWidget);
      expect(find.textContaining('600.000'), findsOneWidget);

      await tester.tap(find.byKey(const Key('open_blocker_later')));
      await tester.pumpAndSettle();

      final screens = tester.widgetList<TransactionDetailScreen>(find.byType(TransactionDetailScreen)).toList();
      expect(screens.last.transactionId, 'later');
    });

    testWidgets('Dòng giao dịch cản hiện đúng thành viên (Vợ / Chồng) và [Mở giao dịch] mở đúng giao dịch', (tester) async {
      final wife = _expenseTx(id: 'wife-tx', amountMinor: 300000);
      final husband = _expenseTx(id: 'husband-tx', amountMinor: 450000, sourceRefId: 'chong');
      fakeRepo.seed([_expenseTx(), wife, husband]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');
      fakeRepo.nextDeleteError = const DeleteWouldOverdrawException(
        PoolKind.memberAvailable,
        'vo',
        blockingTransactionIds: ['wife-tx', 'husband-tx'],
      );

      await tester.tap(find.text('Xóa giao dịch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xóa').last);
      await tester.pumpAndSettle();

      Text header(String id) => tester.widget<Text>(find.byKey(Key('blocker_header_$id')));
      expect(header('wife-tx').data, '01/09/2026 · Vợ');
      expect(header('husband-tx').data, '01/09/2026 · Chồng');
      expect(tester.widget<Text>(find.byKey(const Key('blocker_amount_husband-tx'))).data, '450.000 đ');

      await tester.tap(find.byKey(const Key('open_blocker_husband-tx')));
      await tester.pumpAndSettle();
      final screens = tester.widgetList<TransactionDetailScreen>(find.byType(TransactionDetailScreen)).toList();
      expect(screens.last.transactionId, 'husband-tx');
    });

    testWidgets('Sửa bị chặn (ChangeWouldOverdraw): thông báo dễ hiểu + mở giao dịch cản; không lộ thuật ngữ kỹ thuật', (tester) async {
      fakeRepo.seed([_expenseTx(), _expenseTx(id: 'later', amountMinor: 600000)]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');
      fakeRepo.nextUpdateError = const ChangeWouldOverdrawException(
        PoolKind.memberAvailable,
        'vo',
        blockingTransactionIds: ['later'],
      );

      await tester.enterText(find.byKey(const Key('detail_amount_field')), '50000');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('Không thể lưu thay đổi vì số tiền từ giao dịch này đã được sử dụng hoặc chuyển ở giao dịch khác.'), findsOneWidget);
      expect(find.byKey(const Key('open_blocker_later')), findsOneWidget);
      for (final leak in ['pool', 'ledger', 'invariant', 'memberAvailable']) {
        expect(find.textContaining(leak), findsNothing, reason: leak);
      }
    });

    testWidgets('B — có trạng thái X, chọn "Không có trạng thái" → lưu XÓA trạng thái (clear), không phải "không đổi"', (tester) async {
      fakeRepo.seed([_expenseTx(categoryId: 'cho_di', statusId: 'cho_di_da_gui')]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

      final field = find.byKey(const Key('detail_status_field'));
      expect(find.descendant(of: field, matching: find.text('ĐG')), findsOneWidget, reason: 'mở Sửa thấy X');
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Không có trạng thái').last);
      await tester.pumpAndSettle();
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(fakeRepo.updateCalls.single.status, const FieldUpdate<String>.clear());
    });

    testWidgets('D — trạng thái null, chọn X → lưu SET X', (tester) async {
      fakeRepo.seed([_expenseTx(categoryId: 'cho_di')]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

      final field = find.byKey(const Key('detail_status_field'));
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ĐG').last);
      await tester.pumpAndSettle();
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(fakeRepo.updateCalls.single.status, const FieldUpdate.set('cho_di_da_gui'));
    });

    testWidgets('E/F — đổi danh mục rồi chọn lại trạng thái: sau khi đổi danh mục ô về "Không có trạng thái", chọn bước mới của danh mục mới được set', (tester) async {
      fakeRepo.seed([_expenseTx(categoryId: 'cho_di', statusId: 'cho_di_da_gui')]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('DH').last);
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('detail_status_field'));
      expect(find.descendant(of: field, matching: find.text('Không có trạng thái')), findsOneWidget);

      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ĐD').last);
      await tester.pumpAndSettle();
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(fakeRepo.updateCalls.single.categoryId, 'dang_hien');
      expect(fakeRepo.updateCalls.single.status, const FieldUpdate.set('dang_hien_da_dang'));
    });

    testWidgets('E — cùng danh mục: giữ nguyên trạng thái hiện có khi lưu', (tester) async {
      fakeRepo.seed([_expenseTx(categoryId: 'cho_di', statusId: 'cho_di_da_gui')]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

      await tester.enterText(find.byKey(const Key('detail_amount_field')), '120000');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(fakeRepo.updateCalls.single.status, isNull, reason: 'cùng danh mục, không đụng trạng thái → giữ nguyên');
    });

    testWidgets('Giao dịch chưa có trạng thái ở danh mục có trạng thái: hiện "Không có trạng thái" (không tự chọn bước đầu) và lưu vẫn null', (tester) async {
      fakeRepo.seed([_expenseTx(categoryId: 'cho_di')]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

      final field = find.byKey(const Key('detail_status_field'));
      expect(find.descendant(of: field, matching: find.text('Không có trạng thái')), findsOneWidget);
      expect(find.descendant(of: field, matching: find.text('CCB')), findsNothing);

      await _tapSave(tester);
      await tester.pumpAndSettle();
      expect(fakeRepo.updateCalls.single.status, isNull, reason: 'trạng thái vốn null, không đổi');
    });

    testWidgets('G — đổi sang danh mục khác CÓ trạng thái: về "Không có trạng thái", không tự chọn bước của danh mục mới', (tester) async {
      fakeRepo.seed([_expenseTx(categoryId: 'cho_di', statusId: 'cho_di_da_gui')]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('DH').last);
      await tester.pumpAndSettle();

      final field = find.byKey(const Key('detail_status_field'));
      expect(find.descendant(of: field, matching: find.text('Không có trạng thái')), findsOneWidget);
      await _tapSave(tester);
      await tester.pumpAndSettle();
      expect(fakeRepo.updateCalls.single.categoryId, 'dang_hien');
      expect(fakeRepo.updateCalls.single.status, const FieldUpdate<String>.clear());
    });

    testWidgets('Đổi danh mục: trạng thái cũ bị xóa ngay và lưu KHÔNG mang trạng thái cũ', (tester) async {
      fakeRepo.seed([_expenseTx(categoryId: 'cho_di', statusId: 'cho_di_da_gui')]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sinh hoạt').last);
      await tester.pumpAndSettle();
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(fakeRepo.updateCalls.single.categoryId, 'sinh_hoat');
      expect(fakeRepo.updateCalls.single.status, const FieldUpdate<String>.clear());
    });
  });

  group('Xóa thật — câu chữ và chặn', () {
    testWidgets('Hộp thoại xác nhận dùng câu chữ "Xóa" (không còn "hoàn tác")', (tester) async {
      fakeRepo.seed([_expenseTx()]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');
      await tester.tap(find.text('Xóa giao dịch'));
      await tester.pumpAndSettle();
      expect(find.text('Xóa giao dịch này?'), findsOneWidget);
      expect(find.text('Giao dịch sẽ bị xóa khỏi lịch sử và số liệu sẽ được tính lại.'), findsOneWidget);
      expect(find.textContaining('hoàn tác'), findsNothing);
      expect(find.textContaining('Hoàn tác'), findsNothing);
      // Huỷ thì không xóa.
      await tester.tap(find.text('Huỷ'));
      await tester.pumpAndSettle();
      expect(fakeRepo.deleteCalls, isEmpty);
    });

    for (final reason in DeleteBlockReason.values) {
      testWidgets('Dính ${reason.name} → thông báo dễ hiểu, không xóa', (tester) async {
        fakeRepo.seed([_expenseTx()]);
        await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');
        fakeRepo.nextDeleteError = TransactionDeleteBlockedException(reason);
        await tester.tap(find.text('Xóa giao dịch'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Xóa').last);
        await tester.pumpAndSettle();
        expect(
          find.textContaining(reason == DeleteBlockReason.linkedLoan ? 'khoản vay / cho vay' : 'hoàn tiền / thu hồi'),
          findsOneWidget,
        );
        expect(find.byType(TransactionDetailScreen), findsOneWidget);
      });
    }
  });

  group('Reversal path (Phase 7 mục 23)', () {
    testWidgets(
      '6/7 — Xóa gọi DeleteTransactionUseCase (xóa thật) với đúng id, pop sau thành công',
      (tester) async {
        fakeRepo.seed([_expenseTx()]);
        await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

        await tester.tap(find.text('Xóa giao dịch'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Xóa').last); // xác nhận dialog
        await tester.pumpAndSettle();

        expect(fakeRepo.deleteCalls, ['tx1']);
        expect(
          find.byType(TransactionDetailScreen),
          findsNothing,
          reason: 'màn hình pop sau khi xoá thành công',
        );
      },
    );

    testWidgets('8 — double tap Xoá không gửi 2 request đồng thời', (
      tester,
    ) async {
      fakeRepo.seed([_expenseTx()]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

      fakeRepo.pendingGate = Completer<void>();
      await tester.tap(find.text('Xóa giao dịch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xóa').last);
      await tester.pump(); // build lại với _submitting = true, chưa settle.

      // Nút "Xóa giao dịch" giờ đã bị disable (onPressed: null khi _submitting).
      await tester.tap(find.text('Xóa giao dịch'), warnIfMissed: false);
      await tester.pump();

      expect(fakeRepo.deleteCalls, hasLength(1));

      fakeRepo.pendingGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('9 — giao dịch không còn tồn tại khi Xóa → message an toàn, không crash', (
      tester,
    ) async {
      fakeRepo.seed([_expenseTx()]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

      fakeRepo.nextDeleteError = const TransactionNotFoundException('tx1');
      await tester.tap(find.text('Xóa giao dịch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xóa').last);
      await tester.pumpAndSettle();

      expect(
        find.text('Giao dịch không còn tồn tại — có thể đã bị xoá ở nơi khác.'),
        findsOneWidget,
      );
      expect(find.textContaining('Exception'), findsNothing);
      expect(
        find.byType(TransactionDetailScreen),
        findsOneWidget,
        reason: 'không pop khi lỗi',
      );
    });
  });

  group('Not found / persistence error (Phase 7 mục 25/26)', () {
    testWidgets(
      'TransactionNotFoundException khi Lưu → message an toàn, không crash',
      (tester) async {
        fakeRepo.seed([_expenseTx()]);
        await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

        fakeRepo.nextUpdateError = const TransactionNotFoundException('tx1');
        await _tapSave(tester);
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Giao dịch không còn tồn tại — có thể đã bị xoá ở nơi khác.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Lưu thay đổi'),
          findsOneWidget,
          reason: 'submitting reset, nút dùng lại được',
        );
      },
    );

    testWidgets(
      'PersistenceException khi Lưu → message an toàn, không lộ SQLite',
      (tester) async {
        fakeRepo.seed([_expenseTx()]);
        await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

        fakeRepo.nextUpdateError = const PersistenceException(
          'chi tiết kỹ thuật',
        );
        await _tapSave(tester);
        await tester.pumpAndSettle();

        expect(
          find.text('Có lỗi khi lưu dữ liệu, vui lòng thử lại.'),
          findsOneWidget,
        );
        expect(find.textContaining('Sqlite'), findsNothing);
        expect(find.textContaining('chi tiết kỹ thuật'), findsNothing);
      },
    );

    testWidgets('PersistenceConstraintException khi Lưu → message an toàn', (
      tester,
    ) async {
      fakeRepo.seed([_expenseTx()]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

      fakeRepo.nextUpdateError = const PersistenceConstraintException(
        kind: PersistenceConstraintKind.foreignKey,
        message: 'chi tiết constraint',
      );
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(
        find.text('Dữ liệu tham chiếu không hợp lệ, vui lòng thử lại.'),
        findsOneWidget,
      );
    });

    testWidgets('InsufficientBalanceException khi Lưu → message an toàn', (
      tester,
    ) async {
      fakeRepo.seed([_expenseTx()]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

      fakeRepo.nextUpdateError = const InsufficientBalanceException(
        poolKind: PoolKind.memberAvailable,
        refId: 'vo',
        currentBalance: 0,
        requestedAmount: 100000,
      );
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(find.text('Số dư không đủ để lưu thay đổi này.'), findsOneWidget);
    });
  });

  group('Source of truth / stale transaction (Phase 7 mục 8/27)', () {
    testWidgets(
      'giao dịch bị reverse "ở nơi khác" (fake emit lại qua stream) → màn tự chuyển sang "đã bị xoá" mà không cần thao tác gì',
      (tester) async {
        fakeRepo.seed([_expenseTx()]);
        await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

        expect(find.text('Giao dịch này đã bị xoá.'), findsNothing);

        // Mô phỏng: Repository/Drift stream emit lại vì giao dịch vừa bị
        // reverse ở nơi khác (không có action nào từ CHÍNH màn hình này).
        fakeRepo.seed([_expenseTx(reversedByTxId: 'rev1')]);
        await tester.pumpAndSettle();

        expect(find.text('Giao dịch này đã bị xoá.'), findsOneWidget);
      },
    );
  });

  group('Phase 8.8 simplification — Hoàn tiền / Thu hồi ẩn mặc định', () {
    testWidgets('mặc định KHÔNG có nút "Hoàn tiền / Thu hồi", nhưng Sửa/Xoá vẫn có', (tester) async {
      fakeRepo.seed([_expenseTx()]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');
      expect(find.widgetWithText(OutlinedButton, 'Hoàn tiền / Thu hồi'), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Lưu thay đổi'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Xóa giao dịch'), findsOneWidget);
    });

    testWidgets('giao dịch cũ đã có recovery vẫn hiện thẻ "Đã thu hồi" (tương thích lịch sử), không lỗi', (tester) async {
      final expense = _expenseTx(amountMinor: 2000000);
      final recovery = _recoveryTx(recoveryOfTxId: expense.id, amountMinor: 450000);
      fakeRepo.seed([expense, recovery]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: expense.id);
      expect(find.textContaining('Đã thu hồi'), findsWidgets);
      expect(find.widgetWithText(OutlinedButton, 'Hoàn tiền / Thu hồi'), findsNothing);
    });
  });

  group('Phase 8.6 — Hoàn tiền / Thu hồi', () {
    testWidgets('nút "Hoàn tiền / Thu hồi" hiện với giao dịch Chi hợp lệ', (
      tester,
    ) async {
      fakeRepo.seed([_expenseTx()]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1', advancedFeatures: true);
      expect(
        find.widgetWithText(OutlinedButton, 'Hoàn tiền / Thu hồi'),
        findsOneWidget,
      );
    });

    testWidgets('nút KHÔNG hiện với giao dịch Thu (không phải target hợp lệ)', (
      tester,
    ) async {
      fakeRepo.seed([_incomeTx()]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'income1', advancedFeatures: true);
      expect(
        find.widgetWithText(OutlinedButton, 'Hoàn tiền / Thu hồi'),
        findsNothing,
      );
    });

    testWidgets(
      'nút KHÔNG hiện với giao dịch CHÍNH NÓ đã là 1 recovery (chống chain)',
      (tester) async {
        final expense = _expenseTx();
        final recovery = _recoveryTx(recoveryOfTxId: expense.id);
        fakeRepo.seed([expense, recovery]);
        await _pumpDetail(
          tester,
          fakeRepo: fakeRepo,
          transactionId: recovery.id,
          advancedFeatures: true,
        );
        expect(
          find.widgetWithText(OutlinedButton, 'Hoàn tiền / Thu hồi'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'bấm nút mở sheet Hoàn tiền, pre-linked đúng target, lưu tạo đúng recoveryOfTxId',
      (tester) async {
        final expense = _expenseTx(
          id: 'ipad',
          amountMinor: 10000000,
          note: 'Mua iPad',
        );
        fakeRepo.seed([expense]);
        await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'ipad', advancedFeatures: true);

        await tester.tap(
          find.widgetWithText(OutlinedButton, 'Hoàn tiền / Thu hồi'),
        );
        await tester.pumpAndSettle();

        // Sheet mở đúng chế độ recovery — tiêu đề đổi, banner hiện đúng target.
        expect(find.text('Hoàn tiền / Thu hồi'), findsWidgets);
        expect(
          find.text('Mua iPad'),
          findsWidgets,
          reason: 'banner hiện đúng ghi chú giao dịch gốc',
        );

        // Nhập số tiền thu hồi (2.800.000) qua ô số (bàn phím hệ thống).
        await tester.enterText(
          find.byKey(const Key('add_amount_field')),
          '2800000',
        );
        await tester.pump();
        final saveButton = find.widgetWithText(ElevatedButton, 'Lưu giao dịch');
        await tester.ensureVisible(saveButton);
        await tester.tap(saveButton, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(fakeRepo.addedTransactions, hasLength(1));
        final recovery = fakeRepo.addedTransactions.single;
        expect(recovery.type, TransactionType.income);
        expect(recovery.categoryId, 'hoan_tien_thu_hoi');
        expect(recovery.recoveryOfTxId, 'ipad');
        expect(recovery.amountMinor, 2800000);
        expect(recovery.sourceKind, PoolKind.external);
        expect(recovery.destinationKind, PoolKind.memberAvailable);
      },
    );

    testWidgets(
      'có recovery đang hiệu lực → hiện "Đã thu hồi"/"Chi phí ròng" đúng số',
      (tester) async {
        final expense = _expenseTx(id: 'ipad', amountMinor: 10000000);
        final recovery = _recoveryTx(
          id: 'r1',
          recoveryOfTxId: expense.id,
          amountMinor: 2800000,
        );
        fakeRepo.seed([expense, recovery]);
        await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'ipad', advancedFeatures: true);

        expect(find.textContaining('Đã thu hồi'), findsOneWidget);
        expect(find.text('2.800.000 đ'), findsOneWidget);
        expect(find.textContaining('Chi phí ròng'), findsOneWidget);
        expect(find.text('7.200.000 đ'), findsOneWidget);
      },
    );

    testWidgets(
      'recovery ĐÃ bị reverse → KHÔNG hiện card "Đã thu hồi" (loại theo isVisible)',
      (tester) async {
        final expense = _expenseTx(id: 'ipad', amountMinor: 10000000);
        final recovery = _recoveryTx(
          id: 'r1',
          recoveryOfTxId: expense.id,
          amountMinor: 2800000,
        );
        final reversedRecovery = Transaction(
          id: recovery.id,
          type: recovery.type,
          categoryId: recovery.categoryId,
          sourceKind: recovery.sourceKind,
          destinationKind: recovery.destinationKind,
          destinationRefId: recovery.destinationRefId,
          amountMinor: recovery.amountMinor,
          recoveryOfTxId: recovery.recoveryOfTxId,
          reversedByTxId: 'reversal-of-r1',
          transactionDate: recovery.transactionDate,
          createdAt: recovery.createdAt,
          clientTxId: recovery.clientTxId,
        );
        fakeRepo.seed([expense, reversedRecovery]);
        await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'ipad', advancedFeatures: true);

        expect(find.textContaining('Đã thu hồi'), findsNothing);
      },
    );
  });
}
