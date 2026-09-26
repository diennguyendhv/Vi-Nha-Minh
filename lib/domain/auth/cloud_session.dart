import 'dart:async';

class SessionFailure implements Exception {
  const SessionFailure(this.denied, [this.reason]);
  final bool denied;

  /// Server reason code: TAKEOVER_REQUIRED, RECOVERY_REQUIRED,
  /// RECENT_LOGIN_REQUIRED, TAKEOVER_PENDING, NO_PENDING_TAKEOVER, …
  final String? reason;
  @override
  String toString() => 'SessionFailure(${reason ?? denied})';
}

abstract class SessionStorage {
  Future<String> installationId();
  Future<Map<String, dynamic>?> read(String uid);
  Future<void> write(String uid, Map<String, dynamic> credential);
  Future<void> clear();
}

typedef SessionTransport =
    Future<Map<String, dynamic>> Function(
      String operation,
      Map<String, dynamic> data,
    );

/// Step-up for sensitive actions: device credential / App Lock where
/// available + recent account re-authentication. Returns false if cancelled.
/// Ordinary opening, checking and sync never call it.
typedef StepUp = Future<bool> Function();

/// Takeover request shown on the ACTIVE device; [code] is also shown on the
/// requesting device so the user can match them.
class PendingTakeover {
  const PendingTakeover(this.requestId, this.code, this.expiresAt);
  final String requestId;
  final String code;
  final DateTime expiresAt;
}

/// Held in memory on the REQUESTING device only. The request secret is the
/// one-time grant that becomes usable after the active device approves.
class TakeoverTicket {
  TakeoverTicket._(this.uid, this.requestId, this._secret, this.code, this.expiresAt);
  final String uid;
  final String requestId;
  final String _secret;
  final String code;
  final DateTime expiresAt;
  @override
  String toString() => 'TakeoverTicket(<redacted>)';
}

/// Auth refresh never activates a session. Only explicit calls do.
/// Serializes activation/check/logout so a late response cannot restore a secret
/// after logout. No wallet or device-lock dependencies.
///
/// P7.1: Firebase Auth alone cannot replace another active installation. The
/// server answers TAKEOVER_REQUIRED; the device then either asks the active
/// device for approval ([requestTakeover]/[completeTakeover]) or uses the
/// lost-device path ([recover]) with a Backup Password/Recovery Key proof.
class CloudSession {
  CloudSession(this.storage, this.transport, this.accountId);
  final SessionStorage storage;
  final SessionTransport transport;
  final String? Function() accountId;
  Future<void> _tail = Future.value();

  /// Run when the server says this installation was revoked by lost-device
  /// recovery (e.g. BackupService wipes its Keystore-wrapped BMK here).
  final revokedHandlers = <Future<void> Function()>[];
  static const revokedReasons = {'DEVICE_REVOKED', 'RECOVERY_REQUIRED'};
  static final _secret = RegExp(r'^[A-Za-z0-9_-]{43}$');

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  /// Wipes this device's cloud authority: P7 credential + registered local
  /// key material. Cannot reach a device that stays offline forever.
  Future<void> handleRevoked() async {
    await storage.clear();
    for (final handler in revokedHandlers) {
      try {
        await handler();
      } on Object {
        /* Best effort; credential is already gone. */
      }
    }
  }

  Future<Map<String, dynamic>> _call(
    String operation,
    Map<String, dynamic> data,
  ) async {
    try {
      return await transport(operation, data);
    } on SessionFailure catch (e) {
      if (revokedReasons.contains(e.reason)) await handleRevoked();
      rethrow;
    }
  }

  String _uid() => accountId() ?? (throw const SessionFailure(true));

  Future<Map<String, dynamic>?> _credential(String uid) async {
    final credential = await storage.read(uid);
    // P7 credentials predate epochs; the server treats a missing epoch as 1.
    return credential == null ? null : {'epoch': 1, ...credential};
  }

  /// Current credential for protected backend calls (backup transport).
  Future<Map<String, dynamic>> credential() => _serial(() async {
    return await _credential(_uid()) ?? (throw const SessionFailure(true));
  });

  Future<void> _save(String uid, String installation, Map<String, dynamic> r) async {
    if (accountId() != uid) throw const SessionFailure(true);
    final epoch = r['epoch'] ?? 1;
    if (r['generation'] is! int ||
        (r['generation'] as int) < 1 ||
        epoch is! int ||
        epoch < 1 ||
        r['secret'] is! String ||
        !_secret.hasMatch(r['secret'] as String)) {
      throw const SessionFailure(false);
    }
    await storage.write(uid, {
      'accountId': uid,
      'installationId': installation,
      'generation': r['generation'],
      'epoch': epoch,
      'secret': r['secret'],
    });
  }

  /// Rotation of THIS device's own session (sends its current credential), or
  /// first activation when no session is active. Otherwise the server throws
  /// TAKEOVER_REQUIRED / RECOVERY_REQUIRED / RECENT_LOGIN_REQUIRED.
  Future<void> activate() => _serial(() async {
    final uid = _uid();
    final installation = await storage.installationId();
    final current = await _credential(uid);
    final response = await _call('activateSession', {
      if (current != null && current['installationId'] == installation) ...current,
      'accountId': uid,
      'installationId': installation,
      'confirm': true,
    });
    await _save(uid, installation, response);
  });

  /// Returns a pending takeover request when this is the active device.
  Future<PendingTakeover?> check() => _serial(() async {
    final uid = _uid();
    final credential = await _credential(uid);
    if (credential == null) throw const SessionFailure(true);
    final result = await _call('protectedPing', credential);
    if (accountId() != uid) throw const SessionFailure(true);
    final pending = result['pendingTakeover'];
    if (pending is! Map ||
        pending['requestId'] is! String ||
        pending['code'] is! String ||
        pending['expiresAt'] is! int) {
      return null;
    }
    return PendingTakeover(
      pending['requestId'] as String,
      pending['code'] as String,
      DateTime.fromMillisecondsSinceEpoch(pending['expiresAt'] as int),
    );
  });

  Future<TakeoverTicket> requestTakeover() => _serial(() async {
    final uid = _uid();
    final r = await _call('requestTakeover', {
      'accountId': uid,
      'installationId': await storage.installationId(),
    });
    if (r['requestId'] is! String ||
        r['requestSecret'] is! String ||
        !_secret.hasMatch(r['requestSecret'] as String) ||
        r['code'] is! String ||
        r['expiresAt'] is! int) {
      throw const SessionFailure(false);
    }
    return TakeoverTicket._(
      uid,
      r['requestId'] as String,
      r['requestSecret'] as String,
      r['code'] as String,
      DateTime.fromMillisecondsSinceEpoch(r['expiresAt'] as int),
    );
  });

  /// Succeeds only after the active device approved; single-use.
  Future<void> completeTakeover(TakeoverTicket ticket) => _serial(() async {
    final uid = _uid();
    if (ticket.uid != uid) throw const SessionFailure(true);
    final installation = await storage.installationId();
    final r = await _call('completeTakeover', {
      'accountId': uid,
      'installationId': installation,
      'requestId': ticket.requestId,
      'requestSecret': ticket._secret,
    });
    await _save(uid, installation, r);
  });

  Future<void> _decide(String operation, String requestId) => _serial(() async {
    final credential = await _credential(_uid());
    if (credential == null) throw const SessionFailure(true);
    await _call(operation, {...credential, 'requestId': requestId});
  });

  Future<void> approveTakeover(String requestId) =>
      _decide('approveTakeover', requestId);
  Future<void> rejectTakeover(String requestId) =>
      _decide('rejectTakeover', requestId);

  /// "Thiết bị cũ đã mất": [proof] is derived client-side from the Backup
  /// Password or Recovery Key (never the App Lock PIN or installation id).
  Future<void> recover({
    required String walletId,
    required String proofKind,
    required String proof,
  }) => _serial(() async {
    final uid = _uid();
    final installation = await storage.installationId();
    final r = await _call('recoverSession', {
      'accountId': uid,
      'installationId': installation,
      'walletId': walletId,
      'proofKind': proofKind,
      'proof': proof,
    });
    await _save(uid, installation, r);
  });

  Future<void> signOut(Future<void> Function() authSignOut) => _serial(
    () async {
      // Local logout must work offline. Server deactivation is best effort and
      // only ever uses this device's credential; stale devices cannot revoke B.
      try {
        final uid = accountId();
        final credential = uid == null ? null : await _credential(uid);
        if (credential != null) {
          await transport(
            'deactivateSession',
            credential,
          ).timeout(const Duration(seconds: 5));
        }
      } on Object {
        /* Local cleanup must still run. */
      }
      try {
        await storage.clear();
      } finally {
        await authSignOut();
      }
    },
  );
}
