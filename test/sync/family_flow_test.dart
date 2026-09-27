import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/config/app_environment.dart';
import 'package:vi_nha_minh/data/cloud/family_device_key_store.dart';
import 'package:vi_nha_minh/data/cloud/family_service.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/sync/cloud_binding_store.dart';
import 'package:vi_nha_minh/data/local/sync/sync_capture.dart';
import 'package:vi_nha_minh/data/local/wallet_registry.dart';
import 'package:vi_nha_minh/data/repositories/local_transaction_repository.dart';
import 'package:vi_nha_minh/data/sync/cloud_sync_engine.dart';
import 'package:vi_nha_minh/data/sync/entity_codec.dart';
import 'package:vi_nha_minh/data/sync/restore_engine.dart';
import 'package:vi_nha_minh/domain/auth/cloud_session.dart';
import 'package:vi_nha_minh/domain/engine/financial_engine.dart';
import 'package:vi_nha_minh/domain/entities/wallet_access_scope.dart';
import 'package:vi_nha_minh/domain/entities/wallet_identity.dart';

import '../support/fake_cloud.dart';
import '../support/temp_restore_storage.dart';

/// P10 Family v1 — Owner A (chồng) mời Account B làm FinancialMember "vợ" ĐÃ CÓ; 2
/// installation dùng CHUNG 1 Wallet (cùng walletId, cùng id giao dịch), đồng bộ delta
/// mã hoá 2 chiều, xung đột tường minh, thu hồi. Hợp đồng máy chủ thật:
/// functions/test/family.test.js + test/sync/family_emulator_e2e_test.dart.

const _password = 'Mật khẩu sao lưu Gia đình 2026';

TransactionRowsCompanion _income(String id, int amount, String member) =>
    TransactionRowsCompanion.insert(
      id: id,
      type: 'income',
      categoryId: 'cat-thu',
      sourceKind: 'external',
      destinationKind: 'memberAvailable',
      destinationRefId: Value(member),
      amountMinor: amount,
      note: Value('Ghi chú $id'),
      transactionDate: DateTime(2026, 9, 20),
      createdAt: DateTime(2026, 9, 20, 8),
      clientTxId: 'client-$id',
    );

Future<Map<String, String>> _state(AppDatabase db) async {
  final out = <String, String>{};
  for (final MapEntry(key: table, value: spec) in syncCapturedTables.entries) {
    for (final r in await db
        .customSelect('SELECT ${spec.pk} AS id FROM $table')
        .get()) {
      final id = r.read<String>('id');
      out['${spec.kind}/$id'] = EntityCodec.canonicalJson(
        (await EntityCodec.read(db, spec.kind, id))!['c'],
      );
    }
  }
  return out;
}

Future<Map<String, int>> _balances(AppDatabase db) async => {
  for (final e in computeAllPoolBalances(
    await LocalTransactionRepository(db).allTransactions(),
  ).entries)
    e.key.toString(): e.value,
};

Future<TransactionRow?> _tx(AppDatabase db, String id) => (db.select(
  db.transactionRows,
)..where((t) => t.id.equals(id))).getSingleOrNull();

void main() {
  late FakeCloud cloud;
  late FakeDevice a;
  late WalletRegistry registryA;
  late FamilyService ownerService;
  late String walletId;
  late String husband;
  late String wife;
  late Directory dir;

  setUp(() async {
    cloud = FakeCloud()
      ..emails.addAll({
        'uid-a': 'chong@test.dev',
        'uid-b': 'vo@test.dev',
        'uid-x': 'la@test.dev',
      });
    a = FakeDevice(cloud);
    final members = await (a.db.select(
      a.db.financialMemberRows,
    )..orderBy([(m) => OrderingTerm.asc(m.displayOrder)])).get();
    husband = members[0].memberId;
    wife = members[1].memberId;
    await a.db
        .into(a.db.categoryRows)
        .insert(
          CategoryRowsCompanion.insert(
            id: 'cat-thu',
            name: 'Lương',
            colorValue: 1,
            type: 'income',
          ),
        );
    for (var i = 0; i < 6; i++) {
      await a.db
          .into(a.db.transactionRows)
          .insert(_income('tx-$i', 1000 * (i + 1), i.isEven ? husband : wife));
    }
    await a.signIn('uid-a');
    await a.claim(selfMemberId: husband);
    await a.engine.enableBackup(_password);
    await a.engine.push();
    walletId = await a.walletId();
    registryA = WalletRegistry.inMemory([
      WalletRegistryEntry(
        walletId: 'local-bootstrap-a',
        kind: WalletKind.local,
        dbFileName: 'vi_nha_minh.sqlite',
        createdAt: DateTime(2026),
      ),
      WalletRegistryEntry(
        walletId: walletId,
        kind: WalletKind.personal,
        dbFileName: 'wallet_a.sqlite',
        createdAt: DateTime(2026),
        boundAccountId: 'uid-a',
      ),
    ]);
    ownerService = FamilyService(
      session: a.session,
      transport: cloud.call,
      keyStore: a.keys,
      deviceKeys: MemoryFamilyDeviceKeyStore(),
      registry: registryA,
      db: a.db,
      dbFileName: 'wallet_a.sqlite',
      env: AppEnvironment.dev,
    );
    dir = await Directory.systemTemp.createTemp('vnm_family_');
  });

  tearDown(() async {
    await a.db.close();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  /// Máy B (installation riêng) của Account [uid], chưa có ví Family.
  Future<
    ({
      FakeDevice device,
      FamilyService service,
      WalletRegistry registry,
    })
  >
  memberDevice(String uid, {String installation = '22222222-2222-4222-8222-222222222222'}) async {
    final d = FakeDevice(cloud, installation: installation);
    await d.signIn(uid);
    final registry = WalletRegistry.inMemory([
      WalletRegistryEntry(
        walletId: 'local-bootstrap-$uid',
        kind: WalletKind.local,
        dbFileName: 'vi_nha_minh.sqlite',
        createdAt: DateTime(2026),
      ),
    ]);
    final service = FamilyService(
      session: d.session,
      transport: cloud.call,
      keyStore: d.keys,
      deviceKeys: MemoryFamilyDeviceKeyStore(),
      registry: registry,
      restore: RestoreEngine(
        session: d.session,
        transport: cloud.call,
        keyStore: d.keys,
        registry: registry,
        storage: TempRestoreStorage(dir),
        env: AppEnvironment.dev,
      ),
      env: AppEnvironment.dev,
    );
    return (device: d, service: service, registry: registry);
  }

  /// Owner: nâng ví + mời Account B làm "vợ"; B chấp nhận; 2 bên đối chiếu vân tay;
  /// Owner chia sẻ khoá; B tải ví. Trả về DB + engine của B.
  Future<
    ({
      FakeDevice device,
      FamilyService service,
      WalletRegistry registry,
      AppDatabase db,
      CloudSyncEngine engine,
      List<String> lost,
    })
  >
  joinB() async {
    await ownerService.promote();
    final invite = await ownerService.invite(memberId: wife, email: ' VO@test.dev ');
    // Lựa chọn thành viên ghi nhớ là dữ liệu ví (wallet_settings) ⇒ đồng bộ như mọi thay đổi.
    await a.engine.push();
    final b = await memberDevice('uid-b');
    final accepted = await b.service.accept(invite.token);
    // Chấp nhận lại (bị máy chủ từ chối) không được làm hỏng khoá thiết bị đã đăng ký.
    await expectLater(b.service.accept(invite.token), throwsA(isA<SessionFailure>()));
    final status = await ownerService.status();
    final pending = status.activeMember!;
    expect(pending.awaitingKey, isTrue);
    expect(pending.fingerprint, accepted.fingerprint);
    await ownerService.shareKey(pending);
    final joined = await b.service.join();
    expect(joined.restored, isTrue);
    final entry = b.registry.byWalletId(walletId)!;
    final db = AppDatabase.forTesting(
      NativeDatabase(File('${dir.path}/${entry.dbFileName}')),
    );
    final lost = <String>[];
    final engine = CloudSyncEngine(
      db: db,
      session: b.device.session,
      transport: cloud.call,
      keyStore: b.device.keys,
      env: AppEnvironment.dev,
      onMembershipLost: (id) async {
        lost.add(id);
        await b.registry.setFamilyFlags(id, accessRevoked: true);
      },
    );
    return (
      device: b.device,
      service: b.service,
      registry: b.registry,
      db: db,
      engine: engine,
      lost: lost,
    );
  }

  test('Personal → Family tại chỗ: cùng walletId/file/id/BMK/lịch sử; idempotent', () async {
    final before = await _state(a.db);
    final bmk = (await a.keys.load('uid-a'))!.bmk;
    final head = cloud.wallets[walletId]!['headRev'];
    await ownerService.promote();
    await ownerService.promote();
    expect(cloud.wallets[walletId]!['kind'], 'family');
    expect((await a.db.select(a.db.walletMeta).getSingle()).walletId, walletId);
    expect((await a.db.select(a.db.walletMeta).getSingle()).kind, 'family');
    expect(await _state(a.db), before);
    expect((await a.keys.load('uid-a'))!.bmk, bmk);
    expect(cloud.wallets[walletId]!['headRev'], head);
    final e = registryA.byWalletId(walletId)!;
    expect((e.kind, e.dbFileName, e.boundAccountId), (
      WalletKind.family,
      'wallet_a.sqlite',
      'uid-a',
    ));
    final binding = await CloudBindingStore(a.db).read();
    expect((binding!.accountId, binding.selfMemberId), ('uid-a', husband));
    expect(await SyncOutboxStore(a.db).count(), 0);
  });

  test('lời mời: chỉ Owner, không chọn sẵn thành viên, sai Account/dùng lại bị từ chối', () async {
    await ownerService.promote();
    final choices = await ownerService.inviteChoices(husband);
    expect([for (final c in choices) c.memberId], [wife]);
    final invite = await ownerService.invite(memberId: wife, email: 'vo@test.dev');
    final x = await memberDevice('uid-x', installation: '33333333-3333-4333-8333-333333333333');
    await expectLater(
      x.service.accept(invite.token),
      throwsA(isA<SessionFailure>().having((e) => e.reason, 'reason', 'INVITE_INVALID')),
    );
    final b = await memberDevice('uid-b');
    final preview = await b.service.preview(invite.token);
    expect((preview.walletId, preview.memberId), (walletId, wife));
    await b.service.accept(invite.token);
    await expectLater(
      b.service.accept(invite.token),
      throwsA(isA<SessionFailure>().having((e) => e.reason, 'reason', 'INVITE_INVALID')),
    );
    // Member không mời/thu hồi được; gia đình đã đủ 2 Account.
    final bOwnerOps = FamilyService(
      session: b.device.session,
      transport: cloud.call,
      keyStore: b.device.keys,
      deviceKeys: MemoryFamilyDeviceKeyStore(),
      registry: b.registry,
      db: a.db,
      dbFileName: 'x',
      env: AppEnvironment.dev,
    );
    await expectLater(
      bOwnerOps.invite(memberId: husband, email: 'la@test.dev'),
      throwsA(isA<SessionFailure>()),
    );
    await expectLater(
      ownerService.invite(memberId: wife, email: 'la@test.dev'),
      throwsA(isA<SessionFailure>().having((e) => e.reason, 'reason', 'FAMILY_FULL')),
    );
    // Owner không tự mời chính mình.
    cloud.memberships[walletId]!.remove('uid-b');
    await expectLater(
      ownerService.invite(memberId: wife, email: 'chong@test.dev'),
      throwsA(isA<SessionFailure>().having((e) => e.reason, 'reason', 'SELF_INVITE')),
    );
  });

  test('chưa chia sẻ khoá ⇒ B chưa tải được; máy chủ đổi public key ⇒ Owner không bọc', () async {
    await ownerService.promote();
    final invite = await ownerService.invite(memberId: wife, email: 'vo@test.dev');
    final b = await memberDevice('uid-b');
    final accepted = await b.service.accept(invite.token);
    await expectLater(
      b.service.join(),
      throwsA(isA<FamilyException>().having((e) => e.reason, 'reason', 'key-not-shared')),
    );
    final view = (await ownerService.status()).activeMember!;
    // Máy chủ độc hại thay public key sau khi Owner đã xem vân tay.
    cloud.memberships[walletId]!['uid-b']!['publicKey'] =
        'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=';
    await expectLater(
      ownerService.shareKey(view),
      throwsA(isA<SessionFailure>().having((e) => e.reason, 'reason', 'PUBLIC_KEY_CHANGED')),
    );
    // Vân tay tính lại từ khoá bị tráo KHÔNG còn khớp màn hình B.
    final swapped = (await ownerService.status()).activeMember!;
    expect(swapped.fingerprint, isNot(accepted.fingerprint));
  });

  test('máy chủ đổi memberId đã chọn lúc mời ⇒ Owner KHÔNG bọc BMK (member-mismatch)', () async {
    await ownerService.promote();
    final invite = await ownerService.invite(memberId: wife, email: 'vo@test.dev');
    final b = await memberDevice('uid-b');
    await b.service.accept(invite.token);
    // Máy chủ độc hại gắn B vào FinancialMember khác (chồng) cho CẢ 2 phía ⇒ vân tay
    // 2 máy vẫn trùng; chỉ lựa chọn Owner ghi nhớ cục bộ mới phát hiện được.
    cloud.memberships[walletId]!['uid-b']!['memberId'] = husband;
    final view = (await ownerService.status()).activeMember!;
    expect(view.memberId, husband);
    final callsBefore = ownerService.calls;
    await expectLater(
      ownerService.shareKey(view),
      throwsA(isA<FamilyException>().having((e) => e.reason, 'reason', 'member-mismatch')),
    );
    expect(ownerService.calls, callsBefore, reason: 'không gửi gói khoá nào');
    expect(cloud.memberships[walletId]!['uid-b']!['wrappedKey'], isNull);
    // Thiếu lựa chọn đã ghi nhớ (vd ví cũ) ⇒ cũng dừng (fail closed).
    cloud.memberships[walletId]!['uid-b']!['memberId'] = wife;
    await (a.db.delete(a.db.walletSettings)
          ..where((s) => s.key.equals(FamilyService.invitedMemberKey)))
        .go();
    await expectLater(
      ownerService.shareKey((await ownerService.status()).activeMember!),
      throwsA(isA<FamilyException>().having((e) => e.reason, 'reason', 'member-mismatch')),
    );
  });

  test('B tham gia: cùng walletId, cùng id/clientTxId/memberId, cùng số dư; binding = vợ', () async {
    final b = await joinB();
    expect((await b.db.select(b.db.walletMeta).getSingle()).walletId, walletId);
    expect((await b.db.select(b.db.walletMeta).getSingle()).kind, 'family');
    expect(await _state(b.db), await _state(a.db));
    expect(await _balances(b.db), await _balances(a.db));
    final binding = (await CloudBindingStore(b.db).read())!;
    expect((binding.accountId, binding.selfMemberId), ('uid-b', wife));
    final entry = b.registry.byWalletId(walletId)!;
    expect((entry.kind, entry.boundAccountId, entry.familyMember), (
      WalletKind.family,
      'uid-b',
      true,
    ));
    expect(await ownerService.walletCode(), isNotNull);
    expect(
      await FamilyService(
        session: b.device.session,
        transport: cloud.call,
        keyStore: b.device.keys,
        deviceKeys: MemoryFamilyDeviceKeyStore(),
        registry: b.registry,
        db: b.db,
        dbFileName: entry.dbFileName,
        env: AppEnvironment.dev,
      ).walletCode(),
      await ownerService.walletCode(),
    );
    // Máy chủ không bao giờ thấy BMK / nhãn / số tiền.
    final dump = cloud.dump();
    for (final s in ['Ghi chú tx-1', 'Lương', 'chong@test', 'vo@test']) {
      expect(dump.contains(s), isFalse, reason: s);
    }
    await b.db.close();
  });

  test('A→B và B→A: cùng id giao dịch, cùng số dư, đúng người ghi nhận; rảnh = 0 lời gọi', () async {
    final b = await joinB();
    await a.db.into(a.db.transactionRows).insert(_income('tx-A', 50000, husband));
    await a.engine.syncNow();
    // Màn hình đang theo dõi (Drift) phải được báo khi lượt kéo ghi dòng mới.
    final notified = b.db
        .tableUpdates(TableUpdateQuery.onTableName('transaction_rows'))
        .first;
    final pulledB = await b.engine.syncNow(pullFirst: true);
    await notified.timeout(const Duration(seconds: 2));
    expect(pulledB.pull!.applied, 1);
    expect((await _tx(b.db, 'tx-A'))!.clientTxId, 'client-tx-A');

    await b.db.into(b.db.transactionRows).insert(_income('tx-B', 70000, wife));
    await b.engine.syncNow();
    await a.engine.syncNow(pullFirst: true);
    final tb = (await _tx(a.db, 'tx-B'))!;
    expect((tb.clientTxId, tb.destinationRefId), ('client-tx-B', wife));
    expect(await _state(a.db), await _state(b.db));
    expect(await _balances(a.db), await _balances(b.db));

    final ca = a.engine.calls, cb = b.engine.calls;
    await a.engine.syncNow();
    await b.engine.syncNow();
    expect((a.engine.calls - ca, b.engine.calls - cb), (0, 0));
    await b.db.close();
  });

  test('2 người ghi cùng head + cùng seq cục bộ: id batch KHÔNG trùng ⇒ cả 2 được lưu', () async {
    final b = await joinB();
    await a.db.into(a.db.transactionRows).insert(_income('tx-sa', 1, husband));
    await b.db.into(b.db.transactionRows).insert(_income('tx-sb', 2, wife));
    await a.db.customStatement('UPDATE sync_outbox SET seq = 999');
    await b.db.customStatement('UPDATE sync_outbox SET seq = 999');
    await a.engine.syncNow();
    await b.engine.syncNow();
    await a.engine.syncNow(pullFirst: true);
    expect(await _tx(a.db, 'tx-sb'), isNotNull);
    expect(await _tx(b.db, 'tx-sa'), isNotNull);
    expect(await _state(a.db), await _state(b.db));
    await b.db.close();
  });

  test('sửa đồng thời cùng thực thể ⇒ 1 bản thắng, bản kia vào sync_conflicts (không mất)', () async {
    final b = await joinB();
    await (a.db.update(a.db.transactionRows)..where((t) => t.id.equals('tx-1')))
        .write(const TransactionRowsCompanion(note: Value('A sửa')));
    await (b.db.update(b.db.transactionRows)..where((t) => t.id.equals('tx-1')))
        .write(const TransactionRowsCompanion(note: Value('B sửa')));
    await a.engine.syncNow();
    final r = await b.engine.syncNow();
    expect(r.pull!.conflicts, 1);
    expect((await _tx(b.db, 'tx-1'))!.note, 'A sửa');
    final conflict = await b.db.select(b.db.syncConflicts).getSingle();
    expect(conflict.entityId, 'tx-1');
    expect(conflict.localBody, contains('B sửa'));
    await a.engine.syncNow(pullFirst: true);
    expect((await _tx(a.db, 'tx-1'))!.note, 'A sửa');
    expect(await _state(a.db), await _state(b.db));
    await b.db.close();
  });

  test('xoá vs sửa: không hồi sinh; xoá vs xoá: idempotent', () async {
    final b = await joinB();
    await (a.db.delete(a.db.transactionRows)..where((t) => t.id.equals('tx-2'))).go();
    await (b.db.update(b.db.transactionRows)..where((t) => t.id.equals('tx-2')))
        .write(const TransactionRowsCompanion(note: Value('B sửa sau khi A xoá')));
    await a.engine.syncNow();
    final r = await b.engine.syncNow();
    expect(r.pull!.conflicts, 1);
    expect(await _tx(b.db, 'tx-2'), isNull);
    await a.engine.syncNow(pullFirst: true);
    expect(await _tx(a.db, 'tx-2'), isNull);

    await (a.db.delete(a.db.transactionRows)..where((t) => t.id.equals('tx-3'))).go();
    await (b.db.delete(b.db.transactionRows)..where((t) => t.id.equals('tx-3'))).go();
    await a.engine.syncNow();
    final r2 = await b.engine.syncNow();
    expect(r2.pull!.conflicts, 0);
    expect(await SyncOutboxStore(b.db).count(), 0);
    await a.engine.syncNow(pullFirst: true);
    expect(await _state(a.db), await _state(b.db));
    await b.db.close();
  });

  test('ghép 2 lần chi offline làm pool âm ⇒ được phát hiện + báo, không tự sửa', () async {
    final b = await joinB();
    final bal = (await _balances(a.db))
        .entries
        .firstWhere((e) => e.key.contains(wife))
        .value;
    TransactionRowsCompanion spend(String id) => TransactionRowsCompanion.insert(
      id: id,
      type: 'expense',
      categoryId: 'cat-thu',
      sourceKind: 'memberAvailable',
      sourceRefId: Value(wife),
      destinationKind: 'external',
      amountMinor: bal,
      transactionDate: DateTime(2026, 9, 21),
      createdAt: DateTime(2026, 9, 21),
      clientTxId: 'client-$id',
    );
    await a.db.into(a.db.transactionRows).insert(spend('spend-a'));
    await b.db.into(b.db.transactionRows).insert(spend('spend-b'));
    await a.engine.syncNow();
    final r = await b.engine.syncNow();
    expect(r.pull!.overdrawnPools, 1);
    expect(b.engine.lastOverdrawnPools, 1);
    await b.db.close();
  });

  test('thu hồi: B mất quyền cloud ngay; ví B bị ẩn, file + khoá giữ nguyên', () async {
    final b = await joinB();
    final view = (await ownerService.status()).activeMember!;
    await ownerService.revoke(view);
    await expectLater(
      b.engine.syncNow(pullFirst: true),
      throwsA(isA<SessionFailure>().having((e) => e.reason, 'reason', 'NOT_MEMBER')),
    );
    expect(b.lost, [walletId]);
    final entry = b.registry.byWalletId(walletId)!;
    expect(entry.accessRevoked, isTrue);
    expect(entry.canOpen(const WalletAccessScope.account('uid-b')), isFalse);
    expect(File('${dir.path}/${entry.dbFileName}').existsSync(), isTrue);
    expect(await b.db.select(b.db.transactionRows).get(), isNotEmpty);
    await expectLater(
      b.service.join(),
      throwsA(isA<FamilyException>().having((e) => e.reason, 'reason', 'not-member')),
    );
    await b.db.close();
  });

  test('A→X→A trên máy chồng / B→Y→B trên máy vợ: ẩn với Account khác, cùng ví khi quay lại', () async {
    final b = await joinB();
    const local = WalletAccessScope.local();
    const scopeA = WalletAccessScope.account('uid-a');
    const scopeX = WalletAccessScope.account('uid-x');
    await registryA.markActive(walletId);
    expect(registryA.resolveActive(scopeA)!.walletId, walletId);
    // Đăng xuất / Account lạ: ví Family bị ẩn, rơi về ví cục bộ lúc cài.
    expect(registryA.resolveActive(local)!.walletId, 'local-bootstrap-a');
    expect(registryA.resolveActive(scopeX)!.walletId, 'local-bootstrap-a');
    expect(registryA.openableFor(scopeX).map((e) => e.walletId), isNot(contains(walletId)));
    // X không đọc/ghi/claim được ví này trên máy chủ.
    a.signOut();
    await a.signIn('uid-x');
    await expectLater(
      cloud.call('getEncryptedChanges', {
        ...await a.session.credential(),
        'walletId': walletId,
        'sinceRev': 0,
      }),
      throwsA(isA<SessionFailure>().having((e) => e.reason, 'reason', 'NOT_MEMBER')),
    );
    await expectLater(a.engine.syncNow(), throwsA(anything));
    a.signOut();
    await a.signIn('uid-a');
    final back = registryA.resolveActive(scopeA)!;
    expect((back.walletId, back.dbFileName), (walletId, 'wallet_a.sqlite'));
    expect((await a.db.select(a.db.walletMeta).getSingle()).walletId, walletId);

    const scopeB = WalletAccessScope.account('uid-b');
    const scopeY = WalletAccessScope.account('uid-y');
    final fileB = b.registry.byWalletId(walletId)!.dbFileName;
    expect(b.registry.resolveActive(scopeB)!.walletId, walletId);
    expect(b.registry.resolveActive(scopeY)!.walletId, 'local-bootstrap-uid-b');
    expect(b.registry.resolveActive(local)!.walletId, 'local-bootstrap-uid-b');
    expect(b.registry.resolveActive(scopeB)!.dbFileName, fileB);
    expect(File('${dir.path}/$fileB').existsSync(), isTrue);
    await b.db.close();
  });

  test('phiên P7.1 cũ (thiết bị khác đã tiếp quản) ⇒ Member bị từ chối', () async {
    final b = await joinB();
    await b.db.into(b.db.transactionRows).insert(_income('tx-stale', 5, wife));
    cloud.activate('uid-b'); // installation khác của B trở thành phiên hiện hành
    await expectLater(b.engine.syncNow(), throwsA(isA<SessionFailure>()));
    expect(await SyncOutboxStore(b.db).count(), 1);
    await b.db.close();
  });
}
