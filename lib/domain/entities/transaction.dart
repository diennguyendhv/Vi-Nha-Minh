import 'pool_kind.dart';
import 'transaction_type.dart';
import 'transfer_kind.dart';

/// Entity trung tâm của Financial Core V2 (`docs/financial-core-v2.md` mục
/// 6). Mọi chuyển động tiền đều là 1 `Transaction` với `sourceKind/RefId`
/// (tiền lấy từ đâu) và `destinationKind/RefId` (tiền tới đâu) — 1 hàm
/// `applyEffect` duy nhất xử lý mọi loại, không còn nhánh riêng theo
/// category (xem `domain/engine/financial_engine.dart`).
///
/// `TRANSACTION` là **append-only** cho mọi field ảnh hưởng balance (`type`,
/// `amountMinor`, `sourceKind/RefId`, `destinationKind/RefId`) — sửa/xoá
/// không bao giờ mutate các field này trên 1 bản ghi đã tồn tại, mà tạo bản
/// ghi mới qua `reverseTransaction`/`updateTransaction` (mục 21).
class Transaction {
  const Transaction({
    required this.id,
    required this.type,
    this.transferKind,
    required this.categoryId,
    required this.sourceKind,
    this.sourceRefId,
    required this.destinationKind,
    this.destinationRefId,
    required this.amountMinor,
    this.currency = 'VND',
    this.note = '',
    this.statusId,
    this.statusUpdatedAt,
    required this.transactionDate,
    required this.createdAt,
    this.reversalOfTxId,
    this.correctsTxId,
    this.reversedByTxId,
    this.recoveryOfTxId,
    required this.clientTxId,
    this.version = 1,
  });

  final String id;
  final TransactionType type;

  /// Chỉ khác null khi `type == TransactionType.transfer`.
  final TransferKind? transferKind;

  /// Nhãn để báo cáo/lọc — KHÔNG quyết định dòng tiền (xem `Category`).
  final String categoryId;

  final PoolKind sourceKind;

  /// null khi `sourceKind == PoolKind.external` (tức giao dịch Thu).
  final String? sourceRefId;

  final PoolKind destinationKind;

  /// null khi `destinationKind == PoolKind.external` (tức giao dịch Chi).
  final String? destinationRefId;

  /// Luôn dương — chiều +/- suy ra từ vị trí source/destination
  /// (Invariant 12), không lưu số âm. **Không enforce bằng `assert()` ở
  /// constructor này** (từng có, đã bỏ — assert bị strip ở release build
  /// và không testable, vì test chạy ở chế độ bật assert nên object không
  /// hợp lệ sẽ không bao giờ construct được để test đường ném lỗi). Validate
  /// thật nằm ở `validateNewTransaction` (`domain/engine/financial_engine.dart`),
  /// caller (repository) BẮT BUỘC gọi hàm đó trước khi ghi.
  final int amountMinor;

  final String currency;
  final String note;

  /// FK tới `Status.id`, nullable — KHÔNG bao giờ ảnh hưởng balance (mục
  /// 12, Invariant 9). null nghĩa là chưa chọn (coi như ở bước đầu tiên).
  final String? statusId;
  final DateTime? statusUpdatedAt;

  /// Ngày nghiệp vụ — dùng để rollup theo tháng (khác `createdAt`).
  final DateTime transactionDate;
  final DateTime createdAt;

  /// Transaction này là bản hoàn tác của `txId` nào (mục 21).
  final String? reversalOfTxId;

  /// Transaction này là bản thay thế/sửa cho `txId` nào (mục 21).
  final String? correctsTxId;

  /// Bản gốc bị hoàn tác bởi transaction nào — null = còn hiệu lực. Danh
  /// sách/rollup mặc định phải lọc `reversedByTxId == null`.
  final String? reversedByTxId;

  /// Phase 8.6 — transaction này là 1 khoản THU HỒI/HOÀN TIỀN liên kết tới
  /// `Transaction.id` nào (KHÔNG phải hoàn tác — xem
  /// `docs/financial-core-v2.md` mục 21 vs Phase 8.6): 1 sự kiện tài chính
  /// MỚI (vd bán lại đồ đã mua, hoàn tiền một phần), hiển thị bình thường
  /// (không bị `isVisible()` ẩn), hiệu ứng CỘNG THÊM chứ không triệt tiêu
  /// giao dịch gốc. `applyEffect`/`typeFromEndpoints` hoàn toàn không đọc
  /// field này — chỉ là metadata quan hệ, không tạo nhánh tính toán riêng.
  /// null = transaction gốc (không phải recovery). 1 original → 0..N
  /// recovery (query ngược bằng `recoveryOfTxId == original.id`, không lưu
  /// danh sách recovery IDs trên bản gốc).
  final String? recoveryOfTxId;

  /// Idempotency key chống double-submit (bấm Lưu 2 lần).
  final String clientTxId;

  /// Optimistic concurrency — chưa dùng ở Giai đoạn A (1 thiết bị), có sẵn
  /// schema cho Giai đoạn B (mục 22).
  final int version;

  bool get isReversed => reversedByTxId != null;
  bool get isReversal => reversalOfTxId != null;

  Transaction copyWith({
    String? statusId,
    DateTime? statusUpdatedAt,
    String? reversedByTxId,
    int? version,
  }) {
    return Transaction(
      id: id,
      type: type,
      transferKind: transferKind,
      categoryId: categoryId,
      sourceKind: sourceKind,
      sourceRefId: sourceRefId,
      destinationKind: destinationKind,
      destinationRefId: destinationRefId,
      amountMinor: amountMinor,
      currency: currency,
      note: note,
      statusId: statusId ?? this.statusId,
      statusUpdatedAt: statusUpdatedAt ?? this.statusUpdatedAt,
      transactionDate: transactionDate,
      createdAt: createdAt,
      reversalOfTxId: reversalOfTxId,
      correctsTxId: correctsTxId,
      reversedByTxId: reversedByTxId ?? this.reversedByTxId,
      recoveryOfTxId: recoveryOfTxId,
      clientTxId: clientTxId,
      version: version ?? this.version,
    );
  }
}
