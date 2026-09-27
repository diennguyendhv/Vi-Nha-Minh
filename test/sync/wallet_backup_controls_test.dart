import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/data/local/sync/sync_capture.dart';
import 'package:vi_nha_minh/data/sync/sync_worker.dart';
import 'package:vi_nha_minh/l10n/session_localizations.dart';
import 'package:vi_nha_minh/presentation/features/settings/wallet_backup_controls.dart';

import '../support/fake_cloud.dart';

/// P8.3 DEV UI: chỉ hiện cho ví đã claim ACTIVE; bật sao lưu ⇒ Recovery Key hiện đúng
/// 1 lần (không đóng được trước khi xác nhận) ⇒ worker tải mốc nền ⇒ COMPLETE.
void main() {
  Widget host(Widget child) => MaterialApp(
    locale: const Locale('vi'),
    localizationsDelegates: SessionLocalizations.localizationsDelegates,
    supportedLocales: SessionLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  late StreamController<WalletBackupStatus> status;
  late FakeDevice a;

  /// Thay Drift `watch`: đọc lại trạng thái thật từ DB rồi đẩy vào stream.
  Future<void> waitFor(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 200 && f.evaluate().isEmpty; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        status.add(await WalletBackupStatus.read(a.db));
      });
      await tester.pump();
    }
    expect(f, findsOneWidget);
  }

  testWidgets(
    'chưa claim ⇒ fallback; claim ⇒ bật sao lưu, Recovery Key 1 lần, COMPLETE',
    (tester) async {
      final cloud = FakeCloud();
      a = FakeDevice(cloud);
      status = StreamController<WalletBackupStatus>.broadcast();
      final worker = SyncWorker(
        engine: a.engine,
        db: a.db,
        debounce: const Duration(milliseconds: 20),
      );
      await tester.runAsync(() => a.signIn('uid-ui'));
      await tester.pumpWidget(
        host(
          WalletBackupControls(
            engine: a.engine,
            worker: worker,
            fallback: const Text('fixture-fallback'),
            status: status.stream,
          ),
        ),
      );
      await waitFor(tester, find.text('fixture-fallback'));

      await tester.runAsync(a.claim);
      await waitFor(tester, find.byKey(const Key('wallet_backup_enable')));
      expect(find.text('fixture-fallback'), findsNothing);

      await tester.tap(find.byKey(const Key('wallet_backup_enable')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('backup_password_0')),
        'Mật khẩu UI dài',
      );
      await tester.enterText(
        find.byKey(const Key('backup_password_1')),
        'Mật khẩu UI dài',
      );
      await tester.tap(find.text('Xong').last);
      await tester.pump();
      await waitFor(tester, find.byKey(const Key('recovery_key_text')));

      // Không đóng được trước khi xác nhận đã lưu.
      await tester.pumpAndSettle();
      final done = find.widgetWithText(FilledButton, 'Xong');
      expect(tester.widget<FilledButton>(done).onPressed, isNull);
      await tester.tap(find.byKey(const Key('recovery_key_saved')));
      await tester.pump();
      await tester.tap(done);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recovery_key_text')), findsNothing);

      // Worker (start sau khi bật) tải mốc nền ⇒ outbox rỗng, COMPLETE.
      await tester.runAsync(() async {
        for (
          var i = 0;
          i < 100 && await a.engine.backupState() != 'COMPLETE';
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      expect(await tester.runAsync(a.engine.backupState), 'COMPLETE');
      expect(await tester.runAsync(SyncOutboxStore(a.db).count), 0);
      await waitFor(tester, find.textContaining('Đã sao lưu'));
      expect(find.byKey(const Key('wallet_backup_enable')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await status.close();
        await worker.dispose();
        await a.db.close();
      });
    },
  );
}
