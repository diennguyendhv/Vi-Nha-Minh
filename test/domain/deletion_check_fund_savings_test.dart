import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/family_member.dart';
import 'package:vi_nha_minh/domain/entities/fund.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/savings_asset_type.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/entities/transfer_kind.dart';
import 'package:vi_nha_minh/domain/usecases/compute_deletable_master_data.dart';
import 'package:vi_nha_minh/domain/usecases/deletion_check.dart';

/// Quỹ / Loại tiết kiệm dùng CÙNG mô hình blocker với Danh mục / Trạng thái:
/// xóa hẳn được khi hết dấu vết; không thì chỉ rõ số dư còn lại và/hoặc từng
/// giao dịch đang giữ. Chỉ "Chưa phân bổ" là hạ tầng (systemProtected).
final _cats = [
  Category(id: 'nap_quy', name: 'Nạp quỹ', color: Colors.grey, type: TransactionType.transfer),
  Category(id: 'tiet_kiem', name: 'Tiết kiệm', color: Colors.grey, type: TransactionType.transfer),
  Category(id: 'sinh_hoat', name: 'Sinh hoạt', color: Colors.grey, type: TransactionType.expense),
];

int _n = 0;
Transaction _tx({
  required TransactionType type,
  required String category,
  required PoolKind from,
  String? fromRef,
  required PoolKind to,
  String? toRef,
  required int amount,
  TransferKind? kind,
  DateTime? date,
  String? reversedBy,
  String? reversalOf,
}) {
  _n++;
  final d = date ?? DateTime(2026, 9, 10);
  return Transaction(
    id: 't$_n',
    type: type,
    transferKind: kind,
    categoryId: category,
    sourceKind: from,
    sourceRefId: fromRef,
    destinationKind: to,
    destinationRefId: toRef,
    amountMinor: amount,
    transactionDate: d,
    createdAt: d,
    clientTxId: 'c$_n',
    reversedByTxId: reversedBy,
    reversalOfTxId: reversalOf,
  );
}

Transaction _fundTopup(String fund, int amount, {DateTime? date}) => _tx(
  type: TransactionType.transfer,
  kind: TransferKind.fundTopup,
  category: 'nap_quy',
  from: PoolKind.memberAvailable,
  fromRef: 'vo',
  to: PoolKind.fund,
  toRef: fund,
  amount: amount,
  date: date,
);

Transaction _fundSpend(String fund, int amount) => _tx(
  type: TransactionType.expense,
  category: 'sinh_hoat',
  from: PoolKind.fund,
  fromRef: fund,
  to: PoolKind.external,
  amount: amount,
);

Transaction _savingsIn(String asset, FamilyMember m, int amount) => _tx(
  type: TransactionType.transfer,
  kind: TransferKind.savingsConvert,
  category: 'tiet_kiem',
  from: PoolKind.memberSavingsAsset,
  fromRef: savingsAssetRefId(SystemSavingsAssets.unallocatedId, m),
  to: PoolKind.memberSavingsAsset,
  toRef: savingsAssetRefId(asset, m),
  amount: amount,
);

void main() {
  group('Blocker giao dịch hiện đúng thành viên (dùng chung cho Danh mục / Trạng thái / Quỹ / Loại tiết kiệm)', () {
    test('Quỹ: nạp bởi Vợ → "Vợ"; giao dịch chi từ quỹ (không thuộc thành viên) → null', () {
      final r = checkFundDeletion('q1', _cats, [_fundTopup('q1', 100000), _fundSpend('q1', 30000)]);
      expect(r.transactionBlockers.map((b) => b.memberLabel), containsAll(<String?>['Vợ', null]));
    });

    test('Loại tiết kiệm: Vợ và Chồng đều hiện đúng tên', () {
      final ledger = [
        _savingsIn('vang', FamilyMember.vo, 100000),
        _savingsIn('vang', FamilyMember.chong, 200000),
      ];
      final r = checkSavingsAssetDeletion('vang', _cats, ledger);
      final byAmount = {for (final b in r.transactionBlockers) b.amountMinor: b.memberLabel};
      expect(byAmount[100000], 'Vợ');
      expect(byAmount[200000], 'Chồng');
    });

    test('Danh mục: chi của Chồng → "Chồng"; của Vợ → "Vợ"', () {
      final wife = _tx(
        type: TransactionType.expense, category: 'sinh_hoat',
        from: PoolKind.memberAvailable, fromRef: 'vo', to: PoolKind.external, amount: 1000,
      );
      final husband = _tx(
        type: TransactionType.expense, category: 'sinh_hoat',
        from: PoolKind.memberAvailable, fromRef: 'chong', to: PoolKind.external, amount: 2000,
      );
      final cat = _cats.firstWhere((c) => c.id == 'sinh_hoat');
      final r = checkCategoryDeletion(cat, _cats, [wife, husband]);
      final byAmount = {for (final b in r.transactionBlockers) b.amountMinor: b.memberLabel};
      expect(byAmount[1000], 'Vợ');
      expect(byAmount[2000], 'Chồng');
    });
  });

  group('Quỹ', () {
    test('Không giao dịch nào chạm quỹ → xóa hẳn được (KHÔNG có quỹ "hệ thống", kể cả Quỹ tiền ăn mặc định)', () {
      expect(checkFundDeletion('an_uong', _cats, const []).canDelete, isTrue);
      expect(checkFundDeletion('an_uong', _cats, const []).isSystemProtected, isFalse);
    });

    test('Còn tiền → blocker số dư CHÍNH XÁC + blocker giao dịch (mở được)', () {
      final ledger = [_fundTopup('q1', 100000), _fundSpend('q1', 80000)];
      final r = checkFundDeletion('q1', _cats, ledger);
      expect(r.canDelete, isFalse);
      expect(r.remainingBalance, 20000);
      expect(r.transactionBlockers.length, 2);
      // Blocker số dư đứng TRƯỚC giao dịch.
      expect(r.blockers.first.kind, DeletionBlockerKind.balance);
    });

    test('Hết tiền nhưng còn giao dịch → chỉ blocker giao dịch (không blocker số dư)', () {
      final ledger = [_fundTopup('q1', 100000), _fundSpend('q1', 100000)];
      final r = checkFundDeletion('q1', _cats, ledger);
      expect(r.remainingBalance, isNull);
      expect(r.transactionBlockers.length, 2);
      expect(r.canDelete, isFalse);
    });

    test('Xóa giao dịch cuối cùng của quỹ → xóa hẳn được NGAY; giao dịch quỹ khác không cản', () {
      final other = _fundTopup('q2', 5000);
      final only = _fundTopup('q1', 1000);
      expect(checkFundDeletion('q1', _cats, [only, other]).canDelete, isFalse);
      expect(checkFundDeletion('q1', _cats, [other]).canDelete, isTrue);
    });

    test('Blocker mang đúng ngày/số tiền/tên danh mục để hiện "12/09 · 100.000 đ · Nạp quỹ"', () {
      final t = _fundTopup('q1', 100000, date: DateTime(2026, 9, 12));
      final b = checkFundDeletion('q1', _cats, [t]).transactionBlockers.single;
      expect(b.transactionId, t.id);
      expect(b.date, DateTime(2026, 9, 12));
      expect(b.amountMinor, 100000);
      expect(b.categoryName, 'Nạp quỹ');
    });

    test('computeDeletableFundIds: chỉ quỹ ĐÃ NGỪNG và sạch dấu vết', () {
      const active = Fund(id: 'a', name: 'A', color: Colors.teal);
      const stoppedClean = Fund(id: 'b', name: 'B', color: Colors.teal, isActive: false);
      const stoppedUsed = Fund(id: 'c', name: 'C', color: Colors.teal, isActive: false);
      final ids = computeDeletableFundIds(
        [active, stoppedClean, stoppedUsed],
        _cats,
        [_fundTopup('c', 1)],
      );
      expect(ids, {'b'});
    });
  });

  group('Loại tiết kiệm', () {
    test('"Chưa phân bổ" là hạ tầng: systemProtected, không bao giờ xóa hẳn được', () {
      final r = checkSavingsAssetDeletion(SystemSavingsAssets.unallocatedId, _cats, const []);
      expect(r.isSystemProtected, isTrue);
      expect(r.canDelete, isFalse);
    });

    test('Loại thường chưa từng dùng → xóa hẳn được', () {
      expect(checkSavingsAssetDeletion('savings_gold', _cats, const []).canDelete, isTrue);
    });

    test('Còn tiền (cộng cả Vợ và Chồng) → blocker số dư đúng số tiền + giao dịch giữ', () {
      final ledger = [
        _savingsIn('savings_gold', FamilyMember.vo, 300000),
        _savingsIn('savings_gold', FamilyMember.chong, 200000),
      ];
      final r = checkSavingsAssetDeletion('savings_gold', _cats, ledger);
      expect(r.remainingBalance, 500000);
      expect(r.transactionBlockers.length, 2);
    });

    test('Số dư 0 nhưng còn giao dịch (vào rồi ra) → blocker giao dịch; xóa các giao dịch đó → xóa được', () {
      final into = _savingsIn('savings_gold', FamilyMember.chong, 1000);
      final out = _tx(
        type: TransactionType.transfer,
        kind: TransferKind.savingsConvert,
        category: 'tiet_kiem',
        from: PoolKind.memberSavingsAsset,
        fromRef: savingsAssetRefId('savings_gold', FamilyMember.chong),
        to: PoolKind.memberSavingsAsset,
        toRef: savingsAssetRefId(SystemSavingsAssets.unallocatedId, FamilyMember.chong),
        amount: 1000,
      );
      final r = checkSavingsAssetDeletion('savings_gold', _cats, [into, out]);
      expect(r.remainingBalance, isNull);
      expect(r.transactionBlockers.length, 2);
      expect(checkSavingsAssetDeletion('savings_gold', _cats, const []).canDelete, isTrue);
    });

    test('Giao dịch của loại KHÁC không cản; tiền tố tên giống nhau không nhầm', () {
      final other = _savingsIn('savings_gold_2', FamilyMember.vo, 1000);
      expect(checkSavingsAssetDeletion('savings_gold', _cats, [other]).canDelete, isTrue);
    });
  });
}
