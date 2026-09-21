import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';
import 'wallet_descriptor.dart';
import 'wallet_registry.dart';

/// Nạp registry và đăng ký ví cục bộ hiện tại TẠI CHỖ (đọc `wallet_id` từ chính file
/// `vi_nha_minh.sqlite`, không move/copy/tạo lại). KHÔNG BAO GIỜ ném: lỗi ⇒ registry
/// rỗng không bền, app vẫn mở ví cục bộ mặc định và thử đăng ký lại ở lần chạy sau.
Future<WalletRegistry> bootstrapWalletRegistry() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final registry = await WalletRegistry.load(
      FileWalletRegistryStorage(File(p.join(dir.path, 'wallet_registry.json'))),
    );
    await registry.ensureLegacyLocal(() async {
      final db = AppDatabase(wallet: WalletDescriptor.legacyLocal);
      try {
        return (await db.select(db.walletMeta).getSingle()).walletId;
      } finally {
        await db.close();
      }
    });
    return registry;
  } on Object {
    return WalletRegistry.inMemory();
  }
}
