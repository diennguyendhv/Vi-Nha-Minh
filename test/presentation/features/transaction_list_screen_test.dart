import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vi_nha_minh/core/constants/default_categories.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/presentation/features/transactions/transaction_list_screen.dart';
import 'package:vi_nha_minh/presentation/providers/category_providers.dart';
import 'package:vi_nha_minh/presentation/providers/transaction_providers.dart';
import '../../support/legacy_members.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  final now = DateTime.now();
  var n = 0;
  Transaction tx({
    required TransactionType type,
    required String category,
    required PoolKind from,
    String? fromRef,
    required PoolKind to,
    String? toRef,
    int amount = 100000,
    String note = '',
  }) {
    n++;
    return Transaction(
      id: 'tx-$n',
      type: type,
      categoryId: category,
      sourceKind: from,
      sourceRefId: fromRef,
      destinationKind: to,
      destinationRefId: toRef,
      amountMinor: amount,
      note: note,
      transactionDate: now,
      createdAt: now.add(Duration(seconds: n)),
      clientTxId: 'c-$n',
    );
  }

  final categories = <Category>[
    ...DefaultCategories.all,
    const Category(
      id: 'luong_gv',
      name: 'Lương nhân viên',
      color: Colors.teal,
      type: TransactionType.expense,
      groupKey: CategoryGroupKey.businessExpense,
      isDefault: false,
    ),
  ];

  Future<void> pump(WidgetTester tester, List<Transaction> ledger) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
        ...legacyMemberOverrides,
          transactionsStreamProvider.overrideWith((ref) => Stream.value(ledger)),
          categoriesStreamProvider.overrideWith((ref) => Stream.value(categories)),
        ],
        child: const MaterialApp(home: Scaffold(body: TransactionListScreen())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Mỗi dòng hiện "Nhóm · Danh mục" + ghi chú + Vợ/Chồng', (tester) async {
    await pump(tester, [
      tx(
        type: TransactionType.income,
        category: 'thu_nhap',
        from: PoolKind.external,
        to: PoolKind.memberAvailable,
        toRef: 'vo',
        note: 'HP lop Excel',
      ),
      tx(
        type: TransactionType.expense,
        category: 'luong_gv',
        from: PoolKind.memberAvailable,
        fromRef: 'chong',
        to: PoolKind.external,
        note: 'Luong co Bich',
      ),
      tx(
        type: TransactionType.expense,
        category: 'sinh_hoat',
        from: PoolKind.memberAvailable,
        fromRef: 'vo',
        to: PoolKind.external,
      ),
    ]);

    expect(find.textContaining('Doanh thu · Thu nhập'), findsOneWidget);
    expect(find.text('HP lop Excel · Vợ'), findsOneWidget);
    expect(find.textContaining('Chi phí kinh doanh · Lương nhân viên'), findsOneWidget);
    expect(find.text('Luong co Bich · Chồng'), findsOneWidget);
    expect(find.textContaining('Chi tiêu · Sinh hoạt'), findsOneWidget);
    expect(find.text('Vợ'), findsOneWidget, reason: 'không có ghi chú → chỉ hiện Vợ');
  });

  testWidgets('Chuyển giữa 2 thành viên hiện "Vợ → Chồng"; giao dịch cũ (Vay) vẫn hiển thị', (tester) async {
    await pump(tester, [
      tx(
        type: TransactionType.transfer,
        category: 'chuyen_tien_thanh_vien',
        from: PoolKind.memberAvailable,
        fromRef: 'vo',
        to: PoolKind.memberAvailable,
        toRef: 'chong',
      ),
      tx(
        type: TransactionType.transfer,
        category: 'cho_vay',
        from: PoolKind.memberAvailable,
        fromRef: 'vo',
        to: PoolKind.receivable,
        toRef: 'ob-1',
      ),
    ]);
    expect(find.text('Vợ → Chồng'), findsOneWidget);
    expect(find.textContaining('Cho vay'), findsOneWidget, reason: 'lịch sử Vay vẫn render');
    expect(tester.takeException(), isNull);
  });
}
