import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/application/currency/currency_context.dart';
import 'package:vi_nha_minh/core/constants/default_categories.dart';
import 'package:vi_nha_minh/core/constants/default_funds.dart';
import 'package:vi_nha_minh/core/constants/default_savings_asset_types.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/fund.dart';
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
import 'package:vi_nha_minh/presentation/providers/category_providers.dart';
import 'package:vi_nha_minh/presentation/providers/currency_providers.dart';
import 'package:vi_nha_minh/presentation/providers/fund_providers.dart';
import 'package:vi_nha_minh/presentation/providers/savings_asset_type_providers.dart';
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
    this.statusId,
  });

  final String transactionId;
  final int? amountMinor;
  final String? categoryId;
  final String? note;
  final String? memberRefId;
  final DateTime? transactionDate;
  final String? statusId;
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
    String? statusId,
  }) async {
    updateCalls.add(
      RecordedUpdateCall(
        transactionId: transactionId,
        amountMinor: amountMinor,
        categoryId: categoryId,
        note: note,
        memberRefId: memberRefId,
        transactionDate: transactionDate,
        statusId: statusId,
      ),
    );
    if (pendingGate != null) await pendingGate!.future;
    if (nextUpdateError != null) {
      final err = nextUpdateError!;
      nextUpdateError = null;
      throw err;
    }
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

Transaction _expenseTx({
  String id = 'tx1',
  String categoryId = 'sinh_hoat',
  int amountMinor = 100000,
  String note = 'ghi chú cũ',
  String? statusId,
  String? reversedByTxId,
}) {
  return Transaction(
    id: id,
    type: TransactionType.expense,
    categoryId: categoryId,
    sourceKind: PoolKind.memberAvailable,
    sourceRefId: 'vo',
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
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        transactionRepositoryProvider.overrideWithValue(fakeRepo),
        categoryRepositoryProvider.overrideWithValue(
          _StaticCategoryRepository(DefaultCategories.all),
        ),
        fundRepositoryProvider.overrideWithValue(
          _StaticFundRepository(DefaultFunds.all),
        ),
        savingsAssetTypeRepositoryProvider.overrideWithValue(
          _StaticSavingsAssetTypeRepository(DefaultSavingsAssetTypes.all),
        ),
        currencyContextProvider.overrideWithValue(const _TestCurrencyContext('VND')),
      ],
      child: MaterialApp(
        home: TransactionDetailScreen(transactionId: transactionId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapSave(WidgetTester tester) async {
  final button = find.widgetWithText(ElevatedButton, 'Lưu thay đổi').evaluate().isNotEmpty
      ? find.widgetWithText(ElevatedButton, 'Lưu thay đổi')
      : find.byType(ElevatedButton);
  await tester.ensureVisible(button.first);
  await tester.tap(button.first, warnIfMissed: false);
}

void main() {
  late _FakeTransactionRepository fakeRepo;

  setUp(() {
    fakeRepo = _FakeTransactionRepository();
  });

  tearDown(() async => fakeRepo.dispose());

  group('Update path (Phase 7 mục 22)', () {
    testWidgets('1 — note-only update: gọi UpdateTransactionUseCase với đúng id, amount giữ nguyên', (
      tester,
    ) async {
      fakeRepo.seed([_expenseTx()]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

      await tester.enterText(find.byType(TextField).at(1), 'ghi chú mới');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(fakeRepo.updateCalls, hasLength(1));
      final call = fakeRepo.updateCalls.single;
      expect(call.transactionId, 'tx1', reason: 'Test 4 — đúng id tới Use Case');
      expect(call.note, 'ghi chú mới');
      expect(call.amountMinor, 100000, reason: 'amount không đổi vẫn được truyền đủ (Repository tự quyết định)');
    });

    testWidgets('2 — status update (bundled trong Save) map đúng statusId', (tester) async {
      fakeRepo.seed([
        _expenseTx(categoryId: 'cho_di', statusId: 'cho_di_chua_chuan_bi'),
      ]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

      await tester.tap(find.text('CCB').first, warnIfMissed: false); // mở dropdown trạng thái
      await tester.pumpAndSettle();
      await tester.tap(find.text('ĐCB').last, warnIfMissed: false);
      await tester.pumpAndSettle();

      await _tapSave(tester);
      await tester.pumpAndSettle();

      final call = fakeRepo.updateCalls.single;
      expect(call.statusId, 'cho_di_da_chuan_bi');
      expect(
        call.amountMinor,
        100000,
        reason: 'status-only change vẫn qua UpdateTransactionUseCase (bundled), không mất field khác',
      );
    });

    testWidgets('3 — financial amount update: amountMinor mới tới đúng Use Case', (tester) async {
      fakeRepo.seed([_expenseTx(amountMinor: 100000)]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

      await tester.enterText(find.byType(TextField).first, '250000');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      final call = fakeRepo.updateCalls.single;
      expect(call.transactionId, 'tx1');
      expect(call.amountMinor, 250000);
    });
  });

  group('Reversal path (Phase 7 mục 23)', () {
    testWidgets('6/7 — Xoá gọi ReverseTransactionUseCase với đúng id, pop sau thành công', (
      tester,
    ) async {
      fakeRepo.seed([_expenseTx()]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

      await tester.tap(find.text('Xoá giao dịch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xoá').last); // xác nhận dialog
      await tester.pumpAndSettle();

      expect(fakeRepo.reverseCalls, ['tx1']);
      expect(find.byType(TransactionDetailScreen), findsNothing, reason: 'màn hình pop sau khi xoá thành công');
    });

    testWidgets('8 — double tap Xoá không gửi 2 request đồng thời', (tester) async {
      fakeRepo.seed([_expenseTx()]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

      fakeRepo.pendingGate = Completer<void>();
      await tester.tap(find.text('Xoá giao dịch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xoá').last);
      await tester.pump(); // build lại với _submitting = true, chưa settle.

      // Nút "Xoá giao dịch" giờ đã bị disable (onPressed: null khi _submitting).
      await tester.tap(find.text('Xoá giao dịch'), warnIfMissed: false);
      await tester.pump();

      expect(fakeRepo.reverseCalls, hasLength(1));

      fakeRepo.pendingGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('9 — AlreadyReversedException → message an toàn, không crash', (tester) async {
      fakeRepo.seed([_expenseTx()]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

      fakeRepo.nextReverseError = const AlreadyReversedException('tx1', 'rev1');
      await tester.tap(find.text('Xoá giao dịch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xoá').last);
      await tester.pumpAndSettle();

      expect(find.text('Giao dịch này đã được xử lý rồi, vui lòng tải lại.'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.byType(TransactionDetailScreen), findsOneWidget, reason: 'không pop khi lỗi');
    });
  });

  group('Not found / persistence error (Phase 7 mục 25/26)', () {
    testWidgets('TransactionNotFoundException khi Lưu → message an toàn, không crash', (tester) async {
      fakeRepo.seed([_expenseTx()]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

      fakeRepo.nextUpdateError = const TransactionNotFoundException('tx1');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(
        find.text('Giao dịch không còn tồn tại — có thể đã bị xoá ở nơi khác.'),
        findsOneWidget,
      );
      expect(find.text('Lưu thay đổi'), findsOneWidget, reason: 'submitting reset, nút dùng lại được');
    });

    testWidgets('PersistenceException khi Lưu → message an toàn, không lộ SQLite', (tester) async {
      fakeRepo.seed([_expenseTx()]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

      fakeRepo.nextUpdateError = const PersistenceException('chi tiết kỹ thuật');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(find.text('Có lỗi khi lưu dữ liệu, vui lòng thử lại.'), findsOneWidget);
      expect(find.textContaining('Sqlite'), findsNothing);
      expect(find.textContaining('chi tiết kỹ thuật'), findsNothing);
    });

    testWidgets('PersistenceConstraintException khi Lưu → message an toàn', (tester) async {
      fakeRepo.seed([_expenseTx()]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');

      fakeRepo.nextUpdateError = const PersistenceConstraintException(
        kind: PersistenceConstraintKind.foreignKey,
        message: 'chi tiết constraint',
      );
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(find.text('Dữ liệu tham chiếu không hợp lệ, vui lòng thử lại.'), findsOneWidget);
    });

    testWidgets('InsufficientBalanceException khi Lưu → message an toàn', (tester) async {
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

  group('Phase 8.6 — Hoàn tiền / Thu hồi', () {
    testWidgets('nút "Hoàn tiền / Thu hồi" hiện với giao dịch Chi hợp lệ', (tester) async {
      fakeRepo.seed([_expenseTx()]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'tx1');
      expect(find.widgetWithText(OutlinedButton, 'Hoàn tiền / Thu hồi'), findsOneWidget);
    });

    testWidgets('nút KHÔNG hiện với giao dịch Thu (không phải target hợp lệ)', (tester) async {
      fakeRepo.seed([_incomeTx()]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'income1');
      expect(find.widgetWithText(OutlinedButton, 'Hoàn tiền / Thu hồi'), findsNothing);
    });

    testWidgets('nút KHÔNG hiện với giao dịch CHÍNH NÓ đã là 1 recovery (chống chain)', (tester) async {
      final expense = _expenseTx();
      final recovery = _recoveryTx(recoveryOfTxId: expense.id);
      fakeRepo.seed([expense, recovery]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: recovery.id);
      expect(find.widgetWithText(OutlinedButton, 'Hoàn tiền / Thu hồi'), findsNothing);
    });

    testWidgets('bấm nút mở sheet Hoàn tiền, pre-linked đúng target, lưu tạo đúng recoveryOfTxId', (
      tester,
    ) async {
      final expense = _expenseTx(id: 'ipad', amountMinor: 10000000, note: 'Mua iPad');
      fakeRepo.seed([expense]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'ipad');

      await tester.tap(find.widgetWithText(OutlinedButton, 'Hoàn tiền / Thu hồi'));
      await tester.pumpAndSettle();

      // Sheet mở đúng chế độ recovery — tiêu đề đổi, banner hiện đúng target.
      expect(find.text('Hoàn tiền / Thu hồi'), findsWidgets);
      expect(find.text('Mua iPad'), findsWidgets, reason: 'banner hiện đúng ghi chú giao dịch gốc');

      // Nhập số tiền thu hồi (2.800.000) qua bàn phím sheet.
      for (final d in '2800000'.split('')) {
        await tester.tap(find.text(d).first);
        await tester.pump();
      }
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
    });

    testWidgets('có recovery đang hiệu lực → hiện "Đã thu hồi"/"Chi phí ròng" đúng số', (tester) async {
      final expense = _expenseTx(id: 'ipad', amountMinor: 10000000);
      final recovery = _recoveryTx(id: 'r1', recoveryOfTxId: expense.id, amountMinor: 2800000);
      fakeRepo.seed([expense, recovery]);
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'ipad');

      expect(find.textContaining('Đã thu hồi'), findsOneWidget);
      expect(find.text('2.800.000 đ'), findsOneWidget);
      expect(find.textContaining('Chi phí ròng'), findsOneWidget);
      expect(find.text('7.200.000 đ'), findsOneWidget);
    });

    testWidgets('recovery ĐÃ bị reverse → KHÔNG hiện card "Đã thu hồi" (loại theo isVisible)', (tester) async {
      final expense = _expenseTx(id: 'ipad', amountMinor: 10000000);
      final recovery = _recoveryTx(id: 'r1', recoveryOfTxId: expense.id, amountMinor: 2800000);
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
      await _pumpDetail(tester, fakeRepo: fakeRepo, transactionId: 'ipad');

      expect(find.textContaining('Đã thu hồi'), findsNothing);
    });
  });
}
