import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/constants/default_savings_asset_types.dart';
import 'package:vi_nha_minh/domain/entities/family_member.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/savings_asset_type.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/usecases/compute_member_financials.dart';
import 'package:vi_nha_minh/domain/usecases/compute_savings_breakdown.dart';

int _n = 0;

Transaction _into(FamilyMember m, String asset, int amount) {
  _n++;
  return Transaction(
    id: 'x$_n',
    type: TransactionType.income,
    categoryId: 'so_du_ban_dau',
    sourceKind: PoolKind.external,
    destinationKind: PoolKind.memberSavingsAsset,
    destinationRefId: savingsAssetRefId(asset, m),
    amountMinor: amount,
    transactionDate: DateTime(2026, 9, 1),
    createdAt: DateTime(2026, 9, 1),
    clientTxId: 'k$_n',
  );
}

void main() {
  const vo = FamilyMember.vo;
  const chong = FamilyMember.chong;
  final types = List<SavingsAssetType>.of(DefaultSavingsAssetTypes.all);

  test('"Chưa phân bổ" luôn ở đầu (kể cả 0) rồi tới các loại đang dùng theo thứ tự', () {
    final b = computeMemberSavingsBreakdown(vo, const [], types);
    expect(b.total, 0);
    expect(b.rows.first.assetTypeId, SystemSavingsAssets.unallocatedId);
    expect(b.rows.first.asset?.name, 'Chưa phân bổ');
    expect(b.rows.map((r) => r.assetTypeId).skip(1), types.map((t) => t.id));
    expect(b.rows.every((r) => !r.isInactive), isTrue);
  });

  test('Tổng = tổng mọi pool của thành viên = tổng các dòng; cùng nguồn với Trang chủ', () {
    final ledger = [
      _into(vo, SystemSavingsAssets.unallocatedId, 400000),
      _into(vo, DefaultSavingsAssetTypes.bankId, 700000),
      _into(vo, DefaultSavingsAssetTypes.goldId, 100000),
      _into(chong, DefaultSavingsAssetTypes.bankId, 9000000),
    ];
    final b = computeMemberSavingsBreakdown(vo, ledger, types);
    expect(b.total, 1200000);
    expect(b.rows.fold<int>(0, (a, r) => a + r.balance), b.total, reason: 'không có tiền nào không hiện');
    expect(computeMemberFinancials(vo, ledger).savingsTotal, b.total, reason: 'Home = Savings Total tầng 1');
    // Vợ / Chồng tách riêng.
    expect(computeMemberSavingsBreakdown(chong, ledger, types).total, 9000000);
  });

  test('Loại ĐÃ NGỪNG: số dư 0 → ẩn; còn số dư → hiện + đánh dấu ngừng sử dụng', () {
    final stopped = [
      for (final t in types)
        t.id == DefaultSavingsAssetTypes.goldId || t.id == DefaultSavingsAssetTypes.otherId
            ? t.copyWith(isActive: false)
            : t,
    ];
    final ledger = [_into(vo, DefaultSavingsAssetTypes.goldId, 250000)];
    final b = computeMemberSavingsBreakdown(vo, ledger, stopped);
    final ids = b.rows.map((r) => r.assetTypeId).toList();
    expect(ids, contains(DefaultSavingsAssetTypes.goldId), reason: 'ngừng nhưng còn tiền → phải thấy');
    expect(ids, isNot(contains(DefaultSavingsAssetTypes.otherId)), reason: 'ngừng và 0 → ẩn');
    final gold = b.rows.firstWhere((r) => r.assetTypeId == DefaultSavingsAssetTypes.goldId);
    expect(gold.isInactive, isTrue);
    expect(gold.balance, 250000);
    expect(b.total, 250000);
  });

  test('Pool mồ côi (không có định nghĩa loại) còn số dư vẫn hiện; số dư 0 thì không', () {
    final ledger = [
      _into(vo, 'loai_da_xoa', 80000),
      _into(vo, 'loai_rong', 5000),
      _into(vo, 'loai_rong', -5000).copyWithAmount(5000, reverse: true),
    ];
    final b = computeMemberSavingsBreakdown(vo, ledger, types);
    final orphan = b.rows.where((r) => r.asset == null).toList();
    expect(orphan.map((r) => r.assetTypeId), ['loai_da_xoa']);
    expect(orphan.single.isInactive, isTrue);
    expect(b.rows.fold<int>(0, (a, r) => a + r.balance), b.total);
  });

  test('resolveSavingsAsset: id hệ thống → bản ảo (không cần dòng DB); id thường tra DB; lạ → null', () {
    expect(resolveSavingsAsset(SystemSavingsAssets.unallocatedId, const [])?.name, 'Chưa phân bổ');
    expect(resolveSavingsAsset(DefaultSavingsAssetTypes.bankId, types)?.name, 'Gửi ngân hàng');
    expect(resolveSavingsAsset('khong_co', types), isNull);
    // Loại đã ngừng vẫn resolve được tên (lịch sử).
    final stopped = [types.first.copyWith(isActive: false)];
    expect(resolveSavingsAsset(types.first.id, stopped)?.name, types.first.name);
    expect(SystemSavingsAssets.isSystem(SystemSavingsAssets.unallocatedId), isTrue);
    expect(SystemSavingsAssets.isSystem(DefaultSavingsAssetTypes.bankId), isFalse);
    expect(const Color(0xFF000000), isA<Color>());
  });

  test('Xoá hẳn hiển thị: chỉ loại ĐÃ NGỪNG + CHƯA TỪNG có giao dịch (kể cả đã hoàn tác); loại vừa tạo rồi ngừng có ngay', () {
    final gold = types.firstWhere((t) => t.id == DefaultSavingsAssetTypes.goldId).copyWith(isActive: false);
    final stocks = types.firstWhere((t) => t.id == DefaultSavingsAssetTypes.stocksId).copyWith(isActive: false);
    final fresh = const SavingsAssetType(id: 'moi_tao', name: 'Mới', color: Color(0xFF000000), isActive: false);
    final active = types.firstWhere((t) => t.id == DefaultSavingsAssetTypes.bankId);
    // Vàng từng dùng (vào rồi ra, số dư 0) — giống giao dịch đã hoàn tác.
    final ledger = [
      _into(vo, DefaultSavingsAssetTypes.goldId, 100),
      _into(vo, DefaultSavingsAssetTypes.goldId, -100).copyWithAmount(100, reverse: true),
    ];
    final deletable = computeDeletableAssetTypeIds([gold, stocks, fresh, active], ledger);
    expect(deletable, {DefaultSavingsAssetTypes.stocksId, 'moi_tao'});
    expect(deletable, isNot(contains(DefaultSavingsAssetTypes.goldId)), reason: 'đã dùng');
    expect(deletable, isNot(contains(DefaultSavingsAssetTypes.bankId)), reason: 'còn đang dùng');
    expect(savingsAssetTypeIdsInLedger(ledger), {DefaultSavingsAssetTypes.goldId});
    // Hệ thống không bao giờ nằm trong danh sách.
    expect(
      computeDeletableAssetTypeIds([SystemSavingsAssets.unallocated.copyWith(isActive: false)], const []),
      isEmpty,
    );
  });
}


extension on Transaction {
  /// Bản đảo chiều (giả lập hoàn tác) để pool về 0 — chỉ dùng trong test này.
  Transaction copyWithAmount(int amount, {required bool reverse}) {
    _n++;
    return Transaction(
      id: 'r$_n',
      type: TransactionType.expense,
      categoryId: categoryId,
      sourceKind: destinationKind,
      sourceRefId: destinationRefId,
      destinationKind: PoolKind.external,
      amountMinor: amount,
      transactionDate: transactionDate,
      createdAt: createdAt,
      clientTxId: 'kr$_n',
    );
  }
}
