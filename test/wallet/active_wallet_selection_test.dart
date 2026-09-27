import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/data/local/db_encryption/db_preflight.dart';
import 'package:vi_nha_minh/data/local/wallet_registry.dart';
import 'package:vi_nha_minh/domain/entities/wallet_access_scope.dart';
import 'package:vi_nha_minh/domain/entities/wallet_identity.dart';

import '../support/memory_db_key_store.dart';

/// F1 (quy tắc đã khoá 2026-09-27): khôi phục thành công ⇒ ví khôi phục là ví đang
/// hoạt động của máy; đăng xuất Firebase KHÔNG đổi ví đang hoạt động; ví bootstrap lúc
/// cài chỉ là dự phòng; không chọn theo số giao dịch; ví đang hoạt động hỏng/mất file
/// ⇒ cần khôi phục, không lặng lẽ đổi ví.
WalletRegistryEntry _restored(String id, String account) => WalletRegistryEntry(
  walletId: id,
  kind: WalletKind.personal,
  dbFileName: 'wallet_$id.sqlite',
  createdAt: DateTime.utc(2026, 9, 27),
  boundAccountId: account,
);

const _local = WalletAccessScope.local();
WalletAccessScope _acc(String uid) => WalletAccessScope.account(uid);

void main() {
  late Directory tmp;
  late File file;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('active_wallet_');
    file = File('${tmp.path}/wallet_registry.json');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<WalletRegistry> freshInstallWithRestore() async {
    final r = await WalletRegistry.load(FileWalletRegistryStorage(file));
    await r.ensureLegacyLocal(() async => 'bootstrap'); // ví rỗng tạo lúc cài
    await r.register(_restored('restored', 'A'), activate: true);
    return r;
  }

  test('khôi phục ⇒ ví khôi phục đang hoạt động; đăng xuất vẫn là nó (bền qua khởi động lại)', () async {
    final r = await freshInstallWithRestore();
    expect(r.resolveActive(_acc('A'))!.walletId, 'restored');
    expect(r.resolveActive(_local)!.walletId, 'restored',
        reason: 'đăng xuất không đổi ví đang hoạt động; ví bootstrap không chiếm chỗ');

    final reloaded = await WalletRegistry.load(FileWalletRegistryStorage(file));
    expect(reloaded.recentlyActive, ['restored']);
    expect(reloaded.resolveActive(_local)!.walletId, 'restored');
    expect(reloaded.resolveActive(_acc('A'))!.walletId, 'restored');
  });

  test('Account khác: ví Personal không mở; dự phòng ví bootstrap; quay lại A ⇒ đúng ví cũ', () async {
    final r = await freshInstallWithRestore();
    expect(r.resolveActive(_acc('X'))!.walletId, 'bootstrap');
    expect(r.recentlyActive, ['restored'], reason: 'đổi Account không ghi MRU');
    expect(r.resolveActive(_acc('A'))!.walletId, 'restored');
    expect(r.resolveActive(_local)!.walletId, 'restored');
  });

  test('máy cũ (registry không có "active") ⇒ quy tắc dự phòng như trước, không ghi gì', () async {
    await file.writeAsString(
      '{"version":1,"wallets":[{"walletId":"legacy","kind":"local",'
      '"dbFileName":"vi_nha_minh.sqlite","createdAt":"2026-09-21T00:00:00.000Z"}]}',
    );
    final before = await file.readAsString();
    final r = await WalletRegistry.load(FileWalletRegistryStorage(file));
    expect(r.recentlyActive, isEmpty);
    expect(r.resolveActive(_local)!.walletId, 'legacy');
    expect(r.resolveActive(_acc('A'))!.walletId, 'legacy');
    expect(await file.readAsString(), before);
  });

  test('MRU: kích hoạt tường minh đổi ví; id lạ/ví chưa đăng ký bị bỏ qua khi nạp', () async {
    final r = await freshInstallWithRestore();
    await r.markActive('bootstrap');
    expect(r.resolveActive(_local)!.walletId, 'bootstrap');
    expect(r.recentlyActive, ['bootstrap', 'restored']);
    await expectLater(r.markActive('ghost'), throwsStateError);

    await file.writeAsString((await file.readAsString())
        .replaceFirst('"active":[', '"active":["ghost",'));
    final reloaded = await WalletRegistry.load(FileWalletRegistryStorage(file));
    expect(reloaded.recentlyActive, ['bootstrap', 'restored']);
  });

  test('đăng ký lại cùng ví (retry khôi phục) + activate ⇒ idempotent, vẫn đang hoạt động', () async {
    final r = await freshInstallWithRestore();
    await r.markActive('bootstrap');
    await r.register(_restored('restored', 'A'), activate: true);
    expect(r.entries, hasLength(2));
    expect(r.recentlyActive.first, 'restored');
  });

  test('ví đang hoạt động mất file / mất khoá ⇒ cần khôi phục; ví di sản không bị kiểm theo luật này', () async {
    final keys = MemoryDbKeyStore();
    final missing = await preflightRegisteredWallet(
      'wallet_restored.sqlite',
      keyStore: keys,
      directory: () async => tmp,
    );
    expect(missing?.reason, 'wallet-file-missing');
    expect(keys.entries, isEmpty, reason: 'không bao giờ tạo khoá cho ví đã đăng ký bị mất');
    expect(tmp.listSync().whereType<File>().where((f) => f.path.endsWith('.sqlite')),
        isEmpty, reason: 'không tạo DB rỗng thay thế');

    File('${tmp.path}/wallet_restored.sqlite').writeAsBytesSync(List.filled(4096, 7));
    final keyLost = await preflightRegisteredWallet(
      'wallet_restored.sqlite',
      keyStore: keys,
      directory: () async => tmp,
    );
    expect(keyLost, isNotNull);
    expect(keys.entries, isEmpty);

    expect(
      await preflightRegisteredWallet('vi_nha_minh.sqlite', directory: () async => tmp),
      isNull,
    );
  });
}
