import '../../domain/entities/transaction.dart';
import '../../domain/repositories/obligation_repository.dart';
import '../commands/create_obligation_command.dart';
import '../commands/transaction_from_command.dart';

class CreateObligationUseCase {
  const CreateObligationUseCase(this._repository);

  final ObligationRepository _repository;

  Future<Transaction> call(CreateObligationCommand command) {
    return _repository.createObligationWithOpeningTransaction(
      command.obligation,
      transactionFromCommand(command.opening),
    );
  }
}
