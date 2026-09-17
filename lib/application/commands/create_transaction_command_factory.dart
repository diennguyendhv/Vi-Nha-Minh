import '../../domain/entities/pool_kind.dart';
import '../../domain/entities/transaction_type.dart';
import '../../domain/entities/transfer_kind.dart';
import '../currency/currency_context.dart';
import 'create_transaction_command.dart';

/// **Đường tạo `CreateTransactionCommand` chuẩn** — Phase 4.1 mục 4.
///
/// Đây là nơi DUY NHẤT nên đọc [CurrencyContext] cho 1 logical create
/// request: gọi `getBaseCurrencyCode()` đúng 1 lần, snapshot kết quả vào
/// command cùng lúc với `clientTxId`/`transactionDate` (đều tự sinh/nhận
/// trong constructor của `CreateTransactionCommand`). Sau khi command được
/// tạo, gọi lại `AddTransactionUseCase` bao nhiêu lần (retry) cũng dùng
/// đúng 1 currency đã snapshot — `AddTransactionUseCase` không giữ tham
/// chiếu tới [CurrencyContext] nên không có cách nào vô tình resolve lại.
///
/// **Semantics quan trọng (mục 11):** đổi [CurrencyContext] SAU KHI 1
/// command đã được tạo không ảnh hưởng gì tới command đó — chỉ ảnh hưởng
/// tới các command MỚI được tạo sau thời điểm đổi. Đây đúng là hành vi
/// mong muốn ("currency change ảnh hưởng logical request mới, không viết
/// lại request cũ").
class CreateTransactionCommandFactory {
  const CreateTransactionCommandFactory(this._currencyContext);

  final CurrencyContext _currencyContext;

  Future<CreateTransactionCommand> create({
    required TransactionType type,
    TransferKind? transferKind,
    required String categoryId,
    required PoolKind sourceKind,
    String? sourceRefId,
    required PoolKind destinationKind,
    String? destinationRefId,
    required int amountMinor,
    required DateTime transactionDate,
    String note = '',
    String? statusId,
  }) async {
    final baseCurrencyCode = await _currencyContext.getBaseCurrencyCode();
    return CreateTransactionCommand(
      type: type,
      transferKind: transferKind,
      categoryId: categoryId,
      sourceKind: sourceKind,
      sourceRefId: sourceRefId,
      destinationKind: destinationKind,
      destinationRefId: destinationRefId,
      amountMinor: amountMinor,
      transactionDate: transactionDate,
      baseCurrencyCode: baseCurrencyCode,
      note: note,
      statusId: statusId,
    );
  }
}
