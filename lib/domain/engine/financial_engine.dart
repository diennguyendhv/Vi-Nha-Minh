import '../entities/pool_kind.dart';
import '../entities/transaction.dart';
import '../entities/transaction_type.dart';
import '../errors/domain_exceptions.dart';

/// Khoá 1 "pool" tiền — `(kind, refId)` (`docs/financial-core-v2.md` mục 4).
/// `refId` luôn null khi `kind == PoolKind.external`.
typedef PoolRef = (PoolKind kind, String? refId);

// Financial Engine trung tâm — 1 nơi DUY NHẤT hiểu "tiền chạy đi đâu".
// Không có nhánh if/else riêng cho quỹ/tiết kiệm/chuyển khoản ở bất kỳ nơi
// nào khác trong domain/presentation — mọi nơi đều gọi qua đây.

/// `applyEffect(tx, sign)` — đúng pseudocode mục 6. `sign = +1` khi cộng dồn
/// hiệu ứng, `-1` khi cần trừ ngược lại (hiếm dùng trực tiếp — thường dùng
/// [buildReversal] để tạo 1 transaction mới thay vì gọi sign=-1 thủ công).
void applyEffect(Transaction tx, int sign, Map<PoolRef, int> balances) {
  if (tx.sourceKind != PoolKind.external) {
    final key = (tx.sourceKind, tx.sourceRefId);
    balances[key] = (balances[key] ?? 0) - sign * tx.amountMinor;
  }
  if (tx.destinationKind != PoolKind.external) {
    final key = (tx.destinationKind, tx.destinationRefId);
    balances[key] = (balances[key] ?? 0) + sign * tx.amountMinor;
  }
}

/// Balance của mọi pool = tổng `applyEffect` của **toàn bộ** transaction
/// trong bảng, không lọc gì cả (Invariant 10). Đây là điểm quan trọng nhất
/// của reversal ledger: 1 giao dịch bị hoàn tác vẫn nằm trong tổng này,
/// nhưng bản reversal của nó (source/destination đảo ngược, cùng số tiền)
/// tự động triệt tiêu đúng hiệu ứng cũ khi cộng dồn — không cần lọc
/// `reversedByTxId`/`reversalOfTxId` ở bước này.
Map<PoolRef, int> computeAllPoolBalances(Iterable<Transaction> transactions) {
  final balances = <PoolRef, int>{};
  for (final tx in transactions) {
    applyEffect(tx, 1, balances);
  }
  return balances;
}

int poolBalance(Map<PoolRef, int> balances, PoolKind kind, String? refId) {
  return balances[(kind, refId)] ?? 0;
}

/// Transaction "đang hiệu lực, hiện cho người dùng thấy" — dùng cho danh
/// sách giao dịch, rollup tháng (Total Income/Expense/Transfer), breakdown
/// theo hạng mục/trạng thái. KHÔNG dùng bộ lọc này để tính balance (xem
/// [computeAllPoolBalances] ở trên — balance luôn cộng dồn toàn bộ).
///
/// - `reversedByTxId != null`: bản gốc đã bị hoàn tác/thay thế — ẩn.
/// - `reversalOfTxId != null`: bản thân đây là 1 bản ghi hoàn tác nội bộ
///   (không phải giao dịch người dùng tạo) — ẩn. Bản thay thế
///   (`correctsTxId != null`) KHÔNG bị ẩn bởi điều kiện này vì nó không
///   phải là 1 bản reversal, chỉ là bản mới nhất.
bool isVisible(Transaction tx) {
  return tx.reversedByTxId == null && tx.reversalOfTxId == null;
}

/// Suy `type` từ vị trí source/destination — đúng định nghĩa mục 1 của
/// Executive Summary: EXPENSE = destination external, INCOME = source
/// external, còn lại là TRANSFER.
TransactionType typeFromEndpoints(PoolKind source, PoolKind destination) {
  if (source == PoolKind.external) return TransactionType.income;
  if (destination == PoolKind.external) return TransactionType.expense;
  return TransactionType.transfer;
}

/// Kiểm tra Invariant 12 (`amountMinor` luôn dương) và Invariant 15
/// (source/destination không được là cùng 1 pool) TRƯỚC khi ghi 1 giao dịch
/// mới. Hàm thuần domain, không đụng DB/repository — caller (repository,
/// Phase 2) gọi hàm này ngay trước khi ghi để có validate THẬT, không chỉ
/// dựa vào `assert()` trong constructor `Transaction` (bị strip ở release
/// build).
void validateNewTransaction(Transaction tx) {
  if (tx.amountMinor <= 0) {
    throw InvalidAmountException(tx.amountMinor);
  }
  if (tx.sourceKind == tx.destinationKind && tx.sourceRefId == tx.destinationRefId) {
    throw SameSourceDestinationException(tx.sourceKind, tx.sourceRefId);
  }
}

/// Kiểm tra Invariant 7 (Quỹ/Tiết kiệm/MEMBER_AVAILABLE không bao giờ âm)
/// TRƯỚC khi ghi 1 giao dịch mới — gọi với `delta = -amountMinor` cho pool
/// nguồn của giao dịch sắp tạo.
bool wouldGoNegative({
  required Map<PoolRef, int> currentBalances,
  required PoolKind kind,
  required String? refId,
  required int delta,
}) {
  if (kind == PoolKind.external) return false;
  final current = currentBalances[(kind, refId)] ?? 0;
  return current + delta < 0;
}

/// So sánh 2 giao dịch có cùng "ý định tài chính" hay không — dùng cho
/// idempotency của `clientTxId` (Phase 3, `docs/financial-core-v2.md` mục
/// 14 + mục 6 spec Phase 3): nếu 2 payload cùng gửi 1 `clientTxId` nhưng
/// các field này khác nhau, đó là [ClientTxIdConflictException], KHÔNG phải
/// retry hợp lệ.
///
/// **Cập nhật Phase 3.1 (audit lại theo yêu cầu — idempotency xác định
/// "same request", không chỉ "same financial effect"):** so cả
/// `transactionDate`/`note`/`statusId` vì cả 3 đều là dữ liệu người dùng
/// nhập/CHỌN ngay trên màn "Thêm giao dịch" (`docs/design.html` màn 09) lúc
/// tạo, KHÔNG phải metadata hệ thống tự sinh:
/// - `transactionDate`: có date-picker riêng trên màn 09 (mặc định "Hôm
///   nay", đổi được), cố tình tách khỏi `createdAt` để rollup đúng tháng
///   phát sinh thật (`docs/financial-core-v2.md` F-07) — 1 retry hợp lệ
///   (resend đúng request cũ) luôn mang cùng giá trị đã chọn.
/// - `note`: input text tự do ngay trên màn 09 (cả 3 panel Thu/Chi/Chuyển).
/// - `statusId`: với category có `statuses`, màn 09 có `status-stepper` để
///   chọn NGAY bước trạng thái ban đầu lúc tạo — không chỉ là field sửa
///   sau qua `updateTransaction`.
///
/// Việc `docs/financial-core-v2.md` liệt các field này vào nhóm "không ảnh
/// hưởng balance, sửa trực tiếp không qua reversal" là quy tắc cho
/// `updateTransaction` (sửa 1 giao dịch ĐÃ tồn tại) — khác hoàn toàn với
/// câu hỏi ở đây ("2 request tạo mới có phải cùng 1 request logic không").
/// Không suy ra từ "không ảnh hưởng balance" rằng nên bỏ qua khi so
/// idempotency.
///
/// Chỉ KHÔNG so `id`/`createdAt`/`statusUpdatedAt` — cả 3 là metadata hệ
/// thống tự sinh mỗi lần gọi (`IdGenerator.generate()`/`DateTime.now()`),
/// đổi giá trị ngay cả với đúng 1 request logic lặp lại y hệt.
///
/// **Cập nhật Phase 4.1 (idempotency hardening, KHÔNG phải đổi financial
/// calculation):** thêm `currency` vào so sánh. Audit retry+currency
/// (Phase 4.1) phát hiện: nếu 1 nguồn currency context có thể đổi giá trị
/// giữa 2 lần gọi `AddTransactionUseCase` cho CÙNG 1 `clientTxId` (vd
/// tương lai khi currency trở thành setting mutable ở Layer 2), thiếu điều
/// kiện này sẽ khiến 1 request "VND" và 1 request "USD" bị coi là cùng 1
/// logical transaction — Repository âm thầm trả về bản ghi cũ, bỏ qua
/// currency mới mà không báo lỗi. Currency giờ là 1 phần logical request
/// identity giống hệt `amountMinor`/`categoryId` — khác currency với cùng
/// `clientTxId` phải là [ClientTxIdConflictException], không phải retry
/// hợp lệ. Không đổi `applyEffect`/`buildReversal`/`buildCorrection`/balance
/// rules — đây thuần tuý là mở rộng 1 hàm so sánh identity.
bool isSameLogicalTransaction(Transaction a, Transaction b) {
  return a.type == b.type &&
      a.transferKind == b.transferKind &&
      a.categoryId == b.categoryId &&
      a.sourceKind == b.sourceKind &&
      a.sourceRefId == b.sourceRefId &&
      a.destinationKind == b.destinationKind &&
      a.destinationRefId == b.destinationRefId &&
      a.amountMinor == b.amountMinor &&
      a.currency == b.currency &&
      a.transactionDate == b.transactionDate &&
      a.note == b.note &&
      a.statusId == b.statusId &&
      a.recoveryOfTxId == b.recoveryOfTxId;
}

/// Phase 8.6 — kiểm tra [recovery] (transaction sắp ghi, `recoveryOfTxId ==
/// target.id`) có hợp lệ so với [target] hay không. Hàm THUẦN domain
/// (không đụng DB) — Repository gọi SAU khi tự tra [target] từ DB (giống
/// cách `_assertWontGoNegative` cần đọc balances từ DB trước khi gọi
/// `wouldGoNegative`). KHÔNG động tới `applyEffect`/`typeFromEndpoints` —
/// recovery vẫn là 1 giao dịch INCOME bình thường về mặt tính toán, đây chỉ
/// là ràng buộc QUAN HỆ (mục 7 Phase 8.6).
void validateRecoveryRelation(Transaction recovery, Transaction target) {
  if (recovery.recoveryOfTxId != target.id) {
    // Lỗi lập trình của caller (Repository) — target truyền vào không khớp
    // recoveryOfTxId đang validate. Không phải business exception.
    throw ArgumentError(
      'target.id (${target.id}) không khớp recovery.recoveryOfTxId (${recovery.recoveryOfTxId})',
    );
  }
  if (recovery.recoveryOfTxId == recovery.id) {
    throw InvalidRecoveryTargetException(
      reason: InvalidRecoveryReason.selfLink,
      targetId: target.id,
    );
  }
  if (target.type != TransactionType.expense) {
    throw InvalidRecoveryTargetException(
      reason: InvalidRecoveryReason.targetNotExpense,
      targetId: target.id,
    );
  }
  if (target.recoveryOfTxId != null) {
    throw InvalidRecoveryTargetException(
      reason: InvalidRecoveryReason.targetIsRecovery,
      targetId: target.id,
    );
  }
  if (target.reversedByTxId != null) {
    throw InvalidRecoveryTargetException(
      reason: InvalidRecoveryReason.targetReversed,
      targetId: target.id,
    );
  }
}

/// Tạo bản hoàn tác của [original] — source/destination đảo ngược, cùng
/// `amountMinor`, `reversalOfTxId = original.id` (mục 21). `applyEffect` của
/// bản này tự động triệt tiêu đúng hiệu ứng cũ khi cộng dồn vào balance.
Transaction buildReversal(
  Transaction original, {
  required String newId,
  required String clientTxId,
  required DateTime now,
}) {
  if (original.isReversed) {
    throw AlreadyReversedException(original.id, original.reversedByTxId!);
  }
  final newSourceKind = original.destinationKind;
  final newSourceRefId = original.destinationRefId;
  final newDestinationKind = original.sourceKind;
  final newDestinationRefId = original.sourceRefId;
  return Transaction(
    id: newId,
    type: typeFromEndpoints(newSourceKind, newDestinationKind),
    transferKind: original.transferKind,
    categoryId: original.categoryId,
    sourceKind: newSourceKind,
    sourceRefId: newSourceRefId,
    destinationKind: newDestinationKind,
    destinationRefId: newDestinationRefId,
    amountMinor: original.amountMinor,
    currency: original.currency,
    note: 'Hoàn tác: ${original.note}'.trim(),
    transactionDate: now,
    createdAt: now,
    reversalOfTxId: original.id,
    clientTxId: clientTxId,
  );
}

/// Sửa giao dịch = hoàn tác bản gốc + tạo bản thay thế (`correctsTxId`) —
/// 1 lần sửa tạo ra 3 bản ghi (gốc, hoàn tác, thay thế). Dùng khi
/// `amountMinor` hoặc "người tiêu" (`sourceRefId`/`destinationRefId`) đổi —
/// 2 field này ảnh hưởng balance nên bắt buộc qua reversal ledger (mục 21).
/// `categoryId`/`note`/`transactionDate`/`statusId` không ảnh hưởng balance
/// nên chỉ cần truyền giá trị mới thẳng vào bản thay thế (không cần đổi
/// riêng — nếu không ảnh hưởng balance thì sửa trực tiếp qua
/// `TransactionRepository.updateTransactionDetails` thay vì gọi hàm này).
///
/// Bỏ trống bất kỳ `new*` nào để giữ nguyên giá trị gốc.
({Transaction reversal, Transaction replacement}) buildCorrection(
  Transaction original, {
  required int newAmountMinor,
  String? newCategoryId,
  String? newNote,
  String? newSourceRefId,
  String? newDestinationRefId,
  DateTime? newTransactionDate,
  String? newStatusId,
  required String reversalId,
  required String replacementId,
  required String clientTxId,
  required DateTime now,
}) {
  final reversal = buildReversal(
    original,
    newId: reversalId,
    clientTxId: '$clientTxId-reversal',
    now: now,
  );
  final replacement = Transaction(
    id: replacementId,
    type: original.type,
    transferKind: original.transferKind,
    categoryId: newCategoryId ?? original.categoryId,
    sourceKind: original.sourceKind,
    sourceRefId: newSourceRefId ?? original.sourceRefId,
    destinationKind: original.destinationKind,
    destinationRefId: newDestinationRefId ?? original.destinationRefId,
    amountMinor: newAmountMinor,
    currency: original.currency,
    note: newNote ?? original.note,
    statusId: newStatusId ?? original.statusId,
    statusUpdatedAt: newStatusId != null ? now : original.statusUpdatedAt,
    transactionDate: newTransactionDate ?? original.transactionDate,
    createdAt: now,
    correctsTxId: original.id,
    // Phase 8.6 — quan hệ recovery KHÔNG được mất khi sửa (mục 7F): 1
    // recovery bị correction vẫn phải trỏ về đúng target cũ.
    recoveryOfTxId: original.recoveryOfTxId,
    clientTxId: clientTxId,
  );
  validateNewTransaction(replacement);
  return (reversal: reversal, replacement: replacement);
}
