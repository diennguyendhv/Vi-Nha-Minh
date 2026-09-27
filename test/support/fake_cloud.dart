import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
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
  final receiptWriters = <String, String>{}; // '$walletId/$batchId' → uid

  /// P10: email ĐÃ XÁC MINH của từng Account (máy chủ: token `email_verified`).
  final emails = <String, String>{};
  final invites = <String, Map<String, Object?>>{}; // token → invite
  final familyIndex = <String, String>{}; // uid → walletId
  final log = <String>[];
  int pageSize = 200;
  bool offline = false;

  /// Phiên Firebase có đăng nhập gần đây (máy chủ: `auth_time` ≤ 30 phút).
  bool recentAuth = true;

  /// Commit xong rồi mất câu trả lời (timeout sau khi máy chủ ghi).
  bool dropNextResponseAfterCommit = false;

  /// Chạy NGAY TRƯỚC khi batch được commit (mô phỏng người dùng sửa trong lúc gửi).
  Future<void> Function()? beforeCommit;

  /// Chạy TRƯỚC mỗi trang `getEncryptedChanges` (mô phỏng người khác ghi giữa chừng).
  Future<void> Function(int page)? beforePage;
  int _pages = 0;
  int _n = 0;

  static const familyOps = {
    'promoteToFamily',
    'createFamilyInvite',
    'cancelFamilyInvite',
    'getFamilyInvite',
    'acceptFamilyInvite',
    'getFamilyMembers',
    'putMemberKey',
    'getMemberKey',
    'registerMemberDeviceKey',
    'getMyFamily',
    'revokeFamilyMember',
  };

  int get writes => log.where((l) => l.startsWith('putEncryptedBatch')).length;

  String activate(String uid) {
    final s = base64Url
        .encode(BackupCrypto.randomBytes(32))
        .replaceAll('=', '');
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

  Never _fail(bool auth, [String? reason]) =>
      throw SessionFailure(auth, reason);

  void _authorize(Map<String, dynamic> d) {
    final uid = d['accountId'] as String;
    if (revoked.contains(uid)) _fail(true, 'DEVICE_REVOKED');
    if (secrets[uid] == null || d['secret'] != secrets[uid]) _fail(true);
  }

  String _access(String walletId, String uid) {
    final w = wallets[walletId];
    if (w == null) _fail(true, 'NOT_MEMBER');
    final m = memberships[walletId]?[uid];
    if (m == null || m['status'] != 'ACTIVE') _fail(true, 'NOT_MEMBER');
    return w['ownerAccountId']! as String;
  }

  Map<String, Object?> _ownerWallet(String walletId, String uid) {
    final w = wallets[walletId];
    if (w == null) _fail(false, 'NOT_CLAIMED');
    if (w['ownerAccountId'] != uid) _fail(true);
    return w;
  }

  List<Map<String, Object?>> _active(String walletId) => [
    for (final m
        in memberships[walletId]?.values ?? const <Map<String, Object?>>[])
      if (m['status'] == 'ACTIVE') m,
  ];

  static String _hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  /// P10: mô phỏng các hàm Family của máy chủ (hợp đồng thật: functions/test/family.test.js).
  Future<Map<String, dynamic>> _family(String op, Map<String, dynamic> d) async {
    final uid = d['accountId'] as String;
    final walletId = d['walletId'] as String?;
    _authorize(d);
    switch (op) {
      case 'promoteToFamily':
        if (!recentAuth) _fail(false, 'RECENT_LOGIN_REQUIRED');
        final w = _ownerWallet(walletId!, uid);
        final idem = w['kind'] == 'family';
        w['kind'] = 'family';
        return {'kind': 'family', 'idempotent': idem};
      case 'createFamilyInvite':
        if (!recentAuth) _fail(false, 'RECENT_LOGIN_REQUIRED');
        final w = _ownerWallet(walletId!, uid);
        final email = (d['inviteeEmail'] as String).trim().toLowerCase();
        if (emails[uid] == email) _fail(false, 'SELF_INVITE');
        if (w['kind'] != 'family') _fail(false, 'NOT_FAMILY');
        if (d['memberId'] == w['selfMemberId']) _fail(false, 'OWNER_MEMBER');
        final active = _active(walletId);
        if (active.length >= 2) _fail(false, 'FAMILY_FULL');
        if (active.any((m) => m['memberId'] == d['memberId'])) {
          _fail(false, 'MEMBER_BOUND');
        }
        for (final i in invites.values) {
          if (i['walletId'] == walletId && i['status'] == 'PENDING') {
            i['status'] = 'SUPERSEDED';
          }
        }
        final token = base64Url
            .encode(BackupCrypto.randomBytes(32))
            .replaceAll('=', '');
        final expires = DateTime.now().add(const Duration(hours: 48));
        invites[token] = {
          'walletId': walletId,
          'memberId': d['memberId'],
          'email': email,
          'status': 'PENDING',
          'expiresAt': expires.millisecondsSinceEpoch,
        };
        return {'token': token, 'expiresAt': expires.millisecondsSinceEpoch};
      case 'cancelFamilyInvite':
        _ownerWallet(walletId!, uid);
        var cancelled = false;
        for (final i in invites.values) {
          if (i['walletId'] == walletId && i['status'] == 'PENDING') {
            i['status'] = 'CANCELLED';
            cancelled = true;
          }
        }
        return {'cancelled': cancelled};
      case 'getFamilyInvite':
      case 'acceptFamilyInvite':
        final i = invites[d['token']];
        if (i == null ||
            i['status'] != 'PENDING' ||
            (i['expiresAt']! as int) <= DateTime.now().millisecondsSinceEpoch ||
            i['email'] != emails[uid]) {
          _fail(false, 'INVITE_INVALID');
        }
        if (op == 'getFamilyInvite') {
          return {
            'walletId': i['walletId'],
            'memberId': i['memberId'],
            'expiresAt': i['expiresAt'],
          };
        }
        if (!recentAuth) _fail(false, 'RECENT_LOGIN_REQUIRED');
        final wid = i['walletId']! as String;
        final w = wallets[wid]!;
        if (w['ownerAccountId'] == uid) _fail(false, 'SELF_INVITE');
        final active = _active(wid);
        if (active.length >= 2) _fail(false, 'FAMILY_FULL');
        if (active.any((m) => m['memberId'] == i['memberId'])) {
          _fail(false, 'MEMBER_BOUND');
        }
        memberships[wid]![uid] = {
          'accountId': uid,
          'role': 'MEMBER',
          'status': 'ACTIVE',
          'memberId': i['memberId'],
          'publicKey': d['publicKey'],
          'keyInstallationId': d['installationId'],
          'wrappedKey': null,
        };
        i['status'] = 'ACCEPTED';
        familyIndex[uid] = wid;
        return {
          'walletId': wid,
          'memberId': i['memberId'],
          'ownerAccountId': w['ownerAccountId'],
        };
      case 'getFamilyMembers':
        _access(walletId!, uid);
        final w = wallets[walletId]!;
        return {
          'kind': w['kind'],
          'ownerAccountId': w['ownerAccountId'],
          'members': [
            for (final MapEntry(key: acc, value: m)
                in memberships[walletId]!.entries)
              {
                'accountId': acc,
                'role': m['role'],
                'status': m['status'],
                'memberId': m['memberId'],
                'publicKey': m['publicKey'],
                'keyInstallationId': m['keyInstallationId'],
                'hasKey': m['wrappedKey'] != null,
              },
          ],
        };
      case 'putMemberKey':
        if (!recentAuth) _fail(false, 'RECENT_LOGIN_REQUIRED');
        _ownerWallet(walletId!, uid);
        final m = memberships[walletId]![d['memberAccountId']];
        if (m == null || m['status'] != 'ACTIVE' || m['role'] != 'MEMBER') {
          _fail(false, 'NOT_MEMBER');
        }
        final hash = _hex(
          (await const DartSha256().hash(
            base64.decode(m['publicKey']! as String),
          )).bytes,
        );
        if (hash != d['publicKeyHash'] ||
            m['keyInstallationId'] != d['keyInstallationId']) {
          _fail(false, 'PUBLIC_KEY_CHANGED');
        }
        m['wrappedKey'] = d['wrapped'];
        return {'shared': true};
      case 'getMemberKey':
        final m = memberships[walletId]?[uid];
        if (m == null || m['status'] != 'ACTIVE' || m['role'] != 'MEMBER') {
          _fail(true, 'NOT_MEMBER');
        }
        if (m['keyInstallationId'] != d['installationId']) {
          _fail(false, 'KEY_DEVICE_MISMATCH');
        }
        if (m['wrappedKey'] == null) _fail(false, 'KEY_NOT_SHARED');
        return {
          'wrapped': m['wrappedKey'],
          'memberId': m['memberId'],
          'ownerAccountId': wallets[walletId]!['ownerAccountId'],
          'keyInstallationId': m['keyInstallationId'],
          'publicKey': m['publicKey'],
        };
      case 'registerMemberDeviceKey':
        if (!recentAuth) _fail(false, 'RECENT_LOGIN_REQUIRED');
        final m = memberships[walletId]?[uid];
        if (m == null || m['status'] != 'ACTIVE' || m['role'] != 'MEMBER') {
          _fail(true, 'NOT_MEMBER');
        }
        m
          ..['publicKey'] = d['publicKey']
          ..['keyInstallationId'] = d['installationId']
          ..['wrappedKey'] = null;
        return {'registered': true};
      case 'getMyFamily':
        final wid = familyIndex[uid];
        final m = wid == null ? null : memberships[wid]?[uid];
        if (m == null || m['status'] != 'ACTIVE') return {'member': false};
        return {
          'member': true,
          'walletId': wid,
          'memberId': m['memberId'],
          'ownerAccountId': wallets[wid]!['ownerAccountId'],
          'hasKey': m['wrappedKey'] != null,
          'keyInstallationId': m['keyInstallationId'],
        };
      case 'revokeFamilyMember':
        if (!recentAuth) _fail(false, 'RECENT_LOGIN_REQUIRED');
        _ownerWallet(walletId!, uid);
        final target = d['memberAccountId'] as String;
        final m = memberships[walletId]![target];
        if (m == null || m['role'] != 'MEMBER') _fail(false, 'NOT_MEMBER');
        m
          ..['status'] = 'REVOKED'
          ..['wrappedKey'] = null
          ..['publicKey'] = null
          ..['keyInstallationId'] = null;
        if (familyIndex[target] == walletId) familyIndex.remove(target);
        return {'revoked': true};
    }
    throw StateError(op);
  }

  Future<Map<String, dynamic>> call(String op, Map<String, dynamic> raw) async {
    final d = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
    log.add('$op#${_n++}');
    if (offline) _fail(false);
    final uid = d['accountId'] as String;
    final walletId = d['walletId'] as String?;
    if (familyOps.contains(op)) return _family(op, d);
    switch (op) {
      case 'putBackupKeyring':
        _authorize(d);
        final key = '$uid/$walletId';
        if (d['mode'] == 'rotateRecovery') {
          final k = keyrings[key];
          if (k == null) _fail(false, 'NO_KEYRING');
          if (!recentAuth) _fail(false, 'RECENT_LOGIN_REQUIRED');
          if (k['recoveryRotationId'] == d['rotationId']) {
            if (k['recoveryProof'] == d['recoveryProof']) {
              return {'rev': k['rev']};
            }
            _fail(false, 'KEYRING_CHANGED');
          }
          if (k['rev'] != d['expectedRev']) _fail(false, 'KEYRING_CHANGED');
          k
            ..['rev'] = (k['rev']! as int) + 1
            ..['recovery'] = d['recovery']
            ..['recoveryProof'] = d['recoveryProof']
            ..['recoveryRotationId'] = d['rotationId'];
          if (dropNextResponseAfterCommit) {
            dropNextResponseAfterCommit = false;
            _fail(false);
          }
          return {'rev': k['rev']};
        }
        if (keyrings.containsKey(key)) _fail(false, 'KEYRING_EXISTS');
        keyrings[key] = {
          'cryptoVersion': 1,
          'rev': 1,
          'password': d['password'],
          'recovery': d['recovery'],
          'passwordProof': d['passwordProof'],
          'recoveryProof': d['recoveryProof'],
        };
        return {'rev': 1};
      case 'getBackupKeyring':
        if (d['secret'] != null) _authorize(d);
        final k =
            keyrings['$uid/$walletId'] ??
            keyrings['${wallets[walletId]?['ownerAccountId']}/$walletId'];
        if (k == null) _fail(false, 'NO_KEYRING');
        // Như máy chủ: chỉ slot đã bọc, không bao giờ proof/id xoay.
        return {
          for (final f in ['cryptoVersion', 'rev', 'password', 'recovery'])
            f: k[f],
        };
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
        final m = memberships[walletId]?[uid];
        if (w['ownerAccountId'] != uid &&
            (m == null || m['status'] != 'ACTIVE')) {
          return {'claimed': true, 'ownedByYou': false};
        }
        if (w['ownerAccountId'] != uid) {
          return {
            'claimed': true,
            'ownedByYou': false,
            'isMember': true,
            'walletId': walletId,
            'selfMemberId': m!['memberId'],
            'kind': w['kind'],
            'headRev': w['headRev'],
          };
        }
        return {
          ...w,
          'claimed': true,
          'ownedByYou': w['ownerAccountId'] == uid,
        };
      case 'putEncryptedBatch':
        _authorize(d);
        final owner = _access(walletId!, uid);
        final w = wallets[walletId]!;
        if (!['SEEDING', 'COMPLETE'].contains(w['backupState'])) {
          _fail(false, 'BACKUP_NOT_ENABLED');
        }
        if (!keyrings.containsKey('$owner/$walletId')) {
          _fail(false, 'NO_KEYRING');
        }
        final envs = (d['envelopes'] as List).cast<Map<String, dynamic>>();
        if (envs.isEmpty || envs.length > 100) _fail(false);
        final r = receipts.putIfAbsent(walletId, () => {});
        final batchId = d['batchId'] as String;
        if (r[batchId] != null) {
          // Biên nhận chỉ cho ĐÚNG người ghi (máy chủ: BATCH_ID_CONFLICT).
          if (receiptWriters['$walletId/$batchId'] != uid) {
            _fail(false, 'BATCH_ID_CONFLICT');
          }
          return {'headRev': r[batchId], 'duplicate': true};
        }
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
        receiptWriters['$walletId/$batchId'] = uid;
        if (dropNextResponseAfterCommit) {
          dropNextResponseAfterCommit = false;
          _fail(false);
        }
        return {'headRev': headRev, 'duplicate': false};
      case 'getEncryptedChanges':
        _authorize(d);
        _access(walletId!, uid);
        final hook = beforePage;
        if (hook != null) {
          beforePage = null;
          await hook(_pages++);
          beforePage = hook;
        }
        final w = wallets[walletId]!;
        final since = d['sinceRev'] as int;
        final all =
            (entities[walletId]?.values.toList() ?? [])
                .where((e) => (e['serverRev']! as int) > since)
                .toList()
              ..sort(
                (a, b) =>
                    (a['serverRev']! as int).compareTo(b['serverRev']! as int),
              );
        var page = all.take(pageSize + 1).toList();
        var more = false;
        if (page.length > pageSize) {
          more = true;
          final cut = page[pageSize]['serverRev'];
          final kept = page
              .where((e) => (e['serverRev']! as int) < (cut! as int))
              .toList();
          // 1 batch lớn hơn trang (máy chủ thật: batch ≤ 101 < trang 200) ⇒ trả trọn batch.
          page = kept.isNotEmpty
              ? kept
              : all
                    .where((e) => e['serverRev'] == all.first['serverRev'])
                    .toList();
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
  Future<({String walletId, Uint8List bmk})?> load(String uid) async =>
      map[uid];
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
  Future<void> write(String uid, Map<String, dynamic> c) async =>
      values[uid] = c;
  @override
  Future<void> clear() async => values.clear();
}

/// 1 thiết bị: DB cục bộ + phiên P7.1 + Keystore BMK + engine.
class FakeDevice {
  FakeDevice(this.cloud, {AppDatabase? db, String? installation})
    : db =
          db ??
          AppDatabase.forTesting(
            NativeDatabase.memory(),
            seed: SeedProfile.fresh,
          ),
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
  static const testKdf = KdfParams(
    memoryKib: 19456,
    iterations: 2,
    parallelism: 1,
  );
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

  /// Đăng xuất Firebase trên máy này (phiên P7.1 của Account vẫn nằm trên máy chủ).
  void signOut() => account = null;

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
