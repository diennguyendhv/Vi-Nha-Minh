import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:vi_nha_minh/core/config/app_environment.dart';
import 'package:vi_nha_minh/core/crypto/backup_crypto.dart';
import 'package:vi_nha_minh/data/backup/backup_key_store.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/seed_defaults.dart';
import 'package:vi_nha_minh/data/local/sync/cloud_binding_store.dart';
import 'package:vi_nha_minh/data/sync/cloud_sync_engine.dart';
import 'package:vi_nha_minh/domain/auth/cloud_session.dart';

/// Bản sao ngữ nghĩa backend P7.1/P8 (functions/index.js) đủ cho test engine phía app:
/// phiên hiện hành, keyring, claim, membership, batch CAS + biên nhận idempotent, trang
/// kéo theo ranh giới batch. Hợp đồng thật được kiểm ở emulator (functions/test).
class FakeCloud {
  final secrets = <String, String>{};
  final revoked = <String>{};
  final keyrings = <String, Map<String, Object?>>{}; // '$uid/$walletId'
  final wallets = <String, Map<String, Object?>>{};
  final memberships = <String, Map<String, Map<String, Object?>>>{};
  final entities = <String, Map<String, Map<String, Object?>>>{};
  final receipts = <String, Map<String, int>>{};
  final log = <String>[];
  int pageSize = 200;
  bool offline = false;

  /// Commit xong rồi mất câu trả lời (timeout sau khi máy chủ ghi).
  bool dropNextResponseAfterCommit = false;

  /// Chạy NGAY TRƯỚC khi batch được commit (mô phỏng người dùng sửa trong lúc gửi).
  Future<void> Function()? beforeCommit;
  int _n = 0;

  int get writes => log.where((l) => l.startsWith('putEncryptedBatch')).length;

  String activate(String uid) {
    final s = base64Url.encode(BackupCrypto.randomBytes(32)).replaceAll('=', '');
    secrets[uid] = s;
    return s;
  }

  /// Ví đã claim bởi [owner] (chỉ metadata — như P8.2).
  void claim(String walletId, String owner, String selfMemberId) {
    wallets[walletId] = {
      'state': 'CLAIMED',
      'kind': 'personal',
      'ownerAccountId': owner,
      'selfMemberId': selfMemberId,
      'headRev': 0,
    };
    memberships[walletId] = {
      owner: {'role': 'OWNER', 'status': 'ACTIVE', 'memberId': selfMemberId},
    };
  }

  Never _fail(bool auth, [String? reason]) => throw SessionFailure(auth, reason);

  void _authorize(Map<String, dynamic> d) {
    final uid = d['accountId'] as String;
    if (revoked.contains(uid)) _fail(true, 'DEVICE_REVOKED');
    if (secrets[uid] == null || d['secret'] != secrets[uid]) _fail(true);
  }

  String _access(String walletId, String uid) {
    final w = wallets[walletId];
    if (w == null) _fail(true);
    final m = memberships[walletId]?[uid];
    if (m == null || m['status'] != 'ACTIVE') _fail(true);
    return w['ownerAccountId']! as String;
  }

  Future<Map<String, dynamic>> call(String op, Map<String, dynamic> raw) async {
    final d = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
    log.add('$op#${_n++}');
    if (offline) _fail(false);
    final uid = d['accountId'] as String;
    final walletId = d['walletId'] as String?;
    switch (op) {
      case 'putBackupKeyring':
        _authorize(d);
        final key = '$uid/$walletId';
        if (keyrings.containsKey(key)) _fail(false, 'KEYRING_EXISTS');
        keyrings[key] = {
          'cryptoVersion': 1,
          'rev': 1,
          'password': d['password'],
          'recovery': d['recovery'],
        };
        return {'rev': 1};
      case 'getBackupKeyring':
        if (d['secret'] != null) _authorize(d);
        final k = keyrings['$uid/$walletId'] ??
            keyrings['${wallets[walletId]?['ownerAccountId']}/$walletId'];
        if (k == null) _fail(false, 'NO_KEYRING');
        return Map<String, dynamic>.from(k);
      case 'enableBackup':
        _authorize(d);
        final w = wallets[walletId];
        if (w == null) _fail(false, 'NOT_CLAIMED');
        if (w['ownerAccountId'] != uid) _fail(true);
        if (!keyrings.containsKey('$uid/$walletId')) _fail(false, 'NO_KEYRING');
        w['backupState'] ??= 'SEEDING';
        return {'backupState': w['backupState'], 'headRev': w['headRev']};
      case 'getWalletClaim':
        _authorize(d);
        final w = wallets[walletId];
        if (w == null) return {'claimed': false};
        if (w['ownerAccountId'] != uid && memberships[walletId]?[uid] == null) {
          return {'claimed': true, 'ownedByYou': false};
        }
        return {...w, 'claimed': true, 'ownedByYou': w['ownerAccountId'] == uid};
      case 'putEncryptedBatch':
        _authorize(d);
        final owner = _access(walletId!, uid);
        final w = wallets[walletId]!;
        if (!['SEEDING', 'COMPLETE'].contains(w['backupState'])) {
          _fail(false, 'BACKUP_NOT_ENABLED');
        }
        if (!keyrings.containsKey('$owner/$walletId')) _fail(false, 'NO_KEYRING');
        final envs = (d['envelopes'] as List).cast<Map<String, dynamic>>();
        if (envs.isEmpty || envs.length > 100) _fail(false);
        final r = receipts.putIfAbsent(walletId, () => {});
        final batchId = d['batchId'] as String;
        if (r[batchId] != null) return {'headRev': r[batchId], 'duplicate': true};
        final head = w['headRev']! as int;
        if (head != d['baseHeadRev']) _fail(false, 'HEAD_MOVED');
        final store = entities.putIfAbsent(walletId, () => {});
        for (final e in envs) {
          final stored = store[e['id']];
          if (stored != null && (stored['rev']! as int) >= (e['rev'] as int)) {
            _fail(false, 'STALE_REV');
          }
        }
        await beforeCommit?.call();
        beforeCommit = null;
        final headRev = head + 1;
        w['headRev'] = headRev;
        if (d['checkpoint'] == true) {
          w['checkpointRev'] = headRev;
          if (w['backupState'] == 'SEEDING') w['backupState'] = 'COMPLETE';
        }
        for (final e in envs) {
          store[e['id'] as String] = {...e, 'serverRev': headRev};
        }
        r[batchId] = headRev;
        if (dropNextResponseAfterCommit) {
          dropNextResponseAfterCommit = false;
          _fail(false);
        }
        return {'headRev': headRev, 'duplicate': false};
      case 'getEncryptedChanges':
        _authorize(d);
        _access(walletId!, uid);
        final w = wallets[walletId]!;
        final since = d['sinceRev'] as int;
        final all = (entities[walletId]?.values.toList() ?? [])
            .where((e) => (e['serverRev']! as int) > since)
            .toList()
          ..sort((a, b) => (a['serverRev']! as int).compareTo(b['serverRev']! as int));
        var page = all.take(pageSize + 1).toList();
        var more = false;
        if (page.length > pageSize) {
          more = true;
          final cut = page[pageSize]['serverRev'];
          page = page.where((e) => (e['serverRev']! as int) < (cut! as int)).toList();
        }
        return {
          'headRev': w['headRev'],
          'throughRev': more ? page.last['serverRev'] : w['headRev'],
          'more': more,
          'checkpointRev': w['checkpointRev'],
          'backupState': w['backupState'],
          'envelopes': page,
        };
    }
    throw StateError(op);
  }

  /// Toàn bộ những gì máy chủ lưu (để quét bản rõ).
  String dump() => jsonEncode({
    'keyrings': keyrings,
    'wallets': wallets,
    'memberships': memberships,
    'entities': entities,
    'receipts': receipts,
  });
}

class MemoryBackupKeyStore implements BackupKeyStore {
  final map = <String, ({String walletId, Uint8List bmk})>{};
  @override
  Future<({String walletId, Uint8List bmk})?> load(String uid) async => map[uid];
  @override
  Future<void> store(String uid, String walletId, Uint8List bmk) async =>
      map[uid] = (walletId: walletId, bmk: Uint8List.fromList(bmk));
  @override
  Future<void> clear() async => map.clear();
}

class MemorySessionStorage implements SessionStorage {
  MemorySessionStorage(this.installation);
  final String installation;
  final values = <String, Map<String, dynamic>>{};
  @override
  Future<String> installationId() async => installation;
  @override
  Future<Map<String, dynamic>?> read(String uid) async => values[uid];
  @override
  Future<void> write(String uid, Map<String, dynamic> c) async => values[uid] = c;
  @override
  Future<void> clear() async => values.clear();
}

/// 1 thiết bị: DB cục bộ + phiên P7.1 + Keystore BMK + engine.
class FakeDevice {
  FakeDevice(this.cloud, {AppDatabase? db, String? installation})
    : db = db ?? AppDatabase.forTesting(NativeDatabase.memory(), seed: SeedProfile.fresh),
      storage = MemorySessionStorage(
        installation ?? '11111111-1111-4111-8111-111111111111',
      ) {
    session = CloudSession(storage, cloud.call, () => account);
    session.revokedHandlers.add(keys.clear);
    engine = CloudSyncEngine(
      db: this.db,
      session: session,
      transport: cloud.call,
      keyStore: keys,
      env: AppEnvironment.dev,
      kdf: testKdf,
    );
  }
  static const testKdf = KdfParams(memoryKib: 19456, iterations: 2, parallelism: 1);
  final FakeCloud cloud;
  AppDatabase db;
  final MemorySessionStorage storage;
  final keys = MemoryBackupKeyStore();
  late final CloudSession session;
  late CloudSyncEngine engine;
  String? account;

  void rebuildEngine() => engine = CloudSyncEngine(
    db: db,
    session: session,
    transport: cloud.call,
    keyStore: keys,
    env: AppEnvironment.dev,
    kdf: testKdf,
  );

  Future<String> walletId() async =>
      (await db.select(db.walletMeta).getSingle()).walletId;

  /// Đăng nhập [uid] + phiên P7.1 hiện hành trên máy này.
  Future<void> signIn(String uid) async {
    account = uid;
    storage.values[uid] = {
      'accountId': uid,
      'installationId': storage.installation,
      'generation': 1,
      'epoch': 1,
      'secret': cloud.activate(uid),
    };
  }

  /// Claim P8.2 (cục bộ + máy chủ) cho Account hiện tại.
  Future<void> claim({String? selfMemberId}) async {
    final members = await db.select(db.financialMemberRows).get();
    final self = selfMemberId ?? members.first.memberId;
    final wid = await walletId();
    cloud.claim(wid, account!, self);
    final store = CloudBindingStore(db);
    await store.beginClaim(
      accountId: account!,
      selfMemberId: self,
      environment: 'dev',
      claimRequestId: 'c-1',
    );
    await store.activate(claimRequestId: 'c-1');
  }
}
