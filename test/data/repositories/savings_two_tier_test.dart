import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/constants/default_savings_asset_types.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/repositories/local_savings_asset_type_repository.dart';
import 'package:vi_nha_minh/data/repositories/local_transaction_repository.dart';
import 'package:vi_nha_minh/domain/engine/financial_engine.dart';
import 'package:vi_nha_minh/domain/entities/family_member.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/savings_asset_type.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart' as domain;
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/entities/transfer_kind.dart';
import 'package:vi_nha_minh/domain/errors/domain_exceptions.dart';
import 'package:vi_nha_minh/domain/usecases/compute_grouped_totals.dart';
import 'package:vi_nha_minh/domain/usecases/compute_pool_balance.dart';
import 'package:vi_nha_minh/core/constants/default_categories.dart';

/// Savings 2 tầng (Option A2) + toàn vẹn: trên DB Drift thật (không fake).
/// Tầng 1: Khả dụng ↔ Tiết kiệm (mặc định vào "Chưa phân bổ"); tầng 2: phân bổ
/// giữa các loại. Không đổi `applyEffect`, không đổi schema.
void main() {
  late AppDatabase db;
  late LocalTransactionRepository txRepo;
  late LocalSavingsAssetTypeRepository assetRepo;
  var seq = 0;

  const unalloc = SystemSavingsAssets.unallocatedId;
  const bank = DefaultSavingsAssetTypes.bankId;
  const gold = DefaultSavingsAssetTypes.goldId;
  const stocks = DefaultSavingsAssetTypes.stocksId;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    txRepo = LocalTransactionRepository(db);
    assetRepo = LocalSavingsAssetTypeRepository(db, txRepo);
    seq = 0;
  });

  tearDown(() async => db.close());

  String ref(String asset, FamilyMember m) => savingsAssetRefId(asset, m);

  domain.Transaction tx({
    required String id,
    required TransactionType type,
    TransferKind? kind,
    String category = 'tiet_kiem',
    required PoolKind from,
    String? fromRef,
    required PoolKind to,
    String? toRef,
    required int amount,
  }) {
    seq++;
    return domain.Transaction(
      id: id,
      type: type,
      transferKind: kind,
      categoryId: category,
      sourceKind: from,
      sourceRefId: fromRef,
      destinationKind: to,
      destinationRefId: toRef,
      amountMinor: amount,
      transactionDate: DateTime(2026, 9, 1),
      createdAt: DateTime(2026, 9, 1),
      clientTxId: 'c-$seq',
    );
  }

  domain.Transaction income(String id, FamilyMember m, int amount) => tx(
    id: id,
    type: TransactionType.income,
    category: 'thu_nhap',
    from: PoolKind.external,
    to: PoolKind.memberAvailable,
    toRef: m.name,
    amount: amount,
  );

  /// Thêm vào tiết kiệm: Khả dụng(m) → Chưa phân bổ(m).
  domain.Transaction topup(String id, FamilyMember m, int amount) => tx(
    id: id,
    type: TransactionType.transfer,
    kind: TransferKind.savingsTopup,
    from: PoolKind.memberAvailable,
    fromRef: m.name,
    to: PoolKind.memberSavingsAsset,
    toRef: ref(unalloc, m),
    amount: amount,
  );

  domain.Transaction convert(
    String id,
    FamilyMember m,
    String fromAsset,
    String toAsset,
    int amount,
  ) => tx(
    id: id,
    type: TransactionType.transfer,
    kind: TransferKind.savingsConvert,
    from: PoolKind.memberSavingsAsset,
    fromRef: ref(fromAsset, m),
    to: PoolKind.memberSavingsAsset,
    toRef: ref(toAsset, m),
    amount: amount,
  );

  domain.Transaction withdraw(String id, FamilyMember m, String asset, int amount) => tx(
    id: id,
    type: TransactionType.transfer,
    kind: TransferKind.savingsWithdraw,
    from: PoolKind.memberSavingsAsset,
    fromRef: ref(asset, m),
    to: PoolKind.memberAvailable,
    toRef: m.name,
    amount: amount,
  );

  Future<List<domain.Transaction>> all() => txRepo.watchTransactions().first;

  Future<int> avail(FamilyMember m) async =>
      computeMemberAvailableBalance(m, await all());
  Future<int> savings(FamilyMember m) async =>
      computeMemberSavingsTotal(m, await all());
  Future<int> asset(String a, FamilyMember m) async =>
      computeMemberSavingsByAssetType(a, m, await all());
  Future<int> totalAssets() async {
    // Total Assets = tổng mọi pool không phải external.
    return computeAllPoolBalances(await all()).values.fold<int>(0, (a, b) => a + b);
  }

  Future<int> rows() async => (await db.select(db.transactionRows).get()).length;

  Future<void> expectNoNegativePool() async {
    final balances = computeAllPoolBalances(await all());
    for (final e in balances.entries) {
      expect(e.value >= 0, isTrue, reason: 'pool ${e.key} âm: ${e.value}');
    }
  }

  const vo = FamilyMember.vo;
  const chong = FamilyMember.chong;

  group('Tầng 1 + tầng 2 — flow A/B/C', () {
    test('A — Thêm vào tiết kiệm: Khả dụng giảm, Savings tăng, vào "Chưa phân bổ", Total Assets không đổi', () async {
      await txRepo.addTransaction(income('i1', chong, 5000000));
      final assetsBefore = await totalAssets();

      await txRepo.addTransaction(topup('t1', chong, 1000000));

      expect(await avail(chong), 4000000);
      expect(await savings(chong), 1000000);
      expect(await asset(unalloc, chong), 1000000);
      expect(await totalAssets(), assetsBefore, reason: 'TRANSFER không đổi Total Assets');
    });

    test('B — Phân bổ (SAVINGS_CONVERT): Chưa phân bổ → Vàng, Savings Total và Khả dụng không đổi', () async {
      await txRepo.addTransaction(income('i1', chong, 5000000));
      await txRepo.addTransaction(topup('t1', chong, 1000000));
      final before = (await avail(chong), await savings(chong), await totalAssets());

      await txRepo.addTransaction(convert('c1', chong, unalloc, gold, 500000));

      expect(await asset(unalloc, chong), 500000);
      expect(await asset(gold, chong), 500000);
      expect((await avail(chong), await savings(chong), await totalAssets()), before);
    });

    test('C — Rút 200k từ Vàng về Khả dụng: Vàng 300k, Chưa phân bổ 500k, Savings 800k, Khả dụng +200k', () async {
      await txRepo.addTransaction(income('i1', chong, 5000000));
      await txRepo.addTransaction(topup('t1', chong, 1000000));
      await txRepo.addTransaction(convert('c1', chong, unalloc, gold, 500000));
      final assetsBefore = await totalAssets();

      await txRepo.addTransaction(withdraw('w1', chong, gold, 200000));

      expect(await asset(gold, chong), 300000);
      expect(await asset(unalloc, chong), 500000);
      expect(await savings(chong), 800000);
      expect(await avail(chong), 4200000);
      expect(await totalAssets(), assetsBefore);
    });

    test('Chuyển giữa các loại: Vàng → Gửi NH, Gửi NH → Chứng khoán; tổng Savings không đổi, không phải Thu/Chi', () async {
      await txRepo.addTransaction(income('i1', vo, 3000000));
      await txRepo.addTransaction(topup('t1', vo, 1000000));
      await txRepo.addTransaction(convert('c1', vo, unalloc, gold, 600000));
      await txRepo.addTransaction(convert('c2', vo, gold, bank, 200000));
      await txRepo.addTransaction(convert('c3', vo, bank, stocks, 100000));

      expect(await savings(vo), 1000000);
      expect(await asset(unalloc, vo), 400000);
      expect(await asset(gold, vo), 400000);
      expect(await asset(bank, vo), 100000);
      expect(await asset(stocks, vo), 100000);
    });

    test('Không đủ tiền: phân bổ / rút quá số dư của nguồn bị chặn (không ghi gì)', () async {
      await txRepo.addTransaction(income('i1', vo, 1000000));
      await txRepo.addTransaction(topup('t1', vo, 300000));
      final before = await rows();

      await expectLater(
        txRepo.addTransaction(convert('c1', vo, unalloc, gold, 400000)),
        throwsA(isA<InsufficientBalanceException>()),
      );
      await expectLater(
        txRepo.addTransaction(withdraw('w1', vo, gold, 1)),
        throwsA(isA<InsufficientBalanceException>()),
      );
      expect(await rows(), before);
    });

    test('Savings Total = tổng MỌI pool tiết kiệm của thành viên (gồm Chưa phân bổ + loại đã ngừng còn số dư)', () async {
      await txRepo.addTransaction(income('i1', vo, 2000000));
      await txRepo.addTransaction(topup('t1', vo, 1000000));
      await txRepo.addTransaction(convert('c1', vo, unalloc, gold, 400000));
      // Loại Vàng bị ngừng bằng cách ép trực tiếp (mô phỏng dữ liệu cũ) dù còn tiền.
      await (db.update(db.savingsAssetTypeRows)..where((r) => r.id.equals(gold)))
          .write(const SavingsAssetTypeRowsCompanion(isActive: Value(false)));

      expect(await savings(vo), 1000000, reason: 'Home: vẫn cộng pool của loại đã ngừng');
    });
  });

  group('Vợ / Chồng tách riêng', () {
    test('Vợ thêm/phân bổ/rút chỉ đổi Savings + Khả dụng của Vợ; Chồng nguyên vẹn', () async {
      await txRepo.addTransaction(income('iv', vo, 3000000));
      await txRepo.addTransaction(income('ic', chong, 2000000));
      final chongBefore = (await avail(chong), await savings(chong), await asset(unalloc, chong));

      await txRepo.addTransaction(topup('t1', vo, 1000000));
      await txRepo.addTransaction(convert('c1', vo, unalloc, gold, 600000));
      await txRepo.addTransaction(convert('c2', vo, gold, bank, 200000));
      await txRepo.addTransaction(withdraw('w1', vo, gold, 300000));

      expect((await avail(chong), await savings(chong), await asset(unalloc, chong)), chongBefore);
      expect(await savings(vo), 700000);
      expect(await avail(vo), 2300000);
    });

    test('Chồng thêm vào tiết kiệm chỉ tăng Savings Chồng', () async {
      await txRepo.addTransaction(income('ic', chong, 2000000));
      await txRepo.addTransaction(topup('t1', chong, 500000));
      expect(await savings(chong), 500000);
      expect(await savings(vo), 0);
    });
  });

  group('Bất biến thành viên — chặn ở tầng ghi, không chỉ UI', () {
    test('Vợ Khả dụng → Tiết kiệm Chồng bị từ chối, 0 dòng mới', () async {
      await txRepo.addTransaction(income('iv', vo, 1000000));
      final before = await rows();
      final bad = tx(
        id: 'bad1',
        type: TransactionType.transfer,
        kind: TransferKind.savingsTopup,
        from: PoolKind.memberAvailable,
        fromRef: vo.name,
        to: PoolKind.memberSavingsAsset,
        toRef: ref(unalloc, chong),
        amount: 1000,
      );
      await expectLater(txRepo.addTransaction(bad), throwsA(isA<SavingsMemberMismatchException>()));
      expect(await rows(), before);
    });

    test('Chuyển đổi Vàng Vợ → Gửi NH Chồng bị từ chối', () async {
      await txRepo.addTransaction(income('iv', vo, 1000000));
      await txRepo.addTransaction(topup('t1', vo, 500000));
      await txRepo.addTransaction(convert('c1', vo, unalloc, gold, 500000));
      final bad = tx(
        id: 'bad2',
        type: TransactionType.transfer,
        kind: TransferKind.savingsConvert,
        from: PoolKind.memberSavingsAsset,
        fromRef: ref(gold, vo),
        to: PoolKind.memberSavingsAsset,
        toRef: ref(bank, chong),
        amount: 1000,
      );
      await expectLater(txRepo.addTransaction(bad), throwsA(isA<SavingsMemberMismatchException>()));
    });

    test('Rút Tiết kiệm Vợ → Khả dụng Chồng bị từ chối; nạp sai hình dạng (nguồn là tiết kiệm) bị từ chối', () async {
      final wrongWithdraw = tx(
        id: 'bad3',
        type: TransactionType.transfer,
        kind: TransferKind.savingsWithdraw,
        from: PoolKind.memberSavingsAsset,
        fromRef: ref(gold, vo),
        to: PoolKind.memberAvailable,
        toRef: chong.name,
        amount: 1000,
      );
      await expectLater(txRepo.addTransaction(wrongWithdraw), throwsA(isA<SavingsMemberMismatchException>()));
      final wrongShape = tx(
        id: 'bad4',
        type: TransactionType.transfer,
        kind: TransferKind.savingsTopup,
        from: PoolKind.memberSavingsAsset,
        fromRef: ref(gold, vo),
        to: PoolKind.memberAvailable,
        toRef: vo.name,
        amount: 1000,
      );
      await expectLater(txRepo.addTransaction(wrongShape), throwsA(isA<SavingsMemberMismatchException>()));
    });

    test('Chuyển tiền Vợ → Chồng (member-to-member) VẪN hợp lệ', () async {
      await txRepo.addTransaction(income('iv', vo, 1000000));
      await txRepo.addTransaction(
        tx(
          id: 'm1',
          type: TransactionType.transfer,
          kind: TransferKind.memberToMember,
          category: 'chuyen_tien_thanh_vien',
          from: PoolKind.memberAvailable,
          fromRef: vo.name,
          to: PoolKind.memberAvailable,
          toRef: chong.name,
          amount: 250000,
        ),
      );
      expect(await avail(vo), 750000);
      expect(await avail(chong), 250000);
    });

    test('Số dư ban đầu (INCOME thẳng vào pool tiết kiệm, không có transferKind) vẫn hợp lệ — Golden dùng', () async {
      await txRepo.addTransaction(
        tx(
          id: 'open',
          type: TransactionType.income,
          category: 'so_du_ban_dau',
          from: PoolKind.external,
          to: PoolKind.memberSavingsAsset,
          toRef: ref(bank, vo),
          amount: 700000,
        ),
      );
      expect(await savings(vo), 700000);
    });
  });

  group('Guard hoàn tác không làm pool âm', () {
    test('A — nạp 1m rồi hoàn tác ngay → Khả dụng và Savings trở về ban đầu', () async {
      await txRepo.addTransaction(income('i1', chong, 5000000));
      final before = (await avail(chong), await savings(chong), await totalAssets());
      await txRepo.addTransaction(topup('t1', chong, 1000000));

      await txRepo.reverseTransaction('t1');

      expect((await avail(chong), await savings(chong), await totalAssets()), before);
      expect(await asset(unalloc, chong), 0);
      await expectNoNegativePool();
    });

    test('B — nạp 1m, phân bổ 500k sang Vàng, hoàn tác lần nạp → CHẶN: 0 dòng mới, số dư không đổi, không âm', () async {
      await txRepo.addTransaction(income('i1', chong, 5000000));
      await txRepo.addTransaction(topup('t1', chong, 1000000));
      await txRepo.addTransaction(convert('c1', chong, unalloc, gold, 500000));
      final rowsBefore = await rows();
      final balancesBefore = computeAllPoolBalances(await all());

      await expectLater(
        txRepo.reverseTransaction('t1'),
        throwsA(isA<ReversalWouldOverdrawException>()),
      );

      expect(await rows(), rowsBefore, reason: 'không ghi giao dịch nào');
      expect(computeAllPoolBalances(await all()), balancesBefore);
      await expectNoNegativePool();
      final t1 = (await db.select(db.transactionRows).get()).firstWhere((r) => r.id == 't1');
      expect(t1.reversedByTxId, isNull, reason: 'bản gốc không bị đánh dấu đã hoàn tác');
    });

    test('C — hoàn tác phân bổ trước, rồi hoàn tác lần nạp → cho phép, về trạng thái ban đầu', () async {
      await txRepo.addTransaction(income('i1', chong, 5000000));
      final before = (await avail(chong), await savings(chong), await totalAssets());
      await txRepo.addTransaction(topup('t1', chong, 1000000));
      await txRepo.addTransaction(convert('c1', chong, unalloc, gold, 500000));

      await txRepo.reverseTransaction('c1');
      await txRepo.reverseTransaction('t1');

      expect((await avail(chong), await savings(chong), await totalAssets()), before);
      expect(await asset(gold, chong), 0);
      await expectNoNegativePool();
    });

    test('D — rút 200k từ Vàng rồi hoàn tác → tiền quay đúng pool Vàng, Khả dụng trừ lại', () async {
      await txRepo.addTransaction(income('i1', chong, 5000000));
      await txRepo.addTransaction(topup('t1', chong, 1000000));
      await txRepo.addTransaction(convert('c1', chong, unalloc, gold, 500000));
      await txRepo.addTransaction(withdraw('w1', chong, gold, 200000));

      await txRepo.reverseTransaction('w1');

      expect(await asset(gold, chong), 500000);
      expect(await avail(chong), 4000000);
      await expectNoNegativePool();
    });

    test('Hoàn tác phân bổ vào loại ĐÃ NGỪNG vẫn trả tiền đúng pool (không kẹt tiền)', () async {
      await txRepo.addTransaction(income('i1', vo, 2000000));
      await txRepo.addTransaction(topup('t1', vo, 1000000));
      await txRepo.addTransaction(convert('c1', vo, unalloc, gold, 400000));
      await (db.update(db.savingsAssetTypeRows)..where((r) => r.id.equals(gold)))
          .write(const SavingsAssetTypeRowsCompanion(isActive: Value(false)));

      await txRepo.reverseTransaction('c1');

      expect(await asset(gold, vo), 0);
      expect(await asset(unalloc, vo), 1000000);
    });

    test('Guard TỔNG QUÁT: hoàn tác khoản thu sau khi đã chi hết → chặn (Khả dụng không âm)', () async {
      await txRepo.addTransaction(income('i1', vo, 1000000));
      await txRepo.addTransaction(
        tx(
          id: 'e1',
          type: TransactionType.expense,
          category: 'sinh_hoat',
          from: PoolKind.memberAvailable,
          fromRef: vo.name,
          to: PoolKind.external,
          amount: 900000,
        ),
      );
      final before = await rows();
      await expectLater(txRepo.reverseTransaction('i1'), throwsA(isA<ReversalWouldOverdrawException>()));
      expect(await rows(), before);
    });

    test('Guard TỔNG QUÁT: hoàn tác nạp quỹ sau khi quỹ đã chi → chặn', () async {
      await txRepo.addTransaction(income('i1', vo, 1000000));
      await txRepo.addTransaction(
        tx(
          id: 'f1',
          type: TransactionType.transfer,
          kind: TransferKind.fundTopup,
          category: 'nap_quy',
          from: PoolKind.memberAvailable,
          fromRef: vo.name,
          to: PoolKind.fund,
          toRef: 'an_uong',
          amount: 300000,
        ),
      );
      await txRepo.addTransaction(
        tx(
          id: 'f2',
          type: TransactionType.expense,
          category: 'sinh_hoat',
          from: PoolKind.fund,
          fromRef: 'an_uong',
          to: PoolKind.external,
          amount: 200000,
        ),
      );
      await expectLater(txRepo.reverseTransaction('f1'), throwsA(isA<ReversalWouldOverdrawException>()));
      // Hoàn tác khoản chi từ quỹ (tăng quỹ) vẫn được.
      await txRepo.reverseTransaction('f2');
    });

    test('E — sửa số tiền lần nạp: giảm nhưng vẫn ≥ phần đã phân bổ → được; giảm xuống dưới phần đã phân bổ → chặn', () async {
      await txRepo.addTransaction(income('i1', chong, 5000000));
      await txRepo.addTransaction(topup('t1', chong, 1000000));
      await txRepo.addTransaction(convert('c1', chong, unalloc, gold, 500000));

      // 1m → 900k: Chưa phân bổ còn 400k ≥ 0 → OK (thay dòng cũ bằng dòng mới).
      await txRepo.updateTransaction('t1', amountMinor: 900000);
      expect(await asset(unalloc, chong), 400000);
      expect(await asset(gold, chong), 500000);
      expect(await avail(chong), 4100000);
      await expectNoNegativePool();

      // Dòng nạp hiện tại → giảm xuống 300k < 500k đã phân bổ → chặn.
      final latest = (await db.select(db.transactionRows).get())
          .firstWhere((r) => r.categoryId == 'tiet_kiem' && r.sourceKind == 'memberAvailable');
      final rowsBefore = await rows();
      await expectLater(
        txRepo.updateTransaction(latest.id, amountMinor: 300000),
        throwsA(isA<ChangeWouldOverdrawException>()),
      );
      expect(await rows(), rowsBefore);
      await expectNoNegativePool();
    });

    test('Sửa số tiền của phân bổ giữ nguyên thành viên và loại', () async {
      await txRepo.addTransaction(income('i1', chong, 5000000));
      await txRepo.addTransaction(topup('t1', chong, 1000000));
      await txRepo.addTransaction(convert('c1', chong, unalloc, gold, 500000));

      await txRepo.updateTransaction('c1', amountMinor: 300000);

      expect(await asset(gold, chong), 300000);
      expect(await asset(unalloc, chong), 700000);
      expect(await asset(gold, vo), 0);
    });
  });

  group('Loại tài sản ĐÃ NGỪNG còn số dư', () {
    Future<void> deactivate(String id) =>
        (db.update(db.savingsAssetTypeRows)..where((r) => r.id.equals(id)))
            .write(const SavingsAssetTypeRowsCompanion(isActive: Value(false)));

    test('Không nhận thêm tiền (chuyển VÀO bị chặn) nhưng rút / chuyển RA vẫn được', () async {
      await txRepo.addTransaction(income('i1', vo, 2000000));
      await txRepo.addTransaction(topup('t1', vo, 1000000));
      await txRepo.addTransaction(convert('c1', vo, unalloc, gold, 500000));
      await deactivate(gold);

      await expectLater(
        txRepo.addTransaction(convert('c2', vo, unalloc, gold, 100000)),
        throwsA(isA<SavingsAssetInactiveException>()),
      );
      // Rút và chuyển RA khỏi loại đã ngừng đều được.
      await txRepo.addTransaction(withdraw('w1', vo, gold, 100000));
      await txRepo.addTransaction(convert('c3', vo, gold, bank, 100000));
      expect(await asset(gold, vo), 300000);
      expect(await asset(bank, vo), 100000);
    });

    test('Chưa phân bổ (hệ thống) không bao giờ bị coi là ngừng — luôn nhận tiền', () async {
      await txRepo.addTransaction(income('i1', vo, 1000000));
      await txRepo.addTransaction(topup('t1', vo, 100000));
      await txRepo.addTransaction(convert('c1', vo, unalloc, gold, 50000));
      await txRepo.addTransaction(convert('c2', vo, gold, unalloc, 20000));
      expect(await asset(unalloc, vo), 70000);
    });
  });

  group('Vòng đời SavingsAssetType', () {
    Future<void> deactivateViaRepo(String id) => assetRepo.softDeleteAssetType(id);
    Future<Set<String>> deletable() => assetRepo.watchDeletableAssetTypeIds().first;
    Future<bool> exists(String id) async =>
        (await (db.select(db.savingsAssetTypeRows)..where((r) => r.id.equals(id))).get()).isNotEmpty;

    test('ngừng + chưa từng có giao dịch + số dư 0 → xoá hẳn thành công', () async {
      await deactivateViaRepo(stocks);
      expect(await deletable(), contains(stocks));

      await assetRepo.deleteAssetTypePermanently(stocks);

      expect(await exists(stocks), isFalse);
      expect(await exists(bank), isTrue);
    });

    test('đã từng có giao dịch (kể cả đã hoàn tác) → KHÔNG xoá hẳn được, chỉ ngừng', () async {
      await txRepo.addTransaction(income('i1', vo, 1000000));
      await txRepo.addTransaction(topup('t1', vo, 100000));
      await txRepo.addTransaction(convert('c1', vo, unalloc, gold, 100000));
      await txRepo.reverseTransaction('c1');
      // Số dư Vàng = 0 nhưng đã từng được dùng.
      await deactivateViaRepo(gold);

      expect(await deletable(), isNot(contains(gold)));
      await expectLater(
        assetRepo.deleteAssetTypePermanently(gold),
        throwsA(isA<SavingsAssetTypeNotDeletableException>()),
      );
      expect(await exists(gold), isTrue);
    });

    test('còn số dư ≠ 0 ở bất kỳ thành viên → không ngừng được (không để tiền biến mất khỏi UI)', () async {
      await txRepo.addTransaction(income('i1', chong, 1000000));
      await txRepo.addTransaction(topup('t1', chong, 100000));
      await txRepo.addTransaction(convert('c1', chong, unalloc, gold, 100000));

      await expectLater(
        assetRepo.softDeleteAssetType(gold),
        throwsA(isA<SavingsAssetTypeNotEmptyException>()),
      );
      final row = await (db.select(db.savingsAssetTypeRows)..where((r) => r.id.equals(gold))).getSingle();
      expect(row.isActive, isTrue);
    });

    test('đang dùng (chưa ngừng) → không xoá hẳn', () async {
      expect(await deletable(), isNot(contains(bank)));
      await expectLater(
        assetRepo.deleteAssetTypePermanently(bank),
        throwsA(isA<SavingsAssetTypeNotDeletableException>()),
      );
    });

    test('kiểm tra lại trong lúc xoá: giao dịch xuất hiện sau khi UI thấy an toàn vẫn bị chặn', () async {
      await deactivateViaRepo(stocks);
      expect(await deletable(), contains(stocks));
      // Loại đã ngừng vẫn có thể nhận tiền theo dữ liệu cũ qua INCOME (số dư ban đầu).
      await txRepo.addTransaction(
        tx(
          id: 'late',
          type: TransactionType.income,
          category: 'so_du_ban_dau',
          from: PoolKind.external,
          to: PoolKind.memberSavingsAsset,
          toRef: ref(stocks, vo),
          amount: 1000,
        ),
      );
      await expectLater(
        assetRepo.deleteAssetTypePermanently(stocks),
        throwsA(isA<SavingsAssetTypeNotDeletableException>()),
      );
    });

    test('nhận diện chính xác id (không nhầm tiền tố): loại "sav" không bị coi là đã dùng bởi "savings_bank"', () async {
      await assetRepo.addAssetType(
        const SavingsAssetType(id: 'sav', name: 'Sav', color: Color(0xFF000000)),
      );
      await deactivateViaRepo('sav');
      await txRepo.addTransaction(income('i1', vo, 1000000));
      await txRepo.addTransaction(topup('t1', vo, 100000));
      await txRepo.addTransaction(convert('c1', vo, unalloc, bank, 100000));
      expect(await deletable(), contains('sav'));
    });

    test('Sử dụng lại / đổi tên giữ NGUYÊN id; updateAssetType không đổi isActive', () async {
      await deactivateViaRepo(stocks);
      await assetRepo.reactivateAssetType(stocks);
      var row = await (db.select(db.savingsAssetTypeRows)..where((r) => r.id.equals(stocks))).getSingle();
      expect(row.isActive, isTrue);

      await assetRepo.renameAssetType(stocks, 'Cổ phiếu');
      row = await (db.select(db.savingsAssetTypeRows)..where((r) => r.id.equals(stocks))).getSingle();
      expect(row.name, 'Cổ phiếu');

      // updateAssetType chỉ đổi tên/màu, KHÔNG đổi isActive (né kiểm tra số dư).
      await assetRepo.updateAssetType(
        (await assetRepo.watchAssetTypes().first).firstWhere((a) => a.id == stocks).copyWith(isActive: false),
      );
      row = await (db.select(db.savingsAssetTypeRows)..where((r) => r.id.equals(stocks))).getSingle();
      expect(row.isActive, isTrue);
    });

    test('Tài sản hệ thống "Chưa phân bổ": không có dòng DB; không tạo/ngừng/xoá được', () async {
      expect(
        (await db.select(db.savingsAssetTypeRows).get()).map((r) => r.id),
        isNot(contains(unalloc)),
        reason: 'KHÔNG có row trong bảng SavingsAssetType',
      );
      await expectLater(
        assetRepo.addAssetType(SystemSavingsAssets.unallocated),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        assetRepo.softDeleteAssetType(unalloc),
        throwsA(isA<SavingsAssetTypeNotDeletableException>()),
      );
      await expectLater(
        assetRepo.deleteAssetTypePermanently(unalloc),
        throwsA(isA<SavingsAssetTypeNotDeletableException>()),
      );
      // Dùng "Chưa phân bổ" nhiều lần rồi vẫn không xuất hiện trong bảng.
      await txRepo.addTransaction(income('i1', vo, 1000000));
      await txRepo.addTransaction(topup('t1', vo, 100000));
      expect((await db.select(db.savingsAssetTypeRows).get()).map((r) => r.id), isNot(contains(unalloc)));
      expect(await deletable(), isNot(contains(unalloc)));
    });
  });

  group('Báo cáo Thu/Chi không đổi', () {
    test('Nạp / rút / phân bổ tiết kiệm KHÔNG ảnh hưởng Doanh thu, Khoản thu khác, Chi tiêu, Chi phí KD, Thu nhập ròng', () async {
      await txRepo.addTransaction(income('i1', chong, 5000000));
      final categories = DefaultCategories.all;
      final list0 = await all();
      final g0 = computeGroupedTotals(list0, categories, member: chong);

      await txRepo.addTransaction(topup('t1', chong, 1000000));
      await txRepo.addTransaction(convert('c1', chong, unalloc, gold, 500000));
      await txRepo.addTransaction(withdraw('w1', chong, gold, 200000));

      final g1 = computeGroupedTotals(await all(), categories, member: chong);
      expect(g1.revenue, g0.revenue);
      expect(g1.otherInflow, g0.otherInflow);
      expect(g1.spending, g0.spending);
      expect(g1.businessExpense, g0.businessExpense);
      expect(g1.netIncome, g0.netIncome);
    });
  });
}
