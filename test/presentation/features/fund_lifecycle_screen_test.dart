import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/fund.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/entities/transfer_kind.dart';
import 'package:vi_nha_minh/domain/repositories/fund_repository.dart';
import 'package:vi_nha_minh/presentation/features/fund/fund_list_screen.dart';
import 'package:vi_nha_minh/presentation/providers/category_providers.dart';
import 'package:vi_nha_minh/presentation/providers/fund_providers.dart';
import 'package:vi_nha_minh/presentation/providers/primary_fund_provider.dart';
import 'package:vi_nha_minh/presentation/providers/transaction_providers.dart';

/// Quỹ dùng CÙNG triết lý với Danh mục/Trạng thái: xóa hẳn khi sạch; không thì chỉ
/// rõ số dư còn lại + từng giao dịch đang giữ (mở được), và cập nhật NGAY.
class _FundRepo implements FundRepository {
  final calls = <String>[];

  @override
  Stream<List<Fund>> watchFunds() => const Stream.empty();
  @override
  Future<void> addFund(Fund fund) async => calls.add('add:${fund.id}');
  @override
  Future<void> updateFund(Fund fund) async => calls.add('update:${fund.id}');
  @override
  Future<void> softDeleteFund(String fundId) async => calls.add('stop:$fundId');
  @override
  Future<void> reactivateFund(String fundId) async => calls.add('reuse:$fundId');
  @override
  Future<void> deleteFundPermanently(String fundId) async => calls.add('delete:$fundId');
}

final _cats = <Category>[
  Category(id: 'nap_quy', name: 'Nạp quỹ', color: Colors.grey, type: TransactionType.transfer),
  Category(id: 'sinh_hoat', name: 'Sinh hoạt', color: Colors.grey, type: TransactionType.expense),
];

Transaction _topup(String id, String fund, int amount) => Transaction(
  id: id,
  type: TransactionType.transfer,
  transferKind: TransferKind.fundTopup,
  categoryId: 'nap_quy',
  sourceKind: PoolKind.memberAvailable,
  sourceRefId: 'vo',
  destinationKind: PoolKind.fund,
  destinationRefId: fund,
  amountMinor: amount,
  transactionDate: DateTime(2026, 9, 12),
  createdAt: DateTime(2026, 9, 12),
  clientTxId: 'c-$id',
);

Transaction _spend(String id, String fund, int amount) => Transaction(
  id: id,
  type: TransactionType.expense,
  categoryId: 'sinh_hoat',
  sourceKind: PoolKind.fund,
  sourceRefId: fund,
  destinationKind: PoolKind.external,
  amountMinor: amount,
  transactionDate: DateTime(2026, 9, 15),
  createdAt: DateTime(2026, 9, 15),
  clientTxId: 'c-$id',
);

Future<_FundRepo> _pump(
  WidgetTester tester, {
  required List<Fund> funds,
  required Stream<List<Transaction>> ledger,
  PrimaryFundController? primary,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo = _FundRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (primary != null) primaryFundIdProvider.overrideWith((ref) => primary),
        fundRepositoryProvider.overrideWithValue(repo),
        fundsStreamProvider.overrideWith((ref) => Stream.value(funds)),
        transactionsStreamProvider.overrideWith((ref) => ledger),
        categoriesStreamProvider.overrideWith((ref) => Stream.value(_cats)),
      ],
      child: const MaterialApp(home: FundListScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  const active = Fund(id: 'an_uong', name: 'Quỹ tiền ăn', color: Colors.orange);
  const stoppedUsed = Fund(id: 'q1', name: 'Quỹ học', color: Colors.blue, isActive: false);
  const stoppedClean = Fund(id: 'q2', name: 'Quỹ xe', color: Colors.green, isActive: false);

  Future<void> openStopped(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('fund_stopped_section')));
    await tester.tap(find.byKey(const Key('fund_stopped_section')));
    await tester.pumpAndSettle();
  }

  testWidgets('Quỹ ngừng còn tiền + giao dịch: giải thích "vẫn còn X đ" + "bởi n giao dịch"; có [Xem giao dịch], KHÔNG có [Xóa hẳn]', (tester) async {
    await _pump(
      tester,
      funds: [active, stoppedUsed],
      ledger: Stream.value([_topup('a', 'q1', 100000), _spend('b', 'q1', 80000)]),
    );
    await openStopped(tester);

    expect(
      find.text('Chưa thể xóa quỹ này. Vẫn còn 20.000 đ — hãy rút hoặc chuyển đi trước. Đang được sử dụng bởi 2 giao dịch.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('blockers_fund_q1')), findsOneWidget);
    expect(find.byKey(const Key('delete_fund_q1')), findsNothing);

    await tester.tap(find.byKey(const Key('blockers_fund_q1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('blocking_transactions_dialog')), findsOneWidget);
    expect(find.text('Mở giao dịch'), findsNWidgets(2));
    expect(find.textContaining('100.000'), findsWidgets);
    expect(find.textContaining('12/09/2026'), findsOneWidget);
  });

  testWidgets('Quỹ ngừng sạch dấu vết: [Sử dụng lại] và [Xóa hẳn] (có xác nhận, Huỷ không xóa)', (tester) async {
    final repo = await _pump(tester, funds: [active, stoppedClean], ledger: Stream.value(const []));
    await openStopped(tester);
    expect(find.byKey(const Key('blockers_fund_q2')), findsNothing);

    await tester.tap(find.byKey(const Key('reuse_fund_q2')));
    await tester.pumpAndSettle();
    expect(repo.calls, ['reuse:q2']);

    await tester.tap(find.byKey(const Key('delete_fund_q2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Huỷ'));
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c.startsWith('delete')), isEmpty);

    await tester.tap(find.byKey(const Key('delete_fund_q2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_delete_fund')));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('delete:q2'));
  });

  testWidgets('Xử lý hết giao dịch giữ quỹ → [Xóa hẳn] xuất hiện NGAY (không cần khởi động lại)', (tester) async {
    final ctrl = StreamController<List<Transaction>>();
    addTearDown(ctrl.close);
    await _pump(tester, funds: [active, stoppedUsed], ledger: ctrl.stream);
    ctrl.add([_topup('a', 'q1', 50000)]);
    await tester.pumpAndSettle();
    await openStopped(tester);
    expect(find.byKey(const Key('delete_fund_q1')), findsNothing);
    expect(find.byKey(const Key('blockers_fund_q1')), findsOneWidget);

    ctrl.add(const []); // người dùng đã xóa giao dịch nạp
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('delete_fund_q1')), findsOneWidget);
    expect(find.byKey(const Key('blockers_fund_q1')), findsNothing);
  });

  testWidgets('Quỹ tiền ăn mặc định KHÔNG bị bảo vệ: ngừng rồi vẫn xóa hẳn được như quỹ khác', (tester) async {
    const stoppedDefault = Fund(id: 'an_uong', name: 'Quỹ tiền ăn', color: Colors.orange, isActive: false);
    await _pump(tester, funds: const [stoppedDefault], ledger: Stream.value(const []));
    await openStopped(tester);
    expect(find.byKey(const Key('delete_fund_an_uong')), findsOneWidget);
    expect(find.text('Đây là mục hệ thống của ứng dụng nên không thể xóa.'), findsNothing);
  });

  testWidgets('Danh sách quỹ trống → "Chưa có quỹ nào." + [+ Tạo quỹ mới]', (tester) async {
    await _pump(tester, funds: const [], ledger: Stream.value(const []));
    expect(find.byKey(const Key('fund_list_empty')), findsOneWidget);
    expect(find.byKey(const Key('fund_create')), findsOneWidget);
  });

  group('Quỹ chính (Trang chủ)', () {
    const other = Fund(id: 'q3', name: 'Quỹ du lịch', color: Colors.purple);

    testWidgets('Quỹ chính có nhãn "Quỹ chính"; quỹ khác có nút [Đặt làm quỹ chính] → chọn xong nhãn chuyển sang quỹ đó', (tester) async {
      final primary = PrimaryFundController(); // mặc định an_uong
      await _pump(tester, funds: const [active, other], ledger: Stream.value(const []), primary: primary);

      expect(find.byKey(const Key('fund_primary_badge_an_uong')), findsOneWidget);
      expect(find.byKey(const Key('fund_set_primary_an_uong')), findsNothing);
      expect(find.byKey(const Key('fund_set_primary_q3')), findsOneWidget);

      await tester.tap(find.byKey(const Key('fund_set_primary_q3')));
      await tester.pumpAndSettle();

      expect(primary.state, 'q3');
      expect(find.byKey(const Key('fund_primary_badge_q3')), findsOneWidget);
      expect(find.byKey(const Key('fund_set_primary_an_uong')), findsOneWidget);
    });

    testWidgets('Xóa hẳn ĐÚNG quỹ chính → bỏ chọn (không tự chọn quỹ khác)', (tester) async {
      const stoppedDefault = Fund(id: 'an_uong', name: 'Quỹ tiền ăn', color: Colors.orange, isActive: false);
      final primary = PrimaryFundController();
      final repo = await _pump(tester, funds: const [other, stoppedDefault], ledger: Stream.value(const []), primary: primary);
      await openStopped(tester);

      await tester.tap(find.byKey(const Key('delete_fund_an_uong')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_delete_fund')));
      await tester.pumpAndSettle();

      expect(repo.calls, contains('delete:an_uong'));
      expect(primary.state, isNull);
    });

    testWidgets('Xóa hẳn quỹ KHÔNG phải quỹ chính → quỹ chính giữ nguyên', (tester) async {
      final primary = PrimaryFundController(initialId: 'q3');
      final repo = await _pump(tester, funds: const [other, stoppedClean], ledger: Stream.value(const []), primary: primary);
      await openStopped(tester);

      await tester.tap(find.byKey(const Key('delete_fund_q2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_delete_fund')));
      await tester.pumpAndSettle();

      expect(repo.calls, contains('delete:q2'));
      expect(primary.state, 'q3');
    });
  });
}
