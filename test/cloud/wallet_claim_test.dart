import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/config/app_environment.dart';
import 'package:vi_nha_minh/core/utils/opaque_id.dart';
import 'package:vi_nha_minh/data/cloud/wallet_claim_service.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/seed_defaults.dart';
import 'package:vi_nha_minh/data/local/sync/cloud_binding_store.dart';
import 'package:vi_nha_minh/data/local/sync/sync_capture.dart';
import 'package:vi_nha_minh/data/local/wallet_descriptor.dart';
import 'package:vi_nha_minh/data/local/wallet_registry.dart';
import 'package:vi_nha_minh/data/local/wallet_registry_bootstrap.dart';
import 'package:vi_nha_minh/domain/auth/cloud_session.dart';
import 'package:vi_nha_minh/domain/entities/cloud_binding.dart';
import 'package:vi_nha_minh/domain/entities/wallet_access_scope.dart';
import 'package:vi_nha_minh/domain/entities/wallet_identity.dart';

import '../support/memory_db_key_store.dart';

/// P8.2 — claim TƯỜNG MINH ví Personal: máy trạng thái cục bộ, retry/idempotency,
/// chọn thành viên, ranh giới P7.1, huỷ claim, registry theo DB, đăng xuất/offline,
/// không có payload tài chính.

const _installation = '11111111-1111-4111-8111-111111111111';

/// Phiên P7.1 trong bộ nhớ: mỗi Account có credential riêng; `clear` = đăng xuất.
class _Storage implements SessionStorage {
  final values = <String, Map<String, dynamic>>{};
  @override
  Future<String> installationId() async => _installation;
  @override
  Future<Map<String, dynamic>?> read(String uid) async => values[uid];
  @override
  Future<void> write(String uid, Map<String, dynamic> c) async => values[uid] = c;
  @override
  Future<void> clear() async => values.clear();
}

/// Bản sao ngữ nghĩa `claimWallet`/`getWalletClaim`/`abandonClaim` (functions/index.js)
/// đủ để kiểm máy trạng thái phía app; hợp đồng thật được kiểm ở emulator suite.
class _FakeServer {
  final wallets = <String, Map<String, dynamic>>{};
  final personalIndex = <String, String>{};
  final validSecrets = <String, String>{};
  final revoked = <String>{};
  final requests = <(String, Map<String, dynamic>)>[];
  final seenBinding = <CloudBindingInfo?>[];
  CloudBindingStore? observe;
  bool recentAuth = true;
  bool offline = false;

  /// Ghi xong rồi mất câu trả lời (timeout/app chết sau khi máy chủ commit).
  bool dropNextResponseAfterCommit = false;

  Future<Map<String, dynamic>> call(String op, Map<String, dynamic> data) async {
    requests.add((op, jsonDecode(jsonEncode(data)) as Map<String, dynamic>));
    seenBinding.add(await observe?.read());
    if (offline) throw const SessionFailure(false);
    if (op == 'deactivateSession') return {'deactivated': true};
    final uid = data['accountId'] as String;
    if (revoked.contains(uid)) throw const SessionFailure(true, 'DEVICE_REVOKED');
    if (validSecrets[uid] == null || data['secret'] != validSecrets[uid]) {
      throw const SessionFailure(true);
    }
    final walletId = data['walletId'] as String;
    final wallet = wallets[walletId];
    switch (op) {
      case 'claimWallet':
        if (wallet != null) {
          if (wallet['ownerAccountId'] != uid) {
            throw const SessionFailure(false, 'ALREADY_CLAIMED');
          }
          if (wallet['selfMemberId'] != data['selfMemberId']) {
            throw const SessionFailure(false, 'SELF_MEMBER_MISMATCH');
          }
          return {...wallet, 'claimed': true, 'idempotent': true, 'walletId': walletId};
        }
        if (personalIndex[uid] != null) {
          throw const SessionFailure(false, 'ACCOUNT_HAS_WALLET');
        }
        if (!recentAuth) throw const SessionFailure(true, 'RECENT_LOGIN_REQUIRED');
        wallets[walletId] = {
          'ownerAccountId': uid,
          'selfMemberId': data['selfMemberId'],
          'claimRequestId': data['claimRequestId'],
          'headRev': 0,
        };
        personalIndex[uid] = walletId;
        if (dropNextResponseAfterCommit) {
          dropNextResponseAfterCommit = false;
          throw const SessionFailure(false);
        }
        return {...wallets[walletId]!, 'claimed': true, 'idempotent': false, 'walletId': walletId};
      case 'getWalletClaim':
        if (wallet == null) return {'claimed': false};
        if (wallet['ownerAccountId'] != uid) return {'claimed': true, 'ownedByYou': false};
        return {...wallet, 'claimed': true, 'ownedByYou': true};
      case 'abandonClaim':
        if (wallet == null) return {'abandoned': true, 'alreadyAbsent': true};
        if (wallet['ownerAccountId'] != uid) {
          throw const SessionFailure(false, 'ALREADY_CLAIMED');
        }
        if (wallet['claimRequestId'] != data['claimRequestId']) {
          throw const SessionFailure(false, 'CLAIM_MISMATCH');
        }
        if (wallet['headRev'] != 0) throw const SessionFailure(false, 'BACKUP_STARTED');
        wallets.remove(walletId);
        personalIndex.remove(uid);
        return {'abandoned': true, 'alreadyAbsent': false};
    }
    throw StateError(op);
  }
}

class _Harness {
  _Harness(this.db, {WalletRegistry? registry, AppEnvironment env = AppEnvironment.dev})
    : registry = registry ?? WalletRegistry.inMemory() {
    server.observe = CloudBindingStore(db);
    service = build(env: env);
  }
  final AppDatabase db;
  final WalletRegistry registry;
  final server = _FakeServer();
  final storage = _Storage();
  String? uid = 'acc-A';
  late WalletClaimService service;
  late final session = CloudSession(storage, server.call, () => uid);
  var _ids = 0;

  /// "Khởi động lại app": service mới trên cùng DB/registry (không nhớ gì trong RAM).
  WalletClaimService build({AppEnvironment env = AppEnvironment.dev}) =>
      WalletClaimService(
        session: session,
        transport: server.call,
        db: db,
        registry: registry,
        dbFileName: WalletDescriptor.legacyLocal.dbFileName,
        env: env,
        newRequestId: () => '00000000-0000-4000-8000-${(++_ids).toString().padLeft(12, '0')}',
      );

  /// Phiên P7.1 hợp lệ cho [account] trên máy này.
  void activate(String account, {String secret = 'secret-A'}) {
    storage.values[account] = {
      'accountId': account,
      'installationId': _installation,
      'generation': 1,
      'epoch': 1,
      'secret': secret,
    };
    server.validSecrets[account] = secret;
  }

  Future<String> walletId() async =>
      (await db.select(db.walletMeta).getSingle()).walletId;
  Future<CloudBindingInfo?> binding() => CloudBindingStore(db).read();
  Future<String> kind() async => (await db.select(db.walletMeta).getSingle()).kind;
  List<String> ops() => [for (final r in server.requests) r.$1];
}

Future<void> _addSecretTx(AppDatabase db, String id) =>
    db.into(db.transactionRows).insert(
      TransactionRowsCompanion.insert(
        id: id,
        type: 'income',
        categoryId: 'thu_nhap',
        sourceKind: 'external',
        destinationKind: 'memberAvailable',
        destinationRefId: const Value('vo'),
        amountMinor: 7777777,
        note: const Value('GHI-CHU-BI-MAT'),
        transactionDate: DateTime(2026, 9, 1),
        createdAt: DateTime(2026, 9, 1),
        clientTxId: 'c-$id',
      ),
    );

/// Top-level: closure `directory` không được bắt ngữ cảnh có DB đang mở (Drift gửi
/// nó sang isolate nền).
AppDatabase _openFileWallet(Directory dir, MemoryDbKeyStore keys) => AppDatabase(
  seedProfile: SeedProfile.demo,
  wallet: WalletDescriptor.legacyLocal,
  keyStore: keys,
  directory: () async => dir,
);

void main() {
  late AppDatabase db;
  late _Harness h;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final registry = WalletRegistry.inMemory();
    await registry.ensureLegacyLocal(
      () async => (await db.select(db.walletMeta).getSingle()).walletId,
    );
    h = _Harness(db, registry: registry)..activate('acc-A');
  });
  tearDown(() => db.close());

  group('A — NONE → CLAIMING → ACTIVE', () {
    test('CLAIMING được ghi TRƯỚC khi gọi mạng; máy chủ xác nhận ⇒ ACTIVE + personal', () async {
      expect(await h.binding(), isNull);
      final result = await h.service.claim('chong');

      // Lúc request đi, DB đã có CLAIMING với đúng claimRequestId trong payload.
      final atCall = h.server.seenBinding.single!;
      expect(atCall.state, CloudBindingState.claiming);
      expect(atCall.claimRequestId, h.server.requests.single.$2['claimRequestId']);
      expect(atCall.selfMemberId, 'chong');

      expect(result.state, CloudBindingState.active);
      expect(result.accountId, 'acc-A');
      expect(result.selfMemberId, 'chong');
      expect(result.walletId, await h.walletId());
      expect(await h.kind(), WalletKind.personal.name);
      final entry = h.registry.byWalletId(await h.walletId())!;
      expect(entry.kind, WalletKind.personal);
      expect(entry.boundAccountId, 'acc-A');
      expect(h.server.wallets.length, 1);
    });

    test('đăng nhập (có phiên) mà không bấm claim ⇒ không gọi gì, vẫn NONE', () async {
      await h.service.resume();
      expect(h.server.requests, isEmpty);
      expect(await h.binding(), isNull);
    });

    test('payload chỉ có metadata sở hữu — không nhãn, không số tiền, không ghi chú', () async {
      await _addSecretTx(db, 'tx-secret');
      await h.service.claim('vo');
      final payload = h.server.requests.single.$2;
      expect(payload.keys.toSet(), {
        'accountId', 'installationId', 'generation', 'epoch', 'secret',
        'walletId', 'selfMemberId', 'membersMinimalMetadata', 'payloadSchema',
        'cryptoVersion', 'environment', 'claimRequestId',
      });
      expect(payload['membersMinimalMetadata'], [
        for (final m in await db.select(db.financialMemberRows).get()) {'memberId': m.memberId},
      ]);
      expect(payload['payloadSchema'], db.schemaVersion);
      expect(payload['environment'], 'dev');
      final text = jsonEncode([for (final r in h.server.requests) r.$2]);
      for (final secret in ['7777777', 'GHI-CHU-BI-MAT', 'tx-secret', 'thu_nhap', 'Vợ',
        'Chồng', 'amount', 'note', 'transaction', 'category', 'fund', 'savings']) {
        expect(text.contains(secret), isFalse, reason: secret);
      }
    });

    test('ACTIVE rồi ghi tài chính ⇒ chỉ vào outbox cục bộ, KHÔNG có request đẩy nào', () async {
      await h.service.claim('vo');
      await _addSecretTx(db, 'tx-after');
      expect(await SyncOutboxStore(db).count(), greaterThan(0));
      expect(h.ops(), ['claimWallet']);
    });
  });

  group('B — retry / idempotency / crash', () {
    test('timeout SAU khi máy chủ commit ⇒ vẫn CLAIMING; thử lại CÙNG id ⇒ ACTIVE, 1 ví', () async {
      h.server.dropNextResponseAfterCommit = true;
      await expectLater(h.service.claim('chong'), throwsA(isA<SessionFailure>()));
      final pending = (await h.binding())!;
      expect(pending.state, CloudBindingState.claiming);
      expect(h.server.wallets.length, 1);

      // App chết + mở lại: service mới, không nhớ gì trong RAM.
      final restarted = h.build();
      final done = await restarted.resume();
      expect(done!.state, CloudBindingState.active);
      final ids = [for (final r in h.server.requests) r.$2['claimRequestId']];
      expect(ids, [pending.claimRequestId, pending.claimRequestId]);
      expect(h.server.wallets.length, 1);
      expect(h.server.personalIndex.length, 1);
    });

    test('bấm đúp đồng thời ⇒ 1 claim, cùng 1 id, cả 2 lần đều thấy ACTIVE', () async {
      final both = await Future.wait([h.service.claim('chong'), h.service.claim('chong')]);
      expect(both.map((b) => b.state), everyElement(CloudBindingState.active));
      expect(h.ops(), ['claimWallet']);
      expect(h.server.wallets.length, 1);
    });

    test('mất mạng hẳn ⇒ giữ CLAIMING; bấm lại dùng đúng claimRequestId cũ', () async {
      h.server.offline = true;
      await expectLater(h.service.claim('chong'), throwsA(isA<SessionFailure>()));
      h.server.offline = false;
      await h.service.claim('chong');
      final ids = [for (final r in h.server.requests) r.$2['claimRequestId']];
      expect(ids.toSet().length, 1);
      expect((await h.binding())!.state, CloudBindingState.active);
    });

    test('bản ghi CLAIMING mất (retry id mới, tương thích) ⇒ lưu id GỐC của máy chủ', () async {
      h.server.wallets[await h.walletId()] = {
        'ownerAccountId': 'acc-A',
        'selfMemberId': 'chong',
        'claimRequestId': 'server-original',
        'headRev': 0,
      };
      h.server.personalIndex['acc-A'] = await h.walletId();
      final b = await h.service.claim('chong');
      expect(b.state, CloudBindingState.active);
      expect(b.claimRequestId, 'server-original');
    });

    test('máy chủ trả walletId/thành viên khác ⇒ KHÔNG kích hoạt', () async {
      final store = CloudBindingStore(db);
      await store.beginClaim(
        accountId: 'acc-A',
        selfMemberId: 'vo',
        environment: 'dev',
        claimRequestId: 'r1',
      );
      await expectLater(
        store.activate(claimRequestId: 'r1', serverWalletId: OpaqueId.generate()),
        throwsA(isA<CloudBindingException>()),
      );
      await expectLater(
        store.activate(claimRequestId: 'r1', serverSelfMemberId: 'chong'),
        throwsA(isA<CloudBindingException>()),
      );
      // Thành viên đã chọn biến mất trước khi kích hoạt ⇒ từ chối.
      await (db.delete(db.financialMemberRows)..where((m) => m.memberId.equals('vo'))).go();
      await expectLater(
        store.activate(claimRequestId: 'r1'),
        throwsA(isA<CloudBindingException>()),
      );
      expect((await store.read())!.state, CloudBindingState.claiming);
      expect(await h.kind(), WalletKind.local.name);
    });
  });

  group('C — chọn thành viên (selfMember)', () {
    test('thành viên không tồn tại ⇒ từ chối, không ghi, không gọi mạng', () async {
      await expectLater(
        h.service.claim('ai-do'),
        throwsA(isA<WalletClaimException>().having((e) => e.reason, 'reason', 'unknown-member')),
      );
      expect(await h.binding(), isNull);
      expect(h.server.requests, isEmpty);
    });

    test('đang CLAIMING thành viên A thì không đổi sang B', () async {
      h.server.offline = true;
      await expectLater(h.service.claim('vo'), throwsA(isA<SessionFailure>()));
      h.server.offline = false;
      await expectLater(
        h.service.claim('chong'),
        throwsA(isA<WalletClaimException>().having(
          (e) => e.reason, 'reason', 'pending-different-member')),
      );
      expect((await h.binding())!.selfMemberId, 'vo');
    });

    test('máy chủ đã ghi thành viên khác ⇒ SELF_MEMBER_MISMATCH, ví về NONE', () async {
      h.server.wallets[await h.walletId()] = {
        'ownerAccountId': 'acc-A',
        'selfMemberId': 'vo',
        'claimRequestId': 'x',
        'headRev': 0,
      };
      await expectLater(
        h.service.claim('chong'),
        throwsA(isA<WalletClaimException>().having(
          (e) => e.reason, 'reason', 'SELF_MEMBER_MISMATCH')),
      );
      expect(await h.binding(), isNull);
    });

    test('ứng viên có tóm tắt trung tính (số giao dịch), theo thứ tự hiển thị', () async {
      await _addSecretTx(db, 'tx-1');
      final c = await h.service.candidates();
      expect(c.map((e) => e.memberId), ['vo', 'chong']);
      expect(c.first.transactionCount, greaterThanOrEqualTo(1));
    });
  });

  group('D — xung đột Account/Wallet', () {
    test('ví đã thuộc Account khác ⇒ ALREADY_CLAIMED, ví về NONE, registry cục bộ', () async {
      h.server.wallets[await h.walletId()] = {
        'ownerAccountId': 'acc-B',
        'selfMemberId': 'vo',
        'claimRequestId': 'x',
        'headRev': 0,
      };
      await expectLater(
        h.service.claim('chong'),
        throwsA(isA<WalletClaimException>().having((e) => e.reason, 'reason', 'ALREADY_CLAIMED')),
      );
      expect(await h.binding(), isNull);
      expect(await h.kind(), WalletKind.local.name);
      expect(h.registry.byWalletId(await h.walletId())!.isUnclaimedLocal, isTrue);
    });

    test('Account đã sở hữu ví khác ⇒ ACCOUNT_HAS_WALLET, ví về NONE', () async {
      h.server.personalIndex['acc-A'] = OpaqueId.generate();
      await expectLater(
        h.service.claim('chong'),
        throwsA(isA<WalletClaimException>().having(
          (e) => e.reason, 'reason', 'ACCOUNT_HAS_WALLET')),
      );
      expect(await h.binding(), isNull);
    });

    test('CLAIMING/ACTIVE của Account A: Account B không thử lại, không claim, không huỷ', () async {
      h.server.offline = true;
      await expectLater(h.service.claim('chong'), throwsA(isA<SessionFailure>()));
      h.server.offline = false;
      h.uid = 'acc-B';
      h.activate('acc-B', secret: 'secret-B');
      expect(await h.service.resume(), isNull);
      await expectLater(
        h.service.claim('chong'),
        throwsA(isA<WalletClaimException>().having((e) => e.reason, 'reason', 'other-account')),
      );
      h.uid = 'acc-A';
      await h.service.resume();
      expect((await h.binding())!.state, CloudBindingState.active);
      h.uid = 'acc-B';
      await expectLater(
        h.service.claim('chong'),
        throwsA(isA<WalletClaimException>().having((e) => e.reason, 'reason', 'already-bound')),
      );
      await expectLater(h.service.abandon(), throwsA(isA<WalletClaimException>()));
      expect(h.ops().where((o) => o != 'claimWallet'), isEmpty);
      expect(h.server.requests.every((r) => r.$2['accountId'] == 'acc-A'), isTrue);
    });
  });

  group('E — ranh giới P7.1', () {
    test('chưa có phiên P7.1 trên máy ⇒ không ghi CLAIMING, không gọi mạng', () async {
      h.storage.values.clear();
      await expectLater(h.service.claim('chong'), throwsA(isA<SessionFailure>()));
      expect(await h.binding(), isNull);
      expect(h.server.requests, isEmpty);
    });

    test('máy cũ (credential không còn hiện hành) ⇒ bị từ chối, giữ CLAIMING, không ACTIVE', () async {
      h.server.validSecrets['acc-A'] = 'rotated-by-another-device';
      await expectLater(
        h.service.claim('chong'),
        throwsA(isA<SessionFailure>().having((e) => e.denied, 'denied', isTrue)),
      );
      expect((await h.binding())!.state, CloudBindingState.claiming);
      expect(h.server.wallets, isEmpty);
    });

    test('máy bị thu hồi ⇒ DEVICE_REVOKED xoá credential cục bộ; ví trên máy giữ nguyên', () async {
      await _addSecretTx(db, 'tx-keep');
      h.server.revoked.add('acc-A');
      await expectLater(
        h.service.claim('chong'),
        throwsA(isA<SessionFailure>().having((e) => e.reason, 'reason', 'DEVICE_REVOKED')),
      );
      expect(h.storage.values, isEmpty);
      expect(h.server.wallets, isEmpty);
      expect(await db.select(db.transactionRows).get(), isNotEmpty);
    });

    test('đăng nhập không gần đây ⇒ RECENT_LOGIN_REQUIRED, giữ CLAIMING để thử lại', () async {
      h.server.recentAuth = false;
      await expectLater(h.service.claim('chong'), throwsA(isA<SessionFailure>()));
      expect((await h.binding())!.state, CloudBindingState.claiming);
      h.server.recentAuth = true;
      expect((await h.service.resume())!.state, CloudBindingState.active);
    });

    test('PILOT/PROD bị chặn ở app: không ghi, không gọi mạng', () async {
      for (final env in [AppEnvironment.pilot, AppEnvironment.prod]) {
        final s = h.build(env: env);
        await expectLater(s.claim('chong'), throwsA(isA<WalletClaimException>()));
        expect(await s.resume(), isNull);
      }
      expect(await h.binding(), isNull);
      expect(h.server.requests, isEmpty);
    });
  });

  group('F — huỷ claim', () {
    test('ACTIVE, chưa sao lưu ⇒ máy chủ xoá; cục bộ NONE + local + outbox trống', () async {
      await h.service.claim('chong');
      await _addSecretTx(db, 'tx-1');
      expect(await SyncOutboxStore(db).count(), greaterThan(0));
      final txBefore = (await db.select(db.transactionRows).get()).length;
      await h.service.abandon();
      expect(h.server.wallets, isEmpty);
      expect(h.server.personalIndex, isEmpty);
      expect(await h.binding(), isNull);
      expect(await h.kind(), WalletKind.local.name);
      expect(await SyncOutboxStore(db).count(), 0);
      expect((await db.select(db.transactionRows).get()).length, txBefore);
      expect(h.registry.byWalletId(await h.walletId())!.isUnclaimedLocal, isTrue);
      // Claim lại được (vd chọn nhầm thành viên).
      expect((await h.service.claim('vo')).selfMemberId, 'vo');
    });

    test('đã bắt đầu sao lưu (headRev > 0) ⇒ BACKUP_STARTED, vẫn ACTIVE', () async {
      await h.service.claim('chong');
      h.server.wallets.values.single['headRev'] = 1;
      await expectLater(
        h.service.abandon(),
        throwsA(isA<WalletClaimException>().having((e) => e.reason, 'reason', 'BACKUP_STARTED')),
      );
      expect((await h.binding())!.state, CloudBindingState.active);
      expect(await h.kind(), WalletKind.personal.name);
    });

    test('CLAIMING mà máy chủ chưa từng ghi ⇒ chỉ dọn cục bộ, không gọi abandonClaim', () async {
      h.server.recentAuth = false;
      await expectLater(h.service.claim('chong'), throwsA(isA<SessionFailure>()));
      await h.service.abandon();
      expect(await h.binding(), isNull);
      expect(h.ops(), ['claimWallet', 'getWalletClaim']);
    });

    test('CLAIMING mà máy chủ ĐÃ ghi ⇒ hoàn tất claim rồi huỷ đúng claim đó', () async {
      h.server.dropNextResponseAfterCommit = true;
      await expectLater(h.service.claim('chong'), throwsA(isA<SessionFailure>()));
      await h.service.abandon();
      expect(h.server.wallets, isEmpty);
      expect(await h.binding(), isNull);
      expect(h.ops(), ['claimWallet', 'getWalletClaim', 'claimWallet', 'abandonClaim']);
    });
  });

  group('G — registry phản chiếu DB', () {
    test('registry lệch DB (cả 2 chiều, kể cả Account khác) ⇒ sửa theo DB', () async {
      final id = await h.walletId();
      const file = 'vi_nha_minh.sqlite';
      // Registry nói đã gắn nhưng DB NONE ⇒ về local.
      await h.registry.reconcileBinding(walletId: id, dbFileName: file, boundAccountId: 'acc-X');
      await reconcileRegistryFromDb(h.registry, db, file);
      expect(h.registry.byWalletId(id)!.isUnclaimedLocal, isTrue);
      // DB ACTIVE nhưng registry cục bộ (app chết trước khi ghi registry) ⇒ gắn đúng Account.
      await CloudBindingStore(db).beginClaim(
        accountId: 'acc-A', selfMemberId: 'vo', environment: 'dev', claimRequestId: 'r');
      await reconcileRegistryFromDb(h.registry, db, file);
      expect(h.registry.byWalletId(id)!.isUnclaimedLocal, isTrue, reason: 'CLAIMING chưa gắn');
      await CloudBindingStore(db).activate(claimRequestId: 'r');
      await h.registry.reconcileBinding(walletId: id, dbFileName: file, boundAccountId: 'acc-X');
      await reconcileRegistryFromDb(h.registry, db, file);
      expect(h.registry.byWalletId(id)!.boundAccountId, 'acc-A');
      expect(h.registry.entries.length, 1);
    });

    test('registry không bao giờ tự gắn: đăng nhập chỉ đổi phạm vi, DB vẫn NONE', () async {
      final entry = h.registry.resolveActive(const WalletAccessScope.account('acc-A'))!;
      expect(entry.isUnclaimedLocal, isTrue);
      expect(await h.binding(), isNull);
    });
  });

  test('H — đăng xuất/offline: ví đã claim vẫn mở + đọc được (SQLCipher) trên máy này', () async {
    final dir = Directory.systemTemp.createTempSync('vnm_claim_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final keys = MemoryDbKeyStore();
    AppDatabase open() => _openFileWallet(dir, keys);
    final fileDb = open();
    final storage = MemoryWalletRegistryStorage();
    final registry = await WalletRegistry.load(storage);
    await registry.ensureLegacyLocal(
      () async => (await fileDb.select(fileDb.walletMeta).getSingle()).walletId,
    );
    final fh = _Harness(fileDb, registry: registry)..activate('acc-A');
    await _addSecretTx(fileDb, 'tx-offline');
    final before = (await fileDb.select(fileDb.transactionRows).get()).length;
    await fh.service.claim('chong');
    fh.server.observe = null;
    await fileDb.close();

    // Đăng xuất: credential P7.1 bị xoá, Firebase không còn uid; không có mạng.
    await fh.session.signOut(() async => fh.uid = null);
    fh.server.offline = true;
    final reloaded = await WalletRegistry.load(storage);
    final entry = reloaded.resolveActive(const WalletAccessScope.local())!;
    expect(entry.kind, WalletKind.personal);
    expect(entry.dbFileName, WalletDescriptor.legacyLocal.dbFileName);

    final again = open();
    addTearDown(again.close);
    expect((await again.select(again.transactionRows).get()).length, before);
    expect((await CloudBindingStore(again).read())!.state, CloudBindingState.active);
    // Mất quyền cloud: không Account ⇒ mọi thao tác cloud dừng ở app.
    final offlineService = WalletClaimService(
      session: fh.session,
      transport: fh.server.call,
      db: again,
      registry: reloaded,
      dbFileName: entry.dbFileName,
      env: AppEnvironment.dev,
    );
    await expectLater(offlineService.serverStatus(), throwsA(isA<SessionFailure>()));
    expect(await offlineService.resume(), isNull);

    // Đăng nhập lại ĐÚNG Account: chỉ có quyền cloud sau khi có phiên P7.1 hợp lệ.
    fh.uid = 'acc-A';
    fh.server.offline = false;
    await expectLater(offlineService.serverStatus(), throwsA(isA<SessionFailure>()));
    fh.activate('acc-A', secret: 'secret-A2');
    final status = await offlineService.serverStatus();
    expect(status.ownedByYou, isTrue);
    expect(status.selfMemberId, 'chong');
  });
}
