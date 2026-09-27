import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/config/app_environment.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/db_encryption/db_key_store.dart';
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
/// Closure chỉ giữ [d] (gửi được sang isolate nền của Drift).
Future<Directory> Function() dirOf(Directory d) => () async => d;

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

  group('SQLCipher thật: ví hiện tại không bao giờ bị đụng', () {
    late FakeCloud cloud;
    late FakeDevice a;
    late String walletId;
    late String recovery;
    late MemoryDbKeyStore keys;
    late List<int> legacyBytes;
    late DbKeyEntry legacyKey;
    const pw = 'Mật khẩu sao lưu SQLCipher';

    setUp(() async {
      cloud = FakeCloud();
      a = FakeDevice(cloud);
      await a.signIn('uid-s');
      await a.claim();
      recovery = (await a.engine.enableBackup(pw))!;
      await a.engine.push();
      walletId = await a.walletId();
      keys = MemoryDbKeyStore();
      // Ví hiện tại trên máy mới (SQLCipher, tên di sản) — phải nguyên byte.
      final legacy = AppDatabase(
        seedProfile: SeedProfile.fresh,
        wallet: WalletDescriptor.legacyLocal,
        keyStore: keys,
        directory: dirOf(dir),
      );
      await legacy.select(legacy.walletMeta).get();
      await legacy.close();
      legacyBytes = File('${dir.path}/vi_nha_minh.sqlite').readAsBytesSync();
      legacyKey = keys.entries['vi_nha_minh.sqlite']!;
    });
    tearDown(() => a.db.close());

    Future<RestoreEngine> engine(WalletRegistry r, {bool Function(String)? failAt}) async {
      final c = FakeDevice(cloud, installation: '55555555-5555-4555-8555-555555555555');
      await c.signIn('uid-s');
      return RestoreEngine(
        session: c.session, transport: cloud.call, keyStore: c.keys, registry: r,
        storage: SqlcipherRestoreStorage(keyStore: keys, directory: dirOf(dir)),
        env: AppEnvironment.dev, failAt: failAt,
      );
    }

    void expectUntouched() {
      expect(File('${dir.path}/vi_nha_minh.sqlite').readAsBytesSync(), legacyBytes);
      expect(identical(keys.entries['vi_nha_minh.sqlite'], legacyKey), isTrue);
      final names = dir.listSync().map((f) => f.uri.pathSegments.last).toSet();
      expect(names.where((n) => n.startsWith('wallet_')), isEmpty, reason: '$names');
    }

    for (final stage in ['download', 'create', 'apply', 'verify', 'activate']) {
      test('lỗi tại $stage ⇒ không file khôi phục nào còn lại; ví hiện tại + khoá nguyên vẹn', () async {
        final r = WalletRegistry.inMemory();
        await expectLater((await engine(r, failAt: (s) => s == stage))
            .restore(walletId: walletId, password: pw), throwsA(isA<RestoreException>()));
        expectUntouched();
        expect(r.entries, isEmpty);
      });
    }

    test('sai Mật khẩu sao lưu ⇒ không tạo file, không tạo khoá; Recovery Key ⇒ thành công, khoá DB riêng', () async {
      final r = WalletRegistry.inMemory();
      await expectLater((await engine(r)).restore(walletId: walletId, password: 'sai mật khẩu 123'),
          throwsA(isA<RestoreException>().having((e) => e.reason, 'r', 'wrong-secret')));
      expectUntouched();
      expect(keys.entries.keys, ['vi_nha_minh.sqlite']);
      final ok = await (await engine(r)).restore(walletId: walletId, recoveryKey: recovery);
      expect(File('${dir.path}/vi_nha_minh.sqlite').readAsBytesSync(), legacyBytes);
      final restoredKey = keys.entries[ok.dbFileName]!;
      expect(restoredKey.key, isNot(legacyKey.key), reason: 'DEK-DB độc lập');
      expect(probeDbFile(File('${dir.path}/${ok.dbFileName}')), DbFileState.encrypted);
      // Mở lại qua đúng registry/descriptor: khoá gắn tên file cuối cùng hoạt động.
      final db = AppDatabase(wallet: r.byWalletId(walletId)!.toDescriptor(), keyStore: keys,
          directory: dirOf(dir));
      expect((await db.select(db.walletMeta).getSingle()).walletId, walletId);
      expect((await db.customSelect('PRAGMA integrity_check').getSingle()).data.values.first, 'ok');
      await db.close();
    });
  });
}
