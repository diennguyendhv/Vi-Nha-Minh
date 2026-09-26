import 'dart:convert';
import 'dart:typed_data';

import '../../core/config/app_environment.dart';
import '../../core/crypto/backup_crypto.dart';
import '../../core/crypto/envelope_cipher.dart';
import '../../domain/auth/cloud_session.dart';
import 'backup_key_store.dart';

/// Release gate (CLAUDE.md §19, docs/p8-cloud-backup-architecture.md):
/// local SQLCipher has NOT passed, so only synthetic DEV fixture wallets may be
/// backed up. There is intentionally no API that uploads the real local Wallet.
abstract final class BackupGate {
  static const localDbEncryptionPassed = false;

  static void requireFixtureAllowed(AppEnvironment env) {
    if (env != AppEnvironment.dev) throw const BackupBlocked();
  }
}

class BackupBlocked implements Exception {
  const BackupBlocked();
  @override
  String toString() => 'BackupBlocked';
}

/// Synthetic DEV-only data used to prove the envelope path. Not user data.
const devBackupFixture = <({String kind, String localId, Map<String, Object?> body})>[
  (
    kind: 'category',
    localId: 'fixture-cat-1',
    body: {'name': 'FIXTURE Ăn uống', 'group': 'spending'},
  ),
  (
    kind: 'fund',
    localId: 'fixture-fund-1',
    body: {'name': 'FIXTURE Quỹ du lịch', 'balance': 9876543},
  ),
  (
    kind: 'transaction',
    localId: 'fixture-tx-1',
    body: {
      'amount': 1234567,
      'note': 'FIXTURE Tiền chợ',
      'categoryId': 'fixture-cat-1',
      'memberId': 'fixture-member-a',
    },
  ),
];

/// Zero-knowledge backup client: generates the BMK, wraps it under the Backup
/// Password (Argon2id) and a Recovery Key (HKDF), keeps it locally under
/// Android Keystore, and ships only wrapped keys + AES-GCM envelopes.
class BackupService {
  BackupService({
    required this.session,
    required SessionTransport transport,
    required this.keyStore,
    this.kdf = KdfParams.v1,
    AppEnvironment? env,
  }) : _send = transport,
       env = env ?? AppEnvironment.current {
    // Revoked by lost-device recovery ⇒ this device's BMK copy is wiped too.
    session.revokedHandlers.add(keyStore.clear);
  }
  final CloudSession session;
  final SessionTransport _send;
  final BackupKeyStore keyStore;

  Future<Map<String, dynamic>> transport(
    String operation,
    Map<String, dynamic> data,
  ) async {
    try {
      return await _send(operation, data);
    } on SessionFailure catch (e) {
      if (CloudSession.revokedReasons.contains(e.reason)) {
        await session.handleRevoked();
      }
      rethrow;
    }
  }
  final KdfParams kdf;
  final AppEnvironment env;
  static const minPasswordLength = 10;

  String _uid() => session.accountId() ?? (throw const SessionFailure(true));

  Future<({String walletId, Uint8List bmk})?> localKey() =>
      keyStore.load(_uid());

  /// Returns the Recovery Key display string: show ONCE, never persist.
  Future<({String walletId, String recoveryKey})> enableFixture(
    String password,
  ) async {
    BackupGate.requireFixtureAllowed(env);
    if (password.length < minPasswordLength) {
      throw ArgumentError('password too short');
    }
    final uid = _uid();
    final walletId =
        'fixture-${base64Url.encode(BackupCrypto.randomBytes(12))}';
    final bmk = BackupCrypto.newBmk();
    final pwSalt = BackupCrypto.randomBytes(16);
    final pw = await BackupCrypto.fromPassword(password, pwSalt, kdf);
    final recoveryKey = RecoveryKey.generate();
    final rcSalt = BackupCrypto.randomBytes(32);
    final rc = await BackupCrypto.fromRecoveryKey(recoveryKey, rcSalt);
    final credential = await session.credential();
    await transport('putBackupKeyring', {
      ...credential,
      'walletId': walletId,
      'mode': 'create',
      'cryptoVersion': BackupCrypto.cryptoVersion,
      'password': (await BackupCrypto.wrap(
        bmk: bmk,
        secrets: pw,
        salt: pwSalt,
        kdf: kdf.toJson(),
        walletId: walletId,
        slot: 'password',
      )).toJson(),
      'recovery': (await BackupCrypto.wrap(
        bmk: bmk,
        secrets: rc,
        salt: rcSalt,
        kdf: {'alg': 'hkdf-sha256'},
        walletId: walletId,
        slot: 'recovery',
      )).toJson(),
      'passwordProof': pw.proof,
      'recoveryProof': rc.proof,
    });
    await keyStore.store(uid, walletId, bmk);
    return (walletId: walletId, recoveryKey: await recoveryKey.display());
  }

  Future<Map<String, Object?>> _keyring(String walletId, {bool session = true}) async =>
      Map<String, Object?>.from(
        await transport('getBackupKeyring', {
          if (session) ...await this.session.credential(),
          'accountId': _uid(),
          'walletId': walletId,
        }),
      );

  static Future<({Uint8List bmk, String proof})> _unwrapPassword(
    Map<String, Object?> keyring,
    String walletId,
    String password,
  ) async {
    final slot = WrappedKeySlot.fromJson(
      Map<String, Object?>.from(keyring['password']! as Map),
    );
    final secrets = await BackupCrypto.fromPassword(
      password,
      slot.salt,
      KdfParams.fromJson(slot.kdf),
    );
    return (
      bmk: await BackupCrypto.unwrap(
        slot: slot,
        secrets: secrets,
        walletId: walletId,
        slotName: 'password',
      ),
      proof: secrets.proof,
    );
  }

  /// Wallets with a cloud keyring (recent sign-in required server-side).
  Future<List<String>> cloudWallets() async {
    final r = await transport('listBackupWallets', {'accountId': _uid()});
    return [for (final id in r['walletIds'] as List) id as String];
  }

  /// Re-wraps the SAME BMK. Touches only wrapped-key metadata — never any
  /// envelope. Without [oldPassword] a trusted device (local BMK) + recent
  /// sign-in is required by the server.
  Future<void> changePassword({
    String? oldPassword,
    required String newPassword,
  }) async {
    if (newPassword.length < minPasswordLength) {
      throw ArgumentError('password too short');
    }
    final local = await localKey();
    if (local == null) throw const BackupKeyException();
    final walletId = local.walletId;
    final keyring = await _keyring(walletId);
    String? oldProof;
    if (oldPassword != null) {
      final old = await _unwrapPassword(keyring, walletId, oldPassword);
      if (!_equal(old.bmk, local.bmk)) throw const BackupKeyException();
      oldProof = old.proof;
    }
    final salt = BackupCrypto.randomBytes(16);
    final secrets = await BackupCrypto.fromPassword(newPassword, salt, kdf);
    await transport('putBackupKeyring', {
      ...await session.credential(),
      'walletId': walletId,
      'mode': 'rewrapPassword',
      'expectedRev': keyring['rev'],
      'password': (await BackupCrypto.wrap(
        bmk: local.bmk,
        secrets: secrets,
        salt: salt,
        kdf: kdf.toJson(),
        walletId: walletId,
        slot: 'password',
      )).toJson(),
      'passwordProof': secrets.proof,
      'oldPasswordProof': ?oldProof,
    });
  }

  /// Lost-device takeover on THIS (new) device. Unwraps the BMK locally first
  /// (so a wrong secret fails without a server call), then proves knowledge to
  /// the server; on success stores the BMK under this device's Keystore.
  Future<void> recoverOnThisDevice({
    required String walletId,
    String? password,
    String? recoveryKey,
  }) async {
    BackupGate.requireFixtureAllowed(env);
    if ((password == null) == (recoveryKey == null)) {
      throw ArgumentError('exactly one secret');
    }
    final uid = _uid();
    final keyring = await _keyring(walletId, session: false);
    late Uint8List bmk;
    late String proof;
    if (password != null) {
      final r = await _unwrapPassword(keyring, walletId, password);
      bmk = r.bmk;
      proof = r.proof;
    } else {
      final slot = WrappedKeySlot.fromJson(
        Map<String, Object?>.from(keyring['recovery']! as Map),
      );
      if (slot.kdf['alg'] != 'hkdf-sha256') throw const BackupKeyException();
      final secrets = await BackupCrypto.fromRecoveryKey(
        await RecoveryKey.parse(recoveryKey!),
        slot.salt,
      );
      bmk = await BackupCrypto.unwrap(
        slot: slot,
        secrets: secrets,
        walletId: walletId,
        slotName: 'recovery',
      );
      proof = secrets.proof;
    }
    await session.recover(
      walletId: walletId,
      proofKind: password != null ? 'password' : 'recovery',
      proof: proof,
    );
    await keyStore.store(uid, walletId, bmk);
  }

  /// Encrypts the synthetic fixture and uploads ONE incremental batch.
  Future<int> uploadFixture() async {
    BackupGate.requireFixtureAllowed(env);
    final local = await localKey() ?? (throw const BackupKeyException());
    final cipher = await EnvelopeCipher.create(local.bmk, local.walletId);
    final credential = await session.credential();
    final head = await transport('getEncryptedChanges', {
      ...credential,
      'walletId': local.walletId,
      'sinceRev': 0,
    });
    final rev = (head['headRev'] as int) + 1;
    final envelopes = [
      for (final f in devBackupFixture)
        (await cipher.seal(
          kind: f.kind,
          localId: f.localId,
          rev: rev,
          body: f.body,
        )).toJson(),
    ];
    final result = await transport('putEncryptedBatch', {
      ...credential,
      'walletId': local.walletId,
      'batchId': base64Url
          .encode(BackupCrypto.randomBytes(32))
          .replaceAll('=', ''),
      'baseHeadRev': head['headRev'],
      'fixture': true,
      'envelopes': envelopes,
    });
    return result['headRev'] as int;
  }

  /// Downloads every envelope and decrypts it locally; returns how many opened
  /// AND match the fixture exactly.
  Future<int> verifyFixture() async {
    final local = await localKey() ?? (throw const BackupKeyException());
    final cipher = await EnvelopeCipher.create(local.bmk, local.walletId);
    final changes = await transport('getEncryptedChanges', {
      ...await session.credential(),
      'walletId': local.walletId,
      'sinceRev': 0,
    });
    var matched = 0;
    for (final raw in changes['envelopes'] as List) {
      final opened = await cipher.open(
        Envelope.fromJson(Map<String, Object?>.from(raw as Map)),
      );
      final expected = devBackupFixture.where(
        (f) => f.localId == opened.localId && f.kind == opened.kind,
      );
      if (expected.isNotEmpty &&
          jsonEncode(expected.first.body) == jsonEncode(opened.body)) {
        matched++;
      }
    }
    return matched;
  }

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
