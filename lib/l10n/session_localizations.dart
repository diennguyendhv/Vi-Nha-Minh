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

  /// No description provided for @dbEncryptionOn.
  ///
  /// In en, this message translates to:
  /// **'On-device data encryption: on (SQLCipher, key protected by Android Keystore). Separate from App Lock.'**
  String get dbEncryptionOn;

  /// No description provided for @dbEncryptionPending.
  ///
  /// In en, this message translates to:
  /// **'On-device data encryption: not yet applied. The app will retry on next start; your data is unchanged.'**
  String get dbEncryptionPending;

  /// No description provided for @dbRecoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Wallet data cannot be opened on this device'**
  String get dbRecoveryTitle;

  /// No description provided for @dbRecoveryBody.
  ///
  /// In en, this message translates to:
  /// **'The encryption key protecting this Wallet on this device is no longer available (for example after a system security reset). Your encrypted data has been kept exactly as it was and has not been deleted or overwritten. A new key was NOT created. Recovery from an encrypted cloud backup will be the way back in a future version.'**
  String get dbRecoveryBody;

  /// No description provided for @claimTitle.
  ///
  /// In en, this message translates to:
  /// **'Back up this Wallet'**
  String get claimTitle;

  /// No description provided for @claimNone.
  ///
  /// In en, this message translates to:
  /// **'This Wallet lives only on this device and is not linked to any account.'**
  String get claimNone;

  /// No description provided for @claimStart.
  ///
  /// In en, this message translates to:
  /// **'Back up this Wallet'**
  String get claimStart;

  /// No description provided for @claimNeedSession.
  ///
  /// In en, this message translates to:
  /// **'Activate this device for cloud first (Activate this device).'**
  String get claimNeedSession;

  /// No description provided for @claimWhoTitle.
  ///
  /// In en, this message translates to:
  /// **'Who are you in this Wallet?'**
  String get claimWhoTitle;

  /// No description provided for @claimWhoBody.
  ///
  /// In en, this message translates to:
  /// **'Choose the member the signed-in account represents. There is no default; no transaction is changed.'**
  String get claimWhoBody;

  /// No description provided for @claimMemberSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} transactions · {range}'**
  String claimMemberSummary(int count, String range);

  /// No description provided for @claimMemberEmpty.
  ///
  /// In en, this message translates to:
  /// **'No transactions yet'**
  String get claimMemberEmpty;

  /// No description provided for @claimNext.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get claimNext;

  /// No description provided for @claimConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Wallet registration'**
  String get claimConfirmTitle;

  /// No description provided for @claimConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'• The account {account} becomes the cloud Owner of this Wallet.\n• {member} is you in this Wallet; the other member stays as is, not linked to any account.\n• NO financial data is uploaded in this step — ownership information only.\n• Signing out later does not hide or delete the Wallet on this device.'**
  String claimConfirmBody(String account, String member);

  /// No description provided for @claimConfirm.
  ///
  /// In en, this message translates to:
  /// **'Register Wallet'**
  String get claimConfirm;

  /// No description provided for @claimPending.
  ///
  /// In en, this message translates to:
  /// **'Finishing Wallet registration with the server. Data on this device is unchanged.'**
  String get claimPending;

  /// No description provided for @claimRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get claimRetry;

  /// No description provided for @claimActive.
  ///
  /// In en, this message translates to:
  /// **'Wallet registered to this account (you are {member}). Encrypted backup is managed below.'**
  String claimActive(String member);

  /// No description provided for @claimOtherAccount.
  ///
  /// In en, this message translates to:
  /// **'This Wallet is registered to a different account. The signed-in account has no cloud access to it; the Wallet on this device keeps working.'**
  String get claimOtherAccount;

  /// No description provided for @claimCheck.
  ///
  /// In en, this message translates to:
  /// **'Check with server'**
  String get claimCheck;

  /// No description provided for @claimServerOk.
  ///
  /// In en, this message translates to:
  /// **'Server confirms: this account is the Wallet Owner.'**
  String get claimServerOk;

  /// No description provided for @claimServerMissing.
  ///
  /// In en, this message translates to:
  /// **'The server has no registration of this Wallet for this account.'**
  String get claimServerMissing;

  /// No description provided for @claimAbandon.
  ///
  /// In en, this message translates to:
  /// **'Cancel Wallet registration'**
  String get claimAbandon;

  /// No description provided for @claimAbandonBody.
  ///
  /// In en, this message translates to:
  /// **'Only possible while nothing has been backed up to the cloud. Data on this device is kept.'**
  String get claimAbandonBody;

  /// No description provided for @claimAbandoned.
  ///
  /// In en, this message translates to:
  /// **'Registration cancelled. The Wallet lives only on this device again.'**
  String get claimAbandoned;

  /// No description provided for @claimAlreadyClaimed.
  ///
  /// In en, this message translates to:
  /// **'This Wallet is already registered by another account.'**
  String get claimAlreadyClaimed;

  /// No description provided for @claimAccountHasWallet.
  ///
  /// In en, this message translates to:
  /// **'This account already owns another Wallet.'**
  String get claimAccountHasWallet;

  /// No description provided for @claimSelfMismatch.
  ///
  /// In en, this message translates to:
  /// **'The server recorded you as a different member of this Wallet. Please choose again.'**
  String get claimSelfMismatch;

  /// No description provided for @claimBackupStarted.
  ///
  /// In en, this message translates to:
  /// **'Backup has already started, so the registration cannot be cancelled.'**
  String get claimBackupStarted;

  /// No description provided for @claimFailed.
  ///
  /// In en, this message translates to:
  /// **'Registration did not complete. Data on this device is unchanged; please try again later.'**
  String get claimFailed;

  /// No description provided for @walletBackupTitle.
  ///
  /// In en, this message translates to:
  /// **'Encrypted backup of this Wallet (DEV)'**
  String get walletBackupTitle;

  /// No description provided for @walletBackupOff.
  ///
  /// In en, this message translates to:
  /// **'Not enabled. This Wallet is only on this device.'**
  String get walletBackupOff;

  /// No description provided for @walletBackupSeeding.
  ///
  /// In en, this message translates to:
  /// **'Uploading the first encrypted backup…'**
  String get walletBackupSeeding;

  /// No description provided for @walletBackupComplete.
  ///
  /// In en, this message translates to:
  /// **'Backed up. New changes are uploaded automatically, encrypted on this device.'**
  String get walletBackupComplete;

  /// No description provided for @walletBackupPending.
  ///
  /// In en, this message translates to:
  /// **'Waiting to upload: {count}'**
  String walletBackupPending(int count);

  /// No description provided for @walletBackupDiag.
  ///
  /// In en, this message translates to:
  /// **'Network calls this session: {calls} · server revision: {headRev}'**
  String walletBackupDiag(int calls, String headRev);

  /// No description provided for @walletBackupEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable encrypted backup'**
  String get walletBackupEnable;

  /// No description provided for @walletBackupSyncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get walletBackupSyncNow;

  /// No description provided for @restoreAction.
  ///
  /// In en, this message translates to:
  /// **'Restore a Wallet from backup'**
  String get restoreAction;

  /// No description provided for @restorePick.
  ///
  /// In en, this message translates to:
  /// **'Choose a backup'**
  String get restorePick;

  /// No description provided for @restoreDone.
  ///
  /// In en, this message translates to:
  /// **'Wallet restored and verified.'**
  String get restoreDone;

  /// No description provided for @restoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Restore failed. The current Wallet was not changed.'**
  String get restoreFailed;

  /// No description provided for @rotateRecoveryAction.
  ///
  /// In en, this message translates to:
  /// **'Create new Recovery Key'**
  String get rotateRecoveryAction;

  /// No description provided for @rotateRecoveryConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Create a new Recovery Key?'**
  String get rotateRecoveryConfirmTitle;

  /// No description provided for @rotateRecoveryConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Your current Recovery Key will stop working immediately. The Backup Password and your backup data stay the same. The new key is shown only once.'**
  String get rotateRecoveryConfirmBody;

  /// No description provided for @rotateRecoveryConfirm.
  ///
  /// In en, this message translates to:
  /// **'Create new key'**
  String get rotateRecoveryConfirm;

  /// No description provided for @rotateRecoveryFailed.
  ///
  /// In en, this message translates to:
  /// **'The Recovery Key was not replaced. Your Backup Password still works; try again.'**
  String get rotateRecoveryFailed;

  /// No description provided for @familyEntry.
  ///
  /// In en, this message translates to:
  /// **'Family (DEV)'**
  String get familyEntry;

  /// No description provided for @familyTitle.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get familyTitle;

  /// No description provided for @familyPromote.
  ///
  /// In en, this message translates to:
  /// **'Share with family'**
  String get familyPromote;

  /// No description provided for @familyPromoteBody.
  ///
  /// In en, this message translates to:
  /// **'This Wallet becomes a Family Wallet in place: same Wallet, same data, same backup. You stay the Owner. Nothing is copied. Afterwards it is only visible while you are signed in.'**
  String get familyPromoteBody;

  /// No description provided for @familyPromoted.
  ///
  /// In en, this message translates to:
  /// **'This Wallet is now a Family Wallet.'**
  String get familyPromoted;

  /// No description provided for @familyInvite.
  ///
  /// In en, this message translates to:
  /// **'Share with your spouse'**
  String get familyInvite;

  /// No description provided for @familyInviteWho.
  ///
  /// In en, this message translates to:
  /// **'Who will the invited account be in this Wallet?'**
  String get familyInviteWho;

  /// No description provided for @familyInviteEmail.
  ///
  /// In en, this message translates to:
  /// **'Invited account email'**
  String get familyInviteEmail;

  /// No description provided for @familyInviteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Send this invitation?'**
  String get familyInviteConfirmTitle;

  /// No description provided for @familyInviteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{email} will be able to see and edit this whole Wallet as {member} after accepting, once you confirm the security code.'**
  String familyInviteConfirmBody(String email, String member);

  /// No description provided for @familyInviteCode.
  ///
  /// In en, this message translates to:
  /// **'Invitation code (single use, expires {time}). Send it to the invited person:'**
  String familyInviteCode(String time);

  /// No description provided for @familyInviteCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel invitation'**
  String get familyInviteCancel;

  /// No description provided for @familyCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get familyCopy;

  /// No description provided for @familyCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get familyCopied;

  /// No description provided for @familyOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get familyOwner;

  /// No description provided for @familyMember.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get familyMember;

  /// No description provided for @familyRevoked.
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get familyRevoked;

  /// No description provided for @familyYou.
  ///
  /// In en, this message translates to:
  /// **'(you)'**
  String get familyYou;

  /// No description provided for @familyAwaitingKey.
  ///
  /// In en, this message translates to:
  /// **'Accepted. Compare this security code with the invited person\'s screen:'**
  String get familyAwaitingKey;

  /// No description provided for @familyShareKey.
  ///
  /// In en, this message translates to:
  /// **'Codes match — share the Wallet key'**
  String get familyShareKey;

  /// No description provided for @familyKeyShared.
  ///
  /// In en, this message translates to:
  /// **'Wallet key shared.'**
  String get familyKeyShared;

  /// No description provided for @familyRevoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get familyRevoke;

  /// No description provided for @familyRevokeBody.
  ///
  /// In en, this message translates to:
  /// **'The member immediately loses cloud access to this Wallet. Data already on their phone cannot be erased remotely.'**
  String get familyRevokeBody;

  /// No description provided for @familyWalletCode.
  ///
  /// In en, this message translates to:
  /// **'Wallet code: {code}'**
  String familyWalletCode(String code);

  /// No description provided for @familyJoinTitle.
  ///
  /// In en, this message translates to:
  /// **'Join a Family Wallet'**
  String get familyJoinTitle;

  /// No description provided for @familyJoinCode.
  ///
  /// In en, this message translates to:
  /// **'Invitation code'**
  String get familyJoinCode;

  /// No description provided for @familyJoinPreview.
  ///
  /// In en, this message translates to:
  /// **'View invitation'**
  String get familyJoinPreview;

  /// No description provided for @familyJoinInvite.
  ///
  /// In en, this message translates to:
  /// **'Invitation to a Family Wallet (expires {time}).'**
  String familyJoinInvite(String time);

  /// No description provided for @familyJoinAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get familyJoinAccept;

  /// No description provided for @familyJoinFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Read this security code to the person who invited you: {code}'**
  String familyJoinFingerprint(String code);

  /// No description provided for @familyJoinCheck.
  ///
  /// In en, this message translates to:
  /// **'Check and download the Wallet'**
  String get familyJoinCheck;

  /// No description provided for @familyJoinWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the Owner to confirm the security code.'**
  String get familyJoinWaiting;

  /// No description provided for @familyJoined.
  ///
  /// In en, this message translates to:
  /// **'Family Wallet downloaded and verified.'**
  String get familyJoined;

  /// No description provided for @familyYouAre.
  ///
  /// In en, this message translates to:
  /// **'You are a Member of this Family Wallet as {member}.'**
  String familyYouAre(String member);

  /// No description provided for @familyRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get familyRefresh;

  /// No description provided for @familyFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not complete. Nothing on this phone was changed.'**
  String get familyFailed;

  /// No description provided for @familyNeedsBackup.
  ///
  /// In en, this message translates to:
  /// **'Turn on encrypted backup for this Wallet first.'**
  String get familyNeedsBackup;

  /// No description provided for @familyNeedsClaim.
  ///
  /// In en, this message translates to:
  /// **'Register this Wallet with your account first.'**
  String get familyNeedsClaim;

  /// No description provided for @familyNewDevice.
  ///
  /// In en, this message translates to:
  /// **'Register this phone\'s key'**
  String get familyNewDevice;

  /// No description provided for @familyConflicts.
  ///
  /// In en, this message translates to:
  /// **'Conflicts to review: {count}'**
  String familyConflicts(int count);

  /// No description provided for @familyOverdrawn.
  ///
  /// In en, this message translates to:
  /// **'After syncing, {count} balance(s) went negative. Please review recent transactions.'**
  String familyOverdrawn(int count);
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
