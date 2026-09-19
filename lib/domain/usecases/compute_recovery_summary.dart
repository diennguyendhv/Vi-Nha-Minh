import '../engine/financial_engine.dart';
import '../entities/transaction.dart';

/// Phase 8.6 — tổng hợp thu hồi/hoàn tiền gắn với 1 giao dịch Chi gốc.
/// Thuần Dart, không phụ thuộc Flutter — dùng cho Transaction Detail.
///
/// Phase 8.6B (mục 17 thảo luận resale-profit): 1 khoản recovery có thể vượt
/// quá chi phí gốc (bán lại có lãi) — phần vượt là LỢI NHUẬN thật
/// ([totalProfit]), không phải "chi phí âm". [netCost] không bao giờ âm nữa.
class RecoverySummary {
  const RecoverySummary({
    required this.recoveries,
    required this.totalRecovered,
    required this.totalProfit,
    required this.netCost,
  });

  /// Các giao dịch recovery ĐANG hiệu lực (`isVisible`), sắp theo
  /// `transactionDate` giảm dần — recovery đã bị hoàn tác không xuất hiện
  /// ở đây (mục 7E).
  final List<Transaction> recoveries;

  /// Tổng tiền mặt đã nhận về từ mọi recovery đang hiệu lực (proceeds thật,
  /// KHÔNG trừ phần lợi nhuận) — chỉ cộng recovery đang hiệu lực.
  final int totalRecovered;

  /// Phần CHÊNH LỆCH vượt quá chi phí gốc — lợi nhuận/thu nhập thực
  /// (`max(0, totalRecovered - original.amountMinor)`), KHÔNG được tính lẫn
  /// vào [netCost]/"chi phí âm". 0 khi bán lỗ hoặc hoà vốn.
  final int totalProfit;

  /// Phần chi phí gốc CHƯA được thu hồi — derived metric HIỂN THỊ, KHÔNG
  /// mutate `amountMinor` của giao dịch gốc (mục 5). Luôn `>= 0`
  /// (`max(0, original.amountMinor - totalRecovered)`) — phần vượt quá chi
  /// phí gốc không còn được coi là "chi phí âm" nữa mà tách hẳn sang
  /// [totalProfit] (Phase 8.6B).
  final int netCost;

  /// Phần trong [totalRecovered] thực sự bù đắp chi phí gốc —
  /// `totalRecovered - totalProfit` (= `original.amountMinor - netCost`).
  /// Tiện dụng cho hiển thị "Đã thu hồi (chi phí)" tách khỏi lợi nhuận.
  int get recoveredCost => totalRecovered - totalProfit;
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
  final recoveredCost = totalRecovered < original.amountMinor
      ? totalRecovered
      : original.amountMinor;
  return RecoverySummary(
    recoveries: recoveries,
    totalRecovered: totalRecovered,
    totalProfit: totalRecovered - recoveredCost,
    netCost: original.amountMinor - recoveredCost,
  );
}

/// Phase 8.6B — với MỖI giao dịch recovery đang hiệu lực trong toàn bộ
/// ledger, tính phần LỢI NHUẬN (report được như Income) của riêng giao dịch
/// đó, dùng cho `computeThreeTotals`/`computeFinancialSummary` (attribute lợi
/// nhuận đúng vào tháng của recovery đó, không phải tháng của giao dịch Chi
/// gốc).
///
/// Thuật toán "remaining cost basis" (mục "IMPORTANT — REMAINING COST
/// BASIS"): với mỗi original, đi qua CÁC recovery đang hiệu lực theo thứ tự
/// thời gian (`transactionDate`, rồi `createdAt`, rồi `id` để đảm bảo
/// deterministic khi trùng ngày) — recovery nào tới trước "ăn" vào phần chi
/// phí gốc CHƯA thu hồi trước, phần dư ra (nếu có) mới là lợi nhuận. Recovery
/// đã bị hoàn tác (`!isVisible`) KHÔNG tính vào basis (mục 7E/STEP 10 #10);
/// recovery đã bị correction chỉ bản thay thế mới nhất (`isVisible`) được
/// tính (mục 7F/STEP 10 #11) — cả hai tự động đúng vì chỉ lọc theo
/// `isVisible`, đúng convention `computeRecoverySummary` ở trên.
///
/// Tổng `profitPortions` của mọi recovery thuộc 1 original luôn bằng
/// `computeRecoverySummary(original, allTransactions).totalProfit` — 2 hàm
/// dùng chung 1 công thức toán học (closed-form ở hàm trên = tổng dồn của
/// vòng lặp tuần tự ở hàm này), chỉ khác là hàm này tách được lợi nhuận theo
/// TỪNG giao dịch/TỪNG kỳ báo cáo thay vì gộp chung 1 tổng.
Map<String, int> computeRecoveryProfitPortions(
  List<Transaction> allTransactions,
) {
  final byId = {for (final t in allTransactions) t.id: t};

  final recoveriesByTarget = <String, List<Transaction>>{};
  for (final t in allTransactions) {
    if (t.recoveryOfTxId != null && isVisible(t)) {
      recoveriesByTarget.putIfAbsent(t.recoveryOfTxId!, () => []).add(t);
    }
  }

  final profitPortions = <String, int>{};
  for (final entry in recoveriesByTarget.entries) {
    final original = byId[entry.key];
    if (original == null) continue; // target không tồn tại — bỏ qua, an toàn.

    final orderedRecoveries = entry.value
      ..sort((a, b) {
        final byDate = a.transactionDate.compareTo(b.transactionDate);
        if (byDate != 0) return byDate;
        final byCreatedAt = a.createdAt.compareTo(b.createdAt);
        if (byCreatedAt != 0) return byCreatedAt;
        return a.id.compareTo(b.id);
      });

    var remainingCost = original.amountMinor;
    for (final r in orderedRecoveries) {
      final costPortion = r.amountMinor < remainingCost
          ? r.amountMinor
          : remainingCost;
      profitPortions[r.id] = r.amountMinor - costPortion;
      remainingCost -= costPortion;
    }
  }
  return profitPortions;
}
