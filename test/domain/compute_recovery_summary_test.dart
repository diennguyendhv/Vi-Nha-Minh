import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/engine/financial_engine.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/usecases/compute_recovery_summary.dart';

int _seq = 0;

Transaction _expense({String id = 'expense-1', int amountMinor = 2000000}) {
  return Transaction(
    id: id,
    type: TransactionType.expense,
    categoryId: 'dau_tu',
    sourceKind: PoolKind.memberAvailable,
    sourceRefId: 'chong',
    destinationKind: PoolKind.external,
    amountMinor: amountMinor,
    transactionDate: DateTime(2026, 1, 1),
    createdAt: DateTime(2026, 1, 1),
    clientTxId: 'client-$id',
  );
}

Transaction _recovery({
  required String recoveryOfTxId,
  required int amountMinor,
  String? id,
  DateTime? date,
}) {
  _seq++;
  return Transaction(
    id: id ?? 'recovery-$_seq',
    type: TransactionType.income,
    categoryId: 'hoan_tien_thu_hoi',
    sourceKind: PoolKind.external,
    destinationKind: PoolKind.memberAvailable,
    destinationRefId: 'chong',
    amountMinor: amountMinor,
    recoveryOfTxId: recoveryOfTxId,
    transactionDate: date ?? DateTime(2026, 1, 5),
    createdAt: date ?? DateTime(2026, 1, 5),
    clientTxId: 'client-recovery-$_seq',
  );
}

void main() {
  group('Case 1 — Asset resale (mục 16)', () {
    test('Expense 2.000.000, Recovery 450.000 → Available -1.550.000, netCost 1.550.000', () {
      final expense = _expense(amountMinor: 2000000);
      final recovery = _recovery(recoveryOfTxId: expense.id, amountMinor: 450000);
      final all = [expense, recovery];

      final balances = computeAllPoolBalances(all);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'chong'), -1550000);

      final summary = computeRecoverySummary(expense, all);
      expect(summary.totalRecovered, 450000);
      expect(summary.netCost, 1550000);
      expect(expense.amountMinor, 2000000, reason: 'KHÔNG mutate amount gốc');
    });
  });

  group('Case 2 — Partial refund (mục 16)', () {
    test('Expense 500.000, Recovery 387.000 → totalRecovered 387.000, netCost 113.000', () {
      final expense = _expense(id: 'expense-2', amountMinor: 500000);
      final recovery = _recovery(recoveryOfTxId: expense.id, amountMinor: 387000);
      final summary = computeRecoverySummary(expense, [expense, recovery]);
      expect(summary.totalRecovered, 387000);
      expect(summary.netCost, 113000);
    });
  });

  group('Case 3 — Multiple recoveries (mục 6/16)', () {
    test('1 original → 3 recovery: 2.800.000 + 300.000 + 100.000 = 3.200.000, netCost 6.800.000', () {
      final expense = _expense(id: 'ipad', amountMinor: 10000000);
      final r1 = _recovery(recoveryOfTxId: expense.id, amountMinor: 2800000);
      final r2 = _recovery(recoveryOfTxId: expense.id, amountMinor: 300000);
      final r3 = _recovery(recoveryOfTxId: expense.id, amountMinor: 100000);
      final all = [expense, r1, r2, r3];

      final summary = computeRecoverySummary(expense, all);
      expect(summary.recoveries, hasLength(3));
      expect(summary.totalRecovered, 3200000);
      expect(summary.netCost, 6800000);

      final balances = computeAllPoolBalances(all);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'chong'), -10000000 + 3200000);
    });
  });

  group('Case 4 — Reversal recovery (mục 7E/16)', () {
    test('Recovery bị reverse → không tính vào totalRecovered, netCost trở lại đúng giá trị gốc', () {
      final expense = _expense(id: 'expense-4', amountMinor: 1000000);
      final recovery = _recovery(recoveryOfTxId: expense.id, amountMinor: 400000, id: 'recovery-4');
      final reversal = buildReversal(
        recovery,
        newId: 'reversal-of-recovery-4',
        clientTxId: 'client-reversal-4',
        now: DateTime(2026, 1, 10),
      );
      final recoveryAfterReversed = recovery.copyWith(reversedByTxId: reversal.id);

      final all = [expense, recoveryAfterReversed, reversal];
      final summary = computeRecoverySummary(expense, all);
      expect(summary.totalRecovered, 0, reason: 'recovery đã bị hoàn tác không còn hiệu lực');
      expect(summary.netCost, 1000000, reason: 'netCost quay lại đúng giá trị gốc');
      expect(summary.recoveries, isEmpty);

      final balances = computeAllPoolBalances(all);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'chong'), -1000000, reason: 'hiệu ứng recovery bị triệt tiêu hoàn toàn');
    });
  });

  group('Case 5 — Correction recovery (mục 7F/16)', () {
    test('450k correction thành 400k → totalRecovered = 400k, KHÔNG phải 850k', () {
      final expense = _expense(id: 'expense-5', amountMinor: 2000000);
      final originalRecovery = _recovery(recoveryOfTxId: expense.id, amountMinor: 450000, id: 'recovery-5');
      final correction = buildCorrection(
        originalRecovery,
        newAmountMinor: 400000,
        reversalId: 'rev-5',
        replacementId: 'repl-5',
        clientTxId: 'client-correct-5',
        now: DateTime(2026, 1, 12),
      );
      final originalAfterReversed = originalRecovery.copyWith(reversedByTxId: correction.reversal.id);

      final all = [expense, originalAfterReversed, correction.reversal, correction.replacement];
      expect(correction.replacement.recoveryOfTxId, expense.id, reason: 'replacement giữ đúng quan hệ recovery');

      final summary = computeRecoverySummary(expense, all);
      expect(summary.totalRecovered, 400000);
      expect(summary.netCost, 1600000);
      expect(summary.recoveries, hasLength(1));
    });
  });

  group('Empty / zero recovery', () {
    test('original → 0 recovery: totalRecovered = 0, netCost = amount gốc', () {
      final expense = _expense(id: 'expense-solo', amountMinor: 300000);
      final summary = computeRecoverySummary(expense, [expense]);
      expect(summary.totalRecovered, 0);
      expect(summary.netCost, 300000);
      expect(summary.recoveries, isEmpty);
    });
  });
}
