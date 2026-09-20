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
import 'package:vi_nha_minh/domain/entities/obligation_direction.dart';
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
import 'package:vi_nha_minh/presentation/widgets/tap_guard.dart';

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

  /// Đặt sổ giả (vd có tiền tiết kiệm sẵn để test Rút / Phân bổ).
  void seed(List<Transaction> ledger) {
    _all = ledger;
    _controller.add(ledger);
  }

  @override
  Future<Transaction?> getTransactionById(String id) async => null;

  @override
  Future<Transaction?> getTransactionByClientTxId(String clientTxId) async =>
      null;

  @override
  Future<int> purgeDeletedHistory(String categoryId) async => 0;

  @override
  Future<int> purgeDeletedHistoryForStatus(String statusId) async => 0;

  @override
  Future<void> deleteTransaction(String transactionId) async {}

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

List<Override> _formLookupOverrides({List<Category>? categories}) => [
  categoryRepositoryProvider.overrideWithValue(
    _StaticCategoryRepository(categories ?? DefaultCategories.all),
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
  Transaction? recoveryTarget,
  List<Category>? categories,
}) async {
  // Sheet dài (DraggableScrollableSheet + nhiều panel) không vừa viewport test
  // mặc định (800x600) — phóng to bề mặt test để mọi control (kể cả bàn
  // ở đáy) đều tap được mà không cần cuộn thủ công phức tạp.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._formLookupOverrides(categories: categories),
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
              onPressed: () => showAddTransactionSheet(
                context,
                initialType: initialType,
                recoveryTarget: recoveryTarget,
              ),
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

/// Vợ đang có 500.000 ở "Gửi ngân hàng" (số dư ban đầu vào pool tiết kiệm).
List<Transaction> _voBankSavings() => [
  Transaction(
    id: 'seed-bank',
    type: TransactionType.income,
    categoryId: 'so_du_ban_dau',
    sourceKind: PoolKind.external,
    destinationKind: PoolKind.memberSavingsAsset,
    destinationRefId: savingsAssetRefId(DefaultSavingsAssetTypes.bankId, FamilyMember.vo),
    amountMinor: 500000,
    transactionDate: DateTime(2026, 9, 1),
    createdAt: DateTime(2026, 9, 1),
    clientTxId: 'seed-bank-client',
  ),
];

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

/// Nhập số tiền qua ô số (bàn phím hệ thống) — nối thêm [digits] vào giá trị
/// hiện có, giữ ngữ nghĩa cũ của helper (mỗi lần gọi = gõ thêm chữ số).
Future<void> _typeDigits(WidgetTester tester, String digits) async {
  final field = find.byKey(const Key('add_amount_field'));
  await tester.ensureVisible(field);
  final current = tester.widget<TextField>(field).controller!.text;
  await tester.enterText(field, current + digits);
  await tester.pump();
}

Future<void> _typeNote(WidgetTester tester, String text) async {
  final field = find.byKey(const Key('add_note_field'));
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, text);
  await tester.pump();
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

  tearDown(() async {
    await fakeRepo.dispose();
  });

  group('F9 — Ghi chú tự do: mọi luồng trong sheet đều lưu được note', () {
    const note = 'Trả lương giáo viên';

    testWidgets('Ô Ghi chú (không bắt buộc) là ô trống đơn giản: KHÔNG có chip gợi ý, KHÔNG có câu ví dụ', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chi);

      expect(find.text('GHI CHÚ (KHÔNG BẮT BUỘC)'), findsOneWidget);
      final field = tester.widget<TextField>(find.byKey(const Key('add_note_field')));
      expect(field.controller!.text, isEmpty);
      expect(field.decoration!.hintText, isNull, reason: 'không hiển thị ví dụ');
      expect(find.textContaining('Ví dụ'), findsNothing);
      for (final chip in ['Chợ', 'Xăng xe', 'Cà phê', 'Hoá đơn']) {
        expect(find.text(chip), findsNothing, reason: 'chip "$chip" đã bỏ');
      }
    });

    testWidgets('Không nhập note: lưu bình thường với note rỗng (không bắt buộc)', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chi);
      await _selectDropdown(tester, 'Chọn danh mục', 'Sinh hoạt');
      await _typeDigits(tester, '10000');
      await _tapSave(tester);
      await tester.pumpAndSettle();
      expect(fakeRepo.lastAdded!.note, '');
    });

    testWidgets('Chi: note tự do được lưu, khoảng trắng đầu/cuối được cắt, không đổi loại giao dịch', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chi);
      await _tapSegment(tester, 'Chi phí kinh doanh');
      await _selectDropdown(tester, 'Chọn danh mục', 'Chi phí kinh doanh');
      await _typeNote(tester, '  $note  ');
      await _typeDigits(tester, '1000000');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      final tx = fakeRepo.lastAdded!;
      expect(tx.note, note);
      expect(tx.categoryId, 'chi_phi_kinh_doanh');
      expect(tx.type, TransactionType.expense);
      expect(tx.amountMinor, 1000000);
    });

    testWidgets('Thu: note tự do được lưu', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.thu);
      await _selectDropdown(tester, 'Chọn danh mục', 'Thu nhập');
      await _typeNote(tester, 'HP lớp Excel');
      await _typeDigits(tester, '2000000');
      await _tapSave(tester);
      await tester.pumpAndSettle();
      expect(fakeRepo.lastAdded!.note, 'HP lớp Excel');
      expect(fakeRepo.lastAdded!.type, TransactionType.income);
    });

    testWidgets('Chuyển Vợ ↔ Chồng: note được lưu', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chuyen);
      await _typeNote(tester, 'Đưa tiền chợ');
      await _typeDigits(tester, '80000');
      await _tapSave(tester);
      await tester.pumpAndSettle();
      expect(fakeRepo.lastAdded!.transferKind, TransferKind.memberToMember);
      expect(fakeRepo.lastAdded!.note, 'Đưa tiền chợ');
    });

    testWidgets('Tiết kiệm nạp: note được lưu', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chuyen);
      await _tapSegment(tester, 'Tiết kiệm');
      await _typeNote(tester, 'Gửi kỳ hạn 6 tháng');
      await _typeDigits(tester, '100000');
      await _tapSave(tester);
      await tester.pumpAndSettle();
      expect(fakeRepo.lastAdded!.transferKind, TransferKind.savingsTopup);
      expect(fakeRepo.lastAdded!.note, 'Gửi kỳ hạn 6 tháng');
    });

    testWidgets('Tiết kiệm rút: note được lưu', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chuyen);
      fakeRepo.seed(_voBankSavings());
      await tester.pumpAndSettle();
      await _tapSegment(tester, 'Tiết kiệm');
      await _tapSegment(tester, 'Rút về số dư');
      await _selectDropdown(tester, 'Chọn nguồn', 'Gửi ngân hàng · 500.000 đ');
      await _typeNote(tester, 'Rút chi tiêu tháng 9');
      await _typeDigits(tester, '20000');
      await _tapSave(tester);
      await tester.pumpAndSettle();
      expect(fakeRepo.lastAdded!.transferKind, TransferKind.savingsWithdraw);
      expect(fakeRepo.lastAdded!.note, 'Rút chi tiêu tháng 9');
    });

    testWidgets('Tiết kiệm chuyển đổi: note được lưu', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chuyen);
      fakeRepo.seed(_voBankSavings());
      await tester.pumpAndSettle();
      await _tapSegment(tester, 'Tiết kiệm');
      await _tapSegment(tester, 'Phân bổ');
      await _selectDropdown(tester, 'Chọn nguồn', 'Gửi ngân hàng · 500.000 đ');
      await _selectDropdown(tester, 'Chọn nơi phân bổ', 'Vàng · 0 đ');
      await _typeNote(tester, 'Mua vàng');
      await _typeDigits(tester, '70000');
      await _tapSave(tester);
      await tester.pumpAndSettle();
      expect(fakeRepo.lastAdded!.transferKind, TransferKind.savingsConvert);
      expect(fakeRepo.lastAdded!.note, 'Mua vàng');
    });

    testWidgets('Quỹ nạp: note được lưu', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chuyen);
      await _tapSegment(tester, 'Nạp quỹ');
      await _selectFundByType(tester, DefaultFunds.anUong.name);
      await _typeNote(tester, 'Nạp quỹ tháng 9');
      await _typeDigits(tester, '50000');
      await _tapSave(tester);
      await tester.pumpAndSettle();
      expect(fakeRepo.lastAdded!.transferKind, TransferKind.fundTopup);
      expect(fakeRepo.lastAdded!.note, 'Nạp quỹ tháng 9');
    });

    testWidgets('Quỹ rút: note được lưu', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chuyen);
      await _tapSegment(tester, 'Nạp quỹ');
      await _tapSegment(tester, 'Rút khỏi quỹ');
      await _selectFundByType(tester, DefaultFunds.anUong.name);
      await _typeNote(tester, 'Rút chi mua sắm');
      await _typeDigits(tester, '50000');
      await _tapSave(tester);
      await tester.pumpAndSettle();
      expect(fakeRepo.lastAdded!.transferKind, TransferKind.fundWithdraw);
      expect(fakeRepo.lastAdded!.note, 'Rút chi mua sắm');
    });

    testWidgets('Hoàn tiền / Thu hồi: note được lưu, quan hệ recoveryOfTxId vẫn đúng', (tester) async {
      final target = Transaction(
        id: 'ipad-expense',
        type: TransactionType.expense,
        categoryId: 'dau_tu',
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: 10000000,
        note: 'Mua iPad',
        transactionDate: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        clientTxId: 'client-ipad-expense',
      );
      await _pumpSheet(tester, fakeRepo: fakeRepo, recoveryTarget: target);
      await _typeNote(tester, 'Bán lại cho anh Minh');
      await _typeDigits(tester, '2800000');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      final tx = fakeRepo.lastAdded!;
      expect(tx.note, 'Bán lại cho anh Minh');
      expect(tx.recoveryOfTxId, 'ipad-expense');
      expect(tx.amountMinor, 2800000);
    });

    testWidgets('Sửa note sau khi lưu lỗi → command MỚI (note là một phần của yêu cầu)', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chi);
      await _selectDropdown(tester, 'Chọn danh mục', 'Sinh hoạt');
      await _typeNote(tester, 'Lần 1');
      await _typeDigits(tester, '10000');
      fakeRepo.nextAddError = const PersistenceException('lỗi mô phỏng');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      await _typeNote(tester, 'Lần 2');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(fakeRepo.addedClientTxIds, hasLength(2));
      expect(fakeRepo.addedClientTxIds[0], isNot(fakeRepo.addedClientTxIds[1]));
      expect(fakeRepo.lastAdded!.note, 'Lần 2');
    });
  });

  group('F30 — status ẩn không chọn được cho giao dịch mới', () {
    testWidgets('Bộ chọn trạng thái khi tạo Chi CĐ chỉ có bước ĐANG DÙNG, không có bước đã ẩn', (tester) async {
      await _pumpSheet(
        tester,
        fakeRepo: fakeRepo,
        initialType: EntryType.chi,
        categories: _categoriesWithHiddenDcb(),
      );

      await _selectDropdown(tester, 'Chọn danh mục', 'CĐ');
      // Trạng thái mặc định = bước đang dùng đầu tiên (CCB).
      await tester.tap(find.text('CCB').first, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('ĐCB'), findsNothing, reason: 'bước đã ẩn không được chọn cho giao dịch mới');
      expect(find.text('ĐG'), findsWidgets);
    });
  });

  group('Flow mapping (Phase 6 mục 28/29)', () {
    testWidgets('1 — EXPENSE: category + amount map đúng', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chi);

      await _selectDropdown(tester, 'Chọn danh mục', 'Sinh hoạt');
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

      await _selectDropdown(tester, 'Chọn danh mục', 'Thu nhập');
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

    testWidgets('3.1 — FUND_WITHDRAW: transfer → rút khỏi quỹ map đúng (Phase 7.1)', (
      tester,
    ) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chuyen);

      await _tapSegment(tester, 'Nạp quỹ');
      await _tapSegment(tester, 'Rút khỏi quỹ');
      await _tapSegment(tester, 'Chồng');
      await _selectFundByType(tester, DefaultFunds.anUong.name);
      await _typeDigits(tester, '50000');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      final tx = fakeRepo.lastAdded!;
      expect(tx.type, TransactionType.transfer);
      expect(tx.transferKind, TransferKind.fundWithdraw);
      expect(tx.categoryId, DefaultCategories.napQuy.id);
      expect(tx.sourceKind, PoolKind.fund, reason: 'Phase 7.1 — nguồn là Quỹ, không phải ví thành viên');
      expect(tx.sourceRefId, DefaultFunds.anUongId);
      expect(tx.destinationKind, PoolKind.memberAvailable);
      expect(tx.destinationRefId, 'chong', reason: 'người nhận phải là thành viên TỰ CHỌN, không mặc định ngầm');
      expect(tx.amountMinor, 50000);
    });

    testWidgets('3.2 — FUND_TOPUP regression: sau khi đổi qua Rút rồi đổi lại Nạp vẫn map đúng chiều cũ', (
      tester,
    ) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chuyen);

      await _tapSegment(tester, 'Nạp quỹ');
      await _tapSegment(tester, 'Rút khỏi quỹ');
      await _tapSegment(tester, 'Nạp vào quỹ');
      await _selectFundByType(tester, DefaultFunds.anUong.name);
      await _typeDigits(tester, '50000');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      final tx = fakeRepo.lastAdded!;
      expect(tx.transferKind, TransferKind.fundTopup);
      expect(tx.sourceKind, PoolKind.memberAvailable);
      expect(tx.sourceRefId, 'vo');
      expect(tx.destinationKind, PoolKind.fund);
      expect(tx.destinationRefId, DefaultFunds.anUongId);
    });

    testWidgets('4 — Fund-backed EXPENSE: source = FUND, không phải MEMBER_AVAILABLE', (
      tester,
    ) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chi);

      await _selectDropdown(tester, 'Chọn danh mục', 'Sinh hoạt');
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
      expect(find.text('Chọn loại tài sản'), findsNothing, reason: 'Thêm vào tiết kiệm KHÔNG hỏi loại tài sản');
      await _typeDigits(tester, '100000');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      final tx = fakeRepo.lastAdded!;
      expect(tx.type, TransactionType.transfer);
      expect(tx.transferKind, TransferKind.savingsTopup);
      expect(tx.sourceKind, PoolKind.memberAvailable);
      expect(tx.sourceRefId, 'vo');
      expect(tx.destinationKind, PoolKind.memberSavingsAsset);
      expect(
        tx.destinationRefId,
        savingsAssetRefId(SystemSavingsAssets.unallocatedId, FamilyMember.vo),
        reason: 'mặc định vào "Chưa phân bổ"',
      );
      expect(tx.amountMinor, 100000);
    });

    testWidgets('6 — SAVINGS_WITHDRAW map đúng', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chuyen);

      fakeRepo.seed(_voBankSavings());
      await tester.pumpAndSettle();
      await _tapSegment(tester, 'Tiết kiệm');
      await _tapSegment(tester, 'Rút về số dư');
      await _selectDropdown(tester, 'Chọn nguồn', 'Gửi ngân hàng · 500.000 đ');
      await _typeDigits(tester, '20000');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      final tx = fakeRepo.lastAdded!;
      expect(tx.type, TransactionType.transfer);
      expect(tx.transferKind, TransferKind.savingsWithdraw);
      expect(tx.sourceKind, PoolKind.memberSavingsAsset);
      expect(tx.sourceRefId, savingsAssetRefId(DefaultSavingsAssetTypes.bankId, FamilyMember.vo));
      expect(tx.destinationKind, PoolKind.memberAvailable);
      expect(tx.destinationRefId, 'vo');
      expect(tx.amountMinor, 20000);
    });

    testWidgets('7 — SAVINGS_CONVERT map đúng', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chuyen);

      fakeRepo.seed(_voBankSavings());
      await tester.pumpAndSettle();
      await _tapSegment(tester, 'Tiết kiệm');
      await _tapSegment(tester, 'Phân bổ');
      await _selectDropdown(tester, 'Chọn nguồn', 'Gửi ngân hàng · 500.000 đ');
      await _selectDropdown(tester, 'Chọn nơi phân bổ', 'Vàng · 0 đ');
      await _typeDigits(tester, '70000');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      final tx = fakeRepo.lastAdded!;
      expect(tx.type, TransactionType.transfer);
      expect(tx.transferKind, TransferKind.savingsConvert);
      expect(tx.sourceKind, PoolKind.memberSavingsAsset);
      expect(tx.sourceRefId, savingsAssetRefId(DefaultSavingsAssetTypes.bankId, FamilyMember.vo));
      expect(tx.destinationKind, PoolKind.memberSavingsAsset);
      expect(tx.destinationRefId, savingsAssetRefId(DefaultSavingsAssetTypes.goldId, FamilyMember.vo));
      expect(tx.amountMinor, 70000);
    });

    testWidgets('Phân bổ: nguồn chỉ liệt kê dòng CÒN TIỀN; đích gồm Chưa phân bổ + loại đang dùng, KHÔNG có nguồn và loại đã ngừng', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chuyen);
      fakeRepo.seed(_voBankSavings());
      await tester.pumpAndSettle();
      await _tapSegment(tester, 'Tiết kiệm');
      await _tapSegment(tester, 'Phân bổ');

      await _selectDropdown(tester, 'Chọn nguồn', 'Gửi ngân hàng · 500.000 đ');
      // Mở dropdown đích và đọc các lựa chọn.
      final field = find.text('Chọn nơi phân bổ').first;
      await tester.ensureVisible(field);
      await tester.tap(field, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Chưa phân bổ · 0 đ'), findsWidgets);
      expect(find.text('Vàng · 0 đ'), findsWidgets);
      expect(find.text('Gửi ngân hàng · 500.000 đ'), findsOneWidget, reason: 'chỉ còn ô Nguồn đang chọn; KHÔNG có trong danh sách đích (không phân bổ vào chính nguồn)');
    });

    testWidgets('Rút: chỉ thấy nguồn còn tiền — nếu chưa có tiền tiết kiệm thì báo, Lưu bị khoá', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chuyen);
      await _tapSegment(tester, 'Tiết kiệm');
      await _tapSegment(tester, 'Rút về số dư');
      expect(find.text('Chưa có khoản tiết kiệm nào'), findsOneWidget);
      await _typeDigits(tester, '1000');
      final save = find.byType(ElevatedButton).last;
      expect(tester.widget<ElevatedButton>(save).onPressed, isNull);
    });

    testWidgets('Đổi thành viên trong panel Tiết kiệm xoá nguồn đã chọn (không lẫn Vợ ↔ Chồng)', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chuyen);
      fakeRepo.seed(_voBankSavings());
      await tester.pumpAndSettle();
      await _tapSegment(tester, 'Tiết kiệm');
      await _tapSegment(tester, 'Rút về số dư');
      await _selectDropdown(tester, 'Chọn nguồn', 'Gửi ngân hàng · 500.000 đ');
      await _typeDigits(tester, '1000');
      await _tapSegment(tester, 'Chồng');
      // Chồng không có tiền tiết kiệm: nguồn cũ của Vợ bị bỏ, không thể lưu.
      expect(find.text('Chưa có khoản tiết kiệm nào'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton).last).onPressed, isNull);
    });

    testWidgets('SavingsMemberMismatchException → thông báo dễ hiểu, không lộ chi tiết', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chuyen);
      await _tapSegment(tester, 'Tiết kiệm');
      await _typeDigits(tester, '1000');
      fakeRepo.nextAddError = const SavingsMemberMismatchException('savingsTopup');
      await _tapSave(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('phải cùng một người'), findsOneWidget);
      expect(find.textContaining('savingsTopup'), findsNothing);
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

      await _selectDropdown(tester, 'Chọn danh mục', 'Thu nhập');
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

      await _selectDropdown(tester, 'Chọn danh mục', 'Thu nhập');
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
      await _selectDropdown(tester, 'Chọn danh mục', 'Thu nhập');
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
      await _selectDropdown(tester, 'Chọn danh mục', 'Thu nhập');
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
      await _selectDropdown(tester, 'Chọn danh mục', 'Thu nhập');
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

  group('Fund Withdraw — retry/edit/double-submit (Phase 7.1, dùng chung Phase 6 lifecycle)', () {
    Future<void> setUpFundWithdrawForm(WidgetTester tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chuyen);
      await _tapSegment(tester, 'Nạp quỹ');
      await _tapSegment(tester, 'Rút khỏi quỹ');
      await _selectFundByType(tester, DefaultFunds.anUong.name);
      await _typeDigits(tester, '50000');
    }

    testWidgets('35 — retry sau lỗi transient, KHÔNG đổi form → giữ nguyên clientTxId', (
      tester,
    ) async {
      await setUpFundWithdrawForm(tester);

      fakeRepo.nextAddError = const PersistenceException('lỗi mô phỏng lần 1');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(fakeRepo.addedClientTxIds, hasLength(1));
      expect(fakeRepo.lastAdded, isNull);

      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(fakeRepo.addedClientTxIds, hasLength(2));
      expect(
        fakeRepo.addedClientTxIds[0],
        fakeRepo.addedClientTxIds[1],
        reason: 'retry phải tái sử dụng đúng clientTxId cũ',
      );
      expect(fakeRepo.lastAdded!.transferKind, TransferKind.fundWithdraw);
      expect(fakeRepo.lastAdded!.sourceRefId, DefaultFunds.anUongId);
      expect(fakeRepo.lastAdded!.amountMinor, 50000);
    });

    testWidgets('36 — đổi amount sau khi fail → command/clientTxId MỚI', (tester) async {
      await setUpFundWithdrawForm(tester);

      fakeRepo.nextAddError = const PersistenceException('lỗi mô phỏng');
      await _tapSave(tester);
      await tester.pumpAndSettle();
      final firstClientTxId = fakeRepo.addedClientTxIds.single;

      await _typeDigits(tester, '1'); // 50000 -> 500001
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(fakeRepo.addedClientTxIds, hasLength(2));
      expect(fakeRepo.addedClientTxIds[1], isNot(firstClientTxId));
      expect(fakeRepo.lastAdded!.amountMinor, 500001);
    });

    testWidgets('37 — tap Save 2 lần liên tiếp khi lần đầu còn treo → chỉ 1 request', (
      tester,
    ) async {
      await setUpFundWithdrawForm(tester);

      fakeRepo.pendingGate = Completer<void>();
      await _tapSave(tester);
      await tester.pump();

      await _tapSave(tester);
      await tester.pump();

      expect(fakeRepo.addedClientTxIds, hasLength(1));

      fakeRepo.pendingGate!.complete();
      await tester.pumpAndSettle();
      expect(fakeRepo.lastAdded!.transferKind, TransferKind.fundWithdraw);
    });
  });

  group('Phase 8.6 — Recovery mode: retry/edit/double-submit (dùng chung Phase 6 lifecycle)', () {
    Transaction recoveryTargetTx() {
      return Transaction(
        id: 'ipad-expense',
        type: TransactionType.expense,
        categoryId: 'dau_tu',
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'chong',
        destinationKind: PoolKind.external,
        amountMinor: 10000000,
        note: 'Mua iPad',
        transactionDate: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        clientTxId: 'client-ipad-expense',
      );
    }

    Future<void> setUpRecoveryForm(WidgetTester tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, recoveryTarget: recoveryTargetTx());
      await _typeDigits(tester, '2800000');
    }

    testWidgets('retry sau lỗi transient, KHÔNG đổi form → giữ nguyên clientTxId', (tester) async {
      await setUpRecoveryForm(tester);

      fakeRepo.nextAddError = const PersistenceException('lỗi mô phỏng');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(fakeRepo.addedClientTxIds, hasLength(1));
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(fakeRepo.addedClientTxIds, hasLength(2));
      expect(fakeRepo.addedClientTxIds[0], fakeRepo.addedClientTxIds[1]);
      expect(fakeRepo.lastAdded!.recoveryOfTxId, 'ipad-expense');
      expect(fakeRepo.lastAdded!.amountMinor, 2800000);
    });

    testWidgets('đổi amount sau khi fail → command/clientTxId MỚI', (tester) async {
      await setUpRecoveryForm(tester);

      fakeRepo.nextAddError = const PersistenceException('lỗi mô phỏng');
      await _tapSave(tester);
      await tester.pumpAndSettle();
      final firstClientTxId = fakeRepo.addedClientTxIds.single;

      await _typeDigits(tester, '1');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(fakeRepo.addedClientTxIds, hasLength(2));
      expect(fakeRepo.addedClientTxIds[1], isNot(firstClientTxId));
      expect(fakeRepo.lastAdded!.recoveryOfTxId, 'ipad-expense', reason: 'quan hệ recovery vẫn giữ đúng target dù command mới');
    });

    testWidgets('tap Save 2 lần liên tiếp khi lần đầu còn treo → chỉ 1 request', (tester) async {
      await setUpRecoveryForm(tester);

      fakeRepo.pendingGate = Completer<void>();
      await _tapSave(tester);
      await tester.pump();
      await _tapSave(tester);
      await tester.pump();

      expect(fakeRepo.addedClientTxIds, hasLength(1));

      fakeRepo.pendingGate!.complete();
      await tester.pumpAndSettle();
      expect(fakeRepo.lastAdded!.recoveryOfTxId, 'ipad-expense');
    });

    testWidgets('InvalidRecoveryTargetException → message an toàn, không lộ chi tiết kỹ thuật', (tester) async {
      await setUpRecoveryForm(tester);
      fakeRepo.nextAddError = const InvalidRecoveryTargetException(
        reason: InvalidRecoveryReason.targetReversed,
        targetId: 'ipad-expense',
      );
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('không còn phù hợp để hoàn tiền'),
        findsOneWidget,
      );
      expect(find.textContaining('InvalidRecoveryTargetException'), findsNothing);
    });
  });

  group('F1 — lỗi hiện ngay trong bottom sheet', () {
    Future<void> failOnce(WidgetTester tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.thu);
      await _selectDropdown(tester, 'Chọn danh mục', 'Thu nhập');
      await _typeDigits(tester, '50000');
      fakeRepo.nextAddError = const InsufficientBalanceException(
        poolKind: PoolKind.memberAvailable,
        refId: 'vo',
        currentBalance: 0,
        requestedAmount: 50000,
      );
      await _tapSave(tester);
      await tester.pumpAndSettle();
    }

    testWidgets('Banner nằm trong màn hình, ngay phía trên nút Lưu, không có SnackBar', (tester) async {
      await failOnce(tester);

      final banner = find.byKey(const Key('sheet_error_banner'));
      expect(banner, findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      final bannerRect = tester.getRect(banner);
      final saveRect = tester.getRect(find.byType(ElevatedButton).first);
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(bannerRect.top, greaterThanOrEqualTo(0));
      expect(bannerRect.bottom, lessThanOrEqualTo(screen.height));
      expect(bannerRect.bottom, lessThanOrEqualTo(saveRect.top), reason: 'nằm phía trên nút Lưu');
    });

    testWidgets('Sửa số tiền → banner tự ẩn; lưu lại thành công thì sheet đóng', (tester) async {
      await failOnce(tester);
      expect(find.byKey(const Key('sheet_error_banner')), findsOneWidget);

      await _typeDigits(tester, '0'); // 50000 -> 500000: form đã đổi
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sheet_error_banner')), findsNothing);

      await _tapSave(tester);
      await tester.pumpAndSettle();
      expect(fakeRepo.lastAdded, isNotNull);
      expect(find.byType(AddTransactionSheet), findsNothing);
    });

    testWidgets('Đổi Ghi chú → banner ẩn; khôi phục đúng form lúc lỗi → banner hiện lại', (tester) async {
      await failOnce(tester);
      expect(find.byKey(const Key('sheet_error_banner')), findsOneWidget);

      await _typeNote(tester, 'a');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sheet_error_banner')), findsNothing);

      // Semantics hiện tại: banner gắn với "form intent" của lần Lưu lỗi;
      // form quay về y hệt (note rỗng) thì cùng một yêu cầu → lỗi cũ hiện lại.
      await _typeNote(tester, '');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sheet_error_banner')), findsOneWidget);
    });

    testWidgets('Đổi người nhận (Vợ → Chồng) → banner ẩn', (tester) async {
      await failOnce(tester);
      expect(find.byKey(const Key('sheet_error_banner')), findsOneWidget);
      await _tapSegment(tester, 'Chồng');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sheet_error_banner')), findsNothing);
    });

    testWidgets('Lưu lại lần nữa vẫn lỗi → banner hiện lại (không im lặng)', (tester) async {
      await failOnce(tester);
      fakeRepo.nextAddError = const InsufficientBalanceException(
        poolKind: PoolKind.memberAvailable,
        refId: 'vo',
        currentBalance: 0,
        requestedAmount: 50000,
      );
      await _tapSave(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sheet_error_banner')), findsOneWidget);
      expect(find.text('Số dư không đủ để ghi giao dịch này.'), findsOneWidget);
    });
  });

  group('R1/R2 — ô số tiền dùng bàn phím hệ thống', () {
    Finder amountField() => find.byKey(const Key('add_amount_field'));
    String amountText(WidgetTester t) =>
        t.widget<TextField>(amountField()).controller!.text;

    testWidgets('R1: không còn keypad tự vẽ; ô số dùng bàn phím số hệ thống', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.thu);
      expect(find.text('000'), findsNothing);
      expect(find.text('⌫'), findsNothing);
      final field = tester.widget<TextField>(amountField());
      expect(field.keyboardType, TextInputType.number);
      expect(field.inputFormatters, isNotEmpty);
    });

    testWidgets('chỉ nhận chữ số; bỏ số 0 đầu; xem trước định dạng đúng', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.thu);
      await tester.enterText(amountField(), 'a1b 2.3,4-5');
      await tester.pump();
      expect(amountText(tester), '12345');

      await tester.enterText(amountField(), '0001200000');
      await tester.pump();
      expect(amountText(tester), '1200000');
      expect(find.text('1.200.000 đ'), findsOneWidget);

      await tester.enterText(amountField(), '');
      await tester.pump();
      expect(find.text('0 đ'), findsOneWidget);
    });

    testWidgets('tối đa 9 chữ số (giữ giới hạn cũ)', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.thu);
      await tester.enterText(amountField(), '123456789');
      await tester.pump();
      await tester.enterText(amountField(), '1234567890');
      await tester.pump();
      expect(amountText(tester), '123456789');
    });

    testWidgets('empty và 0 → Lưu bị khoá; 007 → 7 và được lưu đúng 7', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.thu);
      await _selectDropdown(tester, 'Chọn danh mục', 'Thu nhập');
      ElevatedButton save() => tester.widget<ElevatedButton>(find.byType(ElevatedButton).first);
      expect(save().onPressed, isNull);
      await tester.enterText(amountField(), '0');
      await tester.pump();
      expect(save().onPressed, isNull);
      await tester.enterText(amountField(), '007');
      await tester.pump();
      expect(amountText(tester), '7');
      await _tapSave(tester);
      await tester.pumpAndSettle();
      expect(fakeRepo.lastAdded!.amountMinor, 7);
    });

    testWidgets('Amount ↔ Note: đổi focus không làm mất dữ liệu bên nào', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.thu);
      await tester.enterText(amountField(), '1200000');
      await tester.pump();
      await _typeNote(tester, 'HP lop Excel');
      expect(amountText(tester), '1200000');
      await tester.enterText(amountField(), '1200001');
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byKey(const Key('add_note_field'))).controller!.text,
        'HP lop Excel',
      );
      expect(amountText(tester), '1200001');
    });

    testWidgets('lưu qua ô số: amount + note đúng, sheet đóng đúng 1 lần', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.thu);
      await _selectDropdown(tester, 'Chọn danh mục', 'Thu nhập');
      await tester.enterText(amountField(), '1200000');
      await tester.pump();
      await _typeNote(tester, 'HP lop Excel');
      await _tapSave(tester);
      await tester.pumpAndSettle();
      expect(fakeRepo.lastAdded!.amountMinor, 1200000);
      expect(fakeRepo.lastAdded!.note, 'HP lop Excel');
      expect(find.byType(AddTransactionSheet), findsNothing);
    });

    testWidgets('R2: bàn phím mở → Lưu và banner lỗi vẫn nằm trên bàn phím, không bị che', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.thu);
      await _selectDropdown(tester, 'Chọn danh mục', 'Thu nhập');
      await tester.enterText(amountField(), '50000');
      await tester.pump();

      // Giả lập bàn phím hệ thống cao 1000px trên màn 2400px.
      tester.view.viewInsets = const FakeViewPadding(bottom: 1000);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      const keyboardTop = 2400.0 - 1000.0;

      final saveRect = tester.getRect(find.byType(ElevatedButton).first);
      expect(saveRect.bottom, lessThanOrEqualTo(keyboardTop), reason: 'Lưu phải nằm trên bàn phím');

      fakeRepo.nextAddError = const InsufficientBalanceException(
        poolKind: PoolKind.memberAvailable,
        refId: 'vo',
        currentBalance: 0,
        requestedAmount: 50000,
      );
      await tester.tap(find.byType(ElevatedButton).first);
      await tester.pumpAndSettle();

      final banner = find.byKey(const Key('sheet_error_banner'));
      expect(banner, findsOneWidget);
      final bannerRect = tester.getRect(banner);
      expect(bannerRect.top, greaterThanOrEqualTo(0));
      expect(bannerRect.bottom, lessThanOrEqualTo(keyboardTop), reason: 'banner phải nhìn thấy khi bàn phím mở');
      expect(find.byType(AddTransactionSheet), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('Lifecycle — R3/R4/R5 (sheet Thêm giao dịch)', () {
    Finder amountField() => find.byKey(const Key('add_amount_field'));
    Finder noteField() => find.byKey(const Key('add_note_field'));
    IconButton closeButton(WidgetTester t) =>
        t.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close_rounded));

    Future<void> fillForm(WidgetTester tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.thu);
      await _selectDropdown(tester, 'Chọn danh mục', 'Thu nhập');
      await tester.enterText(amountField(), '50000');
      await tester.pump();
      await _typeNote(tester, 'HP lop');
    }

    testWidgets('R3: kéo/vuốt xuống khi form có dữ liệu → sheet KHÔNG đóng, dữ liệu còn nguyên', (tester) async {
      await fillForm(tester);
      await tester.fling(find.byType(ListView).first, const Offset(0, 1600), 4000);
      await tester.pumpAndSettle();
      expect(find.byType(AddTransactionSheet), findsOneWidget);
      expect(tester.widget<TextField>(amountField()).controller!.text, '50000');
      expect(tester.widget<TextField>(noteField()).controller!.text, 'HP lop');
    });

    testWidgets('R3: chạm ra ngoài (barrier) không đóng sheet', (tester) async {
      await fillForm(tester);
      await tester.tapAt(const Offset(540, 20));
      await tester.pumpAndSettle();
      expect(find.byType(AddTransactionSheet), findsOneWidget);
    });

    testWidgets('IDLE: Back hệ thống và nút X vẫn đóng được sheet', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.thu);
      expect(closeButton(tester).onPressed, isNotNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AddTransactionSheet), findsNothing);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(AddTransactionSheet), findsNothing);
    });

    testWidgets('R4: đang submit → Back và nút X bị chặn; xong mới tự đóng, đúng 1 write', (tester) async {
      await fillForm(tester);
      fakeRepo.pendingGate = Completer<void>();
      await _tapSave(tester);
      await tester.pump();

      expect(closeButton(tester).onPressed, isNull, reason: 'X bị khoá khi đang submit');
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(AddTransactionSheet), findsOneWidget, reason: 'Back bị chặn khi đang submit');

      fakeRepo.pendingGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AddTransactionSheet), findsNothing);
      expect(fakeRepo.addedClientTxIds, hasLength(1));
    });

    testWidgets('R4: lỗi → trả lại quyền Back/X, sheet đóng được', (tester) async {
      await fillForm(tester);
      fakeRepo.nextAddError = const InsufficientBalanceException(
        poolKind: PoolKind.memberAvailable,
        refId: 'vo',
        currentBalance: 0,
        requestedAmount: 50000,
      );
      await _tapSave(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sheet_error_banner')), findsOneWidget);
      expect(closeButton(tester).onPressed, isNotNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AddTransactionSheet), findsNothing);
    });

    testWidgets('R5: sau khi lưu thành công, tap dư trong cửa sổ chống tap-xuyên không chạm trang bên dưới', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var underneathTaps = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._formLookupOverrides(),
            transactionRepositoryProvider.overrideWithValue(fakeRepo),
            currencyContextProvider.overrideWithValue(const _TestCurrencyContext('VND')),
          ],
          child: MaterialApp(
            builder: (context, child) => TapGuardScope(child: child!),
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    TextButton(
                      onPressed: () => showAddTransactionSheet(context, initialType: EntryType.thu),
                      child: const Text('open'),
                    ),
                    const Spacer(),
                    // Nằm ngay dưới vị trí nút Lưu — giống nút "+" của Home.
                    TextButton(
                      onPressed: () => underneathTaps++,
                      child: const Text('underneath'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await _selectDropdown(tester, 'Chọn danh mục', 'Thu nhập');
      await tester.enterText(amountField(), '50000');
      await tester.pump();

      await _tapSave(tester);
      await tester.pump(); // lưu xong → pop + bật chống tap-xuyên
      await tester.pump(const Duration(milliseconds: 50));
      expect(fakeRepo.addedClientTxIds, hasLength(1));

      // Tap dư ngay sau khi lưu (route đang đóng / vừa đóng): bị nuốt.
      await tester.tap(find.text('underneath'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('underneath'), warnIfMissed: false);
      expect(underneathTaps, 0, reason: 'không được xuyên xuống trang bên dưới');

      // Hết cửa sổ → sheet đã đóng hẳn, trang bên dưới nhận tap bình thường.
      await tester.pump(kTapGuardWindow + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(find.byType(AddTransactionSheet), findsNothing);
      await tester.tap(find.text('underneath'));
      expect(underneathTaps, 1);
    });
  });

  group('Nhóm Thu/Chi — 2 nhóm chính mỗi loại (Phase 8.8 simplification)', () {
    Finder amountField() => find.byKey(const Key('add_amount_field'));

    Future<void> openDropdown(WidgetTester tester) async {
      final field = find.text('Chọn danh mục').first;
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.tap(field, warnIfMissed: false);
      await tester.pumpAndSettle();
    }

    Future<void> closeDropdown(WidgetTester tester) async {
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    }

    testWidgets('Thu: mặc định nhóm Doanh thu chỉ liệt kê danh mục Doanh thu; Khoản thu khác liệt kê phần còn lại', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.thu);
      expect(find.text('Doanh thu'), findsOneWidget);
      expect(find.text('Khoản thu khác'), findsOneWidget);

      await openDropdown(tester);
      expect(find.text('Thu nhập'), findsWidgets);
      expect(find.text('Số dư ban đầu'), findsNothing);
      await closeDropdown(tester);

      await _tapSegment(tester, 'Khoản thu khác');
      await openDropdown(tester);
      expect(find.text('Số dư ban đầu'), findsWidgets);
      expect(find.text('Thu nhập'), findsNothing);
      await closeDropdown(tester);
    });

    testWidgets('Tính năng nâng cao (Vay, Hoàn tiền, Trả nợ…) không bao giờ có trong bộ chọn', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.thu);
      for (final other in [false, true]) {
        if (other) await _tapSegment(tester, 'Khoản thu khác');
        await openDropdown(tester);
        for (final hidden in ['Hoàn tiền / Thu hồi', 'Lãi cho vay', 'Đi vay']) {
          expect(find.text(hidden), findsNothing, reason: '$hidden phải ẩn');
        }
        await closeDropdown(tester);
      }
      await _tapSegment(tester, 'Chi');
      for (final business in [false, true]) {
        if (business) await _tapSegment(tester, 'Chi phí kinh doanh');
        await openDropdown(tester);
        expect(find.text('Trả nợ'), findsNothing);
        await closeDropdown(tester);
      }
    });

    testWidgets('Chi: Chi tiêu và Chi phí kinh doanh tách theo groupKey', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.chi);
      expect(find.text('Chi tiêu'), findsOneWidget);

      await openDropdown(tester);
      expect(find.text('Sinh hoạt'), findsWidgets);
      expect(find.text('Chi phí kinh doanh'), findsOneWidget, reason: 'chỉ là nhãn nhóm, chưa phải danh mục');
      await closeDropdown(tester);

      await _tapSegment(tester, 'Chi phí kinh doanh');
      await openDropdown(tester);
      expect(find.text('Sinh hoạt'), findsNothing);
      expect(find.text('Chi phí kinh doanh'), findsNWidgets(2), reason: 'nhãn nhóm + danh mục cùng tên');
      await closeDropdown(tester);
    });

    testWidgets('Đổi nhóm hoặc đổi loại Thu/Chi → xoá danh mục đã chọn (Lưu bị khoá, không lưu nhầm danh mục cũ)', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.thu);
      await _selectDropdown(tester, 'Chọn danh mục', 'Thu nhập');
      await tester.enterText(amountField(), '50000');
      await tester.pump();
      ElevatedButton save() => tester.widget<ElevatedButton>(find.byType(ElevatedButton).first);
      expect(save().onPressed, isNotNull);

      await _tapSegment(tester, 'Khoản thu khác');
      expect(save().onPressed, isNull, reason: 'đổi nhóm → phải chọn lại danh mục');

      await _selectDropdown(tester, 'Chọn danh mục', 'Số dư ban đầu');
      expect(save().onPressed, isNotNull);
      await _tapSegment(tester, 'Chi');
      expect(save().onPressed, isNull, reason: 'đổi Thu → Chi: không giữ danh mục Thu');
    });

    testWidgets('Lưu Khoản thu khác → giao dịch income đúng danh mục; Lưu Chi phí kinh doanh → expense đúng danh mục', (tester) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.thu);
      await _tapSegment(tester, 'Khoản thu khác');
      await _selectDropdown(tester, 'Chọn danh mục', 'Số dư ban đầu');
      await tester.enterText(amountField(), '450000');
      await tester.pump();
      await _typeNote(tester, 'Ban lai quat');
      await _tapSave(tester);
      await tester.pumpAndSettle();
      var tx = fakeRepo.lastAdded!;
      expect(tx.type, TransactionType.income);
      expect(tx.categoryId, 'so_du_ban_dau');
      expect(tx.amountMinor, 450000);
      expect(tx.note, 'Ban lai quat');

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await _tapSegment(tester, 'Chi');
      await _tapSegment(tester, 'Chi phí kinh doanh');
      await _selectDropdown(tester, 'Chọn danh mục', 'Chi phí kinh doanh');
      await tester.enterText(amountField(), '700000');
      await tester.pump();
      await _tapSave(tester);
      await tester.pumpAndSettle();
      tx = fakeRepo.lastAdded!;
      expect(tx.type, TransactionType.expense);
      expect(tx.categoryId, 'chi_phi_kinh_doanh');
      expect(tx.amountMinor, 700000);
    });
  });

  group('Error presentation (Phase 6 mục 34)', () {
    Future<void> expectError(
      WidgetTester tester,
      Object error,
      String expectedMessage,
    ) async {
      await _pumpSheet(tester, fakeRepo: fakeRepo, initialType: EntryType.thu);
      await _selectDropdown(tester, 'Chọn danh mục', 'Thu nhập');
      await _typeDigits(tester, '50000');

      fakeRepo.nextAddError = error;
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(find.text(expectedMessage), findsOneWidget);
      // F1: lỗi phải nằm TRONG sheet (không phải SnackBar bị che sau lớp modal).
      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.descendant(of: find.byType(AddTransactionSheet), matching: find.text(expectedMessage)),
        findsOneWidget,
        reason: 'thông báo lỗi phải là một phần của chính bottom sheet',
      );
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
      await _selectDropdown(tester, 'Chọn danh mục', 'Thu nhập');
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
