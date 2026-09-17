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

/// Ném ra khi cố xoá 1 loại tài sản tiết kiệm mà ít nhất 1 thành viên vẫn
/// còn số dư khác 0 ở loại đó.
class SavingsAssetTypeNotEmptyException implements Exception {
  const SavingsAssetTypeNotEmptyException(this.assetTypeId);

  final String assetTypeId;

  @override
  String toString() =>
      'SavingsAssetTypeNotEmptyException: loại tài sản $assetTypeId vẫn còn thành viên có số dư khác 0';
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
