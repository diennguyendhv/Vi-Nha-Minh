import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/config/app_environment.dart';
import 'package:vi_nha_minh/data/cloud/family_device_key_store.dart';
import 'package:vi_nha_minh/data/cloud/family_service.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/seed_defaults.dart';
import 'package:vi_nha_minh/data/local/sync/cloud_binding_store.dart';
import 'package:vi_nha_minh/data/local/sync/sync_capture.dart';
import 'package:vi_nha_minh/data/local/wallet_registry.dart';
import 'package:vi_nha_minh/data/sync/cloud_sync_engine.dart';
import 'package:vi_nha_minh/data/sync/entity_codec.dart';
import 'package:vi_nha_minh/data/sync/restore_engine.dart';
import 'package:vi_nha_minh/domain/auth/cloud_session.dart';
import 'package:vi_nha_minh/domain/entities/wallet_identity.dart';

import '../support/emulator_cloud.dart';
import '../support/fake_cloud.dart'
    show FakeDevice, MemoryBackupKeyStore, MemorySessionStorage;
import '../support/temp_restore_storage.dart';

/// P10 Family end-to-end với backend THẬT (Functions + Firestore + Auth emulator,
/// project demo — không bao giờ live): A (Owner, chồng) nâng ví → mời B làm "vợ" →
/// B chấp nhận → vân tay khớp → A bọc BMK cho thiết bị B → B tải ví → đồng bộ 2 chiều
/// → xung đột → X không truy cập được → thu hồi. Chạy:
///   firebase emulators:exec --project demo-homewallet-p7 --only auth,firestore,functions
///     "flutter test test/sync/family_emulator_e2e_test.dart --dart-define=HW_EMULATOR=1"

const _password = 'Mật khẩu sao lưu Gia đình E2E';
const _secrets = ['Tiền chợ Gia-Đình-E2E', 'Lương-Vợ-E2E-7781', 'tx-fam-a', 'tx-fam-b'];

class _Device {
  _Device(String installation, EmulatorAccount account)
    : storage = MemorySessionStorage(installation),
      transport = EmulatorTransport()..current = account;
  final MemorySessionStorage storage;
  final EmulatorTransport transport;
  final keys = MemoryBackupKeyStore();
  final deviceKeys = MemoryFamilyDeviceKeyStore();
  late final CloudSession session = CloudSession(
    storage,
    transport.call,
    () => transport.current?.uid,
  )..revokedHandlers.add(keys.clear);
  CloudSyncEngine engine(AppDatabase db, {Future<void> Function(String)? lost}) =>
      CloudSyncEngine(
        db: db,
        session: session,
        transport: transport.call,
        keyStore: keys,
        env: AppEnvironment.dev,
        kdf: FakeDevice.testKdf,
        onMembershipLost: lost,
      );
}

Future<Map<String, String>> _state(AppDatabase db) async {
  final out = <String, String>{};
  for (final MapEntry(key: table, value: spec) in syncCapturedTables.entries) {
    for (final r in await db.customSelect('SELECT ${spec.pk} AS id FROM $table').get()) {
      final id = r.read<String>('id');
      out['${spec.kind}/$id'] =
          EntityCodec.canonicalJson((await EntityCodec.read(db, spec.kind, id))!['c']);
    }
  }
  return out;
}

TransactionRowsCompanion _income(String id, int amount, String member, String note) =>
    TransactionRowsCompanion.insert(
      id: id,
      type: 'income',
      categoryId: 'cat-fam',
      sourceKind: 'external',
      destinationKind: 'memberAvailable',
      destinationRefId: Value(member),
      amountMinor: amount,
      note: Value(note),
      transactionDate: DateTime(2026, 9, 27),
      createdAt: DateTime(2026, 9, 27, 9),
      clientTxId: 'client-$id',
    );

void main() {
  test('Family A↔B trên backend emulator thật: mời, khoá, tham gia, delta 2 chiều, X, thu hồi',
      () async {
    final a0 = await EmulatorAccount.createWithEmail();
    final b0 = await EmulatorAccount.createWithEmail();
    final x0 = await EmulatorAccount.createWithEmail();
    final a = _Device('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', a0.account);
    final dbA = AppDatabase.forTesting(NativeDatabase.memory(), seed: SeedProfile.fresh);
    final members = await (dbA.select(dbA.financialMemberRows)
          ..orderBy([(m) => OrderingTerm.asc(m.displayOrder)]))
        .get();
    final husband = members[0].memberId, wife = members[1].memberId;
    await dbA.into(dbA.categoryRows).insert(CategoryRowsCompanion.insert(
        id: 'cat-fam', name: 'Lương-Vợ-E2E-7781', colorValue: 1, type: 'income'));
    await dbA.into(dbA.transactionRows).insert(_income('tx-0', 1000, husband, 'mốc'));
    final walletId = (await dbA.select(dbA.walletMeta).getSingle()).walletId;

    // P7.1 + claim P8.2 + sao lưu P8.3 (Owner).
    await a.session.activate();
    final claim = await a.transport.call('claimWallet', {
      ...await a.session.credential(),
      'walletId': walletId,
      'selfMemberId': husband,
      'membersMinimalMetadata': [for (final m in members) {'memberId': m.memberId}],
      'payloadSchema': dbA.schemaVersion,
      'cryptoVersion': 1,
      'environment': 'dev',
      'claimRequestId': 'fa000000-0000-4000-8000-000000000001',
    });
    final store = CloudBindingStore(dbA);
    await store.beginClaim(accountId: a0.account.uid, selfMemberId: husband,
        environment: 'dev', claimRequestId: claim['claimRequestId'] as String);
    await store.activate(claimRequestId: claim['claimRequestId'] as String);
    final engineA = a.engine(dbA);
    await engineA.enableBackup(_password);
    await engineA.push();

    final registryA = WalletRegistry.inMemory([
      WalletRegistryEntry(walletId: walletId, kind: WalletKind.personal,
          dbFileName: 'wallet_a.sqlite', createdAt: DateTime(2026), boundAccountId: a0.account.uid),
    ]);
    final owner = FamilyService(session: a.session, transport: a.transport.call, keyStore: a.keys,
        deviceKeys: a.deviceKeys, registry: registryA, db: dbA, dbFileName: 'wallet_a.sqlite',
        env: AppEnvironment.dev);
    await owner.promote();
    expect(registryA.byWalletId(walletId)!.kind, WalletKind.family);
    final invite = await owner.invite(memberId: wife, email: b0.email.toUpperCase());

    // X (email khác) không xem/nhận được lời mời; không đọc được ví.
    final x = _Device('cccccccc-cccc-4ccc-8ccc-cccccccccccc', x0.account);
    await x.session.activate();
    final xService = FamilyService(session: x.session, transport: x.transport.call, keyStore: x.keys,
        deviceKeys: x.deviceKeys, registry: WalletRegistry.inMemory(), env: AppEnvironment.dev);
    await expectLater(xService.accept(invite.token),
        throwsA(isA<SessionFailure>().having((e) => e.reason, 'r', 'INVITE_INVALID')));

    // B chấp nhận TƯỜNG MINH; vân tay 2 máy trùng; A bọc khoá; B tải ví.
    final b = _Device('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', b0.account);
    await b.session.activate();
    final dir = await Directory.systemTemp.createTemp('vnm_family_e2e_');
    final registryB = WalletRegistry.inMemory();
    final bService = FamilyService(session: b.session, transport: b.transport.call, keyStore: b.keys,
        deviceKeys: b.deviceKeys, registry: registryB, env: AppEnvironment.dev,
        restore: RestoreEngine(session: b.session, transport: b.transport.call, keyStore: b.keys,
            registry: registryB, storage: TempRestoreStorage(dir), env: AppEnvironment.dev));
    expect((await bService.preview(invite.token)).memberId, wife);
    final accepted = await bService.accept(invite.token);
    await expectLater(bService.accept(invite.token),
        throwsA(isA<SessionFailure>().having((e) => e.reason, 'r', 'INVITE_INVALID')));
    await expectLater(bService.join(),
        throwsA(isA<FamilyException>().having((e) => e.reason, 'r', 'key-not-shared')));
    final pending = (await owner.status()).activeMember!;
    expect(pending.fingerprint, accepted.fingerprint);
    await owner.shareKey(pending);
    final joined = await bService.join();
    expect(joined.walletId, walletId);
    final entryB = registryB.byWalletId(walletId)!;
    expect((entryB.kind, entryB.boundAccountId, entryB.familyMember),
        (WalletKind.family, b0.account.uid, true));
    final dbB = AppDatabase.forTesting(NativeDatabase(File('${dir.path}/${entryB.dbFileName}')));
    expect(await _state(dbB), await _state(dbA));
    expect((await CloudBindingStore(dbB).read())!.selfMemberId, wife);
    final lost = <String>[];
    final engineB = b.engine(dbB, lost: (id) async => lost.add(id));

    // A → B.
    await dbA.into(dbA.transactionRows).insert(_income('tx-fam-a', 42000, husband, 'Tiền chợ Gia-Đình-E2E'));
    await engineA.syncNow();
    await engineB.syncNow(pullFirst: true);
    expect((await (dbB.select(dbB.transactionRows)..where((t) => t.id.equals('tx-fam-a')))
            .getSingle()).clientTxId, 'client-tx-fam-a');
    // B → A.
    await dbB.into(dbB.transactionRows).insert(_income('tx-fam-b', 58000, wife, 'Lương-Vợ-E2E-7781'));
    final cB = b.transport.calls;
    await engineB.syncNow();
    expect(b.transport.calls - cB, 1, reason: '1 delta = 1 lời gọi ghi');
    await engineA.syncNow(pullFirst: true);
    expect(await _state(dbA), await _state(dbB));

    // Sửa đồng thời cùng giao dịch ⇒ xung đột tường minh ở máy ghi sau.
    await (dbA.update(dbA.transactionRows)..where((t) => t.id.equals('tx-0')))
        .write(const TransactionRowsCompanion(note: Value('A sửa')));
    await (dbB.update(dbB.transactionRows)..where((t) => t.id.equals('tx-0')))
        .write(const TransactionRowsCompanion(note: Value('B sửa')));
    await engineA.syncNow();
    final r = await engineB.syncNow();
    expect(r.pull!.conflicts, 1);
    await engineA.syncNow(pullFirst: true);
    expect(await _state(dbA), await _state(dbB));

    // Rảnh: 0 lời gọi.
    final ca = a.transport.calls, cb = b.transport.calls;
    await engineA.syncNow();
    await engineB.syncNow();
    expect((a.transport.calls - ca, b.transport.calls - cb), (0, 0));

    // X không đọc được ví Family.
    await expectLater(x.transport.call('getEncryptedChanges',
        {...await x.session.credential(), 'walletId': walletId, 'sinceRev': 0}),
        throwsA(isA<SessionFailure>().having((e) => e.reason, 'r', 'NOT_MEMBER')));

    // Firestore thật (admin, emulator): không bản rõ, không BMK.
    final bmk = (await a.keys.load(a0.account.uid))!.bmk;
    final dump = await firestoreDump(['wallets/$walletId', 'familyInvites',
        'accounts/${a0.account.uid}', 'accounts/${b0.account.uid}']);
    for (final s in [..._secrets, _password, base64.encode(bmk), invite.token, 'transaction']) {
      expect(dump.contains(s), isFalse, reason: 'Firestore lộ "$s"');
    }

    // Thu hồi: B mất quyền cloud ngay, được báo NOT_MEMBER (ẩn ví), file giữ nguyên.
    await owner.revoke((await owner.status()).activeMember!);
    await expectLater(engineB.syncNow(pullFirst: true),
        throwsA(isA<SessionFailure>().having((e) => e.reason, 'r', 'NOT_MEMBER')));
    expect(lost, [walletId]);
    expect(File('${dir.path}/${entryB.dbFileName}').existsSync(), isTrue);

    // ignore: avoid_print
    print('[family-e2e] A calls=${a.transport.calls} B calls=${b.transport.calls} '
        'X calls=${x.transport.calls}');
    await dbB.close();
    await dbA.close();
    await dir.delete(recursive: true);
  }, skip: emulatorEnabled ? false : 'cần emulator (--dart-define=HW_EMULATOR=1)',
      timeout: const Timeout(Duration(minutes: 3)));
}
