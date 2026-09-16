import '../entities/pool_kind.dart';
import '../entities/transaction.dart';
import '../entities/transaction_type.dart';

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

/// Tạo bản hoàn tác của [original] — source/destination đảo ngược, cùng
/// `amountMinor`, `reversalOfTxId = original.id` (mục 21). `applyEffect` của
/// bản này tự động triệt tiêu đúng hiệu ứng cũ khi cộng dồn vào balance.
Transaction buildReversal(
  Transaction original, {
  required String newId,
  required String clientTxId,
  required DateTime now,
}) {
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
    clientTxId: clientTxId,
  );
  return (reversal: reversal, replacement: replacement);
}
