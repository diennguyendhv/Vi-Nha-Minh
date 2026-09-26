import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/wallet_identity.dart';
import '../local/app_database.dart';
import '../local/db_encryption/db_key_store.dart';
import '../local/seed_defaults.dart';
import '../local/wallet_descriptor.dart';
import '../local/wallet_registry.dart';
import 'restore_engine.dart';

/// Tên file mà CHỈ khôi phục tạo ra (ngẫu nhiên, duy nhất). Ví di sản
/// `vi_nha_minh.sqlite` không bao giờ khớp ⇒ không bao giờ bị dọn.
final restoreFileName = RegExp(r'^wallet_[A-Za-z0-9-]{8,64}\.sqlite$');

/// Bản app: ví khôi phục mở bằng SQLCipher với khoá DEK-DB RIÊNG của đúng tên file
/// cuối cùng (Keystore tạo lúc mở lần đầu), `SeedProfile.none` ⇒ không có file bản rõ.
/// Xoá khi lỗi = file + sidecar + marker (khoá: xem [discard]).
class SqlcipherRestoreStorage implements RestoreStorage {
  SqlcipherRestoreStorage({
    DbKeyStore keyStore = const KeystoreDbKeyStore(),
    Future<Directory> Function()? directory,
  }) : _keys = keyStore,
       _dir = directory ?? getApplicationDocumentsDirectory;
  final DbKeyStore _keys;
  final Future<Directory> Function() _dir;

  Future<File> _file(String name) async {
    if (!restoreFileName.hasMatch(name)) throw ArgumentError('restore file name');
    return File(p.join((await _dir()).path, name));
  }

  @override
  Future<AppDatabase> open(String name) async {
    final file = await _file(name);
    if (file.existsSync()) throw StateError('restore target exists');
    final db = AppDatabase(
      seedProfile: SeedProfile.none,
      wallet: WalletDescriptor(kind: WalletKind.personal, dbFileName: name),
      keyStore: _keys,
      directory: _dir,
    );
    await db.customSelect('SELECT 1').get(); // tạo file (đã mã hoá) + khoá ngay
    return db;
  }

  @override
  Future<void> markRestoring(String name) async =>
      File('${(await _file(name)).path}.restoring').writeAsStringSync('');

  @override
  Future<void> clearMarker(String name) async {
    final m = File('${(await _file(name)).path}.restoring');
    if (m.existsSync()) m.deleteSync();
  }

  @override
  Future<void> discard(String name) async {
    final f = await _file(name);
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final x = File('${f.path}$suffix');
      if (x.existsSync()) x.deleteSync();
    }
    // Mục khoá Keystore của tên file ngẫu nhiên này được GIỮ (bridge cố ý không có
    // API xoá khoá DB — bất biến SQLCipher). Tên không bao giờ được dùng lại nên mục
    // mồ côi vô hại; không có file nào để nó mở.
    await clearMarker(name);
  }
}

/// Khởi động: dọn khôi phục bị ngắt (còn marker `.restoring`, ví CHƯA có trong
/// registry). Không bao giờ đụng ví đã đăng ký hay ví di sản.
Future<int> cleanupInterruptedRestores(
  WalletRegistry registry,
  RestoreStorage storage,
  Directory dir,
) async {
  var cleaned = 0;
  if (!dir.existsSync()) return 0;
  for (final f in dir.listSync().whereType<File>()) {
    final name = p.basename(f.path);
    if (!name.endsWith('.restoring')) continue;
    final db = name.substring(0, name.length - '.restoring'.length);
    if (!restoreFileName.hasMatch(db)) continue;
    if (registry.entries.any((e) => e.dbFileName == db)) {
      await storage.clearMarker(db); // đã kích hoạt, chỉ còn marker
      continue;
    }
    await storage.discard(db);
    cleaned++;
  }
  return cleaned;
}
