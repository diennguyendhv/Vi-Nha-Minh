import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/local_savings_asset_type_repository.dart';
import '../../domain/entities/savings_asset_type.dart';
import '../../domain/repositories/savings_asset_type_repository.dart';
import 'database_provider.dart';
import 'transaction_providers.dart';

final savingsAssetTypeRepositoryProvider = Provider<SavingsAssetTypeRepository>((
  ref,
) {
  final db = ref.watch(appDatabaseProvider);
  final transactionRepository = ref.watch(transactionRepositoryProvider);
  return LocalSavingsAssetTypeRepository(db, transactionRepository);
});

final savingsAssetTypesStreamProvider = StreamProvider<List<SavingsAssetType>>((
  ref,
) {
  final repository = ref.watch(savingsAssetTypeRepositoryProvider);
  return repository.watchAssetTypes();
});
