import '../entities/pool_kind.dart';

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
