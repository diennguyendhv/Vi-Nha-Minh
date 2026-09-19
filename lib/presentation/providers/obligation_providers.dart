import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/use_cases/correct_obligation_settlement_use_case.dart';
import '../../application/use_cases/create_obligation_use_case.dart';
import '../../application/use_cases/reverse_obligation_settlement_use_case.dart';
import '../../application/use_cases/settle_obligation_use_case.dart';
import '../../data/repositories/local_obligation_repository.dart';
import '../../domain/entities/obligation.dart';
import '../../domain/repositories/obligation_repository.dart';
import 'database_provider.dart';
import 'transaction_providers.dart';

final obligationRepositoryProvider = Provider<ObligationRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return LocalObligationRepository(db);
});

final obligationsStreamProvider = StreamProvider<List<Obligation>>((ref) {
  final repository = ref.watch(obligationRepositoryProvider);
  return repository.watchObligations();
});

final createObligationUseCaseProvider = Provider<CreateObligationUseCase>((
  ref,
) {
  return CreateObligationUseCase(ref.watch(obligationRepositoryProvider));
});

final settleObligationUseCaseProvider = Provider<SettleObligationUseCase>((
  ref,
) {
  final repository = ref.watch(transactionRepositoryProvider);
  return SettleObligationUseCase(repository);
});

final reverseObligationSettlementUseCaseProvider =
    Provider<ReverseObligationSettlementUseCase>((ref) {
      final repository = ref.watch(transactionRepositoryProvider);
      return ReverseObligationSettlementUseCase(repository);
    });

final correctObligationSettlementUseCaseProvider =
    Provider<CorrectObligationSettlementUseCase>((ref) {
      final repository = ref.watch(transactionRepositoryProvider);
      return CorrectObligationSettlementUseCase(repository);
    });
