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

  @override
  String get takeoverTitle => 'Another device is active';

  @override
  String get takeoverBody =>
      'Signing in is not enough to replace the active device. Ask the active device to approve, or use lost-device recovery.';

  @override
  String get takeoverRequest => 'Ask the active device';

  @override
  String get takeoverLost => 'Old device is lost';

  @override
  String takeoverWaiting(String code) {
    return 'Code $code. On the active device, tap Check cloud session and approve only if it shows this code. Then tap Finish transfer here.';
  }

  @override
  String get takeoverFinish => 'Finish transfer';

  @override
  String get takeoverPending => 'Not approved yet by the active device.';

  @override
  String get approveTitle => 'Transfer request';

  @override
  String approveBody(String code) {
    return 'A device signed in to this account asks to become the active device. Code: $code. Approve only if the new device shows the same code. This device will lose cloud access.';
  }

  @override
  String get approve => 'Approve';

  @override
  String get reject => 'Reject';

  @override
  String get recoveryRequired =>
      'This device was replaced by lost-device recovery. It needs the Backup Password or Recovery Key.';

  @override
  String get recentLoginRequired =>
      'For safety, sign out and sign in again, then retry within 30 minutes.';

  @override
  String get lostTitle => 'Lost-device recovery';

  @override
  String get lostBody =>
      'Enter the Backup Password or the Recovery Key. The old device will be locked out permanently. The App Lock PIN is not accepted here.';

  @override
  String get usePassword => 'Backup Password';

  @override
  String get useRecoveryKey => 'Recovery Key';

  @override
  String get recover => 'Recover';

  @override
  String get recoverFailed =>
      'Recovery failed. Check the secret and try again.';

  @override
  String get noBackup =>
      'No cloud backup exists for this account, so lost-device recovery is not available.';

  @override
  String get backupTitle => 'Encrypted backup (DEV fixture)';

  @override
  String get backupOff =>
      'Not enabled on this device. Only synthetic DEV data is uploaded until local database encryption is done.';

  @override
  String get backupOn =>
      'Enabled. Backup key is protected by Android Keystore.';

  @override
  String get backupEnable => 'Enable backup';

  @override
  String get backupUpload => 'Upload DEV fixture';

  @override
  String get backupVerify => 'Download & decrypt';

  @override
  String get backupChangePassword => 'Change Backup Password';

  @override
  String get backupPassword => 'Backup Password (min 10 characters)';

  @override
  String get backupPasswordRepeat => 'Repeat Backup Password';

  @override
  String get backupOldPassword =>
      'Current Backup Password (optional on this trusted device)';

  @override
  String get backupPasswordHint =>
      'Separate from your Google account, App Lock PIN and phone PIN. It is never sent to the server.';

  @override
  String get recoveryKeyTitle => 'Save your Recovery Key';

  @override
  String get recoveryKeyBody =>
      'Shown only once. If you lose the Backup Password, this Recovery Key AND every trusted device, the backup cannot be recovered by anyone, including administrators.';

  @override
  String get recoveryKeySaved => 'I have saved the Recovery Key somewhere safe';

  @override
  String get done => 'Done';

  @override
  String backupResult(String result) {
    return '$result';
  }

  @override
  String get backupFailed => 'Backup action failed.';

  @override
  String get stepUpReason => 'Confirm it is you for this security action';

  @override
  String get reauthenticate => 'Verify again';

  @override
  String get stepUpFailed => 'Verification was not completed.';

  @override
  String get deviceRevoked =>
      'This device was replaced by lost-device recovery. Its cloud credential and backup key were removed from this device.';

  @override
  String get dbEncryptionOn =>
      'On-device data encryption: on (SQLCipher, key protected by Android Keystore). Separate from App Lock.';

  @override
  String get dbEncryptionPending =>
      'On-device data encryption: not yet applied. The app will retry on next start; your data is unchanged.';

  @override
  String get dbRecoveryTitle => 'Wallet data cannot be opened on this device';

  @override
  String get dbRecoveryBody =>
      'The encryption key protecting this Wallet on this device is no longer available (for example after a system security reset). Your encrypted data has been kept exactly as it was and has not been deleted or overwritten. A new key was NOT created. Recovery from an encrypted cloud backup will be the way back in a future version.';
}
