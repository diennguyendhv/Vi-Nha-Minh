import '../entities/transaction.dart';

/// `Transaction` là **append-only** cho mọi field ảnh hưởng balance (mục 21
/// — Phương án B, reversal ledger đầy đủ). Không có `deleteTransaction` tự
/// do: `reverseTransaction`/`updateTransaction` dưới đây là toàn bộ cách
/// hợp lệ để "sửa"/"xoá" một giao dịch.
abstract class TransactionRepository {
  /// Trả về TOÀN BỘ transaction (kể cả bản đã bị hoàn tác/bản reversal nội
  /// bộ) — cần đủ để tính balance đúng (`computeAllPoolBalances` cộng dồn
  /// không lọc gì). Lọc `isVisible`/theo tháng ở tầng use case khi cần danh
  /// sách hiển thị cho người dùng.
  Stream<List<Transaction>> watchTransactions();

  /// Ghi 1 giao dịch mới. Ném [InsufficientBalanceException] nếu sẽ làm
  /// pool nguồn âm (Invariant 7) — validate trong cùng 1 thao tác với ghi
  /// để tránh race condition. Implementation phải gọi
  /// `validateNewTransaction` (Invariant 12/15) trước khi ghi.
  ///
  /// **Hợp đồng idempotency (`docs/financial-core-v2.md` mục 14, hoàn
  /// thiện ở Phase 3) — bắt buộc với mọi implementation:**
  /// [Transaction.clientTxId] là idempotency key.
  /// - Gọi lần đầu với 1 `clientTxId` → tạo đúng 1 bản ghi, trả về chính
  ///   [transaction] vừa ghi.
  /// - Gọi lại CÙNG `clientTxId` với payload giống hệt (so theo
  ///   `isSameLogicalTransaction` ở Financial Engine — các field ảnh hưởng
  ///   nghiệp vụ, không so `id`/`createdAt`/`note`/`transactionDate`/
  ///   `statusId`) → KHÔNG tạo bản ghi thứ hai, trả về bản ghi đã tồn tại
  ///   (idempotent success — không ném exception cho trường hợp bình
  ///   thường này).
  /// - Gọi lại CÙNG `clientTxId` với payload KHÁC → ném
  ///   [ClientTxIdConflictException], KHÔNG overwrite, KHÔNG tạo bản ghi
  ///   mới.
  ///
  /// Enforce thật bằng `UNIQUE(clientTxId)` ở `AppDatabase` (Drift, Phase
  /// 2) là lớp bảo vệ CUỐI CÙNG chống race giữa 2 lần gọi đồng thời —
  /// implementation không được chỉ dựa vào "kiểm tra tồn tại rồi mới ghi"
  /// (check-then-insert) mà bỏ qua việc bắt lỗi unique-constraint thật từ
  /// DB.
  Future<Transaction> addTransaction(Transaction transaction);

  /// Đọc 1 giao dịch theo `id` — trả về `null` nếu không tồn tại (không
  /// ném exception cho "not found", đúng bản chất 1 lookup thông thường).
  Future<Transaction?> getTransactionById(String id);

  /// Đọc 1 giao dịch theo `clientTxId` — dùng cho idempotency check/debug.
  /// Trả về `null` nếu chưa có giao dịch nào dùng `clientTxId` này.
  Future<Transaction?> getTransactionByClientTxId(String clientTxId);

  /// = `deleteTransaction` ở UI. Tạo 1 bản reversal mới (source/destination
  /// đảo ngược), đánh dấu `reversedByTxId` lên bản gốc — KHÔNG xoá cứng.
  /// Ném [AlreadyReversedException] nếu [transactionId] đã có
  /// `reversedByTxId != null` (Invariant 13 — không hoàn tác 2 lần).
  Future<void> reverseTransaction(String transactionId);

  /// Sửa 1 giao dịch — bỏ trống field nào thì giữ nguyên giá trị cũ.
  ///
  /// [amountMinor] và [memberRefId] (người tiêu — map vào `sourceRefId`
  /// nếu là EXPENSE nguồn ví, hoặc `destinationRefId` nếu là INCOME; không
  /// áp dụng khi Chi dùng nguồn Quỹ hoặc khi giao dịch là TRANSFER) là 2
  /// field ẢNH HƯỞNG BALANCE — đổi 1 trong 2 sẽ tự động đi qua reversal
  /// ledger (mục 21, tạo thêm 2 bản ghi). [categoryId]/[note]/
  /// [transactionDate]/[statusId] không ảnh hưởng balance nên được update
  /// thẳng tại chỗ, không tạo bản ghi mới.
  ///
  /// Ném [InsufficientBalanceException] nếu giá trị mới sẽ làm 1 pool âm.
  /// Ném [AlreadyReversedException] nếu [transactionId] không phải bản mới
  /// nhất còn hiệu lực của chuỗi sửa (Invariant 14) — implementation phải tự
  /// tìm đúng bản mới nhất trước khi gọi `buildCorrection`, không tin thẳng
  /// [transactionId] do caller truyền vào là bản mới nhất.
  Future<void> updateTransaction(
    String transactionId, {
    int? amountMinor,
    String? categoryId,
    String? note,
    String? memberRefId,
    DateTime? transactionDate,
    String? statusId,
  });
}
