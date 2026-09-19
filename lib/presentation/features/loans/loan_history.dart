import '../../../domain/engine/financial_engine.dart';
import '../../../domain/engine/obligation_settlement.dart';
import '../../../domain/entities/obligation_direction.dart';
import '../../../domain/entities/transaction.dart';

/// Phase 8.8 — 1 dòng lịch sử hiển thị cho người dùng: gộp ĐÚNG 2 ledger leg
/// (gốc + lãi) của 1 lần tất toán thành MỘT hành động logic duy nhất (mục
/// 19 — "người dùng chỉ thấy MỘT logical settlement"). KHÔNG tự tính gì —
/// [amountMinor]/[principalPortion]/[interestPortion] đọc thẳng từ
/// `amountMinor` của các `Transaction` đã có sẵn (domain đã tính đúng), chỉ
/// gộp nhóm theo `settlementGroupId` để hiển thị.
enum LoanHistoryEntryKind { creation, settlement }

class LoanHistoryEntry {
  const LoanHistoryEntry({
    required this.kind,
    required this.anchorTransactionId,
    required this.amountMinor,
    this.principalPortion,
    this.interestPortion,
    required this.date,
    required this.note,
    required this.isLatestSettlement,
  });

  final LoanHistoryEntryKind kind;

  /// Id để truyền cho `reverseObligationSettlement`/`correctObligationSettlement`
  /// (khi [kind] == settlement) — Repository tự resolve group qua
  /// `settlementGroupId`, Presentation không cần biết leg thứ 2 là gì.
  final String anchorTransactionId;

  /// Tổng tiền mặt của hành động này — [kind] == creation: đúng số tiền cho
  /// vay/đi vay; [kind] == settlement: gốc + lãi cộng lại (đúng số tiền
  /// người dùng đã nhập lúc Nhận/Trả).
  final int amountMinor;

  /// Chỉ có ở [kind] == settlement — phần gốc/lãi TÁCH RIÊNG để hiển thị
  /// breakdown trong detail (mục 19: "Detail có thể breakdown bên trong").
  /// `null` khi settlement không có lãi.
  final int? principalPortion;
  final int? interestPortion;

  final DateTime date;
  final String note;

  /// Chỉ có ý nghĩa với [kind] == settlement — đúng lần tất toán MỚI NHẤT
  /// còn hiệu lực, theo policy Phase 8.7 (chỉ lần này được phép "Sửa").
  final bool isLatestSettlement;
}

/// Gộp toàn bộ `Transaction` liên quan 1 khoản vay thành danh sách hiển thị
/// được cho người dùng, sắp theo thời gian TĂNG DẦN (cũ → mới, khớp mockup
/// mục 12: "08/05 Cho vay ... 10/10 Đã nhận"). Chỉ lấy giao dịch còn
/// `isVisible` — giao dịch đã hoàn tác/thay thế biến mất khỏi danh sách,
/// đúng convention toàn app (`transaction_detail_screen.dart`/
/// `fund_detail_screen.dart`).
List<LoanHistoryEntry> buildLoanHistory(
  ObligationDirection direction,
  String obligationId,
  List<Transaction> allTransactions,
) {
  final entries = <LoanHistoryEntry>[];

  final creation = findObligationCreationTransaction(
    direction,
    obligationId,
    allTransactions,
  );
  if (creation != null) {
    entries.add(
      LoanHistoryEntry(
        kind: LoanHistoryEntryKind.creation,
        anchorTransactionId: creation.id,
        amountMinor: creation.amountMinor,
        date: creation.transactionDate,
        note: creation.note,
        isLatestSettlement: false,
      ),
    );
  }

  final anchors = listObligationSettlementAnchors(
    direction,
    obligationId,
    allTransactions,
  );
  for (final anchor in anchors) {
    Transaction? interestLeg;
    for (final t in allTransactions) {
      if (t.settlementGroupId == anchor.id &&
          t.id != anchor.id &&
          isVisible(t)) {
        interestLeg = t;
        break;
      }
    }
    final interestAmount = interestLeg?.amountMinor ?? 0;
    entries.add(
      LoanHistoryEntry(
        kind: LoanHistoryEntryKind.settlement,
        anchorTransactionId: anchor.id,
        amountMinor: anchor.amountMinor + interestAmount,
        principalPortion: anchor.amountMinor,
        interestPortion: interestAmount > 0 ? interestAmount : null,
        date: anchor.transactionDate,
        note: anchor.note,
        isLatestSettlement: identical(anchor, anchors.last),
      ),
    );
  }

  entries.sort((a, b) => a.date.compareTo(b.date));
  return entries;
}
