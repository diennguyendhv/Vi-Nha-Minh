import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/sync/sync_capture.dart';
import 'package:vi_nha_minh/data/sync/sync_worker.dart';

import '../support/fake_cloud.dart';

/// P8.4 — worker nền: debounce + gộp, lùi luỹ thừa khi mất mạng, dừng im khi điều kiện
/// chưa đủ, không thăm dò khi rảnh, không vòng lặp đọc/ghi do chính lượt kéo gây ra.

TransactionRowsCompanion _tx(String id) => TransactionRowsCompanion.insert(
  id: id,
  type: 'income',
  categoryId: 'tiet_kiem',
  sourceKind: 'external',
  destinationKind: 'external',
  amountMinor: 1000,
  transactionDate: DateTime(2026, 9, 5),
  createdAt: DateTime(2026, 9, 5),
  clientTxId: 'c-$id',
);

void main() {
  late FakeCloud cloud;
  late FakeDevice a;
  late SyncWorker worker;

  setUp(() async {
    cloud = FakeCloud();
    a = FakeDevice(cloud);
    await a.signIn('uid-w');
    await a.claim();
    await a.engine.enableBackup('Mật khẩu sao lưu worker');
    worker = SyncWorker(
      engine: a.engine,
      db: a.db,
      debounce: const Duration(milliseconds: 40),
      baseBackoff: const Duration(milliseconds: 30),
      maxBackoff: const Duration(milliseconds: 200),
    );
  });
  tearDown(() async {
    await worker.dispose();
    await a.db.close();
  });

  Future<void> settle([int ms = 400]) => Future<void>.delayed(Duration(milliseconds: ms));

  test('start ⇒ đẩy mốc nền; nhiều ghi liên tiếp ⇒ gộp thành 1 batch; rảnh ⇒ 0 lời gọi', () async {
    worker.start();
    await settle();
    expect(await SyncOutboxStore(a.db).count(), 0);
    expect(await a.engine.backupState(), 'COMPLETE');
    final writes = cloud.writes;
    for (var i = 0; i < 6; i++) {
      await a.db.into(a.db.transactionRows).insert(_tx('w-$i'));
    }
    await settle();
    expect(cloud.writes - writes, 1, reason: 'debounce gộp 6 ghi');
    expect(await SyncOutboxStore(a.db).count(), 0);
    final calls = a.engine.calls;
    await settle(500);
    expect(a.engine.calls, calls, reason: 'không thăm dò khi rảnh');
  });

  test('mất mạng ⇒ lùi luỹ thừa, outbox giữ nguyên; có mạng lại ⇒ đẩy hết', () async {
    cloud.offline = true;
    worker.start();
    await settle(300);
    expect(worker.lastOutcome, SyncRunOutcome.retrying);
    expect(worker.runs, greaterThan(1));
    expect(await SyncOutboxStore(a.db).count(), greaterThan(0));
    expect(worker.backoffFor(1), const Duration(milliseconds: 30));
    expect(worker.backoffFor(3), const Duration(milliseconds: 120));
    expect(worker.backoffFor(20), const Duration(milliseconds: 200));
    cloud.offline = false;
    await settle(500);
    expect(worker.lastOutcome, SyncRunOutcome.synced);
    expect(await SyncOutboxStore(a.db).count(), 0);
  });

  test('đăng xuất / sai Account / phiên cũ ⇒ dừng im (không thử lại), outbox giữ nguyên', () async {
    a.account = null;
    worker.start();
    await settle(300);
    expect(worker.lastOutcome, SyncRunOutcome.blocked);
    expect(worker.runs, 1);
    await a.signIn('uid-khac');
    expect(await worker.runOnce(), SyncRunOutcome.blocked);
    await a.signIn('uid-w');
    cloud.activate('uid-w'); // máy khác thay phiên ⇒ máy này cũ
    expect(await worker.runOnce(), SyncRunOutcome.blocked);
    expect(await SyncOutboxStore(a.db).count(), greaterThan(0));
    await a.signIn('uid-w');
    expect(await worker.runOnce(), SyncRunOutcome.synced);
    expect(await SyncOutboxStore(a.db).count(), 0);
  });

  test('rảnh thật: start/resume với outbox rỗng ⇒ 0 lời gọi mạng; requestPull ⇒ đúng 1', () async {
    await a.engine.push();
    final log = cloud.log.length;
    worker.start();
    await settle();
    worker.start(); // resume lần 2
    await settle();
    expect(cloud.log.length, log, reason: 'mở app/rảnh không gọi backend');
    expect(worker.runs, 0);
    worker.requestPull();
    await settle();
    expect(cloud.log.length - log, 1);
    expect(cloud.log.last, startsWith('getEncryptedChanges'));
    await settle();
    expect(cloud.log.length - log, 1, reason: 'không vòng lặp');
  });

  test('sửa trong lúc batch đang bay ⇒ batch sau đẩy bản mới; không batch trùng', () async {
    await a.engine.push();
    await a.db.into(a.db.transactionRows).insert(_tx('fly'));
    cloud.beforeCommit = () async {
      await (a.db.update(a.db.transactionRows)..where((t) => t.id.equals('fly')))
          .write(const TransactionRowsCompanion(amountMinor: Value(2222)));
    };
    final writes = cloud.writes;
    worker.start();
    await settle(600);
    expect(await SyncOutboxStore(a.db).count(), 0);
    expect(cloud.writes - writes, 2);
    final wid = await a.walletId();
    expect(cloud.receipts[wid]!.length, cloud.writes, reason: 'mỗi lần ghi 1 biên nhận, không trùng');
  });

  test('xoá rồi tạo lại cùng id trong 1 cửa sổ debounce ⇒ 1 batch upsert', () async {
    await a.engine.push();
    worker.start();
    await settle();
    final writes = cloud.writes;
    await a.db.into(a.db.transactionRows).insert(_tx('re'));
    await (a.db.delete(a.db.transactionRows)..where((t) => t.id.equals('re'))).go();
    await a.db.into(a.db.transactionRows).insert(_tx('re'));
    await settle();
    expect(cloud.writes - writes, 1);
    expect(await SyncOutboxStore(a.db).count(), 0);
  });

  test('khởi động lại (worker + engine mới trên cùng DB) ⇒ tiếp tục outbox còn lại', () async {
    cloud.offline = true;
    worker.start();
    await settle(150);
    await worker.dispose();
    expect(await SyncOutboxStore(a.db).count(), greaterThan(0));
    cloud.offline = false;
    a.rebuildEngine();
    worker = SyncWorker(engine: a.engine, db: a.db, debounce: const Duration(milliseconds: 40));
    worker.start();
    await settle();
    expect(await SyncOutboxStore(a.db).count(), 0);
    expect(await a.engine.backupState(), 'COMPLETE');
  });
}
