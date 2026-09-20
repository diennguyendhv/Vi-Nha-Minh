import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/engine/financial_engine.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/family_member.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/savings_asset_type.dart';
import 'package:vi_nha_minh/domain/entities/status.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/entities/transfer_kind.dart';
import 'package:vi_nha_minh/domain/usecases/compute_financial_summary.dart';
import 'package:vi_nha_minh/domain/usecases/compute_grouped_totals.dart';
import 'package:vi_nha_minh/domain/usecases/compute_three_totals.dart';

/// DRY-RUN nhập dữ liệu thật (V2-2A) — CHỈ ĐỌC, in-memory.
///
/// Đọc `sim_input.json` do `tool/legacy_import/audit.py` sinh ra (đường dẫn qua
/// biến môi trường `LEGACY_SIM_DIR`), dựng `Transaction` và chạy toàn bộ qua
/// Financial Core THẬT (`computeAllPoolBalances`, `computeFinancialSummary`,
/// `computeGroupedTotals`, `validateNewTransaction`, `wouldGoNegative`).
/// KHÔNG mở DB, KHÔNG gọi repository, KHÔNG có công thức tài chính thứ hai.
/// Không có biến môi trường → test tự bỏ qua (dữ liệu thật không nằm trong repo).
void main() {
  final dir = Platform.environment['LEGACY_SIM_DIR'];
  if (dir == null || !File('$dir/sim_input.json').existsSync()) {
    test('dry-run mô phỏng nhập dữ liệu — bỏ qua (không có LEGACY_SIM_DIR)', () {},
        skip: 'cần LEGACY_SIM_DIR trỏ tới thư mục có sim_input.json');
    return;
  }

  final input = jsonDecode(File('$dir/sim_input.json').readAsStringSync()) as Map<String, dynamic>;

  TransactionType tType(String s) => TransactionType.values.byName(s);

  final categories = <Category>[];
  for (final c in (input['categories'] as List).cast<Map<String, dynamic>>()) {
    final id = c['id'] as String;
    categories.add(Category(
      id: id,
      name: c['name'] as String,
      color: Colors.grey,
      type: tType(c['type'] as String),
      excludeFromTotals: c['excludeFromTotals'] as bool,
      groupKey: c['groupKey'] as String?,
      isDefault: false,
      statuses: [
        for (final s in ((c['statuses'] as List?) ?? const []).cast<Map<String, dynamic>>())
          Status(id: s['id'] as String, categoryId: id, name: s['name'] as String, sortOrder: s['sortOrder'] as int),
      ],
    ));
  }

  Transaction build(Map<String, dynamic> j) {
    final d = DateTime.parse(j['date'] as String);
    return Transaction(
      id: j['id'] as String,
      type: tType(j['type'] as String),
      transferKind: j['transferKind'] == null ? null : TransferKind.values.byName(j['transferKind'] as String),
      categoryId: j['categoryId'] as String,
      sourceKind: PoolKind.values.byName(j['sourceKind'] as String),
      sourceRefId: j['sourceRefId'] as String?,
      destinationKind: PoolKind.values.byName(j['destinationKind'] as String),
      destinationRefId: j['destinationRefId'] as String?,
      amountMinor: j['amountMinor'] as int,
      statusId: j['statusId'] as String?,
      transactionDate: d,
      createdAt: d,
      clientTxId: 'dryrun-${j['id']}',
    );
  }

  final openingJson = (input['openings'] as List).cast<Map<String, dynamic>>();
  final txJson = (input['transactions'] as List).cast<Map<String, dynamic>>();
  final opening = openingJson.map(build).toList();
  final real = txJson.map(build).toList();
  final all = [...opening, ...real];
  // Tag nguồn (Hạng mục Excel + dấu) theo id để gộp theo Hạng mục gốc.
  final rawCat = {for (final j in txJson) j['id'] as String: j['rawCategory'] as String?};
  final rowOf = {for (final j in txJson) j['id'] as String: j['row'] as int};
  final rawSignOf = {for (final j in txJson) j['id'] as String: j['rawSign'] as int};

  const assetTypes = <SavingsAssetType>[
    SystemSavingsAssets.unallocated,
    SavingsAssetType(id: 'ngan_hang', name: 'Gửi ngân hàng', color: Color(0xFF000011)),
  ];

  Map<String, dynamic> poolsJson(Map<PoolRef, int> b) => {
    for (final e in b.entries) '${e.key.$1.name}|${e.key.$2}': e.value,
  };

  Map<String, dynamic> summaryJson(List<Transaction> txs) {
    final s = computeFinancialSummary(txs, categories: categories, funds: const [], assetTypes: assetTypes);
    final three = computeThreeTotals(txs, categories);
    final g = computeGroupedTotals(txs, categories);
    Map<String, dynamic> gj(GroupedTotals x) => {
      'revenue': x.revenue, 'otherInflow': x.otherInflow, 'spending': x.spending,
      'businessExpense': x.businessExpense, 'netIncome': x.netIncome, 'cashFlow': x.cashFlow,
    };
    return {
      'availableVo': s.availableByMember[FamilyMember.vo],
      'availableChong': s.availableByMember[FamilyMember.chong],
      'savingsVo': s.savingsByMember[FamilyMember.vo],
      'savingsChong': s.savingsByMember[FamilyMember.chong],
      'savingsVoByAsset': s.savingsByMemberAndAssetType[FamilyMember.vo],
      'savingsChongByAsset': s.savingsByMemberAndAssetType[FamilyMember.chong],
      'totalAvailable': s.totalAvailable,
      'totalSavings': s.totalSavings,
      'totalFunds': s.totalFunds,
      'totalAssets': s.totalAssets,
      'threeTotals': {'income': three.totalIncome, 'expense': three.totalExpense, 'transfer': three.totalTransfer},
      'grouped': gj(g),
      'groupedVo': gj(computeGroupedTotals(txs, categories, member: FamilyMember.vo)),
      'groupedChong': gj(computeGroupedTotals(txs, categories, member: FamilyMember.chong)),
      'pools': poolsJson(computeAllPoolBalances(txs)),
    };
  }

  // Replay tuần tự (sắp theo ngày rồi số dòng) — báo cáo mọi điểm âm mà
  // repository thật sẽ chặn nếu nhập theo thứ tự này. KHÔNG sửa, KHÔNG bỏ dòng.
  Map<String, dynamic> replay(List<Transaction> order) {
    final balances = <PoolRef, int>{};
    final minBal = <String, int>{};
    final violations = <Map<String, dynamic>>[];
    for (final tx in order) {
      if (tx.sourceKind != PoolKind.external) {
        final before = balances[(tx.sourceKind, tx.sourceRefId)] ?? 0;
        if (wouldGoNegative(currentBalances: balances, kind: tx.sourceKind, refId: tx.sourceRefId, delta: -tx.amountMinor)) {
          violations.add({
            'row': rowOf[tx.id] ?? 0, 'date': tx.transactionDate.toIso8601String(),
            'pool': '${tx.sourceKind.name}|${tx.sourceRefId}', 'before': before, 'amount': tx.amountMinor,
            'after': before - tx.amountMinor, 'cat': rawCat[tx.id],
          });
        }
      }
      applyEffect(tx, 1, balances);
      for (final e in balances.entries) {
        final k = '${e.key.$1.name}|${e.key.$2}';
        final cur = minBal[k];
        if (cur == null || e.value < cur) minBal[k] = e.value;
      }
    }
    return {'violationCount': violations.length, 'violations': violations, 'minBalance': minBal};
  }

  int cmpChrono(Transaction a, Transaction b) {
    final c = a.transactionDate.compareTo(b.transactionDate);
    if (c != 0) return c;
    return (rowOf[a.id] ?? 0).compareTo(rowOf[b.id] ?? 0);
  }

  // Tổng ký hiệu theo Hạng mục gốc của Excel (chỉ GROUP-BY, không phải công thức tài chính).
  // Thu nhập = doanh thu − chi phí kinh doanh(âm); Hạng mục chi = chi − hoàn; Tiết kiệm = nạp − rút.
  Map<String, dynamic> periodSums(DateTime from, DateTime toExclusive) {
    final out = <String, Map<String, int>>{'vo': {}, 'chong': {}, 'all': {}};
    void add(String who, String cat, int v) {
      out[who]![cat] = (out[who]![cat] ?? 0) + v;
    }

    for (final t in real) {
      final d = t.transactionDate;
      if (d.isBefore(from) || !d.isBefore(toExclusive)) continue;
      final cat = rawCat[t.id]!;
      final sign = rawSignOf[t.id]!;
      final member = t.type == TransactionType.income
          ? t.destinationRefId
          : (t.type == TransactionType.expense ? t.sourceRefId : null);
      // Tiết kiệm/chuyển: dùng người thực hiện.
      String? who;
      if (cat == 'Tiết kiệm') {
        final ref = t.transferKind == TransferKind.savingsTopup ? t.sourceRefId : t.destinationRefId;
        who = ref;
      } else if (t.transferKind == TransferKind.memberToMember) {
        who = null;
      } else {
        who = member;
      }
      final signed = sign * t.amountMinor;
      if (who != null) add(who, cat, signed);
      add('all', cat, signed);
    }
    return out;
  }

  // Tổng ký hiệu theo (Hạng mục gốc | Trạng thái) trong 1 kỳ — cho đối soát các ô trạng thái của Tổng hợp.
  Map<String, int> statusSums(DateTime from, DateTime toExclusive) {
    final nameOf = {
      for (final c in categories) for (final s in c.statuses) s.id: s.name,
    };
    final out = <String, int>{};
    for (final t in real) {
      final d = t.transactionDate;
      if (d.isBefore(from) || !d.isBefore(toExclusive)) continue;
      final st = t.statusId == null ? '(không)' : nameOf[t.statusId]!;
      final k = '${rawCat[t.id]}|$st';
      out[k] = (out[k] ?? 0) + rawSignOf[t.id]! * t.amountMinor;
    }
    return out;
  }

  Map<String, dynamic> gjson(GroupedTotals x) => {
    'revenue': x.revenue, 'otherInflow': x.otherInflow, 'spending': x.spending,
    'businessExpense': x.businessExpense, 'netIncome': x.netIncome,
  };

  final periodCache = <String, dynamic>{};

  group('DRY-RUN nhập dữ liệu thật (chỉ đọc)', () {
    test('mô phỏng + ghi sim_output.json', () {
      // 1. Validate từng giao dịch dự kiến.
      var invalid = 0;
      final invalidRows = <int>[];
      for (final t in all) {
        try {
          validateNewTransaction(t);
        } catch (_) {
          invalid++;
          invalidRows.add(rowOf[t.id] ?? 0);
        }
      }

      // 2. Trạng thái ↔ danh mục (Invariant status.categoryId == transaction.categoryId).
      final statusCat = {for (final c in categories) for (final s in c.statuses) s.id: c.id};
      var badStatus = 0;
      for (final t in all) {
        if (t.statusId != null && statusCat[t.statusId] != t.categoryId) badStatus++;
      }

      final chrono = [...all]..sort(cmpChrono);
      final rowOrder = [...opening, ...([...real]..sort((a, b) => (rowOf[a.id] ?? 0).compareTo(rowOf[b.id] ?? 0)))];

      // 3. Kịch bản A (KHÔNG chọn — chỉ để tham khảo): 1 giao dịch phân bổ tổng hợp 70tr sang Ngân hàng.
      final optionA = Transaction(
        id: 'optionA-bank-allocation',
        type: TransactionType.transfer,
        transferKind: TransferKind.savingsConvert,
        categoryId: 'tiet_kiem',
        sourceKind: PoolKind.memberSavingsAsset,
        sourceRefId: savingsAssetRefId(SystemSavingsAssets.unallocatedId, FamilyMember.chong),
        destinationKind: PoolKind.memberSavingsAsset,
        destinationRefId: savingsAssetRefId('ngan_hang', FamilyMember.chong),
        amountMinor: 70000000,
        transactionDate: DateTime(2026, 9, 13),
        createdAt: DateTime(2026, 9, 13),
        clientTxId: 'dryrun-optionA',
      );

      // 4. Kỳ đối soát với sheet Tổng hợp (ngày 17/09/2026): cả năm, tháng 9, ngày 17/9.
      final year = periodSums(DateTime(2026, 1, 1), DateTime(2027, 1, 1));
      final month = periodSums(DateTime(2026, 9, 1), DateTime(2026, 10, 1));
      final day = periodSums(DateTime(2026, 9, 17), DateTime(2026, 9, 18));
      periodCache['year'] = year;
      periodCache['month'] = month;
      periodCache['day'] = day;

      final futureCut = DateTime(2026, 9, 17, 23, 59, 59, 999);
      final result = {
        'counts': {
          'openings': opening.length, 'transactions': real.length, 'all': all.length,
          'invalidByValidate': invalid, 'invalidRows': invalidRows, 'statusMismatch': badStatus,
        },
        'base': summaryJson(all),
        'baseWithoutOpening': summaryJson(real),
        'optionA_whatIf': summaryJson([...all, optionA]),
        'replayChrono': replay(chrono),
        'replayRowOrder': replay(rowOrder),
        'periods': periodCache,
        'statusSumsSep': statusSums(DateTime(2026, 9, 1), DateTime(2026, 10, 1)),
        'statusSumsYear': statusSums(DateTime(2026, 1, 1), DateTime(2027, 1, 1)),
        'groupedByMonth': {
          for (var m = 1; m <= 12; m++)
            '$m': {
              'all': gjson(computeGroupedTotals(all, categories, month: DateTime(2026, m))),
              'vo': gjson(computeGroupedTotals(all, categories, month: DateTime(2026, m), member: FamilyMember.vo)),
              'chong': gjson(computeGroupedTotals(all, categories, month: DateTime(2026, m), member: FamilyMember.chong)),
            },
        },
        'asOf17Sep': summaryJson(all.where((t) => !t.transactionDate.isAfter(futureCut)).toList()),
        'futureDatedRows': [
          for (final t in real)
            if (t.transactionDate.isAfter(futureCut))
              {'row': rowOf[t.id], 'date': t.transactionDate.toIso8601String(), 'amount': t.amountMinor, 'cat': rawCat[t.id]},
        ]..sort((a, b) => (a['row'] as int).compareTo(b['row'] as int)),
      };
      File('$dir/sim_output.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(result));
      expect(invalid, 0);
      expect(badStatus, 0);
    });
  });
}
