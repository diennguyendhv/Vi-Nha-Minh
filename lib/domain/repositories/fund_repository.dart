import '../entities/fund.dart';

/// Financial Core V2 (mục 8, F-11): không còn `FundEntry` riêng — lịch sử 1
/// quỹ = lọc `TransactionRepository` theo `sourceRefId`/`destinationRefId`.
/// Repository này chỉ còn quản lý entity `Fund` (tạo/sửa tên-màu/soft-delete).
abstract class FundRepository {
  Stream<List<Fund>> watchFunds();

  Future<void> addFund(Fund fund);

  Future<void> updateFund(Fund fund);

  /// Ném [FundNotEmptyException] nếu `balance != 0` — phải rút hết quỹ
  /// trước bằng 1 giao dịch `TRANSFER(FUND_WITHDRAW)`.
  Future<void> softDeleteFund(String fundId);

  /// Dùng lại quỹ đã ngừng — giữ NGUYÊN id.
  Future<void> reactivateFund(String fundId);

  /// XÓA HẲN quỹ (chỉ khi đã ngừng và không dòng nào — kể cả lịch sử ẩn — còn
  /// chạm quỹ; kiểm tra lại trong 1 DB transaction). Ném [FundNotDeletableException]
  /// nếu không đủ điều kiện. Không quỹ nào là "hệ thống".
  Future<void> deleteFundPermanently(String fundId);
}
