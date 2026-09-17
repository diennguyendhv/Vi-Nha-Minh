import '../engine/financial_engine.dart';
import '../entities/transaction.dart';

/// Phase 8.6 — tổng hợp thu hồi/hoàn tiền gắn với 1 giao dịch Chi gốc.
/// Thuần Dart, không phụ thuộc Flutter — dùng cho Transaction Detail.
class RecoverySummary {
  const RecoverySummary({required this.recoveries, required this.totalRecovered, required this.netCost});

  /// Các giao dịch recovery ĐANG hiệu lực (`isVisible`), sắp theo
  /// `transactionDate` giảm dần — recovery đã bị hoàn tác không xuất hiện
  /// ở đây (mục 7E).
  final List<Transaction> recoveries;

  /// Tổng đã thu hồi — chỉ cộng recovery đang hiệu lực.
  final int totalRecovered;

  /// `original.amountMinor - totalRecovered` — derived metric HIỂN THỊ,
  /// KHÔNG mutate `amountMinor` của giao dịch gốc (mục 5). Có thể ÂM nếu
  /// thu hồi vượt quá chi phí gốc (mục 7D — không tự cấm, đây có thể là lãi
  /// thật).
  final int netCost;
}

/// [original] phải là giao dịch Chi đã xác nhận hợp lệ làm target recovery
/// (không tự validate lại ở đây — validate thuộc `validateRecoveryRelation`,
/// chạy lúc GHI, không phải lúc ĐỌC/hiển thị).
RecoverySummary computeRecoverySummary(
  Transaction original,
  List<Transaction> allTransactions,
) {
  final recoveries = allTransactions
      .where((t) => t.recoveryOfTxId == original.id && isVisible(t))
      .toList()
    ..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
  final totalRecovered = recoveries.fold<int>(0, (s, t) => s + t.amountMinor);
  return RecoverySummary(
    recoveries: recoveries,
    totalRecovered: totalRecovered,
    netCost: original.amountMinor - totalRecovered,
  );
}
