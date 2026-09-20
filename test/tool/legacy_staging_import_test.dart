import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/data/import/legacy_import_plan.dart';
import 'package:vi_nha_minh/data/import/legacy_ledger_importer.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/seed_defaults.dart';
import 'package:vi_nha_minh/data/repositories/local_category_repository.dart';
import 'package:vi_nha_minh/data/repositories/local_transaction_repository.dart';
import 'package:vi_nha_minh/domain/engine/financial_engine.dart';
import 'package:vi_nha_minh/domain/entities/family_member.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/savings_asset_type.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/entities/transfer_kind.dart';
import 'package:vi_nha_minh/domain/usecases/compute_financial_summary.dart';
import 'package:vi_nha_minh/domain/usecases/compute_grouped_totals.dart';
import 'package:vi_nha_minh/domain/usecases/compute_three_totals.dart';

/// V2-2B — STAGING import (V2-2B): nhập kế hoạch thật vào 1 DB Drift TẠM trên đĩa
/// (KHÔNG phải DB của app/Pixel), qua repository thật; đóng → mở lại → tính lại
/// từ dòng đã lưu → chạy lần 2 (idempotency). Đường dẫn qua `LEGACY_STAGING_DIR`
/// (chứa `import_plan.json`); không có biến này → test tự bỏ qua.
void main() {
  final dir = Platform.environment['LEGACY_STAGING_DIR'];
  if (dir == null || !File('$dir/import_plan.json').existsSync()) {
    test('staging import — bỏ qua (không có LEGACY_STAGING_DIR)', () {},
        skip: 'cần LEGACY_STAGING_DIR trỏ tới thư mục có import_plan.json');
    return;
  }

  final planJson = jsonDecode(File('$dir/import_plan.json').readAsStringSync()) as Map<String, dynamic>;
  final plan = ImportPlan.fromJson(planJson);
  final dbFile = File('$dir/staging.sqlite');

  AppDatabase open() => AppDatabase.forTesting(NativeDatabase(dbFile), seed: SeedProfile.fresh);

  // Hạng mục Excel gốc + dấu của từng danh mục nhập (chỉ để GROUP-BY đối soát).
  final sourceOf = <String, ({String? raw, int sign})>{
    for (final c in (planJson['categories'] as List).cast<Map<String, dynamic>>())
      c['id'] as String: (
        raw: (c['source'] as Map<String, dynamic>)['rawCategory'] as String?,
        sign: (c['source'] as Map<String, dynamic>)['sign'] as int,
      ),
  };

  const assetTypes = <SavingsAssetType>[
    SystemSavingsAssets.unallocated,
    SavingsAssetType(id: 'savings_bank', name: 'Gửi ngân hàng', color: Color(0xFF13805F)),
  ];

  Map<String, dynamic> gj(GroupedTotals x) => {
    'revenue': x.revenue, 'otherInflow': x.otherInflow, 'spending': x.spending,
    'businessExpense': x.businessExpense, 'netIncome': x.netIncome, 'cashFlow': x.cashFlow,
  };

  Future<Map<String, dynamic>> measure(AppDatabase db) async {
    final txRepo = LocalTransactionRepository(db);
    final catRepo = LocalCategoryRepository(db);
    final txs = await txRepo.watchTransactions().first;
    final cats = await catRepo.watchCategories().first;
    final s = computeFinancialSummary(txs, categories: cats, funds: const [], assetTypes: assetTypes);
    final three = computeThreeTotals(txs, cats);
    final pools = computeAllPoolBalances(txs);

    Map<String, dynamic> periodSums(DateTime from, DateTime toExclusive) {
      final out = <String, Map<String, int>>{'vo': {}, 'chong': {}, 'all': {}};
      void add(String who, String cat, int v) => out[who]![cat] = (out[who]![cat] ?? 0) + v;
      for (final t in txs) {
        final d = t.transactionDate;
        if (d.isBefore(from) || !d.isBefore(toExclusive)) continue;
        String? raw;
        var sign = 1;
        String? who;
        if (t.categoryId == 'tiet_kiem' && t.transferKind == TransferKind.savingsTopup) {
          raw = 'Tiết kiệm'; sign = 1; who = t.sourceRefId;
        } else if (t.categoryId == 'tiet_kiem' && t.transferKind == TransferKind.savingsWithdraw) {
          raw = 'Tiết kiệm'; sign = -1; who = t.destinationRefId;
        } else if (t.categoryId == 'chuyen_tien_thanh_vien') {
          raw = t.sourceRefId == 'chong' ? 'Chồng đưa vợ' : 'Vợ đưa chồng';
        } else if (sourceOf[t.categoryId]?.raw != null) {
          raw = sourceOf[t.categoryId]!.raw;
          sign = sourceOf[t.categoryId]!.sign;
          who = t.type == TransactionType.income ? t.destinationRefId : t.sourceRefId;
        }
        if (raw == null) continue; // số dư đầu kỳ / phân bổ Ngân hàng không thuộc Hạng mục Excel
        final v = sign * t.amountMinor;
        if (who != null) add(who, raw, v);
        add('all', raw, v);
      }
      return out;
    }

    Map<String, int> statusSums(DateTime from, DateTime toExclusive) {
      final nameOf = {for (final c in cats) for (final st in c.statuses) st.id: st.name};
      final out = <String, int>{};
      for (final t in txs) {
        final d = t.transactionDate;
        if (d.isBefore(from) || !d.isBefore(toExclusive)) continue;
        final raw = t.categoryId == 'tiet_kiem'
            ? 'Tiết kiệm'
            : t.categoryId == 'chuyen_tien_thanh_vien'
                ? (t.sourceRefId == 'chong' ? 'Chồng đưa vợ' : 'Vợ đưa chồng')
                : sourceOf[t.categoryId]?.raw;
        if (raw == null) continue;
        final sign = t.categoryId == 'tiet_kiem'
            ? (t.transferKind == TransferKind.savingsWithdraw ? -1 : 1)
            : (sourceOf[t.categoryId]?.sign ?? 1);
        final k = '$raw|${t.statusId == null ? '(không)' : nameOf[t.statusId]!}';
        out[k] = (out[k] ?? 0) + sign * t.amountMinor;
      }
      return out;
    }

    // Định danh & toàn vẹn dựa trên DÒNG ĐÃ LƯU.
    final planned = {for (final t in plan.transactions) t.clientTxId: t};
    var mismatched = 0;
    for (final t in txs) {
      final p = planned[t.clientTxId];
      if (p == null ||
          p.id != t.id ||
          p.type != t.type ||
          p.transferKind != t.transferKind ||
          p.categoryId != t.categoryId ||
          p.sourceKind != t.sourceKind ||
          p.sourceRefId != t.sourceRefId ||
          p.destinationKind != t.destinationKind ||
          p.destinationRefId != t.destinationRefId ||
          p.amountMinor != t.amountMinor ||
          p.date != t.transactionDate ||
          p.note != t.note ||
          p.statusId != t.statusId) {
        mismatched++;
      }
    }
    final statusCat = {for (final c in cats) for (final st in c.statuses) st.id: c.id};
    final invalidPairs = txs.where((t) => t.statusId != null && statusCat[t.statusId] != t.categoryId).length;
    final catIds = {for (final c in cats) c.id};
    final danglingCategory = txs.where((t) => !catIds.contains(t.categoryId)).length;
    final negatives = {
      for (final e in pools.entries)
        if (e.key.$1 != PoolKind.external && e.value < 0) '${e.key.$1.name}|${e.key.$2}': e.value,
    };
    final futureCut = DateTime(2026, 9, 20, 23, 59, 59);

    return {
      'counts': {
        'transactions': txs.length,
        'categories': cats.length,
        'importedCategories': cats.where((c) => c.id.startsWith('imp_')).length,
        'importedStatuses': cats.where((c) => c.id.startsWith('imp_')).fold<int>(0, (a, c) => a + c.statuses.length),
        'statusesTotal': cats.fold<int>(0, (a, c) => a + c.statuses.length),
        'distinctClientTxIds': {for (final t in txs) t.clientTxId}.length,
        'distinctIds': {for (final t in txs) t.id}.length,
        'planTransactions': plan.transactions.length,
        'mismatchedVsPlan': mismatched,
        'invalidCategoryStatusPairs': invalidPairs,
        'danglingCategoryRefs': danglingCategory,
        'zeroOrNegativeAmounts': txs.where((t) => t.amountMinor <= 0).length,
        'openingTransactions': txs.where((t) => t.categoryId == 'imp_so_du_dau_ky').length,
        'bankConverts': txs.where((t) => t.transferKind == TransferKind.savingsConvert).length,
        'noStatusTransactions': txs.where((t) => t.statusId == null).length,
        'statusOnSystemTransfer': txs.where((t) => (t.categoryId == 'tiet_kiem' || t.categoryId == 'chuyen_tien_thanh_vien') && t.statusId != null).length,
        'futureDated': txs.where((t) => t.transactionDate.isAfter(futureCut)).map((t) => t.clientTxId).toList(),
        'negativeProtectedPools': negatives,
      },
      'summary': {
        'availableVo': s.availableByMember[FamilyMember.vo],
        'availableChong': s.availableByMember[FamilyMember.chong],
        'savingsVo': s.savingsByMember[FamilyMember.vo],
        'savingsChong': s.savingsByMember[FamilyMember.chong],
        'savingsVoByAsset': s.savingsByMemberAndAssetType[FamilyMember.vo],
        'savingsChongByAsset': s.savingsByMemberAndAssetType[FamilyMember.chong],
        'totalFunds': s.totalFunds,
        'totalAssets': s.totalAssets,
        'threeTotals': {'income': three.totalIncome, 'expense': three.totalExpense, 'transfer': three.totalTransfer},
        'grouped': gj(computeGroupedTotals(txs, cats)),
        'groupedVo': gj(computeGroupedTotals(txs, cats, member: FamilyMember.vo)),
        'groupedChong': gj(computeGroupedTotals(txs, cats, member: FamilyMember.chong)),
        'pools': {for (final e in pools.entries) '${e.key.$1.name}|${e.key.$2}': e.value},
      },
      'groupedByMonth': {
        for (var m = 1; m <= 12; m++)
          '$m': {
            'all': gj(computeGroupedTotals(txs, cats, month: DateTime(2026, m))),
            'vo': gj(computeGroupedTotals(txs, cats, month: DateTime(2026, m), member: FamilyMember.vo)),
            'chong': gj(computeGroupedTotals(txs, cats, month: DateTime(2026, m), member: FamilyMember.chong)),
          },
      },
      'periods': {
        'year': periodSums(DateTime(2026, 1, 1), DateTime(2027, 1, 1)),
        'month': periodSums(DateTime(2026, 9, 1), DateTime(2026, 10, 1)),
        'day': periodSums(DateTime(2026, 9, 17), DateTime(2026, 9, 18)),
      },
      'statusSumsSep': statusSums(DateTime(2026, 9, 1), DateTime(2026, 10, 1)),
    };
  }

  Map<String, dynamic> resultJson(LegacyImportResult r) => {
    'categoriesCreated': r.categoriesCreated,
    'categoriesExisting': r.categoriesExisting,
    'statusesCreated': r.statusesCreated,
    'transactionsCreated': r.transactionsCreated,
    'transactionsExisting': r.transactionsExisting,
    'schedule': {
      'total': r.schedule.total,
      'skipAheadPlacements': r.schedule.skipAheadPlacements,
      'delayedTransactions': r.schedule.delayedTransactions,
      'minBalances': r.schedule.minBalances,
      'order': [
        for (var i = 0; i < r.schedule.order.length; i++)
          {
            'pos': i + 1,
            'clientTxId': r.schedule.order[i].clientTxId,
            'sourceRow': r.schedule.order[i].sourceRow,
            'date': r.schedule.order[i].date.toIso8601String(),
          },
      ],
    },
  };

  test('staging: nhập → đóng → mở lại → tính lại → nhập lần 2', () async {
    if (dbFile.existsSync()) dbFile.deleteSync();
    for (final ext in ['-wal', '-shm', '-journal']) {
      final f = File('${dbFile.path}$ext');
      if (f.existsSync()) f.deleteSync();
    }

    // 1) Nhập lần 1.
    var db = open();
    final first = await LegacyLedgerImporter(db).run(plan);
    final inMemoryTxCount = (await LocalTransactionRepository(db).watchTransactions().first).length;
    await db.close();

    // 2) Mở lại từ đĩa, tính lại từ dòng đã lưu.
    db = open();
    final afterReopen = await measure(db);

    // 3) Nhập lần 2 (cùng kế hoạch) trên chính DB đó.
    final second = await LegacyLedgerImporter(db).run(plan);
    final afterSecond = await measure(db);
    await db.close();

    // 4) Mở lần 3 để chắc chắn mọi thứ nằm trên đĩa.
    db = open();
    final finalCheck = await measure(db);
    await db.close();

    final out = {
      'planIdentity': {'importerVersion': plan.importerVersion, 'workbookSha256': plan.workbookSha256},
      'firstRun': resultJson(first),
      'inMemoryTransactionCountAfterFirstRun': inMemoryTxCount,
      'afterReopen': afterReopen,
      'secondRun': resultJson(second),
      'afterSecondRun': afterSecond,
      'afterThirdOpen': finalCheck,
      'idempotent': jsonEncode(afterReopen['summary']) == jsonEncode(afterSecond['summary']) &&
          (afterReopen['counts'] as Map)['transactions'] == (afterSecond['counts'] as Map)['transactions'],
    };
    File('$dir/staging_result.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));

    expect((afterReopen['counts'] as Map)['transactions'], plan.transactions.length);
    expect(second.transactionsCreated, 0);
    expect(out['idempotent'], isTrue);
  });
}
