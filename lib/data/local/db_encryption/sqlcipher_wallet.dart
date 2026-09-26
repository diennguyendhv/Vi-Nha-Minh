import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:sqlite3/sqlite3.dart';

import 'db_key_store.dart';

/// Local DB encryption (SQLCipher phase). One Wallet = one SQLite file = one
/// independent random DEK-DB (see `db_key_store.dart`). App Lock, Backup
/// Password and the P7 session secret are NOT involved.
///
/// Nothing in this file logs keys, SQL containing keys, or row contents.

const _plaintextHeader = 'SQLite format 3\u0000';

enum DbFileState { absent, plaintext, encrypted }

/// Header sniff only; never opens the file.
DbFileState probeDbFile(File file) {
  if (!file.existsSync() || file.lengthSync() == 0) return DbFileState.absent;
  final raf = file.openSync();
  try {
    final head = raf.readSync(16);
    return head.length == 16 && latin1.decode(head) == _plaintextHeader
        ? DbFileState.plaintext
        : DbFileState.encrypted;
  } finally {
    raf.closeSync();
  }
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Keys the connection (raw 256-bit key, no passphrase KDF) and FAILS unless
/// the linked library really is SQLCipher and the key opens the file.
void applySqlcipherKey(Database db, Uint8List key) {
  if (key.length != 32) throw ArgumentError('Invalid database key');
  final version = db.select('PRAGMA cipher_version');
  if (version.isEmpty || '${version.first.values.first}'.isEmpty) {
    throw StateError('SQLCipher is not linked; refusing to open unencrypted');
  }
  db.execute('PRAGMA key = "x\'${_hex(key)}\'"');
  // Forces key verification (throws "file is not a database" on a wrong key).
  db.select('SELECT count(*) FROM sqlite_master');
}

/// Structural + content fingerprint used to prove a migration lossless.
class DbSnapshot {
  DbSnapshot({
    required this.userVersion,
    required this.schema,
    required this.tables,
    required this.walletId,
    required this.integrity,
    required this.foreignKeyViolations,
  });
  final int userVersion;
  final List<String> schema;

  /// table → (rowCount, sha256 of every row, all columns, deterministic order).
  final Map<String, ({int count, String digest})> tables;
  final String? walletId;
  final String integrity;
  final int foreignKeyViolations;

  bool get healthy => integrity == 'ok' && foreignKeyViolations == 0;

  bool sameDataAs(DbSnapshot other) =>
      userVersion == other.userVersion &&
      walletId == other.walletId &&
      jsonEncode(schema) == jsonEncode(other.schema) &&
      jsonEncode(_tablesJson) == jsonEncode(other._tablesJson);

  Map<String, List<Object>> get _tablesJson => {
    for (final e in tables.entries) e.key: [e.value.count, e.value.digest],
  };

  int count(String table) => tables[table]?.count ?? -1;

  /// Safe to print: counts/digests/ids only, no row contents.
  Map<String, Object?> summary() => {
    'userVersion': userVersion,
    'walletId': walletId,
    'integrity': integrity,
    'fkViolations': foreignKeyViolations,
    'tables': _tablesJson,
  };
}

String _cell(Object? v) => switch (v) {
  null => 'N',
  int() => 'I$v',
  double() => 'R$v',
  String() => 'T${v.length}:$v',
  List<int>() => 'B${_hex(v)}',
  _ => 'U$v',
};

DbSnapshot captureSnapshot(Database db) {
  final schema = [
    for (final r in db.select(
      "SELECT type, name, tbl_name, sql FROM sqlite_master "
      "WHERE name NOT LIKE 'sqlite_autoindex_%' ORDER BY type, name",
    ))
      '${r['type']}|${r['name']}|${r['tbl_name']}|${r['sql']}',
  ];
  final tables = <String, ({int count, String digest})>{};
  for (final r in db.select(
    "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
  )) {
    final name = r['name'] as String;
    final quoted = '"${name.replaceAll('"', '""')}"';
    final columns = db.select('PRAGMA table_info($quoted)').length;
    final order = [for (var i = 1; i <= columns; i++) '$i'].join(', ');
    final hasher = const DartSha256().newHashSink();
    var count = 0;
    for (final row in db.select('SELECT * FROM $quoted ORDER BY $order')) {
      count++;
      hasher.add(utf8.encode('${row.values.map(_cell).join('\u001f')}\u001e'));
    }
    hasher.close();
    tables[name] = (count: count, digest: _hex(hasher.hashSync().bytes));
  }
  String? walletId;
  if (tables.containsKey('wallet_meta')) {
    final w = db.select('SELECT wallet_id FROM wallet_meta LIMIT 1');
    walletId = w.isEmpty ? null : w.first['wallet_id'] as String?;
  }
  return DbSnapshot(
    userVersion: db.userVersion,
    schema: schema,
    tables: tables,
    walletId: walletId,
    integrity: '${db.select('PRAGMA integrity_check').first.values.first}',
    foreignKeyViolations: db.select('PRAGMA foreign_key_check').length,
  );
}

/// Encrypted DB exists but cannot be opened: key missing, unwrappable or wrong.
/// The DB file is preserved untouched; no new key is ever generated for it.
class DbRecoveryRequired implements Exception {
  const DbRecoveryRequired(this.reason);
  final String reason;
  @override
  String toString() => 'DbRecoveryRequired($reason)';
}

enum DbEncryptionStatus {
  /// Opened with SQLCipher and its Keystore-unwrapped key.
  encrypted,

  /// Migration from plaintext failed; the ORIGINAL plaintext DB is kept and
  /// opened as before so the Wallet stays usable. Retried next launch.
  plaintextMigrationPending,
}

class WalletDbOpenPlan {
  const WalletDbOpenPlan(this.key, this.status, {this.migratedNow = false});
  final Uint8List? key;
  final DbEncryptionStatus status;
  final bool migratedNow;
  @override
  String toString() => 'WalletDbOpenPlan($status, migratedNow: $migratedNow)';
}

/// Test hook: return true to inject a failure at a named stage (proves
/// rollback). Never set outside tests.
typedef MigrationFault = bool Function(String stage);

class SqlcipherMigrationFailed implements Exception {
  const SqlcipherMigrationFailed(this.stage);
  final String stage;
  @override
  String toString() => 'SqlcipherMigrationFailed($stage)';
}

/// Decides how to open [file] and performs the one-time plaintext → SQLCipher
/// migration when needed. Idempotent; recovers an interrupted migration.
class WalletDbEncryption {
  WalletDbEncryption(this.keyStore, {this.fault});
  final DbKeyStore keyStore;
  final MigrationFault? fault;

  static File tempFor(File f) => File('${f.path}.sqlcipher-migrating');
  static File rollbackFor(File f) => File('${f.path}.pre-sqlcipher');

  void _stage(String name) {
    if (fault?.call(name) ?? false) throw SqlcipherMigrationFailed(name);
  }

  static void _deleteWithSidecars(File f) {
    for (final suffix in ['', '-journal', '-wal', '-shm']) {
      final x = File('${f.path}$suffix');
      if (x.existsSync()) x.deleteSync();
    }
  }

  Future<WalletDbOpenPlan> prepare(File file, String dbFileName) async {
    await _recoverInterrupted(file, dbFileName);
    switch (probeDbFile(file)) {
      case DbFileState.absent:
        final entry =
            await keyStore.load(dbFileName) ??
            await keyStore.create(dbFileName);
        return WalletDbOpenPlan(entry.key, DbEncryptionStatus.encrypted);
      case DbFileState.encrypted:
        return WalletDbOpenPlan(
          _verifiedKey(file, await _requireKey(dbFileName)),
          DbEncryptionStatus.encrypted,
        );
      case DbFileState.plaintext:
        try {
          final key = await _migrate(file, dbFileName);
          return WalletDbOpenPlan(
            key,
            DbEncryptionStatus.encrypted,
            migratedNow: true,
          );
        } on Object {
          // Any failure (key store, export, verification, injected fault):
          // the plaintext original is back in place and stays usable.
          if (probeDbFile(file) != DbFileState.plaintext) rethrow;
          return const WalletDbOpenPlan(
            null,
            DbEncryptionStatus.plaintextMigrationPending,
          );
        }
    }
  }

  Future<DbKeyEntry> _requireKey(String dbFileName) async {
    try {
      final entry = await keyStore.load(dbFileName);
      if (entry == null) throw const DbRecoveryRequired('key-missing');
      return entry;
    } on DbKeyUnavailable {
      throw const DbRecoveryRequired('key-unavailable');
    }
  }

  static Uint8List _verifiedKey(File file, DbKeyEntry entry) {
    final db = sqlite3.open(file.path, mode: OpenMode.readOnly);
    try {
      applySqlcipherKey(db, entry.key);
      if (entry.walletId != null) {
        final w = db.select('SELECT wallet_id FROM wallet_meta LIMIT 1');
        if (w.isNotEmpty && w.first['wallet_id'] != entry.walletId) {
          throw const DbRecoveryRequired('wallet-mismatch');
        }
      }
      return entry.key;
    } on DbRecoveryRequired {
      rethrow;
    } on SqliteException {
      throw const DbRecoveryRequired('key-mismatch');
    } finally {
      db.close();
    }
  }

  /// A crash between swap and cleanup leaves `.pre-sqlcipher`. No app write can
  /// have happened to the new file yet (cleanup precedes any open by the app),
  /// so the plaintext original is authoritative unless the encrypted file
  /// fully verifies.
  Future<void> _recoverInterrupted(File file, String dbFileName) async {
    final temp = tempFor(file);
    if (temp.existsSync()) _deleteWithSidecars(temp);
    final rollback = rollbackFor(file);
    if (!rollback.existsSync()) return;
    var finished = false;
    if (probeDbFile(file) == DbFileState.encrypted) {
      try {
        final entry = await keyStore.load(dbFileName);
        if (entry != null) {
          final db = sqlite3.open(file.path);
          try {
            applySqlcipherKey(db, entry.key);
            final source = sqlite3.open(rollback.path, mode: OpenMode.readOnly);
            try {
              finished =
                  captureSnapshot(db).sameDataAs(captureSnapshot(source));
            } finally {
              source.close();
            }
          } finally {
            db.close();
          }
        }
      } on Object {
        finished = false;
      }
    }
    if (finished) {
      _deleteWithSidecars(rollback);
    } else {
      if (file.existsSync()) _deleteWithSidecars(file);
      rollback.renameSync(file.path);
    }
  }

  Future<Uint8List> _migrate(File file, String dbFileName) async {
    // 1. Source snapshot, read-only (a hot journal/WAL is first recovered by a
    //    normal open, which only replays SQLite's own committed state).
    for (final side in ['-journal', '-wal']) {
      if (File('${file.path}$side').existsSync()) {
        sqlite3.open(file.path).close();
        break;
      }
    }
    final source = sqlite3.open(file.path, mode: OpenMode.readOnly);
    late final DbSnapshot before;
    try {
      before = captureSnapshot(source);
    } finally {
      source.close();
    }
    if (!before.healthy) throw const SqlcipherMigrationFailed('source-unhealthy');
    _stage('after-source-snapshot');

    // 2. Key: reuse an entry from an earlier failed attempt, else create one
    //    bound to the source walletId. Never overwrite.
    final entry =
        await keyStore.load(dbFileName) ??
        await keyStore.create(dbFileName, walletId: before.walletId);
    if (entry.walletId != null && entry.walletId != before.walletId) {
      throw const SqlcipherMigrationFailed('wallet-mismatch');
    }
    _stage('after-key');

    // 3. NEW encrypted temp DB, filled by sqlcipher_export from the read-only
    //    source. The original file is never written.
    final temp = tempFor(file);
    _deleteWithSidecars(temp);
    try {
      // uri: true so the ATTACH below honours `?mode=ro` on the source.
      final target = sqlite3.open(temp.path, uri: true);
      try {
        applySqlcipherKey(target, entry.key);
        final src = Uri.file(file.path).replace(queryParameters: {'mode': 'ro'});
        target.execute("ATTACH DATABASE ? AS plain KEY ''", ['$src']);
        target.select("SELECT sqlcipher_export('main', 'plain')");
        target.execute('DETACH DATABASE plain');
        target.userVersion = before.userVersion;
      } finally {
        target.close();
      }
      _stage('after-export');

      // 4. Verify the encrypted copy: unreadable without key, same data.
      _verifyEncryptedCopy(temp, entry.key, before);
      _stage('after-verify');

      // 5. Atomic swap, original kept as rollback until the final check.
      final rollback = rollbackFor(file);
      file.renameSync(rollback.path);
      _stage('after-rename-original');
      temp.renameSync(file.path);
      _stage('after-swap');
      _verifyEncryptedCopy(file, entry.key, before);
      _stage('after-final-verify');
      _deleteWithSidecars(rollback);
      return entry.key;
    } on Object catch (e) {
      // Restore: original plaintext back in place, derived files removed.
      final rollback = rollbackFor(file);
      if (rollback.existsSync()) {
        if (file.existsSync()) _deleteWithSidecars(file);
        rollback.renameSync(file.path);
      }
      if (temp.existsSync()) _deleteWithSidecars(temp);
      if (e is SqlcipherMigrationFailed) rethrow;
      throw SqlcipherMigrationFailed('error:${e.runtimeType}');
    }
  }

  static void _verifyEncryptedCopy(File f, Uint8List key, DbSnapshot before) {
    if (probeDbFile(f) != DbFileState.encrypted) {
      throw const SqlcipherMigrationFailed('not-encrypted');
    }
    final noKey = sqlite3.open(f.path, mode: OpenMode.readOnly);
    try {
      noKey.select('SELECT count(*) FROM sqlite_master');
      throw const SqlcipherMigrationFailed('readable-without-key');
    } on SqliteException {
      // expected: "file is not a database"
    } finally {
      noKey.close();
    }
    final db = sqlite3.open(f.path, mode: OpenMode.readOnly);
    try {
      applySqlcipherKey(db, key);
      final after = captureSnapshot(db);
      if (!after.healthy || !after.sameDataAs(before)) {
        throw const SqlcipherMigrationFailed('verify-mismatch');
      }
    } finally {
      db.close();
    }
  }
}
