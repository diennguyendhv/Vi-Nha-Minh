import '../../core/utils/id_generator.dart';
import '../../domain/entities/obligation_direction.dart';

/// Phase 8.7 — Snapshot bất biến của 1 lần tất toán (thu hồi Receivable /
/// trả nợ Payable), cùng nguyên tắc `CreateTransactionCommand` (Phase 4 mục
/// 5/6): mọi id/clientTxId sinh 1 LẦN lúc command được tạo, giữ nguyên qua
/// mọi lần gọi lại `SettleObligationUseCase.call()` (retry/double-tap) —
/// không có `copyWith`/setter, đổi field nào là 1 logical request KHÁC.
///
/// KHÔNG có `baseCurrencyCode` — Repository tự copy `currency` từ giao dịch
/// TẠO khoản vay (audit Phase 8.7 mục O: tránh mismatch bằng CẤU TRÚC thay
/// vì validate-rồi-reject, không có currency nào để command này tự chọn).
class SettleObligationCommand {
  SettleObligationCommand({
    required this.obligationId,
    required this.direction,
    required this.memberRefId,
    required this.amountMinor,
    required this.transactionDate,
    required this.categoryId,
    required this.interestCategoryId,
    this.note = '',
    String? principalId,
    String? principalClientTxId,
    String? interestId,
    String? interestClientTxId,
  }) : principalId = principalId ?? IdGenerator.generate(),
       principalClientTxId = principalClientTxId ?? IdGenerator.generate(),
       interestId = interestId ?? IdGenerator.generate(),
       interestClientTxId = interestClientTxId ?? IdGenerator.generate();

  final String obligationId;
  final ObligationDirection direction;
  final String memberRefId;

  /// Số tiền người dùng NHẬP THẲNG (toàn bộ số nhận/trả) — KHÔNG tự chia
  /// gốc/lãi ở Presentation/Application (audit mục P — "UX: user chỉ nhập
  /// 1 số"). Repository tự tính split theo outstanding hiện tại.
  final int amountMinor;

  final DateTime transactionDate;
  final String categoryId;
  final String interestCategoryId;
  final String note;

  final String principalId;
  final String principalClientTxId;
  final String interestId;
  final String interestClientTxId;
}
