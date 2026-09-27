import 'package:drift/drift.dart';

import '../../core/config/app_environment.dart';
import '../../core/crypto/envelope_cipher.dart';
import '../../core/utils/opaque_id.dart';
import '../../domain/auth/cloud_session.dart';
import '../../domain/engine/financial_engine.dart';
import '../../domain/entities/wallet_identity.dart';
import '../backup/backup_key_store.dart';
import '../backup/backup_service.dart';
import '../local/app_database.dart';
import '../local/sync/sync_capture.dart';
import '../local/wallet_registry.dart';
import '../repositories/local_transaction_repository.dart';
import 'cloud_sync_engine.dart';
import 'entity_codec.dart';

/// Khôi phục thất bại. KHÔNG có gì được kích hoạt; file tạm (nếu có) đã được dọn.
class RestoreException implements Exception {
  const RestoreException(this.reason, [this.stage]);

  /// `blocked-environment`, `wallet-already-present`, `device-has-other-backup`,
  /// `not-owner`, `not-claimed`, `no-backup`, `wrong-secret`, `bad-envelope`,
  /// `manifest-missing`, `manifest-mismatch`, `count-mismatch`, `content-mismatch`,
  /// `integrity`, `foreign-key`, `financial-invariant`, `newer-schema`, `injected`.
  final String reason;
  final String? stage;
  @override
  String toString() =>
      'RestoreException($reason${stage == null ? '' : ' @ $stage'})';
}

class RestoreResult {
  const RestoreResult({
    required this.walletId,
    required this.dbFileName,
    required this.counts,
    required this.headRev,
    required this.checkpointVerified,
  });
  final String walletId;
  final String dbFileName;
  final Map<String, int> counts;
  final int headRev;

  /// Manifest thuộc đúng head (số lượng đã so khớp chặt). `false` chỉ khi người gọi
  /// cho phép tường minh `allowStaleCheckpoint` (lần đẩy cuối bị ngắt giữa chừng).
  final bool checkpointVerified;
}

/// Mở/xoá file ví cho engine khôi phục. Bản app: SQLCipher + khoá Keystore RIÊNG của
/// [dbFileName] (tạo mới lúc mở lần đầu, `SeedProfile.none`); xoá = file + sidecar +
/// marker. Bản test: file tạm không mã hoá.
abstract class RestoreStorage {
  Future<AppDatabase> open(String dbFileName);

  /// Đánh dấu "đang khôi phục" TRƯỚC khi tạo file (dọn sau crash).
  Future<void> markRestoring(String dbFileName);
  Future<void> clearMarker(String dbFileName);

  /// Xoá file ví dở dang + sidecar + marker. Chỉ gọi cho file DO
  /// CHÍNH lần khôi phục này tạo (tên ngẫu nhiên mới) — không bao giờ cho ví đang dùng.
  Future<void> discard(String dbFileName);
}

/// P8.5 — khôi phục zero-knowledge vào 1 Wallet MỚI, tách biệt.
///
/// Thiết kế file/khoá: KHÔNG đổi tên. File đích có tên CUỐI CÙNG ngẫu nhiên, duy nhất
/// ngay từ đầu (`wallet_<rand>.sqlite`) và khoá DEK-DB riêng được tạo cho đúng tên đó
/// (Keystore AAD gắn tên file — không có bước rename làm gãy ràng buộc). "Kích hoạt
/// nguyên tử" = ghi registry SAU KHI kiểm chứng xong; trước đó ví không tồn tại với
/// app. Lỗi ở bất kỳ bước nào ⇒ đóng + xoá file đó; ví hiện tại không
/// bao giờ được mở/đụng tới. Marker `.restoring` cho phép dọn sau crash.
class RestoreEngine {
  RestoreEngine({
    required this.session,
    required SessionTransport transport,
    required this.keyStore,
    required this.registry,
    required this.storage,
    AppEnvironment? env,
    String Function()? newFileName,
    this.failAt,
  }) : _send = transport,
       env = env ?? AppEnvironment.current,
       _newFileName =
           newFileName ?? (() => 'wallet_${OpaqueId.generate()}.sqlite');

  final CloudSession session;
  final SessionTransport _send;
  final BackupKeyStore keyStore;
  final WalletRegistry registry;
  final RestoreStorage storage;
  final AppEnvironment env;
  final String Function() _newFileName;

  /// Test hook: true ⇒ ném tại giai đoạn [stage] (chứng minh dọn dẹp).
  final bool Function(String stage)? failAt;
  int calls = 0;

  void _stage(String stage) {
    if (failAt?.call(stage) ?? false) throw RestoreException('injected', stage);
  }

  Future<Map<String, dynamic>> _call(
    String op,
    Map<String, dynamic> data,
  ) async {
    calls++;
    try {
      return await _send(op, data);
    } on SessionFailure catch (e) {
      if (CloudSession.revokedReasons.contains(e.reason)) {
        await session.handleRevoked();
      }
      rethrow;
    }
  }

  /// Ví đã claim của Account này trên máy chủ (cần phiên P7.1 hiện hành).
  Future<({bool ownedByYou, String? selfMemberId, int headRev, String? kind})>
  discover(String walletId) async {
    final r = await _call('getWalletClaim', {
      ...await session.credential(),
      'walletId': walletId,
    });
    if (r['claimed'] != true) throw const RestoreException('not-claimed');
    return (
      ownedByYou: r['ownedByYou'] == true,
      selfMemberId: r['selfMemberId'] as String?,
      headRev: (r['headRev'] as int?) ?? 0,
      kind: r['kind'] as String?,
    );
  }

  /// Khôi phục [walletId] bằng ĐÚNG MỘT bí mật: Mật khẩu sao lưu hoặc Recovery Key.
  Future<RestoreResult> restore({
    required String walletId,
    String? password,
    String? recoveryKey,
    bool allowStaleCheckpoint = false,
  }) async {
    if (env != AppEnvironment.dev)
      throw const RestoreException('blocked-environment');
    if ((password == null) == (recoveryKey == null)) {
      throw ArgumentError('exactly one secret');
    }
    final uid = session.accountId() ?? (throw const SessionFailure(true));
    if (registry.byWalletId(walletId) != null) {
      // Không bao giờ ghi đè / gộp im lặng vào ví đang có trên máy.
      throw const RestoreException('wallet-already-present');
    }
    final held = await keyStore.load(uid);
    if (held != null && held.walletId != walletId) {
      throw const RestoreException('device-has-other-backup');
    }
    final credential = await session.credential();
    final claim = await discover(walletId);
    if (!claim.ownedByYou || claim.selfMemberId == null) {
      throw const RestoreException('not-owner');
    }

    // 1. Mở khoá BMK CỤC BỘ (sai bí mật ⇒ lỗi trước khi tạo bất kỳ file nào).
    final Map<String, Object?> keyring;
    try {
      keyring = Map<String, Object?>.from(
        await _call('getBackupKeyring', {...credential, 'walletId': walletId}),
      );
    } on SessionFailure catch (e) {
      if (e.reason == 'NO_KEYRING') throw const RestoreException('no-backup');
      rethrow;
    }
    final Uint8List bmk;
    try {
      bmk = password != null
          ? (await BackupService.unwrapPassword(
              keyring,
              walletId,
              password,
            )).bmk
          : (await BackupService.unwrapRecovery(
              keyring,
              walletId,
              recoveryKey!,
            )).bmk;
    } on Object {
      throw const RestoreException('wrong-secret');
    }
    final cipher = await EnvelopeCipher.create(bmk, walletId);

    // 2. Tải + xác thực mọi envelope (chưa ghi gì).
    _stage('download');
    final ({List<PulledEntity> entities, int throughRev, int calls}) got;
    try {
      got = await CloudSyncEngine.download(
        cipher: cipher,
        sinceRev: 0,
        fetch: (extra) => _call('getEncryptedChanges', {
          ...credential,
          'walletId': walletId,
          ...extra,
        }),
      );
    } on CloudSyncException {
      throw const RestoreException('bad-envelope', 'download');
    }
    final manifestEntity = got.entities
        .where((e) => e.kind == CloudSyncEngine.manifestKind)
        .firstOrNull;
    if (manifestEntity == null)
      throw const RestoreException('manifest-missing');
    final manifest = manifestEntity.body;
    if (manifest['walletId'] != walletId) {
      throw const RestoreException('manifest-mismatch');
    }
    final live = [
      for (final e in got.entities)
        if (e.kind != CloudSyncEngine.manifestKind &&
            !EntityCodec.isTombstone(e.body))
          e,
    ];

    // 3. Ví MỚI, file tên cuối cùng, SeedProfile.none (rỗng tuyệt đối).
    final fileName = _newFileName();
    await storage.markRestoring(fileName);
    AppDatabase? db;
    try {
      _stage('create');
      db = await storage.open(fileName);
      final d = db;
      if (await d.select(d.walletMeta).getSingleOrNull() != null) {
        throw const RestoreException('integrity', 'not-empty');
      }
      _stage('apply');
      await d.transaction(() async {
        await d.customStatement('PRAGMA defer_foreign_keys = ON');
        await d.customStatement(
          'INSERT INTO wallet_meta (singleton, wallet_id, kind, created_at) '
          'VALUES (1, ?, ?, ?)',
          [
            walletId,
            (claim.kind == 'family' ? WalletKind.family : WalletKind.personal)
                .name,
            manifest['walletCreatedAt'] ?? 0,
          ],
        );
        for (final e in live) {
          final body = Map<String, Object?>.from(e.body)..remove('w');
          try {
            await EntityCodec.apply(d, e.kind, e.localId, body);
          } on EntityCodecException catch (x) {
            throw RestoreException(
              x.reason == 'newer-schema' ? 'newer-schema' : 'bad-envelope',
              'apply',
            );
          }
        }
        if ((await d.customSelect('PRAGMA foreign_key_check').get())
            .isNotEmpty) {
          throw const RestoreException('foreign-key', 'apply');
        }
        // Binding ACTIVE ghi SAU dữ liệu ⇒ trigger chưa từng sinh outbox.
        await d
            .into(d.cloudBinding)
            .insert(
              CloudBindingCompanion.insert(
                walletId: walletId,
                accountId: uid,
                selfMemberId: claim.selfMemberId!,
                environment: env.name,
                state: 'ACTIVE',
                claimRequestId: const Value(null),
                cryptoVersion: const Value(1),
                keyringRev: Value(keyring['rev'] as int?),
                updatedAt: DateTime.now(),
              ),
            );
        await d
            .into(d.syncState)
            .insert(
              SyncStateCompanion.insert(
                serverHeadRev: Value(got.throughRev),
                lastPullAt: Value(DateTime.now()),
                backupState: const Value('COMPLETE'),
              ),
            );
      });

      // 4. Kiểm chứng TRỌN VẸN trước khi kích hoạt.
      _stage('verify');
      final counts = await _verify(
        d,
        live,
        manifest,
        manifestEntity.rev,
        got.throughRev,
      );
      if (!counts.checkpoint && !allowStaleCheckpoint) {
        throw const RestoreException('manifest-mismatch', 'stale-checkpoint');
      }
      final checkpointVerified = counts.checkpoint;
      await d.close();
      db = null;

      // 5. Kích hoạt: BMK vào Keystore của máy này, rồi registry (điểm commit).
      _stage('activate');
      await keyStore.store(uid, walletId, bmk);
      await registry.register(
        WalletRegistryEntry(
          walletId: walletId,
          kind: claim.kind == 'family'
              ? WalletKind.family
              : WalletKind.personal,
          dbFileName: fileName,
          createdAt: DateTime.now(),
          boundAccountId: uid,
        ),
        // Điểm commit: đăng ký + KÍCH HOẠT trong cùng 1 lần ghi registry — ví khôi
        // phục là ví đang hoạt động của máy (đăng xuất không đổi; ví bootstrap chỉ là
        // dự phòng).
        activate: true,
      );
      await storage.clearMarker(fileName);
      return RestoreResult(
        walletId: walletId,
        dbFileName: fileName,
        counts: counts.counts,
        headRev: got.throughRev,
        checkpointVerified: checkpointVerified,
      );
    } on Object {
      try {
        await db?.close();
      } on Object {
        /* đã đóng */
      }
      await storage.discard(fileName);
      if (held == null) await keyStore.clear();
      rethrow;
    }
  }

  Future<({Map<String, int> counts, bool checkpoint})> _verify(
    AppDatabase d,
    List<PulledEntity> live,
    Map<String, Object?> manifest,
    int manifestRev,
    int throughRev,
  ) async {
    final integrity = await d.customSelect('PRAGMA integrity_check').get();
    if (integrity.length != 1 || integrity.first.data.values.first != 'ok') {
      throw const RestoreException('integrity', 'verify');
    }
    if ((await d.customSelect('PRAGMA foreign_key_check').get()).isNotEmpty) {
      throw const RestoreException('foreign-key', 'verify');
    }
    // Từng dòng đọc lại == đúng nội dung đã giải mã (id thật, clientTxId, memberId…).
    for (final e in live) {
      final back = await EntityCodec.read(d, e.kind, e.localId);
      if (back == null ||
          EntityCodec.canonicalJson(back['c']) !=
              EntityCodec.canonicalJson(e.body['c'])) {
        throw const RestoreException('content-mismatch', 'verify');
      }
    }
    final counts = <String, int>{
      for (final MapEntry(key: table, value: spec)
          in syncCapturedTables.entries)
        spec.kind:
            (await d
                    .customSelect('SELECT COUNT(*) AS n FROM $table')
                    .getSingle())
                .read<int>('n'),
    };
    // Manifest ghi cùng batch cuối rút cạn outbox. Chỉ so chặt khi nó thuộc ĐÚNG head
    // (không có batch nào sau nó); nếu không ⇒ báo checkpoint cũ, không đoán.
    final mCounts = Map<String, Object?>.from(manifest['counts']! as Map);
    final checkpoint = manifestRev == throughRev;
    if (checkpoint) {
      for (final MapEntry(:key, :value) in counts.entries) {
        if (mCounts[key] != value) {
          throw RestoreException('count-mismatch', key);
        }
      }
    }
    // Bất biến tài chính: engine tính lại mọi pool từ giao dịch; không pool nào âm.
    final txs = await LocalTransactionRepository(d).allTransactions();
    final balances = computeAllPoolBalances(txs);
    if (balances.values.any((v) => v < 0)) {
      throw const RestoreException('financial-invariant', 'verify');
    }
    final ids = <String>{};
    for (final t in txs) {
      if (!ids.add(t.clientTxId)) {
        throw const RestoreException('financial-invariant', 'client-tx');
      }
    }
    if ((await SyncOutboxStore(d).count()) != 0) {
      throw const RestoreException('integrity', 'outbox');
    }
    return (counts: counts, checkpoint: checkpoint);
  }
}
