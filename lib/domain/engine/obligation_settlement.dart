import '../entities/obligation_direction.dart';
import '../entities/pool_kind.dart';
import '../entities/transaction.dart';
import '../entities/transaction_type.dart';
import 'financial_engine.dart';

/// Phase 8.7 — engine phụ trách "khoản vay/cho vay" (`Obligation`), tách
/// RIÊNG khỏi `financial_engine.dart` (không sửa `applyEffect`/
/// `typeFromEndpoints`/`buildReversal`/`buildCorrection` đã freeze — audit
/// Phase 8.7 mục 23: công thức phân bổ gốc/lãi nhìn giống Asset Recovery
/// (Phase 8.6B) nhưng KHÔNG dùng chung field/hàm, vì `Obligation` có vòng
/// đời/quan hệ khác hẳn `recoveryOfTxId`).
///
/// Nguyên tắc cốt lõi (đã audit + approve):
/// - **Receivable** (cho vay) = 1 pool THẬT (`PoolKind.receivable`) — tạo
///   khoản vay và trả gốc (không lãi) là TRANSFER đơn thuần, dùng lại
///   nguyên `applyEffect`/`wouldGoNegative` (Invariant 7 tự động chặn thu
///   hồi vượt gốc, không cần validate riêng).
/// - **Payable** (đi vay) KHÔNG có PoolKind riêng — tạo khoản vay = 1 dòng
///   INCOME thường, trả nợ = 1 dòng EXPENSE thường; outstanding tính
///   DERIVED (không cache).
/// - Principal-first allocation (đã approve): `payment` → trừ outstanding
///   trước → phần dư mới là lãi.

/// Hình dạng "giao dịch TẠO khoản vay" theo từng `direction` — dùng để suy
/// ra giao dịch gốc từ ledger mà KHÔNG cần lưu `Obligation.creationTxId`
/// riêng (audit mục H — giảm bề mặt schema khi suy ra được an toàn).
bool isObligationCreationShape(Transaction t, ObligationDirection direction) {
  switch (direction) {
    case ObligationDirection.receivable:
      return t.type == TransactionType.transfer &&
          t.destinationKind == PoolKind.receivable;
    case ObligationDirection.payable:
      return t.type == TransactionType.income && t.settlementGroupId == null;
  }
}

/// Hình dạng "leg principal của 1 lần tất toán" — luôn có `settlementGroupId
/// == null` (leg neo, TỰ trỏ vào chính `id` của nó khi ghi — xem
/// [buildObligationSettlementLegs]), phân biệt với giao dịch TẠO bằng chiều
/// pool/`type` ngược lại.
bool isObligationSettlementPrincipalShape(
  Transaction t,
  ObligationDirection direction,
) {
  switch (direction) {
    case ObligationDirection.receivable:
      return t.type == TransactionType.transfer &&
          t.sourceKind == PoolKind.receivable;
    case ObligationDirection.payable:
      return t.type == TransactionType.expense;
  }
}

/// Tìm giao dịch TẠO khoản vay (còn `isVisible`) cho 1 `obligationId` — trả
/// `null` nếu chưa từng tạo (vd `Obligation` mới add metadata, chưa ghi
/// giao dịch gốc — giống 1 `Fund` rỗng chưa nạp).
Transaction? findObligationCreationTransaction(
  ObligationDirection direction,
  String obligationId,
  List<Transaction> allTransactions,
) {
  for (final t in allTransactions) {
    if (t.obligationId != obligationId || !isVisible(t)) continue;
    if (isObligationCreationShape(t, direction)) return t;
  }
  return null;
}

/// Toàn bộ leg "principal" (neo tất toán) của 1 khoản vay, còn `isVisible`,
/// sắp theo thời gian TĂNG DẦN (cũ → mới) — dùng để xác định "lần tất toán
/// mới nhất" (audit mục M — chỉ cho sửa leg cuối danh sách này) và để tính
/// outstanding của Payable.
List<Transaction> listObligationSettlementAnchors(
  ObligationDirection direction,
  String obligationId,
  List<Transaction> allTransactions,
) {
  final anchors = allTransactions
      .where(
        (t) =>
            t.obligationId == obligationId &&
            isVisible(t) &&
            // Leg neo (principal) — HOẶC không ghép cặp (`settlementGroupId
            // == null`, tất toán không lãi) HOẶC tự trỏ vào chính nó (`==
            // t.id`, tất toán có lãi — xem `buildObligationSettlementLegs`).
            // KHÔNG được lọc `settlementGroupId == null` đơn thuần — bug đã
            // audit: loại nhầm principal có leg lãi đi kèm (nó KHÔNG null
            // trong case đó), làm sai "tất toán mới nhất" (mục M).
            (t.settlementGroupId == null || t.settlementGroupId == t.id) &&
            isObligationSettlementPrincipalShape(t, direction),
      )
      .toList()
    ..sort((a, b) {
      final byDate = a.transactionDate.compareTo(b.transactionDate);
      if (byDate != 0) return byDate;
      final byCreatedAt = a.createdAt.compareTo(b.createdAt);
      if (byCreatedAt != 0) return byCreatedAt;
      return a.id.compareTo(b.id);
    });
  return anchors;
}

/// Outstanding hiện tại của 1 khoản vay:
/// - Receivable: đọc thẳng `poolBalance(PoolKind.receivable, obligationId)`
///   — pool THẬT, tự động đúng qua `computeAllPoolBalances` (không cần
///   walk tuần tự).
/// - Payable: derived — `creation.amountMinor - Σ(toàn bộ settlement leg
///   đang hiệu lực)`, luôn kẹp `>= 0`. Công thức closed-form này TƯƠNG
///   ĐƯƠNG walk tuần tự "trừ gốc trước" (đã chứng minh trong audit): lãi
///   chỉ phát sinh SAU khi outstanding đã về 0, nên tổng đã tất toán ==
///   tổng đã trừ gốc CHO TỚI KHI outstanding chạm 0, sau đó cả 2 công thức
///   cùng cho kết quả 0 — không cần walk từng leg để ra được TỔNG outstanding
///   (walk tuần tự chỉ cần khi phân bổ lãi CHO TỪNG leg riêng, xem
///   [computeObligationInterestPortions] ở `compute_obligation_summary.dart`).
///   Trả 0 nếu chưa từng tạo khoản vay (chưa có giao dịch gốc).
int computeObligationOutstanding(
  ObligationDirection direction,
  String obligationId,
  List<Transaction> allTransactions,
  Map<PoolRef, int> poolBalances,
) {
  switch (direction) {
    case ObligationDirection.receivable:
      return poolBalance(poolBalances, PoolKind.receivable, obligationId);
    case ObligationDirection.payable:
      final creation = findObligationCreationTransaction(
        direction,
        obligationId,
        allTransactions,
      );
      if (creation == null) return 0;
      final totalSettled = allTransactions
          .where(
            (t) =>
                t.obligationId == obligationId &&
                isVisible(t) &&
                isObligationSettlementPrincipalShape(t, direction),
          )
          .fold<int>(0, (s, t) => s + t.amountMinor);
      final outstanding = creation.amountMinor - totalSettled;
      return outstanding < 0 ? 0 : outstanding;
  }
}

/// Kết quả build 1 lần tất toán — 1 hoặc 2 dòng ledger.
class ObligationSettlementLegs {
  const ObligationSettlementLegs({required this.principal, this.interest});

  /// Leg trừ/thu đúng phần OUTSTANDING (gốc). LUÔN có mặt, kể cả khi
  /// `amountMinor == 0`? KHÔNG — nếu `outstanding == 0` (đã tất toán hết,
  /// khoản trả/thu tiếp theo 100% là lãi), `principal` vẫn được build với
  /// `amountMinor` bằng đúng phần principal (>0 khi còn outstanding, có thể
  /// là toàn bộ payment nếu payment <= outstanding).
  final Transaction principal;

  /// Leg phần vượt outstanding (lãi) — `null` khi `payment <= outstanding`
  /// (không cần 2 dòng).
  final Transaction? interest;

  List<Transaction> get legs => [principal, ?interest];
}

/// Build 1 lần tất toán (thu hồi Receivable / trả nợ Payable) theo đúng quy
/// tắc "principal-first" đã approve: `principalPortion = min(payment,
/// outstanding)`, `interestPortion = payment - principalPortion`.
///
/// - `principal.id` LUÔN được dùng làm `settlementGroupId` (Receivable: TỰ
///   trỏ vào chính nó; Payable: không cần group vì luôn 1 dòng, nhưng vẫn để
///   `null` — xem field doc `Transaction.settlementGroupId`).
/// - Payable KHÔNG BAO GIỜ tạo leg `interest` riêng — 1 dòng EXPENSE duy
///   nhất luôn gánh cả 2 phần, phân bổ lãi tính DERIVED ở tầng đọc báo cáo
///   (`computeObligationInterestPortions`), vì principal-repay và
///   interest-expense cùng 1 chiều tiền (`memberAvailable → external`) —
///   không cần 2 dòng như Receivable (vốn có 2 chiều tiền KHÁC nhau: gốc
///   `receivable → memberAvailable`, lãi `external → memberAvailable`).
ObligationSettlementLegs buildObligationSettlementLegs({
  required ObligationDirection direction,
  required String obligationId,
  required String memberRefId,
  required int outstanding,
  required int paymentAmount,
  required String categoryId,
  required String interestCategoryId,
  required String currency,
  required String principalId,
  required String principalClientTxId,
  required String? interestId,
  required String? interestClientTxId,
  required DateTime transactionDate,
  required DateTime now,
  String note = '',
}) {
  final principalPortion = paymentAmount < outstanding
      ? paymentAmount
      : outstanding;
  final interestPortion = paymentAmount - principalPortion;

  switch (direction) {
    case ObligationDirection.receivable:
      // Outstanding đã về 0 từ trước (khoản vay đã tất toán hết gốc) mà
      // vẫn còn payment mới — 100% là lãi, không có leg gốc để ghép cặp
      // (đứng riêng, `settlementGroupId = null`, giống 1 settlement không
      // lãi bình thường). Case biên hiếm gặp, KHÔNG nằm trong test matrix
      // bắt buộc của Phase 8.7 — vẫn xử lý an toàn thay vì tạo 1 dòng
      // `amountMinor = 0` vi phạm Invariant 12.
      if (outstanding <= 0 && interestPortion > 0) {
        final interestOnly = Transaction(
          id: principalId,
          type: TransactionType.income,
          categoryId: interestCategoryId,
          sourceKind: PoolKind.external,
          destinationKind: PoolKind.memberAvailable,
          destinationRefId: memberRefId,
          amountMinor: interestPortion,
          currency: currency,
          note: note,
          transactionDate: transactionDate,
          createdAt: now,
          obligationId: obligationId,
          clientTxId: principalClientTxId,
        );
        return ObligationSettlementLegs(principal: interestOnly);
      }
      final principal = Transaction(
        id: principalId,
        type: TransactionType.transfer,
        categoryId: categoryId,
        sourceKind: PoolKind.receivable,
        sourceRefId: obligationId,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: memberRefId,
        amountMinor: principalPortion,
        currency: currency,
        note: note,
        transactionDate: transactionDate,
        createdAt: now,
        obligationId: obligationId,
        settlementGroupId: interestPortion > 0 ? principalId : null,
        clientTxId: principalClientTxId,
      );
      if (interestPortion <= 0) {
        return ObligationSettlementLegs(principal: principal);
      }
      final interest = Transaction(
        id: interestId!,
        type: TransactionType.income,
        categoryId: interestCategoryId,
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: memberRefId,
        amountMinor: interestPortion,
        currency: currency,
        note: note,
        transactionDate: transactionDate,
        createdAt: now,
        obligationId: obligationId,
        settlementGroupId: principalId,
        clientTxId: interestClientTxId!,
      );
      return ObligationSettlementLegs(principal: principal, interest: interest);

    case ObligationDirection.payable:
      // Luôn 1 dòng duy nhất — amount = TOÀN BỘ payment (principal + lãi
      // gộp chung, vì cùng chiều tiền memberAvailable → external). Phân bổ
      // lãi cho báo cáo tính ở compute_obligation_summary.dart, KHÔNG ở
      // đây (hàm này chỉ build ledger row, không phải read model).
      final principal = Transaction(
        id: principalId,
        type: TransactionType.expense,
        categoryId: categoryId,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: memberRefId,
        destinationKind: PoolKind.external,
        amountMinor: paymentAmount,
        currency: currency,
        note: note,
        transactionDate: transactionDate,
        createdAt: now,
        obligationId: obligationId,
        clientTxId: principalClientTxId,
      );
      return ObligationSettlementLegs(principal: principal);
  }
}

/// Build reversal cho TOÀN BỘ leg của 1 lần tất toán (1 hoặc 2 dòng) —
/// atomic ở tầng gọi (Repository), hàm này chỉ build object thuần. Dùng lại
/// NGUYÊN `buildReversal` (financial_engine.dart, đã freeze) cho từng leg,
/// không viết lại logic đảo source/destination.
List<Transaction> buildObligationSettlementReversal(
  List<Transaction> legs, {
  required List<String> newIds,
  required List<String> clientTxIds,
  required DateTime now,
}) {
  assert(newIds.length == legs.length && clientTxIds.length == legs.length);
  return [
    for (var i = 0; i < legs.length; i++)
      buildReversal(
        legs[i],
        newId: newIds[i],
        clientTxId: clientTxIds[i],
        now: now,
      ),
  ];
}
