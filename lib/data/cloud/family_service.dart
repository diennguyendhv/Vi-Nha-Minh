import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:drift/drift.dart';

import '../../core/config/app_environment.dart';
import '../../core/config/cloud_policy.dart';
import '../../core/crypto/backup_crypto.dart' show BackupKeyException;
import '../../core/crypto/family_key_crypto.dart';
import '../../domain/auth/cloud_session.dart';
import '../../domain/entities/wallet_identity.dart';
import '../backup/backup_key_store.dart';
import '../local/app_database.dart';
import '../local/wallet_registry.dart';
import '../local/wallet_registry_bootstrap.dart';
import '../sync/restore_engine.dart';
import 'family_device_key_store.dart';

/// Thao tác Family bị chặn ở tầng app, hoặc lý do dứt khoát của máy chủ
/// (`FAMILY_FULL`, `MEMBER_BOUND`, `INVITE_INVALID`, `PUBLIC_KEY_CHANGED`, …).
class FamilyException implements Exception {
  const FamilyException(this.reason);

  /// App: `blocked-environment`, `no-wallet-key`, `not-family`, `no-device-key`,
  /// `device-key-mismatch`, `key-not-shared`, `wrong-key`, `not-member`,
  /// `member-mismatch` (máy chủ trả về FinancialMember khác cái Owner đã chọn lúc mời).
  final String reason;
  @override
  String toString() => 'FamilyException($reason)';
}

/// 1 Account trong ví Family (Owner hoặc Member). [label] = tên FinancialMember LẤY
/// TỪ DB CỤC BỘ (máy chủ không bao giờ biết tên). [fingerprint] chỉ có khi Member đã
/// đăng ký khoá thiết bị.
class FamilyAccountView {
  const FamilyAccountView({
    required this.accountId,
    required this.role,
    required this.status,
    required this.memberId,
    required this.hasKey,
    this.label,
    this.publicKey,
    this.keyInstallationId,
    this.fingerprint,
  });
  final String accountId;
  final String role; // OWNER | MEMBER
  final String status; // ACTIVE | REVOKED
  final String memberId;
  final bool hasKey;
  final String? label;
  final String? publicKey;
  final String? keyInstallationId;
  final String? fingerprint;

  bool get isActiveMember => role == 'MEMBER' && status == 'ACTIVE';

  /// Member đã đăng ký khoá thiết bị nhưng Owner chưa bọc khoá ví cho nó.
  bool get awaitingKey =>
      isActiveMember && !hasKey && publicKey != null && fingerprint != null;
}

class FamilyStatus {
  const FamilyStatus({
    required this.kind,
    required this.isOwner,
    required this.accounts,
  });
  final String? kind; // personal | family
  final bool isOwner;
  final List<FamilyAccountView> accounts;
  bool get isFamily => kind == 'family';
  FamilyAccountView? get activeMember =>
      accounts.where((a) => a.isActiveMember).firstOrNull;
}

class FamilyInvitePreview {
  const FamilyInvitePreview(this.walletId, this.memberId, this.expiresAt);
  final String walletId;
  final String memberId;
  final DateTime expiresAt;
}

/// Lựa chọn "Tài khoản được mời là ai trong ví?" — thành viên ĐÃ CÓ, trừ chính Owner.
class FamilyMemberChoice {
  const FamilyMemberChoice(this.memberId, this.label);
  final String memberId;
  final String label;
}

/// P10 — Family v1 phía app. Mọi quyền do máy chủ quyết (phiên P7.1 + Membership);
/// khoá ví (BMK) chỉ đi qua máy chủ ở dạng đã bọc cho ĐÚNG thiết bị Member
/// ([FamilyKeyCrypto]). Owner/Member là QUYỀN; Vợ/Chồng là FinancialMember ĐÃ CÓ do
/// Owner chọn tường minh — không bao giờ suy từ email/uid.
///
/// [db]/[dbFileName] = ví đang mở (phía Owner). Phía Member (chưa có ví) chỉ dùng các
/// hàm [preview]/[accept]/[myFamily]/[join].
class FamilyService {
  FamilyService({
    required this.session,
    required SessionTransport transport,
    required this.keyStore,
    required this.deviceKeys,
    required this.registry,
    this.db,
    this.dbFileName,
    this.restore,
    AppEnvironment? env,
  }) : _send = transport,
       env = env ?? AppEnvironment.current;

  final CloudSession session;
  final SessionTransport _send;
  final BackupKeyStore keyStore;
  final FamilyDeviceKeyStore deviceKeys;
  final WalletRegistry registry;
  final AppDatabase? db;
  final String? dbFileName;
  final RestoreEngine? restore;
  final AppEnvironment env;
  int calls = 0;

  /// `wallet_settings`: memberId Owner đã chọn TƯỜNG MINH lúc tạo lời mời. Nằm trong
  /// dữ liệu ví (mã hoá bằng BMK khi đồng bộ) ⇒ máy chủ không sửa được. [shareKey] so
  /// khớp với memberId máy chủ trả về; lệch/thiếu ⇒ dừng, không bọc BMK.
  static const invitedMemberKey = 'family_invited_member_id';

  /// DEV, hoặc PROD đã bật cloud tường minh ([CloudPolicy]).
  static bool allowedIn(AppEnvironment env) => CloudPolicy.enabledIn(env);

  void _requireAllowed() {
    if (!allowedIn(env)) throw const FamilyException('blocked-environment');
  }

  String _uid() => session.accountId() ?? (throw const SessionFailure(true));

  Future<Map<String, dynamic>> _call(
    String op,
    Map<String, dynamic> data,
  ) async {
    calls++;
    try {
      return await _send(op, {...await session.credential(), ...data});
    } on SessionFailure catch (e) {
      if (CloudSession.revokedReasons.contains(e.reason)) {
        await session.handleRevoked();
      }
      rethrow;
    }
  }

  Future<String> _walletId() async =>
      (await db!.select(db!.walletMeta).getSingle()).walletId;

  // ---------------------------------------------------------------------------
  // Owner
  // ---------------------------------------------------------------------------

  /// Trạng thái Family của ví đang mở (1 lời gọi, chỉ khi người dùng mở màn hình).
  Future<FamilyStatus> status() async {
    _requireAllowed();
    final uid = _uid();
    final walletId = await _walletId();
    final r = await _call('getFamilyMembers', {'walletId': walletId});
    final labels = {
      for (final m in await db!.select(db!.financialMemberRows).get())
        m.memberId: m.label,
    };
    final owner = r['ownerAccountId'] as String;
    final accounts = <FamilyAccountView>[];
    for (final raw in r['members'] as List) {
      final m = Map<String, Object?>.from(raw as Map);
      final pub = m['publicKey'] as String?;
      final installation = m['keyInstallationId'] as String?;
      String? fp;
      if (m['role'] == 'MEMBER' && pub != null && installation != null) {
        fp = await FamilyKeyCrypto.fingerprint(
          FamilyKeyContext(
            walletId: walletId,
            ownerAccountId: owner,
            recipientAccountId: m['accountId']! as String,
            recipientMemberId: m['memberId']! as String,
            recipientInstallationId: installation,
            recipientPublicKey: base64.decode(pub),
          ),
        );
      }
      accounts.add(
        FamilyAccountView(
          accountId: m['accountId']! as String,
          role: m['role']! as String,
          status: m['status']! as String,
          memberId: m['memberId']! as String,
          hasKey: m['hasKey'] == true,
          label: labels[m['memberId']],
          publicKey: pub,
          keyInstallationId: installation,
          fingerprint: fp,
        ),
      );
    }
    return FamilyStatus(
      kind: r['kind'] as String?,
      isOwner: owner == uid,
      accounts: accounts,
    );
  }

  /// Thành viên có thể gán cho Account được mời: mọi FinancialMember ĐÃ CÓ trừ thành
  /// viên của chính Owner. Không có lựa chọn mặc định (UI bắt chọn).
  Future<List<FamilyMemberChoice>> inviteChoices(String ownerMemberId) async => [
    for (final m
        in await (db!.select(
          db!.financialMemberRows,
        )..orderBy([(m) => OrderingTerm.asc(m.displayOrder)])).get())
      if (m.memberId != ownerMemberId) FamilyMemberChoice(m.memberId, m.label),
  ];

  /// "Chia sẻ với gia đình": nâng ví Personal ĐÃ claim thành Family TẠI CHỖ — cùng
  /// walletId, cùng file SQLite, cùng BMK/bản sao lưu; không sao chép ví. Máy chủ
  /// idempotent; rồi `wallet_meta.kind` = family (ghi riêng, không vào outbox) và
  /// registry phản chiếu DB. Cần step-up (máy chủ đòi đăng nhập gần đây).
  Future<void> promote() async {
    _requireAllowed();
    final walletId = await _walletId();
    await _call('promoteToFamily', {'walletId': walletId});
    await db!.update(db!.walletMeta).write(
      WalletMetaCompanion(kind: Value(WalletKind.family.name)),
    );
    await reconcileRegistryFromDb(registry, db!, dbFileName!);
  }

  /// Owner mời 1 Account (email đã xác minh) làm [memberId] ĐÃ CÓ. Trả token dùng 1
  /// lần (máy chủ chỉ lưu băm) để Owner gửi cho người được mời.
  Future<({String token, DateTime expiresAt})> invite({
    required String memberId,
    required String email,
  }) async {
    _requireAllowed();
    final r = await _call('createFamilyInvite', {
      'walletId': await _walletId(),
      'memberId': memberId,
      'inviteeEmail': email.trim(),
    });
    await db!
        .into(db!.walletSettings)
        .insertOnConflictUpdate(
          WalletSettingsCompanion.insert(key: invitedMemberKey, value: memberId),
        );
    return (
      token: r['token'] as String,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(r['expiresAt'] as int),
    );
  }

  Future<void> cancelInvite() async {
    _requireAllowed();
    await _call('cancelFamilyInvite', {'walletId': await _walletId()});
  }

  /// Owner đã đối chiếu [FamilyAccountView.fingerprint] với màn hình người được mời
  /// ⇒ bọc BMK (đang giữ trong Keystore) cho ĐÚNG thiết bị đó, ghim public key hash +
  /// installation. Máy chủ đổi khoá giữa chừng ⇒ `PUBLIC_KEY_CHANGED`.
  Future<void> shareKey(FamilyAccountView member) async {
    _requireAllowed();
    final uid = _uid();
    final walletId = await _walletId();
    final held = await keyStore.load(uid);
    if (held == null || held.walletId != walletId) {
      throw const FamilyException('no-wallet-key');
    }
    if (!member.isActiveMember ||
        member.publicKey == null ||
        member.keyInstallationId == null) {
      throw const FamilyException('not-member');
    }
    // Không tin máy chủ lặng lẽ đổi FinancialMember: vân tay 12 số được tính từ CÙNG
    // memberId máy chủ đưa cho cả 2 máy nên không tự phát hiện được việc này.
    final chosen = await (db!.select(
      db!.walletSettings,
    )..where((s) => s.key.equals(invitedMemberKey))).getSingleOrNull();
    if (chosen == null || chosen.value != member.memberId) {
      throw const FamilyException('member-mismatch');
    }
    final pub = base64.decode(member.publicKey!);
    final wrapped = await FamilyKeyCrypto.wrapBmk(
      held.bmk,
      FamilyKeyContext(
        walletId: walletId,
        ownerAccountId: uid,
        recipientAccountId: member.accountId,
        recipientMemberId: member.memberId,
        recipientInstallationId: member.keyInstallationId!,
        recipientPublicKey: pub,
      ),
    );
    await _call('putMemberKey', {
      'walletId': walletId,
      'memberAccountId': member.accountId,
      'publicKeyHash': _hex(await _sha256(pub)),
      'keyInstallationId': member.keyInstallationId,
      'wrapped': wrapped,
    });
  }

  /// Owner thu hồi Member: máy chủ chặn mọi truy cập cloud tương lai ngay. Không xoá
  /// được dữ liệu đã lưu trên máy Member (giới hạn trung thực — xem tài liệu).
  Future<void> revoke(FamilyAccountView member) async {
    _requireAllowed();
    await _call('revokeFamilyMember', {
      'walletId': await _walletId(),
      'memberAccountId': member.accountId,
    });
  }

  /// Mã ví (cam kết BMK) của ví đang mở — hiện trên cả máy Owner và Member.
  Future<String?> walletCode() async {
    final uid = session.accountId();
    if (uid == null || db == null) return null;
    final walletId = await _walletId();
    final held = await keyStore.load(uid);
    if (held == null || held.walletId != walletId) return null;
    return FamilyKeyCrypto.walletCode(held.bmk, walletId);
  }

  // ---------------------------------------------------------------------------
  // Member
  // ---------------------------------------------------------------------------

  Future<FamilyInvitePreview> preview(String token) async {
    _requireAllowed();
    final r = await _call('getFamilyInvite', {'token': token.trim()});
    return FamilyInvitePreview(
      r['walletId'] as String,
      r['memberId'] as String,
      DateTime.fromMillisecondsSinceEpoch(r['expiresAt'] as int),
    );
  }

  /// Khoá thiết bị của ĐÚNG installation hiện hành: có rồi ⇒ dùng lại (thử lại / lời
  /// gọi bị từ chối không bao giờ làm mất khoá đã đăng ký); chưa có ⇒ sinh mới và lưu
  /// Keystore TRƯỚC khi public key rời máy.
  Future<FamilyDeviceKey> _deviceKey(String uid, String installation) async {
    final held = await deviceKeys.load(uid);
    if (held != null && held.installationId == installation) return held.key;
    final device = await FamilyDeviceKey.generate();
    await deviceKeys.store(uid, installation, device);
    return device;
  }

  /// Chấp nhận TƯỜNG MINH: khoá thiết bị X25519 của installation này (lưu Keystore
  /// trước khi gửi public key), máy chủ gắn Account này vào memberId Owner đã chọn. Trả
  /// về vân tay để 2 người đối chiếu trước khi Owner bọc khoá.
  Future<({String walletId, String memberId, String fingerprint})> accept(
    String token,
  ) async {
    _requireAllowed();
    final uid = _uid();
    final installation =
        (await session.credential())['installationId'] as String;
    final device = await _deviceKey(uid, installation);
    final r = await _call('acceptFamilyInvite', {
      'token': token.trim(),
      'publicKey': base64.encode(device.publicKey),
    });
    final walletId = r['walletId'] as String;
    final memberId = r['memberId'] as String;
    return (
      walletId: walletId,
      memberId: memberId,
      fingerprint: await FamilyKeyCrypto.fingerprint(
        FamilyKeyContext(
          walletId: walletId,
          ownerAccountId: r['ownerAccountId'] as String,
          recipientAccountId: uid,
          recipientMemberId: memberId,
          recipientInstallationId: installation,
          recipientPublicKey: device.publicKey,
        ),
      ),
    );
  }

  /// Membership Family của Account này (máy chủ) + vân tay thiết bị này (nếu có khoá).
  Future<
    ({
      bool member,
      String? walletId,
      String? memberId,
      bool hasKey,
      String? fingerprint,
      bool thisDevice,
    })
  >
  myFamily() async {
    _requireAllowed();
    final uid = _uid();
    final r = await _call('getMyFamily', {});
    if (r['member'] != true) {
      return (
        member: false,
        walletId: null,
        memberId: null,
        hasKey: false,
        fingerprint: null,
        thisDevice: false,
      );
    }
    final installation =
        (await session.credential())['installationId'] as String;
    final device = await deviceKeys.load(uid);
    final thisDevice =
        device != null &&
        device.installationId == installation &&
        r['keyInstallationId'] == installation;
    return (
      member: true,
      walletId: r['walletId'] as String,
      memberId: r['memberId'] as String,
      hasKey: r['hasKey'] == true,
      thisDevice: thisDevice,
      fingerprint: !thisDevice
          ? null
          : await FamilyKeyCrypto.fingerprint(
              FamilyKeyContext(
                walletId: r['walletId'] as String,
                ownerAccountId: r['ownerAccountId'] as String,
                recipientAccountId: uid,
                recipientMemberId: r['memberId'] as String,
                recipientInstallationId: installation,
                recipientPublicKey: device.key.publicKey,
              ),
            ),
    );
  }

  /// Member trên installation MỚI (sau tiếp quản P7.1): đăng ký khoá thiết bị mới;
  /// Owner phải đối chiếu vân tay mới và bọc lại. Cần step-up.
  Future<String> registerThisDevice(String walletId) async {
    _requireAllowed();
    final uid = _uid();
    final installation =
        (await session.credential())['installationId'] as String;
    final device = await _deviceKey(uid, installation);
    await _call('registerMemberDeviceKey', {
      'walletId': walletId,
      'publicKey': base64.encode(device.publicKey),
    });
    return (await myFamily()).fingerprint ?? '';
  }

  /// Mở gói khoá Owner đã bọc cho thiết bị này ⇒ BMK (chỉ trong bộ nhớ). Context dựng
  /// từ danh tính CỦA CHÍNH máy này; máy chủ đổi người nhận/thiết bị/thành viên ⇒ lỗi.
  Future<({String walletId, String memberId, Uint8List bmk})>
  _unwrapMyKey() async {
    final uid = _uid();
    final mine = await myFamily();
    if (!mine.member) throw const FamilyException('not-member');
    if (!mine.hasKey) throw const FamilyException('key-not-shared');
    if (!mine.thisDevice) throw const FamilyException('device-key-mismatch');
    final device = (await deviceKeys.load(uid))!;
    final r = await _call('getMemberKey', {'walletId': mine.walletId});
    final Uint8List bmk;
    try {
      bmk = await FamilyKeyCrypto.unwrapBmk(
        Map<String, Object?>.from(r['wrapped'] as Map),
        FamilyKeyContext(
          walletId: mine.walletId!,
          ownerAccountId: r['ownerAccountId'] as String,
          recipientAccountId: uid,
          recipientMemberId: mine.memberId!,
          recipientInstallationId: device.installationId,
          recipientPublicKey: device.key.publicKey,
        ),
        device.key,
      );
    } on BackupKeyException {
      throw const FamilyException('wrong-key');
    }
    return (walletId: mine.walletId!, memberId: mine.memberId!, bmk: bmk);
  }

  /// Member: BMK mở cục bộ → tải ví mã hoá → khôi phục vào ví SQLCipher MỚI (kiểm
  /// chứng trọn vẹn) → kích hoạt. Ví đã có trên máy nhưng bị ẩn vì thu hồi trước đó
  /// (được mời lại) ⇒ chỉ lưu lại BMK + bỏ cờ thu hồi (cùng file, không khôi phục lại).
  Future<({String walletId, bool restored})> join() async {
    _requireAllowed();
    final uid = _uid();
    final k = await _unwrapMyKey();
    final existing = registry.byWalletId(k.walletId);
    if (existing != null) {
      if (existing.boundAccountId != uid) {
        throw const FamilyException('not-member');
      }
      await keyStore.store(uid, k.walletId, k.bmk);
      await registry.setFamilyFlags(
        k.walletId,
        accessRevoked: false,
        familyMember: true,
      );
      await registry.markActive(k.walletId);
      return (walletId: k.walletId, restored: false);
    }
    final engine = restore ?? (throw const FamilyException('not-member'));
    final result = await engine.restoreAsFamilyMember(
      walletId: k.walletId,
      bmk: k.bmk,
      // Người ghi khác có thể vừa đẩy 1 batch không kèm manifest; mọi envelope vẫn
      // được xác thực + kiểm FK/toàn vẹn/bất biến tài chính.
      allowStaleCheckpoint: true,
    );
    return (walletId: result.walletId, restored: true);
  }

  static Future<List<int>> _sha256(List<int> bytes) async =>
      (await const DartSha256().hash(bytes)).bytes;

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Endpoint máy chủ mà Family dùng (test đối chiếu với allowlist transport).
abstract final class FamilyServiceOps {
  static const all = {
    'promoteToFamily',
    'createFamilyInvite',
    'getFamilyInvite',
    'acceptFamilyInvite',
    'cancelFamilyInvite',
    'getFamilyMembers',
    'putMemberKey',
    'getMemberKey',
    'registerMemberDeviceKey',
    'getMyFamily',
    'revokeFamilyMember',
  };
}
