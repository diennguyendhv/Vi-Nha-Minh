import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/config/app_environment.dart';
import 'package:vi_nha_minh/data/cloud/wallet_claim_service.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/sync/cloud_binding_store.dart';
import 'package:vi_nha_minh/data/local/wallet_registry.dart';
import 'package:vi_nha_minh/domain/auth/cloud_session.dart';
import 'package:vi_nha_minh/domain/entities/cloud_binding.dart';
import 'package:vi_nha_minh/l10n/session_localizations.dart';
import 'package:vi_nha_minh/presentation/features/settings/wallet_claim_controls.dart';

import '../auth/cloud_session_test.dart' show MemoryStorage;

/// P8.2 UX: đăng nhập KHÔNG bao giờ tự claim; phải bấm "Sao lưu ví này", tự chọn
/// thành viên (không mặc định), đọc màn xác nhận rồi mới gửi.
void main() {
  late AppDatabase db;
  late List<Map<String, dynamic>> sent;
  late WalletClaimService service;
  var stepUps = 0;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sent = [];
    stepUps = 0;
    final storage = MemoryStorage();
    await storage.write('acc-A', {
      'accountId': 'acc-A',
      'installationId': await storage.installationId(),
      'generation': 1,
      'epoch': 1,
      'secret': 's' * 43,
    });
    Future<Map<String, dynamic>> server(
      String op,
      Map<String, dynamic> d,
    ) async {
      sent.add({'op': op, ...d});
      return {
        'claimed': true,
        'walletId': d['walletId'],
        'selfMemberId': d['selfMemberId'],
        'claimRequestId': d['claimRequestId'],
        'headRev': 0,
      };
    }

    service = WalletClaimService(
      session: CloudSession(storage, server, () => 'acc-A'),
      transport: server,
      db: db,
      registry: WalletRegistry.inMemory(),
      dbFileName: 'vi_nha_minh.sqlite',
      env: AppEnvironment.dev,
    );
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: SessionLocalizations.localizationsDelegates,
        supportedLocales: SessionLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: WalletClaimControls(
              service: service,
              accountLabel: 'owner@example.com',
              stepUp: () async {
                stepUps++;
                return true;
              },
            ),
          ),
        ),
      ),
    );
    await settle(t);
  }

  testWidgets(
    'đăng nhập + mở màn hình KHÔNG claim; huỷ ở bất kỳ bước nào không gửi gì',
    (t) async {
      await pump(t);
      expect(find.textContaining('lives only on this device'), findsOneWidget);
      expect(sent, isEmpty);

      await t.tap(find.byKey(const Key('claim_start')));
      await settle(t);
      expect(find.text('Who are you in this Wallet?'), findsOneWidget);
      // Không lựa chọn mặc định ⇒ Tiếp tục bị khoá.
      final next = find.byKey(const Key('claim_member_next'));
      expect(t.widget<FilledButton>(next).onPressed, isNull);
      await t.tap(find.text('Cancel'));
      await settle(t);

      await t.tap(find.byKey(const Key('claim_start')));
      await settle(t);
      await t.tap(find.byKey(const Key('claim_member_chong')));
      await t.pump();
      await t.tap(find.byKey(const Key('claim_member_next')));
      await settle(t);
      await t.tap(find.text('Cancel'));
      await settle(t);
      expect(sent, isEmpty);
      expect(stepUps, 0);
      expect(await t.runAsync(() => CloudBindingStore(db).read()), isNull);
    },
  );

  testWidgets(
    'chưa có phiên P7.1 ⇒ không mở "Bạn là ai?", báo kích hoạt thiết bị',
    (t) async {
      await t.runAsync(() => service.session.storage.clear());
      await pump(t);
      await t.tap(find.byKey(const Key('claim_start')));
      await settle(t);
      expect(find.text('Who are you in this Wallet?'), findsNothing);
      expect(
        find.textContaining('Activate this device for cloud first'),
        findsOneWidget,
      );
      expect(sent, isEmpty);
      expect(stepUps, 0);
    },
  );

  testWidgets(
    'chọn thành viên → xác nhận rõ hệ quả → step-up → claim đúng thành viên',
    (t) async {
      await pump(t);
      await t.tap(find.byKey(const Key('claim_start')));
      await settle(t);
      await t.tap(find.byKey(const Key('claim_member_chong')));
      await t.pump();
      await t.tap(find.byKey(const Key('claim_member_next')));
      await settle(t);
      final body = t
          .widget<Text>(find.byKey(const Key('claim_confirm_body')))
          .data!;
      expect(body, contains('owner@example.com'));
      expect(body, contains('Chồng'));
      expect(body, contains('NO financial data'));
      expect(body, contains('does not hide or delete'));

      await t.tap(find.byKey(const Key('claim_confirm')));
      await settle(t);
      expect(stepUps, 1);
      expect(sent.map((r) => r['op']), ['claimWallet']);
      expect(sent.single['selfMemberId'], 'chong');
      final binding = await t.runAsync(() => CloudBindingStore(db).read());
      expect(binding!.state, CloudBindingState.active);
      expect(find.textContaining('you are Chồng'), findsOneWidget);
    },
  );

  Future<void> pumpRole(
    WidgetTester t,
    WalletClaimService svc,
    FamilyWalletRole? role,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: SessionLocalizations.localizationsDelegates,
        supportedLocales: SessionLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: WalletClaimControls(
              key: const ValueKey('claim-acc-A'),
              service: svc,
              accountLabel: 'member@example.com',
              familyRole: role,
            ),
          ),
        ),
      ),
    );
    await settle(t);
  }

  testWidgets(
    'P10 Member: hiện vai trò Thành viên, không "đăng ký với tài khoản này", '
    'không có thao tác đăng ký/huỷ',
    (t) async {
      await t.runAsync(() => service.claim('vo'));
      sent.clear();
      await pumpRole(t, service, FamilyWalletRole.member);
      final status = t
          .widget<Text>(find.byKey(const Key('claim_status')))
          .data!;
      expect(status, contains('Member of this Family Wallet'));
      expect(status, contains('you are Vợ'));
      expect(status, contains('Owner manages members and the backup keys'));
      expect(status, isNot(contains('registered to this account')));
      expect(status, isNot(contains('not linked')));
      expect(find.text('Family Wallet'), findsOneWidget);
      expect(find.text('Back up this Wallet'), findsNothing);
      expect(find.byKey(const Key('claim_abandon')), findsNothing);
      expect(find.byKey(const Key('claim_check')), findsNothing);
      expect(find.byKey(const Key('claim_start')), findsNothing);
      expect(sent, isEmpty, reason: 'chỉ đọc DB cục bộ, không gọi mạng');
    },
  );

  testWidgets('P10 Owner: hiện vai trò Chủ ví', (t) async {
    await t.runAsync(() => service.claim('chong'));
    await pumpRole(t, service, FamilyWalletRole.owner);
    final status = t.widget<Text>(find.byKey(const Key('claim_status'))).data!;
    expect(status, contains('Owner of this Family Wallet'));
    expect(status, contains('you are Chồng'));
    expect(find.byKey(const Key('claim_abandon')), findsNothing);
  });

  testWidgets(
    'đổi ví đang mở (Member vừa tham gia) ⇒ đọc lại, không giữ "chưa gắn" '
    'của ví cũ',
    (t) async {
      // Ví cục bộ lúc cài: chưa gắn.
      await pumpRole(t, service, null);
      expect(find.textContaining('lives only on this device'), findsOneWidget);

      // Ví Family MỚI (khôi phục cho Member) trên DB khác, binding ACTIVE của acc-A.
      final db2 = AppDatabase.forTesting(NativeDatabase.memory());
      final service2 = WalletClaimService(
        session: service.session,
        transport: (op, d) async => {
          'claimed': true,
          'walletId': d['walletId'],
          'selfMemberId': d['selfMemberId'],
          'claimRequestId': d['claimRequestId'],
          'headRev': 0,
        },
        db: db2,
        registry: WalletRegistry.inMemory(),
        dbFileName: 'wallet_family.sqlite',
        env: AppEnvironment.dev,
      );
      await t.runAsync(() => service2.claim('vo'));
      await pumpRole(t, service2, FamilyWalletRole.member);
      expect(find.textContaining('lives only on this device'), findsNothing);
      expect(
        find.textContaining('Member of this Family Wallet'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
      await t.runAsync(db2.close);
    },
  );
}

/// DB thật trong bộ nhớ: cho các Future của Drift chạy xong rồi dựng lại khung hình.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pumpAndSettle();
  }
}
