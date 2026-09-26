// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'session_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class SessionLocalizationsEn extends SessionLocalizations {
  SessionLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get activateSession => 'Activate this device';

  @override
  String get checkSession => 'Check cloud session';

  @override
  String get confirmSession =>
      'Use this device for cloud access? The previous device will lose cloud access. Local data stays on both devices.';

  @override
  String get cancelSession => 'Cancel';

  @override
  String get sessionReady => 'Session accepted by server at last check.';

  @override
  String get sessionDenied =>
      'No current cloud session on this device. Activate explicitly to use it again.';

  @override
  String get sessionUnknown =>
      'Cloud session could not be verified. Local data remains available.';

  @override
  String get sessionUnchecked => 'Cloud session has not been checked.';
}
