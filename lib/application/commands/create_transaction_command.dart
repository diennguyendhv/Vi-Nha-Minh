import '../../core/utils/id_generator.dart';
import '../../domain/entities/pool_kind.dart';
import '../../domain/entities/transaction_type.dart';
import '../../domain/entities/transfer_kind.dart';

/// Snapshot bất biến của **1 logical create request** — Phase 4 mục 5/6.
///
/// `id`/`clientTxId` được sinh (qua `IdGenerator`, đúng convention đã có từ
/// Phase 1) **đúng 1 lần lúc command được tạo** và giữ nguyên suốt vòng đời
/// của request đó — kể cả khi caller gọi lại `AddTransactionUseCase` nhiều
/// lần với CÙNG instance command này (double-tap, retry sau lỗi). Không có
/// `copyWith`/setter nào — muốn đổi bất kỳ field nào nghĩa là đó là 1
/// logical request KHÁC, phải tạo command mới (với `clientTxId` mới).
///
/// `transactionDate` là **business/calendar date** do người dùng chọn
/// (`docs/global-readiness-audit.md` mục 11) — Application chỉ lưu nguyên
/// giá trị `DateTime` được truyền vào, KHÔNG tự `.toUtc()`/`.toLocal()`/biến
/// đổi gì thêm (giữ đúng convention hiện tại của project: không có bất kỳ
/// timezone conversion nào trong toàn bộ codebase).
///
/// KHÔNG chứa `createdAt` — đó là audit timestamp hệ thống, thuộc trách
/// nhiệm của `AddTransactionUseCase` tại **thời điểm THỰC THI** (mỗi lần
/// gọi lại có `createdAt` khác nhau là ĐÚNG, vì nó ghi nhận "lúc nào request
/// này được thử ghi", khác với "logical request là gì" mà command này giữ).
///
/// `baseCurrencyCode` — **snapshot 1 lần cùng lúc với `clientTxId`/
/// `transactionDate`** (Phase 4.1 mục 2/4/8, invariant I-RETRY-CURRENCY).
/// KHÔNG phải field cho UI tự do chọn currency: đường tạo command bình
/// thường là qua `CreateTransactionCommandFactory` (đọc từ
/// `CurrencyContext` đúng 1 lần lúc tạo), không phải người dùng gõ/chọn
/// currency cho từng giao dịch — currency thuộc về book/family context.
/// Constructor này vẫn public (không làm private/phức tạp hoá — mục 14: "
/// không security theater") để dễ test, nhưng **đường tạo command chuẩn
/// trong Presentation phải luôn đi qua factory**.
class CreateTransactionCommand {
  CreateTransactionCommand({
    required this.type,
    this.transferKind,
    required this.categoryId,
    required this.sourceKind,
    this.sourceRefId,
    required this.destinationKind,
    this.destinationRefId,
    required this.amountMinor,
    required this.transactionDate,
    required this.baseCurrencyCode,
    this.note = '',
    this.statusId,
    String? id,
    String? clientTxId,
  }) : id = id ?? IdGenerator.generate(),
       clientTxId = clientTxId ?? IdGenerator.generate();

  /// Id của `Transaction` sẽ được tạo — sinh 1 lần, freeze cùng lúc với
  /// `clientTxId`. Có thể truyền tay (chủ yếu cho test) để kiểm soát giá
  /// trị chính xác; caller thật (Presentation, phase sau) luôn để trống và
  /// dùng giá trị tự sinh.
  final String id;

  /// Idempotency key — sinh 1 lần, KHÔNG regenerate khi retry (Phase 3 mục
  /// 14, Phase 3.1, Phase 3.5 mục 12). Repository dựa vào field này để
  /// nhận diện "đây là request đã gửi trước đó".
  final String clientTxId;

  final TransactionType type;

  /// Chỉ khác null khi `type == TransactionType.transfer`.
  final TransferKind? transferKind;

  final String categoryId;
  final PoolKind sourceKind;
  final String? sourceRefId;
  final PoolKind destinationKind;
  final String? destinationRefId;

  /// Luôn dương, đơn vị minor units — Application KHÔNG nhân/chia theo
  /// currency (`docs/global-readiness-audit.md` mục 10). Validate thật
  /// (Invariant 12) vẫn nằm ở `validateNewTransaction`, Repository gọi khi
  /// ghi — Application không lặp lại validate này.
  final int amountMinor;

  /// Ngày nghiệp vụ người dùng chọn — xem doc-comment class ở trên.
  final DateTime transactionDate;

  /// Snapshot của `CurrencyContext.getBaseCurrencyCode()` tại thời điểm
  /// command được tạo (qua `CreateTransactionCommandFactory`) — xem
  /// doc-comment class ở trên. Immutable, `AddTransactionUseCase` KHÔNG
  /// được resolve lại giá trị này.
  final String baseCurrencyCode;

  final String note;

  /// FK tới `Status.id`, nullable — không ảnh hưởng balance (Invariant 9).
  final String? statusId;
}
