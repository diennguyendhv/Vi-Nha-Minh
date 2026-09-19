import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/engine/financial_engine.dart';
import 'package:vi_nha_minh/domain/engine/obligation_settlement.dart';
import 'package:vi_nha_minh/domain/entities/obligation.dart';
import 'package:vi_nha_minh/domain/entities/obligation_direction.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/usecases/compute_obligation_summary.dart';

/// Phase 8.7 — test THUẦN DOMAIN (không DB) cho engine Receivable/Payable:
/// build legs, outstanding, phân bổ lãi. Atomicity/idempotency/reversal
/// thật qua DB xem `test/data/repositories/obligation_repository_test.dart`.
void main() {
  int seq = 0;
  String nextId(String p) => '$p-${seq++}';

  Transaction receivableCreation({
    String? obligationId,
    int amountMinor = 1200000,
    String member = 'vo',
    DateTime? date,
  }) {
    final id = obligationId ?? 'oblig-r';
    return Transaction(
      id: nextId('creation'),
      type: TransactionType.transfer,
      categoryId: 'cho_vay',
      sourceKind: PoolKind.memberAvailable,
      sourceRefId: member,
      destinationKind: PoolKind.receivable,
      destinationRefId: id,
      amountMinor: amountMinor,
      obligationId: id,
      transactionDate: date ?? DateTime(2026, 5, 8),
      createdAt: date ?? DateTime(2026, 5, 8),
      clientTxId: nextId('client'),
    );
  }

  Transaction payableCreation({
    String? obligationId,
    int amountMinor = 700000,
    String member = 'vo',
    DateTime? date,
  }) {
    final id = obligationId ?? 'oblig-p';
    return Transaction(
      id: nextId('creation'),
      type: TransactionType.income,
      categoryId: 'vay_no',
      sourceKind: PoolKind.external,
      destinationKind: PoolKind.memberAvailable,
      destinationRefId: member,
      amountMinor: amountMinor,
      obligationId: id,
      transactionDate: date ?? DateTime(2026, 5, 8),
      createdAt: date ?? DateTime(2026, 5, 8),
      clientTxId: nextId('client'),
    );
  }

  group('Example A/B/C — Receivable (mục "REQUIRED DOMAIN EXAMPLES")', () {
    test('A: Cho vay 1.200.000 → Available -1.2m, Receivable +1.2m, Net Worth unchanged', () {
      final creation = receivableCreation(obligationId: 'r-a', amountMinor: 1200000);
      final balances = computeAllPoolBalances([creation]);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'vo'), -1200000);
      expect(poolBalance(balances, PoolKind.receivable, 'r-a'), 1200000);
      expect(balances.values.fold<int>(0, (s, v) => s + v), 0, reason: 'Total Assets 0 change — transfer tự cân bằng');
    });

    test('B: Nhận lại đúng 1.200.000 → Available +1.2m, Receivable 0, Income 0', () {
      final creation = receivableCreation(obligationId: 'r-b', amountMinor: 1200000);
      final all = [creation];
      final balances = computeAllPoolBalances(all);
      final outstanding = computeObligationOutstanding(
        ObligationDirection.receivable,
        'r-b',
        all,
        balances,
      );
      expect(outstanding, 1200000);

      final legs = buildObligationSettlementLegs(
        direction: ObligationDirection.receivable,
        obligationId: 'r-b',
        memberRefId: 'vo',
        outstanding: outstanding,
        paymentAmount: 1200000,
        categoryId: 'cho_vay',
        interestCategoryId: 'lai_cho_vay',
        currency: 'VND',
        principalId: 'p-b',
        principalClientTxId: 'c-b',
        interestId: 'i-b',
        interestClientTxId: 'ci-b',
        transactionDate: DateTime(2027, 7, 1),
        now: DateTime(2027, 7, 1),
      );
      expect(legs.interest, isNull, reason: 'không lãi → 1 dòng duy nhất');
      expect(legs.principal.amountMinor, 1200000);
      expect(legs.principal.type, TransactionType.transfer);

      final after = computeAllPoolBalances([...all, legs.principal]);
      expect(poolBalance(after, PoolKind.memberAvailable, 'vo'), 0);
      expect(poolBalance(after, PoolKind.receivable, 'r-b'), 0);
    });

    test('C (quan trọng nhất): Nhận 1.400.000 trên gốc 1.2m → Principal 1.2m, Interest Income 200k, Receivable 0', () {
      final creation = receivableCreation(obligationId: 'r-c', amountMinor: 1200000);
      final all = [creation];
      final balances = computeAllPoolBalances(all);
      final outstanding = computeObligationOutstanding(
        ObligationDirection.receivable,
        'r-c',
        all,
        balances,
      );

      final legs = buildObligationSettlementLegs(
        direction: ObligationDirection.receivable,
        obligationId: 'r-c',
        memberRefId: 'vo',
        outstanding: outstanding,
        paymentAmount: 1400000,
        categoryId: 'cho_vay',
        interestCategoryId: 'lai_cho_vay',
        currency: 'VND',
        principalId: 'p-c',
        principalClientTxId: 'c-c',
        interestId: 'i-c',
        interestClientTxId: 'ci-c',
        transactionDate: DateTime(2027, 7, 1),
        now: DateTime(2027, 7, 1),
      );

      expect(legs.principal.amountMinor, 1200000, reason: 'principal KHÔNG được là 1.4m');
      expect(legs.interest, isNotNull);
      expect(legs.interest!.amountMinor, 200000);
      expect(legs.interest!.type, TransactionType.income);
      expect(legs.interest!.settlementGroupId, legs.principal.id, reason: 'ghép cặp qua settlementGroupId');

      final after = computeAllPoolBalances([...all, ...legs.legs]);
      expect(poolBalance(after, PoolKind.memberAvailable, 'vo'), 200000, reason: 'net: -1.2m (cho vay) + 1.4m (thu về) = +200k');
      expect(poolBalance(after, PoolKind.receivable, 'r-c'), 0);
      // Available effect CỦA RIÊNG lần thu hồi = +1.4m (khớp STOP condition).
      final beforeSettle = computeAllPoolBalances(all);
      final availBefore = poolBalance(beforeSettle, PoolKind.memberAvailable, 'vo');
      final availAfter = poolBalance(after, PoolKind.memberAvailable, 'vo');
      expect(availAfter - availBefore, 1400000);
    });

    test('Bán lỗ tương tự — nhận 4.500.000 trên gốc 6.000.000 (STEP 8 tổng quát)', () {
      final creation = receivableCreation(obligationId: 'r-loss', amountMinor: 6000000);
      final all = [creation];
      final balances = computeAllPoolBalances(all);
      final outstanding = computeObligationOutstanding(
        ObligationDirection.receivable,
        'r-loss',
        all,
        balances,
      );
      final legs = buildObligationSettlementLegs(
        direction: ObligationDirection.receivable,
        obligationId: 'r-loss',
        memberRefId: 'vo',
        outstanding: outstanding,
        paymentAmount: 4500000,
        categoryId: 'cho_vay',
        interestCategoryId: 'lai_cho_vay',
        currency: 'VND',
        principalId: 'p-loss',
        principalClientTxId: 'c-loss',
        interestId: 'i-loss',
        interestClientTxId: 'ci-loss',
        transactionDate: DateTime(2027, 1, 1),
        now: DateTime(2027, 1, 1),
      );
      expect(legs.interest, isNull, reason: 'thu ít hơn gốc → không có lãi');
      expect(legs.principal.amountMinor, 4500000);
    });
  });

  group('Example D/E/F — Payable', () {
    test('D: Mượn 700.000 → Available +700k, Payable(outstanding) +700k, Income 0, Net Worth unchanged', () {
      final creation = payableCreation(obligationId: 'p-d', amountMinor: 700000);
      final balances = computeAllPoolBalances([creation]);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'vo'), 700000);
      final outstanding = computeObligationOutstanding(
        ObligationDirection.payable,
        'p-d',
        [creation],
        balances,
      );
      expect(outstanding, 700000);
      // netWorth impact = totalAssets(+700k) - totalPayables(+700k) = 0.
    });

    test('E: Trả đúng 700.000 → Available -700k, Payable 0, Expense 0', () {
      final creation = payableCreation(obligationId: 'p-e', amountMinor: 700000);
      final all = [creation];
      final outstanding = computeObligationOutstanding(
        ObligationDirection.payable,
        'p-e',
        all,
        computeAllPoolBalances(all),
      );
      final legs = buildObligationSettlementLegs(
        direction: ObligationDirection.payable,
        obligationId: 'p-e',
        memberRefId: 'vo',
        outstanding: outstanding,
        paymentAmount: 700000,
        categoryId: 'tra_no',
        interestCategoryId: 'tra_no',
        currency: 'VND',
        principalId: 'pp-e',
        principalClientTxId: 'cc-e',
        interestId: 'ii-e',
        interestClientTxId: 'cci-e',
        transactionDate: DateTime(2027, 5, 1),
        now: DateTime(2027, 5, 1),
      );
      expect(legs.interest, isNull, reason: 'Payable KHÔNG BAO GIỜ tách leg riêng');
      expect(legs.principal.type, TransactionType.expense);
      expect(legs.principal.amountMinor, 700000);

      final after = computeAllPoolBalances([...all, legs.principal]);
      expect(poolBalance(after, PoolKind.memberAvailable, 'vo'), 0);
      final newOutstanding = computeObligationOutstanding(
        ObligationDirection.payable,
        'p-e',
        [...all, legs.principal],
        after,
      );
      expect(newOutstanding, 0);
    });

    test('F (quan trọng nhất): Trả 800.000 trên nợ 700.000 → Principal 700k + Interest Expense 100k gộp 1 dòng', () {
      final creation = payableCreation(obligationId: 'p-f', amountMinor: 700000);
      final all = [creation];
      final outstanding = computeObligationOutstanding(
        ObligationDirection.payable,
        'p-f',
        all,
        computeAllPoolBalances(all),
      );
      final legs = buildObligationSettlementLegs(
        direction: ObligationDirection.payable,
        obligationId: 'p-f',
        memberRefId: 'vo',
        outstanding: outstanding,
        paymentAmount: 800000,
        categoryId: 'tra_no',
        interestCategoryId: 'tra_no',
        currency: 'VND',
        principalId: 'pp-f',
        principalClientTxId: 'cc-f',
        interestId: 'ii-f',
        interestClientTxId: 'cci-f',
        transactionDate: DateTime(2027, 5, 1),
        now: DateTime(2027, 5, 1),
      );
      expect(legs.interest, isNull);
      expect(legs.principal.amountMinor, 800000, reason: 'gộp cả gốc+lãi cùng 1 dòng (cùng chiều tiền)');

      final portions = computeObligationSettlementInterestPortions([...all, legs.principal]);
      expect(portions[legs.principal.id], 100000, reason: 'lãi report được = 100.000, KHÔNG phải 800.000');

      final after = computeAllPoolBalances([...all, legs.principal]);
      expect(poolBalance(after, PoolKind.memberAvailable, 'vo'), -100000, reason: 'net: +700k (vay) - 800k (trả) = -100k');
    });
  });

  group('Partial settlement — Receivable (STEP 4 / mục 4)', () {
    test('1.200.000 → 500k → 400k → 500k (300k gốc + 200k lãi)', () {
      final creation = receivableCreation(obligationId: 'r-partial', amountMinor: 1200000);
      var all = [creation];

      int outstandingOf() => computeObligationOutstanding(
        ObligationDirection.receivable,
        'r-partial',
        all,
        computeAllPoolBalances(all),
      );

      final r1 = buildObligationSettlementLegs(
        direction: ObligationDirection.receivable,
        obligationId: 'r-partial',
        memberRefId: 'vo',
        outstanding: outstandingOf(),
        paymentAmount: 500000,
        categoryId: 'cho_vay',
        interestCategoryId: 'lai_cho_vay',
        currency: 'VND',
        principalId: 'r1',
        principalClientTxId: 'c-r1',
        interestId: 'i-r1',
        interestClientTxId: 'ci-r1',
        transactionDate: DateTime(2026, 6, 1),
        now: DateTime(2026, 6, 1),
      );
      expect(r1.interest, isNull);
      all = [...all, r1.principal];
      expect(outstandingOf(), 700000);

      final r2 = buildObligationSettlementLegs(
        direction: ObligationDirection.receivable,
        obligationId: 'r-partial',
        memberRefId: 'vo',
        outstanding: outstandingOf(),
        paymentAmount: 400000,
        categoryId: 'cho_vay',
        interestCategoryId: 'lai_cho_vay',
        currency: 'VND',
        principalId: 'r2',
        principalClientTxId: 'c-r2',
        interestId: 'i-r2',
        interestClientTxId: 'ci-r2',
        transactionDate: DateTime(2026, 7, 1),
        now: DateTime(2026, 7, 1),
      );
      expect(r2.interest, isNull);
      all = [...all, r2.principal];
      expect(outstandingOf(), 300000);

      final r3 = buildObligationSettlementLegs(
        direction: ObligationDirection.receivable,
        obligationId: 'r-partial',
        memberRefId: 'vo',
        outstanding: outstandingOf(),
        paymentAmount: 500000,
        categoryId: 'cho_vay',
        interestCategoryId: 'lai_cho_vay',
        currency: 'VND',
        principalId: 'r3',
        principalClientTxId: 'c-r3',
        interestId: 'i-r3',
        interestClientTxId: 'ci-r3',
        transactionDate: DateTime(2026, 8, 1),
        now: DateTime(2026, 8, 1),
      );
      expect(r3.principal.amountMinor, 300000);
      expect(r3.interest!.amountMinor, 200000);
      all = [...all, ...r3.legs];
      expect(outstandingOf(), 0);
    });
  });

  group('Partial settlement — Payable (STEP 8 / mục 4 đối xứng)', () {
    test('700.000 → trả 200k → trả 300k → trả 250k (200k gốc + 50k lãi)', () {
      final creation = payableCreation(obligationId: 'p-partial', amountMinor: 700000);
      var all = [creation];

      int outstandingOf() => computeObligationOutstanding(
        ObligationDirection.payable,
        'p-partial',
        all,
        computeAllPoolBalances(all),
      );

      final pay1 = buildObligationSettlementLegs(
        direction: ObligationDirection.payable,
        obligationId: 'p-partial',
        memberRefId: 'vo',
        outstanding: outstandingOf(),
        paymentAmount: 200000,
        categoryId: 'tra_no',
        interestCategoryId: 'tra_no',
        currency: 'VND',
        principalId: 'pay1',
        principalClientTxId: 'c-pay1',
        interestId: 'i-pay1',
        interestClientTxId: 'ci-pay1',
        transactionDate: DateTime(2026, 6, 1),
        now: DateTime(2026, 6, 1),
      );
      all = [...all, pay1.principal];
      expect(outstandingOf(), 500000);

      final pay2 = buildObligationSettlementLegs(
        direction: ObligationDirection.payable,
        obligationId: 'p-partial',
        memberRefId: 'vo',
        outstanding: outstandingOf(),
        paymentAmount: 300000,
        categoryId: 'tra_no',
        interestCategoryId: 'tra_no',
        currency: 'VND',
        principalId: 'pay2',
        principalClientTxId: 'c-pay2',
        interestId: 'i-pay2',
        interestClientTxId: 'ci-pay2',
        transactionDate: DateTime(2026, 7, 1),
        now: DateTime(2026, 7, 1),
      );
      all = [...all, pay2.principal];
      expect(outstandingOf(), 200000);

      final pay3 = buildObligationSettlementLegs(
        direction: ObligationDirection.payable,
        obligationId: 'p-partial',
        memberRefId: 'vo',
        outstanding: outstandingOf(),
        paymentAmount: 250000,
        categoryId: 'tra_no',
        interestCategoryId: 'tra_no',
        currency: 'VND',
        principalId: 'pay3',
        principalClientTxId: 'c-pay3',
        interestId: 'i-pay3',
        interestClientTxId: 'ci-pay3',
        transactionDate: DateTime(2026, 8, 1),
        now: DateTime(2026, 8, 1),
      );
      all = [...all, pay3.principal];
      expect(outstandingOf(), 0);

      final portions = computeObligationSettlementInterestPortions(all);
      expect(portions[pay1.principal.id] ?? 0, 0);
      expect(portions[pay2.principal.id] ?? 0, 0);
      expect(portions[pay3.principal.id] ?? 0, 50000, reason: 'chỉ lần cuối mới có lãi 50.000');
    });
  });

  group('computeObligationSummary — status derived', () {
    test('open/partiallySettled/settled đúng theo outstanding', () {
      final creation = payableCreation(obligationId: 'p-status', amountMinor: 1000000);
      final obligation = _obligation('p-status', ObligationDirection.payable);
      final summaryOpen = computeObligationSummary(obligation, [creation]);
      expect(summaryOpen!.status, ObligationStatus.open);

      final legs = buildObligationSettlementLegs(
        direction: ObligationDirection.payable,
        obligationId: 'p-status',
        memberRefId: 'vo',
        outstanding: 1000000,
        paymentAmount: 400000,
        categoryId: 'tra_no',
        interestCategoryId: 'tra_no',
        currency: 'VND',
        principalId: 'leg1',
        principalClientTxId: 'c1',
        interestId: 'i1',
        interestClientTxId: 'ci1',
        transactionDate: DateTime(2026, 6, 1),
        now: DateTime(2026, 6, 1),
      );
      final summaryPartial = computeObligationSummary(obligation, [creation, legs.principal]);
      expect(summaryPartial!.status, ObligationStatus.partiallySettled);
      expect(summaryPartial.outstanding, 600000);

      final legs2 = buildObligationSettlementLegs(
        direction: ObligationDirection.payable,
        obligationId: 'p-status',
        memberRefId: 'vo',
        outstanding: 600000,
        paymentAmount: 600000,
        categoryId: 'tra_no',
        interestCategoryId: 'tra_no',
        currency: 'VND',
        principalId: 'leg2',
        principalClientTxId: 'c2',
        interestId: 'i2',
        interestClientTxId: 'ci2',
        transactionDate: DateTime(2026, 7, 1),
        now: DateTime(2026, 7, 1),
      );
      final summarySettled = computeObligationSummary(
        obligation,
        [creation, legs.principal, legs2.principal],
      );
      expect(summarySettled!.status, ObligationStatus.settled);
      expect(summarySettled.outstanding, 0);
    });

    test('chưa từng tạo giao dịch gốc → null', () {
      final obligation = _obligation('never-created', ObligationDirection.receivable);
      expect(computeObligationSummary(obligation, const []), isNull);
    });
  });
}

Obligation _obligation(String id, ObligationDirection direction) {
  return Obligation(id: id, counterpartyId: 'cp-1', direction: direction);
}
