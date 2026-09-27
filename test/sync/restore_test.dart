import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/config/app_environment.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/seed_defaults.dart';
import 'package:vi_nha_minh/data/local/sync/sync_capture.dart';
import 'package:vi_nha_minh/data/local/wallet_registry.dart';
import 'package:vi_nha_minh/data/sync/cloud_sync_engine.dart';
import 'package:vi_nha_minh/data/sync/entity_codec.dart';
import 'package:vi_nha_minh/domain/auth/cloud_session.dart';
import 'package:vi_nha_minh/data/sync/restore_engine.dart';
import 'package:vi_nha_minh/domain/entities/wallet_identity.dart';

import '../support/fake_cloud.dart';
import '../support/temp_restore_storage.dart';

/// P8.5 — khôi phục zero-knowledge vào ví MỚI; lỗi ở mọi giai đoạn không để lại gì
/// và không đụng ví hiện tại.

const _password = 'Mật khẩu sao lưu DEV 2026';

TransactionRowsCompanion _tx(String id, int amount, {String? member}) =>
    TransactionRowsCompanion.insert(
      id: id,
      type: 'income',
      categoryId: 'cat-thu',
      sourceKind: 'external',
      destinationKind: 'memberAvailable',
      destinationRefId: Value(member),
      amountMinor: amount,
      note: Value('Ghi chú $id — Đà Nẵng'),
      transactionDate: DateTime(2026, 9, 2),
      createdAt: DateTime(2026, 9, 2, 9),
      clientTxId: 'client-$id',
    );

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

String _hashDir(Directory d) {
  final files = d.listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));
  return [for (final f in files) '${f.uri.pathSegments.last}:${base64.encode(f.readAsBytesSync())}']
      .join('|');
}

void main() {
  late FakeCloud cloud;
  late FakeDevice a;
  late String recovery;
  late String walletId;
  late Directory dir;

  setUp(() async {
    cloud = FakeCloud();
    a = FakeDevice(cloud);
    await a.db.into(a.db.categoryRows).insert(
      CategoryRowsCompanion.insert(id: 'cat-thu', name: 'Lương Bí-Mật', colorValue: 1, type: 'income'),
    );
    final members = await a.db.select(a.db.financialMemberRows).get();
    for (var i = 0; i < 30; i++) {
      await a.db.into(a.db.transactionRows).insert(_tx('tx-$i', 1000 * (i + 1), member: members[i % 2].memberId));
    }
    await a.db.into(a.db.statusRows).insert(
      StatusRowsCompanion.insert(id: 'st-1', categoryId: 'cat-thu', name: 'Đã nhận', sortOrder: 0),
    );
    await a.signIn('uid-a');
    await a.claim();
    recovery = (await a.engine.enableBackup(_password))!;
    await a.engine.push();
    // Delta sau mốc nền: sửa, xoá, thêm.
    await (a.db.update(a.db.transactionRows)..where((t) => t.id.equals('tx-3')))
        .write(const TransactionRowsCompanion(statusId: Value('st-1')));
    await (a.db.delete(a.db.transactionRows)..where((t) => t.id.equals('tx-7'))).go();
    await a.db.into(a.db.transactionRows).insert(_tx('tx-new', 777, member: members[0].memberId));
    await a.engine.push();
    walletId = await a.walletId();
    dir = await Directory.systemTemp.createTemp('vnm_restore_');
  });
  tearDown(() async {
    await a.db.close();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  /// Máy MỚI sạch của cùng Account (phiên P7.1 mới ⇒ máy A thành cũ).
  Future<(FakeDevice, RestoreEngine, WalletRegistry, TempRestoreStorage)> newDevice({
    bool Function(String)? failAt,
    String uid = 'uid-a',
  }) async {
    final c = FakeDevice(cloud, installation: '22222222-2222-4222-8222-222222222222');
    await c.signIn(uid);
    final registry = WalletRegistry.inMemory();
    final storage = TempRestoreStorage(dir);
    final engine = RestoreEngine(
      session: c.session,
      transport: cloud.call,
      keyStore: c.keys,
      registry: registry,
      storage: storage,
      env: AppEnvironment.dev,
      failAt: failAt,
    );
    return (c, engine, registry, storage);
  }

  test('Mật khẩu sao lưu ⇒ ví mới giống hệt từng dòng; id/clientTxId/memberId/walletId giữ nguyên', () async {
    final (c, engine, registry, _) = await newDevice();
    final result = await engine.restore(walletId: walletId, password: _password);
    expect(result.walletId, walletId);
    expect(result.checkpointVerified, isTrue);
    final restored = AppDatabase.forTesting(NativeDatabase(File('${dir.path}/${result.dbFileName}')));
    expect(await _state(restored), await _state(a.db));
    expect((await restored.select(restored.walletMeta).getSingle()).walletId, walletId);
    expect((await _state(restored)).keys, isNot(contains('transaction/tx-7')), reason: 'không hồi sinh');
    final binding = await restored.select(restored.cloudBinding).getSingle();
    expect(binding.state, 'ACTIVE');
    expect(binding.selfMemberId, (await a.db.select(a.db.cloudBinding).getSingle()).selfMemberId);
    expect(await SyncOutboxStore(restored).count(), 0);
    final entry = registry.byWalletId(walletId)!;
    expect(entry.kind, WalletKind.personal);
    expect(entry.boundAccountId, 'uid-a');
    expect(Directory(dir.path).listSync().map((f) => f.uri.pathSegments.last),
        isNot(contains(endsWith('.restoring'))));
    // Máy mới tiếp tục sao lưu từ đúng head: không có gì để kéo/đẩy lại.
    c.db = restored;
    c.rebuildEngine();
    final r = await c.engine.syncNow(pullFirst: true);
    expect(r.pull!.applied, 0);
    expect(r.push.batches, 0);
    await restored.into(restored.transactionRows).insert(_tx('tx-c', 5));
    expect((await c.engine.push()).envelopes, 2);
    await restored.close();
  });

  test('Recovery Key ⇒ cùng kết quả', () async {
    final (_, engine, _, _) = await newDevice();
    final result = await engine.restore(walletId: walletId, recoveryKey: recovery);
    final restored = AppDatabase.forTesting(NativeDatabase(File('${dir.path}/${result.dbFileName}')));
    expect(await _state(restored), await _state(a.db));
    await restored.close();
  });

  test('sai bí mật / sai Account / ví đã có trên máy ⇒ từ chối, không tạo file', () async {
    final (_, engine, registry, _) = await newDevice();
    await expectLater(
      engine.restore(walletId: walletId, password: 'mật khẩu sai hoàn toàn'),
      throwsA(isA<RestoreException>().having((e) => e.reason, 'r', 'wrong-secret')),
    );
    await expectLater(
      engine.restore(walletId: walletId, recoveryKey: 'HW1-SAI'),
      throwsA(isA<RestoreException>()),
    );
    expect(dir.listSync(), isEmpty);
    final (_, other, _, _) = await newDevice(uid: 'uid-x');
    await expectLater(other.restore(walletId: walletId, password: _password), throwsA(anything));
    expect(dir.listSync(), isEmpty);
    await registry.register(WalletRegistryEntry(
      walletId: walletId, kind: WalletKind.personal, dbFileName: 'x.sqlite',
      createdAt: DateTime(2026), boundAccountId: 'uid-a'));
    await expectLater(
      engine.restore(walletId: walletId, password: _password),
      throwsA(isA<RestoreException>().having((e) => e.reason, 'r', 'wallet-already-present')),
    );
  });

  for (final stage in ['download', 'create', 'apply', 'verify', 'activate']) {
    test('lỗi ở giai đoạn $stage ⇒ không file nào còn lại, ví hiện tại nguyên byte, không kích hoạt', () async {
      // "Ví hiện tại" trên máy: 1 file DB khác trong cùng thư mục.
      final current = File('${dir.path}/vi_nha_minh.sqlite');
      final cur = AppDatabase.forTesting(NativeDatabase(current), seed: SeedProfile.fresh);
      await cur.select(cur.walletMeta).get();
      await cur.close();
      final before = _hashDir(dir);
      final (c, engine, registry, _) = await newDevice(failAt: (s) => s == stage);
      await expectLater(
        engine.restore(walletId: walletId, password: _password),
        throwsA(isA<RestoreException>().having((e) => e.stage, 's', stage)),
      );
      expect(_hashDir(dir), before);
      expect(registry.byWalletId(walletId), isNull);
      expect(await c.keys.load('uid-a'), isNull);
      // Thử lại không lỗi ⇒ thành công.
      final ok = await RestoreEngine(
        session: c.session, transport: cloud.call, keyStore: c.keys,
        registry: registry, storage: TempRestoreStorage(dir), env: AppEnvironment.dev,
      ).restore(walletId: walletId, password: _password);
      expect(ok.walletId, walletId);
    });
  }

  test('ciphertext bị sửa trên máy chủ ⇒ bad-envelope, không file', () async {
    final store = cloud.entities[walletId]!;
    final victim = store.values.first;
    final c = base64.decode(victim['c']! as String);
    c[5] ^= 0x01;
    victim['c'] = base64.encode(c);
    final (_, engine, _, _) = await newDevice();
    await expectLater(
      engine.restore(walletId: walletId, password: _password),
      throwsA(isA<RestoreException>().having((e) => e.reason, 'r', 'bad-envelope')),
    );
    expect(dir.listSync(), isEmpty);
  });

  test('checkpoint cũ (lần đẩy cuối bị ngắt) ⇒ từ chối trừ khi cho phép tường minh', () async {
    // Nhiều thay đổi hơn 1 batch; batch đầu (không manifest) commit rồi mất mạng.
    for (var i = 0; i < 5; i++) {
      await a.db.into(a.db.transactionRows).insert(_tx('tx-more-$i', 9));
    }
    var n = 0;
    final small = CloudSyncEngine(
      db: a.db,
      session: a.session,
      transport: (op, d) async {
        if (op == 'putEncryptedBatch' && ++n > 1) throw const SessionFailure(false);
        return cloud.call(op, d);
      },
      keyStore: a.keys,
      env: AppEnvironment.dev,
      kdf: FakeDevice.testKdf,
      batchSize: 2,
    );
    await expectLater(small.push(), throwsA(isA<SessionFailure>()));
    final (_, engine, _, _) = await newDevice();
    await expectLater(
      engine.restore(walletId: walletId, password: _password),
      throwsA(isA<RestoreException>().having((e) => e.reason, 'r', 'manifest-mismatch')),
    );
    expect(dir.listSync(), isEmpty);
    final r = await engine.restore(walletId: walletId, password: _password, allowStaleCheckpoint: true);
    expect(r.checkpointVerified, isFalse);
  });
}
