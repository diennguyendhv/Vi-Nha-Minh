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

  @override
  String get claimTitle => 'Back up this Wallet';

  @override
  String get claimNone =>
      'This Wallet lives only on this device and is not linked to any account.';

  @override
  String get claimStart => 'Back up this Wallet';

  @override
  String get claimNeedSession =>
      'Activate this device for cloud first (Activate this device).';

  @override
  String get claimWhoTitle => 'Who are you in this Wallet?';

  @override
  String get claimWhoBody =>
      'Choose the member the signed-in account represents. There is no default; no transaction is changed.';

  @override
  String claimMemberSummary(int count, String range) {
    return '$count transactions · $range';
  }

  @override
  String get claimMemberEmpty => 'No transactions yet';

  @override
  String get claimNext => 'Continue';

  @override
  String get claimConfirmTitle => 'Confirm Wallet registration';

  @override
  String claimConfirmBody(String account, String member) {
    return '• The account $account becomes the cloud Owner of this Wallet.\n• $member is you in this Wallet; the other member stays as is, not linked to any account.\n• NO financial data is uploaded in this step — ownership information only.\n• Signing out later does not hide or delete the Wallet on this device.';
  }

  @override
  String get claimConfirm => 'Register Wallet';

  @override
  String get claimPending =>
      'Finishing Wallet registration with the server. Data on this device is unchanged.';

  @override
  String get claimRetry => 'Retry';

  @override
  String claimActive(String member) {
    return 'Wallet registered to this account (you are $member). Encrypted backup is managed below.';
  }

  @override
  String get claimOtherAccount =>
      'This Wallet is registered to a different account. The signed-in account has no cloud access to it; the Wallet on this device keeps working.';

  @override
  String get claimCheck => 'Check with server';

  @override
  String get claimServerOk =>
      'Server confirms: this account is the Wallet Owner.';

  @override
  String get claimServerMissing =>
      'The server has no registration of this Wallet for this account.';

  @override
  String get claimAbandon => 'Cancel Wallet registration';

  @override
  String get claimAbandonBody =>
      'Only possible while nothing has been backed up to the cloud. Data on this device is kept.';

  @override
  String get claimAbandoned =>
      'Registration cancelled. The Wallet lives only on this device again.';

  @override
  String get claimAlreadyClaimed =>
      'This Wallet is already registered by another account.';

  @override
  String get claimAccountHasWallet =>
      'This account already owns another Wallet.';

  @override
  String get claimSelfMismatch =>
      'The server recorded you as a different member of this Wallet. Please choose again.';

  @override
  String get claimBackupStarted =>
      'Backup has already started, so the registration cannot be cancelled.';

  @override
  String get claimFailed =>
      'Registration did not complete. Data on this device is unchanged; please try again later.';

  @override
  String get walletBackupTitle => 'Encrypted backup of this Wallet (DEV)';

  @override
  String get walletBackupOff =>
      'Not enabled. This Wallet is only on this device.';

  @override
  String get walletBackupSeeding => 'Uploading the first encrypted backup…';

  @override
  String get walletBackupComplete =>
      'Backed up. New changes are uploaded automatically, encrypted on this device.';

  @override
  String walletBackupPending(int count) {
    return 'Waiting to upload: $count';
  }

  @override
  String walletBackupDiag(int calls, String headRev) {
    return 'Network calls this session: $calls · server revision: $headRev';
  }

  @override
  String get walletBackupEnable => 'Enable encrypted backup';

  @override
  String get walletBackupSyncNow => 'Sync now';

  @override
  String get restoreAction => 'Restore a Wallet from backup';

  @override
  String get restorePick => 'Choose a backup';

  @override
  String get restoreDone => 'Wallet restored and verified.';

  @override
  String get restoreFailed =>
      'Restore failed. The current Wallet was not changed.';

  @override
  String get rotateRecoveryAction => 'Create new Recovery Key';

  @override
  String get rotateRecoveryConfirmTitle => 'Create a new Recovery Key?';

  @override
  String get rotateRecoveryConfirmBody =>
      'Your current Recovery Key will stop working immediately. The Backup Password and your backup data stay the same. The new key is shown only once.';

  @override
  String get rotateRecoveryConfirm => 'Create new key';

  @override
  String get rotateRecoveryFailed =>
      'The Recovery Key was not replaced. Your Backup Password still works; try again.';
}
