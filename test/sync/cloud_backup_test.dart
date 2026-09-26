import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/crypto/envelope_cipher.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/seed_defaults.dart';
import 'package:vi_nha_minh/data/local/sync/sync_capture.dart';
import 'package:vi_nha_minh/data/sync/cloud_sync_engine.dart';
import 'package:vi_nha_minh/data/sync/entity_codec.dart';
import 'package:vi_nha_minh/domain/auth/cloud_session.dart';

import '../support/fake_cloud.dart';

/// P8.3 sao lưu ban đầu mã hoá + P8.4 delta: engine phía app với backend giả lập
/// đúng ngữ nghĩa functions/index.js. Hợp đồng thật: functions/test/backup.test.js
/// và test/sync/emulator_e2e_test.dart (emulator).

const _password = 'Mật khẩu sao lưu DEV 2026';
const _note = 'Tiền chợ Đà Lạt ĐẶC-BIỆT-7731';
const _amount = 98765431;
const _category = 'Hạng mục Bí-Mật-Nhà-Mình';
const _fund = 'Quỹ Du-Lịch-Phú-Quốc-5521';

Future<void> _fixture(AppDatabase db) async {
  await db.into(db.categoryRows).insert(
    CategoryRowsCompanion.insert(
      id: 'cat-bi-mat',
      name: _category,
      colorValue: 7,
      type: 'expense',
    ),
  );
  await db.into(db.fundRows).insert(
    FundRowsCompanion.insert(id: 'fund-pq', name: _fund, colorValue: 3),
  );
  await db.into(db.transactionRows).insert(_tx('tx-dac-biet', _amount, _note));
}

TransactionRowsCompanion _tx(String id, int amount, String note) =>
    TransactionRowsCompanion.insert(
      id: id,
      type: 'expense',
      categoryId: 'cat-bi-mat',
      sourceKind: 'external',
      destinationKind: 'external',
      amountMinor: amount,
      note: Value(note),
      transactionDate: DateTime(2026, 9, 1),
      createdAt: DateTime(2026, 9, 1, 8),
      clientTxId: 'client-$id',
    );

Future<Map<String, String>> _serverState(FakeDevice d) async {
  final b = await d.keys.load(d.account!);
  final cipher = await EnvelopeCipher.create(b!.bmk, b.walletId);
  final out = <String, String>{};
  for (final raw in d.cloud.entities[b.walletId]!.values) {
    final m = Map<String, Object?>.from(raw)..remove('serverRev');
    final o = await cipher.open(Envelope.fromJson(m));
    if (o.kind == 'manifest') continue;
    final body = Map<String, Object?>.from(o.body)..remove('w');
    out['${o.kind}/${o.localId}'] = EntityCodec.canonicalJson(
      EntityCodec.isTombstone(body) ? 'deleted' : body['c'],
    );
  }
  return out;
}

Future<Map<String, String>> _localState(AppDatabase db) async {
  final out = <String, String>{};
  for (final MapEntry(key: table, value: spec) in syncCapturedTables.entries) {
    for (final r in await db.customSelect('SELECT ${spec.pk} AS id FROM $table').get()) {
      final id = r.read<String>('id');
      final body = await EntityCodec.read(db, spec.kind, id);
      out['${spec.kind}/$id'] = EntityCodec.canonicalJson(body!['c']);
    }
  }
  return out;
}

Map<String, String> _live(Map<String, String> m) =>
    {...m}..removeWhere((_, v) => v == '"deleted"');

Future<int> _outbox(AppDatabase db) => SyncOutboxStore(db).count();

void main() {
  late FakeCloud cloud;
  late FakeDevice a;

  setUp(() async {
    cloud = FakeCloud();
    a = FakeDevice(cloud);
    await _fixture(a.db);
    await a.signIn('uid-owner-a');
    await a.claim();
  });
  tearDown(() => a.db.close());

  group('P8.3 — bật sao lưu + mốc nền', () {
    test('keyring chỉ chứa khoá đã bọc; mốc nền đủ mọi thực thể; COMPLETE sau checkpoint', () async {
      final total = (await _localState(a.db)).length;
      final recovery = await a.engine.enableBackup(_password);
      expect(recovery, startsWith('HW1-'));
      expect(await a.engine.backupState(), 'SEEDING');
      expect(await _outbox(a.db), total);
      final wid = await a.walletId();
      expect(cloud.wallets[wid]!['backupState'], 'SEEDING');

      final report = await a.engine.push();
      expect(await _outbox(a.db), 0);
      expect(await a.engine.backupState(), 'COMPLETE');
      expect(cloud.wallets[wid]!['backupState'], 'COMPLETE');
      expect(cloud.wallets[wid]!['checkpointRev'], report.headRev);
      expect(_live(await _serverState(a)), await _localState(a.db));
      // Thực thể thật (không chỉ fixture) + real id nằm TRONG ciphertext.
      expect((await _serverState(a)).keys, contains('transaction/tx-dac-biet'));
    });

    test('máy chủ không thấy bản rõ: số tiền, ghi chú, nhãn, id cục bộ, loại thực thể', () async {
      await a.engine.enableBackup(_password);
      await a.engine.push();
      final dump = cloud.dump();
      final members = await a.db.select(a.db.financialMemberRows).get();
      for (final secret in [
        _note, 'Đà Lạt', '$_amount', _category, _fund, 'tx-dac-biet', 'cat-bi-mat',
        'fund-pq', 'client-tx-dac-biet', for (final m in members) m.label,
        'transaction', 'category', 'financialMember', 'walletSetting', 'manifest',
        _password,
      ]) {
        expect(dump.contains(secret), isFalse, reason: 'lộ "$secret"');
      }
      // Id thành viên thật chỉ là metadata sở hữu của claim (P8.2), không nằm trong entity.
      expect(jsonEncode(cloud.entities).contains(members.first.memberId), isFalse);
    });

    test('rớt mạng ở bước enableBackup ⇒ thử lại cùng mật khẩu, cùng BMK; bật lại ⇒ từ chối', () async {
      final original = cloud.call;
      var failOnce = true;
      a.engine = CloudSyncEngine(
        db: a.db,
        session: a.session,
        transport: (op, d) async {
          if (op == 'enableBackup' && failOnce) {
            failOnce = false;
            throw const SessionFailure(false);
          }
          return original(op, d);
        },
        keyStore: a.keys,
        env: a.engine.env,
        kdf: FakeDevice.testKdf,
      );
      await expectLater(a.engine.enableBackup(_password), throwsA(isA<SessionFailure>()));
      final bmk = (await a.keys.load('uid-owner-a'))!.bmk;
      expect(await a.engine.backupState(), isNull);
      expect(await _outbox(a.db), 0, reason: 'chưa bật ⇒ chưa xếp mốc nền');
      expect(await a.engine.enableBackup(_password), isNull);
      expect((await a.keys.load('uid-owner-a'))!.bmk, bmk);
      expect(await a.engine.backupState(), 'SEEDING');
      await expectLater(
        a.engine.enableBackup(_password),
        throwsA(isA<CloudSyncException>().having((e) => e.reason, 'r', 'already-enabled')),
      );
    });

    test('KEYRING_EXISTS: sai mật khẩu ⇒ không bật; đúng mật khẩu ⇒ cùng BMK, không Recovery Key mới', () async {
      final wid = await a.walletId();
      await a.engine.enableBackup(_password);
      final bmk = (await a.keys.load('uid-owner-a'))!.bmk;
      // Mô phỏng chết trước khi ghi cục bộ: xoá trạng thái cục bộ + BMK cục bộ.
      await a.db.delete(a.db.syncState).go();
      await a.db.delete(a.db.syncOutbox).go();
      a.keys.map.clear();
      await expectLater(
        a.engine.enableBackup('một mật khẩu sai khác'),
        throwsA(anything),
      );
      expect(await a.engine.backupState(), isNull);
      a.keys.map.clear();
      final again = await a.engine.enableBackup(_password);
      expect(again, isNull, reason: 'keyring có sẵn ⇒ không phát Recovery Key mới');
      expect((await a.keys.load('uid-owner-a'))!.bmk, bmk);
      expect(cloud.keyrings.keys.where((k) => k.endsWith(wid)).length, 1);
    });
  });

  group('P8.3 — ACK, timeout, tombstone', () {
    setUp(() async {
      await a.engine.enableBackup(_password);
    });

    test('sửa trong lúc batch cũ đang bay: ACK batch cũ KHÔNG xoá việc mới', () async {
      cloud.beforeCommit = () async {
        await (a.db.update(a.db.transactionRows)
              ..where((t) => t.id.equals('tx-dac-biet')))
            .write(const TransactionRowsCompanion(note: Value('ghi chú MỚI')));
      };
      final r = await a.engine.push();
      // Batch cũ được ACK theo seq cũ; bản sửa (seq mới) còn lại và được đẩy ở batch sau.
      expect(r.batches, 2);
      expect(await _outbox(a.db), 0);
      expect((await _serverState(a))['transaction/tx-dac-biet'], contains('ghi chú MỚI'));
      expect(_live(await _serverState(a)), await _localState(a.db));
    });

    test('timeout SAU khi máy chủ commit ⇒ gửi lại cùng batchId ⇒ không ghi lần 2', () async {
      cloud.dropNextResponseAfterCommit = true;
      await expectLater(a.engine.push(), throwsA(isA<SessionFailure>()));
      final wid = await a.walletId();
      final head = cloud.wallets[wid]!['headRev'];
      expect(await _outbox(a.db), greaterThan(0), reason: 'outbox giữ nguyên');
      await a.engine.push();
      expect(cloud.wallets[wid]!['headRev'], head, reason: 'biên nhận idempotent');
      expect(await _outbox(a.db), 0);
      expect(await a.engine.backupState(), 'COMPLETE');
    });

    test('xoá ⇒ tombstone; tạo lại cùng id ⇒ upsert rev cao hơn; không hồi sinh', () async {
      await a.engine.push();
      await (a.db.delete(a.db.transactionRows)..where((t) => t.id.equals('tx-dac-biet'))).go();
      await a.engine.push();
      expect((await _serverState(a))['transaction/tx-dac-biet'], '"deleted"');
      await a.db.into(a.db.transactionRows).insert(_tx('tx-dac-biet', 5, 'tạo lại'));
      await a.engine.push();
      expect(_live(await _serverState(a)), await _localState(a.db));
      await (a.db.delete(a.db.transactionRows)..where((t) => t.id.equals('tx-dac-biet'))).go();
      await a.engine.push();
      expect((await _serverState(a))['transaction/tx-dac-biet'], '"deleted"');
    });
  });

  group('P8.4 — delta tăng dần', () {
    setUp(() async {
      await a.engine.enableBackup(_password);
      await a.engine.push();
    });

    test('1 thực thể đổi ⇒ đúng 1 envelope thực thể (+ manifest); nhiều lần sửa gộp làm 1', () async {
      final before = cloud.writes;
      for (var i = 0; i < 5; i++) {
        await (a.db.update(a.db.transactionRows)..where((t) => t.id.equals('tx-dac-biet')))
            .write(TransactionRowsCompanion(note: Value('sửa $i')));
      }
      expect(await _outbox(a.db), 1);
      final r = await a.engine.push();
      expect(cloud.writes - before, 1);
      expect(r.envelopes, 2, reason: '1 thực thể + manifest');
      await a.db.into(a.db.transactionRows).insert(_tx('tx-2', 10, 'mới'));
      await (a.db.delete(a.db.fundRows)..where((f) => f.id.equals('fund-pq'))).go();
      expect((await a.engine.push()).envelopes, 3);
      expect(_live(await _serverState(a)), await _localState(a.db));
    });

    test('rảnh: syncNow = 1 lần kéo, 0 lần ghi; không toàn bộ ví', () async {
      final writes = cloud.writes;
      final calls = a.engine.calls;
      final r = await a.engine.syncNow();
      expect(r.push.batches, 0);
      expect(r.pull.applied, 0);
      expect(cloud.writes, writes);
      expect(a.engine.calls - calls, 1);
    });

    test('offline / phiên cũ / thiết bị bị thu hồi / sai Account ⇒ outbox giữ nguyên', () async {
      await a.db.into(a.db.transactionRows).insert(_tx('tx-3', 10, 'offline'));
      cloud.offline = true;
      await expectLater(a.engine.push(), throwsA(isA<SessionFailure>()));
      expect(await _outbox(a.db), 1);
      cloud.offline = false;

      cloud.activate('uid-owner-a'); // máy khác thay phiên ⇒ máy này cũ
      await expectLater(a.engine.push(), throwsA(isA<SessionFailure>()));
      expect(await _outbox(a.db), 1);

      await a.signIn('uid-khac');
      await expectLater(
        a.engine.push(),
        throwsA(isA<CloudSyncException>().having((e) => e.reason, 'r', 'other-account')),
      );
      expect(await _outbox(a.db), 1);

      await a.signIn('uid-owner-a');
      a.account = null;
      await expectLater(a.engine.push(), throwsA(isA<SessionFailure>()));
      await a.signIn('uid-owner-a');
      await a.engine.push();
      expect(await _outbox(a.db), 0);

      await a.db.into(a.db.transactionRows).insert(_tx('tx-4', 10, 'revoked'));
      cloud.revoked.add('uid-owner-a');
      await expectLater(a.engine.push(), throwsA(isA<SessionFailure>()));
      expect(await a.keys.load('uid-owner-a'), isNull, reason: 'BMK bị xoá khi DEVICE_REVOKED');
      expect(await _outbox(a.db), 1);
      await expectLater(
        a.engine.push(),
        throwsA(isA<CloudSyncException>()),
      );
    });

    test('khởi động lại app (đóng/mở lại file DB) ⇒ outbox bền, đẩy tiếp được', () async {
      // DB file thật để mô phỏng process restart.
      final dir = await Directory.systemTemp.createTemp('vnm_p84_');
      final file = File('${dir.path}/w.sqlite');
      final c2 = FakeCloud();
      var d = FakeDevice(c2, db: AppDatabase.forTesting(NativeDatabase(file), seed: SeedProfile.fresh));
      await _fixture(d.db);
      await d.signIn('uid-r');
      await d.claim();
      await d.engine.enableBackup(_password);
      await d.db.close(); // chết trước khi đẩy
      final keys = d.keys.map;
      d = FakeDevice(c2, db: AppDatabase.forTesting(NativeDatabase(file)));
      d.keys.map.addAll(keys);
      await d.signIn('uid-r');
      expect(await _outbox(d.db), greaterThan(0));
      expect(await d.engine.backupState(), 'SEEDING');
      await d.engine.push();
      expect(await d.engine.backupState(), 'COMPLETE');
      expect(_live(await _serverState(d)), await _localState(d.db));
      await d.db.close();
      await dir.delete(recursive: true);
    });
  });
}
