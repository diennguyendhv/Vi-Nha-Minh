import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/default_funds.dart';

/// Lưu lựa chọn "quỹ chính" của Trang chủ.
///
/// Quy ước giá trị lưu (khóa [key]):
///  - chưa từng lưu → mặc định [DefaultFunds.anUongId] (cài mới);
///  - chuỗi rỗng    → người dùng CHỦ ĐỘNG không có quỹ chính (vd đã xóa quỹ chính);
///  - id quỹ        → quỹ đó.
/// Nhờ phân biệt "chưa lưu" với "rỗng" mà quỹ mặc định không bao giờ tự sống lại
/// sau khi người dùng cố ý xóa.
class PrimaryFundStorage {
  const PrimaryFundStorage._();

  static const key = 'primary_fund_id';

  static String? load(SharedPreferences prefs) {
    if (!prefs.containsKey(key)) return DefaultFunds.anUongId;
    final value = prefs.getString(key);
    return (value == null || value.isEmpty) ? null : value;
  }

  static Future<void> save(SharedPreferences prefs, String? id) =>
      prefs.setString(key, id ?? '');
}

/// Id quỹ chính hiện tại (`null` = chưa chọn). Việc quỹ đó còn tồn tại/đang dùng
/// được kiểm tra lúc hiển thị (`resolvePrimaryFund`), nên xóa quỹ chính không
/// làm crash — Trang chủ chỉ hiện "Chưa chọn quỹ chính".
class PrimaryFundController extends StateNotifier<String?> {
  PrimaryFundController({
    String? initialId = DefaultFunds.anUongId,
    this.persist,
  }) : super(initialId);

  /// Ghi lựa chọn xuống nơi lưu bền vững (null trong test → chỉ in-memory).
  final Future<void> Function(String? id)? persist;

  Future<void> select(String? id) async {
    state = id;
    await persist?.call(id);
  }

  /// Gọi sau khi xóa hẳn 1 quỹ: nếu đó là quỹ chính thì bỏ chọn.
  Future<void> clearIfPrimary(String fundId) async {
    if (state == fundId) await select(null);
  }
}

/// Mặc định (test / chưa nạp prefs): in-memory, khởi tạo = quỹ ăn. `main()` ghi đè
/// bằng bản đọc/ghi `shared_preferences` thật.
final primaryFundIdProvider =
    StateNotifierProvider<PrimaryFundController, String?>(
      (ref) => PrimaryFundController(),
    );

/// Dựng controller lưu bền vững từ [prefs] — dùng ở `main()`.
PrimaryFundController createPersistentPrimaryFundController(
  SharedPreferences prefs,
) => PrimaryFundController(
  initialId: PrimaryFundStorage.load(prefs),
  persist: (id) => PrimaryFundStorage.save(prefs, id),
);
