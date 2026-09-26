import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/auth/cloud_session.dart';
import 'package:vi_nha_minh/l10n/session_localizations.dart';
import 'package:vi_nha_minh/presentation/features/settings/session_controls.dart';

import 'cloud_session_test.dart' show MemoryStorage;

void main() {
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
