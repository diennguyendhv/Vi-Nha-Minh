import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/local_counterparty_repository.dart';
import '../../domain/entities/counterparty.dart';
import '../../domain/repositories/counterparty_repository.dart';
import 'database_provider.dart';
import 'transaction_providers.dart';

final counterpartyRepositoryProvider = Provider<CounterpartyRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final transactionRepository = ref.watch(transactionRepositoryProvider);
  return LocalCounterpartyRepository(db, transactionRepository);
});

final counterpartiesStreamProvider = StreamProvider<List<Counterparty>>((ref) {
  final repository = ref.watch(counterpartyRepositoryProvider);
  return repository.watchCounterparties();
});
