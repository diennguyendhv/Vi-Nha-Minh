import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/constants/default_savings_asset_types.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/repositories/local_category_repository.dart';
import 'package:vi_nha_minh/data/repositories/local_status_repository.dart';
import 'package:vi_nha_minh/data/repositories/local_transaction_repository.dart';
import 'package:vi_nha_minh/domain/engine/financial_engine.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/family_member.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/savings_asset_type.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart' as domain;
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/entities/transfer_kind.dart';
import 'package:vi_nha_minh/domain/errors/domain_exceptions.dart';
import 'package:vi_nha_minh/domain/usecases/compute_pool_balance.dart';
import '../../support/legacy_correction.dart';

/// "Xóa giao dịch" = XOÁ THẬT: dòng (và cả họ gốc/hoàn tác/thay thế) biến mất
/// khỏi DB, số dư tính lại từ các giao dịch còn lại; bị chặn nếu làm pool âm
/// hoặc dính Vay / Hoàn tiền. Không tạo giao dịch bù trừ.
void main() {
  late AppDatabase db;
  late LocalTransactionRepository repo;
  late LocalCategoryRepository cats;
  late LocalStatusRepository statuses;
  var seq = 0;
  const vo = FamilyMember.vo;
  const chong = FamilyMember.chong;
  const unalloc = SystemSavingsAssets.unallocatedId;
  const gold = DefaultSavingsAssetTypes.goldId;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LocalTransactionRepository(db);
    cats = LocalCategoryRepository(db);
    statuses = LocalStatusRepository(db);
    seq = 0;
  });

  tearDown(() async => db.close());

  domain.Transaction tx({
    required String id,
    required TransactionType type,
    TransferKind? kind,
    String category = 'sinh_hoat',
    String? statusId,
    required PoolKind from,
    String? fromRef,
    required PoolKind to,
    String? toRef,
    required int amount,
    String? recoveryOf,
    String? obligation,
  }) {
    seq++;
    return domain.Transaction(
      id: id,
      type: type,
      transferKind: kind,
      categoryId: category,
      statusId: statusId,
      sourceKind: from,
      sourceRefId: fromRef,
      destinationKind: to,
      destinationRefId: toRef,
      amountMinor: amount,
      recoveryOfTxId: recoveryOf,
      obligationId: obligation,
      transactionDate: DateTime(2026, 9, 1),
      createdAt: DateTime(2026, 9, 1),
      clientTxId: 'c-$seq',
    );
  }

  domain.Transaction income(String id, FamilyMember m, int amount, {String category = 'thu_nhap'}) => tx(
    id: id,
    type: TransactionType.income,
    category: category,
    from: PoolKind.external,
    to: PoolKind.memberAvailable,
    toRef: m.name,
    amount: amount,
  );

  domain.Transaction expense(String id, FamilyMember m, int amount, {String category = 'sinh_hoat', String? statusId}) => tx(
    id: id,
    type: TransactionType.expense,
    category: category,
    statusId: statusId,
    from: PoolKind.memberAvailable,
    fromRef: m.name,
    to: PoolKind.external,
    amount: amount,
  );

  domain.Transaction topup(String id, FamilyMember m, int amount) => tx(
    id: id,
    type: TransactionType.transfer,
    kind: TransferKind.savingsTopup,
    category: 'tiet_kiem',
    from: PoolKind.memberAvailable,
    fromRef: m.name,
    to: PoolKind.memberSavingsAsset,
    toRef: savingsAssetRefId(unalloc, m),
    amount: amount,
  );

  domain.Transaction allocate(String id, FamilyMember m, int amount) => tx(
    id: id,
    type: TransactionType.transfer,
    kind: TransferKind.savingsConvert,
    category: 'tiet_kiem',
    from: PoolKind.memberSavingsAsset,
    fromRef: savingsAssetRefId(unalloc, m),
    to: PoolKind.memberSavingsAsset,
    toRef: savingsAssetRefId(gold, m),
    amount: amount,
  );

  Future<List<domain.Transaction>> all() => repo.watchTransactions().first;
  Future<bool> exists(String id) async => (await all()).any((t) => t.id == id);
  Future<int> rows() async => (await all()).length;
  Future<int> avail(FamilyMember m) async => computeMemberAvailableBalance(m, await all());
  Future<int> savings(FamilyMember m) async => computeMemberSavingsTotal(m, await all());

  Category cat(String id) => Category(
    id: id,
    name: 'Tên $id',
    color: const Color(0xFF123456),
    type: TransactionType.expense,
    isDefault: false,
  );

  group('Xóa thật — giao dịch bình thường', () {
    test('A — xóa khoản THU: dòng biến mất, Khả dụng giảm lại đúng số đó', () async {
      await repo.addTransaction(income('i1', vo, 3000000));
      await repo.addTransaction(income('i2', vo, 1000000));
      expect(await avail(vo), 4000000);

      await repo.deleteTransaction('i2');

      expect(await exists('i2'), isFalse);
      expect(await avail(vo), 3000000);
      expect(await rows(), 1, reason: 'KHÔNG tạo giao dịch bù trừ');
    });

    test('B — xóa khoản CHI: dòng biến mất, Khả dụng tăng lại', () async {
      await repo.addTransaction(income('i1', vo, 1000000));
      await repo.addTransaction(expense('e1', vo, 300000));
      expect(await avail(vo), 700000);

      await repo.deleteTransaction('e1');

      expect(await exists('e1'), isFalse);
      expect(await avail(vo), 1000000);
      expect(await rows(), 1);
    });

    test('C — xóa CHUYỂN Vợ → Chồng: cả 2 số dư quay lại đúng', () async {
      await repo.addTransaction(income('i1', vo, 1000000));
      await repo.addTransaction(
        tx(
          id: 'm1',
          type: TransactionType.transfer,
          kind: TransferKind.memberToMember,
          category: 'chuyen_tien_thanh_vien',
          from: PoolKind.memberAvailable,
          fromRef: vo.name,
          to: PoolKind.memberAvailable,
          toRef: chong.name,
          amount: 400000,
        ),
      );
      expect((await avail(vo), await avail(chong)), (600000, 400000));

      await repo.deleteTransaction('m1');

      expect((await avail(vo), await avail(chong)), (1000000, 0));
    });

    test('Không tồn tại → TransactionNotFoundException; không đổi gì', () async {
      await repo.addTransaction(income('i1', vo, 1000));
      await expectLater(repo.deleteTransaction('khong-co'), throwsA(isA<TransactionNotFoundException>()));
      expect(await rows(), 1);
    });

    test('Xóa 2 lần liên tiếp / đồng thời: chỉ xóa 1 lần, lần sau báo không tồn tại', () async {
      await repo.addTransaction(income('i1', vo, 1000000));
      await repo.addTransaction(income('i2', vo, 500000));

      final results = await Future.wait([
        repo.deleteTransaction('i2').then<Object?>((_) => 'ok').catchError((Object e) => e),
        repo.deleteTransaction('i2').then<Object?>((_) => 'ok').catchError((Object e) => e),
      ]);

      expect(results.where((r) => r == 'ok'), hasLength(1));
      expect(results.whereType<TransactionNotFoundException>(), hasLength(1));
      expect(await avail(vo), 1000000);
    });
  });

  group('Xóa bị chặn nếu làm pool âm (không cascade)', () {
    test('D — xóa lần nạp tiết kiệm CHƯA dùng tiếp → được', () async {
      await repo.addTransaction(income('i1', chong, 5000000));
      await repo.addTransaction(topup('t1', chong, 1000000));
      await repo.deleteTransaction('t1');
      expect(await exists('t1'), isFalse);
      expect((await avail(chong), await savings(chong)), (5000000, 0));
    });

    test('E — xóa lần nạp khi ĐÃ phân bổ 600k → CHẶN: 0 dòng đổi, không âm', () async {
      await repo.addTransaction(income('i1', chong, 5000000));
      await repo.addTransaction(topup('t1', chong, 1000000));
      await repo.addTransaction(allocate('a1', chong, 600000));
      final before = computeAllPoolBalances(await all());
      final rowsBefore = await rows();

      await expectLater(repo.deleteTransaction('t1'), throwsA(isA<DeleteWouldOverdrawException>()));

      expect(await rows(), rowsBefore);
      expect(computeAllPoolBalances(await all()), before);
      expect(await exists('t1'), isTrue);
      expect(await exists('a1'), isTrue, reason: 'không tự cascade xóa phân bổ');
    });

    test('F — xóa phân bổ trước, rồi xóa lần nạp → cho phép, về trạng thái ban đầu', () async {
      await repo.addTransaction(income('i1', chong, 5000000));
      await repo.addTransaction(topup('t1', chong, 1000000));
      await repo.addTransaction(allocate('a1', chong, 600000));

      await repo.deleteTransaction('a1');
      await repo.deleteTransaction('t1');

      expect((await avail(chong), await savings(chong)), (5000000, 0));
      expect(await rows(), 1);
    });

    test('G — xóa nạp quỹ sau khi quỹ đã chi → CHẶN; xóa khoản chi quỹ thì được', () async {
      await repo.addTransaction(income('i1', vo, 1000000));
      await repo.addTransaction(
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
      await repo.addTransaction(
        tx(
          id: 'f2',
          type: TransactionType.expense,
          from: PoolKind.fund,
          fromRef: 'an_uong',
          to: PoolKind.external,
          amount: 200000,
        ),
      );
      await expectLater(repo.deleteTransaction('f1'), throwsA(isA<DeleteWouldOverdrawException>()));
      await repo.deleteTransaction('f2');
      await repo.deleteTransaction('f1');
      expect(await avail(vo), 1000000);
    });

    test('Xóa khoản thu khi tiền đã chi hết → CHẶN (Khả dụng không âm)', () async {
      await repo.addTransaction(income('i1', vo, 1000000));
      await repo.addTransaction(expense('e1', vo, 900000));
      await expectLater(repo.deleteTransaction('i1'), throwsA(isA<DeleteWouldOverdrawException>()));
      expect(await exists('i1'), isTrue);
    });
  });

  group('Họ giao dịch: gốc + hoàn tác + bản thay thế', () {
    test('H — cặp gốc + hoàn tác (cách xóa cũ): xóa 1 dòng bất kỳ → xóa CẢ HAI, số dư không đổi', () async {
      await repo.addTransaction(income('i1', vo, 1000000));
      await repo.addTransaction(expense('e1', vo, 200000));
      await repo.reverseTransaction('e1'); // cơ chế cũ: e1 + dòng hoàn tác
      expect(await rows(), 3);
      final balancesBefore = computeAllPoolBalances(await all());

      await repo.deleteTransaction('e1');

      expect(await rows(), 1, reason: 'cả gốc lẫn hoàn tác đều biến mất');
      expect(computeAllPoolBalances(await all())[(PoolKind.memberAvailable, vo.name)], balancesBefore[(PoolKind.memberAvailable, vo.name)]);
    });

    test('H2 — chọn đúng DÒNG HOÀN TÁC cũng dọn cả cặp', () async {
      await repo.addTransaction(income('i1', vo, 1000000));
      await repo.addTransaction(expense('e1', vo, 200000));
      await repo.reverseTransaction('e1');
      final reversalId = (await all()).firstWhere((t) => t.reversalOfTxId == 'e1').id;

      await repo.deleteTransaction(reversalId);

      expect(await rows(), 1);
    });

    test('K — chuỗi sửa số tiền (gốc → hoàn tác → thay thế → …): xóa giao dịch hiện tại xóa CẢ HỌ, không nửa chuỗi', () async {
      await repo.addTransaction(income('i1', vo, 1000000));
      await repo.addTransaction(expense('e1', vo, 200000));
      await legacyCorrect(repo, 'e1', amount: 300000); // gốc + hoàn tác + thay thế #1
      final latest1 = (await all()).firstWhere((t) => t.correctsTxId == 'e1');
      await legacyCorrect(repo, latest1.id, amount: 400000); // gốc #1 + hoàn tác + thay thế #2
      expect(await rows(), 1 + 5);
      final current = (await all()).firstWhere((t) => t.isVisibleHead && t.type == TransactionType.expense);
      expect(current.amountMinor, 400000);

      await repo.deleteTransaction(current.id);

      expect(await rows(), 1, reason: 'toàn bộ 5 dòng của họ biến mất, chỉ còn khoản thu');
      expect(await avail(vo), 1000000);
    });

    test('K2 — xóa bằng id của dòng GỐC cũng ra cùng kết quả (mọi dòng trong họ đều là điểm vào)', () async {
      await repo.addTransaction(income('i1', vo, 1000000));
      await repo.addTransaction(expense('e1', vo, 200000));
      await legacyCorrect(repo, 'e1', amount: 300000);

      await repo.deleteTransaction('e1');

      expect(await rows(), 1);
      expect(await avail(vo), 1000000);
    });

    test('Họ KHÔNG kéo theo giao dịch không liên quan', () async {
      await repo.addTransaction(income('i1', vo, 1000000));
      await repo.addTransaction(expense('e1', vo, 100000));
      await repo.addTransaction(expense('e2', vo, 50000));
      await legacyCorrect(repo, 'e1', amount: 120000);

      await repo.deleteTransaction('e1');

      expect(await exists('e2'), isTrue);
      expect(await exists('i1'), isTrue);
      expect(await avail(vo), 950000);
    });

    test('Họ mà xóa làm pool âm → CHẶN cả họ (không xóa nửa chuỗi)', () async {
      await repo.addTransaction(income('i1', chong, 5000000));
      await repo.addTransaction(topup('t1', chong, 1000000));
      await legacyCorrect(repo, 't1', amount: 900000); // t1 + hoàn tác + thay thế
      final head = (await all()).firstWhere((t) => t.correctsTxId == 't1');
      await repo.addTransaction(allocate('a1', chong, 500000));
      final rowsBefore = await rows();

      await expectLater(repo.deleteTransaction(head.id), throwsA(isA<DeleteWouldOverdrawException>()));
      await expectLater(repo.deleteTransaction('t1'), throwsA(isA<DeleteWouldOverdrawException>()));

      expect(await rows(), rowsBefore, reason: 'không dòng nào của họ bị xóa');
    });
  });

  group('Vay / Hoàn tiền (lịch sử nâng cao) — chặn, không cascade', () {
    test('L — khoản Thu hồi trỏ về khoản Chi gốc: xóa gốc HOẶC xóa thu hồi đều bị chặn', () async {
      await repo.addTransaction(income('i1', vo, 1000000));
      await repo.addTransaction(expense('e1', vo, 300000));
      await repo.addTransaction(
        tx(
          id: 'r1',
          type: TransactionType.income,
          category: 'hoan_tien_thu_hoi',
          from: PoolKind.external,
          to: PoolKind.memberAvailable,
          toRef: vo.name,
          amount: 100000,
          recoveryOf: 'e1',
        ),
      );
      final before = await rows();
      await expectLater(
        repo.deleteTransaction('e1'),
        throwsA(isA<TransactionDeleteBlockedException>().having((e) => e.reason, 'reason', DeleteBlockReason.linkedRecovery)),
      );
      await expectLater(repo.deleteTransaction('r1'), throwsA(isA<TransactionDeleteBlockedException>()));
      expect(await rows(), before);
    });

    test('Giao dịch thuộc khoản vay (obligationId) → chặn', () async {
      await repo.addTransaction(income('i1', vo, 1000000));
      await repo.addTransaction(
        tx(
          id: 'l1',
          type: TransactionType.expense,
          category: 'tra_no',
          from: PoolKind.memberAvailable,
          fromRef: vo.name,
          to: PoolKind.external,
          amount: 1000,
          obligation: 'ob-1',
        ),
      );
      await expectLater(
        repo.deleteTransaction('l1'),
        throwsA(isA<TransactionDeleteBlockedException>().having((e) => e.reason, 'reason', DeleteBlockReason.linkedLoan)),
      );
      expect(await exists('l1'), isTrue);
    });
  });

  group('Danh mục / Trạng thái sau khi xóa thật (kiểm tra theo DB HIỆN TẠI)', () {
    test('I — danh mục chỉ bị giữ bởi giao dịch vừa xóa → xóa hẳn được', () async {
      await repo.addTransaction(income('i1', vo, 1000000));
      await cats.addCategory(cat('c_tam'));
      await repo.addTransaction(expense('e1', vo, 1000, category: 'c_tam'));
      await cats.softDeleteCategory('c_tam');
      expect(await cats.watchDeletableCategoryIds().first, isNot(contains('c_tam')), reason: 'còn giao dịch dùng');

      await repo.deleteTransaction('e1');

      expect(await cats.watchDeletableCategoryIds().first, contains('c_tam'));
      await cats.deleteCategoryPermanently('c_tam');
      expect((await cats.watchCategories().first).map((c) => c.id), isNot(contains('c_tam')));
    });

    test('J — trạng thái chỉ bị giữ bởi giao dịch vừa xóa → xóa hẳn được', () async {
      await repo.addTransaction(income('i1', vo, 1000000));
      await repo.addTransaction(expense('e1', vo, 1000, category: 'cho_di', statusId: 'cho_di_da_gui'));
      await statuses.softDeleteStatus('cho_di_da_gui');
      expect(await statuses.watchDeletableStatusIds().first, isNot(contains('cho_di_da_gui')));

      await repo.deleteTransaction('e1');

      expect(await statuses.watchDeletableStatusIds().first, contains('cho_di_da_gui'));
      await statuses.deleteStatusPermanently('cho_di_da_gui');
    });

    test('Cặp gốc + hoàn tác cũ giữ danh mục "ZZ B" — sau khi dọn cả họ, danh mục xóa hẳn được', () async {
      await repo.addTransaction(income('i1', vo, 1000000));
      await cats.addCategory(cat('zz_b'));
      await repo.addTransaction(expense('e1', vo, 1000, category: 'zz_b'));
      await repo.reverseTransaction('e1'); // cách "xóa" cũ để lại 2 dòng ẩn
      await cats.softDeleteCategory('zz_b');
      expect(await cats.watchDeletableCategoryIds().first, isNot(contains('zz_b')), reason: 'dòng ẩn vẫn giữ danh mục');

      await repo.deleteTransaction('e1');

      expect(await cats.watchDeletableCategoryIds().first, contains('zz_b'));
      await cats.deleteCategoryPermanently('zz_b');
    });

    test('Dọn lịch sử ẩn (purgeDeletedHistory): xóa cặp gốc + hoàn tác của danh mục, KHÔNG đụng giao dịch sống; sau đó danh mục xóa hẳn được', () async {
      await repo.addTransaction(income('i1', vo, 1000000));
      await cats.addCategory(cat('zz_b'));
      await repo.addTransaction(expense('e1', vo, 1000, category: 'zz_b'));
      await repo.reverseTransaction('e1');
      await repo.addTransaction(expense('live', vo, 5000, category: 'sinh_hoat'));
      await cats.softDeleteCategory('zz_b');
      final balance = await avail(vo);

      final removed = await repo.purgeDeletedHistory('zz_b');

      expect(removed, 2);
      expect(await avail(vo), balance, reason: 'cặp đã triệt tiêu nhau → số dư không đổi');
      expect(await exists('live'), isTrue);
      expect(await exists('i1'), isTrue);
      await cats.deleteCategoryPermanently('zz_b');
    });

    test('Dọn lịch sử ẩn: danh mục còn giao dịch SỐNG → chỉ dọn phần ẩn, giao dịch sống ở lại (danh mục vẫn không xóa được)', () async {
      await repo.addTransaction(income('i1', vo, 1000000));
      await cats.addCategory(cat('zz_c'));
      await repo.addTransaction(expense('dead', vo, 1000, category: 'zz_c'));
      await repo.reverseTransaction('dead');
      await repo.addTransaction(expense('alive', vo, 2000, category: 'zz_c'));
      await cats.softDeleteCategory('zz_c');

      expect(await repo.purgeDeletedHistory('zz_c'), 2);

      expect(await exists('alive'), isTrue);
      expect(await cats.watchDeletableCategoryIds().first, isNot(contains('zz_c')));
      expect(await repo.purgeDeletedHistory('zz_c'), 0, reason: 'không còn gì để dọn');
    });

    test('Không khỏi bug cũ: trạng thái phải thuộc ĐÚNG danh mục — trạng thái danh mục khác bị từ chối khi thêm', () async {
      await repo.addTransaction(income('i1', vo, 1000000));
      await expectLater(
        repo.addTransaction(expense('bad', vo, 1000, category: 'sinh_hoat', statusId: 'cho_di_da_gui')),
        throwsA(isA<InvalidStatusForCategoryException>()),
      );
      expect(await exists('bad'), isFalse);
    });

    test('Đổi danh mục không chỉ định trạng thái → trạng thái cũ bị xóa (không "mắc kẹt" ở danh mục khác), cả đường sửa tại chỗ', () async {
      await repo.addTransaction(income('i1', vo, 1000000));
      await repo.addTransaction(expense('e1', vo, 1000, category: 'cho_di', statusId: 'cho_di_da_gui'));

      await repo.updateTransaction('e1', categoryId: 'sinh_hoat');

      final e1 = (await all()).firstWhere((t) => t.id == 'e1');
      expect(e1.categoryId, 'sinh_hoat');
      expect(e1.statusId, isNull);
    });

    test('Đổi danh mục KÈM sửa số tiền: dòng cũ biến mất, dòng mới đúng danh mục, trạng thái cũ bị xóa, không để lại lịch sử ẩn', () async {
      await repo.addTransaction(income('i1', vo, 1000000));
      await repo.addTransaction(expense('e1', vo, 1000, category: 'cho_di', statusId: 'cho_di_da_gui'));

      await repo.updateTransaction('e1', categoryId: 'sinh_hoat', amountMinor: 2000);

      final list = await all();
      expect(list.any((t) => t.id == 'e1'), isFalse, reason: 'dòng cũ mất');
      expect(list.length, 2, reason: 'chỉ còn khoản thu + dòng mới');
      final head = list.firstWhere((t) => t.type == TransactionType.expense);
      expect(head.categoryId, 'sinh_hoat');
      expect(head.statusId, isNull);
      expect(head.amountMinor, 2000);
      expect(list.any((t) => t.categoryId == 'cho_di' || t.statusId != null), isFalse, reason: 'không còn tham chiếu danh mục/trạng thái cũ');
      expect(list.every((t) => t.reversalOfTxId == null && t.reversedByTxId == null && t.correctsTxId == null), isTrue);
    });

    test('Chỉ định trạng thái không thuộc danh mục khi sửa → từ chối', () async {
      await repo.addTransaction(income('i1', vo, 1000000));
      await repo.addTransaction(expense('e1', vo, 1000));
      await expectLater(
        repo.updateTransaction('e1', statusId: 'cho_di_da_gui'),
        throwsA(isA<InvalidStatusForCategoryException>()),
      );
    });

    test('Giao dịch cũ đã lệch (Sinh hoạt + trạng thái của danh mục khác) được chữa khi lưu lại', () async {
      await repo.addTransaction(income('i1', vo, 1000000));
      await repo.addTransaction(expense('e1', vo, 1000));
      // Mô phỏng dữ liệu cũ bị lệch (bug trước đây): ép trực tiếp bằng SQL.
      await db.customStatement("UPDATE transaction_rows SET status_id = 'cho_di_da_gui' WHERE id = 'e1'");
      expect((await all()).firstWhere((t) => t.id == 'e1').statusId, 'cho_di_da_gui');

      await repo.updateTransaction('e1', note: 'sửa ghi chú');

      expect((await all()).firstWhere((t) => t.id == 'e1').statusId, isNull);
    });
  });

  test('N — khởi động lại app (mở lại file DB): dòng đã xóa KHÔNG quay lại', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final dir = await Directory.systemTemp.createTemp('vnm_delete_');
    final file = File('${dir.path}/vi_nha_minh.sqlite');
    addTearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    var fileDb = AppDatabase.forTesting(NativeDatabase(file));
    var r = LocalTransactionRepository(fileDb);
    await r.addTransaction(income('i1', vo, 1000000));
    await r.addTransaction(expense('e1', vo, 100000));
    await r.deleteTransaction('e1');
    await fileDb.close();

    fileDb = AppDatabase.forTesting(NativeDatabase(file));
    r = LocalTransactionRepository(fileDb);
    final list = await r.watchTransactions().first;
    expect(list.map((t) => t.id), ['i1']);
    expect(computeMemberAvailableBalance(vo, list), 1000000);
    final integrity = await fileDb.customSelect('PRAGMA integrity_check').get();
    expect(integrity.single.data.values.single, 'ok');
    await fileDb.close();
  });

  test('Xóa xong Explorer/Tổng hợp thấy ngay: luồng giao dịch phát lại danh sách không còn dòng đó', () async {
    await repo.addTransaction(income('i1', vo, 1000000));
    await repo.addTransaction(expense('e1', vo, 100000));
    final emissions = <List<String>>[];
    final sub = repo.watchTransactions().listen((l) => emissions.add([for (final t in l) t.id]));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await repo.deleteTransaction('e1');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(emissions.last, ['i1']);
    await sub.cancel();
  });

  test('Toàn vẹn sau nhiều lần xóa: integrity_check, foreign_key_check, không pool âm, không trùng clientTxId', () async {
    await repo.addTransaction(income('i1', chong, 5000000));
    await repo.addTransaction(topup('t1', chong, 1000000));
    await repo.addTransaction(allocate('a1', chong, 400000));
    await repo.addTransaction(expense('e1', chong, 100000));
    await repo.updateTransaction('e1', amountMinor: 150000); // thay dòng cũ bằng dòng mới (id mới)
    await repo.deleteTransaction('a1');
    final replaced = (await all()).firstWhere((t) => t.type == TransactionType.expense);
    await repo.deleteTransaction(replaced.id);
    final integrity = await db.customSelect('PRAGMA integrity_check').get();
    expect(integrity.single.data.values.single, 'ok');
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    for (final v in computeAllPoolBalances(await all()).values) {
      expect(v >= 0, isTrue);
    }
    final dup = await db.customSelect('SELECT client_tx_id FROM transaction_rows GROUP BY client_tx_id HAVING COUNT(*) > 1').get();
    expect(dup, isEmpty);
  });

  group('Hàm thuần: họ giao dịch / chặn / pool âm', () {
    domain.Transaction row(String id, {String? reversalOf, String? corrects, String? reversedBy}) => domain.Transaction(
      id: id,
      type: TransactionType.expense,
      categoryId: 'x',
      sourceKind: PoolKind.memberAvailable,
      sourceRefId: 'vo',
      destinationKind: PoolKind.external,
      amountMinor: 10,
      reversalOfTxId: reversalOf,
      correctsTxId: corrects,
      reversedByTxId: reversedBy,
      transactionDate: DateTime(2026, 9, 1),
      createdAt: DateTime(2026, 9, 1),
      clientTxId: 'k$id',
    );

    test('transactionFamilyIds: nối mọi hướng; không tồn tại → rỗng; không kéo dòng lạ', () {
      final list = [
        row('a', reversedBy: 'r'),
        row('r', reversalOf: 'a'),
        row('b', corrects: 'a'),
        row('lạ'),
      ];
      expect(transactionFamilyIds('b', list), {'a', 'r', 'b'});
      expect(transactionFamilyIds('r', list), {'a', 'r', 'b'});
      expect(transactionFamilyIds('lạ', list), {'lạ'});
      expect(transactionFamilyIds('khong', list), isEmpty);
    });
  });
}

extension on domain.Transaction {
  /// Dòng đang hiệu lực (không phải hoàn tác, chưa bị hoàn tác).
  bool get isVisibleHead => reversalOfTxId == null && reversedByTxId == null;
}
