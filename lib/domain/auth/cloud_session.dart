import 'dart:async';

class SessionFailure implements Exception {
  const SessionFailure(this.denied);
  final bool denied;
  @override
  String toString() => 'SessionFailure';
}

abstract class SessionStorage {
  Future<String> installationId();
  Future<Map<String, dynamic>?> read(String uid);
  Future<void> write(String uid, Map<String, dynamic> credential);
  Future<void> clear();
}

typedef SessionTransport = Future<Map<String, dynamic>> Function(
  String operation,
  Map<String, dynamic> data,
);

/// Auth refresh never activates a session. Only an explicit activate() does.
/// Serializes activation/check/logout so a late response cannot restore a secret
/// after logout. No wallet or device-lock dependencies.
class CloudSession {
  CloudSession(this.storage, this.transport, this.accountId);
  final SessionStorage storage;
  final SessionTransport transport;
  final String? Function() accountId;
  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> activate() => _serial(() async {
    final uid = accountId();
    if (uid == null) throw const SessionFailure(true);
    final installation = await storage.installationId();
    final response = await transport('activateSession', {
      'accountId': uid,
      'installationId': installation,
      'confirm': true,
    });
    if (accountId() != uid) throw const SessionFailure(true);
    if (response['generation'] is! int ||
        (response['generation'] as int) < 1 ||
        response['secret'] is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$')
            .hasMatch(response['secret'] as String)) {
      throw const SessionFailure(false);
    }
    await storage.write(uid, {
      'accountId': uid,
      'installationId': installation,
      'generation': response['generation'],
      'secret': response['secret'],
    });
  });

  Future<void> check() => _serial(() async {
    final uid = accountId();
    if (uid == null) throw const SessionFailure(true);
    final credential = await storage.read(uid);
    if (credential == null) throw const SessionFailure(true);
    await transport('protectedPing', credential);
    if (accountId() != uid) throw const SessionFailure(true);
  });

  Future<void> signOut(Future<void> Function() authSignOut) => _serial(
    () async {
      // Local logout must work offline. Server deactivation is best effort and
      // only ever uses this device's credential; stale devices cannot revoke B.
      try {
        final uid = accountId();
        final credential = uid == null ? null : await storage.read(uid);
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
