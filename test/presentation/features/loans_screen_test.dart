import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/utils/id_generator.dart';
import 'package:vi_nha_minh/domain/engine/financial_engine.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/presentation/features/loans/create_loan_sheet.dart';
import 'package:vi_nha_minh/presentation/features/loans/loans_screen.dart';
import 'package:vi_nha_minh/presentation/features/loans/settle_loan_sheet.dart';
import 'package:vi_nha_minh/presentation/providers/counterparty_providers.dart';
import 'package:vi_nha_minh/presentation/providers/obligation_providers.dart';
import 'package:vi_nha_minh/presentation/providers/transaction_providers.dart';

import 'loans_test_support.dart';

/// Phase 8.8 — widget test cho toàn bộ luồng "Vay & Cho vay".
///
/// Dùng fake repository in-memory (`loans_test_support.dart`), KHÔNG dùng
/// `AppDatabase.forTesting(NativeDatabase.memory())` — đã XÁC NHẬN bằng log
/// chạy thật rằng kết hợp Drift thật + `tester.pumpAndSettle()` treo 10
/// phút/lần (Timer nội bộ `StreamQueryStore` của Drift không được dọn đúng
/// trong widget test binding). Đây là vấn đề TEST HARNESS, không phải lỗi
/// Presentation — sửa bằng cách quay lại đúng convention fake in-memory đã
/// ổn định ở `add_transaction_sheet_test.dart`/`home_screen_test.dart`/
/// `transaction_detail_screen_test.dart`. Logic tài chính (allocation gốc/
/// lãi, atomicity, idempotency) vẫn tái sử dụng NGUYÊN các hàm domain thuần
/// qua fake — không viết lại công thức nào ở đây; atomicity/idempotency mức
/// SQL thật đã chứng minh riêng ở `obligation_repository_test.dart`/
/// `atomic_obligation_creation_test.dart`.
void main() {
  late FakeLoanTransactionRepository transactionRepository;
  late FakeObligationRepository obligationRepository;
  late FakeCounterpartyRepository counterpartyRepository;

  setUp(() {
    transactionRepository = FakeLoanTransactionRepository();
    obligationRepository = FakeObligationRepository(transactionRepository);
    counterpartyRepository = FakeCounterpartyRepository();
  });

  Widget wrap(Widget child) {
    return ProviderScope(
      overrides: [
        transactionRepositoryProvider.overrideWithValue(transactionRepository),
        obligationRepositoryProvider.overrideWithValue(obligationRepository),
        counterpartyRepositoryProvider.overrideWithValue(counterpartyRepository),
      ],
      child: MaterialApp(home: child),
    );
  }

  Future<void> seedAvailable(WidgetTester tester, int amountMinor) async {
    // Nạp sẵn Available cho Vợ — cần thiết vì Receivable rút từ Available.
    final now = DateTime(2026, 1, 1);
    await transactionRepository.addTransaction(
      Transaction(
        id: IdGenerator.generate(),
        type: TransactionType.income,
        categoryId: 'thu_nhap',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: amountMinor,
        transactionDate: now,
        createdAt: now,
        clientTxId: IdGenerator.generate(),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('LoansScreen — empty state & entry', () {
    testWidgets('1 — mở màn, empty state hiện đúng cho Receivable', (tester) async {
      await tester.pumpWidget(wrap(const LoansScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Vay & Cho vay'), findsOneWidget);
      expect(find.textContaining('Chưa có khoản cho vay nào'), findsOneWidget);
    });

    testWidgets('2 — switch sang Payable → empty state đổi đúng nhãn', (tester) async {
      await tester.pumpWidget(wrap(const LoansScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mình đang nợ'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Chưa có khoản đi vay nào'), findsOneWidget);
    });
  });

  group('Create Receivable (mục 9/11 STOP condition)', () {
    testWidgets(
      '11 — Cho vay 1.200.000 → Available -1.2m, Receivable +1.2m, xuất hiện trong list',
      (tester) async {
        await tester.pumpWidget(wrap(const LoansScreen()));
        await tester.pumpAndSettle();
        await seedAvailable(tester, 5000000);

        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(const Key('createLoan_counterparty')), 'Chị Hằng');
        await tester.enterText(find.byKey(const Key('createLoan_amount')), '1200000');
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.byKey(const Key('createLoan_save'), skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('createLoan_save')));
        await tester.pumpAndSettle();

        // Sheet đóng, list hiện đúng khoản vừa tạo.
        expect(find.text('Chị Hằng'), findsOneWidget);
        expect(find.textContaining('1.200.000'), findsWidgets);

        final transactions = await transactionRepository.watchTransactions().first;
        final balances = computeAllPoolBalances(transactions);
        expect(poolBalance(balances, PoolKind.memberAvailable, 'vo'), 5000000 - 1200000);
        final receivablePools = balances.entries.where((e) => e.key.$1 == PoolKind.receivable).toList();
        expect(receivablePools, hasLength(1));
        expect(receivablePools.single.value, 1200000);
      },
    );

    testWidgets('reuse Counterparty đã có — không tạo trùng', (tester) async {
      await tester.pumpWidget(wrap(const LoansScreen()));
      await tester.pumpAndSettle();
      await seedAvailable(tester, 5000000);

      Future<void> createLend(String name, String amount) async {
        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('createLoan_counterparty')), name);
        await tester.enterText(find.byKey(const Key('createLoan_amount')), amount);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('createLoan_save'), skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('createLoan_save')));
        await tester.pumpAndSettle();
      }

      await createLend('Chị Hằng', '500000');
      await createLend('Chị Hằng', '300000');

      final counterparties = await counterpartyRepository.watchCounterparties().first;
      expect(
        counterparties.where((c) => c.displayName == 'Chị Hằng'),
        hasLength(1),
        reason: '2 lần cho vay cùng tên KHÔNG tạo 2 Counterparty trùng',
      );
      final transactions = await transactionRepository.watchTransactions().first;
      expect(transactions, hasLength(3), reason: 'seed + 2 khoản cho vay riêng biệt');

      // 2 thẻ riêng biệt cùng tên "Chị Hằng" (2 khoản vay khác nhau, KHÔNG
      // gộp) — chỉ Counterparty dùng chung, mỗi Obligation vẫn độc lập.
      expect(find.text('Chị Hằng'), findsNWidgets(2));
    });
  });

  group('Settle — receive/repay + preview (mục 13/15)', () {
    testWidgets('15/16 — nhận đúng gốc, không lãi → Còn phải thu giảm đúng, không hiện preview lãi', (tester) async {
      await tester.pumpWidget(wrap(const LoansScreen()));
      await tester.pumpAndSettle();
      await seedAvailable(tester, 5000000);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('createLoan_counterparty')), 'Chị Hằng');
      await tester.enterText(find.byKey(const Key('createLoan_amount')), '1200000');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('createLoan_save'), skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('createLoan_save')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chị Hằng'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nhận tiền'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('settleLoan_amount')), '500000');
      await tester.pumpAndSettle();

      expect(find.textContaining('Thu hồi gốc'), findsNothing, reason: 'không lãi thì không hiện preview breakdown');

      await tester.ensureVisible(find.byKey(const Key('settleLoan_save'), skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settleLoan_save')));
      await tester.pumpAndSettle();

      expect(find.textContaining('700.000'), findsWidgets, reason: 'còn phải thu 700.000');
    });

    testWidgets(
      '17 — nhận vượt outstanding → preview hiện đúng gốc/lãi, sau Save khoản tất toán',
      (tester) async {
        await tester.pumpWidget(wrap(const LoansScreen()));
        await tester.pumpAndSettle();
        await seedAvailable(tester, 5000000);

        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('createLoan_counterparty')), 'Chị Hằng');
        await tester.enterText(find.byKey(const Key('createLoan_amount')), '1200000');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('createLoan_save'), skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('createLoan_save')));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Chị Hằng'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Nhận tiền'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('settleLoan_amount')), '1400000');
        await tester.pumpAndSettle();

        expect(find.text('Thu hồi gốc'), findsOneWidget);
        expect(find.textContaining('1.200.000'), findsWidgets);
        expect(find.text('Tiền lãi'), findsOneWidget);
        expect(find.textContaining('200.000'), findsWidgets);

        await tester.ensureVisible(find.byKey(const Key('settleLoan_save'), skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settleLoan_save')));
        await tester.pumpAndSettle();

        expect(find.text('Đã tất toán'), findsWidgets);
        expect(find.text('Nhận tiền'), findsNothing, reason: 'đã tất toán thì không còn nút Nhận tiền');
      },
    );
  });

  group('Reversal / Correction UX (mục 19/20)', () {
    testWidgets('24/25 — Hoàn tác lần nhận tiền (2 leg) → outstanding quay lại đúng', (tester) async {
      await tester.pumpWidget(wrap(const LoansScreen()));
      await tester.pumpAndSettle();
      await seedAvailable(tester, 5000000);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('createLoan_counterparty')), 'Chị Hằng');
      await tester.enterText(find.byKey(const Key('createLoan_amount')), '1200000');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('createLoan_save'), skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('createLoan_save')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chị Hằng'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nhận tiền'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('settleLoan_amount')), '1400000');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('settleLoan_save'), skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settleLoan_save')));
      await tester.pumpAndSettle();

      expect(find.text('Đã tất toán'), findsWidgets);

      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hoàn tác lần nhận tiền'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hoàn tác').last);
      await tester.pumpAndSettle();

      expect(find.text('Nhận tiền'), findsWidgets, reason: 'outstanding quay lại > 0, nút Nhận tiền hiện lại');
    });

    testWidgets('26/28 — Sửa lần tất toán mới nhất: 500k (không lãi) → 1.4m (có lãi)', (tester) async {
      await tester.pumpWidget(wrap(const LoansScreen()));
      await tester.pumpAndSettle();
      await seedAvailable(tester, 5000000);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('createLoan_counterparty')), 'Chị Hằng');
      await tester.enterText(find.byKey(const Key('createLoan_amount')), '1200000');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('createLoan_save'), skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('createLoan_save')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chị Hằng'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nhận tiền'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('settleLoan_amount')), '500000');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('settleLoan_save'), skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settleLoan_save')));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sửa'));
      await tester.pumpAndSettle();

      final amountField = find.byKey(const Key('settleLoan_amount'));
      await tester.enterText(amountField, '1400000');
      await tester.pumpAndSettle();

      expect(find.text('Thu hồi gốc'), findsOneWidget);
      expect(find.text('Tiền lãi'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('settleLoan_save'), skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settleLoan_save')));
      await tester.pumpAndSettle();

      expect(find.text('Đã tất toán'), findsWidgets);
    });
  });

  group('Error mapping (mục 22) — không lộ thuật ngữ kỹ thuật', () {
    testWidgets('không đủ số dư khi cho vay → message tiếng Việt an toàn', (tester) async {
      await tester.pumpWidget(wrap(const LoansScreen()));
      await tester.pumpAndSettle();
      // KHÔNG seed Available — cho vay sẽ vượt quá số dư (0đ).

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('createLoan_counterparty')), 'Chị Hằng');
      await tester.enterText(find.byKey(const Key('createLoan_amount')), '1200000');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('createLoan_save'), skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('createLoan_save')));
      await tester.pumpAndSettle();

      expect(find.text('Không đủ số dư để thực hiện.'), findsOneWidget);
      expect(find.textContaining('InsufficientBalanceException'), findsNothing);
      expect(find.textContaining('PoolKind'), findsNothing);
      // F1: lỗi nằm TRONG sheet (không phải SnackBar bị che sau modal).
      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.descendant(
          of: find.byType(CreateLoanSheet),
          matching: find.byKey(const Key('sheet_error_banner')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('rapid tap Lưu khi cho vay hợp lệ → đúng 1 giao dịch mở khoản, sheet đóng', (tester) async {
      await tester.pumpWidget(wrap(const LoansScreen()));
      await tester.pumpAndSettle();
      await seedAvailable(tester, 5000000);
      final base = (await transactionRepository.watchTransactions().first).length;

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('createLoan_counterparty')), 'Chị Lan');
      await tester.enterText(find.byKey(const Key('createLoan_amount')), '1000000');
      await tester.pumpAndSettle();
      final save = find.byKey(const Key('createLoan_save'));
      await tester.ensureVisible(save.hitTestable(at: Alignment.center).evaluate().isEmpty ? find.byKey(const Key('createLoan_save'), skipOffstage: false) : save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.tap(save, warnIfMissed: false);
      await tester.tap(save, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect((await transactionRepository.watchTransactions().first).length, base + 1);
      expect(find.byType(CreateLoanSheet), findsNothing);
    });

    testWidgets('trả nợ vượt số dư → lỗi hiện trong settle sheet, sheet vẫn mở', (tester) async {
      await tester.pumpWidget(wrap(const LoansScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mình đang nợ'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('createLoan_counterparty')), 'Anh Nam');
      await tester.enterText(find.byKey(const Key('createLoan_amount')), '1000000');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('createLoan_save'), skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('createLoan_save')));
      await tester.pumpAndSettle();

      // Tiêu hết tiền vừa vay → Available về 0, trả nợ sẽ thiếu số dư.
      final now = DateTime(2026, 1, 2);
      await transactionRepository.addTransaction(
        Transaction(
          id: IdGenerator.generate(),
          type: TransactionType.expense,
          categoryId: 'sinh_hoat',
          sourceKind: PoolKind.memberAvailable,
          sourceRefId: 'vo',
          destinationKind: PoolKind.external,
          amountMinor: 1000000,
          transactionDate: now,
          createdAt: now,
          clientTxId: IdGenerator.generate(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Anh Nam'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trả tiền'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('settleLoan_amount')), '500000');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('settleLoan_save'), skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settleLoan_save')));
      await tester.pumpAndSettle();

      expect(find.byType(SettleLoanSheet), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.descendant(
          of: find.byType(SettleLoanSheet),
          matching: find.text('Không đủ số dư để thực hiện.'),
        ),
        findsOneWidget,
      );

      // Không có ghi tài chính nào từ lần Lưu lỗi.
      final before = (await transactionRepository.watchTransactions().first).length;
      // Lưu lại khi chưa đổi gì + rapid tap: vẫn 1 banner, vẫn 0 ghi mới.
      final save = find.byKey(const Key('settleLoan_save'));
      await tester.tap(save);
      await tester.tap(save, warnIfMissed: false);
      await tester.tap(save, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sheet_error_banner')), findsOneWidget);
      expect((await transactionRepository.watchTransactions().first).length, before);

      // Đổi số tiền → banner cũ biến mất ngay (không giữ lỗi của form cũ).
      await tester.ensureVisible(find.byKey(const Key('settleLoan_amount'), skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('settleLoan_amount')), '400000');
      await tester.pump();
      expect(find.byKey(const Key('sheet_error_banner')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('settleLoan_save'), skipOffstage: false));
      await tester.pumpAndSettle();
      // Bấm Lưu với số mới (vẫn thiếu số dư) → lỗi mới hiện lại, sheet còn mở.
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sheet_error_banner')), findsOneWidget);
      expect(find.byType(SettleLoanSheet), findsOneWidget);
      expect((await transactionRepository.watchTransactions().first).length, before);
    });
  });

  group('R7 — ô số tiền Vay & Cho vay', () {
    Finder createAmount() => find.byKey(const Key('createLoan_amount'));
    Finder settleAmount() => find.byKey(const Key('settleLoan_amount'));
    String textOf(WidgetTester t, Finder f) =>
        t.widget<TextField>(f).controller!.text;
    ElevatedButton buttonOf(WidgetTester t, String key) => t.widget<ElevatedButton>(
      find.byKey(Key(key), skipOffstage: false),
    );

    Future<void> openCreate(WidgetTester tester) async {
      await tester.pumpWidget(wrap(const LoansScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
    }

    Future<void> saveCreate(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const Key('createLoan_save'), skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('createLoan_save')));
      await tester.pumpAndSettle();
    }

    testWidgets('Create: bàn phím số hệ thống, chỉ chữ số, bỏ số 0 đầu, xem trước, tối đa 9 chữ số', (tester) async {
      await openCreate(tester);
      final field = tester.widget<TextField>(createAmount());
      expect(field.keyboardType, TextInputType.number);
      expect(field.inputFormatters, isNotEmpty);

      await tester.enterText(createAmount(), 'a1-2.3,4 5');
      await tester.pump();
      expect(textOf(tester, createAmount()), '12345');

      await tester.enterText(createAmount(), '0400000');
      await tester.pump();
      expect(textOf(tester, createAmount()), '400000');
      expect(find.text('400.000 đ'), findsOneWidget);

      await tester.enterText(createAmount(), '123456789');
      await tester.pump();
      await tester.enterText(createAmount(), '1234567890');
      await tester.pump();
      expect(textOf(tester, createAmount()), '123456789');
    });

    testWidgets('Create: empty và 0 → Lưu bị khoá', (tester) async {
      await openCreate(tester);
      await tester.enterText(find.byKey(const Key('createLoan_counterparty')), 'Chị Hằng');
      await tester.pump();
      expect(buttonOf(tester, 'createLoan_save').onPressed, isNull);
      await tester.enterText(createAmount(), '0');
      await tester.pump();
      expect(buttonOf(tester, 'createLoan_save').onPressed, isNull);
      await tester.enterText(createAmount(), '1');
      await tester.pump();
      expect(buttonOf(tester, 'createLoan_save').onPressed, isNotNull);
    });

    testWidgets('Create: thiếu số dư → banner trong sheet, 0 ghi; đổi số tiền → banner ẩn, tên giữ nguyên', (tester) async {
      await openCreate(tester);
      await tester.enterText(find.byKey(const Key('createLoan_counterparty')), 'Chị Hằng');
      await tester.enterText(createAmount(), '900000');
      await tester.pump();
      final before = (await transactionRepository.watchTransactions().first).length;
      await saveCreate(tester);
      expect(find.byKey(const Key('sheet_error_banner')), findsOneWidget);
      expect((await transactionRepository.watchTransactions().first).length, before);

      await tester.ensureVisible(find.byKey(const Key('createLoan_amount'), skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.enterText(createAmount(), '800000');
      await tester.pump();
      expect(find.byKey(const Key('sheet_error_banner')), findsNothing);
      expect(
        textOf(tester, find.byKey(const Key('createLoan_counterparty'), skipOffstage: false)),
        'Chị Hằng',
      );
    });

    testWidgets('Create: 0400000 → đúng 1 giao dịch mở khoản 400000 (không nhân đôi)', (tester) async {
      await openCreate(tester);
      await seedAvailable(tester, 5000000);
      final base = (await transactionRepository.watchTransactions().first).length;
      await tester.enterText(find.byKey(const Key('createLoan_counterparty')), 'Chị Lan');
      await tester.enterText(createAmount(), '0400000');
      await tester.pumpAndSettle();
      await saveCreate(tester);
      final txs = await transactionRepository.watchTransactions().first;
      expect(txs.length, base + 1);
      expect(txs.last.amountMinor, 400000);
      expect(find.byType(CreateLoanSheet), findsNothing);
    });

    Future<void> openSettleOnFreshLoan(WidgetTester tester) async {
      await tester.pumpWidget(wrap(const LoansScreen()));
      await tester.pumpAndSettle();
      await seedAvailable(tester, 5000000);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('createLoan_counterparty')), 'Chị Hằng');
      await tester.enterText(createAmount(), '1200000');
      await tester.pumpAndSettle();
      await saveCreate(tester);
      await tester.tap(find.text('Chị Hằng'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nhận tiền'));
      await tester.pumpAndSettle();
    }

    testWidgets('Settle: bàn phím số, chỉ chữ số, bỏ số 0 đầu, empty/0 khoá Lưu, xem trước', (tester) async {
      await openSettleOnFreshLoan(tester);
      final field = tester.widget<TextField>(settleAmount());
      expect(field.keyboardType, TextInputType.number);
      expect(field.inputFormatters, isNotEmpty);
      expect(buttonOf(tester, 'settleLoan_save').onPressed, isNull);

      await tester.enterText(settleAmount(), 'x5-0.0,0 0');
      await tester.pump();
      expect(textOf(tester, settleAmount()), '50000');

      await tester.enterText(settleAmount(), '0');
      await tester.pump();
      expect(buttonOf(tester, 'settleLoan_save').onPressed, isNull);

      await tester.enterText(settleAmount(), '0500000');
      await tester.pump();
      expect(textOf(tester, settleAmount()), '500000');
      expect(find.text('500.000 đ'), findsOneWidget);
      expect(buttonOf(tester, 'settleLoan_save').onPressed, isNotNull);
    });

    testWidgets('Settle: formatter KHÔNG chặn số lớn hơn outstanding (gốc/lãi vẫn do domain quyết)', (tester) async {
      await openSettleOnFreshLoan(tester);
      await tester.enterText(settleAmount(), '1500000'); // outstanding 1.200.000
      await tester.pumpAndSettle();
      expect(textOf(tester, settleAmount()), '1500000');
      expect(find.text('Thu hồi gốc'), findsOneWidget);
      expect(find.text('Tiền lãi'), findsOneWidget);
      expect(find.text('300.000 đ'), findsWidgets);
    });

    testWidgets('Settle: rapid tap Lưu → đúng 1 lần tất toán', (tester) async {
      await openSettleOnFreshLoan(tester);
      final base = (await transactionRepository.watchTransactions().first).length;
      await tester.enterText(settleAmount(), '500000');
      await tester.pumpAndSettle();
      final save = find.byKey(const Key('settleLoan_save'));
      await tester.ensureVisible(find.byKey(const Key('settleLoan_save'), skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.tap(save, warnIfMissed: false);
      await tester.tap(save, warnIfMissed: false);
      await tester.pumpAndSettle();
      // Receivable không lãi → 1 dòng thu hồi gốc.
      expect((await transactionRepository.watchTransactions().first).length, base + 1);
    });
  });

  group('Lifecycle — R3/R4/R8 (sheet Vay & Tất toán)', () {
    Finder createAmount() => find.byKey(const Key('createLoan_amount'));
    Finder settleAmount() => find.byKey(const Key('settleLoan_amount'));
    IconButton closeButton(WidgetTester t) =>
        t.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close_rounded));

    void bigScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Future<void> openCreate(WidgetTester tester) async {
      bigScreen(tester);
      await tester.pumpWidget(wrap(const LoansScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
    }

    Future<void> openSettle(WidgetTester tester) async {
      bigScreen(tester);
      await tester.pumpWidget(wrap(const LoansScreen()));
      await tester.pumpAndSettle();
      await seedAvailable(tester, 5000000);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('createLoan_counterparty')), 'Chị Hằng');
      await tester.enterText(createAmount(), '1200000');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('createLoan_save')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chị Hằng'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nhận tiền'));
      await tester.pumpAndSettle();
    }

    (double, double) keyboardSpan(WidgetTester tester, {required double keyboardHeight}) =>
        (2400.0 - keyboardHeight, keyboardHeight);

    testWidgets('Create Loan R3: kéo/vuốt xuống + chạm ngoài → sheet còn, form giữ nguyên', (tester) async {
      await openCreate(tester);
      await tester.enterText(find.byKey(const Key('createLoan_counterparty')), 'Chị Hằng');
      await tester.enterText(createAmount(), '400000');
      await tester.enterText(find.byKey(const Key('createLoan_note')), 'gap lai');
      await tester.pump();

      await tester.fling(
        find.descendant(of: find.byType(CreateLoanSheet), matching: find.byType(ListView)),
        const Offset(0, 1600),
        4000,
      );
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(540, 20));
      await tester.pumpAndSettle();

      expect(find.byType(CreateLoanSheet), findsOneWidget);
      expect(tester.widget<TextField>(createAmount()).controller!.text, '400000');
      expect(
        tester.widget<TextField>(find.byKey(const Key('createLoan_counterparty'))).controller!.text,
        'Chị Hằng',
      );
      expect(
        tester.widget<TextField>(find.byKey(const Key('createLoan_note'))).controller!.text,
        'gap lai',
      );
    });

    testWidgets('Create Loan R8: bàn phím mở → Lưu và banner lỗi nằm trên bàn phím', (tester) async {
      await openCreate(tester);
      await tester.enterText(find.byKey(const Key('createLoan_counterparty')), 'Chị Hằng');
      await tester.enterText(createAmount(), '900000'); // không đủ số dư
      await tester.pump();

      tester.view.viewInsets = const FakeViewPadding(bottom: 1000);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final (keyboardTop, _) = keyboardSpan(tester, keyboardHeight: 1000);

      final save = find.byKey(const Key('createLoan_save'));
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(keyboardTop), reason: 'Lưu phải nằm trên bàn phím');

      await tester.tap(save);
      await tester.pumpAndSettle();
      final banner = find.byKey(const Key('sheet_error_banner'));
      expect(banner, findsOneWidget);
      final rect = tester.getRect(banner);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(keyboardTop), reason: 'banner phải nhìn thấy khi bàn phím mở');
      expect(find.byType(CreateLoanSheet), findsOneWidget);
    });

    testWidgets('Settle R3: kéo/vuốt xuống + chạm ngoài → sheet còn, số tiền giữ nguyên', (tester) async {
      await openSettle(tester);
      await tester.enterText(settleAmount(), '500000');
      await tester.pump();

      await tester.fling(
        find.descendant(of: find.byType(SettleLoanSheet), matching: find.byType(ListView)),
        const Offset(0, 1600),
        4000,
      );
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(540, 20));
      await tester.pumpAndSettle();

      expect(find.byType(SettleLoanSheet), findsOneWidget);
      expect(tester.widget<TextField>(settleAmount()).controller!.text, '500000');
    });

    testWidgets('Settle R4: IDLE Back đóng được; đang submit Back/X bị chặn, xong mới đóng, đúng 1 lần ghi', (tester) async {
      await openSettle(tester);
      expect(closeButton(tester).onPressed, isNotNull);

      await tester.enterText(settleAmount(), '500000');
      await tester.pump();
      final base = (await transactionRepository.watchTransactions().first).length;
      transactionRepository.pendingGate = Completer<void>();
      final save = find.byKey(const Key('settleLoan_save'));
      await tester.tap(save);
      await tester.pump();

      expect(closeButton(tester).onPressed, isNull, reason: 'X bị khoá khi đang submit');
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(SettleLoanSheet), findsOneWidget, reason: 'Back bị chặn khi đang submit');

      transactionRepository.pendingGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(SettleLoanSheet), findsNothing);
      expect((await transactionRepository.watchTransactions().first).length, base + 1);
    });

    testWidgets('Settle R4: sau lỗi (trả nợ vượt số dư) sheet vẫn mở, Back/X hoạt động lại', (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(wrap(const LoansScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mình đang nợ'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('createLoan_counterparty')), 'Anh Nam');
      await tester.enterText(createAmount(), '1000000');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('createLoan_save')));
      await tester.pumpAndSettle();
      // Tiêu hết tiền vừa vay → trả nợ sẽ thiếu số dư.
      final now = DateTime(2026, 1, 2);
      await transactionRepository.addTransaction(
        Transaction(
          id: IdGenerator.generate(),
          type: TransactionType.expense,
          categoryId: 'sinh_hoat',
          sourceKind: PoolKind.memberAvailable,
          sourceRefId: 'vo',
          destinationKind: PoolKind.external,
          amountMinor: 1000000,
          transactionDate: now,
          createdAt: now,
          clientTxId: IdGenerator.generate(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anh Nam'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trả tiền'));
      await tester.pumpAndSettle();
      await tester.enterText(settleAmount(), '500000');
      await tester.pump();
      final base = (await transactionRepository.watchTransactions().first).length;
      await tester.tap(find.byKey(const Key('settleLoan_save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sheet_error_banner')), findsOneWidget);
      expect(find.byType(SettleLoanSheet), findsOneWidget);
      expect((await transactionRepository.watchTransactions().first).length, base, reason: '0 ghi khi lỗi');
      expect(closeButton(tester).onPressed, isNotNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SettleLoanSheet), findsNothing);
    });

    testWidgets('Settle R8: bàn phím mở → Lưu nằm trên bàn phím', (tester) async {
      await openSettle(tester);
      await tester.enterText(settleAmount(), '500000');
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 1000);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final (keyboardTop, _) = keyboardSpan(tester, keyboardHeight: 1000);
      final save = find.byKey(const Key('settleLoan_save'));
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(keyboardTop));
      expect(tester.getRect(save).top, greaterThanOrEqualTo(0));
    });
  });
}
