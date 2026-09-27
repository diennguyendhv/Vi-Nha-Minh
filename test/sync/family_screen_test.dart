import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/config/app_environment.dart';
import 'package:vi_nha_minh/data/cloud/family_device_key_store.dart';
import 'package:vi_nha_minh/data/cloud/family_service.dart';
import 'package:vi_nha_minh/data/local/wallet_registry.dart';
import 'package:vi_nha_minh/domain/entities/wallet_identity.dart';
import 'package:vi_nha_minh/l10n/session_localizations.dart';
import 'package:vi_nha_minh/presentation/features/settings/family_screen.dart';
import 'package:vi_nha_minh/presentation/providers/database_provider.dart';
import 'package:vi_nha_minh/presentation/providers/sync_provider.dart';

import '../support/fake_cloud.dart';

/// P10 DEV UI: "Chia sẻ với gia đình" nâng ví tại chỗ; "Chia sẻ với vợ/chồng" KHÔNG
/// chọn sẵn thành viên (nút tiếp tục khoá tới khi chọn + nhập email), xác nhận rõ ràng,
/// step-up rồi mới gọi máy chủ; mã mời hiện 1 lần để gửi.
void main() {
  testWidgets('Owner: nâng ví → mời vợ/chồng (không chọn sẵn) → mã mời', (tester) async {
    final cloud = FakeCloud()..emails['uid-a'] = 'chong@test.dev';
    late FakeDevice a;
    late String walletId;
    late WalletRegistry registry;
    late FamilyService service;
    await tester.runAsync(() async {
      a = FakeDevice(cloud);
      await a.signIn('uid-a');
      final members = await a.db.select(a.db.financialMemberRows).get();
      await a.claim(selfMemberId: members.first.memberId);
      await a.engine.enableBackup('Mật khẩu gia đình UI');
      await a.engine.push();
      walletId = await a.walletId();
      registry = WalletRegistry.inMemory([
        WalletRegistryEntry(
          walletId: walletId,
          kind: WalletKind.personal,
          dbFileName: 'wallet_a.sqlite',
          createdAt: DateTime(2026),
          boundAccountId: 'uid-a',
        ),
      ]);
      service = FamilyService(
        session: a.session,
        transport: cloud.call,
        keyStore: a.keys,
        deviceKeys: MemoryFamilyDeviceKeyStore(),
        registry: registry,
        db: a.db,
        dbFileName: 'wallet_a.sqlite',
        env: AppEnvironment.dev,
      );
    });
    var stepUps = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyServiceProvider.overrideWithValue(service),
          appDatabaseProvider.overrideWithValue(a.db),
          walletRegistryProvider.overrideWithValue(registry),
          walletAccessDeniedProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          locale: const Locale('vi'),
          localizationsDelegates: SessionLocalizations.localizationsDelegates,
          supportedLocales: SessionLocalizations.supportedLocales,
          home: FamilyScreen(
            stepUp: () async {
              stepUps++;
              return true;
            },
          ),
        ),
      ),
    );

    Future<void> settle(Finder f) async {
      for (var i = 0; i < 100 && f.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }
      expect(f, findsWidgets);
    }

    await settle(find.byKey(const Key('family_promote')));
    await tester.tap(find.byKey(const Key('family_promote')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('family_confirm')));
    await tester.pump();
    await settle(find.byKey(const Key('family_invite')));
    expect(cloud.wallets[walletId]!['kind'], 'family');
    expect(registry.byWalletId(walletId)!.kind, WalletKind.family);
    expect(stepUps, 1);

    await tester.tap(find.byKey(const Key('family_invite')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 400));
    final next = find.byKey(const Key('family_invite_next'));
    FilledButton button() => tester.widget<FilledButton>(next);
    // Không có lựa chọn mặc định: chỉ 1 ứng viên (không phải Owner), chưa được chọn.
    expect(button().onPressed, isNull);
    await tester.enterText(find.byKey(const Key('family_invite_email')), 'vo@test.dev');
    await tester.pump();
    expect(button().onPressed, isNull, reason: 'chưa chọn thành viên');
    final choice = find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('family_invite_member_'),
    );
    expect(choice, findsOneWidget);
    await tester.tap(choice);
    await tester.pump();
    expect(button().onPressed, isNotNull);
    await tester.tap(next);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('family_confirm')));
    await tester.pump();
    await settle(find.byKey(const Key('family_invite_token')));
    expect(stepUps, 2);
    expect(cloud.invites.values.single['email'], 'vo@test.dev');
    await tester.runAsync(() => a.db.close());
  });
}
