import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/local_category_repository.dart';
import '../../domain/entities/category.dart';
import '../../domain/repositories/category_repository.dart';
import '../../domain/usecases/compute_deletable_master_data.dart';
import 'database_provider.dart';
import 'transaction_providers.dart';

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return LocalCategoryRepository(db);
});

/// Kèm sẵn `statuses` cho mỗi category — nguồn dữ liệu chung cho mọi màn
/// (Thêm giao dịch, Danh mục, Tổng hợp trạng thái). Không lọc `isActive`
/// ở đây — mỗi màn tự lọc theo nhu cầu (danh sách tạo mới chỉ hiện active,
/// nhưng lịch sử cũ vẫn cần tên/màu danh mục đã inactive).
final categoriesStreamProvider = StreamProvider<List<Category>>((ref) {
  final repository = ref.watch(categoryRepositoryProvider);
  return repository.watchCategories();
});

/// Id danh mục đã ngừng VÀ an toàn để hiện "Xóa hẳn" (không giao dịch nào còn
/// tham chiếu). Suy ra TRỰC TIẾP từ danh mục + sổ giao dịch đang xem — không
/// dùng stream riêng — nên cập nhật ngay khi vừa xóa giao dịch/ngừng danh mục.
/// Xóa thật vẫn được kiểm tra lại trong DB.
final deletableCategoryIdsProvider = Provider<Set<String>>((ref) {
  final categories = ref.watch(categoriesStreamProvider).valueOrNull ?? const [];
  final transactions =
      ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
  return computeDeletableCategoryIds(categories, transactions);
});
