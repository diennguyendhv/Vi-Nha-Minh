import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/data/import/import_scheduler.dart';
import 'package:vi_nha_minh/data/import/legacy_import_plan.dart';
import 'package:vi_nha_minh/data/import/legacy_ledger_importer.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/seed_defaults.dart';
import 'package:vi_nha_minh/data/repositories/local_transaction_repository.dart';
import 'package:vi_nha_minh/domain/engine/financial_engine.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/errors/domain_exceptions.dart';

/// Importer + scheduler với kế hoạch TỔNG HỢP (không có dữ liệu thật), DB trong bộ
/// nhớ, seed người dùng mới — đi qua repository thật.

Map<String, dynamic> _tx(
  String key, {
  required String type,
  String? kind,
  required String category,
  required String srcKind,
  String? srcRef,
  required String dstKind,
  String? dstRef,
  required int amount,
  required String date,
  String? status,
  String note = '',
  int row = 1,
}) => {
  'id': 'id-$key',
  'clientTxId': 'c-$key',
  'role': 'src',
  'sourceRow': row,
  'type': type,
  'transferKind': kind,
  'categoryId': category,
  'sourceKind': srcKind,
  'sourceRefId': srcRef,
  'destinationKind': dstKind,
  'destinationRefId': dstRef,
  'amountMinor': amount,
  'date': date,
  'note': note,
  'statusId': status,
};

Map<String, dynamic> _plan(List<Map<String, dynamic>> txs) => {
  'importerVersion': 'test',
  'workbookSha256': 'test-sha',
  'requiredSystemCategories': ['chuyen_tien_thanh_vien', 'tiet_kiem'],
  'requiredSavingsAssets': ['savings_bank'],
  'categories': [
    {
      'id': 'imp_thu', 'name': 'Thu', 'type': 'income', 'excludeFromTotals': false,
      'groupKey': null, 'colorValue': 0xFF13805F, 'statuses': <dynamic>[],
    },
    {
      'id': 'imp_chi', 'name': 'Chi', 'type': 'expense', 'excludeFromTotals': false,
      'groupKey': null, 'colorValue': 0xFFC14F7A,
      'statuses': [
        {'id': 'imp_st_chi_0', 'name': 'Đã gửi', 'sortOrder': 0},
      ],
    },
    {
      'id': 'imp_chi2', 'name': 'Chi 2', 'type': 'expense', 'excludeFromTotals': false,
      'groupKey': null, 'colorValue': 0xFF3E6FB0,
      'statuses': [
        {'id': 'imp_st_chi2_0', 'name': 'Đã gửi', 'sortOrder': 0},
      ],
    },
  ],
  'transactions': txs,
};

Map<String, dynamic> _sample() => _plan([
  // Chi 10/01 sớm hơn khoản thu 20/01 → thứ tự ngày sẽ làm âm; phải hoãn.
  _tx('spend', type: 'expense', category: 'imp_chi', srcKind: 'memberAvailable', srcRef: 'vo', dstKind: 'external', amount: 300000, date: '2026-01-10T09:00:00.000', status: 'imp_st_chi_0', row: 2),
  _tx('inc', type: 'income', category: 'imp_thu', srcKind: 'external', dstKind: 'memberAvailable', dstRef: 'vo', amount: 1000000, date: '2026-01-20T09:00:00.000', row: 3),
  _tx('save', type: 'transfer', kind: 'savingsTopup', category: 'tiet_kiem', srcKind: 'memberAvailable', srcRef: 'vo', dstKind: 'memberSavingsAsset', dstRef: 'savings_unallocated|vo', amount: 200000, date: '2026-01-21T09:00:00.000', row: 4),
  _tx('move', type: 'transfer', kind: 'memberToMember', category: 'chuyen_tien_thanh_vien', srcKind: 'memberAvailable', srcRef: 'vo', dstKind: 'memberAvailable', dstRef: 'chong', amount: 100000, date: '2026-01-22T09:00:00.000', row: 5),
  _tx('bank', type: 'transfer', kind: 'savingsConvert', category: 'tiet_kiem', srcKind: 'memberSavingsAsset', srcRef: 'savings_unallocated|vo', dstKind: 'memberSavingsAsset', dstRef: 'savings_bank|vo', amount: 150000, date: '2026-01-23T00:00:00.000', row: 0),
]);

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory(), seed: SeedProfile.fresh);
  });
  tearDown(() async => db.close());

  Future<int> txCount() async => (await db.select(db.transactionRows).get()).length;

  group('Scheduler — thứ tự GHI an toàn, ngày giữ nguyên', () {
    test('Thứ tự ngày sẽ làm âm → hoãn khoản chi; ngày không đổi; không pool nào âm', () {
      final plan = ImportPlan.fromJson(_sample());
      final r = scheduleImport(plan.transactions);
      expect(r.total, 5);
      expect(r.order.map((t) => t.sourceRow), isNot(orderedEquals([2, 3, 4, 5, 0])));
      expect(r.order.first.id, 'id-inc', reason: 'khoản thu phải ghi trước khoản chi đã hoãn');
      expect(r.skipAheadPlacements, greaterThan(0));
      expect(r.delayedTransactions, 1);
      expect(r.minBalances.values.every((v) => v >= 0), isTrue);
      expect({for (final t in r.order) t.id: t.date}, {for (final t in plan.transactions) t.id: t.date}, reason: 'transactionDate giữ nguyên');
    });

    test('Tất định: cùng đầu vào (kể cả xáo trộn) → cùng thứ tự', () {
      final txs = ImportPlan.fromJson(_sample()).transactions;
      final a = scheduleImport(txs).order.map((t) => t.id).toList();
      final b = scheduleImport(txs.reversed.toList()).order.map((t) => t.id).toList();
      expect(a, b);
    });

    test('Không có thứ tự an toàn (chi vượt mọi khoản thu) → dừng, StateError', () {
      final plan = ImportPlan.fromJson(_plan([
        _tx('spend', type: 'expense', category: 'imp_chi', srcKind: 'memberAvailable', srcRef: 'vo', dstKind: 'external', amount: 500, date: '2026-01-01T00:00:00.000'),
      ]));
      expect(() => scheduleImport(plan.transactions), throwsStateError);
    });
  });

  group('Importer — repository thật', () {
    test('Tạo danh mục/trạng thái/giao dịch; số dư đúng; danh mục hệ thống KHÔNG bị tạo lại; chuyển/tiết kiệm không có trạng thái', () async {
      final plan = ImportPlan.fromJson(_sample());
      final r = await LegacyLedgerImporter(db).run(plan);
      expect((r.categoriesCreated, r.statusesCreated, r.transactionsCreated, r.transactionsExisting), (3, 2, 5, 0));
      expect(await txCount(), 5);

      final txs = await LocalTransactionRepository(db).watchTransactions().first;
      final bal = computeAllPoolBalances(txs);
      expect(poolBalance(bal, PoolKind.memberAvailable, 'vo'), 1000000 - 300000 - 200000 - 100000);
      expect(poolBalance(bal, PoolKind.memberAvailable, 'chong'), 100000);
      expect(poolBalance(bal, PoolKind.memberSavingsAsset, 'savings_unallocated|vo'), 50000);
      expect(poolBalance(bal, PoolKind.memberSavingsAsset, 'savings_bank|vo'), 150000);
      expect(txs.firstWhere((t) => t.clientTxId == 'c-spend').statusId, 'imp_st_chi_0');
      expect(txs.where((t) => t.categoryId == 'tiet_kiem' || t.categoryId == 'chuyen_tien_thanh_vien').every((t) => t.statusId == null), isTrue);
      expect(txs.firstWhere((t) => t.clientTxId == 'c-spend').transactionDate, DateTime(2026, 1, 10, 9), reason: 'ngày nguồn giữ nguyên');
    });

    test('Idempotent: chạy lần 2 không tạo thêm gì', () async {
      final plan = ImportPlan.fromJson(_sample());
      final importer = LegacyLedgerImporter(db);
      await importer.run(plan);
      final second = await importer.run(plan);
      expect((second.categoriesCreated, second.statusesCreated, second.transactionsCreated, second.transactionsExisting), (0, 0, 0, 5));
      expect(await txCount(), 5);
      expect((await db.select(db.statusRows).get()).where((s) => s.id.startsWith('imp_')).length, 2);
    });

    test('Cùng danh tính nhưng payload khác → ClientTxIdConflictException, KHÔNG ghi đè, rollback toàn bộ lần chạy', () async {
      await LegacyLedgerImporter(db).run(ImportPlan.fromJson(_sample()));
      final changed = _sample();
      final txs = (changed['transactions'] as List).cast<Map<String, dynamic>>();
      txs.firstWhere((t) => t['id'] == 'id-inc')['amountMinor'] = 1000001;
      await expectLater(
        LegacyLedgerImporter(db).run(ImportPlan.fromJson(changed)),
        throwsA(isA<ClientTxIdConflictException>()),
      );
      final rows = await db.select(db.transactionRows).get();
      expect(rows.length, 5);
      expect(rows.firstWhere((r) => r.clientTxId == 'c-inc').amountMinor, 1000000);
    });

    test('Nguyên tử: 1 giao dịch lỗi ở CUỐI → rollback TOÀN BỘ (không danh mục, không giao dịch)', () async {
      final bad = _sample();
      (bad['transactions'] as List).add(_tx('bad', type: 'expense', category: 'khong_ton_tai', srcKind: 'memberAvailable', srcRef: 'chong', dstKind: 'external', amount: 1000, date: '2026-02-01T00:00:00.000', row: 99));
      await expectLater(LegacyLedgerImporter(db).run(ImportPlan.fromJson(bad)), throwsA(anything));
      expect(await txCount(), 0);
      expect((await db.select(db.categoryRows).get()).where((c) => c.id.startsWith('imp_')), isEmpty);
      expect((await db.select(db.statusRows).get()).where((s) => s.id.startsWith('imp_')), isEmpty);
    });

    test('Thiếu danh mục hệ thống / loại tiết kiệm bắt buộc → dừng, không ghi gì', () async {
      final missingCat = _sample()..['requiredSystemCategories'] = ['khong_co'];
      await expectLater(LegacyLedgerImporter(db).run(ImportPlan.fromJson(missingCat)), throwsA(isA<LegacyImportConflictException>()));
      final missingAsset = _sample()..['requiredSavingsAssets'] = ['khong_co'];
      await expectLater(LegacyLedgerImporter(db).run(ImportPlan.fromJson(missingAsset)), throwsA(isA<LegacyImportConflictException>()));
      expect(await txCount(), 0);
    });

    test('Danh mục đã có nhưng nội dung khác kế hoạch → xung đột, không ghi đè', () async {
      await LegacyLedgerImporter(db).run(ImportPlan.fromJson(_sample()));
      final changed = _sample();
      (changed['categories'] as List).cast<Map<String, dynamic>>().first['name'] = 'Tên khác';
      await expectLater(LegacyLedgerImporter(db).run(ImportPlan.fromJson(changed)), throwsA(isA<LegacyImportConflictException>()));
    });

    test('Không pool bảo vệ nào âm SAU khi nhập; kiểm tra của repository vẫn hoạt động (chi vượt số dư bị từ chối)', () async {
      await LegacyLedgerImporter(db).run(ImportPlan.fromJson(_sample()));
      final repo = LocalTransactionRepository(db);
      final txs = await repo.watchTransactions().first;
      final bal = computeAllPoolBalances(txs);
      expect(bal.entries.where((e) => e.key.$1 != PoolKind.external && e.value < 0), isEmpty);
      final overdraw = ImportPlan.fromJson(_plan([
        _tx('over', type: 'expense', category: 'imp_thu', srcKind: 'memberAvailable', srcRef: 'chong', dstKind: 'external', amount: 999999999, date: '2026-03-01T00:00:00.000'),
      ])).transactions.single.toDomain();
      await expectLater(repo.addTransaction(overdraw), throwsA(isA<InsufficientBalanceException>()));
    });
  });
}
