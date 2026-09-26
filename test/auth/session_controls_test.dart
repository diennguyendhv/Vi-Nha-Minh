import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/auth/cloud_session.dart';
import 'package:vi_nha_minh/l10n/session_localizations.dart';
import 'package:vi_nha_minh/presentation/features/settings/session_controls.dart';

import 'cloud_session_test.dart' show MemoryStorage;

void main() {
  takeoverTests();
  testWidgets(
    'activation requires confirmation; stale and offline never report active',
    (t) async {
      final operations = <String>[];
      var denied = false;
      var offline = false;
      final session = CloudSession(MemoryStorage(), (op, data) async {
        operations.add(op);
        if (offline) throw const SessionFailure(false);
        if (denied) throw const SessionFailure(true);
        return op == 'activateSession'
            ? {'generation': 1, 'secret': 'a' * 43}
            : {'allowed': true};
      }, () => 'account');
      await t.pumpWidget(
        MaterialApp(
          localizationsDelegates: SessionLocalizations.localizationsDelegates,
          supportedLocales: SessionLocalizations.supportedLocales,
          home: Scaffold(body: SessionControls(session: session)),
        ),
      );
      await t.pumpAndSettle();
      expect(operations, isEmpty);
      await t.tap(find.text('Activate this device'));
      await t.pumpAndSettle();
      expect(operations, isEmpty);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(operations, isEmpty);
      await t.tap(find.text('Activate this device'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Activate this device'));
      await t.pumpAndSettle();
      expect(operations, ['activateSession', 'protectedPing']);
      expect(
        find.text('Session accepted by server at last check.'),
        findsOneWidget,
      );
      denied = true;
      await t.tap(find.text('Check cloud session'));
      await t.pumpAndSettle();
      expect(find.textContaining('No current cloud session'), findsOneWidget);
      offline = true;
      await t.tap(find.text('Check cloud session'));
      await t.pumpAndSettle();
      expect(find.textContaining('could not be verified'), findsOneWidget);
      expect(operations.where((o) => o == 'activateSession').length, 1);
    },
  );
}

Future<void> _pump(WidgetTester t, CloudSession session, {StepUp? stepUp}) async {
  await t.pumpWidget(
    MaterialApp(
      localizationsDelegates: SessionLocalizations.localizationsDelegates,
      supportedLocales: SessionLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SessionControls(session: session, stepUp: stepUp),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void takeoverTests() {
  testWidgets('P7.1: TAKEOVER_REQUIRED → request shows code; finish waits for approval', (t) async {
    final operations = <String>[];
    var approved = false;
    final session = CloudSession(MemoryStorage(), (op, data) async {
      operations.add(op);
      switch (op) {
        case 'activateSession':
          throw const SessionFailure(false, 'TAKEOVER_REQUIRED');
        case 'requestTakeover':
          return {'requestId': 'r' * 43, 'requestSecret': 's' * 43, 'code': '482913',
            'expiresAt': 1 << 42};
        case 'completeTakeover':
          if (!approved) throw const SessionFailure(false, 'TAKEOVER_PENDING');
          expect(data['requestSecret'], 's' * 43);
          return {'generation': 2, 'epoch': 1, 'secret': 'b' * 43};
      }
      return {'allowed': true};
    }, () => 'account');
    await _pump(t, session);
    await t.tap(find.text('Activate this device'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Activate this device'));
    await t.pumpAndSettle();
    expect(find.text('Another device is active'), findsOneWidget);
    await t.tap(find.text('Ask the active device'));
    await t.pumpAndSettle();
    expect(find.textContaining('Code 482913'), findsOneWidget);
    await t.tap(find.text('Finish transfer'));
    await t.pumpAndSettle();
    expect(find.text('Not approved yet by the active device.'), findsOneWidget);
    approved = true;
    await t.tap(find.text('Finish transfer'));
    await t.pumpAndSettle();
    expect(find.text('Session accepted by server at last check.'), findsOneWidget);
    expect(operations.where((o) => o == 'completeTakeover').length, 2);
  });

  testWidgets('P7.1: active device approval requires step-up; cancelled step-up never approves', (t) async {
    final operations = <String>[];
    final storage = MemoryStorage();
    await storage.write('account', {'accountId': 'account', 'secret': 'a' * 43,
      'generation': 1, 'installationId': '11111111-1111-4111-8111-111111111111'});
    final session = CloudSession(storage, (op, data) async {
      operations.add(op);
      return op == 'protectedPing'
          ? {'allowed': true, 'pendingTakeover': {'requestId': 'q', 'code': '123456', 'expiresAt': 1 << 42}}
          : {'approved': op == 'approveTakeover'};
    }, () => 'account');
    var allow = false;
    var stepUps = 0;
    await _pump(t, session, stepUp: () async {
      stepUps++;
      return allow;
    });
    for (final expected in [false, true]) {
      allow = expected;
      await t.tap(find.text('Check cloud session'));
      await t.pumpAndSettle();
      expect(find.textContaining('Code: 123456'), findsOneWidget);
      await t.tap(find.text('Approve'));
      await t.pumpAndSettle();
    }
    expect(stepUps, 2);
    expect(operations.where((o) => o == 'approveTakeover').length, 1);
    await t.tap(find.text('Check cloud session'));
    await t.pumpAndSettle();
    await t.tap(find.text('Reject'));
    await t.pumpAndSettle();
    expect(stepUps, 2);
    expect(operations.last, 'rejectTakeover');
  });

  test('DEVICE_REVOKED wipes P7 credential and runs revoked handlers', () async {
    final storage = MemoryStorage();
    await storage.write('account', {'secret': 'a' * 43});
    var wiped = false;
    final session = CloudSession(storage,
        (op, data) async => throw const SessionFailure(true, 'DEVICE_REVOKED'), () => 'account');
    session.revokedHandlers.add(() async => wiped = true);
    await expectLater(session.check(), throwsA(isA<SessionFailure>()));
    expect(storage.value, isNull);
    expect(wiped, isTrue);
  });
}
