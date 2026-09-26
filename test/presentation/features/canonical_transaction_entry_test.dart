import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vi_nha_minh/application/currency/currency_context.dart';
import 'package:vi_nha_minh/core/constants/default_categories.dart';
import 'package:vi_nha_minh/core/constants/default_funds.dart';
import 'package:vi_nha_minh/core/constants/default_savings_asset_types.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/field_update.dart';
import 'package:vi_nha_minh/domain/entities/fund.dart';
import 'package:vi_nha_minh/domain/entities/obligation.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/savings_asset_type.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/entities/transfer_kind.dart';
import 'package:vi_nha_minh/domain/repositories/category_repository.dart';
import 'package:vi_nha_minh/domain/repositories/fund_repository.dart';
import 'package:vi_nha_minh/domain/repositories/obligation_repository.dart';
import 'package:vi_nha_minh/domain/repositories/savings_asset_type_repository.dart';
import 'package:vi_nha_minh/domain/repositories/transaction_repository.dart';
import 'package:vi_nha_minh/presentation/features/fund/fund_detail_screen.dart';
import 'package:vi_nha_minh/presentation/features/savings/savings_screen.dart';
import 'package:vi_nha_minh/presentation/features/transactions/transaction_detail_screen.dart';
import 'package:vi_nha_minh/presentation/providers/category_providers.dart';
import 'package:vi_nha_minh/presentation/providers/counterparty_providers.dart';
import 'package:vi_nha_minh/presentation/providers/currency_providers.dart';
import 'package:vi_nha_minh/presentation/providers/feature_providers.dart';
import 'package:vi_nha_minh/presentation/providers/fund_providers.dart';
import 'package:vi_nha_minh/presentation/providers/obligation_providers.dart';
import 'package:vi_nha_minh/presentation/providers/savings_asset_type_providers.dart';
import 'package:vi_nha_minh/presentation/providers/transaction_providers.dart';
import '../../support/legacy_members.dart';

class _Repo implements TransactionRepository {
  _Repo(this._current);
  final _controller = StreamController<List<Transaction>>.broadcast();
  List<Transaction> _current;
  final updates = <({String id, int? amount})>[];
  final deletes = <String>[];

  @override
  Stream<List<Transaction>> watchTransactions() async* {
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
    updates.add((id: transactionId, amount: amountMinor));
  }

  @override
  Future<void> deleteTransaction(String transactionId) async {
    deletes.add(transactionId);
    _current = _current.where((t) => t.id != transactionId).toList();
    _controller.add(_current);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _CatRepo implements CategoryRepository {
  @override
  Stream<List<Category>> watchCategories() =>
      Stream.value(DefaultCategories.all);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FundRepo implements FundRepository {
  @override
  Stream<List<Fund>> watchFunds() => Stream.value(DefaultFunds.all);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _AssetRepo implements SavingsAssetTypeRepository {
  @override
  Stream<List<SavingsAssetType>> watchAssetTypes() =>
      Stream.value(DefaultSavingsAssetTypes.all);
  @override
  Stream<Set<String>> watchDeletableAssetTypeIds() => Stream.value(const {});
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _ObRepo implements ObligationRepository {
  @override
  Stream<List<Obligation>> watchObligations() => Stream.value(const []);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Currency implements CurrencyContext {
  @override
  Future<String> getBaseCurrencyCode() async => 'VND';
}

Transaction _tx(
  String id,
  TransactionType type,
  String category,
  PoolKind from,
  String? fromRef,
  PoolKind to,
  String? toRef,
  int amount, {
  TransferKind? kind,
}) => Transaction(
  id: id,
  type: type,
  transferKind: kind,
  categoryId: category,
  sourceKind: from,
  sourceRefId: fromRef,
  destinationKind: to,
  destinationRefId: toRef,
  amountMinor: amount,
  transactionDate: DateTime(2026, 9, 10),
  createdAt: DateTime(2026, 9, 10),
  clientTxId: 'c-$id',
);

final _fundTopup = _tx(
  'fund-topup', TransactionType.transfer, 'nap_quy',
  PoolKind.memberAvailable, 'chong', PoolKind.fund, DefaultFunds.anUongId, 300000,
  kind: TransferKind.fundTopup,
);
final _fundSpend = _tx(
  'fund-spend', TransactionType.expense, 'sinh_hoat',
  PoolKind.fund, DefaultFunds.anUongId, PoolKind.external, null, 120000,
);
final _savingsTopup = _tx(
  'sav-topup', TransactionType.transfer, 'tiet_kiem',
  PoolKind.memberAvailable, 'vo', PoolKind.memberSavingsAsset,
  savingsAssetRefId(DefaultSavingsAssetTypes.bankId, 'vo'), 200000,
  kind: TransferKind.savingsTopup,
);
final _income = _tx(
  'income', TransactionType.income, 'thu_nhap',
  PoolKind.external, null, PoolKind.memberAvailable, 'chong', 1000000,
);

Future<_Repo> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo = _Repo([_income, _fundTopup, _fundSpend, _savingsTopup]);
  addTearDown(() => repo._controller.close());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...legacyMemberOverrides,
        transactionRepositoryProvider.overrideWithValue(repo),
        categoryRepositoryProvider.overrideWithValue(_CatRepo()),
        fundRepositoryProvider.overrideWithValue(_FundRepo()),
        savingsAssetTypeRepositoryProvider.overrideWithValue(_AssetRepo()),
        obligationRepositoryProvider.overrideWithValue(_ObRepo()),
        obligationsStreamProvider.overrideWith((ref) => Stream.value(const [])),
        counterpartiesStreamProvider.overrideWith((ref) => Stream.value([])),
        advancedFeaturesEnabledProvider.overrideWithValue(false),
        currencyContextProvider.overrideWithValue(_Currency()),
      ],
      child: MaterialApp(home: home),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

Future<void> _openDetail(WidgetTester tester, String rowKey, String id) async {
  final row = find.byKey(Key(rowKey));
  await tester.ensureVisible(row);
  await tester.tap(row);
  await tester.pumpAndSettle();
  final detail = tester.widget<TransactionDetailScreen>(
    find.byType(TransactionDetailScreen),
  );
  expect(detail.transactionId, id);
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('Quỹ: nạp quỹ và chi từ quỹ mở đúng chi tiết chuẩn; sửa số tiền rồi xóa', (tester) async {
    final repo = await _pump(tester, const FundDetailScreen(fundId: DefaultFunds.anUongId));
    expect(find.byKey(const Key('fund_transaction_fund-topup')), findsOneWidget);
    expect(find.byKey(const Key('fund_transaction_fund-spend')), findsOneWidget);
    expect(find.byKey(const Key('fund_transaction_income')), findsNothing);

    await _openDetail(tester, 'fund_transaction_fund-spend', 'fund-spend');
    expect(find.text('Chi'), findsWidgets);
    await tester.enterText(find.byKey(const Key('detail_amount_field')), '150000');
    await tester.pump();
    final save = find.widgetWithText(ElevatedButton, 'Lưu thay đổi');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repo.updates.single, (id: 'fund-spend', amount: 150000));
    expect(find.byType(TransactionDetailScreen), findsNothing);

    await _openDetail(tester, 'fund_transaction_fund-topup', 'fund-topup');
    expect(find.text('Chuyển'), findsWidgets);
    final delete = find.widgetWithText(OutlinedButton, 'Xóa giao dịch');
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Xóa'));
    await tester.pumpAndSettle();
    expect(repo.deletes, ['fund-topup']);
    expect(find.byKey(const Key('fund_transaction_fund-topup')), findsNothing);
    expect(find.byKey(const Key('fund_transaction_fund-spend')), findsOneWidget);
  });

  testWidgets('Tiết kiệm: dòng lịch sử mở đúng chi tiết chuẩn theo Transaction.id', (tester) async {
    final repo = await _pump(tester, const SavingsScreen(initialMemberId: 'vo'));
    await _openDetail(tester, 'savings_transaction_sav-topup', 'sav-topup');
    await tester.enterText(find.byKey(const Key('detail_amount_field')), '250000');
    await tester.pump();
    final save = find.widgetWithText(ElevatedButton, 'Lưu thay đổi');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repo.updates.single, (id: 'sav-topup', amount: 250000));
  });
}
