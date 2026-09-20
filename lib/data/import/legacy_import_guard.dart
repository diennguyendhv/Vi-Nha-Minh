import '../../domain/engine/financial_engine.dart';
import '../../domain/entities/family_member.dart';
import '../../domain/entities/pool_kind.dart';
import '../../domain/entities/savings_asset_type.dart';
import '../../domain/usecases/compute_grouped_totals.dart';
import '../local/app_database.dart';
import '../repositories/local_category_repository.dart';
import '../repositories/local_transaction_repository.dart';
import 'legacy_import_plan.dart';

/// Kế hoạch/DB không khớp điều kiện an toàn để nhập — KHÔNG "best effort".
class LegacyImportRejectedException implements Exception {
  const LegacyImportRejectedException(this.problems);
  final List<String> problems;
  @override
  String toString() => 'LegacyImportRejectedException: ${problems.join('; ')}';
}

/// Giá trị kỳ vọng do CHỦ DỰ ÁN duyệt, nằm trong `import_manifest.json` đi
/// kèm kế hoạch (đẩy bằng adb, KHÔNG commit, KHÔNG đóng gói vào APK) — số tiền
/// thật không nằm trong mã nguồn.
class LegacyImportManifest {
  const LegacyImportManifest({
    required this.workbookSha256,
    required this.importerVersion,
    required this.sourceTransactions,
    required this.openingTransactions,
    required this.allocationTransactions,
    required this.finalTransactions,
    required this.importedCategories,
    required this.importedStatuses,
    required this.balances,
    required this.totals,
  });

  factory LegacyImportManifest.fromJson(Map<String, dynamic> j) =>
      LegacyImportManifest(
        workbookSha256: j['workbookSha256'] as String,
        importerVersion: j['importerVersion'] as String,
        sourceTransactions: j['sourceTransactions'] as int,
        openingTransactions: j['openingTransactions'] as int,
        allocationTransactions: j['allocationTransactions'] as int,
        finalTransactions: j['finalTransactions'] as int,
        importedCategories: j['importedCategories'] as int,
        importedStatuses: j['importedStatuses'] as int,
        balances: (j['balances'] as Map<String, dynamic>).cast<String, int>(),
        totals: (j['totals'] as Map<String, dynamic>).cast<String, int>(),
      );

  /// Phiên bản importer được hỗ trợ (đổi importer ⇒ phải duyệt lại).
  static const supportedImporterVersion = 'v2-2b-1';

  final String workbookSha256;
  final String importerVersion;
  final int sourceTransactions;
  final int openingTransactions;
  final int allocationTransactions;
  final int finalTransactions;
  final int importedCategories;
  final int importedStatuses;

  /// availableVo, availableChong, savingsVo, savingsChong, unallocatedChong,
  /// bankChong, totalAssets, totalFunds.
  final Map<String, int> balances;

  /// revenue, businessExpense, netIncome, spending, otherInflow.
  final Map<String, int> totals;
}

/// Số đo của 1 sổ cái (tính bằng Financial Engine, không công thức riêng).
class LegacyLedgerMeasure {
  const LegacyLedgerMeasure(this.balances, this.totals);
  final Map<String, int> balances;
  final Map<String, int> totals;
}

/// Kết quả đọc DB thật để quyết định có cho phép nhập không.
class LegacyBaseline {
  const LegacyBaseline({
    required this.problems,
    required this.alreadyImported,
    required this.facts,
  });

  /// Rỗng ⇒ DB đúng trạng thái sạch mong đợi.
  final List<String> problems;

  /// Mọi `clientTxId` của kế hoạch đã có trong DB (nhập lần 2).
  final bool alreadyImported;
  final Map<String, Object> facts;
  bool get clean => problems.isEmpty;
}

class LegacyImportGuard {
  const LegacyImportGuard._();

  /// Xác thực kế hoạch + số liệu SUY RA TỪ CHÍNH kế hoạch với manifest. Ném
  /// [LegacyImportRejectedException] nếu sai bất kỳ điều gì.
  static void validatePlan(ImportPlan plan, LegacyImportManifest m) {
    final p = <String>[];
    if (plan.workbookSha256 != m.workbookSha256) {
      p.add('SHA workbook trong kế hoạch khác manifest.');
    }
    if (plan.importerVersion != m.importerVersion ||
        plan.importerVersion != LegacyImportManifest.supportedImporterVersion) {
      p.add('Phiên bản importer "${plan.importerVersion}" không được hỗ trợ.');
    }
    final txs = plan.transactions;
    final src = txs.where((t) => t.role == 'src').length;
    final opening = txs.where((t) => t.role.startsWith('opening:')).length;
    final alloc = txs.where((t) => t.role == 'migration:bank-allocation').length;
    if (src != m.sourceTransactions) {
      p.add('Giao dịch nguồn $src ≠ ${m.sourceTransactions}.');
    }
    if (opening != m.openingTransactions) {
      p.add('Số dư đầu kỳ $opening ≠ ${m.openingTransactions}.');
    }
    if (alloc != m.allocationTransactions) {
      p.add('Phân bổ tiết kiệm $alloc ≠ ${m.allocationTransactions}.');
    }
    if (txs.length != m.finalTransactions ||
        src + opening + alloc != txs.length) {
      p.add('Tổng giao dịch ${txs.length} ≠ ${m.finalTransactions}.');
    }
    if (plan.categories.length != m.importedCategories) {
      p.add('Danh mục ${plan.categories.length} ≠ ${m.importedCategories}.');
    }
    final statuses = plan.categories.fold<int>(
      0,
      (a, c) => a + c.statuses.length,
    );
    if (statuses != m.importedStatuses) {
      p.add('Trạng thái $statuses ≠ ${m.importedStatuses}.');
    }
    if ({for (final t in txs) t.clientTxId}.length != txs.length ||
        {for (final t in txs) t.id}.length != txs.length) {
      p.add('Trùng id/clientTxId trong kế hoạch.');
    }
    if (txs.any((t) => t.amountMinor <= 0)) {
      p.add('Có giao dịch số tiền ≤ 0.');
    }
    // Số dư suy ra từ kế hoạch (thuần Financial Engine) phải khớp kỳ vọng.
    final got = _balances(
      computeAllPoolBalances([for (final t in txs) t.toDomain()]),
    );
    for (final e in m.balances.entries) {
      if (got[e.key] != e.value) {
        p.add('Số dư ${e.key}: kế hoạch cho ${got[e.key]} ≠ ${e.value}.');
      }
    }
    if (p.isNotEmpty) throw LegacyImportRejectedException(p);
  }

  static Map<String, int> _balances(Map<PoolRef, int> b) {
    int a(FamilyMember m) => poolBalance(b, PoolKind.memberAvailable, m.name);
    int s(String asset, FamilyMember m) =>
        poolBalance(b, PoolKind.memberSavingsAsset, savingsAssetRefId(asset, m));
    final uv = SystemSavingsAssets.unallocatedId;
    int savings(FamilyMember m) => b.entries
        .where(
          (e) =>
              e.key.$1 == PoolKind.memberSavingsAsset &&
              e.key.$2 != null &&
              parseSavingsAssetRefId(e.key.$2!)?.member == m,
        )
        .fold<int>(0, (x, e) => x + e.value);
    return {
      'availableVo': a(FamilyMember.vo),
      'availableChong': a(FamilyMember.chong),
      'savingsVo': savings(FamilyMember.vo),
      'savingsChong': savings(FamilyMember.chong),
      'unallocatedChong': s(uv, FamilyMember.chong),
      'bankChong': s('savings_bank', FamilyMember.chong),
      'totalAssets': b.values.fold<int>(0, (x, v) => x + v),
      'totalFunds': b.entries
          .where((e) => e.key.$1 == PoolKind.fund)
          .fold<int>(0, (x, e) => x + e.value),
    };
  }

  /// Đo sổ cái THẬT trong [db] (đọc qua repository).
  static Future<LegacyLedgerMeasure> measure(AppDatabase db) async {
    final txs = await LocalTransactionRepository(db).watchTransactions().first;
    final cats = await LocalCategoryRepository(db).watchCategories().first;
    final g = computeGroupedTotals(txs, cats);
    return LegacyLedgerMeasure(_balances(computeAllPoolBalances(txs)), {
      'revenue': g.revenue,
      'businessExpense': g.businessExpense,
      'netIncome': g.netIncome,
      'spending': g.spending,
      'otherInflow': g.otherInflow,
    });
  }

  /// So số đo với manifest; trả danh sách sai lệch (rỗng = khớp).
  static List<String> diff(LegacyLedgerMeasure got, LegacyImportManifest m) => [
    for (final e in m.balances.entries)
      if (got.balances[e.key] != e.value)
        'Số dư ${e.key}: ${got.balances[e.key]} ≠ ${e.value}',
    for (final e in m.totals.entries)
      if (got.totals[e.key] != e.value)
        'Tổng ${e.key}: ${got.totals[e.key]} ≠ ${e.value}',
  ];

  /// Kiểm tra DB thật TRƯỚC khi cho phép nhập. Không sửa gì.
  static Future<LegacyBaseline> checkBaseline(
    AppDatabase db,
    ImportPlan plan,
  ) async {
    Future<int> count(String sql) async =>
        (await db.customSelect(sql).getSingle()).read<int>('c');
    final version = (await db.customSelect('PRAGMA user_version').getSingle())
        .read<int>('user_version');
    final integrity = (await db.customSelect('PRAGMA integrity_check').get())
        .map((r) => r.read<String>('integrity_check'))
        .toList();
    final fk = await db.customSelect('PRAGMA foreign_key_check').get();
    final tx = await count('SELECT COUNT(*) c FROM transaction_rows');
    final userCats = await count(
      "SELECT COUNT(*) c FROM category_rows WHERE id LIKE 'imp\\_%' ESCAPE '\\'",
    );
    final statuses = await count('SELECT COUNT(*) c FROM status_rows');
    final obligations = await count('SELECT COUNT(*) c FROM obligation_rows');
    final funds = await db.customSelect('SELECT id FROM fund_rows').get();
    final assets = await db
        .customSelect('SELECT id FROM savings_asset_type_rows')
        .get();
    final planIds = plan.transactions.map((t) => t.clientTxId).toSet();
    final present = (await db
            .customSelect('SELECT client_tx_id FROM transaction_rows')
            .get())
        .map((r) => r.read<String>('client_tx_id'))
        .toSet();
    final overlap = present.intersection(planIds).length;
    final allThere = overlap == planIds.length && planIds.isNotEmpty;

    final nonSystemCats = await count(
      'SELECT COUNT(*) c FROM category_rows WHERE is_default = 0',
    );

    final problems = <String>[];
    if (version != 7) problems.add('schema $version ≠ 7');
    if (integrity.length != 1 || integrity.first != 'ok') {
      problems.add('integrity_check: ${integrity.join(',')}');
    }
    if (fk.isNotEmpty) problems.add('foreign_key_check có ${fk.length} dòng');
    if (!allThere) {
      if (tx != 0) problems.add('giao dịch $tx ≠ 0');
      if (userCats != 0) problems.add('danh mục nhập $userCats ≠ 0');
      if (nonSystemCats != 0) {
        problems.add('danh mục người dùng $nonSystemCats ≠ 0');
      }
      if (statuses != 0) problems.add('trạng thái $statuses ≠ 0');
      if (obligations != 0) problems.add('khoản vay/cho vay $obligations ≠ 0');
      if (overlap != 0) problems.add('$overlap clientTxId của kế hoạch đã có');
    }
    if (!funds.any((r) => r.read<String>('id') == 'an_uong')) {
      problems.add('thiếu quỹ an_uong');
    }
    if (!assets.any((r) => r.read<String>('id') == 'savings_bank')) {
      problems.add('thiếu loại tiết kiệm savings_bank');
    }
    return LegacyBaseline(
      problems: problems,
      alreadyImported: allThere,
      facts: {
        'schema': version,
        'transactions': tx,
        'statuses': statuses,
        'obligations': obligations,
        'nonSystemCategories': nonSystemCats,
        'funds': funds.length,
        'savingsAssets': assets.length,
      },
    );
  }
}
