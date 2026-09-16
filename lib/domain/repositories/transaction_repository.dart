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
  /// để tránh race condition.
  Future<void> addTransaction(Transaction transaction);

  /// = `deleteTransaction` ở UI. Tạo 1 bản reversal mới (source/destination
  /// đảo ngược), đánh dấu `reversedByTxId` lên bản gốc — KHÔNG xoá cứng.
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
