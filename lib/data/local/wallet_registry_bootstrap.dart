import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';
import 'sync/cloud_binding_store.dart';
import 'wallet_descriptor.dart';
import 'wallet_registry.dart';
import '../../domain/entities/cloud_binding.dart';

/// Nạp registry và đăng ký ví cục bộ hiện tại TẠI CHỖ (đọc `wallet_id` từ chính file
/// `vi_nha_minh.sqlite`, không move/copy/tạo lại). KHÔNG BAO GIỜ ném: lỗi ⇒ registry
/// rỗng không bền, app vẫn mở ví cục bộ mặc định và thử đăng ký lại ở lần chạy sau.
Future<WalletRegistry> bootstrapWalletRegistry() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final registry = await WalletRegistry.load(
      FileWalletRegistryStorage(File(p.join(dir.path, 'wallet_registry.json'))),
    );
    final db = AppDatabase(wallet: WalletDescriptor.legacyLocal);
    try {
      await registry.ensureLegacyLocal(
        () async => (await db.select(db.walletMeta).getSingle()).walletId,
      );
      // P8.2: DB là nguồn sự thật của ràng buộc cloud — sửa registry theo DB (vd app
      // chết giữa lúc kích hoạt claim và lúc ghi registry).
      await reconcileRegistryFromDb(
        registry,
        db,
        WalletDescriptor.legacyLocal.dbFileName,
      );
    } finally {
      await db.close();
    }
    return registry;
  } on Object {
    return WalletRegistry.inMemory();
  }
}

/// Đưa dòng registry của ví trong [db] về đúng `cloud_binding` (ACTIVE ⇒ gắn Account;
/// NONE/CLAIMING ⇒ cục bộ chưa gắn). Không bao giờ ghi vào DB.
Future<WalletRegistryEntry> reconcileRegistryFromDb(
  WalletRegistry registry,
  AppDatabase db,
  String dbFileName,
) async {
  final walletId = (await db.select(db.walletMeta).getSingle()).walletId;
  final binding = await CloudBindingStore(db).read();
  return registry.reconcileBinding(
    walletId: walletId,
    dbFileName: dbFileName,
    boundAccountId:
        binding != null &&
            binding.state == CloudBindingState.active &&
            binding.walletId == walletId
        ? binding.accountId
        : null,
  );
}
