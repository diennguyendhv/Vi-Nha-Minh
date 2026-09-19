import 'dart:async';

import 'package:vi_nha_minh/core/utils/id_generator.dart';
import 'package:vi_nha_minh/domain/engine/financial_engine.dart';
import 'package:vi_nha_minh/domain/engine/obligation_settlement.dart';
import 'package:vi_nha_minh/domain/entities/counterparty.dart';
import 'package:vi_nha_minh/domain/entities/obligation.dart';
import 'package:vi_nha_minh/domain/entities/obligation_direction.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/errors/domain_exceptions.dart';
import 'package:vi_nha_minh/domain/repositories/counterparty_repository.dart';
import 'package:vi_nha_minh/domain/repositories/obligation_repository.dart';
import 'package:vi_nha_minh/domain/repositories/transaction_repository.dart';

/// Phase 8.8 — fake in-memory (không Drift) cho widget test "Vay & Cho vay".
///
/// LÝ DO: `loans_screen_test.dart` chạy qua `AppDatabase.forTesting(
/// NativeDatabase.memory())` trong `pumpAndSettle()` bị treo — CHỨNG MINH
/// bằng log thật (test đầu tiên, không hề có `tester.tap`, treo đúng 10
/// phút rồi ném `TimeoutException`/`A Timer is still pending even after the
/// widget tree was disposed`, stack trace trỏ vào
/// `package:drift/src/runtime/executor/stream_queries.dart`
/// (`StreamQueryStore.markAsClosed`) — Timer nội bộ của Drift's stream-query
/// không được `pumpAndSettle()` chờ/dọn đúng cách trong test environment
/// này). Đây là lỗi TEST HARNESS (kết hợp Drift thật + widget test), KHÔNG
/// phải lỗi Presentation — mọi widget test khác đã ổn định trong repo
/// (`add_transaction_sheet_test.dart`, `home_screen_test.dart`,
/// `transaction_detail_screen_test.dart`) đều dùng fake in-memory kiểu này,
/// không đụng Drift thật.
///
/// Logic tài chính (allocation gốc/lãi, atomicity, idempotency, reversal,
/// correction) đã được CHỨNG MINH đúng bằng test DB thật ở
/// `test/data/repositories/obligation_repository_test.dart` (15 test) và
/// `test/data/repositories/atomic_obligation_creation_test.dart` (9 test) —
/// fake ở đây KHÔNG re-chứng minh atomicity/idempotency mức SQL, chỉ tái sử
/// dụng ĐÚNG các hàm domain thuần (`buildObligationSettlementLegs`,
/// `computeObligationOutstanding`, `buildObligationSettlementReversal`,
/// `isSameLogicalTransaction`, `computeAllPoolBalances`, `wouldGoNegative`)
/// để widget test verify đúng số liệu hiển thị mà không cần SQLite.
class FakeLoanTransactionRepository implements TransactionRepository {
  final _controller = StreamController<List<Transaction>>.broadcast();

  /// Nếu đặt, `settleObligation` chờ cổng này trước khi ghi — giả lập lúc
  /// đang submit để test khoá Back/Close (R4).
  Completer<void>? pendingGate;
  List<Transaction> _all = const [];

  void _emit() => _controller.add(_all);

  Transaction? _byClientTxId(String clientTxId) {
    for (final t in _all) {
      if (t.clientTxId == clientTxId) return t;
    }
    return null;
  }

  Transaction? _byId(String id) {
    for (final t in _all) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  Stream<List<Transaction>> watchTransactions() async* {
    yield _all;
    yield* _controller.stream;
  }

  @override
  Future<Transaction> addTransaction(Transaction transaction) async {
    validateNewTransaction(transaction);
    final existing = _byClientTxId(transaction.clientTxId);
    if (existing != null) {
      if (isSameLogicalTransaction(existing, transaction)) return existing;
      throw ClientTxIdConflictException(
        clientTxId: transaction.clientTxId,
        existing: existing,
        attempted: transaction,
      );
    }
    final balances = computeAllPoolBalances(_all);
    if (wouldGoNegative(
      currentBalances: balances,
      kind: transaction.sourceKind,
      refId: transaction.sourceRefId,
      delta: -transaction.amountMinor,
    )) {
      throw InsufficientBalanceException(
        poolKind: transaction.sourceKind,
        refId: transaction.sourceRefId,
        currentBalance: poolBalance(
          balances,
          transaction.sourceKind,
          transaction.sourceRefId,
        ),
        requestedAmount: transaction.amountMinor,
      );
    }
    _all = [..._all, transaction];
    _emit();
    return transaction;
  }

  @override
  Future<Transaction?> getTransactionById(String id) async => _byId(id);

  @override
  Future<Transaction?> getTransactionByClientTxId(String clientTxId) async =>
      _byClientTxId(clientTxId);

  @override
  Future<void> reverseTransaction(String transactionId) =>
      throw UnimplementedError('not exercised by loans_screen_test.dart');

  @override
  Future<void> updateTransaction(
    String transactionId, {
    int? amountMinor,
    String? categoryId,
    String? note,
    String? memberRefId,
    DateTime? transactionDate,
    String? statusId,
  }) => throw UnimplementedError('not exercised by loans_screen_test.dart');

  @override
  Future<({Transaction principal, Transaction? interest})> settleObligation({
    required String obligationId,
    required ObligationDirection direction,
    required String memberRefId,
    required int amountMinor,
    required DateTime transactionDate,
    String note = '',
    required String categoryId,
    required String interestCategoryId,
    required String principalId,
    required String principalClientTxId,
    required String interestId,
    required String interestClientTxId,
  }) async {
    if (amountMinor <= 0) throw InvalidAmountException(amountMinor);
    if (pendingGate != null) await pendingGate!.future;
    final creation = findObligationCreationTransaction(
      direction,
      obligationId,
      _all,
    );
    if (creation == null) {
      throw ObligationCreationNotFoundException(obligationId);
    }
    final balances = computeAllPoolBalances(_all);
    final outstanding = computeObligationOutstanding(
      direction,
      obligationId,
      _all,
      balances,
    );
    final legs = buildObligationSettlementLegs(
      direction: direction,
      obligationId: obligationId,
      memberRefId: memberRefId,
      outstanding: outstanding,
      paymentAmount: amountMinor,
      categoryId: categoryId,
      interestCategoryId: interestCategoryId,
      currency: creation.currency,
      principalId: principalId,
      principalClientTxId: principalClientTxId,
      interestId: interestId,
      interestClientTxId: interestClientTxId,
      transactionDate: transactionDate,
      now: DateTime.now(),
      note: note,
    );

    final existingPrincipal = _byClientTxId(principalClientTxId);
    final existingInterest = _byClientTxId(interestClientTxId);
    if (existingPrincipal != null && existingInterest != null) {
      final matches =
          existingPrincipal.obligationId == obligationId &&
          existingInterest.obligationId == obligationId &&
          existingInterest.settlementGroupId == existingPrincipal.id &&
          existingPrincipal.amountMinor + existingInterest.amountMinor ==
              amountMinor;
      if (matches) {
        return (principal: existingPrincipal, interest: existingInterest);
      }
      throw ClientTxIdConflictException(
        clientTxId: principalClientTxId,
        existing: existingPrincipal,
        attempted: legs.principal,
      );
    }
    if (existingPrincipal != null && existingInterest == null) {
      final matchesSingleLeg =
          existingPrincipal.obligationId == obligationId &&
          existingPrincipal.settlementGroupId == null &&
          existingPrincipal.amountMinor == amountMinor;
      if (matchesSingleLeg) {
        return (principal: existingPrincipal, interest: null);
      }
      throw SettlementIntegrityException(
        obligationId: obligationId,
        clientTxId: principalClientTxId,
        missingLeg: 'interest',
      );
    }
    if (existingPrincipal == null && existingInterest != null) {
      throw SettlementIntegrityException(
        obligationId: obligationId,
        clientTxId: principalClientTxId,
        missingLeg: 'principal',
      );
    }

    if (wouldGoNegative(
      currentBalances: balances,
      kind: legs.principal.sourceKind,
      refId: legs.principal.sourceRefId,
      delta: -legs.principal.amountMinor,
    )) {
      throw InsufficientBalanceException(
        poolKind: legs.principal.sourceKind,
        refId: legs.principal.sourceRefId,
        currentBalance: poolBalance(
          balances,
          legs.principal.sourceKind,
          legs.principal.sourceRefId,
        ),
        requestedAmount: legs.principal.amountMinor,
      );
    }
    _all = [..._all, legs.principal, if (legs.interest != null) legs.interest!];
    _emit();
    return (principal: legs.principal, interest: legs.interest);
  }

  @override
  Future<void> reverseObligationSettlement(String anyLegTransactionId) async {
    final tx = _byId(anyLegTransactionId);
    if (tx == null || tx.reversalOfTxId != null) {
      throw TransactionNotFoundException(anyLegTransactionId);
    }
    final groupId = tx.settlementGroupId ?? tx.id;
    final groupLegs = _all
        .where((t) => t.id == groupId || t.settlementGroupId == groupId)
        .toList();
    if (groupLegs.isEmpty) {
      throw TransactionNotFoundException(anyLegTransactionId);
    }
    for (final leg in groupLegs) {
      if (leg.reversedByTxId != null) {
        throw AlreadyReversedException(leg.id, leg.reversedByTxId!);
      }
    }
    final now = DateTime.now();
    final reversals = buildObligationSettlementReversal(
      groupLegs,
      newIds: [for (final _ in groupLegs) IdGenerator.generate()],
      clientTxIds: [for (final _ in groupLegs) IdGenerator.generate()],
      now: now,
    );
    var updated = _all;
    for (var i = 0; i < groupLegs.length; i++) {
      updated = [
        for (final t in updated)
          t.id == groupLegs[i].id
              ? t.copyWith(reversedByTxId: reversals[i].id)
              : t,
      ];
    }
    _all = [...updated, ...reversals];
    _emit();
  }

  @override
  Future<({Transaction principal, Transaction? interest})>
  correctObligationSettlement(
    String anyLegTransactionId, {
    required int newAmountMinor,
    required String categoryId,
    required String interestCategoryId,
    required String newPrincipalId,
    required String newPrincipalClientTxId,
    required String newInterestId,
    required String newInterestClientTxId,
  }) async {
    if (newAmountMinor <= 0) throw InvalidAmountException(newAmountMinor);
    final tx = _byId(anyLegTransactionId);
    if (tx == null || tx.reversalOfTxId != null || tx.obligationId == null) {
      throw TransactionNotFoundException(anyLegTransactionId);
    }
    final obligationId = tx.obligationId!;
    final groupId = tx.settlementGroupId ?? tx.id;
    final groupLegs = _all
        .where((t) => t.id == groupId || t.settlementGroupId == groupId)
        .toList();
    if (groupLegs.isEmpty) {
      throw TransactionNotFoundException(anyLegTransactionId);
    }
    for (final leg in groupLegs) {
      if (leg.reversedByTxId != null) {
        throw AlreadyReversedException(leg.id, leg.reversedByTxId!);
      }
    }
    final direction = groupLegs.any(
      (t) =>
          t.sourceKind == PoolKind.receivable ||
          t.destinationKind == PoolKind.receivable,
    )
        ? ObligationDirection.receivable
        : ObligationDirection.payable;
    final anchors = listObligationSettlementAnchors(
      direction,
      obligationId,
      _all,
    );
    if (anchors.isEmpty || anchors.last.id != groupId) {
      throw NotLatestSettlementException(anyLegTransactionId, obligationId);
    }
    final memberRefId = direction == ObligationDirection.receivable
        ? groupLegs
            .firstWhere((t) => t.sourceKind == PoolKind.receivable)
            .destinationRefId!
        : groupLegs.first.sourceRefId!;
    final now = DateTime.now();
    final reversals = buildObligationSettlementReversal(
      groupLegs,
      newIds: [for (final _ in groupLegs) IdGenerator.generate()],
      clientTxIds: [for (final _ in groupLegs) IdGenerator.generate()],
      now: now,
    );
    final workingList = [..._all, ...reversals];
    final creation = findObligationCreationTransaction(
      direction,
      obligationId,
      workingList,
    );
    if (creation == null) {
      throw ObligationCreationNotFoundException(obligationId);
    }
    final workingBalances = computeAllPoolBalances(workingList);
    final restoredOutstanding = computeObligationOutstanding(
      direction,
      obligationId,
      workingList,
      workingBalances,
    );
    final newLegs = buildObligationSettlementLegs(
      direction: direction,
      obligationId: obligationId,
      memberRefId: memberRefId,
      outstanding: restoredOutstanding,
      paymentAmount: newAmountMinor,
      categoryId: categoryId,
      interestCategoryId: interestCategoryId,
      currency: creation.currency,
      principalId: newPrincipalId,
      principalClientTxId: newPrincipalClientTxId,
      interestId: newInterestId,
      interestClientTxId: newInterestClientTxId,
      transactionDate: tx.transactionDate,
      now: now,
      note: tx.note,
    );
    if (wouldGoNegative(
      currentBalances: workingBalances,
      kind: newLegs.principal.sourceKind,
      refId: newLegs.principal.sourceRefId,
      delta: -newLegs.principal.amountMinor,
    )) {
      throw InsufficientBalanceException(
        poolKind: newLegs.principal.sourceKind,
        refId: newLegs.principal.sourceRefId,
        currentBalance: poolBalance(
          workingBalances,
          newLegs.principal.sourceKind,
          newLegs.principal.sourceRefId,
        ),
        requestedAmount: newLegs.principal.amountMinor,
      );
    }
    var updated = _all;
    for (var i = 0; i < groupLegs.length; i++) {
      updated = [
        for (final t in updated)
          t.id == groupLegs[i].id
              ? t.copyWith(reversedByTxId: reversals[i].id)
              : t,
      ];
    }
    _all = [
      ...updated,
      ...reversals,
      newLegs.principal,
      if (newLegs.interest != null) newLegs.interest!,
    ];
    _emit();
    return (principal: newLegs.principal, interest: newLegs.interest);
  }
}

/// Fake `ObligationRepository` — metadata in-memory + atomic create mô
/// phỏng: chỉ persist metadata SAU KHI ghi ledger thành công (nếu ledger
/// ném lỗi, metadata KHÔNG được thêm) — giữ đúng bất biến "commit cả 2 hoặc
/// không cái nào" ở MỨC HÀNH VI QUAN SÁT ĐƯỢC cho widget test, dù không
/// dùng SQL transaction thật (atomicity SQL thật đã test riêng ở
/// `atomic_obligation_creation_test.dart`).
class FakeObligationRepository implements ObligationRepository {
  FakeObligationRepository(this._transactionRepository);

  final FakeLoanTransactionRepository _transactionRepository;
  final _controller = StreamController<List<Obligation>>.broadcast();
  List<Obligation> _all = const [];

  @override
  Stream<List<Obligation>> watchObligations() async* {
    yield _all;
    yield* _controller.stream;
  }

  @override
  Future<void> addObligation(Obligation obligation) async {
    _all = [..._all, obligation];
    _controller.add(_all);
  }

  @override
  Future<void> updateObligation(Obligation obligation) async {
    _all = [for (final o in _all) o.id == obligation.id ? obligation : o];
    _controller.add(_all);
  }

  @override
  Future<Transaction> createObligationWithOpeningTransaction(
    Obligation obligation,
    Transaction opening,
  ) async {
    final alreadyPersisted = _all.any((o) => o.id == obligation.id);
    final result = await _transactionRepository.addTransaction(opening);
    if (!alreadyPersisted) {
      _all = [..._all, obligation];
      _controller.add(_all);
    }
    return result;
  }
}

class FakeCounterpartyRepository implements CounterpartyRepository {
  final _controller = StreamController<List<Counterparty>>.broadcast();
  List<Counterparty> _all = const [];

  @override
  Stream<List<Counterparty>> watchCounterparties() async* {
    yield _all;
    yield* _controller.stream;
  }

  @override
  Future<void> addCounterparty(Counterparty counterparty) async {
    _all = [..._all, counterparty];
    _controller.add(_all);
  }

  @override
  Future<void> updateCounterparty(Counterparty counterparty) async {
    _all = [
      for (final c in _all) c.id == counterparty.id ? counterparty : c,
    ];
    _controller.add(_all);
  }

  @override
  Future<void> softDeleteCounterparty(String counterpartyId) async {
    _all = [
      for (final c in _all)
        c.id == counterpartyId ? c.copyWith(isActive: false) : c,
    ];
    _controller.add(_all);
  }
}
