import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/seed_defaults.dart';
import 'package:vi_nha_minh/data/local/wallet_registry.dart';
import 'package:vi_nha_minh/domain/auth/account_identity.dart';
import 'package:vi_nha_minh/domain/auth/auth_repository.dart';
import 'package:vi_nha_minh/domain/entities/wallet_access_scope.dart';
import 'package:vi_nha_minh/domain/entities/wallet_identity.dart';
import 'package:vi_nha_minh/presentation/features/wallet_access/wallet_access_gate.dart';
import 'package:vi_nha_minh/presentation/providers/auth_providers.dart';
import 'package:vi_nha_minh/presentation/providers/database_provider.dart';

/// Phase 4 — ngữ nghĩa đổi tài khoản trên CÙNG máy:
/// - Ví Family gắn Account A: A mở được; đăng xuất / Account X ⇒ ẨN (không mở DB nào,
///   không xoá, không chuyển quyền); A quay lại ⇒ đúng ví đó, đúng file, đúng walletId.
/// - Ví Personal đã claim: đăng xuất vẫn mở (P8.2); Account X ⇒ ẩn.
/// - Ví cục bộ chưa claim: không áp cổng Account.

AccountIdentity _acc(String uid) =>
    AccountIdentity(uid: uid, provider: AccountIdentity.providerGoogle, email: '$uid@x.test');

class _Auth implements AuthRepository {
  AccountIdentity? cur;
  final _c = StreamController<AccountIdentity?>.broadcast();
  @override
  bool get isAvailable => true;
  @override
  AccountIdentity? currentAccount() => cur;
  @override
  Stream<AccountIdentity?> watchAuthState() async* {
    yield cur;
    yield* _c.stream;
  }

  void as(String? uid) {
    cur = uid == null ? null : _acc(uid);
    _c.add(cur);
  }

  @override
  Future<AccountIdentity> signInWithGoogle() async => throw UnimplementedError();
  @override
  Future<void> signOut() async => as(null);
}

class _Probe extends ConsumerWidget {
  const _Probe();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(appDatabaseProvider);
    return Text('open:${ref.watch(activeWalletProvider).dbFileName}');
  }
}

void main() {
  group('registry', () {
    WalletRegistryEntry e(String id, WalletKind kind, String? owner) => WalletRegistryEntry(
      walletId: id,
      kind: kind,
      dbFileName: '$id.sqlite',
      createdAt: DateTime(2026),
      boundAccountId: owner,
    );
    const a = WalletAccessScope.account('A');
    const x = WalletAccessScope.account('X');
    const local = WalletAccessScope.local();

    test('Family gắn A: A mở; đăng xuất/X bị từ chối; A quay lại đúng ví', () {
      final r = WalletRegistry.inMemory([e('fam', WalletKind.family, 'A')]);
      expect(r.resolveActive(a)!.walletId, 'fam');
      expect(r.deniesAll(local), isTrue);
      expect(r.deniesAll(x), isTrue);
      expect(r.openableFor(x), isEmpty);
      expect(r.resolveActive(a)!.dbFileName, 'fam.sqlite');
    });

    test('Personal đã claim: đăng xuất vẫn mở; X bị từ chối', () {
      final r = WalletRegistry.inMemory([e('per', WalletKind.personal, 'A')]);
      expect(r.resolveActive(local)!.walletId, 'per');
      expect(r.deniesAll(x), isTrue);
    });

    test('ví cục bộ chưa claim: mọi phạm vi đều mở (không áp cổng Account)', () {
      final r = WalletRegistry.inMemory([e('loc', WalletKind.local, null)]);
      for (final s in [a, x, local]) {
        expect(r.resolveActive(s)!.walletId, 'loc');
      }
    });

    test('X có ví riêng + ví Family của A trên cùng máy ⇒ X chỉ thấy ví của X', () {
      final r = WalletRegistry.inMemory([
        e('fam', WalletKind.family, 'A'),
        e('xper', WalletKind.personal, 'X'),
      ]);
      expect(r.openableFor(x).map((w) => w.walletId), ['xper']);
      expect(r.resolveActive(a)!.walletId, 'fam');
    });

    test('registry rỗng (cài mới) không bị coi là từ chối', () {
      expect(WalletRegistry.inMemory().deniesAll(x), isFalse);
    });
  });

  group('app gate (máy chồng: Family gắn A; máy vợ: Family gắn B)', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('vnm_switch_'));
    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } on FileSystemException {
        /* Windows: file còn giữ bởi isolate test */
      }
    });

    Future<({_Auth auth, List<String> opened, String walletId, File file})> pumpDevice(
      WidgetTester tester,
      String owner,
    ) async {
      final file = File('${tmp.path}/fam_$owner.sqlite');
      final walletId = (await tester.runAsync(() async {
        final db = AppDatabase.forTesting(NativeDatabase(file), seed: SeedProfile.fresh);
        final id = (await db.select(db.walletMeta).getSingle()).walletId;
        await db.close();
        return id;
      }))!;
      final registry = WalletRegistry.inMemory([
        WalletRegistryEntry(
          walletId: walletId,
          kind: WalletKind.family,
          dbFileName: 'fam_$owner.sqlite',
          createdAt: DateTime(2026),
          boundAccountId: owner,
        ),
      ]);
      final auth = _Auth()..cur = _acc(owner);
      final opened = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            walletRegistryProvider.overrideWithValue(registry),
            walletDatabaseFactoryProvider.overrideWithValue((w) {
              opened.add(w.dbFileName);
              return AppDatabase.forTesting(
                NativeDatabase(File('${tmp.path}/${w.dbFileName}')),
              );
            }),
          ],
          child: const MaterialApp(home: WalletAccessGate(child: _Probe())),
        ),
      );
      await tester.pumpAndSettle();
      return (auth: auth, opened: opened, walletId: walletId, file: file);
    }

    Future<void> to(WidgetTester tester, _Auth auth, String? uid) async {
      auth.as(uid);
      await tester.pumpAndSettle();
    }

    testWidgets('chồng: A → đăng xuất → X → A: ẩn khi sai, DB không bị mở/xoá, cùng ví quay lại', (
      tester,
    ) async {
      final d = await pumpDevice(tester, 'A');
      expect(find.text('open:fam_A.sqlite'), findsOneWidget);
      expect(d.opened, ['fam_A.sqlite']);
      final bytes = d.file.readAsBytesSync();

      await to(tester, d.auth, null);
      expect(find.byKey(const Key('wallet_access_denied')), findsOneWidget);
      expect(find.textContaining('open:'), findsNothing);

      await to(tester, d.auth, 'X');
      expect(find.byKey(const Key('wallet_access_denied')), findsOneWidget);
      expect(d.opened, ['fam_A.sqlite'], reason: 'không mở DB nào cho X');
      expect(d.file.existsSync(), isTrue);
      expect(d.file.readAsBytesSync(), bytes, reason: 'không xoá/không ghi');

      // X tự đăng xuất ngay trên màn chặn.
      await tester.tap(find.byKey(const Key('wallet_access_sign_out')));
      await tester.pumpAndSettle();
      expect(d.auth.cur, isNull);

      await to(tester, d.auth, 'A');
      expect(find.text('open:fam_A.sqlite'), findsOneWidget);
      expect(d.opened, ['fam_A.sqlite', 'fam_A.sqlite'], reason: 'cùng file, không khôi phục lại');
      final id = await tester.runAsync(() async {
        final db = AppDatabase.forTesting(NativeDatabase(d.file));
        final w = (await db.select(db.walletMeta).getSingle()).walletId;
        await db.close();
        return w;
      });
      expect(id, d.walletId);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('vợ: B → Y → B: ẩn với Y, quay lại đúng ví', (tester) async {
      final d = await pumpDevice(tester, 'B');
      expect(find.text('open:fam_B.sqlite'), findsOneWidget);
      await to(tester, d.auth, 'Y');
      expect(find.byKey(const Key('wallet_access_denied')), findsOneWidget);
      expect(d.opened, ['fam_B.sqlite']);
      await to(tester, d.auth, 'B');
      expect(find.text('open:fam_B.sqlite'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
