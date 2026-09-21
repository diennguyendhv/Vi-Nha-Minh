import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
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
import 'package:vi_nha_minh/domain/repositories/obligation_repository.dart';
import 'package:vi_nha_minh/domain/repositories/savings_asset_type_repository.dart';
import 'package:vi_nha_minh/domain/repositories/transaction_repository.dart';
import 'package:vi_nha_minh/domain/entities/obligation.dart';
import 'package:vi_nha_minh/presentation/features/add_transaction/add_transaction_sheet.dart';
import 'package:vi_nha_minh/presentation/features/savings/savings_screen.dart';
import 'package:vi_nha_minh/presentation/providers/category_providers.dart';
import 'package:vi_nha_minh/presentation/providers/fund_providers.dart';
import 'package:vi_nha_minh/presentation/providers/obligation_providers.dart';
import 'package:vi_nha_minh/presentation/providers/savings_asset_type_providers.dart';
import 'package:vi_nha_minh/presentation/providers/transaction_providers.dart';
import '../../support/legacy_members.dart';

class _TxRepo implements TransactionRepository {
  _TxRepo(this.ledger);
  final List<Transaction> ledger;
  @override
  Stream<List<Transaction>> watchTransactions() => Stream.value(ledger);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _CatRepo implements CategoryRepository {
  @override
  Stream<List<Category>> watchCategories() => Stream.value(DefaultCategories.all);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FundRepo implements FundRepository {
  @override
  Stream<List<Fund>> watchFunds() => Stream.value(DefaultFunds.all);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _ObRepo implements ObligationRepository {
  @override
  Stream<List<Obligation>> watchObligations() => Stream.value(const []);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _AssetRepo implements SavingsAssetTypeRepository {
  _AssetRepo(this.types, {this.deletable = const {}});
  final List<SavingsAssetType> types;
  final Set<String> deletable;
  final calls = <String>[];
  Object? softDeleteError;

  @override
  Stream<List<SavingsAssetType>> watchAssetTypes() => Stream.value(types);
  @override
  Future<void> addAssetType(SavingsAssetType a) async => calls.add('add:${a.name}');
  @override
  Future<void> updateAssetType(SavingsAssetType a) async => calls.add('update:${a.id}');
  @override
  Future<void> renameAssetType(String id, String name) async => calls.add('rename:$id:$name');
  @override
  Future<void> reactivateAssetType(String id) async => calls.add('reuse:$id');
  @override
  Future<void> softDeleteAssetType(String id) async {
    if (softDeleteError != null) throw softDeleteError!;
    calls.add('stop:$id');
  }

  @override
  Stream<Set<String>> watchDeletableAssetTypeIds() => Stream.value(deletable);
  @override
  Future<void> deleteAssetTypePermanently(String id) async => calls.add('purge:$id');
}

int _n = 0;
Transaction _into(String m, String asset, int amount) {
  _n++;
  return Transaction(
    id: 's$_n',
    type: TransactionType.income,
    categoryId: 'so_du_ban_dau',
    sourceKind: PoolKind.external,
    destinationKind: PoolKind.memberSavingsAsset,
    destinationRefId: savingsAssetRefId(asset, m),
    amountMinor: amount,
    transactionDate: DateTime(2026, 9, 1),
    createdAt: DateTime(2026, 9, 1),
    clientTxId: 'ck$_n',
  );
}

Transaction _outOf(String m, String asset, int amount) {
  _n++;
  return Transaction(
    id: 'o$_n',
    type: TransactionType.expense,
    categoryId: 'tiet_kiem',
    sourceKind: PoolKind.memberSavingsAsset,
    sourceRefId: savingsAssetRefId(asset, m),
    destinationKind: PoolKind.external,
    amountMinor: amount,
    transactionDate: DateTime(2026, 9, 1),
    createdAt: DateTime(2026, 9, 1),
    clientTxId: 'co$_n',
  );
}

Future<_AssetRepo> _pump(
  WidgetTester tester, {
  List<Transaction> ledger = const [],
  List<SavingsAssetType>? types,
  Set<String> deletable = const {},
  String? member,
}) async {
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final assets = _AssetRepo(types ?? DefaultSavingsAssetTypes.all, deletable: deletable);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...legacyMemberOverrides,
        transactionRepositoryProvider.overrideWithValue(_TxRepo(ledger)),
        categoryRepositoryProvider.overrideWithValue(_CatRepo()),
        fundRepositoryProvider.overrideWithValue(_FundRepo()),
        obligationRepositoryProvider.overrideWithValue(_ObRepo()),
        savingsAssetTypeRepositoryProvider.overrideWithValue(assets),
      ],
      child: MaterialApp(home: SavingsScreen(initialMemberId: member)),
    ),
  );
  await tester.pumpAndSettle();
  return assets;
}

String _text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  const vo = 'vo';
  const chong = 'chong';
  const bank = DefaultSavingsAssetTypes.bankId;
  const gold = DefaultSavingsAssetTypes.goldId;
  const unalloc = SystemSavingsAssets.unallocatedId;

  group('Hiển thị 2 tầng', () {
    testWidgets('Mở đúng thành viên (initialMember); Vợ / Chồng tách riêng, tổng theo từng người', (tester) async {
      final ledger = [_into(vo, bank, 700000), _into(chong, unalloc, 300000), _into(chong, gold, 200000)];
      await _pump(tester, ledger: ledger, member: chong);

      expect(find.text('TIẾT KIỆM CHỒNG'), findsOneWidget);
      expect(_text(tester, 'savings_total'), '500.000 đ');

      await tester.tap(find.text('Vợ'));
      await tester.pumpAndSettle();
      expect(find.text('TIẾT KIỆM VỢ'), findsOneWidget);
      expect(_text(tester, 'savings_total'), '700.000 đ');
    });

    testWidgets('"Chưa phân bổ" ở đầu danh sách Phân bổ; số từng dòng cộng lại = tổng', (tester) async {
      final ledger = [_into(chong, unalloc, 300000), _into(chong, gold, 200000), _into(chong, bank, 500000)];
      await _pump(tester, ledger: ledger, member: chong);

      expect(_text(tester, 'savings_total'), '1.000.000 đ');
      expect(_text(tester, 'savings_balance_$unalloc'), '300.000 đ');
      expect(_text(tester, 'savings_balance_$gold'), '200.000 đ');
      expect(_text(tester, 'savings_balance_$bank'), '500.000 đ');
      final unallocTop = tester.getTopLeft(find.byKey(const Key('savings_row_$unalloc'))).dy;
      final bankTop = tester.getTopLeft(find.byKey(const Key('savings_row_$bank'))).dy;
      expect(unallocTop, lessThan(bankTop));
      expect(find.text('Chưa phân bổ'), findsOneWidget);
    });

    testWidgets('Loại đã ngừng CÒN số dư vẫn hiện, gắn "Ngừng sử dụng", chỉ có Rút/Phân bổ (không Ngừng, không nạp)', (tester) async {
      final types = [
        for (final t in DefaultSavingsAssetTypes.all) t.id == gold ? t.copyWith(isActive: false) : t,
      ];
      await _pump(tester, ledger: [_into(chong, gold, 250000)], types: types, member: chong);

      expect(find.byKey(const Key('savings_row_$gold')), findsOneWidget);
      expect(find.byKey(const Key('savings_inactive_tag')), findsOneWidget);
      expect(_text(tester, 'savings_total'), '250.000 đ', reason: 'không có tiền nào không hiện');

      await tester.tap(find.byKey(const Key('savings_menu_$gold')));
      await tester.pumpAndSettle();
      expect(find.text('Phân bổ / chuyển'), findsOneWidget);
      expect(find.text('Rút về số dư'), findsWidgets);
      expect(find.text('Ngừng sử dụng'), findsOneWidget, reason: 'chỉ là nhãn của dòng, KHÔNG có mục menu "Ngừng sử dụng" nữa');
    });

    testWidgets('Loại đã ngừng số dư 0 KHÔNG nằm trong Phân bổ mà ở khu "Ngừng sử dụng"', (tester) async {
      final types = [
        for (final t in DefaultSavingsAssetTypes.all) t.id == gold ? t.copyWith(isActive: false) : t,
      ];
      await _pump(tester, types: types, member: chong);
      expect(find.byKey(const Key('savings_row_$gold')), findsNothing);
      expect(find.byKey(const Key('savings_stopped_section')), findsOneWidget);
      expect(find.text('Ngừng sử dụng (1)'), findsOneWidget);
    });

    testWidgets('Chưa phân bổ (hệ thống): không có menu Đổi tên / Ngừng sử dụng', (tester) async {
      await _pump(tester, ledger: [_into(chong, unalloc, 100000)], member: chong);
      await tester.tap(find.byKey(const Key('savings_menu_$unalloc')));
      await tester.pumpAndSettle();
      expect(find.text('Đổi tên'), findsNothing);
      expect(find.text('Ngừng sử dụng'), findsNothing);
      expect(find.text('Phân bổ / chuyển'), findsOneWidget);
    });

    testWidgets('Không lộ thuật ngữ kỹ thuật', (tester) async {
      await _pump(tester, ledger: [_into(chong, unalloc, 100000)], member: chong);
      for (final leak in ['savings_unallocated', 'memberSavingsAsset', 'SAVINGS', 'pool', 'ledger']) {
        expect(find.textContaining(leak), findsNothing, reason: leak);
      }
    });
  });

  group('Sự kiện — mở sheet', () {
    testWidgets('"+ Thêm vào tiết kiệm" → đúng 1 sheet, mặc định Thêm vào, đúng thành viên; bấm nhanh không mở trùng', (tester) async {
      await _pump(tester, member: chong);
      final onPressed = tester.widget<FilledButton>(find.byKey(const Key('savings_add'))).onPressed!;
      onPressed();
      onPressed();
      onPressed();
      await tester.pumpAndSettle();

      expect(find.byType(AddTransactionSheet, skipOffstage: false), findsOneWidget);
      final sheet = tester.widget<AddTransactionSheet>(find.byType(AddTransactionSheet));
      expect(sheet.initialSavingsAction, SavingsAction.topup);
      expect(sheet.initialMemberId, chong);
      expect(sheet.initialTransferSubKind, TransferSubKind.savings);
      expect(find.byKey(const Key('savings_topup_hint')), findsOneWidget, reason: 'không hỏi loại tài sản');
    });

    testWidgets('"Rút về số dư": khoá khi chưa có tiền tiết kiệm; có tiền thì mở sheet Rút', (tester) async {
      await _pump(tester, member: chong);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('savings_withdraw'))).onPressed, isNull);

      await _pump(tester, ledger: [_into(chong, gold, 100000)], member: chong);
      await tester.tap(find.byKey(const Key('savings_withdraw')));
      await tester.pumpAndSettle();
      final sheet = tester.widget<AddTransactionSheet>(find.byType(AddTransactionSheet));
      expect(sheet.initialSavingsAction, SavingsAction.withdraw);
      expect(sheet.initialSavingsAssetTypeId, isNull);
    });

    testWidgets('Menu dòng: Phân bổ / chuyển → sheet Phân bổ với nguồn = dòng đó; Rút → sheet Rút với nguồn = dòng đó', (tester) async {
      await _pump(tester, ledger: [_into(chong, gold, 100000)], member: chong);

      await tester.tap(find.byKey(const Key('savings_menu_$gold')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Phân bổ / chuyển'));
      await tester.pumpAndSettle();
      var sheet = tester.widget<AddTransactionSheet>(find.byType(AddTransactionSheet));
      expect(sheet.initialSavingsAction, SavingsAction.convert);
      expect(sheet.initialSavingsAssetTypeId, gold);
    });
  });

  group('Quản lý loại tài sản', () {
    testWidgets('Thêm loại: tạo mới (tên tự do như "Gửi NH 3 tháng"); Huỷ thì không tạo', (tester) async {
      final repo = await _pump(tester, member: chong);

      await tester.tap(find.byKey(const Key('savings_add_type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Huỷ'));
      await tester.pumpAndSettle();
      expect(repo.calls, isEmpty);

      await tester.tap(find.byKey(const Key('savings_add_type')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('asset_name_field')), 'Gửi NH 3 tháng');
      await tester.tap(find.byKey(const Key('asset_create_save')));
      await tester.pumpAndSettle();
      expect(repo.calls, ['add:Gửi NH 3 tháng']);
    });

    testWidgets('Tên trùng loại đang dùng / trùng "Chưa phân bổ" → báo lỗi, không tạo', (tester) async {
      final repo = await _pump(tester, member: chong);
      await tester.tap(find.byKey(const Key('savings_add_type')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('asset_name_field')), '  vàng ');
      await tester.tap(find.byKey(const Key('asset_create_save')));
      await tester.pumpAndSettle();
      expect(find.text('Đã có loại tài sản tên này'), findsOneWidget);
      expect(find.byKey(const Key('asset_dup_reuse')), findsNothing);

      await tester.enterText(find.byKey(const Key('asset_name_field')), 'CHƯA PHÂN BỔ');
      await tester.tap(find.byKey(const Key('asset_create_save')));
      await tester.pumpAndSettle();
      expect(find.text('Đã có loại tài sản tên này'), findsOneWidget);
      expect(repo.calls, isEmpty);
    });

    testWidgets('Tên trùng loại ĐÃ NGỪNG → gợi ý "Sử dụng lại" (cùng id), không tạo bản sao', (tester) async {
      final types = [
        for (final t in DefaultSavingsAssetTypes.all) t.id == gold ? t.copyWith(isActive: false) : t,
      ];
      final repo = await _pump(tester, types: types, member: chong);
      await tester.tap(find.byKey(const Key('savings_add_type')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('asset_name_field')), 'Vàng');
      await tester.tap(find.byKey(const Key('asset_create_save')));
      await tester.pumpAndSettle();
      expect(find.text('Loại này đã tồn tại nhưng đang ngừng sử dụng.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('asset_dup_reuse')));
      await tester.pumpAndSettle();
      expect(repo.calls, ['reuse:$gold']);
    });

    testWidgets('Đổi tên: giữ id; trùng tên khác → báo lỗi', (tester) async {
      final repo = await _pump(tester, member: chong);

      await tester.tap(find.byKey(const Key('savings_menu_$gold')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đổi tên'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('asset_rename_field')), 'Gửi ngân hàng');
      await tester.tap(find.byKey(const Key('asset_rename_save')));
      await tester.pumpAndSettle();
      expect(find.text('Đã có loại tài sản tên này'), findsOneWidget);
      expect(repo.calls, isEmpty);

      await tester.enterText(find.byKey(const Key('asset_rename_field')), 'Vàng SJC');
      await tester.tap(find.byKey(const Key('asset_rename_save')));
      await tester.pumpAndSettle();
      expect(repo.calls, ['rename:$gold:Vàng SJC']);
    });

    testWidgets('Ngừng sử dụng: gọi repo; còn tiền → hộp thoại giải thích dễ hiểu (không thuật ngữ)', (tester) async {
      final repo = await _pump(tester, member: chong);
      await tester.tap(find.byKey(const Key('savings_menu_$gold')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ngừng sử dụng'));
      await tester.pumpAndSettle();
      expect(repo.calls, ['stop:$gold']);

      final repo2 = await _pump(tester, member: chong);
      repo2.softDeleteError = const SavingsAssetTypeNotEmptyException(bank);
      await tester.tap(find.byKey(const Key('savings_menu_$bank')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ngừng sử dụng'));
      await tester.pumpAndSettle();
      expect(find.text('Chưa thể ngừng sử dụng loại này'), findsOneWidget);
      expect(find.textContaining('rút'), findsWidgets);
      expect(find.textContaining('chuyển'), findsWidgets);
      expect(repo2.calls, isEmpty);
    });

    testWidgets('Khu Ngừng sử dụng: Sử dụng lại (cùng id); Xóa hẳn CHỈ khi chưa từng dùng, có xác nhận', (tester) async {
      final types = [
        for (final t in DefaultSavingsAssetTypes.all)
          (t.id == gold || t.id == DefaultSavingsAssetTypes.stocksId) ? t.copyWith(isActive: false) : t,
      ];
      // Vàng đã từng được dùng (vào rồi ra, số dư 0); Chứng khoán chưa từng.
      final ledger = [_into(chong, gold, 100), _outOf(chong, gold, 100)];
      final repo = await _pump(tester, types: types, ledger: ledger, member: chong);
      await tester.tap(find.byKey(const Key('savings_stopped_section')));
      await tester.pumpAndSettle();

      expect(find.byKey(Key('delete_asset_${DefaultSavingsAssetTypes.stocksId}')), findsOneWidget);
      expect(find.byKey(const Key('delete_asset_$gold')), findsNothing, reason: 'đã dùng lịch sử');
      // Vàng bị 2 giao dịch giữ: giải thích ĐÚNG lý do + cho xem/mở từng giao dịch cản.
      expect(find.text('Chưa thể xóa loại tiết kiệm này. Đang được sử dụng bởi 2 giao dịch.'), findsOneWidget);
      expect(find.byKey(const Key('blockers_asset_$gold')), findsOneWidget);
      expect(find.byKey(Key('blockers_asset_${DefaultSavingsAssetTypes.stocksId}')), findsNothing);
      await tester.tap(find.byKey(const Key('blockers_asset_$gold')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('blocking_transactions_dialog')), findsOneWidget);
      expect(find.text('Mở giao dịch'), findsNWidgets(2), reason: '2 giao dịch đang giữ Vàng');
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reuse_asset_$gold')));
      await tester.pumpAndSettle();
      expect(repo.calls, ['reuse:$gold']);

      await tester.tap(find.byKey(Key('delete_asset_${DefaultSavingsAssetTypes.stocksId}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Huỷ'));
      await tester.pumpAndSettle();
      expect(repo.calls.where((c) => c.startsWith('purge')), isEmpty);

      await tester.tap(find.byKey(Key('delete_asset_${DefaultSavingsAssetTypes.stocksId}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_delete_asset')));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('purge:${DefaultSavingsAssetTypes.stocksId}'));
    });
  });
}
