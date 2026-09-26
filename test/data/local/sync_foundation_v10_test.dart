import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sq;
import 'package:vi_nha_minh/core/crypto/backup_crypto.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/db_encryption/db_key_store.dart';
import 'package:vi_nha_minh/data/local/db_encryption/sqlcipher_wallet.dart';
import 'package:vi_nha_minh/data/local/seed_defaults.dart';
import 'package:vi_nha_minh/data/local/sync/cloud_binding_store.dart';
import 'package:vi_nha_minh/data/local/sync/sync_capture.dart';
import 'package:vi_nha_minh/data/local/wallet_descriptor.dart';
import 'package:vi_nha_minh/data/repositories/local_wallet_settings_repository.dart';
import 'package:vi_nha_minh/domain/entities/cloud_binding.dart';
import 'package:vi_nha_minh/domain/entities/wallet_identity.dart';
import 'package:vi_nha_minh/presentation/providers/primary_fund_provider.dart';

import '../../support/memory_db_key_store.dart';

/// P8.1 — schema v10: cloud_binding / sync_outbox / sync_state / wallet_settings,
/// ghi nhận thay đổi bằng trigger, SeedProfile.none, quỹ chính trong DB ví.

const _v9Tables = [
  'transaction_rows',
  'category_rows',
  'status_rows',
  'fund_rows',
  'savings_asset_type_rows',
  'counterparty_rows',
  'obligation_rows',
  'wallet_meta',
  'financial_member_rows',
];
const _v10Tables = ['cloud_binding', 'sync_outbox', 'sync_state', 'wallet_settings'];

TransactionRowsCompanion _tx(String id, int amount, {String category = 'thu_nhap'}) =>
    TransactionRowsCompanion.insert(
      id: id,
      type: 'income',
      categoryId: category,
      sourceKind: 'external',
      destinationKind: 'memberAvailable',
      destinationRefId: const Value('vo'),
      amountMinor: amount,
      note: Value('ghi chú $id'),
      transactionDate: DateTime(2026, 9, 1),
      createdAt: DateTime(2026, 9, 1),
      clientTxId: 'c-$id',
    );

/// Ví v10 đủ loại dữ liệu (demo + giao dịch + đối tác/khoản vay).
Future<void> _fill(AppDatabase db, {int n = 25}) async {
  for (var i = 0; i < n; i++) {
    await db.into(db.transactionRows).insert(_tx('tx-$i', 1000 + i * 31));
  }
  await db.into(db.counterpartyRows).insert(
    CounterpartyRowsCompanion.insert(id: 'cp-1', displayName: 'Đối tác'),
  );
  await db.into(db.obligationRows).insert(
    ObligationRowsCompanion.insert(
      id: 'ob-1',
      counterpartyId: 'cp-1',
      direction: 'receivable',
    ),
  );
}

/// Hạ 1 file v10 về đúng hình dạng v9 (bỏ 4 bảng + trigger mới, user_version 9).
void _downgradeToV9(sq.Database raw) {
  for (final r in raw.select(
    "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'sync_capture_%'",
  )) {
    raw.execute('DROP TRIGGER "${r['name']}"');
  }
  for (final t in _v10Tables) {
    raw.execute('DROP TABLE $t');
  }
  // sqlite_sequence không xoá được (còn lại, rỗng) — vô hại cho migration.
  raw.execute('DELETE FROM sqlite_sequence');
  raw.userVersion = 9;
}

Map<String, String> _tableSql(sq.Database raw) => {
  for (final r in raw.select(
    "SELECT name, sql FROM sqlite_master WHERE type IN ('table','index') "
    "AND name NOT LIKE 'sqlite_%'",
  ))
    r['name'] as String: '${r['sql']}',
};

Future<List<(String, String, String)>> _outbox(AppDatabase db) async => [
  for (final r in await SyncOutboxStore(db).pending(limit: 10000))
    (r.entityKind, r.entityId, r.op),
];

Future<void> _activate(AppDatabase db) async {
  final store = CloudBindingStore(db);
  await store.beginClaim(
    accountId: 'acc-1',
    selfMemberId: 'vo',
    environment: 'dev',
    claimRequestId: 'req-1',
  );
  await store.activate(claimRequestId: 'req-1', cryptoVersion: 1, keyringRev: 1);
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vnm_v10_'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('A — migration v9 → v10', () {
    test('giữ nguyên MỌI dòng + id + walletId + schema bảng cũ; chỉ thêm bảng trống', () async {
      final file = File('${dir.path}/w.sqlite');
      final seed = AppDatabase.forTesting(NativeDatabase(file));
      await _fill(seed);
      await seed.close();

      final raw = sq.sqlite3.open(file.path);
      _downgradeToV9(raw);
      final before = captureSnapshot(raw);
      final sqlBefore = _tableSql(raw);
      raw.close();
      expect(before.count('transaction_rows'), 25);
      expect(before.tables.keys, isNot(contains('cloud_binding')));

      final db = AppDatabase.forTesting(NativeDatabase(file));
      await db.customSelect('SELECT 1').get(); // mở ⇒ migrate
      await db.close();

      final after = sq.sqlite3.open(file.path, mode: sq.OpenMode.readOnly);
      final snap = captureSnapshot(after);
      final sqlAfter = _tableSql(after);
      after.close();
      expect(snap.userVersion, 10);
      for (final t in _v9Tables) {
        expect(snap.tables[t], before.tables[t], reason: '$t phải trùng số dòng + digest');
        expect(sqlAfter[t], sqlBefore[t], reason: 'schema $t không đổi');
      }
      for (final t in _v10Tables) {
        expect(snap.count(t), 0, reason: '$t trống sau migration');
      }
      expect(snap.walletId, before.walletId);
      expect(snap.healthy, isTrue);
    });

    test('ví đã mã hoá SQLCipher: migrate xong vẫn mã hoá, dữ liệu giữ nguyên', () async {
      final keys = MemoryDbKeyStore();
      const name = 'enc.sqlite';
      final wallet = const WalletDescriptor(kind: WalletKind.local, dbFileName: name);
      var db = AppDatabase(
        seedProfile: SeedProfile.demo,
        wallet: wallet,
        keyStore: keys,
        directory: () async => dir,
      );
      await _fill(db);
      await db.close();
      final file = File('${dir.path}/$name');
      final key = keys.entries[name]!.key;

      var raw = sq.sqlite3.open(file.path);
      applySqlcipherKey(raw, key);
      _downgradeToV9(raw);
      final before = captureSnapshot(raw);
      raw.close();

      db = AppDatabase(wallet: wallet, keyStore: keys, directory: () async => dir);
      final ids = await db.customSelect('SELECT id FROM transaction_rows ORDER BY id').get();
      expect(ids, hasLength(25));
      await db.close();

      expect(probeDbFile(file), DbFileState.encrypted);
      raw = sq.sqlite3.open(file.path, mode: sq.OpenMode.readOnly);
      applySqlcipherKey(raw, key);
      final snap = captureSnapshot(raw);
      raw.close();
      expect(snap.userVersion, 10);
      for (final t in _v9Tables) {
        expect(snap.tables[t], before.tables[t], reason: t);
      }
      expect(snap.count('cloud_binding'), 0);
      expect(snap.count('sync_outbox'), 0);
      expect(snap.healthy, isTrue);
      expect(keys.creates, 1, reason: 'không bao giờ tạo khoá mới cho ví đã mã hoá');
    });
  });

  group('B — cloud_binding', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('mặc định NONE (không có dòng); DB là nguồn sự thật', () async {
      expect(await CloudBindingStore(db).read(), isNull);
      expect(await CloudBindingStore(db).state(), CloudBindingState.none);
    });

    test('claim tường minh: thành viên phải đã có; walletId lấy từ wallet_meta', () async {
      final store = CloudBindingStore(db);
      await expectLater(
        store.beginClaim(
          accountId: 'acc',
          selfMemberId: 'ai-do',
          environment: 'dev',
          claimRequestId: 'r',
        ),
        throwsA(isA<CloudBindingException>()),
      );
      expect(await store.read(), isNull);
      await store.beginClaim(
        accountId: 'acc',
        selfMemberId: 'chong',
        environment: 'dev',
        claimRequestId: 'r',
      );
      final b = (await store.read())!;
      expect(b.state, CloudBindingState.claiming);
      expect(b.walletId, (await db.select(db.walletMeta).getSingle()).walletId);
      expect(b.selfMemberId, 'chong');
      await expectLater(
        store.activate(claimRequestId: 'khac'),
        throwsA(isA<CloudBindingException>()),
      );
      await expectLater(
        store.beginClaim(
          accountId: 'acc2',
          selfMemberId: 'vo',
          environment: 'dev',
          claimRequestId: 'r2',
        ),
        throwsA(isA<CloudBindingException>()),
      );
      await store.activate(claimRequestId: 'r', cryptoVersion: 1, keyringRev: 3);
      expect((await store.read())!.state, CloudBindingState.active);
      expect((await store.read())!.keyringRev, 3);
      await expectLater(store.abandonClaim(), throwsA(isA<CloudBindingException>()));
    });

    test('abandonClaim CLAIMING → NONE', () async {
      final store = CloudBindingStore(db);
      await store.beginClaim(
        accountId: 'acc',
        selfMemberId: 'vo',
        environment: 'dev',
        claimRequestId: 'r',
      );
      await store.abandonClaim();
      expect(await store.state(), CloudBindingState.none);
    });

    test('CHECK: CLAIMING bắt buộc claim_request_id; trạng thái lạ bị từ chối', () async {
      final meta = await db.select(db.walletMeta).getSingle();
      for (final (state, req) in [('CLAIMING', null), ('BOUND', 'r')]) {
        await expectLater(
          db.customStatement(
            'INSERT INTO cloud_binding (wallet_id, account_id, self_member_id, '
            'environment, state, claim_request_id, updated_at) VALUES (?, ?, ?, ?, ?, ?, 0)',
            [meta.walletId, 'a', 'vo', 'dev', state, req],
          ),
          throwsA(anything),
        );
      }
    });
  });

  group('C/D — outbox, tombstone, gộp', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('ví chưa ACTIVE (NONE và CLAIMING): ghi tài chính KHÔNG sinh việc đồng bộ', () async {
      await _fill(db, n: 3);
      await (db.update(db.transactionRows)..where((t) => t.id.equals('tx-1')))
          .write(const TransactionRowsCompanion(amountMinor: Value(5)));
      await (db.delete(db.transactionRows)..where((t) => t.id.equals('tx-2'))).go();
      expect(await _outbox(db), isEmpty);

      await CloudBindingStore(db).beginClaim(
        accountId: 'a',
        selfMemberId: 'vo',
        environment: 'dev',
        claimRequestId: 'r',
      );
      await db.into(db.transactionRows).insert(_tx('tx-claiming', 1));
      expect(await _outbox(db), isEmpty);
    });

    test('ACTIVE: bắt insert / update / delete (tombstone); outbox không có nội dung', () async {
      await _activate(db);
      expect(await _outbox(db), isEmpty, reason: 'bản thân claim không phải dữ liệu ví');
      await db.into(db.transactionRows).insert(_tx('a', 100));
      await db.into(db.transactionRows).insert(_tx('b', 200));
      expect(await _outbox(db), [
        ('transaction', 'a', 'upsert'),
        ('transaction', 'b', 'upsert'),
      ]);
      await (db.update(db.fundRows)..where((f) => f.id.equals('an_uong')))
          .write(const FundRowsCompanion(name: Value('Quỹ ăn')));
      await (db.delete(db.transactionRows)..where((t) => t.id.equals('a'))).go();
      expect(await _outbox(db), [
        ('transaction', 'b', 'upsert'),
        ('fund', 'an_uong', 'upsert'),
        ('transaction', 'a', 'delete'),
      ]);
      final cols = (await db.customSelect('PRAGMA table_info(sync_outbox)').get())
          .map((r) => r.read<String>('name'))
          .toSet();
      expect(cols, {'seq', 'entity_kind', 'entity_id', 'op', 'changed_at', 'attempts'});
    });

    test('gộp: sửa lặp lại = 1 dòng; xoá rồi tạo lại = upsert; tạo rồi xoá = tombstone', () async {
      await _activate(db);
      await db.into(db.transactionRows).insert(_tx('x', 1));
      for (var i = 2; i < 12; i++) {
        await (db.update(db.transactionRows)..where((t) => t.id.equals('x')))
            .write(TransactionRowsCompanion(amountMinor: Value(i)));
      }
      expect(await _outbox(db), [('transaction', 'x', 'upsert')]);

      await (db.delete(db.transactionRows)..where((t) => t.id.equals('x'))).go();
      expect(await _outbox(db), [('transaction', 'x', 'delete')]);
      await db.into(db.transactionRows).insert(_tx('x', 7));
      expect(await _outbox(db), [('transaction', 'x', 'upsert')]);

      await db.into(db.transactionRows).insert(_tx('tmp', 1));
      await (db.delete(db.transactionRows)..where((t) => t.id.equals('tmp'))).go();
      expect(await _outbox(db), [
        ('transaction', 'x', 'upsert'),
        ('transaction', 'tmp', 'delete'),
      ]);
    });

    test('xác nhận theo seq không nuốt thay đổi đến sau khi đang đẩy', () async {
      await _activate(db);
      await db.into(db.transactionRows).insert(_tx('x', 1));
      final inFlight = await SyncOutboxStore(db).pending();
      await (db.update(db.transactionRows)..where((t) => t.id.equals('x')))
          .write(const TransactionRowsCompanion(amountMinor: Value(2)));
      await SyncOutboxStore(db).acknowledge(inFlight.map((r) => r.seq));
      expect(await _outbox(db), [('transaction', 'x', 'upsert')]);
      final latest = await SyncOutboxStore(db).pending();
      expect(latest.single.seq, greaterThan(inFlight.single.seq));
      await SyncOutboxStore(db).acknowledge(latest.map((r) => r.seq));
      expect(await SyncOutboxStore(db).count(), 0);
    });

    test('chính sách xung đột câu ngoài (OR IGNORE / OR REPLACE) không làm hỏng việc gộp', () async {
      await _activate(db);
      await db.into(db.fundRows).insert(
        FundRowsCompanion.insert(id: 'q', name: 'Q', colorValue: 1),
      );
      await (db.delete(db.fundRows)..where((f) => f.id.equals('q'))).go();
      // OR IGNORE bên ngoài: dòng mới được chèn ⇒ outbox phải thành upsert.
      await db.into(db.fundRows).insert(
        FundRowsCompanion.insert(id: 'q', name: 'Q2', colorValue: 1),
        mode: InsertMode.insertOrIgnore,
      );
      expect(await _outbox(db), [('fund', 'q', 'upsert')]);
      // OR REPLACE thay dòng có unique client_tx_id của id KHÁC ⇒ id cũ bị tombstone.
      await db.into(db.transactionRows).insert(_tx('old', 1));
      await db.into(db.transactionRows).insert(
        _tx('new', 2).copyWith(clientTxId: const Value('c-old')),
        mode: InsertMode.insertOrReplace,
      );
      expect(await _outbox(db), containsAll([
        ('transaction', 'old', 'delete'),
        ('transaction', 'new', 'upsert'),
      ]));
    });

    test('đổi khoá chính = tombstone id cũ + upsert id mới', () async {
      await _activate(db);
      await db.into(db.counterpartyRows).insert(
        CounterpartyRowsCompanion.insert(id: 'cp-x', displayName: 'X'),
      );
      await SyncOutboxStore(db).acknowledge(
        (await SyncOutboxStore(db).pending()).map((r) => r.seq),
      );
      await db.customStatement("UPDATE counterparty_rows SET id = 'cp-y' WHERE id = 'cp-x'");
      expect(await _outbox(db), [
        ('counterparty', 'cp-x', 'delete'),
        ('counterparty', 'cp-y', 'upsert'),
      ]);
    });

    test('ghi nội bộ restore/sync: withoutSyncCapture không sinh outbox, cờ tự tắt', () async {
      await _activate(db);
      await withoutSyncCapture(db, () async {
        await db.into(db.transactionRows).insert(_tx('restored', 9));
        await (db.update(db.fundRows)..where((f) => f.id.equals('an_uong')))
            .write(const FundRowsCompanion(name: Value('R')));
      });
      expect(await _outbox(db), isEmpty);
      await db.into(db.transactionRows).insert(_tx('user', 1));
      expect(await _outbox(db), [('transaction', 'user', 'upsert')]);

      // Lỗi giữa chừng ⇒ rollback cả dữ liệu lẫn cờ; ghi nhận vẫn hoạt động.
      await expectLater(
        withoutSyncCapture(db, () async {
          await db.into(db.transactionRows).insert(_tx('half', 1));
          throw StateError('boom');
        }),
        throwsStateError,
      );
      expect(
        await (db.select(db.transactionRows)..where((t) => t.id.equals('half'))).get(),
        isEmpty,
      );
      final flag = await db.select(db.syncState).getSingle();
      expect(flag.captureSuppressed, isFalse);
      await db.into(db.transactionRows).insert(_tx('after', 1));
      expect((await _outbox(db)).last, ('transaction', 'after', 'upsert'));
    });

    test('mốc nền khi ACTIVE: enqueueFullSnapshot xếp mọi dòng mọi bảng đồng bộ', () async {
      await _fill(db, n: 4);
      await _activate(db);
      await SyncOutboxStore(db).enqueueFullSnapshot();
      var expected = 0;
      for (final MapEntry(key: t, value: spec) in syncCapturedTables.entries) {
        final n = (await db.customSelect('SELECT COUNT(*) AS n FROM $t').getSingle())
            .read<int>('n');
        final got = (await _outbox(db)).where((e) => e.$1 == spec.kind).length;
        expect(got, n, reason: t);
        expected += n;
      }
      expect(await SyncOutboxStore(db).count(), expected);
    });
  });

  group('E — phủ bảng', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('MỌI bảng trong DB được phân loại đúng 1 lần (đồng bộ | loại trừ)', () async {
      final tables = {
        for (final r in await db.customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
        ).get())
          r.read<String>('name'),
      };
      final captured = syncCapturedTables.keys.toSet();
      final excluded = syncExcludedTables.keys.toSet();
      expect(captured.intersection(excluded), isEmpty);
      expect(tables, captured.union(excluded),
          reason: 'bảng mới phải được thêm vào syncCapturedTables hoặc syncExcludedTables');
      expect(db.allTables.map((t) => t.actualTableName).toSet(), tables);
    });

    test('mỗi bảng đồng bộ có đủ 3 trigger và khoá chính đúng cột khai báo', () async {
      final triggers = {
        for (final r in await db.customSelect(
          "SELECT name, tbl_name FROM sqlite_master WHERE type = 'trigger'",
        ).get())
          r.read<String>('name'): r.read<String>('tbl_name'),
      };
      for (final MapEntry(key: t, value: spec) in syncCapturedTables.entries) {
        for (final name in syncTriggerNames(t)) {
          expect(triggers[name], t, reason: name);
        }
        final pk = [
          for (final c in await db.customSelect('PRAGMA table_info($t)').get())
            if (c.read<int>('pk') > 0) c.read<String>('name'),
        ];
        expect(pk, [spec.pk], reason: t);
      }
      for (final t in syncExcludedTables.keys) {
        expect(triggers.values, isNot(contains(t)), reason: '$t không được ghi nhận');
      }
    });

    test('mỗi bảng đồng bộ thực sự sinh outbox; bảng loại trừ thì không', () async {
      await _fill(db, n: 1);
      await db.into(db.walletSettings).insert(
        WalletSettingsCompanion.insert(key: 'k', value: 'v'),
      );
      await _activate(db);
      for (final MapEntry(key: t, value: spec) in syncCapturedTables.entries) {
        await db.customStatement(
          'UPDATE $t SET ${spec.pk} = ${spec.pk} WHERE rowid = (SELECT MIN(rowid) FROM $t)',
        );
        expect((await _outbox(db)).any((e) => e.$1 == spec.kind), isTrue, reason: t);
      }
      final before = await SyncOutboxStore(db).count();
      await db.customStatement("UPDATE wallet_meta SET kind = kind");
      await db.customStatement('UPDATE cloud_binding SET keyring_rev = 9');
      await db.customStatement(
        'INSERT INTO sync_state (singleton, server_head_rev) VALUES (1, 5) '
        'ON CONFLICT(singleton) DO UPDATE SET server_head_rev = 5',
      );
      expect(await SyncOutboxStore(db).count(), before);
    });

    test('trạng thái chỉ-thiết-bị (App Lock, P7, Keystore, sắp xếp Explorer) không nằm trong DB ví', () {
      final all = {...syncCapturedTables.keys, ...syncExcludedTables.keys};
      for (final forbidden in ['lock', 'session', 'credential', 'keystore', 'explorer', 'sort']) {
        expect(all.where((t) => t.contains(forbidden)), isEmpty, reason: forbidden);
      }
    });
  });

  group('F — quỹ chính trong wallet_settings', () {
    late AppDatabase db;
    late LocalWalletSettingsRepository settings;
    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      settings = LocalWalletSettingsRepository(db);
    });
    tearDown(() => db.close());

    Future<PrimaryFundController> boot(Map<String, Object> prefsValues) async {
      SharedPreferences.setMockInitialValues(prefsValues);
      final prefs = await SharedPreferences.getInstance();
      final c = createWalletPrimaryFundController(
        prefs,
        WalletDescriptor.legacyLocal,
        settings,
      );
      await Future<void>.delayed(Duration.zero);
      await pumpEventQueue();
      return c;
    }

    test('di trú giữ giá trị hiệu lực từ prefs (id quỹ)', () async {
      final c = await boot({'primary_fund_id': 'du_lich'});
      expect(c.state, 'du_lich');
      expect(await settings.readRaw('primary_fund_id'), 'du_lich');
    });

    test('di trú giữ "chủ động không có quỹ chính" (chuỗi rỗng)', () async {
      final c = await boot({'primary_fund_id': ''});
      expect(c.state, isNull);
      expect(await settings.readRaw('primary_fund_id'), '');
    });

    test('chưa từng lưu ⇒ mặc định an_uong, không ghi gì vào DB', () async {
      final c = await boot({});
      expect(c.state, 'an_uong');
      expect(await settings.readRaw('primary_fund_id'), isNull);
    });

    test('ghi mới CHỈ vào DB; DB thắng prefs cũ khi mở lại', () async {
      final c = await boot({'primary_fund_id': 'du_lich'});
      await c.select('quy_moi');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('primary_fund_id'), 'du_lich', reason: 'prefs không bị ghi');
      expect(await settings.readRaw('primary_fund_id'), 'quy_moi');
      final reopened = createWalletPrimaryFundController(
        prefs,
        WalletDescriptor.legacyLocal,
        settings,
      );
      await pumpEventQueue();
      expect(reopened.state, 'quy_moi');
      await reopened.clearIfPrimary('quy_moi');
      expect(await settings.readRaw('primary_fund_id'), '');
    });

    test('đổi quỹ chính không đụng số dư/giao dịch', () async {
      await _fill(db, n: 3);
      final before = await db.customSelect('SELECT * FROM transaction_rows ORDER BY id').get();
      final c = await boot({});
      await c.select('du_lich');
      final after = await db.customSelect('SELECT * FROM transaction_rows ORDER BY id').get();
      expect(after.map((r) => r.data), before.map((r) => r.data));
    });
  });

  group('G/H — SeedProfile.none + SQLCipher', () {
    test('ví khôi phục rỗng tuyệt đối, mã hoá từ lúc tạo, không có file bản rõ', () async {
      final keys = MemoryDbKeyStore();
      const name = 'restore-target.sqlite.restoring';
      final db = AppDatabase(
        seedProfile: SeedProfile.none,
        wallet: const WalletDescriptor(kind: WalletKind.local, dbFileName: name),
        keyStore: keys,
        directory: () async => dir,
      );
      for (final t in [..._v9Tables, ..._v10Tables]) {
        final n = (await db.customSelect('SELECT COUNT(*) AS n FROM $t').getSingle())
            .read<int>('n');
        expect(n, 0, reason: '$t phải rỗng');
      }
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version'),
        10,
      );
      await db.close();

      final files = dir.listSync().whereType<File>().toList();
      expect(files, isNotEmpty);
      for (final f in files) {
        expect(probeDbFile(f), isNot(DbFileState.plaintext), reason: f.path);
        expect(String.fromCharCodes(f.readAsBytesSync()), isNot(contains('CREATE TABLE')));
      }
      expect(probeDbFile(File('${dir.path}/$name')), DbFileState.encrypted);

      // Không khoá / sai khoá ⇒ không đọc được.
      final noKey = sq.sqlite3.open('${dir.path}/$name', mode: sq.OpenMode.readOnly);
      expect(() => noKey.select('SELECT count(*) FROM sqlite_master'), throwsA(isA<sq.SqliteException>()));
      noKey.close();
      final wrong = sq.sqlite3.open('${dir.path}/$name', mode: sq.OpenMode.readOnly);
      expect(() => applySqlcipherKey(wrong, BackupCrypto.randomBytes(32)), throwsA(isA<sq.SqliteException>()));
      wrong.close();
    });

    test('ví v10 mất khoá / sai khoá ⇒ DbRecoveryRequired, file giữ nguyên, không tạo khoá mới', () async {
      final keys = MemoryDbKeyStore();
      const name = 'w.sqlite';
      const wallet = WalletDescriptor(kind: WalletKind.local, dbFileName: name);
      final db = AppDatabase(wallet: wallet, keyStore: keys, directory: () async => dir);
      await db.customSelect('SELECT 1').get();
      await db.close();
      final file = File('${dir.path}/$name');
      final bytes = file.readAsBytesSync();

      final missing = MemoryDbKeyStore();
      await expectLater(
        WalletDbEncryption(missing).prepare(file, name),
        throwsA(isA<DbRecoveryRequired>()),
      );
      final wrongKeys = MemoryDbKeyStore()
        ..entries[name] = DbKeyEntry(BackupCrypto.randomBytes(32), null, 1);
      await expectLater(
        WalletDbEncryption(wrongKeys).prepare(file, name),
        throwsA(isA<DbRecoveryRequired>()),
      );
      expect(missing.creates, 0);
      expect(file.readAsBytesSync(), bytes);
    });

    test('tạo ví mới bình thường vẫn seed như cũ (fresh)', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory(), seed: SeedProfile.fresh);
      expect(await db.select(db.categoryRows).get(), isNotEmpty);
      expect(await db.select(db.financialMemberRows).get(), hasLength(2));
      expect(await db.select(db.walletMeta).get(), hasLength(1));
      expect(await db.select(db.walletSettings).get(), isEmpty);
      expect(await db.select(db.cloudBinding).get(), isEmpty);
      await db.close();
    });
  });
}
