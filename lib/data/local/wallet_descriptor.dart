import '../../domain/entities/wallet_identity.dart';

/// Mô tả CÁCH MỞ DB của 1 Wallet — để mã sau này mở DB theo Wallet thay vì giả định
/// mãi mãi chỉ có 1 DB toàn cục. Kiến trúc đích: 1 Wallet = 1 file SQLite; registry
/// bền vững (nhiều ví) hoãn tới phase cách ly Account/Wallet — P2 CHỈ có trừu tượng
/// này, KHÔNG có registry, KHÔNG di chuyển file DB hiện tại.
class WalletDescriptor {
  const WalletDescriptor({
    this.walletId,
    required this.kind,
    required this.dbFileName,
  });

  /// `null` với Wallet di sản CHƯA được định danh (id nằm TRONG DB, chỉ biết sau
  /// khi mở). Sau khi mở, đọc `wallet_meta` để biết.
  final String? walletId;
  final WalletKind kind;

  /// Tên file SQLite trong thư mục tài liệu của app.
  final String dbFileName;

  /// DB hiện tại của app = Wallet cục bộ đầu tiên. Tên file GIỮ NGUYÊN.
  static const legacyLocal = WalletDescriptor(
    kind: WalletKind.local,
    dbFileName: 'vi_nha_minh.sqlite',
  );
}
