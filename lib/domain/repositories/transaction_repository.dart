import '../entities/transaction.dart';

/// `Transaction` là **append-only** cho mọi field ảnh hưởng balance (mục 21
/// — Phương án B, reversal ledger đầy đủ). Không có `updateTransaction`
/// hay `deleteTransaction` tự do nữa: 3 method dưới đây là toàn bộ cách hợp
/// lệ để "sửa"/"xoá" một giao dịch, khớp đúng phạm vi UI đã chốt (chỉ sửa
/// `amountMinor` và `statusId`).
abstract class TransactionRepository {
  /// Trả về TOÀN BỘ transaction (kể cả bản đã bị hoàn tác/bản reversal nội
  /// bộ) — cần đủ để tính balance đúng (`computeAllPoolBalances` cộng dồn
  /// không lọc gì). Lọc `isVisible`/theo tháng ở tầng use case khi cần danh
  /// sách hiển thị cho người dùng.
  Stream<List<Transaction>> watchTransactions();

  /// Ghi 1 giao dịch mới. Ném [InsufficientBalanceException] nếu sẽ làm
  /// pool nguồn âm (Invariant 7) — validate trong cùng 1 thao tác với ghi
  /// để tránh race condition.
  Future<void> addTransaction(Transaction transaction);

  /// = `deleteTransaction` ở UI. Tạo 1 bản reversal mới (source/destination
  /// đảo ngược), đánh dấu `reversedByTxId` lên bản gốc — KHÔNG xoá cứng.
  Future<void> reverseTransaction(String transactionId);

  /// Sửa số tiền: hoàn tác bản gốc + tạo bản thay thế (`correctsTxId`).
  /// Ném [InsufficientBalanceException] nếu số tiền mới sẽ làm pool âm.
  Future<void> correctTransactionAmount(String transactionId, int newAmountMinor);

  /// Đổi trạng thái — update thẳng field, KHÔNG qua reversal (status không
  /// bao giờ ảnh hưởng balance, Invariant 9).
  Future<void> updateTransactionStatus(String transactionId, String? statusId);
}
