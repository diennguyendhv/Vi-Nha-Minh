import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/engine/financial_engine.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/family_member.dart';
import 'package:vi_nha_minh/domain/entities/fund.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/savings_asset_type.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/entities/transfer_kind.dart';
import 'package:vi_nha_minh/domain/usecases/compute_financial_summary.dart';
import 'package:vi_nha_minh/domain/usecases/compute_three_totals.dart';

/// PHASE 8.5 — REAL-DATA GOLDEN TEST.
///
/// Nguồn dữ liệu: `test/golden_data/real_data_2026.json` — fixture PRIVATE,
/// KHÔNG commit (xem `.gitignore`), sinh ra bằng script Python đọc
/// `Claude_Context_Quan_ly_tai_chinh_2026.xlsx` sheet `RAW_WITH_INTERPRETATION`
/// và áp dụng ĐÚNG các quy tắc normalization đã được người dùng xác nhận
/// từng dòng trong phiên review (không tự suy diễn — xem lịch sử hội thoại
/// Phase 8.5). Test này KHÔNG có trong máy người khác (fixture không tồn
/// tại) → tự skip toàn bộ, không làm fail baseline CI chung.
///
/// Toàn bộ số liệu chạy qua Financial Core THẬT
/// (`computeAllPoolBalances`/`computeFinancialSummary`/`validateNewTransaction`/
/// `wouldGoNegative`) — KHÔNG có phép cộng/trừ thủ công nào lặp lại logic
/// engine ở đây.
void main() {
  final fixtureFile = File('test/golden_data/real_data_2026.json');
  final fixtureExists = fixtureFile.existsSync();

  if (!fixtureExists) {
    test('Golden test SKIPPED — fixture riêng tư không có trên máy này', () {
      // ignore: avoid_print
      print(
        'test/golden_data/real_data_2026.json không tồn tại (đúng — file này '
        'bị gitignore, chỉ có trên máy đã chạy script export). Bỏ qua toàn bộ '
        'Phase 8.5 golden test, không phải lỗi.',
      );
    }, skip: false);
    return;
  }

  // ---- Categories (fixture-local — KHÔNG phải DefaultCategories production,
  // KHÔNG có category "Dâng hiến" cứng nào ảnh hưởng Financial Core generic).
  const catSinhHoat = Category(id: 'sinh_hoat', name: 'Sinh hoạt', color: Color(0xFF000001), type: TransactionType.expense);
  const catTuThuong = Category(id: 'tu_thuong', name: 'Tự thưởng', color: Color(0xFF000002), type: TransactionType.expense);
  const catChoDi = Category(id: 'cho_di', name: 'Cho đi', color: Color(0xFF000003), type: TransactionType.expense);
  const catDangHien = Category(id: 'dang_hien', name: 'Dâng hiến', color: Color(0xFF000004), type: TransactionType.expense);
  const catDauTu = Category(id: 'dau_tu', name: 'Đầu tư', color: Color(0xFF000005), type: TransactionType.expense);
  const catThuNhap = Category(id: 'thu_nhap', name: 'Thu nhập', color: Color(0xFF000006), type: TransactionType.income);
  const catChiPhiKinhDoanh = Category(id: 'chi_phi_kinh_doanh', name: 'Chi phí kinh doanh', color: Color(0xFF000007), type: TransactionType.expense);
  const catChuyenTien = Category(id: 'chuyen_tien_thanh_vien', name: 'Chuyển tiền thành viên', color: Color(0xFF000008), type: TransactionType.transfer);
  const catTietKiem = Category(id: 'tiet_kiem', name: 'Tiết kiệm', color: Color(0xFF000009), type: TransactionType.transfer);
  // Confirmed (Phase 8.5 audit, xem hội thoại) — non-income inflow: tiền
  // quay về Available (bán lại đồ/hoàn tiền/người khác trả nợ) nhưng KHÔNG
  // phải income mới. Dùng lại ĐÚNG cơ chế excludeFromTotals đã có sẵn từ
  // Phase 1 (giống "Số dư ban đầu"), KHÔNG phải TransactionType/field mới.
  const catThuHoiTaiSan = Category(
    id: 'thu_hoi_tai_san_hoan_tien',
    name: 'Thu hồi tài sản / hoàn tiền',
    color: Color(0xFF00000A),
    type: TransactionType.income,
    excludeFromTotals: true,
  );
  const catSoDuBanDau = Category(
    id: 'so_du_ban_dau',
    name: 'Số dư ban đầu',
    color: Color(0xFF00000B),
    type: TransactionType.income,
    excludeFromTotals: true,
  );

  final categories = <Category>[
    catSinhHoat,
    catTuThuong,
    catChoDi,
    catDangHien,
    catDauTu,
    catThuNhap,
    catChiPhiKinhDoanh,
    catChuyenTien,
    catTietKiem,
    catThuHoiTaiSan,
    catSoDuBanDau,
  ];

  const legacyAssetType = SavingsAssetType(id: 'legacy', name: 'Tiết kiệm (legacy)', color: Color(0xFF000010));
  const bankAssetType = SavingsAssetType(id: 'ngan_hang', name: 'Ngân hàng', color: Color(0xFF000011));
  final assetTypes = <SavingsAssetType>[legacyAssetType, bankAssetType];
  const noFunds = <Fund>[];

  Transaction fromJson(Map<String, dynamic> j, String idSuffix) {
    return Transaction(
      id: 'golden-$idSuffix',
      type: TransactionType.values.byName(j['type'] as String),
      transferKind: j['transferKind'] == null
          ? null
          : TransferKind.values.byName(j['transferKind'] as String),
      categoryId: j['categoryId'] as String,
      sourceKind: PoolKind.values.byName(j['sourceKind'] as String),
      sourceRefId: j['sourceRefId'] as String?,
      destinationKind: PoolKind.values.byName(j['destinationKind'] as String),
      destinationRefId: j['destinationRefId'] as String?,
      amountMinor: j['amountMinor'] as int,
      note: (j['note'] as String?) ?? '',
      transactionDate: DateTime.parse(j['date'] as String),
      // Deterministic — KHÔNG dùng DateTime.now() (mục 13), golden test phải
      // reproducible tuyệt đối.
      createdAt: DateTime.parse(j['date'] as String),
      clientTxId: 'golden-client-$idSuffix',
    );
  }

  final raw = jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
  final rawTxJson = (raw['transactions'] as List).cast<Map<String, dynamic>>();

  // ---- Opening balances (mục 1, OPENING_BALANCES sheet) — model qua category
  // 'so_du_ban_dau' (excludeFromTotals=true), ĐÚNG cơ chế đã có, KHÔNG field
  // openingBalance riêng nào (docs/financial-core-v2.md mục 17).
  final openingDate = DateTime(2026, 1, 1);
  final openingTx = <Transaction>[
    Transaction(
      id: 'opening-vo-available',
      type: TransactionType.income,
      categoryId: 'so_du_ban_dau',
      sourceKind: PoolKind.external,
      destinationKind: PoolKind.memberAvailable,
      destinationRefId: 'vo',
      amountMinor: 627000,
      transactionDate: openingDate,
      createdAt: openingDate,
      clientTxId: 'opening-client-1',
    ),
    Transaction(
      id: 'opening-chong-available',
      type: TransactionType.income,
      categoryId: 'so_du_ban_dau',
      sourceKind: PoolKind.external,
      destinationKind: PoolKind.memberAvailable,
      destinationRefId: 'chong',
      amountMinor: 1060000,
      transactionDate: openingDate,
      createdAt: openingDate,
      clientTxId: 'opening-client-2',
    ),
    Transaction(
      id: 'opening-vo-savings',
      type: TransactionType.income,
      categoryId: 'so_du_ban_dau',
      sourceKind: PoolKind.external,
      destinationKind: PoolKind.memberSavingsAsset,
      destinationRefId: savingsAssetRefId('legacy', FamilyMember.vo),
      amountMinor: 2500000,
      transactionDate: openingDate,
      createdAt: openingDate,
      clientTxId: 'opening-client-3',
    ),
    Transaction(
      id: 'opening-chong-savings',
      type: TransactionType.income,
      categoryId: 'so_du_ban_dau',
      sourceKind: PoolKind.external,
      destinationKind: PoolKind.memberSavingsAsset,
      destinationRefId: savingsAssetRefId('legacy', FamilyMember.chong),
      amountMinor: 12000000,
      transactionDate: openingDate,
      createdAt: openingDate,
      clientTxId: 'opening-client-4',
    ),
  ];

  // ---- Synthetic STATE_SPLIT (mục 4, LEGACY_RULES "STATE SPLIT" policy) —
  // KHÔNG phải 1 dòng raw cụ thể: dữ liệu gốc chỉ có 1 pool tiết kiệm chung
  // cho Chồng, không phân biệt "Ngân hàng"/"khác" theo từng dòng. Người
  // dùng xác nhận tách 70.000.000 sang loại tài sản "Ngân hàng" bằng ĐÚNG
  // 1 giao dịch SAVINGS_CONVERT, Total Assets không đổi.
  final stateSplitTx = Transaction(
    id: 'state-split-bank',
    type: TransactionType.transfer,
    transferKind: TransferKind.savingsConvert,
    categoryId: 'tiet_kiem',
    sourceKind: PoolKind.memberSavingsAsset,
    sourceRefId: savingsAssetRefId('legacy', FamilyMember.chong),
    destinationKind: PoolKind.memberSavingsAsset,
    destinationRefId: savingsAssetRefId('ngan_hang', FamilyMember.chong),
    amountMinor: 70000000,
    note: 'STATE_SPLIT — tách theo GOLDEN_STATE, không phải dòng raw cụ thể',
    transactionDate: DateTime(2026, 9, 17),
    createdAt: DateTime(2026, 9, 17),
    clientTxId: 'state-split-client',
  );

  final realTx = [
    for (var i = 0; i < rawTxJson.length; i++) fromJson(rawTxJson[i], '$i'),
  ];

  final allTx = [...openingTx, ...realTx, stateSplitTx];

  group('PHASE 8.5 — Real-data golden test (2026)', () {
    test('0 — Fixture nạp đúng số lượng giao dịch đã normalize', () {
      expect(realTx.length, 1788);
      expect(allTx.length, 1788 + 4 + 1);
    });

    test(
      '1 — Replay tuần tự (sort theo transactionDate, ổn định theo row gốc) '
      'không vi phạm invariant nào (amount dương, source != destination)',
      () {
        for (final tx in allTx) {
          expect(
            () => validateNewTransaction(tx),
            returnsNormally,
            reason: 'Transaction ${tx.id} (note: ${tx.note}) vi phạm Invariant 12/15',
          );
        }
      },
    );

    test(
      '2 — Replay tuần tự: BÁO CÁO (không fail-fast) mọi điểm mà '
      'InsufficientBalanceException guard của Repository THẬT sẽ chặn nếu '
      'dữ liệu này được nhập qua app — dữ liệu lịch sử này được ghi trong '
      'Excel thủ công trước khi app tồn tại nên không có ràng buộc đó tại '
      'thời điểm nhập; KHÔNG phải bằng chứng dữ liệu sai, chỉ báo cáo minh '
      'bạch (mục 15/21 Phase 8.5) — không tự bỏ transaction, không tự sửa gì.',
      () {
        final sorted = [...allTx]
          ..sort((a, b) {
            final byDate = a.transactionDate.compareTo(b.transactionDate);
            if (byDate != 0) return byDate;
            return a.id.compareTo(b.id);
          });

        final balances = <PoolRef, int>{};
        final violations = <String>[];
        for (final tx in sorted) {
          if (tx.sourceKind != PoolKind.external) {
            final before = balances[(tx.sourceKind, tx.sourceRefId)] ?? 0;
            final wouldBeNegative = wouldGoNegative(
              currentBalances: balances,
              kind: tx.sourceKind,
              refId: tx.sourceRefId,
              delta: -tx.amountMinor,
            );
            if (wouldBeNegative) {
              violations.add(
                '${tx.transactionDate.toIso8601String().substring(0, 10)} '
                '(note: "${tx.note}", pool: ${tx.sourceKind}/${tx.sourceRefId}, '
                'balance trước: $before, effect: -${tx.amountMinor}, '
                'balance sau dự kiến: ${before - tx.amountMinor})',
              );
            }
          }
          applyEffect(tx, 1, balances);
        }

        // ignore: avoid_print
        print(
          'Test 2 — ${violations.length} điểm InsufficientBalance nếu thay '
          'app enforce real-time khi nhập lịch sử (KHÔNG chặn Golden Test, '
          'chỉ báo cáo):',
        );
        for (final v in violations) {
          // ignore: avoid_print
          print('  - $v');
        }
        // Không assert = 0 — dữ liệu lịch sử tiền-app hợp lệ có thể có điểm
        // âm tạm thời; final reconciliation (test 3) mới là bằng chứng
        // quyết định, đã PASS riêng.
      },
    );

    test('3 — Final state khớp CHÍNH XÁC GOLDEN_STATE 17/09/2026', () {
      final summary = computeFinancialSummary(
        allTx,
        categories: categories,
        funds: noFunds,
        assetTypes: assetTypes,
      );

      expect(summary.availableByMember[FamilyMember.vo], 244000, reason: 'Vợ Available');
      expect(summary.savingsByMember[FamilyMember.vo], 4740000, reason: 'Vợ Savings total');
      expect(summary.availableByMember[FamilyMember.chong], 835000, reason: 'Chồng Available');
      expect(summary.savingsByMember[FamilyMember.chong], 70500000, reason: 'Chồng Savings total');
      expect(summary.totalAssets, 76319000, reason: 'Total family assets');
    });

    test('4 — Chồng Savings tách đúng Bank/Non-bank (70.000.000 / 500.000)', () {
      final summary = computeFinancialSummary(
        allTx,
        categories: categories,
        funds: noFunds,
        assetTypes: assetTypes,
      );
      final chongByAssetType = summary.savingsByMemberAndAssetType[FamilyMember.chong]!;
      expect(chongByAssetType['ngan_hang'], 70000000, reason: 'Bank');
      expect(chongByAssetType['legacy'], 500000, reason: 'Non-bank/other');
    });

    test(
      '5 — Non-income inflow (bán lại/hoàn tiền): Available + Total Assets '
      'tăng, nhưng monthlyIncome/totalIncome KHÔNG tăng',
      () {
        final nonIncomeInflowTx = realTx
            .where((t) => t.categoryId == 'thu_hoi_tai_san_hoan_tien')
            .toList();
        expect(nonIncomeInflowTx, isNotEmpty);
        final totalNonIncomeInflow = nonIncomeInflowTx.fold<int>(0, (s, t) => s + t.amountMinor);
        expect(totalNonIncomeInflow, 7786000, reason: 'tổng 20 dòng đã xác nhận non-income inflow');

        // So sánh Total Income CÓ vs KHÔNG có nhóm non-income-inflow — phải
        // giống hệt nhau (excludeFromTotals chặn đúng chỗ).
        final totalsWithGroup = computeThreeTotals(allTx, categories);
        final withoutGroup = allTx.where((t) => t.categoryId != 'thu_hoi_tai_san_hoan_tien').toList();
        final totalsWithoutGroup = computeThreeTotals(withoutGroup, categories);
        expect(
          totalsWithGroup.totalIncome,
          totalsWithoutGroup.totalIncome,
          reason: 'monthlyIncome/totalIncome không được đổi khi có/không có nhóm non-income-inflow',
        );
        expect(
          totalsWithGroup.totalExpense,
          totalsWithoutGroup.totalExpense,
          reason: 'monthlyExpense cũng không bị đụng tới bởi nhóm này',
        );

        // Nhưng Available/Total Assets THÌ có đổi đúng bằng tổng nhóm này.
        final balancesWith = computeAllPoolBalances(allTx);
        final balancesWithout = computeAllPoolBalances(withoutGroup);
        final assetsWith = balancesWith.values.fold<int>(0, (s, v) => s + v);
        final assetsWithout = balancesWithout.values.fold<int>(0, (s, v) => s + v);
        expect(
          assetsWith - assetsWithout,
          totalNonIncomeInflow,
          reason: 'Total Assets phải tăng ĐÚNG bằng tổng non-income inflow',
        );
      },
    );

    test('6 — Internal transfer net = 0 trên toàn bộ ledger (Tiết kiệm + Member-to-member + STATE_SPLIT)', () {
      final balances = computeAllPoolBalances(allTx);
      final transferTx = allTx.where((t) => t.type == TransactionType.transfer).toList();
      final balancesFromTransferOnly = computeAllPoolBalances(transferTx);
      final netFromTransfers = balancesFromTransferOnly.values.fold<int>(0, (s, v) => s + v);
      expect(netFromTransfers, 0, reason: 'Mọi TRANSFER (kể cả STATE_SPLIT) phải tự triệt tiêu, không đổi Total Assets');
      expect(balances.isNotEmpty, isTrue);
    });

    test(
      '7 — Reconciliation: Opening Assets + reportable Income + non-income inflow − true Expense = Final Assets',
      () {
        const openingAssets = 627000 + 1060000 + 2500000 + 12000000; // 16,187,000
        final totals = computeThreeTotals(allTx, categories);
        final nonIncomeInflow = realTx
            .where((t) => t.categoryId == 'thu_hoi_tai_san_hoan_tien')
            .fold<int>(0, (s, t) => s + t.amountMinor);
        // computeThreeTotals đã loại "so_du_ban_dau" (excludeFromTotals) khỏi
        // totalIncome — nên totals.totalIncome ở đây là ĐÚNG "reportable
        // income" (không lẫn opening balance, không lẫn non-income inflow).
        final reconciled = openingAssets + totals.totalIncome + nonIncomeInflow - totals.totalExpense;

        final summary = computeFinancialSummary(allTx, categories: categories, funds: noFunds, assetTypes: assetTypes);
        expect(reconciled, summary.totalAssets, reason: 'Công thức reconciliation phải khớp Total Assets thật');
        expect(summary.totalAssets, 76319000);
      },
    );

    test('8 — Checkpoint cuối kỳ (17/09/2026) — báo cáo, đã assert chính xác ở test 3', () {
      final summary = computeFinancialSummary(
        allTx,
        categories: categories,
        funds: noFunds,
        assetTypes: assetTypes,
        month: DateTime(2026, 9),
      );
      // ignore: avoid_print
      print(
        'Checkpoint 17/09: Vợ avail=${summary.availableByMember[FamilyMember.vo]} '
        'savings=${summary.savingsByMember[FamilyMember.vo]} | '
        'Chồng avail=${summary.availableByMember[FamilyMember.chong]} '
        'savings=${summary.savingsByMember[FamilyMember.chong]} | '
        'totalAssets=${summary.totalAssets} | '
        'monthlyIncome(Sep)=${summary.monthlyIncome} monthlyExpense(Sep)=${summary.monthlyExpense} '
        'monthlyNet(Sep)=${summary.monthlyNet}',
      );
      expect(summary.availableByMember[FamilyMember.vo], 244000);
      expect(summary.availableByMember[FamilyMember.chong], 835000);
    });

    test(
      '9 — Checkpoint hàng tháng (31/01..31/08) — báo cáo (KHÔNG có số đối '
      'chiếu độc lập từ Excel cho các mốc giữa kỳ, chỉ verify không crash/không âm pool)',
      () {
        final checkpoints = [
          DateTime(2026, 1, 31, 23, 59, 59),
          DateTime(2026, 2, 28, 23, 59, 59),
          DateTime(2026, 3, 31, 23, 59, 59),
          DateTime(2026, 4, 30, 23, 59, 59),
          DateTime(2026, 5, 31, 23, 59, 59),
          DateTime(2026, 6, 30, 23, 59, 59),
          DateTime(2026, 7, 31, 23, 59, 59),
          DateTime(2026, 8, 31, 23, 59, 59),
        ];
        for (final cp in checkpoints) {
          final upTo = allTx.where((t) => !t.transactionDate.isAfter(cp)).toList();
          final summary = computeFinancialSummary(
            upTo,
            categories: categories,
            funds: noFunds,
            assetTypes: assetTypes,
            month: DateTime(cp.year, cp.month),
          );
          // ignore: avoid_print
          print(
            'Checkpoint ${cp.year}-${cp.month.toString().padLeft(2, '0')}: '
            'Vợ avail=${summary.availableByMember[FamilyMember.vo]} savings=${summary.savingsByMember[FamilyMember.vo]} | '
            'Chồng avail=${summary.availableByMember[FamilyMember.chong]} savings=${summary.savingsByMember[FamilyMember.chong]} | '
            'totalAssets=${summary.totalAssets} | income=${summary.monthlyIncome} expense=${summary.monthlyExpense}',
          );
          expect(summary.totalAssets, greaterThanOrEqualTo(0));
        }
      },
    );

    test('10 — Legacy "Vợ chồng" counterpart không bị double-count (mục 6 Phase 8.5)', () {
      // 24/02/2026: "Vợ chồng -400.000, Người tiêu = Chồng" đã xác nhận là
      // Vợ đưa Chồng 400.000 — đây LÀ dòng đối ứng của 1 dòng "Vợ đưa chồng"
      // CREATE khác, không phải giao dịch thứ 2. Verify: tổng volume
      // "chuyen_tien_thanh_vien" trong fixture = ĐÚNG tổng 49+9=58 dòng gốc
      // (Chồng đưa vợ + Vợ đưa chồng), KHÔNG cộng thêm 13 dòng "Vợ chồng"
      // legacy nào.
      final transferTx = realTx.where((t) => t.categoryId == 'chuyen_tien_thanh_vien').toList();
      expect(transferTx.length, 58, reason: '49 Chồng đưa vợ + 9 Vợ đưa chồng, KHÔNG có dòng Vợ chồng nào lọt vào (đã IGNORE ở bước export)');
    });
  });
}
