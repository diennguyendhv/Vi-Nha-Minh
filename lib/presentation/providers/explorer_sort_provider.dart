import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/usecases/explore_transactions.dart';

/// Lưu cấu hình sắp xếp ĐÃ ÁP DỤNG của Tổng hợp / Explorer (tuỳ chọn hiển thị của
/// người dùng, không phải sổ cái) — khóa bật, thứ tự ưu tiên, chiều từng khóa.
class ExplorerSortStorage {
  const ExplorerSortStorage._();

  static const key = 'explorer_sort';

  static ExplorerSort load(SharedPreferences prefs) =>
      ExplorerSort.decode(prefs.getString(key));

  static Future<void> save(SharedPreferences prefs, ExplorerSort sort) =>
      prefs.setString(key, sort.encode());
}

class ExplorerSortController extends StateNotifier<ExplorerSort> {
  ExplorerSortController({
    ExplorerSort initial = ExplorerSort.defaultSort,
    this.persist,
  }) : super(initial);

  /// Ghi xuống nơi lưu bền vững (null trong test → chỉ in-memory).
  final Future<void> Function(ExplorerSort sort)? persist;

  Future<void> select(ExplorerSort sort) async {
    state = sort;
    await persist?.call(sort);
  }
}

/// Mặc định (test / chưa nạp prefs): in-memory, Ngày ↓. `main()` ghi đè bằng bản
/// đọc/ghi `shared_preferences` thật.
final explorerSortProvider =
    StateNotifierProvider<ExplorerSortController, ExplorerSort>(
      (ref) => ExplorerSortController(),
    );

ExplorerSortController createPersistentExplorerSortController(
  SharedPreferences prefs,
) => ExplorerSortController(
  initial: ExplorerSortStorage.load(prefs),
  persist: (sort) => ExplorerSortStorage.save(prefs, sort),
);
