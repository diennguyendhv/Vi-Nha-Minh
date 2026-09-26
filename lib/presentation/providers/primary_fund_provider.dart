import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/default_funds.dart';
import '../../data/local/wallet_descriptor.dart';
import '../../data/repositories/local_wallet_settings_repository.dart';
import 'database_provider.dart';

/// Lưu lựa chọn "quỹ chính" của Trang chủ.
///
/// Từ v10 (P8.1) nơi lưu CHÍNH là `wallet_settings` trong DB của ví (WALLET DATA,
/// đồng bộ cùng ví). Khoá SharedPreferences cũ dưới đây chỉ còn là nguồn ĐỌC dự
/// phòng tạm thời + nguồn di trú một lần; không ghi mới vào đó.
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

  static String? load(SharedPreferences prefs, {String storageKey = key}) =>
      decode(readRaw(prefs, storageKey: storageKey));

  /// Giá trị thô (`null` = chưa từng lưu).
  static String? readRaw(SharedPreferences prefs, {String storageKey = key}) =>
      prefs.containsKey(storageKey) ? (prefs.getString(storageKey) ?? '') : null;

  /// Thô → id quỹ theo quy ước ở trên.
  static String? decode(String? raw) {
    if (raw == null) return DefaultFunds.anUongId;
    return raw.isEmpty ? null : raw;
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

  bool _touched = false;

  Future<void> select(String? id) async {
    _touched = true;
    state = id;
    await persist?.call(id);
  }

  /// Nạp giá trị bền vững (bất đồng bộ, từ DB ví). Bỏ qua nếu người dùng đã chọn
  /// trong lúc chờ; lỗi đọc ⇒ giữ giá trị dự phòng hiện tại.
  Future<void> hydrate(Future<String?> Function() load) async {
    try {
      final id = await load();
      if (!_touched && mounted) state = id;
    } on Object {
      // giữ giá trị dự phòng
    }
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

/// Dựng controller của [wallet] cho `main()`: đọc/ghi `wallet_settings` trong DB ví.
/// Lần đầu (DB chưa có giá trị) chép giá trị hiệu lực từ khoá prefs cũ sang DB; prefs
/// cũ chỉ là giá trị hiển thị tạm trước khi DB nạp xong. Ghi mới CHỈ vào DB.
PrimaryFundController createWalletPrimaryFundController(
  SharedPreferences prefs,
  WalletDescriptor wallet,
  LocalWalletSettingsRepository settings,
) {
  final legacyKey = PrimaryFundStorage.keyFor(wallet);
  final legacyRaw = PrimaryFundStorage.readRaw(prefs, storageKey: legacyKey);
  const k = LocalWalletSettingsRepository.primaryFundKey;
  final controller = PrimaryFundController(
    initialId: PrimaryFundStorage.decode(legacyRaw),
    persist: (id) => settings.writeRaw(k, id ?? ''),
  );
  controller.hydrate(
    () async => PrimaryFundStorage.decode(
      await settings.readOrMigrate(k, legacyRaw: legacyRaw),
    ),
  );
  return controller;
}
