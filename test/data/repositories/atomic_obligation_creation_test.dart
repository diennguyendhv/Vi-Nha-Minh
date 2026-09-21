import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/repositories/local_obligation_repository.dart';
import 'package:vi_nha_minh/data/repositories/local_transaction_repository.dart';
import 'package:vi_nha_minh/domain/entities/obligation.dart';
import 'package:vi_nha_minh/domain/entities/obligation_direction.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/errors/domain_exceptions.dart';
import 'package:vi_nha_minh/domain/usecases/compute_financial_summary.dart';
import '../../support/legacy_members.dart';

void main() {
  late AppDatabase db;
  late LocalObligationRepository loans;
  late LocalTransactionRepository ledger;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    loans = LocalObligationRepository(db);
    ledger = LocalTransactionRepository(db);
    await db.into(db.counterpartyRows).insert(CounterpartyRowsCompanion.insert(id: 'person', displayName: 'Person'));
    await ledger.addTransaction(Transaction(
      id: 'seed', clientTxId: 'seed-client', type: TransactionType.income,
      categoryId: 'thu_nhap', sourceKind: PoolKind.external,
      destinationKind: PoolKind.memberAvailable, destinationRefId: 'vo',
      amountMinor: 5000000, transactionDate: DateTime(2026, 1, 1), createdAt: DateTime(2026, 1, 1),
    ));
  });
  tearDown(() => db.close());

  Obligation metadata(ObligationDirection direction) => Obligation(
    id: 'loan', counterpartyId: 'person', direction: direction,
    dueDate: DateTime(2026, 12, 1), note: 'loan note',
  );

  Transaction opening(ObligationDirection direction, {int amount = 1200000, String category = '', String? link = 'loan'}) {
    final receivable = direction == ObligationDirection.receivable;
    return Transaction(
      id: 'opening', clientTxId: 'opening-client',
      type: receivable ? TransactionType.transfer : TransactionType.income,
      categoryId: category.isNotEmpty ? category : (receivable ? 'cho_vay' : 'vay_no'),
      sourceKind: receivable ? PoolKind.memberAvailable : PoolKind.external,
      sourceRefId: receivable ? 'vo' : null,
      destinationKind: receivable ? PoolKind.receivable : PoolKind.memberAvailable,
      destinationRefId: receivable ? 'loan' : 'vo', obligationId: link,
      amountMinor: amount, transactionDate: DateTime(2026, 9, 18), createdAt: DateTime.now(),
      note: 'opening note',
    );
  }

  Future<void> injectFailure() => db.customStatement('''
    CREATE TEMP TRIGGER fail_opening BEFORE INSERT ON transaction_rows
    WHEN NEW.id = 'opening' AND EXISTS (SELECT 1 FROM obligation_rows WHERE id = 'loan')
    BEGIN SELECT RAISE(ABORT, 'injected opening failure after metadata insert'); END
  ''');

  Future<FinancialSummary> summary() async => computeFinancialSummary(members: legacyMembers, 
    await ledger.watchTransactions().first,
    categories: [], funds: [], assetTypes: [], obligations: await loans.watchObligations().first,
  );

  for (final direction in ObligationDirection.values) {
    test('$direction: atomic success, relationship and duplicate retry', () async {
      final command = opening(direction);
      final result = await loans.createObligationWithOpeningTransaction(metadata(direction), command);
      expect(result.obligationId, 'loan');
      final retry = await loans.createObligationWithOpeningTransaction(metadata(direction), command);
      expect(retry.id, result.id);
      expect(await loans.watchObligations().first, hasLength(1));
      expect((await ledger.watchTransactions().first).where((t) => t.obligationId == 'loan'), hasLength(1));
      final totals = await summary();
      expect(totals.totalReceivables, direction == ObligationDirection.receivable ? 1200000 : 0);
      expect(totals.totalPayables, direction == ObligationDirection.payable ? 1200000 : 0);
    });

    test('$direction: SQL failure AFTER metadata insert rolls back both, no stream ghost, retry succeeds', () async {
      final emissions = <List<Obligation>>[];
      final initial = Completer<void>();
      final committed = Completer<void>();
      final subscription = loans.watchObligations().listen((value) {
        emissions.add(value);
        if (!initial.isCompleted) initial.complete();
        if (value.isNotEmpty && !committed.isCompleted) committed.complete();
      });
      addTearDown(subscription.cancel);
      await initial.future;
      final before = await summary();
      await injectFailure();
      await expectLater(loans.createObligationWithOpeningTransaction(metadata(direction), opening(direction)),
        throwsA(isA<PersistenceConstraintException>()));
      expect(await db.select(db.obligationRows).get(), isEmpty);
      expect((await ledger.watchTransactions().first).where((t) => t.id == 'opening'), isEmpty);
      expect(await loans.watchObligations().first, isEmpty);
      final after = await summary();
      expect(after.totalAvailable, before.totalAvailable);
      expect(after.totalReceivables, before.totalReceivables);
      expect(after.totalPayables, before.totalPayables);
      expect(after.totalAssets, before.totalAssets);
      expect(after.netWorth, before.netWorth);
      expect(emissions.every((list) => list.isEmpty), isTrue);
      expect(committed.isCompleted, isFalse);
      await db.customStatement('DROP TRIGGER fail_opening');
      await loans.createObligationWithOpeningTransaction(metadata(direction), opening(direction));
      await committed.future;
      expect(await loans.watchObligations().first, hasLength(1));
      expect((await ledger.watchTransactions().first).where((t) => t.id == 'opening'), hasLength(1));
    });

    test('$direction: changed payload with same client identity conflicts without mutation', () async {
      await loans.createObligationWithOpeningTransaction(metadata(direction), opening(direction));
      await expectLater(loans.createObligationWithOpeningTransaction(metadata(direction), opening(direction, amount: 1300000)),
        throwsA(isA<ClientTxIdConflictException>()));
      await expectLater(loans.createObligationWithOpeningTransaction(metadata(direction).copyWith(note: 'changed'), opening(direction)),
        throwsA(isA<ClientTxIdConflictException>()));
      expect((await loans.watchObligations().first).single.note, 'loan note');
      expect((await ledger.getTransactionByClientTxId('opening-client'))!.amountMinor, 1200000);
    });
  }

  test('insufficient balance and missing category both roll back metadata', () async {
    await expectLater(loans.createObligationWithOpeningTransaction(metadata(ObligationDirection.receivable), opening(ObligationDirection.receivable, amount: 6000000)),
      throwsA(isA<InsufficientBalanceException>()));
    expect(await loans.watchObligations().first, isEmpty);
    await expectLater(loans.createObligationWithOpeningTransaction(metadata(ObligationDirection.payable), opening(ObligationDirection.payable, category: 'missing')),
      throwsA(isA<PersistenceConstraintException>()));
    expect(await loans.watchObligations().first, isEmpty);
    expect(await ledger.watchTransactions().first, hasLength(1));
  });

  test('missing relationship cannot create an ordinary income instead of a loan', () async {
    await expectLater(loans.createObligationWithOpeningTransaction(metadata(ObligationDirection.payable), opening(ObligationDirection.payable, link: null)),
      throwsA(isA<PersistenceConstraintException>()));
    expect(await loans.watchObligations().first, isEmpty);
    expect(await ledger.watchTransactions().first, hasLength(1));
  });

  test('concurrent duplicate commands share one committed opening', () async {
    final command = opening(ObligationDirection.payable);
    final results = await Future.wait(List.generate(2, (_) => loans.createObligationWithOpeningTransaction(metadata(ObligationDirection.payable), command)));
    expect(results.map((t) => t.id).toSet(), {'opening'});
    expect(await loans.watchObligations().first, hasLength(1));
    expect(await ledger.watchTransactions().first, hasLength(2));
  });
}
