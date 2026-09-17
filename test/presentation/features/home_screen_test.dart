import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/constants/default_categories.dart';
import 'package:vi_nha_minh/core/constants/default_funds.dart';
import 'package:vi_nha_minh/core/constants/default_savings_asset_types.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/fund.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/savings_asset_type.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/repositories/category_repository.dart';
import 'package:vi_nha_minh/domain/repositories/fund_repository.dart';
import 'package:vi_nha_minh/domain/repositories/savings_asset_type_repository.dart';
import 'package:vi_nha_minh/domain/repositories/transaction_repository.dart';
import 'package:vi_nha_minh/presentation/features/home/home_screen.dart';
import 'package:vi_nha_minh/presentation/providers/category_providers.dart';
import 'package:vi_nha_minh/presentation/providers/fund_providers.dart';
import 'package:vi_nha_minh/presentation/providers/savings_asset_type_providers.dart';
import 'package:vi_nha_minh/presentation/providers/transaction_providers.dart';

/// Widget test cho Phase 8 — Trang chủ (Dashboard rút gọn). Chỉ kiểm tra
/// vòng đời render (loading/empty/error/stream update) và số hiển thị
/// KHỚP ĐÚNG với `computeFinancialSummary` — không test lại business logic
/// (đã có `test/domain/compute_financial_summary_test.dart`).
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

int _seq = 0;

Transaction _income(int amount, {String memberRefId = 'vo'}) {
  _seq++;
  return Transaction(
    id: 'tx-$_seq',
    type: TransactionType.income,
    categoryId: DefaultCategories.thuNhap.id,
    sourceKind: PoolKind.external,
    destinationKind: PoolKind.memberAvailable,
    destinationRefId: memberRefId,
    amountMinor: amount,
    transactionDate: DateTime.now(),
    createdAt: DateTime.now(),
    clientTxId: 'client-$_seq',
  );
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required _FakeTransactionRepository fakeRepo,
  List<Category>? categories,
  List<Fund>? funds,
  List<SavingsAssetType>? assetTypes,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        transactionRepositoryProvider.overrideWithValue(fakeRepo),
        categoryRepositoryProvider.overrideWithValue(
          _StaticCategoryRepository(categories ?? DefaultCategories.all),
        ),
        fundRepositoryProvider.overrideWithValue(
          _StaticFundRepository(funds ?? DefaultFunds.all),
        ),
        savingsAssetTypeRepositoryProvider.overrideWithValue(
          _StaticSavingsAssetTypeRepository(assetTypes ?? DefaultSavingsAssetTypes.all),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: HomeScreen())),
    ),
  );
}

void main() {
  late _FakeTransactionRepository fakeRepo;

  setUp(() {
    fakeRepo = _FakeTransactionRepository();
  });

  tearDown(() async {
    await fakeRepo.dispose();
  });

  testWidgets('Loading state — hiện CircularProgressIndicator trước khi stream emit', (
    tester,
  ) async {
    await _pumpHome(tester, fakeRepo: fakeRepo);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('16 — Empty ledger: mọi số về 0đ, không crash', (tester) async {
    await _pumpHome(tester, fakeRepo: fakeRepo);
    fakeRepo.emit(const []);
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('TỔNG TÀI SẢN'), findsOneWidget);
    expect(find.text('0 đ'), findsWidgets);
  });

  testWidgets('Error state — hiện thông báo lỗi, không crash app', (tester) async {
    await _pumpHome(tester, fakeRepo: fakeRepo);
    fakeRepo.errorToEmit = Exception('lỗi mô phỏng');
    fakeRepo.emit(const []);
    await tester.pumpAndSettle();

    expect(find.textContaining('Lỗi tải dữ liệu'), findsOneWidget);
  });

  testWidgets('Dữ liệu thật — Tổng tài sản trên Trang chủ khớp đúng tổng income đã ghi', (
    tester,
  ) async {
    await _pumpHome(tester, fakeRepo: fakeRepo);
    fakeRepo.emit([_income(5000000, memberRefId: 'vo'), _income(3000000, memberRefId: 'chong')]);
    await tester.pumpAndSettle();

    expect(find.text('8.000.000 đ'), findsWidgets, reason: 'Tổng tài sản = 5tr + 3tr');
  });

  testWidgets('17 — Stream update: Trang chủ tự cập nhật khi Repository emit list mới', (
    tester,
  ) async {
    await _pumpHome(tester, fakeRepo: fakeRepo);
    fakeRepo.emit([_income(1000000, memberRefId: 'vo')]);
    await tester.pumpAndSettle();
    expect(find.text('1.000.000 đ'), findsWidgets);

    fakeRepo.emit([_income(1000000, memberRefId: 'vo'), _income(4000000, memberRefId: 'chong')]);
    await tester.pumpAndSettle();

    expect(find.text('5.000.000 đ'), findsWidgets, reason: 'Tổng tài sản phải tự cập nhật thành 5tr');
  });
}
