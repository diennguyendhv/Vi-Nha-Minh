import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/local_category_repository.dart';
import '../../domain/entities/category.dart';
import '../../domain/repositories/category_repository.dart';
import 'database_provider.dart';

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
