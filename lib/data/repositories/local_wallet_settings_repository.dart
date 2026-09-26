import '../local/app_database.dart';

/// Cài đặt thuộc WALLET (`wallet_settings`, v10) — đồng bộ cùng ví, khác prefs thiết
/// bị. Giá trị là chuỗi thô; ý nghĩa do nơi dùng quyết định.
class LocalWalletSettingsRepository {
  LocalWalletSettingsRepository(this._db);
  final AppDatabase _db;

  static const primaryFundKey = 'primary_fund_id';

  /// `null` = chưa từng lưu.
  Future<String?> readRaw(String key) async => (await (_db.select(
    _db.walletSettings,
  )..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Future<void> writeRaw(String key, String value) => _db
      .into(_db.walletSettings)
      .insertOnConflictUpdate(
        WalletSettingsCompanion.insert(key: key, value: value),
      );

  /// Di trú một lần: DB chưa có [key] mà nguồn cũ có [legacyRaw] ⇒ chép sang DB
  /// (nguyên tử). Trả về giá trị thô HIỆU LỰC (DB thắng; `null` = chưa từng lưu ở đâu).
  Future<String?> readOrMigrate(String key, {String? legacyRaw}) =>
      _db.transaction(() async {
        final current = await readRaw(key);
        if (current != null || legacyRaw == null) return current;
        await writeRaw(key, legacyRaw);
        return legacyRaw;
      });
}
