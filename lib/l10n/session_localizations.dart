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

  /// No description provided for @takeoverTitle.
  ///
  /// In en, this message translates to:
  /// **'Another device is active'**
  String get takeoverTitle;

  /// No description provided for @takeoverBody.
  ///
  /// In en, this message translates to:
  /// **'Signing in is not enough to replace the active device. Ask the active device to approve, or use lost-device recovery.'**
  String get takeoverBody;

  /// No description provided for @takeoverRequest.
  ///
  /// In en, this message translates to:
  /// **'Ask the active device'**
  String get takeoverRequest;

  /// No description provided for @takeoverLost.
  ///
  /// In en, this message translates to:
  /// **'Old device is lost'**
  String get takeoverLost;

  /// No description provided for @takeoverWaiting.
  ///
  /// In en, this message translates to:
  /// **'Code {code}. On the active device, tap Check cloud session and approve only if it shows this code. Then tap Finish transfer here.'**
  String takeoverWaiting(String code);

  /// No description provided for @takeoverFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish transfer'**
  String get takeoverFinish;

  /// No description provided for @takeoverPending.
  ///
  /// In en, this message translates to:
  /// **'Not approved yet by the active device.'**
  String get takeoverPending;

  /// No description provided for @approveTitle.
  ///
  /// In en, this message translates to:
  /// **'Transfer request'**
  String get approveTitle;

  /// No description provided for @approveBody.
  ///
  /// In en, this message translates to:
  /// **'A device signed in to this account asks to become the active device. Code: {code}. Approve only if the new device shows the same code. This device will lose cloud access.'**
  String approveBody(String code);

  /// No description provided for @approve.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approve;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @recoveryRequired.
  ///
  /// In en, this message translates to:
  /// **'This device was replaced by lost-device recovery. It needs the Backup Password or Recovery Key.'**
  String get recoveryRequired;

  /// No description provided for @recentLoginRequired.
  ///
  /// In en, this message translates to:
  /// **'For safety, sign out and sign in again, then retry within 30 minutes.'**
  String get recentLoginRequired;

  /// No description provided for @lostTitle.
  ///
  /// In en, this message translates to:
  /// **'Lost-device recovery'**
  String get lostTitle;

  /// No description provided for @lostBody.
  ///
  /// In en, this message translates to:
  /// **'Enter the Backup Password or the Recovery Key. The old device will be locked out permanently. The App Lock PIN is not accepted here.'**
  String get lostBody;

  /// No description provided for @usePassword.
  ///
  /// In en, this message translates to:
  /// **'Backup Password'**
  String get usePassword;

  /// No description provided for @useRecoveryKey.
  ///
  /// In en, this message translates to:
  /// **'Recovery Key'**
  String get useRecoveryKey;

  /// No description provided for @recover.
  ///
  /// In en, this message translates to:
  /// **'Recover'**
  String get recover;

  /// No description provided for @recoverFailed.
  ///
  /// In en, this message translates to:
  /// **'Recovery failed. Check the secret and try again.'**
  String get recoverFailed;

  /// No description provided for @noBackup.
  ///
  /// In en, this message translates to:
  /// **'No cloud backup exists for this account, so lost-device recovery is not available.'**
  String get noBackup;

  /// No description provided for @backupTitle.
  ///
  /// In en, this message translates to:
  /// **'Encrypted backup (DEV fixture)'**
  String get backupTitle;

  /// No description provided for @backupOff.
  ///
  /// In en, this message translates to:
  /// **'Not enabled on this device. Only synthetic DEV data is uploaded until local database encryption is done.'**
  String get backupOff;

  /// No description provided for @backupOn.
  ///
  /// In en, this message translates to:
  /// **'Enabled. Backup key is protected by Android Keystore.'**
  String get backupOn;

  /// No description provided for @backupEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable backup'**
  String get backupEnable;

  /// No description provided for @backupUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload DEV fixture'**
  String get backupUpload;

  /// No description provided for @backupVerify.
  ///
  /// In en, this message translates to:
  /// **'Download & decrypt'**
  String get backupVerify;

  /// No description provided for @backupChangePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Backup Password'**
  String get backupChangePassword;

  /// No description provided for @backupPassword.
  ///
  /// In en, this message translates to:
  /// **'Backup Password (min 10 characters)'**
  String get backupPassword;

  /// No description provided for @backupPasswordRepeat.
  ///
  /// In en, this message translates to:
  /// **'Repeat Backup Password'**
  String get backupPasswordRepeat;

  /// No description provided for @backupOldPassword.
  ///
  /// In en, this message translates to:
  /// **'Current Backup Password (optional on this trusted device)'**
  String get backupOldPassword;

  /// No description provided for @backupPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Separate from your Google account, App Lock PIN and phone PIN. It is never sent to the server.'**
  String get backupPasswordHint;

  /// No description provided for @recoveryKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Save your Recovery Key'**
  String get recoveryKeyTitle;

  /// No description provided for @recoveryKeyBody.
  ///
  /// In en, this message translates to:
  /// **'Shown only once. If you lose the Backup Password, this Recovery Key AND every trusted device, the backup cannot be recovered by anyone, including administrators.'**
  String get recoveryKeyBody;

  /// No description provided for @recoveryKeySaved.
  ///
  /// In en, this message translates to:
  /// **'I have saved the Recovery Key somewhere safe'**
  String get recoveryKeySaved;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @backupResult.
  ///
  /// In en, this message translates to:
  /// **'{result}'**
  String backupResult(String result);

  /// No description provided for @backupFailed.
  ///
  /// In en, this message translates to:
  /// **'Backup action failed.'**
  String get backupFailed;

  /// No description provided for @stepUpReason.
  ///
  /// In en, this message translates to:
  /// **'Confirm it is you for this security action'**
  String get stepUpReason;

  /// No description provided for @reauthenticate.
  ///
  /// In en, this message translates to:
  /// **'Verify again'**
  String get reauthenticate;

  /// No description provided for @stepUpFailed.
  ///
  /// In en, this message translates to:
  /// **'Verification was not completed.'**
  String get stepUpFailed;

  /// No description provided for @deviceRevoked.
  ///
  /// In en, this message translates to:
  /// **'This device was replaced by lost-device recovery. Its cloud credential and backup key were removed from this device.'**
  String get deviceRevoked;
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
