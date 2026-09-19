import '../engine/financial_engine.dart';
import '../engine/obligation_settlement.dart';
import '../entities/obligation.dart';
import '../entities/obligation_direction.dart';
import '../entities/transaction.dart';

/// Phase 8.7 — trạng thái tất toán, DERIVED hoàn toàn từ ledger (audit mục
/// K — ưu tiên derived state, không lưu status riêng vì dễ lệch).
enum ObligationStatus { open, partiallySettled, settled }

/// Read model DUY NHẤT cho 1 `Obligation` — dùng cho Transaction Detail/
/// list "Khoản vay" tương lai. Thuần Dart, không phụ thuộc Flutter.
class ObligationSummary {
  const ObligationSummary({
    required this.originalPrincipal,
    required this.outstanding,
    required this.totalPrincipalSettled,
    required this.totalInterest,
  });

  /// `amountMinor` của giao dịch TẠO khoản vay — không đổi theo thời gian
  /// (trừ khi correction lúc CHƯA có tất toán nào, audit mục M).
  final int originalPrincipal;

  final int outstanding;
  final int totalPrincipalSettled;
  final int totalInterest;

  ObligationStatus get status {
    if (outstanding <= 0) return ObligationStatus.settled;
    if (totalPrincipalSettled > 0) return ObligationStatus.partiallySettled;
    return ObligationStatus.open;
  }

  /// `dueDate != null && dueDate < now && outstanding > 0` — derive thuần,
  /// không lưu (audit mục K/J).
  bool isOverdue(DateTime? dueDate, DateTime now) {
    return dueDate != null && dueDate.isBefore(now) && outstanding > 0;
  }
}

/// [obligation] chỉ cần cho `direction` — không đọc `dueDate`/`note` ở đây
/// (hiển thị thuần, không phải tính toán tài chính). Trả `null` nếu khoản
/// vay chưa từng có giao dịch TẠO (vd `Obligation` mới add metadata, chưa
/// ghi giao dịch gốc — giống 1 `Fund` rỗng chưa nạp).
ObligationSummary? computeObligationSummary(
  Obligation obligation,
  List<Transaction> allTransactions,
) {
  final creation = findObligationCreationTransaction(
    obligation.direction,
    obligation.id,
    allTransactions,
  );
  if (creation == null) return null;

  final balances = computeAllPoolBalances(allTransactions);
  final outstanding = computeObligationOutstanding(
    obligation.direction,
    obligation.id,
    allTransactions,
    balances,
  );
  final totalPrincipalSettled = creation.amountMinor - outstanding;

  final totalInterest = switch (obligation.direction) {
    // Receivable: lãi đã là 1 dòng INCOME riêng (leg "interest" của mỗi lần
    // tất toán) — nhận diện bằng `settlementGroupId != null && id !=
    // settlementGroupId` (leg principal luôn TỰ trỏ, leg interest trỏ SANG
    // principal — xem `buildObligationSettlementLegs`).
    ObligationDirection.receivable => allTransactions
        .where(
          (t) =>
              t.obligationId == obligation.id &&
              isVisible(t) &&
              t.settlementGroupId != null &&
              t.id != t.settlementGroupId,
        )
        .fold<int>(0, (s, t) => s + t.amountMinor),
    // Payable: lãi gộp chung trong leg settlement duy nhất — phân bổ bằng
    // walk tuần tự (cùng hình dạng thuật toán 8.6B, hàm riêng — xem
    // computeObligationSettlementInterestPortions).
    ObligationDirection.payable => computeObligationSettlementInterestPortions(
      allTransactions,
    ).entries.where((e) => e.value > 0 && _belongsToObligation(e.key, obligation.id, allTransactions)).fold<int>(
      0,
      (s, e) => s + e.value,
    ),
  };

  return ObligationSummary(
    originalPrincipal: creation.amountMinor,
    outstanding: outstanding,
    totalPrincipalSettled: totalPrincipalSettled < 0 ? 0 : totalPrincipalSettled,
    totalInterest: totalInterest,
  );
}

bool _belongsToObligation(
  String transactionId,
  String obligationId,
  List<Transaction> allTransactions,
) {
  for (final t in allTransactions) {
    if (t.id == transactionId) return t.obligationId == obligationId;
  }
  return false;
}

/// Phase 8.7 — Payable: phân bổ phần LÃI (report được như Expense) CHO
/// TỪNG settlement transaction, để `computeThreeTotals` cộng đúng vào đúng
/// tháng của chính leg đó (khác Receivable — lãi đã là 1 dòng riêng, không
/// cần hàm này). Cùng HÌNH DẠNG thuật toán với `computeRecoveryProfitPortions`
/// (Phase 8.6B: trừ outstanding trước, phần dư là lãi) nhưng KHÔNG dùng
/// chung hàm/field (audit Phase 8.7 mục 23 — chia sẻ Ý TƯỞNG thuật toán,
/// không chia sẻ quan hệ domain, vì `Obligation` và Asset Recovery có vòng
/// đời khác hẳn nhau).
Map<String, int> computeObligationSettlementInterestPortions(
  List<Transaction> allTransactions,
) {
  final byObligation = <String, List<Transaction>>{};
  for (final t in allTransactions) {
    if (t.obligationId == null || !isVisible(t)) continue;
    if (!isObligationSettlementPrincipalShape(t, ObligationDirection.payable)) {
      continue;
    }
    byObligation.putIfAbsent(t.obligationId!, () => []).add(t);
  }

  final creationByObligation = <String, Transaction>{};
  for (final t in allTransactions) {
    if (t.obligationId == null || !isVisible(t)) continue;
    if (isObligationCreationShape(t, ObligationDirection.payable)) {
      creationByObligation[t.obligationId!] = t;
    }
  }

  final portions = <String, int>{};
  for (final entry in byObligation.entries) {
    final creation = creationByObligation[entry.key];
    if (creation == null) continue;

    final orderedSettlements = entry.value
      ..sort((a, b) {
        final byDate = a.transactionDate.compareTo(b.transactionDate);
        if (byDate != 0) return byDate;
        final byCreatedAt = a.createdAt.compareTo(b.createdAt);
        if (byCreatedAt != 0) return byCreatedAt;
        return a.id.compareTo(b.id);
      });

    var remainingOutstanding = creation.amountMinor;
    for (final s in orderedSettlements) {
      final principalPortion = s.amountMinor < remainingOutstanding
          ? s.amountMinor
          : remainingOutstanding;
      portions[s.id] = s.amountMinor - principalPortion;
      remainingOutstanding -= principalPortion;
    }
  }
  return portions;
}
