import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/default_funds.dart';
import '../../data/local/wallet_descriptor.dart';
import 'database_provider.dart';

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

  /// Quỹ chính là WALLET DATA ⇒ khoá theo ví (P6). Ví cục bộ hiện tại GIỮ khoá trần
  /// cũ (không di trú, không mất lựa chọn đã lưu); ví khác dùng `primary_fund_id.<walletId>`.
  static String keyFor(WalletDescriptor wallet) =>
      (wallet.dbFileName == WalletDescriptor.legacyLocal.dbFileName ||
          wallet.walletId == null)
      ? key
      : '$key.${wallet.walletId}';

  static String? load(SharedPreferences prefs, {String storageKey = key}) {
    if (!prefs.containsKey(storageKey)) return DefaultFunds.anUongId;
    final value = prefs.getString(storageKey);
    return (value == null || value.isEmpty) ? null : value;
  }

  static Future<void> save(
    SharedPreferences prefs,
    String? id, {
    String storageKey = key,
  }) => prefs.setString(storageKey, id ?? '');
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
      (ref) {
        ref.watch(walletSessionKeyProvider); // đổi ví ⇒ không giữ quỹ của ví trước
        return PrimaryFundController();
      },
    );

/// Dựng controller lưu bền vững từ [prefs] cho [wallet] — dùng ở `main()`.
PrimaryFundController createPersistentPrimaryFundController(
  SharedPreferences prefs, [
  WalletDescriptor wallet = WalletDescriptor.legacyLocal,
]) {
  final storageKey = PrimaryFundStorage.keyFor(wallet);
  return PrimaryFundController(
    initialId: PrimaryFundStorage.load(prefs, storageKey: storageKey),
    persist: (id) =>
        PrimaryFundStorage.save(prefs, id, storageKey: storageKey),
  );
}
