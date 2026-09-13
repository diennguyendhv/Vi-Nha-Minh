import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/local_fund_repository.dart';
import '../../domain/entities/fund_entry.dart';
import '../../domain/repositories/fund_repository.dart';
import 'database_provider.dart';

// Giai đoạn A: luôn dùng LocalFundRepository (SQLite trên máy). Giai đoạn B
// sẽ đổi sang FirestoreFundRepository khi gia đình chuyển syncMode "cloud".
final fundRepositoryProvider = Provider<FundRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return LocalFundRepository(db);
});

final fundEntriesStreamProvider =
    StreamProvider.family<List<FundEntry>, String>((ref, fundId) {
      final repository = ref.watch(fundRepositoryProvider);
      return repository.watchEntries(fundId);
    });
