import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/engine/financial_engine.dart';
import 'package:vi_nha_minh/domain/entities/family_member.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/entities/transfer_kind.dart';
import 'package:vi_nha_minh/domain/errors/domain_exceptions.dart';
import 'package:vi_nha_minh/domain/usecases/compute_pool_balance.dart';

int _seq = 0;

Transaction _tx({
  required TransactionType type,
  TransferKind? transferKind,
  String categoryId = 'test_cat',
  required PoolKind sourceKind,
  String? sourceRefId,
  required PoolKind destinationKind,
  String? destinationRefId,
  required int amountMinor,
  String? statusId,
  String? reversalOfTxId,
  String? correctsTxId,
  String? reversedByTxId,
}) {
  _seq++;
  return Transaction(
    id: 'tx-$_seq',
    type: type,
    transferKind: transferKind,
    categoryId: categoryId,
    sourceKind: sourceKind,
    sourceRefId: sourceRefId,
    destinationKind: destinationKind,
    destinationRefId: destinationRefId,
    amountMinor: amountMinor,
    statusId: statusId,
    transactionDate: DateTime(2026, 9, 1),
    createdAt: DateTime(2026, 9, 1),
    reversalOfTxId: reversalOfTxId,
    correctsTxId: correctsTxId,
    reversedByTxId: reversedByTxId,
    clientTxId: 'client-$_seq',
  );
}

void main() {
  group('applyEffect / computeAllPoolBalances — nguyên tắc cơ bản', () {
    test('INCOME chỉ cộng vào destination, không đụng pool khác', () {
      final tx = _tx(
        type: TransactionType.income,
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 10000000,
      );
      final balances = computeAllPoolBalances([tx]);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'vo'), 10000000);
    });

    test('EXPENSE chỉ trừ ở source, destination external không có pool', () {
      final tx = _tx(
        type: TransactionType.expense,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: 300000,
      );
      final balances = computeAllPoolBalances([tx]);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'vo'), -300000);
    });

    test('TRANSFER (chuyển thành viên) không đổi Tổng tài sản — 2 pool đổi ngược dấu nhau', () {
      final tx = _tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.memberToMember,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'chong',
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 3000000,
      );
      final balances = computeAllPoolBalances([tx]);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'chong'), -3000000);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'vo'), 3000000);
      final totalAssetChange = balances.values.fold<int>(0, (s, v) => s + v);
      expect(totalAssetChange, 0);
    });
  });

  group('Fund Model — F-03, không trừ kép (Test 6/7/8, docs/financial-core-v2.md mục 8)', () {
    test('Test 6 — Nạp quỹ: member 5tr→3tr (giả định), fund 0→2tr, tổng không đổi', () {
      final topUp = _tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.fundTopup,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.fund,
        destinationRefId: 'an_uong',
        amountMinor: 2000000,
      );
      final balances = computeAllPoolBalances([topUp]);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'vo'), -2000000);
      expect(poolBalance(balances, PoolKind.fund, 'an_uong'), 2000000);
    });

    test('Test 7 — Chi từ quỹ 500k: chỉ quỹ giảm, MEMBER_AVAILABLE người mua giữ nguyên', () {
      final topUp = _tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.fundTopup,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.fund,
        destinationRefId: 'an_uong',
        amountMinor: 2000000,
      );
      final spendFromFund = _tx(
        type: TransactionType.expense,
        sourceKind: PoolKind.fund,
        sourceRefId: 'an_uong',
        destinationKind: PoolKind.external,
        amountMinor: 500000,
      );
      final balances = computeAllPoolBalances([topUp, spendFromFund]);
      // Member chỉ đổi đúng 1 lần (lúc nạp), KHÔNG bị trừ thêm khi chi từ quỹ.
      expect(poolBalance(balances, PoolKind.memberAvailable, 'vo'), -2000000);
      expect(poolBalance(balances, PoolKind.fund, 'an_uong'), 1500000);
    });

    test('Test 8 — Chi KHÔNG dùng quỹ 500k: chỉ member đổi, fund giữ nguyên', () {
      final topUp = _tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.fundTopup,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.fund,
        destinationRefId: 'an_uong',
        amountMinor: 2000000,
      );
      final spendDirect = _tx(
        type: TransactionType.expense,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: 500000,
      );
      final balances = computeAllPoolBalances([topUp, spendDirect]);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'vo'), -2500000);
      expect(poolBalance(balances, PoolKind.fund, 'an_uong'), 2000000);
    });
  });

  group('Invariant 7 — Quỹ/Tiết kiệm/MEMBER_AVAILABLE không bao giờ âm', () {
    test('wouldGoNegative true khi chi vượt số dư quỹ hiện có', () {
      final topUp = _tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.fundTopup,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.fund,
        destinationRefId: 'an_uong',
        amountMinor: 100000,
      );
      final balances = computeAllPoolBalances([topUp]);
      final result = wouldGoNegative(
        currentBalances: balances,
        kind: PoolKind.fund,
        refId: 'an_uong',
        delta: -200000,
      );
      expect(result, isTrue);
    });

    test('wouldGoNegative false khi số dư đủ', () {
      final topUp = _tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.fundTopup,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.fund,
        destinationRefId: 'an_uong',
        amountMinor: 100000,
      );
      final balances = computeAllPoolBalances([topUp]);
      final result = wouldGoNegative(
        currentBalances: balances,
        kind: PoolKind.fund,
        refId: 'an_uong',
        delta: -50000,
      );
      expect(result, isFalse);
    });
  });

  group('Reversal ledger — mục 21', () {
    test('buildReversal đảo ngược đúng source/destination, cùng amountMinor', () {
      final original = _tx(
        type: TransactionType.expense,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: 500000,
      );
      final reversal = buildReversal(
        original,
        newId: 'rev-1',
        clientTxId: 'client-rev-1',
        now: DateTime(2026, 9, 5),
      );
      expect(reversal.sourceKind, PoolKind.external);
      expect(reversal.destinationKind, PoolKind.memberAvailable);
      expect(reversal.destinationRefId, 'vo');
      expect(reversal.amountMinor, 500000);
      expect(reversal.reversalOfTxId, original.id);

      // Cộng dồn 2 bản ghi (gốc + reversal) phải triệt tiêu về đúng 0.
      final balances = computeAllPoolBalances([original, reversal]);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'vo'), 0);
    });

    test('isVisible ẩn đúng bản gốc đã hoàn tác và bản reversal nội bộ', () {
      final original = _tx(
        type: TransactionType.expense,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: 500000,
      );
      final reversal = buildReversal(
        original,
        newId: 'rev-1',
        clientTxId: 'client-rev-1',
        now: DateTime(2026, 9, 5),
      );
      final reversedOriginal = original.copyWith(reversedByTxId: reversal.id);

      expect(isVisible(reversedOriginal), isFalse);
      expect(isVisible(reversal), isFalse);
    });

    test(
      'Test 10 — sửa Expense 500k thành 800k: chỉ phần chênh lệch (-300k) bị trừ thêm',
      () {
        final original = _tx(
          type: TransactionType.expense,
          sourceKind: PoolKind.memberAvailable,
          sourceRefId: 'vo',
          destinationKind: PoolKind.external,
          amountMinor: 500000,
        );
        final balancesBefore = computeAllPoolBalances([original]);
        expect(poolBalance(balancesBefore, PoolKind.memberAvailable, 'vo'), -500000);

        final result = buildCorrection(
          original,
          newAmountMinor: 800000,
          reversalId: 'rev-1',
          replacementId: 'repl-1',
          clientTxId: 'client-correct-1',
          now: DateTime(2026, 9, 6),
        );
        final reversedOriginal = original.copyWith(reversedByTxId: result.reversal.id);

        final balancesAfter = computeAllPoolBalances([
          reversedOriginal,
          result.reversal,
          result.replacement,
        ]);
        expect(poolBalance(balancesAfter, PoolKind.memberAvailable, 'vo'), -800000);

        // Danh sách hiển thị chỉ còn đúng bản thay thế.
        expect(isVisible(reversedOriginal), isFalse);
        expect(isVisible(result.reversal), isFalse);
        expect(isVisible(result.replacement), isTrue);
        expect(result.replacement.statusId, original.statusId);
      },
    );
  });

  group('Savings Model — mục 9 (loại tài sản tự do, không còn cố định cash/bank)', () {
    test('Nạp/Chuyển đổi loại tài sản tiết kiệm không đổi Tổng tài sản', () {
      final topup = _tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.savingsTopup,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.memberSavingsAsset,
        destinationRefId: savingsAssetRefId('savings_cash', FamilyMember.vo),
        amountMinor: 2000000,
      );
      final convert = _tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.savingsConvert,
        sourceKind: PoolKind.memberSavingsAsset,
        sourceRefId: savingsAssetRefId('savings_cash', FamilyMember.vo),
        destinationKind: PoolKind.memberSavingsAsset,
        destinationRefId: savingsAssetRefId('savings_bank', FamilyMember.vo),
        amountMinor: 1500000,
      );
      final balances = computeAllPoolBalances([topup, convert]);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'vo'), -2000000);
      expect(
        poolBalance(
          balances,
          PoolKind.memberSavingsAsset,
          savingsAssetRefId('savings_cash', FamilyMember.vo),
        ),
        500000,
      );
      expect(
        poolBalance(
          balances,
          PoolKind.memberSavingsAsset,
          savingsAssetRefId('savings_bank', FamilyMember.vo),
        ),
        1500000,
      );
      final totalChange = balances.values.fold<int>(0, (s, v) => s + v);
      expect(totalChange, 0);
    });

    test('computeMemberSavingsTotal cộng dồn mọi loại tài sản của 1 thành viên', () {
      final stocksTopup = _tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.savingsTopup,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.memberSavingsAsset,
        destinationRefId: savingsAssetRefId('chung_khoan', FamilyMember.vo),
        amountMinor: 3000000,
      );
      final bankTopup = _tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.savingsTopup,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.memberSavingsAsset,
        destinationRefId: savingsAssetRefId('savings_bank', FamilyMember.vo),
        amountMinor: 2000000,
      );
      final total = computeMemberSavingsTotal(FamilyMember.vo, [stocksTopup, bankTopup]);
      expect(total, 5000000);
    });
  });

  group('validateNewTransaction — Invariant 12 (amount) & 15 (source≠destination)', () {
    test('amount = 0 bị reject bằng InvalidAmountException', () {
      final tx = _tx(
        type: TransactionType.expense,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: 0,
      );
      expect(() => validateNewTransaction(tx), throwsA(isA<InvalidAmountException>()));
    });

    test('amount âm bị reject bằng InvalidAmountException', () {
      final tx = _tx(
        type: TransactionType.expense,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: -50000,
      );
      expect(() => validateNewTransaction(tx), throwsA(isA<InvalidAmountException>()));
    });

    test('amount dương hợp lệ không ném lỗi gì', () {
      final tx = _tx(
        type: TransactionType.expense,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: 100000,
      );
      expect(() => validateNewTransaction(tx), returnsNormally);
    });

    test('MEMBER_TO_MEMBER người nhận = người gửi bị reject (source = destination)', () {
      final tx = _tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.memberToMember,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 100000,
      );
      expect(() => validateNewTransaction(tx), throwsA(isA<SameSourceDestinationException>()));
    });

    test('SAVINGS_CONVERT cùng loại tài sản (nguồn = đích) bị reject', () {
      final tx = _tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.savingsConvert,
        sourceKind: PoolKind.memberSavingsAsset,
        sourceRefId: savingsAssetRefId('savings_cash', FamilyMember.vo),
        destinationKind: PoolKind.memberSavingsAsset,
        destinationRefId: savingsAssetRefId('savings_cash', FamilyMember.vo),
        amountMinor: 500000,
      );
      expect(() => validateNewTransaction(tx), throwsA(isA<SameSourceDestinationException>()));
    });

    test('SAVINGS_CONVERT khác loại tài sản (hợp lệ) không ném lỗi', () {
      final tx = _tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.savingsConvert,
        sourceKind: PoolKind.memberSavingsAsset,
        sourceRefId: savingsAssetRefId('savings_cash', FamilyMember.vo),
        destinationKind: PoolKind.memberSavingsAsset,
        destinationRefId: savingsAssetRefId('savings_bank', FamilyMember.vo),
        amountMinor: 500000,
      );
      expect(() => validateNewTransaction(tx), returnsNormally);
    });
  });

  group('Reversal — chặn hoàn tác 2 lần (Invariant 13)', () {
    test('reverse lần đầu thành công', () {
      final original = _tx(
        type: TransactionType.expense,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: 500000,
      );
      final reversal = buildReversal(
        original,
        newId: 'rev-1',
        clientTxId: 'client-rev-1',
        now: DateTime(2026, 9, 5),
      );
      expect(reversal.reversalOfTxId, original.id);
    });

    test('reverse lần thứ 2 trên bản đã REVERSED bị AlreadyReversedException, balance không đổi thêm', () {
      final original = _tx(
        type: TransactionType.expense,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: 500000,
      );
      final firstReversal = buildReversal(
        original,
        newId: 'rev-1',
        clientTxId: 'client-rev-1',
        now: DateTime(2026, 9, 5),
      );
      // Bản gốc giờ đã REVERSED (giống repository set reversedByTxId sau khi ghi bản reversal).
      final reversedOriginal = original.copyWith(reversedByTxId: firstReversal.id);

      expect(
        () => buildReversal(
          reversedOriginal,
          newId: 'rev-2',
          clientTxId: 'client-rev-2',
          now: DateTime(2026, 9, 6),
        ),
        throwsA(isA<AlreadyReversedException>()),
      );

      // Balance chỉ tính đúng 1 lần hoàn tác (gốc + reversal đầu tiên), không có rev-2.
      final balances = computeAllPoolBalances([reversedOriginal, firstReversal]);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'vo'), 0);
    });

    test('buildCorrection trên bản đã REVERSED cũng bị AlreadyReversedException (Invariant 14)', () {
      final original = _tx(
        type: TransactionType.expense,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: 500000,
      );
      final firstReversal = buildReversal(
        original,
        newId: 'rev-1',
        clientTxId: 'client-rev-1',
        now: DateTime(2026, 9, 5),
      );
      final reversedOriginal = original.copyWith(reversedByTxId: firstReversal.id);

      expect(
        () => buildCorrection(
          reversedOriginal,
          newAmountMinor: 800000,
          reversalId: 'rev-2',
          replacementId: 'repl-2',
          clientTxId: 'client-correct-2',
          now: DateTime(2026, 9, 6),
        ),
        throwsA(isA<AlreadyReversedException>()),
      );
    });
  });

  group('Sửa nhiều lần liên tiếp (Invariant 14) — 100 → 150 → 200 → 250', () {
    test('mỗi lần sửa phải thao tác trên bản mới nhất, balance cuối khớp đúng 250k', () {
      final original = _tx(
        type: TransactionType.expense,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: 100000,
      );

      // Sửa lần 1: 100k -> 150k, thao tác trên `original`.
      final step1 = buildCorrection(
        original,
        newAmountMinor: 150000,
        reversalId: 'rev-1',
        replacementId: 'repl-1',
        clientTxId: 'client-1',
        now: DateTime(2026, 9, 2),
      );
      final originalAfterStep1 = original.copyWith(reversedByTxId: step1.reversal.id);

      // Sửa lần 2: 150k -> 200k, PHẢI thao tác trên step1.replacement (bản mới nhất).
      final step2 = buildCorrection(
        step1.replacement,
        newAmountMinor: 200000,
        reversalId: 'rev-2',
        replacementId: 'repl-2',
        clientTxId: 'client-2',
        now: DateTime(2026, 9, 3),
      );
      final replacement1AfterStep2 = step1.replacement.copyWith(reversedByTxId: step2.reversal.id);

      // Sửa lần 3: 200k -> 250k, thao tác trên step2.replacement.
      final step3 = buildCorrection(
        step2.replacement,
        newAmountMinor: 250000,
        reversalId: 'rev-3',
        replacementId: 'repl-3',
        clientTxId: 'client-3',
        now: DateTime(2026, 9, 4),
      );
      final replacement2AfterStep3 = step2.replacement.copyWith(reversedByTxId: step3.reversal.id);

      final allRecords = [
        originalAfterStep1,
        step1.reversal,
        replacement1AfterStep2,
        step2.reversal,
        replacement2AfterStep3,
        step3.reversal,
        step3.replacement,
      ];

      // 7 bản ghi tổng cộng (1 gốc + 3 x (reversal+replacement) trừ bản thay thế cuối chưa bị reverse).
      expect(allRecords.length, 7);

      final balances = computeAllPoolBalances(allRecords);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'vo'), -250000);

      // Chỉ đúng 1 bản hiển thị: bản thay thế cuối cùng (250k).
      final visible = allRecords.where(isVisible).toList();
      expect(visible.length, 1);
      expect(visible.single.amountMinor, 250000);
      expect(visible.single.correctsTxId, step2.replacement.id);
    });

    test('sửa nhầm trên bản đã lỗi thời (không phải mới nhất) bị chặn (Invariant 14)', () {
      final original = _tx(
        type: TransactionType.expense,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: 100000,
      );
      final step1 = buildCorrection(
        original,
        newAmountMinor: 150000,
        reversalId: 'rev-1',
        replacementId: 'repl-1',
        clientTxId: 'client-1',
        now: DateTime(2026, 9, 2),
      );
      final originalAfterStep1 = original.copyWith(reversedByTxId: step1.reversal.id);

      // Cố sửa tiếp trên `originalAfterStep1` (đã REVERSED) thay vì `step1.replacement` — phải bị chặn.
      expect(
        () => buildCorrection(
          originalAfterStep1,
          newAmountMinor: 999000,
          reversalId: 'rev-x',
          replacementId: 'repl-x',
          clientTxId: 'client-x',
          now: DateTime(2026, 9, 3),
        ),
        throwsA(isA<AlreadyReversedException>()),
      );
    });
  });

  group('Status không ảnh hưởng balance (Invariant 9)', () {
    test('2 giao dịch giống hệt nhau, chỉ khác statusId, cho cùng 1 hiệu ứng balance', () {
      final withStatusA = _tx(
        type: TransactionType.expense,
        categoryId: 'cho_di',
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: 500000,
        statusId: 'cho_di_chua_chuan_bi',
      );
      final withStatusB = _tx(
        type: TransactionType.expense,
        categoryId: 'cho_di',
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: 500000,
        statusId: 'cho_di_da_gui',
      );
      final balancesA = computeAllPoolBalances([withStatusA]);
      final balancesB = computeAllPoolBalances([withStatusB]);
      expect(
        poolBalance(balancesA, PoolKind.memberAvailable, 'vo'),
        poolBalance(balancesB, PoolKind.memberAvailable, 'vo'),
      );
    });

    test('đổi statusId qua copyWith không kích hoạt applyEffect nào khác', () {
      final tx = _tx(
        type: TransactionType.expense,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: 500000,
        statusId: 'step_0',
      );
      final changedStatus = tx.copyWith(statusId: 'step_1');
      final balancesBefore = computeAllPoolBalances([tx]);
      final balancesAfter = computeAllPoolBalances([changedStatus]);
      expect(
        poolBalance(balancesAfter, PoolKind.memberAvailable, 'vo'),
        poolBalance(balancesBefore, PoolKind.memberAvailable, 'vo'),
      );
    });
  });

  group('isSameLogicalTransaction — currency là 1 phần logical identity (Phase 4.1)', () {
    Transaction incomeTx({required String currency}) {
      return Transaction(
        id: 'tx-currency-test',
        type: TransactionType.income,
        categoryId: 'thu_nhap',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 100000,
        currency: currency,
        transactionDate: DateTime(2026, 9, 1),
        createdAt: DateTime(2026, 9, 1),
        clientTxId: 'client-currency-test',
      );
    }

    test('C — cùng currency → coi là cùng logical transaction', () {
      expect(isSameLogicalTransaction(incomeTx(currency: 'VND'), incomeTx(currency: 'VND')), isTrue);
    });

    test('C — khác currency (mọi field khác giống hệt) → KHÔNG phải cùng logical transaction', () {
      expect(isSameLogicalTransaction(incomeTx(currency: 'VND'), incomeTx(currency: 'USD')), isFalse);
    });
  });
}
