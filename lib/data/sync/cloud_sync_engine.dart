import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/config/app_environment.dart';
import '../../core/crypto/backup_crypto.dart';
import '../../core/crypto/envelope_cipher.dart';
import '../../domain/auth/cloud_session.dart';
import '../../domain/entities/cloud_binding.dart';
import '../backup/backup_key_store.dart';
import '../backup/backup_service.dart';
import '../local/app_database.dart';
import '../local/sync/cloud_binding_store.dart';
import '../local/sync/sync_capture.dart';
import '../repositories/local_transaction_repository.dart';
import '../../domain/engine/financial_engine.dart';
import 'entity_codec.dart';

/// Đồng bộ không chạy (điều kiện chưa đủ) hoặc máy chủ từ chối. Outbox GIỮ NGUYÊN.
class CloudSyncException implements Exception {
  const CloudSyncException(this.reason);

  /// Cục bộ: `blocked-environment`, `not-bound`, `other-account`, `no-key`,
  /// `key-wallet-mismatch`, `backup-not-enabled`, `already-enabled`,
  /// `dependency-conflict`, `bad-envelope`, `head-moved`.
  /// Máy chủ: lý do nguyên văn (`HEAD_MOVED`, `BACKUP_NOT_ENABLED`, …).
  final String reason;
  @override
  String toString() => 'CloudSyncException($reason)';
}

class PushReport {
  const PushReport(this.batches, this.envelopes, this.headRev);
  final int batches;
  final int envelopes;
  final int headRev;
}

class PullReport {
  const PullReport({
    required this.applied,
    required this.conflicts,
    required this.headRev,
    required this.calls,
    this.overdrawnPools = 0,
  });
  final int applied;
  final int conflicts;
  final int headRev;
  final int calls;

  /// P10: sau khi gộp thay đổi của người ghi khác, số pool bị âm (vd 2 người cùng chi
  /// từ 1 pool khi offline). Máy chủ không kiểm được (chỉ thấy ciphertext) ⇒ app phát
  /// hiện và báo; KHÔNG tự sửa/gộp giao dịch.
  final int overdrawnPools;
}

/// Thực thể đã giải mã + xác thực từ máy chủ.
class PulledEntity {
  const PulledEntity(this.kind, this.localId, this.rev, this.body);
  final String kind;
  final String localId;
  final int rev;
  final Map<String, Object?> body;
}

/// P8.3/P8.4 — engine sao lưu zero-knowledge + delta cho 1 Wallet ĐÃ claim.
///
/// - UI không bao giờ đọc cloud: engine chỉ trao đổi delta với SQLite cục bộ.
/// - Đẩy: đọc outbox (chỉ danh tính/ý định) + dòng HIỆN TẠI trong 1 DB transaction,
///   niêm phong từng thực thể (rev = headRev mới — luôn lớn hơn mọi rev đã lưu), gửi 1
///   batch CAS(baseHeadRev) với `batchId` TẤT ĐỊNH = HMAC(IDK, head‖seqs): gửi lại sau
///   timeout ⇒ cùng batchId ⇒ biên nhận idempotent. Xác nhận theo `seq` CHÍNH XÁC —
///   thay đổi mới hơn trong lúc gửi có `seq` mới nên không bị nuốt.
/// - Kéo: tải MỌI trang tới head, xác thực từng envelope, áp dụng trong 1 DB transaction
///   (`withoutSyncCapture`, FK hoãn tới commit). Thực thể đang có thay đổi cục bộ chưa
///   đẩy mà máy chủ có bản KHÁC của người khác ⇒ xung đột: bản cục bộ lưu nguyên văn
///   vào `sync_conflicts`, bản máy chủ thắng — không ghi đè im lặng.
class CloudSyncEngine {
  CloudSyncEngine({
    required this.db,
    required this.session,
    required SessionTransport transport,
    required this.keyStore,
    AppEnvironment? env,
    this.kdf = KdfParams.v1,
    this.batchSize = 99,
    this.onMembershipLost,
  }) : _send = transport,
       env = env ?? AppEnvironment.current;

  final AppDatabase db;
  final CloudSession session;
  final SessionTransport _send;
  final BackupKeyStore keyStore;
  final AppEnvironment env;
  final KdfParams kdf;

  /// Envelope thực thể mỗi batch (+1 manifest ≤ giới hạn 100 của máy chủ).
  final int batchSize;

  /// P10: máy chủ báo Account này không (còn) là thành viên của ví (`NOT_MEMBER` — vd
  /// Owner đã thu hồi Member). Nhận walletId; app ẩn ví khỏi UI thường. Không xoá gì.
  final Future<void> Function(String walletId)? onMembershipLost;

  /// Số lời gọi mạng (đo đạc/test "không vòng lặp khi rảnh").
  int calls = 0;

  /// P10: số pool âm sau lần kéo gần nhất có áp dụng thay đổi (UI cảnh báo).
  int lastOverdrawnPools = 0;

  static const manifestKind = 'manifest';
  static const manifestId = 'manifest';

  Future<T> _tail0<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> _tail = Future.value();

  Future<Map<String, dynamic>> _call(
    String operation,
    Map<String, dynamic> data,
  ) async {
    calls++;
    try {
      return await _send(operation, data);
    } on SessionFailure catch (e) {
      if (CloudSession.revokedReasons.contains(e.reason)) {
        await session.handleRevoked();
      }
      final walletId = data['walletId'];
      if (e.reason == 'NOT_MEMBER' && walletId is String) {
        await onMembershipLost?.call(walletId);
      }
      rethrow;
    }
  }

  /// Chỉ DEV (cổng dữ liệu thật: CLAUDE.md §19/§22 — backend cũng chỉ phục vụ DEV).
  void _requireAllowed() {
    if (env != AppEnvironment.dev) {
      throw const CloudSyncException('blocked-environment');
    }
  }

  Future<CloudBindingInfo> _binding() async {
    final b = await CloudBindingStore(db).read();
    if (b == null || b.state != CloudBindingState.active) {
      throw const CloudSyncException('not-bound');
    }
    final uid = session.accountId();
    if (uid == null) throw const SessionFailure(true);
    if (uid != b.accountId) throw const CloudSyncException('other-account');
    return b;
  }

  Future<EnvelopeCipher> _cipher(CloudBindingInfo b) async {
    final local = await keyStore.load(b.accountId);
    if (local == null) throw const CloudSyncException('no-key');
    if (local.walletId != b.walletId) {
      throw const CloudSyncException('key-wallet-mismatch');
    }
    return EnvelopeCipher.create(local.bmk, b.walletId);
  }

  Future<SyncStateRow?> _state() => db.select(db.syncState).getSingleOrNull();

  Future<void> _writeState(SyncStateCompanion c) => db
      .into(db.syncState)
      .insert(
        c.copyWith(singleton: const Value(1)),
        onConflict: DoUpdate((_) => c),
      );

  /// Trạng thái sao lưu cục bộ (`null` = chưa bật).
  Future<String?> backupState() async => (await _state())?.backupState;

  // ---------------------------------------------------------------------------
  // P8.3 — bật sao lưu (Backup Password + Recovery Key) + mốc nền.
  // ---------------------------------------------------------------------------

  /// Bật sao lưu mã hoá cho ví ĐÃ claim (Owner). Thứ tự an toàn khi chết giữa chừng:
  /// BMK ngẫu nhiên → lưu Keystore TRƯỚC → tạo keyring trên máy chủ (KEYRING_EXISTS ⇒
  /// mở khoá bằng chính mật khẩu để lấy lại đúng BMK) → `enableBackup` (idempotent) →
  /// 1 DB transaction: `backup_state = SEEDING` + xếp hàng MỌI thực thể (mốc nền).
  /// Trả về Recovery Key (hiển thị 1 lần) — `null` nếu keyring đã có từ lần trước.
  Future<String?> enableBackup(String password) => _tail0(() async {
    _requireAllowed();
    if (password.length < BackupService.minPasswordLength) {
      throw ArgumentError('password too short');
    }
    final b = await _binding();
    if ((await _state())?.backupState != null) {
      throw const CloudSyncException('already-enabled');
    }
    final credential = await session.credential();
    final existing = await keyStore.load(b.accountId);
    var bmk = existing != null && existing.walletId == b.walletId
        ? existing.bmk
        : BackupCrypto.newBmk();
    await keyStore.store(b.accountId, b.walletId, bmk);
    String? recoveryKey;
    final keyring = await BackupService.newKeyring(
      bmk: bmk,
      walletId: b.walletId,
      password: password,
      kdf: kdf,
    );
    var rev = 1;
    try {
      await _call('putBackupKeyring', {...credential, ...keyring.payload});
      recoveryKey = keyring.recoveryKey;
    } on SessionFailure catch (e) {
      if (e.reason != 'KEYRING_EXISTS') rethrow;
      // Lần trước đã tạo keyring rồi chết: chỉ đúng mật khẩu mới lấy lại được BMK.
      final server = Map<String, Object?>.from(
        await _call('getBackupKeyring', {
          ...credential,
          'walletId': b.walletId,
        }),
      );
      bmk = (await BackupService.unwrapPassword(
        server,
        b.walletId,
        password,
      )).bmk;
      rev = server['rev']! as int;
      await keyStore.store(b.accountId, b.walletId, bmk);
    }
    await _call('enableBackup', {...credential, 'walletId': b.walletId});
    await db.transaction(() async {
      await (db.update(db.cloudBinding)).write(
        CloudBindingCompanion(
          cryptoVersion: const Value(BackupCrypto.cryptoVersion),
          keyringRev: Value(rev),
        ),
      );
      await _writeState(
        const SyncStateCompanion(backupState: Value('SEEDING')),
      );
      await SyncOutboxStore(db).enqueueFullSnapshot();
    });
    return recoveryKey;
  });

  // ---------------------------------------------------------------------------
  // Đẩy.
  // ---------------------------------------------------------------------------

  /// Tạo lại Recovery Key (xoay slot recovery) cho ví ĐÃ bật sao lưu, trên thiết bị tin
  /// cậy ĐANG giữ BMK. Người gọi phải step-up trước (xác minh chủ máy + đăng nhập gần
  /// đây — máy chủ cũng đòi đăng nhập gần đây).
  ///
  /// CÙNG BMK → Recovery Key ngẫu nhiên 256-bit MỚI → Recovery KEK độc lập → bọc lại →
  /// máy chủ thay slot recovery + proof nguyên tử (CAS `rev`, rev+1). Không đổi BMK,
  /// không mã hoá lại envelope nào, slot mật khẩu giữ nguyên, Recovery Key cũ vô hiệu
  /// ngay khi thành công. Lời gọi mất phản hồi ⇒ gửi lại ĐÚNG payload (cùng
  /// `rotationId` + proof) ⇒ máy chủ trả biên nhận, không xoay lần 2. Trả về Recovery
  /// Key MỚI để hiển thị đúng 1 lần — không lưu, không log.
  Future<String> rotateRecoveryKey({int maxAttempts = 3}) => _tail0(() async {
    _requireAllowed();
    final b = await _binding();
    if ((await _state())?.backupState == null) {
      throw const CloudSyncException('backup-not-enabled');
    }
    final cipher = await _cipher(b);
    final bmk = (await keyStore.load(b.accountId))!.bmk;
    final credential = await session.credential();
    final keyring = await _call('getBackupKeyring', {
      ...credential,
      'walletId': b.walletId,
    });
    // BMK trên máy phải đúng là BMK của ví này: mở được ciphertext thật trên máy chủ.
    await _verifyHeldBmk(cipher, credential, b.walletId);
    final next = await BackupService.newRecoverySlot(
      bmk: bmk,
      walletId: b.walletId,
    );
    final payload = {
      ...credential,
      'walletId': b.walletId,
      'mode': 'rotateRecovery',
      'expectedRev': keyring['rev'],
      'recovery': next.slot,
      'recoveryProof': next.proof,
      'rotationId': base64Url
          .encode(BackupCrypto.randomBytes(32))
          .replaceAll('=', ''),
    };
    for (var attempt = 1; ; attempt++) {
      try {
        await _call('putBackupKeyring', payload);
        return next.recoveryKey;
      } on SessionFailure catch (e) {
        // Từ chối dứt khoát (phiên cũ/thu hồi, cần đăng nhập lại, keyring đã đổi):
        // slot cũ vẫn là slot hợp lệ duy nhất. Chỉ lỗi mạng mới gửi lại.
        if (e.denied || e.reason != null || attempt >= maxAttempts) rethrow;
      }
    }
  });

  Future<void> _verifyHeldBmk(
    EnvelopeCipher cipher,
    Map<String, dynamic> credential,
    String walletId,
  ) async {
    final head = (await _state())?.serverHeadRev ?? 0;
    final page = await _call('getEncryptedChanges', {
      ...credential,
      'walletId': walletId,
      'sinceRev': head > 0 ? head - 1 : 0,
    });
    final envelopes = page['envelopes'] as List;
    if (envelopes.isEmpty) throw const CloudSyncException('bad-envelope');
    for (final raw in envelopes) {
      final map = Map<String, Object?>.from(raw as Map)..remove('serverRev');
      try {
        await cipher.open(Envelope.fromJson(map));
      } on BackupKeyException {
        throw const CloudSyncException('key-wallet-mismatch');
      }
    }
  }

  Future<Map<String, Object?>> _manifest() async {
    final meta = await db
        .customSelect('SELECT wallet_id, created_at FROM wallet_meta')
        .getSingle();
    return {
      's': db.schemaVersion,
      'walletId': meta.read<String>('wallet_id'),
      'walletCreatedAt': meta.data['created_at'],
      'counts': {
        for (final MapEntry(key: table, value: spec)
            in syncCapturedTables.entries)
          spec.kind:
              (await db
                      .customSelect('SELECT COUNT(*) AS n FROM $table')
                      .getSingle())
                  .read<int>('n'),
      },
    };
  }

  /// Đẩy hết outbox (từng batch). HEAD_MOVED ⇒ [CloudSyncException] `head-moved`
  /// (phải kéo trước). Lỗi mạng/phiên ⇒ ném nguyên, outbox không đổi.
  Future<PushReport> push() => _tail0(_push);

  Future<PushReport> _push() async {
    _requireAllowed();
    final b = await _binding();
    final cipher = await _cipher(b);
    var batches = 0;
    var sent = 0;
    var head = (await _state())?.serverHeadRev ?? 0;
    if ((await _state())?.backupState == null) {
      throw const CloudSyncException('backup-not-enabled');
    }
    while (true) {
      final snap = await db.transaction(() async {
        final rows = await SyncOutboxStore(db).pending(limit: batchSize);
        final total = await SyncOutboxStore(db).count();
        return (
          rows: rows,
          bodies: [
            for (final r in rows)
              await EntityCodec.read(db, r.entityKind, r.entityId) ??
                  EntityCodec.tombstone(db),
          ],
          manifest: rows.isNotEmpty && rows.length == total
              ? await _manifest()
              : null,
          head: (await _state())?.serverHeadRev ?? 0,
        );
      });
      if (snap.rows.isEmpty) break;
      head = snap.head;
      final rev = head + 1;
      final writer = b.accountId;
      final envelopes = <Map<String, Object>>[
        for (var i = 0; i < snap.rows.length; i++)
          (await cipher.seal(
            kind: snap.rows[i].entityKind,
            localId: snap.rows[i].entityId,
            rev: rev,
            body: {...snap.bodies[i], 'w': writer},
          )).toJson(),
        if (snap.manifest != null)
          (await cipher.seal(
            kind: manifestKind,
            localId: manifestId,
            rev: rev,
            body: {...snap.manifest!, 'w': writer},
          )).toJson(),
      ];
      final seqs = [for (final r in snap.rows) r.seq];
      // P10: 2 người ghi Family dùng CHUNG IDK và `seq` là bộ đếm CỤC BỘ ⇒ id batch
      // phải gồm người ghi, nếu không batch của B có thể trùng id batch của A và bị
      // máy chủ trả "đã lưu" (mất dữ liệu). Máy chủ cũng từ chối biên nhận khác người ghi.
      final batchId = await cipher.opaqueId(
        'batch',
        '$head:$writer:${snap.manifest != null ? 1 : 0}:${seqs.join(',')}',
      );
      final Map<String, dynamic> result;
      try {
        result = await _call('putEncryptedBatch', {
          ...await session.credential(),
          'walletId': b.walletId,
          'batchId': batchId,
          'baseHeadRev': head,
          'checkpoint': snap.manifest != null,
          'envelopes': envelopes,
        });
      } on SessionFailure catch (e) {
        if (e.reason == 'HEAD_MOVED') {
          throw const CloudSyncException('head-moved');
        }
        rethrow;
      }
      final newHead = result['headRev'] as int;
      await db.transaction(() async {
        await SyncOutboxStore(db).acknowledge(seqs);
        final state = await _state();
        await _writeState(
          SyncStateCompanion(
            serverHeadRev: Value(newHead),
            lastPushAt: Value(DateTime.now()),
            backupState: Value(
              snap.manifest != null && state?.backupState == 'SEEDING'
                  ? 'COMPLETE'
                  : state?.backupState,
            ),
          ),
        );
      });
      head = newHead;
      batches++;
      sent += envelopes.length;
    }
    return PushReport(batches, sent, head);
  }

  // ---------------------------------------------------------------------------
  // Kéo.
  // ---------------------------------------------------------------------------

  /// Tải + giải mã mọi thay đổi sau [sinceRev] (mọi trang). Không ghi DB.
  static Future<({List<PulledEntity> entities, int throughRev, int calls})>
  download({
    required EnvelopeCipher cipher,
    required Future<Map<String, dynamic>> Function(Map<String, dynamic>) fetch,
    required int sinceRev,
  }) async {
    final latest = <String, PulledEntity>{};
    var cursor = sinceRev;
    var calls = 0;
    while (true) {
      final page = await fetch({'sinceRev': cursor});
      calls++;
      for (final raw in page['envelopes'] as List) {
        final map = Map<String, Object?>.from(raw as Map);
        final serverRev = map.remove('serverRev');
        final env = Envelope.fromJson(map);
        if (serverRev != env.rev) {
          throw const CloudSyncException('bad-envelope');
        }
        final OpenedEntity opened;
        try {
          opened = await cipher.open(env);
        } on BackupKeyException {
          throw const CloudSyncException('bad-envelope');
        }
        final prev = latest['${opened.kind}\u0000${opened.localId}'];
        if (prev == null || prev.rev < opened.rev) {
          latest['${opened.kind}\u0000${opened.localId}'] = PulledEntity(
            opened.kind,
            opened.localId,
            opened.rev,
            opened.body,
          );
        }
      }
      final through = page['throughRev'] as int? ?? page['headRev'] as int;
      if (through < cursor) throw const CloudSyncException('bad-envelope');
      cursor = through;
      if (page['more'] != true) break;
    }
    return (entities: latest.values.toList(), throughRev: cursor, calls: calls);
  }

  /// Kéo mọi thay đổi mới về SQLite cục bộ (1 DB transaction, nguyên tử).
  Future<PullReport> pull() => _tail0(_pull);

  Future<PullReport> _pull() async {
    _requireAllowed();
    final b = await _binding();
    final cipher = await _cipher(b);
    final since = (await _state())?.serverHeadRev ?? 0;
    final credential = await session.credential();
    final got = await download(
      cipher: cipher,
      sinceRev: since,
      fetch: (extra) => _call('getEncryptedChanges', {
        ...credential,
        'walletId': b.walletId,
        ...extra,
      }),
    );
    var applied = 0;
    var conflicts = 0;
    var overdrawn = 0;
    await withoutSyncCapture(db, () async {
      await db.customStatement('PRAGMA defer_foreign_keys = ON');
      for (final e in got.entities) {
        if (e.kind == manifestKind) continue;
        final body = Map<String, Object?>.from(e.body);
        final writer = body.remove('w');
        final pending =
            await (db.select(db.syncOutbox)..where(
                  (o) =>
                      o.entityKind.equals(e.kind) &
                      o.entityId.equals(e.localId),
                ))
                .getSingleOrNull();
        final local = await EntityCodec.read(db, e.kind, e.localId);
        final same = _sameContent(local, body);
        if (pending != null) {
          if (same) {
            // Máy chủ đã có đúng nội dung này (vd gửi xong nhưng mất biên nhận).
            await SyncOutboxStore(db).acknowledge([pending.seq]);
            continue;
          }
          if (writer == b.accountId) {
            // Bản cũ của CHÍNH mình: cục bộ mới hơn, giữ nguyên + vẫn chờ đẩy.
            continue;
          }
          await db
              .into(db.syncConflicts)
              .insert(
                SyncConflictsCompanion.insert(
                  entityKind: e.kind,
                  entityId: e.localId,
                  localBody: Value(
                    local == null ? null : EntityCodec.canonicalJson(local),
                  ),
                  serverOp: EntityCodec.isTombstone(body) ? 'delete' : 'upsert',
                  serverRev: e.rev,
                  detectedAt: DateTime.now(),
                ),
              );
          await SyncOutboxStore(db).acknowledge([pending.seq]);
          conflicts++;
        } else if (same) {
          continue;
        }
        try {
          await EntityCodec.apply(db, e.kind, e.localId, body);
        } on EntityCodecException {
          throw const CloudSyncException('bad-envelope');
        }
        applied++;
      }
      final fk = await db.customSelect('PRAGMA foreign_key_check').get();
      if (fk.isNotEmpty) {
        // Vd người khác xoá danh mục mà giao dịch cục bộ chưa đẩy đang dùng. Không tự
        // gộp: huỷ toàn bộ lần kéo (rollback), cần người dùng xem lại.
        throw const CloudSyncException('dependency-conflict');
      }
      if (applied > 0) {
        final balances = computeAllPoolBalances(
          await LocalTransactionRepository(db).allTransactions(),
        );
        overdrawn = balances.values.where((v) => v < 0).length;
      }
      await _writeState(
        SyncStateCompanion(
          serverHeadRev: Value(got.throughRev),
          lastPullAt: Value(DateTime.now()),
        ),
      );
    });
    if (applied > 0) {
      lastOverdrawnPools = overdrawn;
      // Dòng kéo về được ghi bằng SQL thô (EntityCodec) ⇒ Drift không tự biết; báo để
      // mọi màn hình đang theo dõi đọc lại. Worker bỏ qua (outbox rỗng ⇒ 0 lời gọi).
      db.notifyUpdates({
        for (final table in syncCapturedTables.keys) TableUpdate(table),
      });
    }
    return PullReport(
      applied: applied,
      conflicts: conflicts,
      headRev: got.throughRev,
      calls: got.calls,
      overdrawnPools: overdrawn,
    );
  }

  static bool _sameContent(
    Map<String, Object?>? local,
    Map<String, Object?> incoming,
  ) {
    if (EntityCodec.isTombstone(incoming)) return local == null;
    if (local == null) return false;
    return EntityCodec.canonicalJson(local['c']) ==
        EntityCodec.canonicalJson(incoming['c']);
  }

  /// Đẩy outbox; chỉ KÉO khi có tín hiệu: [pullFirst] (yêu cầu tường minh — vd
  /// người dùng bấm "Đồng bộ ngay" hoặc tín hiệu thay đổi từ xa) hoặc máy chủ báo
  /// HEAD_MOVED (người khác vừa ghi) ⇒ kéo rồi đẩy lại (tối đa [maxRounds]).
  /// Outbox rỗng + không yêu cầu kéo ⇒ 0 lời gọi mạng (không thăm dò khi rảnh).
  Future<({PullReport? pull, PushReport push})> syncNow({
    bool pullFirst = false,
    int maxRounds = 4,
  }) async {
    PullReport? pulled = pullFirst ? await pull() : null;
    for (var round = 1; ; round++) {
      try {
        final pushed = await push();
        return (pull: pulled, push: pushed);
      } on CloudSyncException catch (e) {
        if (e.reason != 'head-moved' || round >= maxRounds) rethrow;
        pulled = await pull();
      }
    }
  }
}
