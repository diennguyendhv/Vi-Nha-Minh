import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/local_fund_repository.dart';
import '../../domain/entities/fund.dart';
import '../../domain/repositories/fund_repository.dart';
import 'database_provider.dart';
import 'transaction_providers.dart';

// Giai đoạn A: luôn dùng LocalFundRepository (SQLite trên máy). Giai đoạn B
// sẽ đổi sang FirestoreFundRepository khi gia đình chuyển syncMode "cloud".
final fundRepositoryProvider = Provider<FundRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final transactionRepository = ref.watch(transactionRepositoryProvider);
  return LocalFundRepository(db, transactionRepository);
});

final fundsStreamProvider = StreamProvider<List<Fund>>((ref) {
  final repository = ref.watch(fundRepositoryProvider);
  return repository.watchFunds();
});
