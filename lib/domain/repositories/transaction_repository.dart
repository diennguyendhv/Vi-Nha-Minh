import '../entities/obligation_direction.dart';
import '../entities/transaction.dart';

/// Mô hình như bảng tính: dòng còn tồn tại thì còn ảnh hưởng. "Xóa giao dịch" =
/// [deleteTransaction] (xoá thật); "Sửa giao dịch" = [updateTransaction] (thay dòng
/// cũ bằng dòng mới, atomic). `reverseTransaction`/reversal ledger chỉ còn cho
/// nghiệp vụ Vay và dữ liệu cũ.
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

  /// XOÁ THẬT giao dịch (hành động người dùng "Xóa giao dịch"): xoá vật lý dòng
  /// đó cùng toàn bộ "họ giao dịch" của nó (gốc + hoàn tác + bản thay thế…) trong
  /// 1 DB transaction; số dư/báo cáo tự tính lại từ các giao dịch còn lại. KHÔNG
  /// tạo giao dịch bù trừ. Ném:
  /// - [TransactionNotFoundException] nếu không tồn tại;
  /// - [TransactionDeleteBlockedException] nếu dính Vay & Cho vay / hoàn tiền-thu hồi;
  /// - [DeleteWouldOverdrawException] nếu xoá làm bất kỳ pool nào âm.
  /// Không có dòng nào bị đổi nếu ném lỗi. Nhận id của BẤT KỲ dòng nào trong họ
  /// (kể cả dòng ẩn của cơ chế hoàn tác cũ) — để dọn lịch sử ẩn khi người dùng
  /// chủ động chọn.
  Future<void> deleteTransaction(String transactionId);

  /// Dọn LỊCH SỬ ẨN đã "xóa" theo cơ chế cũ (gốc + hoàn tác, không còn dòng đang
  /// hiệu lực) mà còn dùng [categoryId] — do người dùng chủ động chọn. Xóa cả họ
  /// trong 1 DB transaction, cùng kiểm tra an toàn như [deleteTransaction].
  /// Trả về số dòng đã xóa (0 nếu không có gì để dọn).
  Future<int> purgeDeletedHistory(String categoryId);

  /// Như [purgeDeletedHistory] nhưng cho lịch sử ẩn còn dùng trạng thái [statusId].
  Future<int> purgeDeletedHistoryForStatus(String statusId);

  /// Sửa 1 giao dịch — bỏ trống field nào thì giữ nguyên giá trị cũ.
  ///
  /// [amountMinor] và [memberRefId] (người tiêu — map vào `sourceRefId` nếu là
  /// EXPENSE nguồn ví, hoặc `destinationRefId` nếu là INCOME; không áp dụng khi
  /// Chi dùng nguồn Quỹ hoặc TRANSFER) ảnh hưởng số dư: đổi 1 trong 2 sẽ THAY dòng
  /// cũ bằng 1 dòng MỚI (id + clientTxId mới) trong cùng 1 DB transaction — xoá
  /// cả họ giao dịch cũ (nếu có) rồi ghi dòng mới; KHÔNG tạo hoàn tác/bản thay
  /// thế, không để lại lịch sử ẩn. [categoryId]/[note]/[transactionDate]/
  /// [statusId] không ảnh hưởng số dư nên update thẳng tại chỗ.
  ///
  /// Đổi danh mục mà không chỉ định trạng thái hợp lệ → trạng thái cũ bị xoá
  /// (Invariant `status.categoryId == transaction.categoryId`).
  ///
  /// Ném [InsufficientBalanceException] nếu pool nguồn không đủ tiền,
  /// [ChangeWouldOverdrawException] (kèm giao dịch đang cản) nếu sổ sau khi thay
  /// làm pool nào âm, [TransactionDeleteBlockedException] nếu dính Vay/Hoàn tiền,
  /// [InvalidStatusForCategoryException] nếu trạng thái không thuộc danh mục.
  /// Lỗi ở bất kỳ bước nào → rollback, giao dịch cũ nguyên vẹn.
  Future<void> updateTransaction(
    String transactionId, {
    int? amountMinor,
    String? categoryId,
    String? note,
    String? memberRefId,
    DateTime? transactionDate,
    String? statusId,
  });

  /// Phase 8.7 — tất toán (thu hồi Receivable / trả nợ Payable) 1
  /// `Obligation`. Tự tính outstanding hiện tại và phân bổ "trừ gốc trước,
  /// dư ra là lãi" (principal-first, đã approve) — Repository ghi 1 dòng
  /// (không lãi) hoặc 2 dòng ATOMIC trong 1 DB transaction (Receivable có
  /// lãi — xem `docs/financial-core-v2.md` audit "atomicity + idempotency"
  /// Phase 8.7). Payable KHÔNG BAO GIỜ trả về `interest` (luôn gộp 1 dòng —
  /// xem `buildObligationSettlementLegs`).
  ///
  /// **Idempotency:** [principalId]/[principalClientTxId]/[interestId]/
  /// [interestClientTxId] do CALLER (Application, qua
  /// `SettleObligationCommand`) sinh 1 lần và giữ nguyên qua các lần gọi lại
  /// (retry) — cùng contract `clientTxId` như `addTransaction`. Ném
  /// [SettlementIntegrityException] nếu phát hiện half-state (1 trong 2 leg
  /// tồn tại, leg kia thì không) — KHÔNG tự vá.
  ///
  /// Ném [ObligationCreationNotFoundException] nếu chưa có giao dịch TẠO
  /// khoản vay. Ném [InsufficientBalanceException] nếu Receivable-principal
  /// sẽ làm pool `receivable` âm (không nên xảy ra vì `principalPortion`
  /// luôn `<= outstanding`, nhưng vẫn validate qua đúng cơ chế chung).
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
  });

  /// Hoàn tác TOÀN BỘ 1 lần tất toán (1 hoặc 2 leg, xác định qua
  /// `settlementGroupId`) — ATOMIC, cùng 1 hành động người dùng ("Undo tất
  /// toán"), không để lộ 2 nút "Xoá giao dịch" riêng cho 2 leg kỹ thuật.
  /// [anyLegTransactionId] có thể là id của leg principal HOẶC leg interest
  /// — Repository tự resolve group. Ném [AlreadyReversedException] nếu bất
  /// kỳ leg nào đã bị hoàn tác.
  Future<void> reverseObligationSettlement(String anyLegTransactionId);

  /// Sửa 1 lần tất toán — chiến lược "hoàn tác cả group cũ rồi tạo lại từ
  /// đầu với số tiền mới" (đã approve), ATOMIC trong 1 DB transaction. Tự
  /// chuyển đổi đúng số leg (1↔2) theo số tiền MỚI so với outstanding vừa
  /// khôi phục — không cần code riêng cho từng chiều chuyển đổi.
  ///
  /// Ném [NotLatestSettlementException] nếu [anyLegTransactionId] không
  /// thuộc lần tất toán MỚI NHẤT còn hiệu lực của khoản vay (chính sách đã
  /// approve — chỉ sửa được lần gần nhất).
  Future<({Transaction principal, Transaction? interest})> correctObligationSettlement(
    String anyLegTransactionId, {
    required int newAmountMinor,
    required String categoryId,
    required String interestCategoryId,
    required String newPrincipalId,
    required String newPrincipalClientTxId,
    required String newInterestId,
    required String newInterestClientTxId,
  });
}
