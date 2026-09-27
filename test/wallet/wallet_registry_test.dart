import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/data/local/wallet_descriptor.dart';
import 'package:vi_nha_minh/data/local/wallet_registry.dart';
import 'package:vi_nha_minh/domain/entities/wallet_access_scope.dart';
import 'package:vi_nha_minh/domain/entities/wallet_identity.dart';

WalletRegistryEntry _bound(String id, String account, {String? file}) =>
    WalletRegistryEntry(
      walletId: id,
      kind: WalletKind.personal,
      dbFileName: file ?? 'wallet_$id.sqlite',
      createdAt: DateTime.utc(2026, 9, 21),
      boundAccountId: account,
    );

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('wallet_registry_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('registry bền: ghi rồi nạp lại ra đúng descriptor', () async {
    final file = File('${tmp.path}/wallet_registry.json');
    final r1 = await WalletRegistry.load(FileWalletRegistryStorage(file));
    await r1.ensureLegacyLocal(() async => 'legacy-id');
    await r1.register(_bound('wa', 'A'));

    final r2 = await WalletRegistry.load(FileWalletRegistryStorage(file));
    expect(r2.entries.map((e) => e.walletId), ['legacy-id', 'wa']);
    final legacy = r2.byWalletId('legacy-id')!;
    expect(legacy.kind, WalletKind.local);
    expect(legacy.boundAccountId, isNull);
    expect(legacy.dbFileName, 'vi_nha_minh.sqlite');
    expect(r2.byWalletId('wa')!.boundAccountId, 'A');
    expect(File('${file.path}.tmp').existsSync(), isFalse);
  });

  test('ví LOCAL hiện có được đăng ký đúng 1 lần, retry idempotent', () async {
    final s = MemoryWalletRegistryStorage();
    final r = await WalletRegistry.load(s);
    var reads = 0;
    Future<String> read() async {
      reads++;
      return 'legacy-id';
    }

    final a = await r.ensureLegacyLocal(read);
    final b = await r.ensureLegacyLocal(read);
    final r2 = await WalletRegistry.load(s);
    final c = await r2.ensureLegacyLocal(read);
    expect(reads, 1, reason: 'đã đăng ký thì không đọc lại DB');
    expect([a.walletId, b.walletId, c.walletId], everyElement('legacy-id'));
    expect(r2.entries, hasLength(1));
  });

  test('register xung đột bị từ chối, đăng ký lại y hệt là no-op', () async {
    final r = WalletRegistry.inMemory();
    await r.register(_bound('wa', 'A'));
    await r.register(_bound('wa', 'A'));
    expect(r.entries, hasLength(1));
    expect(() => r.register(_bound('wa', 'B')), throwsStateError);
    expect(
      () => r.register(_bound('wa', 'A', file: 'other.sqlite')),
      throwsStateError,
    );
    expect(
      () => r.register(_bound('wx', 'A', file: 'wallet_wa.sqlite')),
      throwsStateError,
    );
  });

  test('tên file phải thuần; LOCAL không gắn Account, PERSONAL phải gắn', () {
    expect(
      () => _bound('w', 'A', file: '../vi_nha_minh.sqlite'),
      throwsArgumentError,
    );
    expect(() => _bound('w', 'A', file: r'a\b.sqlite'), throwsArgumentError);
    expect(
      () => WalletRegistryEntry(
        walletId: 'w',
        kind: WalletKind.local,
        dbFileName: 'x.sqlite',
        createdAt: DateTime.now(),
        boundAccountId: 'A',
      ),
      throwsArgumentError,
    );
    expect(
      () => WalletRegistryEntry(
        walletId: 'w',
        kind: WalletKind.personal,
        dbFileName: 'x.sqlite',
        createdAt: DateTime.now(),
      ),
      throwsArgumentError,
    );
  });

  test('registry hỏng ⇒ rỗng, không ném; dòng hỏng lẻ bị bỏ qua', () async {
    final bad = MemoryWalletRegistryStorage()..contents = '{not json';
    expect((await WalletRegistry.load(bad)).entries, isEmpty);

    final mixed = MemoryWalletRegistryStorage()
      ..contents = jsonEncode({
        'wallets': [
          _bound('wa', 'A').toJson(),
          {
            'walletId': 'evil',
            'kind': 'personal',
            'dbFileName': '../x',
            'createdAt': '2026-01-01T00:00:00Z',
            'boundAccountId': 'A',
          },
          'rác',
        ],
      });
    final r = await WalletRegistry.load(mixed);
    expect(r.entries.map((e) => e.walletId), ['wa']);
  });

  group('phạm vi truy cập', () {
    late WalletRegistry r;
    setUp(() async {
      r = WalletRegistry.inMemory();
      await r.ensureLegacyLocal(() async => 'L');
      await r.register(_bound('wa', 'A'));
      await r.register(_bound('wb', 'B'));
    });

    test('Account A không mở được ví của B, và ngược lại', () {
      final a = r.openableFor(const WalletAccessScope.account('A'));
      final b = r.openableFor(const WalletAccessScope.account('B'));
      expect(a.map((e) => e.walletId), ['L', 'wa']);
      expect(b.map((e) => e.walletId), ['L', 'wb']);
    });

    test('P8.2: đã đăng xuất vẫn mở được ví Personal trên máy (claim chỉ gắn quyền cloud)', () {
      final l = r.openableFor(const WalletAccessScope.local());
      expect(l.map((e) => e.walletId), ['L', 'wa', 'wb']);
      // Ví chưa claim vẫn là lựa chọn mặc định khi chưa đăng nhập.
      expect(r.resolveActive(const WalletAccessScope.local())!.walletId, 'L');
    });

    test('P8.2: reconcileBinding phản chiếu DB, giữ vị trí + createdAt, không trùng', () async {
      final storage = MemoryWalletRegistryStorage();
      final reg = await WalletRegistry.load(storage);
      final l = await reg.ensureLegacyLocal(() async => 'L', now: DateTime.utc(2026));
      final bound = await reg.reconcileBinding(
        walletId: 'L',
        dbFileName: l.dbFileName,
        boundAccountId: 'A',
      );
      expect(bound.kind, WalletKind.personal);
      expect(bound.createdAt, DateTime.utc(2026));
      final reloaded = await WalletRegistry.load(storage);
      expect(reloaded.entries.single.boundAccountId, 'A');
      // Đăng xuất: vẫn mở được; Account khác đăng nhập thì không chọn được ví này.
      expect(reloaded.resolveActive(const WalletAccessScope.local())!.walletId, 'L');
      expect(reloaded.openableFor(const WalletAccessScope.account('B')), isEmpty);
      final again = await reloaded.reconcileBinding(walletId: 'L', dbFileName: l.dbFileName);
      expect(again.isUnclaimedLocal, isTrue);
      expect((await WalletRegistry.load(storage)).entries.single.isUnclaimedLocal, isTrue);
      expect(
        () => reloaded.reconcileBinding(walletId: 'khac', dbFileName: l.dbFileName),
        throwsStateError,
      );
    });

    test('resolveActive: ưu tiên ví gắn Account, không vượt phạm vi', () {
      expect(r.resolveActive(const WalletAccessScope.account('A'))!.walletId, 'wa');
      expect(r.resolveActive(const WalletAccessScope.local())!.walletId, 'L');
      // Account C chưa có ví gắn ⇒ ví cục bộ chưa claim, không đụng ví A/B.
      expect(r.resolveActive(const WalletAccessScope.account('C'))!.walletId, 'L');
      // Ví được chọn nhưng thuộc Account khác ⇒ bị bỏ qua.
      expect(
        r
            .resolveActive(
              const WalletAccessScope.account('B'),
              preferredWalletId: 'wa',
            )!
            .walletId,
        'wb',
      );
      expect(
        r
            .resolveActive(
              const WalletAccessScope.account('A'),
              preferredWalletId: 'L',
            )!
            .walletId,
        'L',
      );
    });

    test('registry rỗng ⇒ null (provider rơi về ví cục bộ mặc định)', () {
      expect(
        WalletRegistry.inMemory().resolveActive(const WalletAccessScope.local()),
        isNull,
      );
      expect(WalletDescriptor.legacyLocal.dbFileName, 'vi_nha_minh.sqlite');
    });
  });

  test('P10: cờ Member/thu hồi bền qua JSON; thu hồi ⇒ ẩn với chính Account đó; mời lại ⇒ hiện', () async {
    final file = File('${tmp.path}/wallet_registry.json');
    final r1 = await WalletRegistry.load(FileWalletRegistryStorage(file));
    await r1.ensureLegacyLocal(() async => 'legacy-id');
    await r1.register(
      WalletRegistryEntry(
        walletId: 'fam',
        kind: WalletKind.family,
        dbFileName: 'wallet_fam.sqlite',
        createdAt: DateTime.utc(2026, 9, 27),
        boundAccountId: 'B',
        familyMember: true,
      ),
      activate: true,
    );
    const b = WalletAccessScope.account('B');
    expect(r1.resolveActive(b)!.walletId, 'fam');
    await r1.setFamilyFlags('fam', accessRevoked: true);
    final r2 = await WalletRegistry.load(FileWalletRegistryStorage(file));
    final e = r2.byWalletId('fam')!;
    expect((e.familyMember, e.accessRevoked, e.dbFileName), (true, true, 'wallet_fam.sqlite'));
    expect(e.canOpen(b), isFalse);
    expect(r2.resolveActive(b)!.walletId, 'legacy-id');
    expect(r2.deniesAll(b), isFalse);
    await r2.setFamilyFlags('fam', accessRevoked: false);
    expect(r2.resolveActive(b)!.walletId, 'fam');
    // Ví Family không mở khi đăng xuất / Account khác (khác Personal).
    expect(e.canOpen(const WalletAccessScope.local()), isFalse);
    expect(r2.byWalletId('fam')!.canOpen(const WalletAccessScope.account('Y')), isFalse);
  });
}
