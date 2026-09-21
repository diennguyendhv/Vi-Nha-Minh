import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/constants/default_categories.dart';
import 'package:vi_nha_minh/core/utils/opaque_id.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/repositories/local_member_repository.dart';
import 'package:vi_nha_minh/data/repositories/local_transaction_repository.dart';
import 'package:vi_nha_minh/domain/entities/member_directory.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/entities/transfer_kind.dart';
import 'package:vi_nha_minh/domain/entities/wallet_identity.dart';
import 'package:vi_nha_minh/domain/usecases/compute_financial_summary.dart';
import 'package:vi_nha_minh/domain/usecases/compute_grouped_totals.dart';
import 'package:vi_nha_minh/domain/usecases/compute_member_financials.dart';
import 'package:vi_nha_minh/domain/usecases/compute_pool_balance.dart';
import 'package:vi_nha_minh/domain/usecases/compute_reportable_income.dart';
import 'package:vi_nha_minh/domain/usecases/explore_transactions.dart';
import 'package:vi_nha_minh/domain/usecases/transaction_member_label.dart';

import '../support/legacy_members.dart';

/// P4 — FinancialMember là dữ liệu: mọi logic tài chính chạy với `memberId` MỜ, nhãn
/// "Vợ"/"Chồng" chỉ là dữ liệu, không suy ra từ chuỗi id.
const _idWife = '5b0f6c1e-2a34-4c5d-8e7f-1a2b3c4d5e6f';
const _idHusband = '9d8c7b6a-5f4e-4d3c-a2b1-0f9e8d7c6b5a';
const _opaque = [
  FinancialMember(memberId: _idWife, label: 'Vợ', displayOrder: 0),
  FinancialMember(memberId: _idHusband, label: 'Chồng', displayOrder: 1),
];

var _seq = 0;
Transaction _tx({
  required TransactionType type,
  required String categoryId,
  required PoolKind from,
  String? fromRef,
  required PoolKind to,
  String? toRef,
  required int amount,
  TransferKind? transferKind,
}) {
  _seq++;
  return Transaction(
    id: 't$_seq',
    type: type,
    transferKind: transferKind,
    categoryId: categoryId,
    sourceKind: from,
    sourceRefId: fromRef,
    destinationKind: to,
    destinationRefId: toRef,
    amountMinor: amount,
    transactionDate: DateTime(2026, 9, 10),
    createdAt: DateTime(2026, 9, 10),
    clientTxId: 'c$_seq',
  );
}

Transaction _income(String member, int amount) => _tx(
  type: TransactionType.income,
  categoryId: DefaultCategories.thuNhap.id,
  from: PoolKind.external,
  to: PoolKind.memberAvailable,
  toRef: member,
  amount: amount,
);

Transaction _expense(String member, int amount) => _tx(
  type: TransactionType.expense,
  categoryId: DefaultCategories.sinhHoat.id,
  from: PoolKind.memberAvailable,
  fromRef: member,
  to: PoolKind.external,
  amount: amount,
);

Transaction _savingsTopup(String member, String asset, int amount) => _tx(
  type: TransactionType.transfer,
  transferKind: TransferKind.savingsTopup,
  categoryId: DefaultCategories.tietKiem.id,
  from: PoolKind.memberAvailable,
  fromRef: member,
  to: PoolKind.memberSavingsAsset,
  toRef: savingsAssetRefId(asset, member),
  amount: amount,
);

void main() {
  group('MemberDirectory', () {
    test('tra theo memberId, nhãn là dữ liệu; ID lạ → null (không đoán)', () {
      final d = MemberDirectory(_opaque);
      expect(d.byId(_idWife)!.label, 'Vợ');
      expect(d.labelOf(_idHusband), 'Chồng');
      expect(d.labelOf('vo'), isNull, reason: 'nhãn KHÔNG suy ra từ chuỗi memberId');
      expect(d.labelOf('khong-ton-tai'), isNull);
      expect(d.contains(null), isFalse);
      expect(d.ids, [_idWife, _idHusband]);
    });

    test('mặc định = người đầu tiên; ID lạ/null rơi về mặc định; rỗng → null', () {
      final d = MemberDirectory(_opaque);
      expect(d.defaultMemberId, _idWife);
      expect(d.resolveOrDefault(_idHusband), _idHusband);
      expect(d.resolveOrDefault('la'), _idWife);
      expect(d.resolveOrDefault(null), _idWife);
      expect(MemberDirectory.empty.defaultMemberId, isNull);
      expect(MemberDirectory.empty.resolveOrDefault('x'), isNull);
    });

    test('"người còn lại" suy ra từ dữ liệu, chỉ khi ĐÚNG 2 thành viên', () {
      final d = MemberDirectory(_opaque);
      expect(d.otherThan(_idWife), _idHusband);
      expect(d.otherThan(_idHusband), _idWife);
      expect(d.otherThan('la'), isNull);
      expect(MemberDirectory(_opaque.take(1)).otherThan(_idWife), isNull);
      final three = MemberDirectory([
        ..._opaque,
        const FinancialMember(memberId: 'c', label: 'Con', displayOrder: 2),
      ]);
      expect(three.otherThan(_idWife), isNull, reason: 'không đoán khi có ≠ 2 thành viên');
      expect(three.firstOtherThan(_idWife), _idHusband);
      expect(MemberDirectory(_opaque.take(1)).firstOtherThan(_idWife), isNull);
    });
  });

  group('Financial Core với memberId mờ + nhãn "Vợ" (KHÔNG cần memberId == "vo")', () {
    final ledger = [
      _income(_idWife, 5000000),
      _income(_idHusband, 3000000),
      _expense(_idWife, 1000000),
      _tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.memberToMember,
        categoryId: DefaultCategories.chuyenTienThanhVien.id,
        from: PoolKind.memberAvailable,
        fromRef: _idHusband,
        to: PoolKind.memberAvailable,
        toRef: _idWife,
        amount: 500000,
      ),
      _savingsTopup(_idWife, 'savings_unallocated', 700000),
    ];

    test('số dư/tiết kiệm từng người đúng', () {
      final w = computeMemberFinancials(_idWife, ledger);
      final h = computeMemberFinancials(_idHusband, ledger);
      // Vợ: +5tr −1tr +0,5tr (nhận) −0,7tr (gửi tiết kiệm) = 3,8tr; Chồng: 3tr − 0,5tr = 2,5tr.
      expect(w.balance, 3800000);
      expect(w.savingsTotal, 700000);
      expect(w.savingsUnallocated, 700000);
      expect(h.balance, 2500000);
      expect(h.savingsTotal, 0);
      expect(w.memberId, _idWife);
    });

    test('computeFinancialSummary lặp theo danh sách thành viên truyền vào (dữ liệu)', () {
      final s = computeFinancialSummary(
        ledger,
        categories: DefaultCategories.all,
        funds: const [],
        assetTypes: const [],
        members: _opaque,
      );
      expect(s.availableByMember.keys, [_idWife, _idHusband]);
      expect(s.availableByMember[_idWife], 3800000);
      expect(s.totalAvailable, 6300000);
      expect(s.totalSavings, 700000, reason: 'tổng quét thẳng ledger, độc lập danh sách thành viên');
    });

    test('người chi / người nhận / lọc theo memberId', () {
      expect(expenseSpender(ledger[2]), _idWife);
      expect(incomeRecipient(ledger[0]), _idWife);
      expect(expenseSpender(ledger[4]), _idWife);
      expect(incomeRecipient(ledger[4]), _idWife, reason: 'đích là pool tiết kiệm của Vợ');
      final byWife = computeGroupedTotals(ledger, DefaultCategories.all, memberId: _idWife);
      final byHusband = computeGroupedTotals(ledger, DefaultCategories.all, memberId: _idHusband);
      expect(byWife.revenue, 5000000);
      expect(byHusband.revenue, 3000000);
      final r = exploreTransactions(
        ledger,
        DefaultCategories.all,
        const TransactionFilter(memberId: _idHusband),
        hiddenCategoryIds: const {},
      );
      expect(r.rows.map((t) => t.id), containsAll([ledger[1].id, ledger[3].id]));
      expect(r.rows.any((t) => t.id == ledger[0].id), isFalse);
      expect(computeMemberNetIncome(_idWife, ledger, DefaultCategories.all), 5000000);
    });

    test('nhãn giao dịch lấy từ DỮ LIỆU; ID lạ → không nhãn (an toàn)', () {
      expect(transactionMemberLabel(ledger[3], _opaque), 'Chồng → Vợ');
      expect(transactionMemberLabel(ledger[4], _opaque), 'Vợ', reason: 'nạp tiết kiệm cùng 1 người → 1 tên');
      expect(transactionMemberLabel(ledger[0], legacyMembers), isNull, reason: 'id mờ không có trong danh sách di sản');
      expect(transactionMemberLabel(ledger[0], const []), isNull);
    });

    test('savingsAssetRefId round-trip với memberId mờ; refId hỏng → null', () {
      final ref = savingsAssetRefId('savings_gold', _idHusband);
      final p = parseSavingsAssetRefId(ref)!;
      expect(p.assetTypeId, 'savings_gold');
      expect(p.memberId, _idHusband);
      expect(parseSavingsAssetRefId('khong-co-dau-phan-cach'), isNull);
      expect(parseSavingsAssetRefId('a|b|c'), isNull);
      expect(parseSavingsAssetRefId('|x'), isNull);
    });

    test('số dư loại tiết kiệm cộng dồn mọi thành viên, không cần danh sách thành viên', () {
      final l = [
        _income(_idWife, 1000000),
        _income(_idHusband, 1000000),
        _savingsTopup(_idWife, 'gold', 300000),
        _savingsTopup(_idHusband, 'gold', 200000),
      ];
      expect(computeSavingsAssetTypeBalance('gold', l), 500000);
      expect(computeSavingsAssetTypeBalance('bank', l), 0);
    });
  });

  group('LocalMemberRepository', () {
    late AppDatabase db;
    late LocalMemberRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LocalMemberRepository(db);
    });
    tearDown(() => db.close());

    test('Wallet di sản: vo/chong theo displayOrder, tra theo memberId, ID lạ → null', () async {
      final ms = await repo.getMembers();
      expect(ms.map((m) => (m.memberId, m.label, m.displayOrder)), [('vo', 'Vợ', 0), ('chong', 'Chồng', 1)]);
      expect((await repo.getMemberById('chong'))!.label, 'Chồng');
      expect(await repo.getMemberById('la'), isNull);
    });

    test('thứ tự xác định theo displayOrder dù chèn ngược', () async {
      await db.delete(db.financialMemberRows).go();
      final now = DateTime.now();
      for (final (id, label, order) in [('b', 'B', 2), ('a', 'A', 0), ('c', 'C', 1)]) {
        await db.into(db.financialMemberRows).insert(
          FinancialMemberRowsCompanion.insert(memberId: id, label: label, displayOrder: order, createdAt: now),
        );
      }
      expect((await repo.getMembers()).map((m) => m.memberId), ['a', 'c', 'b']);
      expect((await repo.watchMembers().first).map((m) => m.memberId), ['a', 'c', 'b']);
    });

    test('createMember: ID mờ (không suy từ nhãn), nối cuối, KHÔNG đổi dòng hiện có', () async {
      final before = await db.select(db.financialMemberRows).get();
      final created = await repo.createMember(label: 'Vợ');
      expect(OpaqueId.isValid(created.memberId), isTrue);
      expect(created.memberId, isNot(anyOf('vo', 'chong')));
      expect(created.displayOrder, 2);
      final after = await db.select(db.financialMemberRows).get();
      expect(after, hasLength(3));
      for (final b in before) {
        expect(after.firstWhere((a) => a.memberId == b.memberId), b, reason: 'dòng cũ giữ nguyên field-for-field');
      }
      final second = await repo.createMember(label: 'Vợ');
      expect(second.memberId, isNot(created.memberId), reason: 'cùng nhãn vẫn là danh tính khác');
    });

    test('thành viên ID mờ ghi/đọc giao dịch qua repository thật, số dư đúng', () async {
      final m = await repo.createMember(label: 'Vợ');
      final txRepo = LocalTransactionRepository(db);
      await txRepo.addTransaction(_income(m.memberId, 1234000));
      final all = await txRepo.watchTransactions().first;
      expect(computeMemberAvailableBalance(m.memberId, all), 1234000);
      expect(computeMemberAvailableBalance('vo', all), 0);
    });
  });
}
