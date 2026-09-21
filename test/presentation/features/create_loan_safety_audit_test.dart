import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/entities/counterparty.dart';
import 'package:vi_nha_minh/domain/entities/obligation.dart';
import 'package:vi_nha_minh/domain/entities/obligation_direction.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/errors/domain_exceptions.dart';
import 'package:vi_nha_minh/domain/repositories/counterparty_repository.dart';
import 'package:vi_nha_minh/domain/repositories/obligation_repository.dart';
import 'package:vi_nha_minh/domain/usecases/compute_obligation_summary.dart';
import 'package:vi_nha_minh/presentation/features/loans/create_loan_sheet.dart';
import 'package:vi_nha_minh/presentation/providers/counterparty_providers.dart';
import 'package:vi_nha_minh/presentation/providers/obligation_providers.dart';
import 'package:vi_nha_minh/presentation/providers/transaction_providers.dart';

import '../../application/support/recording_transaction_repository.dart';
import '../../support/legacy_members.dart';

class _Counterparties implements CounterpartyRepository {
  final rows = <Counterparty>[];
  @override
  Future<void> addCounterparty(Counterparty value) async => rows.add(value);
  @override
  Stream<List<Counterparty>> watchCounterparties() => Stream.value(rows);
  @override
  Future<void> updateCounterparty(Counterparty value) =>
      throw UnimplementedError();
  @override
  Future<void> softDeleteCounterparty(String id) => throw UnimplementedError();
}

class _Obligations implements ObligationRepository {
  _Obligations(this.ledger);
  final _Transactions ledger;
  final attemptedMetadata = <Obligation>[];
  final rows = <Obligation>[];
  Completer<void>? afterWrite;
  final written = Completer<void>();
  @override
  Future<void> addObligation(Obligation value) => throw StateError('Use atomic create');

  @override
  Future<Transaction> createObligationWithOpeningTransaction(Obligation value, Transaction opening) async {
    attemptedMetadata.add(value);
    if (!written.isCompleted) written.complete();
    if (afterWrite != null) await afterWrite!.future;
    final result = await ledger.addTransaction(opening);
    rows.add(value);
    return result;
  }

  @override
  Stream<List<Obligation>> watchObligations() => Stream.value(rows);
  @override
  Future<void> updateObligation(Obligation value) => throw UnimplementedError();
}

class _Transactions extends RecordingTransactionRepository {
  final attempts = <Transaction>[];
  @override
  Future<Transaction> addTransaction(Transaction transaction) {
    attempts.add(transaction);
    return super.addTransaction(transaction);
  }
}

// Production UI and Application through a controllable atomic boundary.
// Database rollback itself is covered by atomic_obligation_creation_test.dart.
void main() {
  late _Counterparties counterparties;
  late _Obligations obligations;
  late _Transactions transactions;

  setUp(() {
    counterparties = _Counterparties();
    transactions = _Transactions();
    obligations = _Obligations(transactions);
  });

  Future<void> openSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
        ...legacyMemberOverrides,
          counterpartyRepositoryProvider.overrideWithValue(counterparties),
          obligationRepositoryProvider.overrideWithValue(obligations),
          transactionRepositoryProvider.overrideWithValue(transactions),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showCreateLoanSheet(
                  context,
                  direction: ObligationDirection.payable,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester
        .pumpAndSettle(); // modal route animation and initial provider emission
    await tester.enterText(
      find.byKey(const Key('createLoan_counterparty')),
      'Person A',
    );
    await tester.enterText(
      find.byKey(const Key('createLoan_amount')),
      '100000',
    );
    await tester.pump(); // enable Save for the valid form
  }

  Future<void> save(WidgetTester tester) async {
    final button = find.byKey(const Key('createLoan_save'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle(); // complete mutation futures and route/snackbar animations
  }

  testWidgets(
    'atomic failure keeps form and no metadata; unchanged retry reuses identity',
    (tester) async {
      transactions.throwOnAdd = const PersistenceException(
        'injected before transaction write',
      );
      await openSheet(tester);
      await save(tester);
      expect(counterparties.rows, hasLength(1));
      expect(obligations.rows, isEmpty);
      expect(transactions.lastAdded, isNull);
      expect(tester.widget<TextField>(find.byKey(const Key('createLoan_amount'))).controller!.text, '100000');
      expect(find.text('Có lỗi khi lưu dữ liệu, vui lòng thử lại.'), findsOneWidget);
      expect(find.byType(CreateLoanSheet), findsOneWidget);
      final failed = transactions.attempts.single;
      transactions.throwOnAdd = null;
      await save(tester);
      expect(obligations.rows, hasLength(1));
      expect(transactions.lastAdded!.obligationId, failed.obligationId);
      expect(transactions.lastAdded!.clientTxId, failed.clientTxId);
      expect(transactions.lastAdded!.id, failed.id);
      expect(find.byType(CreateLoanSheet), findsNothing);
    },
  );

  testWidgets(
    'editing after failure creates another identity without orphan metadata',
    (tester) async {
      transactions.throwOnAdd = const PersistenceException(
        'injected before transaction write',
      );
      await openSheet(tester);
      await save(tester);
      final abandoned = obligations.attemptedMetadata.single;
      final failedClient = transactions.attempts.single.clientTxId;
      expect(obligations.rows, isEmpty);
      transactions.throwOnAdd = null;
      await tester.enterText(
        find.byKey(const Key('createLoan_amount')),
        '200000',
      );
      await tester.pump();
      await save(tester);
      expect(obligations.rows, hasLength(1));
      expect(transactions.lastAdded!.clientTxId, isNot(failedClient));
      expect(transactions.lastAdded!.amountMinor, 200000);
      expect(transactions.lastAdded!.obligationId, isNot(abandoned.id));
      expect(
        computeObligationSummary(abandoned, [transactions.lastAdded!]),
        isNull,
      );
    },
  );

  testWidgets(
    'pending create locks controls and dismiss; no double-submit or lost linkage',
    (tester) async {
      obligations.afterWrite = Completer<void>();
      await openSheet(tester);
      await save(tester);
      // Await the atomic boundary, not a guessed delay. No false-success close.
      expect(obligations.written.isCompleted, isTrue);
      expect(obligations.rows, isEmpty);
      expect(find.byType(CreateLoanSheet), findsOneWidget);
      expect(transactions.attempts, isEmpty);
      final amountField = find.byKey(const Key('createLoan_amount'));
      for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
        expect(field.enabled, isFalse);
      }
      await tester.ensureVisible(amountField);
      await tester.tap(amountField);
      await tester.pump();
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.widget<TextField>(amountField).controller!.text, '100000');
      expect(tester.widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>)).onSelectionChanged, isNull);
      for (final button in tester.widgetList<OutlinedButton>(find.byType(OutlinedButton))) {
        expect(button.onPressed, isNull);
      }
      for (final button in tester.widgetList<IconButton>(find.byType(IconButton))) {
        expect(button.onPressed, isNull);
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(CreateLoanSheet), findsOneWidget);
      await save(tester);
      expect(obligations.attemptedMetadata, hasLength(1));
      obligations.afterWrite!.complete();
      await tester.pumpAndSettle();
      expect(transactions.lastAdded, isNotNull);
      expect(
        transactions.lastAdded!.obligationId,
        obligations.rows.single.id,
        reason: 'Opening retains the immutable loan identity.',
      );
      expect(
        transactions.lastAdded!.amountMinor,
        100000,
        reason: 'The form could not change the in-flight request.',
      );
      expect(
        computeObligationSummary(obligations.rows.single, [
          transactions.lastAdded!,
        ]),
        isNotNull,
      );
      expect(
        find.byType(CreateLoanSheet),
        findsNothing,
        reason: 'The UI closes only after the atomic operation succeeds.',
      );
    },
  );
}
