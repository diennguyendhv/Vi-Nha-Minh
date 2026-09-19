import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/repositories/local_transaction_repository.dart';
import 'package:vi_nha_minh/domain/engine/financial_engine.dart';
import 'package:vi_nha_minh/domain/entities/obligation_direction.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart' as domain;
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/errors/domain_exceptions.dart';

/// Phase 8.7 — test Repository THẬT (DB in-memory thật, không mock) cho
/// `settleObligation`/`reverseObligationSettlement`/
/// `correctObligationSettlement`: atomicity (rollback thật, không chỉ
/// validate-trước-khi-ghi), idempotency/retry matrix, half-state defensive,
/// reversal, correction — đúng yêu cầu audit "atomicity + idempotency"
/// Phase 8.7 (KHÔNG chỉ test validation failure trước insert).
void main() {
  late AppDatabase db;
  late LocalTransactionRepository repo;
  var seq = 0;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LocalTransactionRepository(db);
    seq = 0;
    // Category `cho_vay`/`lai_cho_vay`/`vay_no`/`tra_no` đã có sẵn trong
    // `DefaultCategories.all` (Phase 8.7), tự seed bởi `seedDefaults` khi
    // `AppDatabase.forTesting` khởi tạo — KHÔNG tự insert lại (trùng id).
  });

  tearDown(() async => db.close());

  String nextId(String p) => '$p-${seq++}';

  /// Nạp sẵn Available cho `vo` — Receivable cần rút TỪ Available (source =
  /// memberAvailable) nên phải có sẵn tiền trước, khác Payable (nguồn =
  /// external, không cần seed).
  Future<void> seedAvailable(int amount) async {
    await repo.addTransaction(
      domain.Transaction(
        id: nextId('seed'),
        type: TransactionType.income,
        categoryId: 'vay_no',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: amount,
        transactionDate: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        clientTxId: nextId('client'),
      ),
    );
  }

  Future<domain.Transaction> createReceivable(String obligationId, int amount) async {
    await seedAvailable(amount);
    return repo.addTransaction(
      domain.Transaction(
        id: nextId('creation'),
        type: TransactionType.transfer,
        categoryId: 'cho_vay',
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.receivable,
        destinationRefId: obligationId,
        amountMinor: amount,
        obligationId: obligationId,
        transactionDate: DateTime(2026, 5, 8),
        createdAt: DateTime(2026, 5, 8),
        clientTxId: nextId('client'),
      ),
    );
  }

  Future<domain.Transaction> createPayable(String obligationId, int amount) {
    return repo.addTransaction(
      domain.Transaction(
        id: nextId('creation'),
        type: TransactionType.income,
        categoryId: 'vay_no',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: amount,
        obligationId: obligationId,
        transactionDate: DateTime(2026, 5, 8),
        createdAt: DateTime(2026, 5, 8),
        clientTxId: nextId('client'),
      ),
    );
  }

  group('settleObligation — happy path', () {
    test('Receivable không lãi → 1 dòng, Available/Receivable đúng', () async {
      await createReceivable('r1', 1200000);
      final result = await repo.settleObligation(
        obligationId: 'r1',
        direction: ObligationDirection.receivable,
        memberRefId: 'vo',
        amountMinor: 1200000,
        transactionDate: DateTime(2027, 7, 1),
        categoryId: 'cho_vay',
        interestCategoryId: 'lai_cho_vay',
        principalId: 'p1',
        principalClientTxId: 'c1',
        interestId: 'i1',
        interestClientTxId: 'ci1',
      );
      expect(result.interest, isNull);
      final all = await repo.watchTransactions().first;
      final balances = computeAllPoolBalances(all);
      // seed 1.2m (để có tiền cho vay) - 1.2m (cho vay) + 1.2m (thu hồi) = 1.2m.
      expect(poolBalance(balances, PoolKind.memberAvailable, 'vo'), 1200000);
      expect(poolBalance(balances, PoolKind.receivable, 'r1'), 0);
    });

    test('Receivable có lãi → 2 dòng atomic, đúng STOP condition (Available +1.4m, Income +200k)', () async {
      await createReceivable('r2', 1200000);
      final result = await repo.settleObligation(
        obligationId: 'r2',
        direction: ObligationDirection.receivable,
        memberRefId: 'vo',
        amountMinor: 1400000,
        transactionDate: DateTime(2027, 7, 1),
        categoryId: 'cho_vay',
        interestCategoryId: 'lai_cho_vay',
        principalId: 'p2',
        principalClientTxId: 'c2',
        interestId: 'i2',
        interestClientTxId: 'ci2',
      );
      expect(result.principal.amountMinor, 1200000);
      expect(result.interest!.amountMinor, 200000);
      final rows = await db.select(db.transactionRows).get();
      expect(rows, hasLength(4), reason: '1 seed + 1 creation + 2 leg tất toán');
    });

    test('Payable có lãi → luôn 1 dòng duy nhất', () async {
      await createPayable('p1', 700000);
      await seedAvailable(100000); // để đủ Available trả 800k (700k gốc + 100k lãi)
      final result = await repo.settleObligation(
        obligationId: 'p1',
        direction: ObligationDirection.payable,
        memberRefId: 'vo',
        amountMinor: 800000,
        transactionDate: DateTime(2027, 5, 1),
        categoryId: 'tra_no',
        interestCategoryId: 'tra_no',
        principalId: 'pp1',
        principalClientTxId: 'cc1',
        interestId: 'ii1',
        interestClientTxId: 'cci1',
      );
      expect(result.interest, isNull);
      final rows = await db.select(db.transactionRows).get();
      expect(rows, hasLength(3), reason: '1 creation + 1 seed + 1 leg tất toán duy nhất');
    });
  });

  group('REQUIRED ATOMICITY TEST — rollback thật giữa 2 insert', () {
    test('interest leg fail SAU KHI principal đã insert → rollback TOÀN BỘ, không leak dòng nào', () async {
      await createReceivable('r3', 1200000);

      // Pre-insert 1 row CHIẾM SẴN đúng `id` sẽ dùng cho leg interest (PRIMARY
      // KEY collision — không phải clientTxId, để KHÔNG bị chặn sớm ở fast-path
      // idempotency mà phải đi xuyên qua insert principal THẬT rồi mới fail ở
      // insert interest, đúng yêu cầu "không chỉ test validation trước insert").
      await db.into(db.transactionRows).insert(
        TransactionRowsCompanion.insert(
          id: 'i3', // trùng interestId sẽ dùng bên dưới
          type: 'income',
          categoryId: 'lai_cho_vay',
          sourceKind: 'external',
          destinationKind: 'memberAvailable',
          destinationRefId: const Value('vo'),
          amountMinor: 999,
          transactionDate: DateTime(2020, 1, 1),
          createdAt: DateTime(2020, 1, 1),
          clientTxId: 'unrelated-clienttxid',
        ),
      );

      final rowsBefore = await db.select(db.transactionRows).get();
      expect(rowsBefore, hasLength(3), reason: '1 seed + 1 creation + 1 dòng "chiếm chỗ"');

      await expectLater(
        repo.settleObligation(
          obligationId: 'r3',
          direction: ObligationDirection.receivable,
          memberRefId: 'vo',
          amountMinor: 1400000, // > outstanding → sinh leg interest với id='i3'
          transactionDate: DateTime(2027, 7, 1),
          categoryId: 'cho_vay',
          interestCategoryId: 'lai_cho_vay',
          principalId: 'p3',
          principalClientTxId: 'c3',
          interestId: 'i3',
          interestClientTxId: 'ci3',
        ),
        throwsA(anything),
      );

      final rowsAfter = await db.select(db.transactionRows).get();
      expect(
        rowsAfter,
        hasLength(3),
        reason: 'KHÔNG có principal leg mồ côi bị leak — rollback xoá sạch cả '
            'principal ĐÃ insert thành công trước đó',
      );
      expect(
        rowsAfter.any((r) => r.id == 'p3'),
        isFalse,
        reason: 'principal leg (đã insert thành công trước khi interest fail) '
            'phải bị rollback theo',
      );

      final all = await repo.watchTransactions().first;
      final balances = computeAllPoolBalances(all);
      expect(
        poolBalance(balances, PoolKind.memberAvailable, 'vo'),
        999,
        reason: 'Available KHÔNG đổi so với trước lần settle fail (seed 1.2m - cho vay 1.2m '
            '+ 999 của dòng "chiếm chỗ" — dòng đó tồn tại ĐỘC LẬP, không liên quan tới rollback)',
      );
      expect(poolBalance(balances, PoolKind.receivable, 'r3'), 1200000, reason: 'Receivable outstanding KHÔNG đổi');
    });
  });

  group('Idempotency / retry matrix', () {
    test('retry đúng cùng clientTxId, cả 2 leg đã tồn tại + payload khớp → idempotent success, KHÔNG tạo thêm dòng', () async {
      await createReceivable('r4', 1200000);
      final first = await repo.settleObligation(
        obligationId: 'r4',
        direction: ObligationDirection.receivable,
        memberRefId: 'vo',
        amountMinor: 1400000,
        transactionDate: DateTime(2027, 7, 1),
        categoryId: 'cho_vay',
        interestCategoryId: 'lai_cho_vay',
        principalId: 'p4',
        principalClientTxId: 'c4',
        interestId: 'i4',
        interestClientTxId: 'ci4',
      );
      final second = await repo.settleObligation(
        obligationId: 'r4',
        direction: ObligationDirection.receivable,
        memberRefId: 'vo',
        amountMinor: 1400000,
        transactionDate: DateTime(2027, 7, 1),
        categoryId: 'cho_vay',
        interestCategoryId: 'lai_cho_vay',
        principalId: 'p4',
        principalClientTxId: 'c4',
        interestId: 'i4',
        interestClientTxId: 'ci4',
      );
      expect(second.principal.id, first.principal.id);
      expect(second.interest!.id, first.interest!.id);
      final rows = await db.select(db.transactionRows).get();
      expect(rows, hasLength(4), reason: '1 seed + 1 creation + 2 leg — KHÔNG nhân đôi');
    });

    test('half-state phòng thủ: principal tồn tại, interest thiếu → SettlementIntegrityException, KHÔNG tự vá', () async {
      await createReceivable('r5', 1200000);
      // Insert THỦ CÔNG chỉ leg principal (mô phỏng dữ liệu hỏng/half-state
      // từ 1 phiên bản app cũ) — KHÔNG qua settleObligation.
      await repo.addTransaction(
        domain.Transaction(
          id: 'p5',
          type: TransactionType.transfer,
          categoryId: 'cho_vay',
          sourceKind: PoolKind.receivable,
          sourceRefId: 'r5',
          destinationKind: PoolKind.memberAvailable,
          destinationRefId: 'vo',
          amountMinor: 1200000,
          obligationId: 'r5',
          settlementGroupId: 'p5',
          transactionDate: DateTime(2027, 7, 1),
          createdAt: DateTime(2027, 7, 1),
          clientTxId: 'c5',
        ),
      );

      await expectLater(
        repo.settleObligation(
          obligationId: 'r5',
          direction: ObligationDirection.receivable,
          memberRefId: 'vo',
          amountMinor: 1400000,
          transactionDate: DateTime(2027, 7, 1),
          categoryId: 'cho_vay',
          interestCategoryId: 'lai_cho_vay',
          principalId: 'p5',
          principalClientTxId: 'c5',
          interestId: 'i5',
          interestClientTxId: 'ci5',
        ),
        throwsA(isA<SettlementIntegrityException>()),
      );

      final rows = await db.select(db.transactionRows).get();
      expect(rows, hasLength(3), reason: '1 seed + 1 creation + 1 principal thủ công — KHÔNG có dòng thứ 4 nào được tạo');
    });

    test('half-state phòng thủ: interest tồn tại, principal thiếu → SettlementIntegrityException', () async {
      await createReceivable('r6', 1200000);
      await repo.addTransaction(
        domain.Transaction(
          id: 'i6',
          type: TransactionType.income,
          categoryId: 'lai_cho_vay',
          sourceKind: PoolKind.external,
          destinationKind: PoolKind.memberAvailable,
          destinationRefId: 'vo',
          amountMinor: 200000,
          obligationId: 'r6',
          settlementGroupId: 'p6',
          transactionDate: DateTime(2027, 7, 1),
          createdAt: DateTime(2027, 7, 1),
          clientTxId: 'ci6',
        ),
      );

      await expectLater(
        repo.settleObligation(
          obligationId: 'r6',
          direction: ObligationDirection.receivable,
          memberRefId: 'vo',
          amountMinor: 1400000,
          transactionDate: DateTime(2027, 7, 1),
          categoryId: 'cho_vay',
          interestCategoryId: 'lai_cho_vay',
          principalId: 'p6',
          principalClientTxId: 'c6',
          interestId: 'i6',
          interestClientTxId: 'ci6',
        ),
        throwsA(isA<SettlementIntegrityException>()),
      );

      final rows = await db.select(db.transactionRows).get();
      expect(rows, hasLength(3), reason: '1 seed + 1 creation + 1 interest thủ công');
    });
  });

  group('Reversal', () {
    test('reverse single-leg settlement (Payable, không lãi)', () async {
      await createPayable('p7', 700000);
      await repo.settleObligation(
        obligationId: 'p7',
        direction: ObligationDirection.payable,
        memberRefId: 'vo',
        amountMinor: 700000,
        transactionDate: DateTime(2027, 5, 1),
        categoryId: 'tra_no',
        interestCategoryId: 'tra_no',
        principalId: 'pp7',
        principalClientTxId: 'cc7',
        interestId: 'ii7',
        interestClientTxId: 'cci7',
      );
      await repo.reverseObligationSettlement('pp7');

      final all = await repo.watchTransactions().first;
      final balances = computeAllPoolBalances(all);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'vo'), 700000, reason: 'quay lại đúng trạng thái sau khi vay, trước khi trả');
    });

    test('reverse two-leg settlement (Receivable có lãi) — atomic cả 2 leg, Available/Receivable/Income khôi phục đúng', () async {
      await createReceivable('r8', 1200000);
      await repo.settleObligation(
        obligationId: 'r8',
        direction: ObligationDirection.receivable,
        memberRefId: 'vo',
        amountMinor: 1400000,
        transactionDate: DateTime(2027, 7, 1),
        categoryId: 'cho_vay',
        interestCategoryId: 'lai_cho_vay',
        principalId: 'p8',
        principalClientTxId: 'c8',
        interestId: 'i8',
        interestClientTxId: 'ci8',
      );
      await repo.reverseObligationSettlement('p8'); // truyền id leg principal

      final all = await repo.watchTransactions().first;
      final balances = computeAllPoolBalances(all);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'vo'), 0, reason: 'khôi phục đúng trạng thái sau khi cho vay (seed 1.2m - cho vay 1.2m), trước khi thu');
      expect(poolBalance(balances, PoolKind.receivable, 'r8'), 1200000);

      final visiblePrincipal = all.firstWhere((t) => t.id == 'p8');
      final visibleInterest = all.firstWhere((t) => t.id == 'i8');
      expect(visiblePrincipal.reversedByTxId, isNotNull);
      expect(visibleInterest.reversedByTxId, isNotNull, reason: 'leg lãi CŨNG phải bị hoàn tác atomic cùng leg gốc');
    });

    test('reverse bằng id của leg INTEREST vẫn resolve đúng group và hoàn tác cả 2', () async {
      await createReceivable('r9', 1200000);
      await repo.settleObligation(
        obligationId: 'r9',
        direction: ObligationDirection.receivable,
        memberRefId: 'vo',
        amountMinor: 1400000,
        transactionDate: DateTime(2027, 7, 1),
        categoryId: 'cho_vay',
        interestCategoryId: 'lai_cho_vay',
        principalId: 'p9',
        principalClientTxId: 'c9',
        interestId: 'i9',
        interestClientTxId: 'ci9',
      );
      await repo.reverseObligationSettlement('i9'); // truyền id leg INTEREST

      final all = await repo.watchTransactions().first;
      expect(all.firstWhere((t) => t.id == 'p9').reversedByTxId, isNotNull);
      expect(all.firstWhere((t) => t.id == 'i9').reversedByTxId, isNotNull);
    });

    test('reverse 2 lần → AlreadyReversedException, không tạo reversal thứ 2', () async {
      await createPayable('p10', 700000);
      await repo.settleObligation(
        obligationId: 'p10',
        direction: ObligationDirection.payable,
        memberRefId: 'vo',
        amountMinor: 700000,
        transactionDate: DateTime(2027, 5, 1),
        categoryId: 'tra_no',
        interestCategoryId: 'tra_no',
        principalId: 'pp10',
        principalClientTxId: 'cc10',
        interestId: 'ii10',
        interestClientTxId: 'cci10',
      );
      await repo.reverseObligationSettlement('pp10');
      await expectLater(
        repo.reverseObligationSettlement('pp10'),
        throwsA(isA<AlreadyReversedException>()),
      );
      final rows = await db.select(db.transactionRows).get();
      expect(rows, hasLength(3), reason: '1 creation + 1 settlement + 1 reversal — không có reversal thứ 2');
    });
  });

  group('Correction', () {
    test('correction 1.4m → 1.3m: cuối cùng CHỈ còn principal 1.2m/interest 100k visible, không cộng dồn lãi cũ', () async {
      await createReceivable('r11', 1200000);
      await repo.settleObligation(
        obligationId: 'r11',
        direction: ObligationDirection.receivable,
        memberRefId: 'vo',
        amountMinor: 1400000,
        transactionDate: DateTime(2027, 7, 1),
        categoryId: 'cho_vay',
        interestCategoryId: 'lai_cho_vay',
        principalId: 'p11',
        principalClientTxId: 'c11',
        interestId: 'i11',
        interestClientTxId: 'ci11',
      );

      final corrected = await repo.correctObligationSettlement(
        'p11',
        newAmountMinor: 1300000,
        categoryId: 'cho_vay',
        interestCategoryId: 'lai_cho_vay',
        newPrincipalId: 'p11b',
        newPrincipalClientTxId: 'c11b',
        newInterestId: 'i11b',
        newInterestClientTxId: 'ci11b',
      );
      expect(corrected.principal.amountMinor, 1200000);
      expect(corrected.interest!.amountMinor, 100000);

      final all = await repo.watchTransactions().first;
      final visible = all.where(isVisible).toList();
      final visibleInterestLegs = visible.where(
        (t) => t.obligationId == 'r11' && t.settlementGroupId != null && t.id != t.settlementGroupId,
      );
      expect(visibleInterestLegs, hasLength(1));
      expect(visibleInterestLegs.first.amountMinor, 100000, reason: 'KHÔNG phải 200k cũ + 100k mới');

      final balances = computeAllPoolBalances(all);
      expect(poolBalance(balances, PoolKind.receivable, 'r11'), 0);
      expect(
        poolBalance(balances, PoolKind.memberAvailable, 'vo'),
        1300000,
        reason: 'seed 1.2m - cho vay 1.2m + 1.3m (thu, đã sửa) = 1.3m',
      );
    });

    test('reject correction settlement KHÔNG PHẢI mới nhất → NotLatestSettlementException', () async {
      await createReceivable('r12', 2000000);
      await repo.settleObligation(
        obligationId: 'r12',
        direction: ObligationDirection.receivable,
        memberRefId: 'vo',
        amountMinor: 500000,
        transactionDate: DateTime(2027, 1, 1),
        categoryId: 'cho_vay',
        interestCategoryId: 'lai_cho_vay',
        principalId: 'first-leg',
        principalClientTxId: 'c-first',
        interestId: 'i-first',
        interestClientTxId: 'ci-first',
      );
      await repo.settleObligation(
        obligationId: 'r12',
        direction: ObligationDirection.receivable,
        memberRefId: 'vo',
        amountMinor: 500000,
        transactionDate: DateTime(2027, 2, 1),
        categoryId: 'cho_vay',
        interestCategoryId: 'lai_cho_vay',
        principalId: 'second-leg',
        principalClientTxId: 'c-second',
        interestId: 'i-second',
        interestClientTxId: 'ci-second',
      );

      await expectLater(
        repo.correctObligationSettlement(
          'first-leg',
          newAmountMinor: 600000,
          categoryId: 'cho_vay',
          interestCategoryId: 'lai_cho_vay',
          newPrincipalId: 'first-leg-b',
          newPrincipalClientTxId: 'c-first-b',
          newInterestId: 'i-first-b',
          newInterestClientTxId: 'ci-first-b',
        ),
        throwsA(isA<NotLatestSettlementException>()),
      );

      // Sửa lần MỚI NHẤT thì được phép.
      final corrected = await repo.correctObligationSettlement(
        'second-leg',
        newAmountMinor: 600000,
        categoryId: 'cho_vay',
        interestCategoryId: 'lai_cho_vay',
        newPrincipalId: 'second-leg-b',
        newPrincipalClientTxId: 'c-second-b',
        newInterestId: 'i-second-b',
        newInterestClientTxId: 'ci-second-b',
      );
      expect(corrected.principal.amountMinor, 600000);
    });

    test('single-leg → two-leg correction: 500k (không lãi) sửa thành 1.4m (có lãi)', () async {
      await createReceivable('r13', 1200000);
      await repo.settleObligation(
        obligationId: 'r13',
        direction: ObligationDirection.receivable,
        memberRefId: 'vo',
        amountMinor: 500000,
        transactionDate: DateTime(2027, 1, 1),
        categoryId: 'cho_vay',
        interestCategoryId: 'lai_cho_vay',
        principalId: 'p13',
        principalClientTxId: 'c13',
        interestId: 'i13',
        interestClientTxId: 'ci13',
      );

      final corrected = await repo.correctObligationSettlement(
        'p13',
        newAmountMinor: 1400000,
        categoryId: 'cho_vay',
        interestCategoryId: 'lai_cho_vay',
        newPrincipalId: 'p13b',
        newPrincipalClientTxId: 'c13b',
        newInterestId: 'i13b',
        newInterestClientTxId: 'ci13b',
      );
      expect(corrected.principal.amountMinor, 1200000);
      expect(corrected.interest, isNotNull);
      expect(corrected.interest!.amountMinor, 200000);
    });

    test('two-leg → single-leg correction: 1.4m (có lãi) sửa thành 500k (không lãi)', () async {
      await createReceivable('r14', 1200000);
      await repo.settleObligation(
        obligationId: 'r14',
        direction: ObligationDirection.receivable,
        memberRefId: 'vo',
        amountMinor: 1400000,
        transactionDate: DateTime(2027, 1, 1),
        categoryId: 'cho_vay',
        interestCategoryId: 'lai_cho_vay',
        principalId: 'p14',
        principalClientTxId: 'c14',
        interestId: 'i14',
        interestClientTxId: 'ci14',
      );

      final corrected = await repo.correctObligationSettlement(
        'p14',
        newAmountMinor: 500000,
        categoryId: 'cho_vay',
        interestCategoryId: 'lai_cho_vay',
        newPrincipalId: 'p14b',
        newPrincipalClientTxId: 'c14b',
        newInterestId: 'i14b',
        newInterestClientTxId: 'ci14b',
      );
      expect(corrected.principal.amountMinor, 500000);
      expect(corrected.interest, isNull);

      final all = await repo.watchTransactions().first;
      final balances = computeAllPoolBalances(all);
      expect(poolBalance(balances, PoolKind.receivable, 'r14'), 700000);
    });
  });
}
