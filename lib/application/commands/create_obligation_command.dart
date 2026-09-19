import '../../domain/entities/obligation.dart';
import 'create_transaction_command.dart';

/// One immutable logical create request, including metadata and ledger identity.
class CreateObligationCommand {
  const CreateObligationCommand({
    required this.obligation,
    required this.opening,
  });

  final Obligation obligation;
  final CreateTransactionCommand opening;
}
