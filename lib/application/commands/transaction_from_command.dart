import '../../domain/entities/transaction.dart';
import 'create_transaction_command.dart';

/// Shared mapping for ordinary creates and atomic loan creates. Only the audit
/// timestamp changes per attempt; currency and logical identity stay frozen.
Transaction transactionFromCommand(CreateTransactionCommand command) {
  return Transaction(
    id: command.id,
    type: command.type,
    transferKind: command.transferKind,
    categoryId: command.categoryId,
    sourceKind: command.sourceKind,
    sourceRefId: command.sourceRefId,
    destinationKind: command.destinationKind,
    destinationRefId: command.destinationRefId,
    amountMinor: command.amountMinor,
    note: command.note,
    statusId: command.statusId,
    recoveryOfTxId: command.recoveryOfTxId,
    obligationId: command.obligationId,
    transactionDate: command.transactionDate,
    createdAt: DateTime.now(),
    clientTxId: command.clientTxId,
    currency: command.baseCurrencyCode,
  );
}
