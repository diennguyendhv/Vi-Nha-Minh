import '../entities/pool_kind.dart';
import '../entities/transaction.dart';

/// Ném ra khi 1 giao dịch sắp ghi sẽ làm 1 pool (Quỹ/Tiết kiệm/Ví thành
/// viên) âm — Invariant 7, "không có ngoại lệ nào được phép âm". Repository
/// kiểm tra và ném lỗi này TRƯỚC khi ghi, để UI hiển thị đúng thông điệp
/// thay vì lỗi DB chung chung.
class InsufficientBalanceException implements Exception {
  const InsufficientBalanceException({
    required this.poolKind,
    required this.refId,
    required this.currentBalance,
    required this.requestedAmount,
  });

  final PoolKind poolKind;
  final String? refId;
  final int currentBalance;
  final int requestedAmount;

  @override
  String toString() =>
      'InsufficientBalanceException: pool $poolKind($refId) chỉ còn '
      '$currentBalance, không đủ trừ $requestedAmount';
}

/// Ném ra khi cố xoá 1 Quỹ đang có `balance != 0` (mục 8 — phải rút hết
/// quỹ trước bằng `TRANSFER(FUND_WITHDRAW)`).
class FundNotEmptyException implements Exception {
  const FundNotEmptyException(this.fundId, this.balance);

  final String fundId;
  final int balance;

  @override
  String toString() =>
      'FundNotEmptyException: quỹ $fundId còn $balance đ, phải rút hết trước khi xoá';
}

/// Phase 8.7 — ném ra khi cố soft-delete 1 `Counterparty` mà còn `Obligation`
/// đang mở (outstanding > 0) tham chiếu tới. Cùng tinh thần
/// `FundNotEmptyException` — phải tất toán hết trước khi xoá.
class CounterpartyHasOpenObligationsException implements Exception {
  const CounterpartyHasOpenObligationsException(this.counterpartyId);

  final String counterpartyId;

  @override
  String toString() =>
      'CounterpartyHasOpenObligationsException: counterpartyId=$counterpartyId còn khoản vay đang mở';
}

/// Ném ra khi cố xoá 1 loại tài sản tiết kiệm mà ít nhất 1 thành viên vẫn
/// còn số dư khác 0 ở loại đó.
class SavingsAssetTypeNotEmptyException implements Exception {
  const SavingsAssetTypeNotEmptyException(this.assetTypeId);

  final String assetTypeId;

  @override
  String toString() =>
      'SavingsAssetTypeNotEmptyException: loại tài sản $assetTypeId vẫn còn thành viên có số dư khác 0';
}

/// Ném ra khi cố xoá hẳn 1 danh mục không đủ điều kiện: còn đang dùng, là danh
/// mục hệ thống, đã từng có giao dịch (kể cả giao dịch đã hoàn tác — vẫn là 1
/// dòng trong sổ), hoặc danh mục khác đang trỏ tới nó. Danh mục như vậy chỉ
/// được ngừng sử dụng, không được xoá cứng.
class CategoryNotDeletableException implements Exception {
  const CategoryNotDeletableException(this.categoryId);

  final String categoryId;

  @override
  String toString() =>
      'CategoryNotDeletableException: danh mục $categoryId không đủ điều kiện xoá hẳn';
}

/// Tương tự [CategoryNotDeletableException] cho 1 bước trạng thái.
class StatusNotDeletableException implements Exception {
  const StatusNotDeletableException(this.statusId);

  final String statusId;

  @override
  String toString() =>
      'StatusNotDeletableException: trạng thái $statusId không đủ điều kiện xoá hẳn';
}

/// Ném ra khi 1 giao dịch tiết kiệm (`savingsTopup`/`savingsWithdraw`/
/// `savingsConvert`) không cùng 1 thành viên hoặc sai hình dạng nguồn/đích —
/// vd Vợ khả dụng → Tiết kiệm Chồng. Chặn ở tầng ghi, không chỉ dựa vào UI.
class SavingsMemberMismatchException implements Exception {
  const SavingsMemberMismatchException(this.transactionKind);

  final String transactionKind;

  @override
  String toString() =>
      'SavingsMemberMismatchException: giao dịch $transactionKind không cùng thành viên / sai nguồn-đích';
}

/// Ném ra khi HOÀN TÁC 1 giao dịch sẽ làm 1 pool âm (vd hoàn tác lần nạp tiết
/// kiệm sau khi 1 phần đã được phân bổ/rút). Không ghi gì, không cascade.
class ReversalWouldOverdrawException implements Exception {
  const ReversalWouldOverdrawException(this.poolKind, this.refId);

  final PoolKind poolKind;
  final String? refId;

  @override
  String toString() =>
      'ReversalWouldOverdrawException: hoàn tác sẽ làm pool $poolKind($refId) âm';
}

/// Ném ra khi cố xoá hẳn 1 loại tài sản tiết kiệm không đủ điều kiện (còn
/// đang dùng, còn số dư, đã từng có giao dịch, hoặc là tài sản hệ thống).
/// Quỹ chưa thể xóa hẳn: còn đang sử dụng, còn tiền hoặc còn giao dịch chạm quỹ.
class FundNotDeletableException implements Exception {
  const FundNotDeletableException(this.fundId);

  final String fundId;

  @override
  String toString() =>
      'FundNotDeletableException: quỹ $fundId không đủ điều kiện xóa hẳn';
}

class SavingsAssetTypeNotDeletableException implements Exception {
  const SavingsAssetTypeNotDeletableException(this.assetTypeId);

  final String assetTypeId;

  @override
  String toString() =>
      'SavingsAssetTypeNotDeletableException: loại tài sản $assetTypeId không đủ điều kiện xoá hẳn';
}

/// Ném ra khi cố đưa tiền VÀO 1 loại tài sản đã ngừng sử dụng (nạp/chuyển
/// đến). Loại đã ngừng chỉ cho rút hoặc chuyển ra.
class SavingsAssetInactiveException implements Exception {
  const SavingsAssetInactiveException(this.assetTypeId);

  final String assetTypeId;

  @override
  String toString() =>
      'SavingsAssetInactiveException: loại tài sản $assetTypeId đã ngừng, không nhận thêm tiền';
}

/// Ném ra khi XOÁ THẬT 1 giao dịch sẽ làm 1 pool âm (vd xoá lần nạp tiết kiệm
/// khi 1 phần đã phân bổ / xoá khoản thu khi tiền đã chi). Không xoá gì, không
/// cascade — người dùng phải xử lý giao dịch phát sinh sau trước.
class DeleteWouldOverdrawException implements Exception {
  const DeleteWouldOverdrawException(
    this.poolKind,
    this.refId, {
    this.blockingTransactionIds = const [],
  });

  final PoolKind poolKind;
  final String? refId;

  /// Các giao dịch (đang hiệu lực) đã dùng số tiền này — để UI cho người dùng mở
  /// và xử lý trước. Rỗng nếu không xác định được.
  final List<String> blockingTransactionIds;

  @override
  String toString() =>
      'DeleteWouldOverdrawException: xoá sẽ làm pool $poolKind($refId) âm';
}

/// Ném ra khi SỬA 1 giao dịch (thay dòng cũ bằng dòng mới) sẽ làm 1 pool âm —
/// giao dịch cũ giữ nguyên, không ghi gì.
class ChangeWouldOverdrawException implements Exception {
  const ChangeWouldOverdrawException(
    this.poolKind,
    this.refId, {
    this.blockingTransactionIds = const [],
  });

  final PoolKind poolKind;
  final String? refId;
  final List<String> blockingTransactionIds;

  @override
  String toString() =>
      'ChangeWouldOverdrawException: sửa sẽ làm pool $poolKind($refId) âm';
}

/// Lý do 1 giao dịch (hoặc họ giao dịch của nó) chưa được xoá thật.
enum DeleteBlockReason {
  /// Thuộc / gắn với khoản Vay & Cho vay (obligation, tất toán).
  linkedLoan,

  /// Là giao dịch hoàn tiền/thu hồi, hoặc có giao dịch hoàn tiền/thu hồi trỏ tới.
  linkedRecovery,
}

class TransactionDeleteBlockedException implements Exception {
  const TransactionDeleteBlockedException(this.reason);

  final DeleteBlockReason reason;

  @override
  String toString() => 'TransactionDeleteBlockedException: $reason';
}

/// Ném ra khi 1 giao dịch dùng trạng thái KHÔNG thuộc danh mục của nó
/// (`status.categoryId != transaction.categoryId`).
class InvalidStatusForCategoryException implements Exception {
  const InvalidStatusForCategoryException(this.statusId, this.categoryId);

  final String statusId;
  final String categoryId;

  @override
  String toString() =>
      'InvalidStatusForCategoryException: trạng thái $statusId không thuộc danh mục $categoryId';
}

/// Ném ra khi `amountMinor` không hợp lệ — Invariant 12
/// (`docs/financial-core-v2.md` mục 18): luôn phải dương, không chấp nhận 0
/// hay số âm. Đây là validate THẬT ở tầng Financial Engine (không bị strip
/// ở release build như `assert()` trong constructor `Transaction`).
class InvalidAmountException implements Exception {
  const InvalidAmountException(this.amountMinor);

  final int amountMinor;

  @override
  String toString() =>
      'InvalidAmountException: amountMinor phải dương, nhận được $amountMinor';
}

/// Ném ra khi `sourceKind`/`sourceRefId` và `destinationKind`/
/// `destinationRefId` của 1 giao dịch trỏ tới CÙNG 1 pool — Invariant 15.
/// Với INCOME/EXPENSE hợp lệ, điều này không bao giờ xảy ra (1 đầu luôn là
/// `EXTERNAL`, đầu kia không) — invariant này thực chất chỉ có thể vi phạm
/// ở TRANSFER (vd chọn người nhận = người gửi, hoặc chuyển đổi tiết kiệm
/// sang chính loại đang có).
class SameSourceDestinationException implements Exception {
  const SameSourceDestinationException(this.poolKind, this.refId);

  final PoolKind poolKind;
  final String? refId;

  @override
  String toString() =>
      'SameSourceDestinationException: source và destination cùng là pool $poolKind($refId)';
}

/// Ném ra khi cố `reverseTransaction` hoặc sửa (`updateTransaction` với field
/// ảnh hưởng balance) trên 1 giao dịch đã có `reversedByTxId != null`.
/// Gộp chung 2 invariant vì cùng 1 điều kiện bảo vệ:
/// - Invariant 13: không hoàn tác 2 lần trên cùng 1 giao dịch.
/// - Invariant 14: không thao tác trên 1 bản ghi đã lỗi thời trong chuỗi
///   sửa — bất kỳ bản ghi nào không phải mới nhất trong chuỗi đều đã có
///   `reversedByTxId` được set (mục 21), nên kiểm tra 1 điều kiện này là đủ
///   cho cả 2 invariant, không cần dò lại toàn bộ chuỗi `correctsTxId`.
class AlreadyReversedException implements Exception {
  const AlreadyReversedException(this.transactionId, this.reversedByTxId);

  final String transactionId;
  final String reversedByTxId;

  @override
  String toString() =>
      'AlreadyReversedException: giao dịch $transactionId đã bị hoàn tác/thay '
      'thế bởi $reversedByTxId — không thể hoàn tác hoặc sửa lần nữa, thao '
      'tác trên bản thay thế mới nhất thay vì bản này';
}

/// Hợp đồng idempotency cho `clientTxId` (`docs/financial-core-v2.md` mục
/// 14): request đầu tiên với 1 `clientTxId` tạo đúng 1 transaction; request
/// lặp lại CÙNG `clientTxId` không được tạo bản ghi thứ hai.
///
/// **Cập nhật ở Phase 3 (Repository + Idempotency):** khi request lặp lại
/// có payload GIỐNG bản gốc (cùng field ảnh hưởng nghiệp vụ — xem
/// `isSameLogicalTransaction`), `TransactionRepository.addTransaction`
/// KHÔNG ném exception này — trả về thẳng transaction đã tồn tại, coi như
/// thành công (đúng tinh thần "idempotent success", không bắt caller phải
/// bắt riêng 1 exception cho trường hợp bình thường). Exception này giữ lại
/// cho debug/trường hợp cần phân biệt rõ "đây là request lặp lại" — không
/// còn là đường đi mặc định. Xem [ClientTxIdConflictException] cho trường
/// hợp payload KHÁC (mới thêm ở Phase 3 — đây mới là lỗi thật cần xử lý).
class DuplicateClientTxIdException implements Exception {
  const DuplicateClientTxIdException(this.clientTxId);

  final String clientTxId;

  @override
  String toString() =>
      'DuplicateClientTxIdException: đã tồn tại giao dịch với clientTxId=$clientTxId';
}

/// Ném ra khi retry cùng `clientTxId` nhưng payload (các field ảnh hưởng
/// nghiệp vụ — xem `isSameLogicalTransaction` ở Financial Engine) KHÁC với
/// bản đã ghi trước đó — Phase 3 mục 6. Đây là bảo vệ chống caller tái sử
/// dụng nhầm `clientTxId` cho 1 giao dịch khác hẳn — KHÔNG BAO GIỜ overwrite
/// bản ghi cũ, KHÔNG tạo bản ghi mới, chỉ báo lỗi rõ ràng cho caller.
class ClientTxIdConflictException implements Exception {
  const ClientTxIdConflictException({
    required this.clientTxId,
    required this.existing,
    required this.attempted,
  });

  final String clientTxId;

  /// Giao dịch đã tồn tại trong DB (bản ghi đầu tiên, không đổi).
  final Transaction existing;

  /// Payload của request gây conflict — KHÔNG được persist.
  final Transaction attempted;

  @override
  String toString() =>
      'ClientTxIdConflictException: clientTxId=$clientTxId đã tồn tại với '
      'payload khác (existing amount=${existing.amountMinor}, '
      'attempted amount=${attempted.amountMinor}) — không overwrite, không '
      'tạo bản ghi mới';
}

/// Ném ra khi `reverseTransaction`/`updateTransaction` được gọi với 1
/// `transactionId` không tồn tại trong DB — Phase 3.1 hardening: trước đây
/// `LocalTransactionRepository` dùng `getSingle()`/`firstWhere()` cho
/// trường hợp này, để lộ `StateError` (Dart core, không mô tả rõ nguyên
/// nhân) qua ranh giới `TransactionRepository`.
///
/// **`getTransactionById`/`getTransactionByClientTxId` KHÔNG đổi** — vẫn
/// trả `null` khi không tìm thấy, đúng bản chất 1 lookup thông thường.
/// Chỉ 2 thao tác GHI (`reverseTransaction`/`updateTransaction`) mới cần
/// báo lỗi rõ ràng khi target không tồn tại, vì đó là điều kiện tiên quyết
/// bắt buộc để thao tác hợp lệ, không phải 1 kết quả "có thể có hoặc
/// không" như query.
class TransactionNotFoundException implements Exception {
  const TransactionNotFoundException(this.transactionId);

  final String transactionId;

  @override
  String toString() =>
      'TransactionNotFoundException: không tìm thấy giao dịch $transactionId';
}

/// Phân loại tối thiểu cho [PersistenceConstraintException] (Phase 3.1 mục
/// 5 — "không tạo 15 loại exception cho mọi SQLite result code", chỉ đủ để
/// Application layer phân biệt 3 nhóm constraint có ý nghĩa khác nhau).
enum PersistenceConstraintKind {
  /// FK trỏ tới bản ghi không tồn tại (vd `categoryId`/`statusId` sai).
  foreignKey,

  /// Vi phạm ràng buộc duy nhất KHÔNG PHẢI `clientTxId` (đã có đường xử lý
  /// idempotency riêng — xem [ClientTxIdConflictException]). Case này hiếm
  /// gặp trong thực tế (vd trùng `id` do `IdGenerator` đụng độ).
  uniqueViolation,

  /// Vi phạm ràng buộc dữ liệu khác đã biết trước (CHECK/NOT NULL...) mà
  /// không rơi vào 2 nhóm trên.
  other,
}

/// Ném ra khi 1 thao tác ghi vi phạm ràng buộc dữ liệu (FK/unique/khác)
/// **không phải** `clientTxId` — Repository dịch từ `SqliteException` thô
/// sang exception này (Phase 3.1 mục 4/5) để Application/Use Case layer
/// không cần biết `sqlite3`/`SqliteException`/Drift internals qua boundary
/// của `TransactionRepository`. [cause] giữ lại exception gốc để debug,
/// KHÔNG hiện trực tiếp cho người dùng.
class PersistenceConstraintException implements Exception {
  const PersistenceConstraintException({
    required this.kind,
    required this.message,
    this.cause,
  });

  final PersistenceConstraintKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => 'PersistenceConstraintException($kind): $message';
}

/// Lỗi lưu trữ không mong đợi, không thuộc bất kỳ nhóm nào ở
/// [PersistenceConstraintKind] (Phase 3.1 mục 5 — "unexpected persistence
/// failure"). [cause] giữ lại exception gốc để debug.
class PersistenceException implements Exception {
  const PersistenceException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'PersistenceException: $message (cause: $cause)';
}

/// Phase 8.6 — lý do 1 giao dịch `recoveryOfTxId` bị từ chối. Validate ở
/// `validateRecoveryRelation` (Financial Engine), Repository gọi trước khi
/// ghi (giống cách `_assertWontGoNegative` cần đọc DB nên nằm ở Repository,
/// không phải `validateNewTransaction` thuần).
enum InvalidRecoveryReason {
  /// Target không phải `TransactionType.expense` — minimum-safe rule khớp
  /// 100% use case đã nêu (mua đồ/ứng tiền hộ), không tự mở rộng thêm.
  targetNotExpense,

  /// Target CHÍNH NÓ đã là 1 recovery (`target.recoveryOfTxId != null`) —
  /// cấm recovery chain, recovery phải trỏ THẲNG về giao dịch gốc.
  targetIsRecovery,

  /// Target đã bị hoàn tác (`target.reversedByTxId != null`) — hiệu ứng gốc
  /// coi như chưa từng xảy ra, thu hồi 1 khoản chi "không tồn tại" là vô
  /// nghĩa.
  targetReversed,

  /// `recoveryOfTxId == id` của chính giao dịch đang tạo.
  selfLink,

  /// `recoveryOfTxId` trỏ tới 1 id không tồn tại trong DB.
  targetNotFound,
}

class InvalidRecoveryTargetException implements Exception {
  const InvalidRecoveryTargetException({
    required this.reason,
    required this.targetId,
  });

  final InvalidRecoveryReason reason;
  final String targetId;

  @override
  String toString() =>
      'InvalidRecoveryTargetException($reason): target=$targetId';
}

/// Phase 8.7 — ném ra khi không tìm thấy giao dịch TẠO khoản vay (hình dạng
/// đúng theo `direction`, còn `isVisible`) cho 1 `obligationId` — cần thiết
/// trước khi tất toán/tính outstanding (không có "principal gốc" thì không
/// có gì để tất toán).
class ObligationCreationNotFoundException implements Exception {
  const ObligationCreationNotFoundException(this.obligationId);

  final String obligationId;

  @override
  String toString() =>
      'ObligationCreationNotFoundException: không tìm thấy giao dịch tạo khoản vay cho obligationId=$obligationId';
}

/// Ném ra khi cố hoàn tác/sửa giao dịch TẠO khoản vay trong khi đã tồn tại
/// >= 1 lần tất toán (settlement) còn hiệu lực — audit Phase 8.7 mục L/M,
/// cùng tinh thần `FundNotEmptyException` ("tất toán hết trước khi hoàn
/// tác/sửa khoản vay gốc", không cascade-xoá lịch sử tất toán).
class ObligationHasSettlementsException implements Exception {
  const ObligationHasSettlementsException(this.obligationId);

  final String obligationId;

  @override
  String toString() =>
      'ObligationHasSettlementsException: obligationId=$obligationId đã có tất toán, phải hoàn tác hết tất toán trước';
}

/// Ném ra khi cố sửa (correction) 1 lần tất toán KHÔNG PHẢI lần tất toán
/// MỚI NHẤT còn hiệu lực của 1 khoản vay — decision đã approve Phase 8.7
/// (audit "atomicity + idempotency" mục M): chỉ cho sửa lần tất toán gần
/// nhất, tránh phải recompute lại phân bổ gốc/lãi của các lần tất toán sau
/// nó.
class NotLatestSettlementException implements Exception {
  const NotLatestSettlementException(this.settlementLegId, this.obligationId);

  final String settlementLegId;
  final String obligationId;

  @override
  String toString() =>
      'NotLatestSettlementException: $settlementLegId không phải tất toán mới nhất của obligationId=$obligationId';
}

/// Phase 8.7 — phát hiện "half-settlement": 1 trong 2 leg (principal/lãi)
/// của cùng 1 lần tất toán tồn tại trong DB nhưng leg còn lại thì không.
/// Theo thiết kế, `settleObligation` ghi cả 2 leg atomic trong 1
/// `_db.transaction()` nên trạng thái này KHÔNG THỂ xảy ra qua đường ghi
/// bình thường — nếu phát hiện, coi là dữ liệu hỏng (audit "atomicity +
/// idempotency" mục 4/D), KHÔNG tự ý ghi nốt leg còn thiếu (outstanding có
/// thể đã đổi do giao dịch khác chen giữa), chỉ báo lỗi rõ ràng.
class SettlementIntegrityException implements Exception {
  const SettlementIntegrityException({
    required this.obligationId,
    required this.clientTxId,
    required this.missingLeg,
  });

  final String obligationId;
  final String clientTxId;

  /// 'principal' hoặc 'interest' — leg nào đang bị thiếu.
  final String missingLeg;

  @override
  String toString() =>
      'SettlementIntegrityException: obligationId=$obligationId, '
      'clientTxId=$clientTxId thiếu leg "$missingLeg" — dữ liệu nửa vời, '
      'không tự sửa';
}
