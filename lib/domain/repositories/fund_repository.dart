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
}
