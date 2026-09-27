import 'package:drift/drift.dart';

import '../../core/config/app_environment.dart';
import '../../core/config/cloud_policy.dart';
import '../../core/crypto/backup_crypto.dart';
import '../../core/utils/opaque_id.dart';
import '../../domain/auth/cloud_session.dart';
import '../../domain/entities/cloud_binding.dart';
import '../local/app_database.dart';
import '../local/sync/cloud_binding_store.dart';
import '../local/wallet_registry.dart';
import '../local/wallet_registry_bootstrap.dart';

/// Claim bị chặn ở tầng app (không gửi gì lên máy chủ).
class WalletClaimException implements Exception {
  const WalletClaimException(this.reason);

  /// `blocked-environment`, `other-account`, `pending-different-member`,
  /// `already-bound`, `unknown-member`, `invalid-response`, hoặc lý do dứt khoát của
  /// máy chủ (`ALREADY_CLAIMED`, `ACCOUNT_HAS_WALLET`, `SELF_MEMBER_MISMATCH`, …).
  final String reason;
  @override
  String toString() => 'WalletClaimException($reason)';
}

/// 1 lựa chọn cho "Bạn là ai trong ví này?" + tóm tắt TRUNG TÍNH (số giao dịch,
/// khoảng thời gian — không số tiền) để người dùng tự nhận, không đoán hộ.
class ClaimCandidate {
  const ClaimCandidate({
    required this.memberId,
    required this.label,
    required this.transactionCount,
    this.firstDate,
    this.lastDate,
  });
  final String memberId;
  final String label;
  final int transactionCount;
  final DateTime? firstDate;
  final DateTime? lastDate;
}

/// Trạng thái claim do máy chủ báo (chỉ đọc, cần phiên P7.1 hiện hành).
class ServerClaimStatus {
  const ServerClaimStatus({
    required this.claimed,
    required this.ownedByYou,
    this.selfMemberId,
    this.headRev,
  });
  final bool claimed;
  final bool ownedByYou;
  final String? selfMemberId;
  final int? headRev;
}

/// P8.2 — claim TƯỜNG MINH ví Personal qua backend tin cậy. CHỈ metadata sở hữu:
/// walletId, id thành viên (không nhãn), thành viên người dùng chọn là mình, phiên bản
/// schema/crypto. Không bao giờ gửi giao dịch/số tiền/ghi chú/danh mục/quỹ/tiết kiệm,
/// không đẩy outbox, không khôi phục.
///
/// Máy trạng thái cục bộ (DB là nguồn sự thật, registry chỉ phản chiếu):
/// NONE → CLAIMING (ghi `claimRequestId` TRƯỚC khi gọi mạng) → ACTIVE (sau khi máy chủ
/// xác nhận, kiểm lại walletId/thành viên trong 1 DB transaction). App chết sau khi máy
/// chủ đã ghi ⇒ lần sau [resume] gửi lại ĐÚNG `claimRequestId` ⇒ máy chủ trả idempotent.
/// Đăng xuất/offline KHÔNG đụng binding hay DB: ví vẫn mở được trên máy này.
class WalletClaimService {
  WalletClaimService({
    required this.session,
    required SessionTransport transport,
    required this.db,
    required this.registry,
    required this.dbFileName,
    AppEnvironment? env,
    String Function()? newRequestId,
  }) : _send = transport,
       env = env ?? AppEnvironment.current,
       _newRequestId = newRequestId ?? OpaqueId.generate;

  final CloudSession session;
  final SessionTransport _send;
  final AppDatabase db;
  final WalletRegistry registry;
  final String dbFileName;
  final AppEnvironment env;
  final String Function() _newRequestId;

  /// Máy chủ khẳng định claim NÀY không được ghi (hoặc không phải của mình) ⇒ an toàn
  /// trả ví cục bộ về NONE. Lỗi mạng/phiên thì KHÔNG nằm ở đây: giữ CLAIMING để thử lại.
  static const terminalReasons = {
    'ALREADY_CLAIMED',
    'ACCOUNT_HAS_WALLET',
    'SELF_MEMBER_MISMATCH',
    'CLAIM_MISMATCH',
    'WALLET_NOT_CLAIMABLE',
    'ENVIRONMENT_MISMATCH',
  };

  CloudBindingStore get _store => CloudBindingStore(db);

  // Bấm đúp / màn hình tự thử lại cùng lúc ⇒ chạy lần lượt: lần sau thấy CLAIMING/
  // ACTIVE của lần trước, không bao giờ tạo claim thứ hai.
  Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  /// DEV, hoặc PROD đã bật cloud tường minh ([CloudPolicy]).
  static bool allowedIn(AppEnvironment env) => CloudPolicy.enabledIn(env);

  void _requireAllowed() {
    if (!allowedIn(env)) {
      throw const WalletClaimException('blocked-environment');
    }
  }

  String _uid() => session.accountId() ?? (throw const SessionFailure(true));

  Future<Map<String, dynamic>> _call(
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

  Future<CloudBindingInfo?> binding() => _store.read();

  Future<List<ClaimCandidate>> candidates() async {
    final members = await (db.select(
      db.financialMemberRows,
    )..orderBy([(m) => OrderingTerm.asc(m.displayOrder)])).get();
    final t = db.transactionRows;
    final count = t.id.count();
    final first = t.transactionDate.min();
    final last = t.transactionDate.max();
    return [
      for (final m in members)
        await (db.selectOnly(t)
              ..addColumns([count, first, last])
              ..where(
                t.sourceRefId.equals(m.memberId) |
                    t.destinationRefId.equals(m.memberId) |
                    t.actorMemberId.equals(m.memberId) |
                    t.sourceRefId.like('%|${m.memberId}') |
                    t.destinationRefId.like('%|${m.memberId}'),
              ))
            .getSingle()
            .then(
              (r) => ClaimCandidate(
                memberId: m.memberId,
                label: m.label,
                transactionCount: r.read(count) ?? 0,
                firstDate: r.read(first),
                lastDate: r.read(last),
              ),
            ),
    ];
  }

  /// Người dùng đã chọn [selfMemberId] và xác nhận rõ ràng. Bấm đúp / gọi lại khi đang
  /// CLAIMING ⇒ dùng lại đúng `claimRequestId` đã lưu (không tạo claim mới).
  Future<CloudBindingInfo> claim(String selfMemberId) => _serial(() async {
    _requireAllowed();
    final uid = _uid();
    // Không có phiên P7.1 hiện hành ⇒ dừng TRƯỚC khi ghi CLAIMING.
    await session.credential();
    final current = await _store.read();
    switch (current?.state) {
      case CloudBindingState.active:
        if (current!.accountId == uid && current.selfMemberId == selfMemberId) {
          return current;
        }
        throw const WalletClaimException('already-bound');
      case CloudBindingState.claiming:
        if (current!.accountId != uid) {
          throw const WalletClaimException('other-account');
        }
        if (current.selfMemberId != selfMemberId) {
          throw const WalletClaimException('pending-different-member');
        }
      case CloudBindingState.none:
      case null:
        try {
          await _store.beginClaim(
            accountId: uid,
            selfMemberId: selfMemberId,
            environment: env.flavor,
            claimRequestId: _newRequestId(),
          );
        } on CloudBindingException catch (e) {
          throw WalletClaimException(
            e.reason == 'unknown-member' ? 'unknown-member' : e.reason,
          );
        }
    }
    return _complete((await _store.read())!);
  });

  /// Khởi động lại / quay lại màn hình khi còn CLAIMING của CHÍNH Account này ⇒ gửi lại
  /// đúng claim đã lưu. Account khác / không CLAIMING ⇒ không làm gì.
  Future<CloudBindingInfo?> resume() => _serial(() async {
    if (!allowedIn(env)) return null;
    final current = await _store.read();
    final uid = session.accountId();
    if (current == null ||
        current.state != CloudBindingState.claiming ||
        uid == null ||
        current.accountId != uid) {
      return null;
    }
    return _complete(current);
  });

  Future<CloudBindingInfo> _complete(CloudBindingInfo pending) async {
    final uid = pending.accountId;
    final members = await db.select(db.financialMemberRows).get();
    final credential = await session.credential();
    final Map<String, dynamic> result;
    try {
      result = await _call('claimWallet', {
        ...credential,
        'walletId': pending.walletId,
        'selfMemberId': pending.selfMemberId,
        'membersMinimalMetadata': [
          for (final m in members) {'memberId': m.memberId},
        ],
        'payloadSchema': db.schemaVersion,
        'cryptoVersion': BackupCrypto.cryptoVersion,
        'environment': pending.environment,
        'claimRequestId': pending.claimRequestId,
      });
    } on SessionFailure catch (e) {
      if (terminalReasons.contains(e.reason)) {
        // Máy chủ không giữ claim này của mình ⇒ không có gì để kích hoạt.
        await _store.release();
        await reconcileRegistry();
        throw WalletClaimException(e.reason!);
      }
      rethrow; // mạng/phiên/đăng nhập gần đây: vẫn CLAIMING, thử lại cùng id.
    }
    final serverRequestId = result['claimRequestId'];
    if (result['claimed'] != true ||
        result['walletId'] != pending.walletId ||
        result['selfMemberId'] != pending.selfMemberId ||
        serverRequestId is! String ||
        serverRequestId.isEmpty) {
      throw const WalletClaimException('invalid-response');
    }
    // Đổi Account giữa chừng ⇒ không kích hoạt dưới Account khác; lần sau thử lại.
    if (session.accountId() != uid) throw const SessionFailure(true);
    await _store.activate(
      claimRequestId: pending.claimRequestId!,
      serverWalletId: result['walletId'] as String,
      serverSelfMemberId: result['selfMemberId'] as String,
      serverClaimRequestId: serverRequestId,
      cryptoVersion: BackupCrypto.cryptoVersion,
    );
    await reconcileRegistry();
    return (await _store.read())!;
  }

  /// Hỏi máy chủ (phiên P7.1 hiện hành của Account đang đăng nhập).
  Future<ServerClaimStatus> serverStatus() async {
    _requireAllowed();
    final uid = _uid();
    final walletId = (await db.select(db.walletMeta).getSingle()).walletId;
    final credential = await session.credential();
    final r = await _call('getWalletClaim', {...credential, 'walletId': walletId});
    if (session.accountId() != uid) throw const SessionFailure(true);
    return ServerClaimStatus(
      claimed: r['claimed'] == true,
      ownedByYou: r['ownedByYou'] == true,
      selfMemberId: r['selfMemberId'] as String?,
      headRev: r['headRev'] as int?,
    );
  }

  /// Huỷ claim — chỉ khi máy chủ chưa có bản sao lưu nào (máy chủ kiểm headRev == 0 và
  /// không có entity). CLAIMING: hỏi máy chủ trước — có claim của mình thì kích hoạt
  /// rồi huỷ đúng claim đó; không có thì chỉ dọn cục bộ.
  Future<void> abandon() => _serial(() async {
    _requireAllowed();
    final uid = _uid();
    var current = await _store.read();
    if (current == null) return;
    if (current.accountId != uid) {
      throw const WalletClaimException('other-account');
    }
    if (current.state == CloudBindingState.claiming) {
      final status = await serverStatus();
      if (!status.claimed || !status.ownedByYou) {
        await _store.release();
        await reconcileRegistry();
        return;
      }
      current = await _complete(current);
    }
    final credential = await session.credential();
    try {
      await _call('abandonClaim', {
        ...credential,
        'walletId': current.walletId,
        'selfMemberId': current.selfMemberId,
        'claimRequestId': current.claimRequestId,
      });
    } on SessionFailure catch (e) {
      if (e.reason == 'BACKUP_STARTED' ||
          e.reason == 'CLAIM_MISMATCH' ||
          e.reason == 'ALREADY_CLAIMED') {
        throw WalletClaimException(e.reason!);
      }
      rethrow;
    }
    await _store.release();
    await reconcileRegistry();
  });

  /// Sửa registry theo DB (không bao giờ ngược lại).
  Future<void> reconcileRegistry() async {
    try {
      await reconcileRegistryFromDb(registry, db, dbFileName);
    } on Object {
      /* Registry chỉ là cache: lần khởi động sau sẽ sửa lại từ DB. */
    }
  }
}
