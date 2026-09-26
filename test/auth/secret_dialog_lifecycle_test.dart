import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/config/app_environment.dart';
import 'package:vi_nha_minh/data/backup/backup_key_store.dart';
import 'package:vi_nha_minh/data/backup/backup_service.dart';
import 'package:vi_nha_minh/domain/auth/cloud_session.dart';
import 'package:vi_nha_minh/l10n/session_localizations.dart';
import 'package:vi_nha_minh/presentation/features/settings/backup_controls.dart';
import 'package:vi_nha_minh/presentation/features/settings/session_controls.dart';

import 'cloud_session_test.dart' show MemoryStorage;

class _Keys implements BackupKeyStore {
  @override
  Future<({String walletId, Uint8List bmk})?> load(String uid) async => null;
  @override
  Future<void> store(String uid, String walletId, Uint8List bmk) async {}
  @override
  Future<void> clear() async {}
}

/// Regression (Pixel DEV 2026-09-26, red screen `_dependents.isEmpty`): the
/// secret dialog's TextEditingController was disposed right after pop while
/// the TextField was still mounted in the exit animation; the keyboard closing
/// (view insets change) rebuilt it with a disposed controller.
void main() {
  testWidgets('lost-device dialog survives keyboard closing during exit animation', (t) async {
    final session = CloudSession(MemoryStorage(), (op, data) async {
      if (op == 'activateSession') throw const SessionFailure(false, 'TAKEOVER_REQUIRED');
      if (op == 'listBackupWallets') return {'walletIds': ['fixture-wallet-01']};
      throw const SessionFailure(true);
    }, () => 'account');
    final backup = BackupService(
      session: session,
      transport: session.transport,
      keyStore: _Keys(),
      env: AppEnvironment.dev,
    );
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: SessionLocalizations.localizationsDelegates,
      supportedLocales: SessionLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(
        child: SessionControls(session: session, backup: backup, stepUp: () async => false),
      )),
    ));
    await t.tap(find.text('Activate this device'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Activate this device'));
    await t.pumpAndSettle();
    await t.tap(find.text('Old device is lost'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('lost_device_secret')), 'Tiền chợ sáng nay');
    t.view.viewInsets = const FakeViewPadding(bottom: 800);
    addTearDown(t.view.resetViewInsets);
    await t.pump();
    await t.tap(find.text('Recover'));
    await t.pump();
    // Keyboard closes while the dialog is still animating out.
    t.view.viewInsets = FakeViewPadding.zero;
    await t.pump(const Duration(milliseconds: 16));
    await t.pump(const Duration(milliseconds: 100));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('Verification was not completed.'), findsOneWidget);
  });

  testWidgets('backup password dialog survives keyboard closing during exit animation', (t) async {
    final session = CloudSession(MemoryStorage(), (op, data) async => {}, () => 'account');
    final backup = BackupService(session: session, transport: session.transport,
        keyStore: _Keys(), env: AppEnvironment.dev);
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: SessionLocalizations.localizationsDelegates,
      supportedLocales: SessionLocalizations.supportedLocales,
      home: Scaffold(body: BackupControls(backup: backup)),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Enable backup'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('backup_password_0')), 'Tiền chợ sáng nay');
    // Mismatched repeat: fails before any key derivation (keeps the test fast).
    await t.enterText(find.byKey(const Key('backup_password_1')), 'Tiền chợ sáng mai');
    t.view.viewInsets = const FakeViewPadding(bottom: 800);
    addTearDown(t.view.resetViewInsets);
    await t.pump();
    await t.tap(find.text('Done'));
    await t.pump();
    t.view.viewInsets = FakeViewPadding.zero;
    await t.pump(const Duration(milliseconds: 16));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('Backup action failed.'), findsOneWidget);
  });

  testWidgets('backup card reflects BMK wipe when the device is revoked', (t) async {
    final session = CloudSession(MemoryStorage(), (op, data) async => {}, () => 'account');
    final keys = _MemoryKeys();
    await keys.store('account', 'fixture-wallet-01', Uint8List(32));
    final backup = BackupService(session: session, transport: session.transport,
        keyStore: keys, env: AppEnvironment.dev);
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: SessionLocalizations.localizationsDelegates,
      supportedLocales: SessionLocalizations.supportedLocales,
      home: Scaffold(body: BackupControls(backup: backup)),
    ));
    await t.pumpAndSettle();
    expect(find.textContaining('Enabled.'), findsOneWidget);
    await session.handleRevoked();
    await t.pumpAndSettle();
    expect(find.textContaining('Not enabled'), findsOneWidget);
  });
}

class _MemoryKeys implements BackupKeyStore {
  ({String walletId, Uint8List bmk})? value;
  @override
  Future<({String walletId, Uint8List bmk})?> load(String uid) async => value;
  @override
  Future<void> store(String uid, String walletId, Uint8List bmk) async =>
      value = (walletId: walletId, bmk: bmk);
  @override
  Future<void> clear() async => value = null;
}
