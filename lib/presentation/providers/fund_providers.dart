import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/local_fund_repository.dart';
import '../../domain/entities/fund.dart';
import '../../domain/repositories/fund_repository.dart';
import '../../domain/usecases/compute_deletable_master_data.dart';
import 'category_providers.dart';
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

/// Id quỹ đã ngừng và không còn dấu vết trong sổ — hiện "Xóa hẳn". Suy ra trực
/// tiếp từ dữ liệu đang xem nên tự cập nhật ngay khi sửa/xóa giao dịch giữ quỹ.
final deletableFundIdsProvider = Provider<Set<String>>((ref) {
  final funds = ref.watch(fundsStreamProvider).valueOrNull ?? const [];
  final categories =
      ref.watch(categoriesStreamProvider).valueOrNull ?? const [];
  final transactions =
      ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
  return computeDeletableFundIds(funds, categories, transactions);
});
