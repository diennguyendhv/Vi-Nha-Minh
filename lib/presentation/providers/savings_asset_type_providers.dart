import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/local_savings_asset_type_repository.dart';
import '../../domain/entities/savings_asset_type.dart';
import '../../domain/repositories/savings_asset_type_repository.dart';
import '../../domain/usecases/compute_savings_breakdown.dart';
import 'database_provider.dart';
import 'transaction_providers.dart';

final savingsAssetTypeRepositoryProvider = Provider<SavingsAssetTypeRepository>(
  (ref) {
    final db = ref.watch(appDatabaseProvider);
    final transactionRepository = ref.watch(transactionRepositoryProvider);
    return LocalSavingsAssetTypeRepository(db, transactionRepository);
  },
);

final savingsAssetTypesStreamProvider = StreamProvider<List<SavingsAssetType>>((
  ref,
) {
  final repository = ref.watch(savingsAssetTypeRepositoryProvider);
  return repository.watchAssetTypes();
});

/// Id loại tài sản đã ngừng VÀ chưa từng được giao dịch nào dùng — hiện "Xóa
/// hẳn". Suy ra trực tiếp từ loại tài sản + sổ giao dịch đang xem (không dùng
/// stream riêng) nên luôn khớp màn hình ngay khi vừa ngừng/tạo/hoàn tác. Xoá
/// thật vẫn được kiểm tra lại trong DB.
final deletableSavingsAssetTypeIdsProvider = Provider<Set<String>>((ref) {
  final assetTypes =
      ref.watch(savingsAssetTypesStreamProvider).valueOrNull ?? const [];
  final transactions =
      ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
  return computeDeletableAssetTypeIds(assetTypes, transactions);
});
