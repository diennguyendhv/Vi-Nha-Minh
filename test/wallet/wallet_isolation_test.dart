import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/seed_defaults.dart';
import 'package:vi_nha_minh/data/local/wallet_descriptor.dart';
import 'package:vi_nha_minh/data/local/wallet_registry.dart';
import 'package:vi_nha_minh/data/repositories/local_wallet_identity_repository.dart';
import 'package:vi_nha_minh/domain/auth/account_identity.dart';
import 'package:vi_nha_minh/domain/auth/auth_repository.dart';
import 'package:vi_nha_minh/domain/entities/wallet_identity.dart';
import 'package:vi_nha_minh/presentation/providers/app_state_providers.dart';
import 'package:vi_nha_minh/presentation/providers/auth_providers.dart';
import 'package:vi_nha_minh/presentation/providers/database_provider.dart';
import 'package:vi_nha_minh/presentation/providers/fund_providers.dart';
import 'package:vi_nha_minh/presentation/providers/primary_fund_provider.dart';

AccountIdentity _acc(String uid) => AccountIdentity(
  uid: uid,
  provider: AccountIdentity.providerGoogle,
  email: '$uid@x.test',
);

class _SwitchableAuth implements AuthRepository {
  AccountIdentity? _cur;
  final _c = StreamController<AccountIdentity?>.broadcast();
  @override
  bool get isAvailable => true;
  @override
  AccountIdentity? currentAccount() => _cur;
  @override
  Stream<AccountIdentity?> watchAuthState() async* {
    yield _cur;
    yield* _c.stream;
  }

  void as(AccountIdentity? a) {
    _cur = a;
    _c.add(a);
  }

  @override
  Future<AccountIdentity> signInWithGoogle() async =>
      throw UnimplementedError();
  @override
  Future<void> signOut() async => as(null);
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  late Directory tmp;
  late _SwitchableAuth auth;
  late WalletRegistry registry;
  late ProviderContainer c;
  final opened = <String, List<AppDatabase>>{};
  final walletIds = <String, String>{};

  Future<void> markFund(String file, String name) async {
    final db = AppDatabase.forTesting(
      NativeDatabase(File('${tmp.path}/$file')),
      seed: SeedProfile.fresh,
    );
    await db
        .into(db.fundRows)
        .insert(
          FundRowsCompanion.insert(
            id: 'f-$name',
            name: name,
            colorValue: 0,
            isActive: const Value(true),
          ),
        );
    walletIds[file] = (await db.select(db.walletMeta).getSingle()).walletId;
    await db.close();
  }

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('wallet_iso_');
    opened.clear();
    walletIds.clear();
    await markFund('vi_nha_minh.sqlite', 'QUY-LOCAL');
    await markFund('wa.sqlite', 'QUY-A');
    await markFund('wb.sqlite', 'QUY-B');
    registry = WalletRegistry.inMemory();
    await registry.ensureLegacyLocal(
      () async => walletIds['vi_nha_minh.sqlite']!,
    );
    for (final e in [('wa', 'A'), ('wb', 'B')]) {
      await registry.register(
        WalletRegistryEntry(
          walletId: walletIds['${e.$1}.sqlite']!,
          kind: WalletKind.personal,
          dbFileName: '${e.$1}.sqlite',
          createdAt: DateTime.utc(2026, 9, 21),
          boundAccountId: e.$2,
        ),
      );
    }
    auth = _SwitchableAuth();
    SharedPreferences.setMockInitialValues({});
    c = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        walletRegistryProvider.overrideWithValue(registry),
        walletDatabaseFactoryProvider.overrideWithValue((w) {
          final db = AppDatabase.forTesting(
            NativeDatabase(File('${tmp.path}/${w.dbFileName}')),
            seed: SeedProfile.fresh,
          );
          opened.putIfAbsent(w.dbFileName, () => []).add(db);
          return db;
        }),
      ],
    );
    // Giữ accountProvider sống như UI thật.
    c.listen(accountProvider, (_, _) {});
    await _settle();
  });

  tearDown(() async {
    c.dispose();
    for (final dbs in opened.values) {
      for (final db in dbs) {
        await db.close(); // idempotent; nhả khoá file trên Windows
      }
    }
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows đôi khi giữ khoá thêm chút; thư mục tạm không ảnh hưởng kết quả.
    }
  });

  Future<List<String>> fundNames() async =>
      (await c.read(fundRepositoryProvider).watchFunds().first)
          .map((f) => f.name)
          .toList();

  Future<String> activeWalletId() async =>
      (await c.read(walletIdentityProvider.future)).walletId;

  test('chưa đăng nhập: ví cục bộ mở bình thường, không thấy quỹ ví Account', () async {
    final names = await fundNames();
    expect(names, contains('QUY-LOCAL'));
    expect(names, isNot(contains('QUY-A')));
    expect(c.read(activeWalletProvider).dbFileName, 'vi_nha_minh.sqlite');
    expect(await activeWalletId(), walletIds['vi_nha_minh.sqlite']);
  });

  test('A → B → A: mỗi Account chỉ thấy ví của mình; DB cũ được đóng', () async {
    auth.as(_acc('A'));
    await _settle();
    expect(await fundNames(), contains('QUY-A'));
    final dbA = opened['wa.sqlite']!.last;

    auth.as(_acc('B'));
    await _settle();
    final namesB = await fundNames();
    expect(namesB, contains('QUY-B'));
    expect(namesB, isNot(contains('QUY-A')), reason: 'không rò dòng ví A sang B');
    expect(c.read(activeWalletProvider).dbFileName, 'wb.sqlite');
    // DB của A đã đóng: mọi truy vấn qua nó phải lỗi.
    await expectLater(dbA.select(dbA.fundRows).get(), throwsA(anything));

    auth.as(_acc('A'));
    await _settle();
    expect(await fundNames(), contains('QUY-A'));
    expect(await activeWalletId(), walletIds['wa.sqlite']);
  });

  test('B không thể chọn ví của A qua bộ chọn ví', () async {
    auth.as(_acc('B'));
    await _settle();
    c.read(selectedWalletIdProvider.notifier).state = walletIds['wa.sqlite'];
    expect(c.read(activeWalletProvider).dbFileName, 'wb.sqlite');
  });

  test('đăng xuất: xoá lựa chọn ví theo Account, giữ file ví, về cục bộ', () async {
    auth.as(_acc('A'));
    await _settle();
    c.read(selectedWalletIdProvider.notifier).state = walletIds['wa.sqlite'];
    expect(c.read(selectedWalletIdProvider), isNotNull);

    await c.read(authRepositoryProvider).signOut();
    await _settle();
    expect(c.read(selectedWalletIdProvider), isNull);
    expect(c.read(activeWalletProvider).dbFileName, 'vi_nha_minh.sqlite');
    for (final f in ['vi_nha_minh.sqlite', 'wa.sqlite', 'wb.sqlite']) {
      expect(File('${tmp.path}/$f').existsSync(), isTrue, reason: f);
    }
    expect(await fundNames(), isNot(contains('QUY-A')));
    // Dữ liệu ví A còn nguyên khi A đăng nhập lại.
    auth.as(_acc('A'));
    await _settle();
    expect(await fundNames(), contains('QUY-A'));
  });

  test('state theo ví (quỹ chính, tab) reset khi đổi ví', () async {
    c.read(currentTabProvider.notifier).state = AppTab.summary;
    await c.read(primaryFundIdProvider.notifier).select('f-QUY-LOCAL');
    expect(c.read(primaryFundIdProvider), 'f-QUY-LOCAL');

    auth.as(_acc('A'));
    await _settle();
    expect(c.read(currentTabProvider), AppTab.home);
    expect(c.read(primaryFundIdProvider), isNot('f-QUY-LOCAL'));
  });

  test('chỉ đăng nhập (Account chưa có ví) KHÔNG đổi/đóng ví cục bộ, KHÔNG claim', () async {
    final before = await activeWalletId();
    final dbBefore = c.read(appDatabaseProvider);
    final entriesBefore = registry.entries
        .map((e) => e.toJson().toString())
        .toList();

    auth.as(_acc('C')); // Account chưa có ví nào
    await _settle();

    expect(
      identical(c.read(appDatabaseProvider), dbBefore),
      isTrue,
      reason: 'không đóng/mở lại DB khi chỉ đăng nhập',
    );
    expect(await activeWalletId(), before);
    expect(
      registry.entries.map((e) => e.toJson().toString()),
      entriesBefore,
      reason: 'registry không đổi: không gắn Account, không đổi kind',
    );
    final local = registry.byWalletId(before)!;
    expect(local.boundAccountId, isNull);
    expect(local.kind, WalletKind.local);

    final identity = await LocalWalletIdentityRepository(
      c.read(appDatabaseProvider),
    ).read();
    expect(identity.walletId, before);
    expect(identity.kind, WalletKind.local);
    expect(opened['vi_nha_minh.sqlite'], hasLength(1));
  });

  test('khoá quỹ chính: ví cục bộ giữ khoá cũ, ví khác theo walletId', () {
    expect(
      PrimaryFundStorage.keyFor(WalletDescriptor.legacyLocal),
      'primary_fund_id',
    );
    expect(
      PrimaryFundStorage.keyFor(
        const WalletDescriptor(
          walletId: 'W1',
          kind: WalletKind.personal,
          dbFileName: 'w1.sqlite',
        ),
      ),
      'primary_fund_id.W1',
    );
  });

  test('prefs thiết bị (sắp xếp, khoá) không bị chạm khi đăng xuất', () async {
    SharedPreferences.setMockInitialValues({
      'explorer_sort': 'x',
      'primary_fund_id': 'an_uong',
    });
    final prefs = await SharedPreferences.getInstance();
    auth.as(_acc('A'));
    await _settle();
    await c.read(authRepositoryProvider).signOut();
    await _settle();
    expect(prefs.getString('explorer_sort'), 'x');
    expect(prefs.getString('primary_fund_id'), 'an_uong');
  });
}
