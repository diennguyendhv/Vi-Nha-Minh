import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/config/app_environment.dart';
import 'package:vi_nha_minh/data/backup/backup_service.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/seed_defaults.dart';
import 'package:vi_nha_minh/data/local/sync/cloud_binding_store.dart';
import 'package:vi_nha_minh/data/local/sync/sync_capture.dart';
import 'package:vi_nha_minh/data/local/wallet_registry.dart';
import 'package:vi_nha_minh/data/sync/cloud_sync_engine.dart';
import 'package:vi_nha_minh/data/sync/entity_codec.dart';
import 'package:vi_nha_minh/data/sync/restore_engine.dart';
import 'package:vi_nha_minh/domain/auth/cloud_session.dart';

import '../support/emulator_cloud.dart';
import '../support/fake_cloud.dart' show FakeDevice, MemoryBackupKeyStore, MemorySessionStorage;
import '../support/temp_restore_storage.dart';

/// P8.3/P8.4/P8.5 end-to-end với backend THẬT (Functions + Firestore + Auth emulator,
/// project demo — không bao giờ live). Chạy:
///   firebase emulators:exec --project demo-homewallet-p7 --only auth,firestore,functions
///     "flutter test test/sync/emulator_e2e_test.dart --dart-define=HW_EMULATOR=1"

const _password = 'Mật khẩu sao lưu E2E ĐẶC BIỆT';
final _secrets = <String>[
  'Tiền học Bé Na — Trường Hoà Bình',
  'Quỹ Cưới Em-Gái-9931',
  'Lương-Công-Ty-XYZ',
  '12345678901',
  'tx-e2e-dac-biet',
  'cat-e2e-luong',
  'client-tx-e2e-dac-biet',
  'fund-e2e-cuoi',
  'Nhãn-Thành-Viên-Chồng-E2E',
];

class _Device {
  _Device(String installation)
    : storage = MemorySessionStorage(installation),
      transport = EmulatorTransport();
  final MemorySessionStorage storage;
  final EmulatorTransport transport;
  final keys = MemoryBackupKeyStore();
  late final CloudSession session = CloudSession(
    storage,
    transport.call,
    () => transport.current?.uid,
  )..revokedHandlers.add(keys.clear);
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

void main() {
  test('backup ban đầu + delta + quét bản rõ Firestore + mất máy → khôi phục', () async {
    final account = await EmulatorAccount.create();
    final a = _Device('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    a.transport.current = account;
    final db = AppDatabase.forTesting(NativeDatabase.memory(), seed: SeedProfile.fresh);
    await (db.update(db.financialMemberRows)..where((m) => m.displayOrder.equals(1)))
        .write(const FinancialMemberRowsCompanion(label: Value('Nhãn-Thành-Viên-Chồng-E2E')));
    await db.into(db.categoryRows).insert(CategoryRowsCompanion.insert(
      id: 'cat-e2e-luong', name: 'Lương-Công-Ty-XYZ', colorValue: 1, type: 'income'));
    await db.into(db.fundRows).insert(
      FundRowsCompanion.insert(id: 'fund-e2e-cuoi', name: 'Quỹ Cưới Em-Gái-9931', colorValue: 2));
    final members = await db.select(db.financialMemberRows).get();
    await db.into(db.transactionRows).insert(TransactionRowsCompanion.insert(
      id: 'tx-e2e-dac-biet', type: 'income', categoryId: 'cat-e2e-luong',
      sourceKind: 'external', destinationKind: 'memberAvailable',
      destinationRefId: Value(members[1].memberId), amountMinor: 12345678901,
      note: const Value('Tiền học Bé Na — Trường Hoà Bình'),
      transactionDate: DateTime(2026, 9, 3), createdAt: DateTime(2026, 9, 3, 7),
      clientTxId: 'client-tx-e2e-dac-biet'));
    final walletId = (await db.select(db.walletMeta).getSingle()).walletId;

    // P7.1 phiên + claim P8.2 thật.
    await a.session.activate();
    final claim = await a.transport.call('claimWallet', {
      ...await a.session.credential(),
      'walletId': walletId,
      'selfMemberId': members[1].memberId,
      'membersMinimalMetadata': [for (final m in members) {'memberId': m.memberId}],
      'payloadSchema': db.schemaVersion,
      'cryptoVersion': 1,
      'environment': 'dev',
      'claimRequestId': 'e2e00000-0000-4000-8000-000000000001',
    });
    final store = CloudBindingStore(db);
    await store.beginClaim(accountId: account.uid, selfMemberId: members[1].memberId,
        environment: 'dev', claimRequestId: claim['claimRequestId'] as String);
    await store.activate(claimRequestId: claim['claimRequestId'] as String);

    final engine = CloudSyncEngine(db: db, session: a.session, transport: a.transport.call,
        keyStore: a.keys, env: AppEnvironment.dev, kdf: FakeDevice.testKdf);
    final recovery = await engine.enableBackup(_password);
    expect(recovery, startsWith('HW1-'));
    final c0 = a.transport.calls;
    final initial = await engine.push();
    final initialCalls = a.transport.calls - c0;
    expect(await engine.backupState(), 'COMPLETE');

    // Delta: 1 sửa ⇒ 1 lời gọi ghi.
    await (db.update(db.transactionRows)..where((t) => t.id.equals('tx-e2e-dac-biet')))
        .write(const TransactionRowsCompanion(note: Value('Tiền học Bé Na — Trường Hoà Bình (sửa)')));
    final c1 = a.transport.calls;
    final delta = await engine.push();
    expect(a.transport.calls - c1, 1);
    expect(delta.envelopes, 2);
    // Rảnh: 0 lời gọi; kéo tường minh = đúng 1 lời gọi đọc.
    final c2 = a.transport.calls;
    await engine.syncNow();
    expect(a.transport.calls - c2, 0);
    await engine.syncNow(pullFirst: true);
    expect(a.transport.calls - c2, 1);

    // Firestore thật (admin, emulator): không bản rõ nào.
    final dump = await firestoreDump(['wallets/$walletId', 'accounts/${account.uid}']);
    expect(dump.contains('"c"'), isTrue);
    for (final s in [..._secrets, _password, 'transaction', 'financialMember', 'walletSetting',
        'category', recovery!]) {
      expect(dump.contains(s), isFalse, reason: 'Firestore lộ "$s"');
    }

    // Mất máy: thiết bị mới C khôi phục phiên bằng Mật khẩu sao lưu (A bị thu hồi),
    // rồi khôi phục ví vào file MỚI.
    final c = _Device('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
    c.transport.current = account;
    await BackupService(session: c.session, transport: c.transport.call, keyStore: c.keys,
            env: AppEnvironment.dev)
        .recoverOnThisDevice(walletId: walletId, password: _password);
    final dir = await Directory.systemTemp.createTemp('vnm_e2e_');
    final registry = WalletRegistry.inMemory();
    final result = await RestoreEngine(session: c.session, transport: c.transport.call,
            keyStore: c.keys, registry: registry, storage: TempRestoreStorage(dir),
            env: AppEnvironment.dev)
        .restore(walletId: walletId, recoveryKey: recovery);
    expect(result.checkpointVerified, isTrue);
    final restored = AppDatabase.forTesting(NativeDatabase(File('${dir.path}/${result.dbFileName}')));
    expect(await _state(restored), await _state(db));
    expect((await restored.select(restored.walletMeta).getSingle()).walletId, walletId);

    // Máy A cũ: DEVICE_REVOKED ⇒ BMK cục bộ bị xoá, không đẩy được nữa.
    await db.into(db.transactionRows).insert(TransactionRowsCompanion.insert(
      id: 'tx-sau-khi-mat', type: 'income', categoryId: 'cat-e2e-luong', sourceKind: 'external',
      destinationKind: 'external', amountMinor: 1, transactionDate: DateTime(2026, 9, 4),
      createdAt: DateTime(2026, 9, 4), clientTxId: 'c-sau'));
    await expectLater(engine.push(), throwsA(isA<SessionFailure>()));
    expect(await a.keys.load(account.uid), isNull);

    final cBytes = RegExp(r'"c":\s*\{\s*"stringValue":\s*"([^"]+)"')
        .allMatches(dump)
        .fold<int>(0, (n, m) => n + m.group(1)!.length * 3 ~/ 4);
    final entityDocs = RegExp('/entities/').allMatches(dump).length;
    // ignore: avoid_print
    print('[e2e] firestore entityDocs~$entityDocs ciphertextBytes=$cBytes');
    // ignore: avoid_print
    print('[e2e] initialBackup envelopes=${initial.envelopes} batches=${initial.batches} '
        'calls=$initialCalls | delta calls=1 envelopes=${delta.envelopes} | idle calls=0 | '
        'restore calls=${a.transport.calls}');
    await restored.close();
    await db.close();
    await dir.delete(recursive: true);
  }, skip: emulatorEnabled ? false : 'cần emulator (--dart-define=HW_EMULATOR=1)',
      timeout: const Timeout(Duration(minutes: 3)));
}
