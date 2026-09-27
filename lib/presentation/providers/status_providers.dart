import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/local_status_repository.dart';
import '../../domain/entities/status.dart';
import '../../domain/repositories/status_repository.dart';
import '../../domain/usecases/compute_deletable_master_data.dart';
import 'category_providers.dart';
import 'database_provider.dart';
import 'transaction_providers.dart';

final statusRepositoryProvider = Provider<StatusRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return LocalStatusRepository(db);
});

final statusesStreamProvider = StreamProvider.family<List<Status>, String>((
  ref,
  categoryId,
) {
  final repository = ref.watch(statusRepositoryProvider);
  return repository.watchStatuses(categoryId);
});

/// Id bước trạng thái đã ngừng VÀ chưa có giao dịch nào (còn tồn tại) dùng — hiện
/// "Xóa hẳn". Suy ra trực tiếp từ danh mục + sổ giao dịch đang xem (luôn khớp
/// màn hình); xóa thật vẫn được kiểm tra lại trong DB.
final deletableStatusIdsProvider = Provider<Set<String>>((ref) {
  final categories =
      ref.watch(categoriesStreamProvider).valueOrNull ?? const [];
  final transactions =
      ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
  return computeDeletableStatusIds(categories, transactions);
});
