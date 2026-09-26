import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'session_localizations_en.dart';
import 'session_localizations_vi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of SessionLocalizations
/// returned by `SessionLocalizations.of(context)`.
///
/// Applications need to include `SessionLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/session_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: SessionLocalizations.localizationsDelegates,
///   supportedLocales: SessionLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the SessionLocalizations.supportedLocales
/// property.
abstract class SessionLocalizations {
  SessionLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static SessionLocalizations? of(BuildContext context) {
    return Localizations.of<SessionLocalizations>(
      context,
      SessionLocalizations,
    );
  }

  static const LocalizationsDelegate<SessionLocalizations> delegate =
      _SessionLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('vi'),
  ];

  /// No description provided for @activateSession.
  ///
  /// In en, this message translates to:
  /// **'Activate this device'**
  String get activateSession;

  /// No description provided for @checkSession.
  ///
  /// In en, this message translates to:
  /// **'Check cloud session'**
  String get checkSession;

  /// No description provided for @confirmSession.
  ///
  /// In en, this message translates to:
  /// **'Use this device for cloud access? The previous device will lose cloud access. Local data stays on both devices.'**
  String get confirmSession;

  /// No description provided for @cancelSession.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelSession;

  /// No description provided for @sessionReady.
  ///
  /// In en, this message translates to:
  /// **'Session accepted by server at last check.'**
  String get sessionReady;

  /// No description provided for @sessionDenied.
  ///
  /// In en, this message translates to:
  /// **'No current cloud session on this device. Activate explicitly to use it again.'**
  String get sessionDenied;

  /// No description provided for @sessionUnknown.
  ///
  /// In en, this message translates to:
  /// **'Cloud session could not be verified. Local data remains available.'**
  String get sessionUnknown;

  /// No description provided for @sessionUnchecked.
  ///
  /// In en, this message translates to:
  /// **'Cloud session has not been checked.'**
  String get sessionUnchecked;
}

class _SessionLocalizationsDelegate
    extends LocalizationsDelegate<SessionLocalizations> {
  const _SessionLocalizationsDelegate();

  @override
  Future<SessionLocalizations> load(Locale locale) {
    return SynchronousFuture<SessionLocalizations>(
      lookupSessionLocalizations(locale),
    );
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'vi'].contains(locale.languageCode);

  @override
  bool shouldReload(_SessionLocalizationsDelegate old) => false;
}

SessionLocalizations lookupSessionLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return SessionLocalizationsEn();
    case 'vi':
      return SessionLocalizationsVi();
  }

  throw FlutterError(
    'SessionLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
