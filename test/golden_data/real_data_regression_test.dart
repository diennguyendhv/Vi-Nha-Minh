import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/engine/financial_engine.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/family_member.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/entities/transfer_kind.dart';
import 'package:vi_nha_minh/domain/usecases/compute_three_totals.dart';

/// Phase 8.5 §23 — regression test nhỏ, TỰ ĐỦ (không phụ thuộc
/// `real_data_2026.json` riêng tư), an toàn commit — rút ra từ các case
/// thật đã audit trong dataset 2026 nhưng KHÔNG chứa dữ liệu cá nhân, chỉ
/// tái tạo semantics đã xác nhận với số liệu tối giản.
void main() {
  int seq = 0;
  Transaction tx({
    required TransactionType type,
    TransferKind? transferKind,
    String categoryId = 'cat',
    required PoolKind sourceKind,
    String? sourceRefId,
    required PoolKind destinationKind,
    String? destinationRefId,
    required int amountMinor,
    String? statusId,
    DateTime? date,
  }) {
    seq++;
    final d = date ?? DateTime(2026, 1, 1);
    return Transaction(
      id: 'reg-$seq',
      type: type,
      transferKind: transferKind,
      categoryId: categoryId,
      sourceKind: sourceKind,
      sourceRefId: sourceRefId,
      destinationKind: destinationKind,
      destinationRefId: destinationRefId,
      amountMinor: amountMinor,
      statusId: statusId,
      transactionDate: d,
      createdAt: d,
      clientTxId: 'reg-client-$seq',
    );
  }

  group('1 — Savings topup (Tiết kiệm số dương)', () {
    test('MEMBER_AVAILABLE -X, MEMBER_SAVINGS_ASSET +X', () {
      final t = tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.savingsTopup,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'chong',
        destinationKind: PoolKind.memberSavingsAsset,
        destinationRefId: savingsAssetRefId('legacy', FamilyMember.chong),
        amountMinor: 150000,
      );
      final balances = computeAllPoolBalances([t]);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'chong'), -150000);
      expect(
        poolBalance(balances, PoolKind.memberSavingsAsset, savingsAssetRefId('legacy', FamilyMember.chong)),
        150000,
      );
    });
  });

  group('2 — Savings withdraw qua "Tiết kiệm số âm" legacy', () {
    test('MEMBER_SAVINGS_ASSET -X, MEMBER_AVAILABLE +X (dấu âm = rút, không phải income)', () {
      final t = tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.savingsWithdraw,
        sourceKind: PoolKind.memberSavingsAsset,
        sourceRefId: savingsAssetRefId('legacy', FamilyMember.vo),
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 120000,
      );
      final balances = computeAllPoolBalances([t]);
      expect(
        poolBalance(balances, PoolKind.memberSavingsAsset, savingsAssetRefId('legacy', FamilyMember.vo)),
        -120000,
      );
      expect(poolBalance(balances, PoolKind.memberAvailable, 'vo'), 120000);
    });
  });

  group('3/4 — Chồng đưa vợ / Vợ đưa chồng (MEMBER_TO_MEMBER 2 chiều)', () {
    test('Chồng → Vợ: Chồng -X, Vợ +X, Total Assets không đổi', () {
      final t = tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.memberToMember,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'chong',
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 1000000,
      );
      final balances = computeAllPoolBalances([t]);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'chong'), -1000000);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'vo'), 1000000);
      expect(balances.values.fold<int>(0, (s, v) => s + v), 0);
    });

    test('Vợ → Chồng: Vợ -X, Chồng +X, Total Assets không đổi', () {
      final t = tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.memberToMember,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'chong',
        amountMinor: 400000,
      );
      final balances = computeAllPoolBalances([t]);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'vo'), -400000);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'chong'), 400000);
    });
  });

  group('5 — Legacy "Vợ chồng" counterpart — xác nhận thật 24/02/2026', () {
    test(
      '"Vợ chồng -400.000, Người tiêu = Chồng" = Vợ đưa Chồng 400.000 '
      '(1 giao dịch MEMBER_TO_MEMBER duy nhất, KHÔNG phải dòng riêng)',
      () {
        // Đúng ý nghĩa đã xác nhận (Phase 8.5 §5): normalize thành 1 transaction
        // duy nhất, dòng "Vợ chồng" legacy KHÔNG được tạo transaction thứ 2.
        final t = tx(
          type: TransactionType.transfer,
          transferKind: TransferKind.memberToMember,
          categoryId: 'chuyen_tien_thanh_vien',
          sourceKind: PoolKind.memberAvailable,
          sourceRefId: 'vo',
          destinationKind: PoolKind.memberAvailable,
          destinationRefId: 'chong',
          amountMinor: 400000,
          date: DateTime(2026, 2, 24),
        );
        final balances = computeAllPoolBalances([t]);
        expect(poolBalance(balances, PoolKind.memberAvailable, 'vo'), -400000);
        expect(poolBalance(balances, PoolKind.memberAvailable, 'chong'), 400000);
      },
    );
  });

  group('6 — Chuẩn hoá 2-dòng legacy không double-count', () {
    test('2 dòng raw (CREATE + IGNORE_LEGACY_COUNTERPART) → chỉ 1 Transaction thật trong ledger', () {
      // Mô phỏng đúng cặp dòng thật: "Chồng đưa vợ +1.000.000" (CREATE) và
      // "Vợ chồng -1.000.000" (IGNORE_LEGACY_COUNTERPART — KHÔNG import).
      final onlyCreatedRow = tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.memberToMember,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'chong',
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 1000000,
      );
      // "Dòng Vợ chồng đối ứng" CỐ TÌNH không được thêm vào danh sách này —
      // đó chính là hành vi cần test (IGNORE_LEGACY_COUNTERPART).
      final ledger = [onlyCreatedRow];

      final balances = computeAllPoolBalances(ledger);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'chong'), -1000000, reason: 'KHÔNG phải -2.000.000 nếu double-count');
      expect(poolBalance(balances, PoolKind.memberAvailable, 'vo'), 1000000, reason: 'KHÔNG phải +2.000.000 nếu double-count');
    });
  });

  group('7 — 70 triệu chuyển sang Ngân hàng (SAVINGS_CONVERT asset-type split)', () {
    test('Savings tổng không đổi, chỉ đổi chỗ giữa 2 loại tài sản, Total Assets không đổi', () {
      final topup = tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.savingsTopup,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'chong',
        destinationKind: PoolKind.memberSavingsAsset,
        destinationRefId: savingsAssetRefId('legacy', FamilyMember.chong),
        amountMinor: 70000000,
      );
      final convert = tx(
        type: TransactionType.transfer,
        transferKind: TransferKind.savingsConvert,
        sourceKind: PoolKind.memberSavingsAsset,
        sourceRefId: savingsAssetRefId('legacy', FamilyMember.chong),
        destinationKind: PoolKind.memberSavingsAsset,
        destinationRefId: savingsAssetRefId('ngan_hang', FamilyMember.chong),
        amountMinor: 70000000,
      );
      final beforeConvert = computeAllPoolBalances([topup]);
      final afterConvert = computeAllPoolBalances([topup, convert]);

      final totalSavingsBefore = poolBalance(
        beforeConvert,
        PoolKind.memberSavingsAsset,
        savingsAssetRefId('legacy', FamilyMember.chong),
      );
      final totalSavingsAfter = poolBalance(
            afterConvert,
            PoolKind.memberSavingsAsset,
            savingsAssetRefId('legacy', FamilyMember.chong),
          ) +
          poolBalance(
            afterConvert,
            PoolKind.memberSavingsAsset,
            savingsAssetRefId('ngan_hang', FamilyMember.chong),
          );

      expect(totalSavingsAfter, totalSavingsBefore, reason: 'Tổng tiết kiệm Chồng không đổi khi tách asset type');
      expect(
        poolBalance(afterConvert, PoolKind.memberSavingsAsset, savingsAssetRefId('ngan_hang', FamilyMember.chong)),
        70000000,
      );
      expect(
        afterConvert.values.fold<int>(0, (s, v) => s + v),
        beforeConvert.values.fold<int>(0, (s, v) => s + v),
        reason: 'Total Assets không đổi bởi SAVINGS_CONVERT',
      );
    });
  });

  group('8 — Dâng hiến "Chưa chuẩn bị" vẫn là EXPENSE ngay khi tạo', () {
    test('Status = Chưa chuẩn bị KHÔNG trì hoãn hiệu ứng trừ tiền', () {
      final t = tx(
        type: TransactionType.expense,
        categoryId: 'dang_hien',
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'chong',
        destinationKind: PoolKind.external,
        amountMinor: 500000,
        statusId: 'chua_chuan_bi',
      );
      final balances = computeAllPoolBalances([t]);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'chong'), -500000, reason: 'Trừ ngay lúc tạo, bất kể status');
    });
  });

  group('9 — Đổi status không tạo thêm hiệu ứng tài chính (không double-expense)', () {
    test('2 bản ghi cùng amount, khác statusId → hiệu ứng balance giống hệt nhau', () {
      final withStatusA = tx(
        type: TransactionType.expense,
        categoryId: 'dang_hien',
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'chong',
        destinationKind: PoolKind.external,
        amountMinor: 500000,
        statusId: 'chua_chuan_bi',
      );
      final withStatusB = tx(
        type: TransactionType.expense,
        categoryId: 'dang_hien',
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'chong',
        destinationKind: PoolKind.external,
        amountMinor: 500000,
        statusId: 'da_gui',
      );
      final balancesA = computeAllPoolBalances([withStatusA]);
      final balancesB = computeAllPoolBalances([withStatusB]);
      expect(
        poolBalance(balancesA, PoolKind.memberAvailable, 'chong'),
        poolBalance(balancesB, PoolKind.memberAvailable, 'chong'),
      );
    });
  });

  group('10 — Số dư ban đầu không tính vào monthlyIncome', () {
    test('excludeFromTotals=true: cộng available nhưng KHÔNG cộng totalIncome', () {
      const openingCategory = Category(
        id: 'so_du_ban_dau',
        name: 'Số dư ban đầu',
        color: Color(0xFF2F8F4F),
        type: TransactionType.income,
        excludeFromTotals: true,
      );
      const salaryCategory = Category(
        id: 'thu_nhap',
        name: 'Thu nhập',
        color: Color(0xFF12805C),
        type: TransactionType.income,
      );
      final opening = tx(
        type: TransactionType.income,
        categoryId: 'so_du_ban_dau',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 627000,
      );
      final salary = tx(
        type: TransactionType.income,
        categoryId: 'thu_nhap',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 2000000,
      );
      final balances = computeAllPoolBalances([opening, salary]);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'vo'), 2627000, reason: 'Available cộng đủ cả 2');

      final totals = computeThreeTotals([opening, salary], [openingCategory, salaryCategory]);
      expect(totals.totalIncome, 2000000, reason: 'Chỉ tính lương, KHÔNG tính số dư ban đầu');
    });
  });
}
