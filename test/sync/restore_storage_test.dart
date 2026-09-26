import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/config/app_environment.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/db_encryption/sqlcipher_wallet.dart';
import 'package:vi_nha_minh/data/local/seed_defaults.dart';
import 'package:vi_nha_minh/data/local/wallet_descriptor.dart';
import 'package:vi_nha_minh/data/local/wallet_registry.dart';
import 'package:vi_nha_minh/data/sync/restore_engine.dart';
import 'package:vi_nha_minh/data/sync/restore_storage.dart';
import 'package:vi_nha_minh/domain/entities/wallet_identity.dart';

import '../support/fake_cloud.dart';
import '../support/memory_db_key_store.dart';

/// P8.5 — storage SQLCipher THẬT của khôi phục: file tên CUỐI CÙNG + khoá riêng ngay từ
/// đầu (không rename ⇒ không gãy ràng buộc khoá↔tên file), không bao giờ có bản rõ,
/// lỗi ⇒ dọn sạch, crash ⇒ dọn lúc khởi động, không bao giờ đụng ví đang dùng.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vnm_restore_sqlcipher_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('khôi phục qua SQLCipher: file mã hoá từ đầu, mở lại bằng đúng khoá của tên đó', () async {
    final cloud = FakeCloud();
    final a = FakeDevice(cloud);
    await a.signIn('uid-s');
    await a.claim();
    await a.engine.enableBackup('Mật khẩu sao lưu SQLCipher');
    await a.engine.push();
    final walletId = await a.walletId();

    final c = FakeDevice(cloud, installation: '33333333-3333-4333-8333-333333333333');
    await c.signIn('uid-s');
    final keys = MemoryDbKeyStore();
    final registry = WalletRegistry.inMemory();
    final result = await RestoreEngine(
      session: c.session, transport: cloud.call, keyStore: c.keys, registry: registry,
      storage: SqlcipherRestoreStorage(keyStore: keys, directory: () async => dir),
      env: AppEnvironment.dev,
    ).restore(walletId: walletId, password: 'Mật khẩu sao lưu SQLCipher');
    expect(restoreFileName.hasMatch(result.dbFileName), isTrue);
    for (final f in dir.listSync().whereType<File>()) {
      expect(probeDbFile(f), isNot(DbFileState.plaintext), reason: f.path);
      expect(f.path.endsWith('.restoring'), isFalse);
    }
    expect(keys.entries.keys, [result.dbFileName]);
    expect(keys.entries[result.dbFileName]!.walletId, isNull,
        reason: 'gắn walletId ở lần mở kế tiếp (beforeOpen)');
    final reopened = AppDatabase(
      wallet: registry.byWalletId(walletId)!.toDescriptor(),
      keyStore: keys,
      directory: () async => dir,
    );
    expect((await reopened.select(reopened.walletMeta).getSingle()).walletId, walletId);
    expect(keys.entries[result.dbFileName]!.walletId, walletId);
    await reopened.close();
    await a.db.close();
  });

  test('tên file ngoài mẫu khôi phục bị từ chối; ví di sản không bao giờ bị dọn', () async {
    final storage = SqlcipherRestoreStorage(keyStore: MemoryDbKeyStore(), directory: () async => dir);
    await expectLater(storage.open('vi_nha_minh.sqlite'), throwsArgumentError);
    await expectLater(storage.discard('vi_nha_minh.sqlite'), throwsArgumentError);
  });

  test('crash giữa khôi phục ⇒ khởi động dọn file + marker chưa đăng ký; giữ ví đã đăng ký', () async {
    final keys = MemoryDbKeyStore();
    final storage = SqlcipherRestoreStorage(keyStore: keys, directory: () async => dir);
    const dead = 'wallet_11111111-dead-4000-8000-000000000000.sqlite';
    const live = 'wallet_22222222-live-4000-8000-000000000000.sqlite';
    await storage.markRestoring(dead);
    final half = await storage.open(dead);
    await half.close();
    await storage.markRestoring(live);
    final ok = await storage.open(live);
    await ok.close();
    // Ví di sản bên cạnh (không bao giờ khớp mẫu).
    final legacy = AppDatabase(
      seedProfile: SeedProfile.fresh,
      wallet: WalletDescriptor.legacyLocal,
      keyStore: keys,
      directory: () async => dir,
    );
    await legacy.select(legacy.walletMeta).get();
    await legacy.close();
    final legacyBytes = File('${dir.path}/vi_nha_minh.sqlite').readAsBytesSync();
    final registry = WalletRegistry.inMemory();
    await registry.register(WalletRegistryEntry(walletId: 'w-live-1234', kind: WalletKind.personal,
        dbFileName: live, createdAt: DateTime(2026), boundAccountId: 'uid'));
    expect(await cleanupInterruptedRestores(registry, storage, dir), 1);
    final names = dir.listSync().map((f) => f.uri.pathSegments.last).toSet();
    expect(names.any((n) => n.startsWith(dead)), isFalse);
    expect(names, contains(live));
    expect(names.any((n) => n.endsWith('.restoring')), isFalse);
    expect(File('${dir.path}/vi_nha_minh.sqlite').readAsBytesSync(), legacyBytes);
  });
}
