import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/data/import/legacy_import_guard.dart';
import 'package:vi_nha_minh/data/import/legacy_import_plan.dart';
import 'package:vi_nha_minh/data/import/legacy_ledger_importer.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/seed_defaults.dart';

/// V2-2C — guard của công cụ nhập debug trên KẾ HOẠCH THẬT (đặt ngoài git). Cần
/// `LEGACY_STAGING_DIR` có `import_plan.json` + `import_manifest.json`; không có
/// ⇒ tự bỏ qua.
void main() {
  const long = Timeout(Duration(minutes: 8));
  final dir = Platform.environment['LEGACY_STAGING_DIR'];
  if (dir == null ||
      !File('$dir/import_plan.json').existsSync() ||
      !File('$dir/import_manifest.json').existsSync()) {
    test('import guard — bỏ qua (không có LEGACY_STAGING_DIR)', () {},
        skip: 'cần LEGACY_STAGING_DIR có import_plan.json + import_manifest.json');
    return;
  }
  Map<String, dynamic> read(String f) =>
      jsonDecode(File('$dir/$f').readAsStringSync()) as Map<String, dynamic>;
  final plan = ImportPlan.fromJson(read('import_plan.json'));
  final manifest = LegacyImportManifest.fromJson(read('import_manifest.json'));

  AppDatabase fresh() =>
      AppDatabase.forTesting(NativeDatabase.memory(), seed: SeedProfile.fresh);

  test('kế hoạch hợp lệ; manifest sai bị từ chối', () {
    LegacyImportGuard.validatePlan(plan, manifest);
    for (final tamper in <void Function(Map<String, dynamic>)>[
      (j) => j['workbookSha256'] = 'x',
      (j) => j['importerVersion'] = 'v9',
      (j) => j['finalTransactions'] = 1806,
      (j) => j['sourceTransactions'] = 1801,
      (j) => (j['balances'] as Map)['totalAssets'] = 1,
    ]) {
      final j = read('import_manifest.json');
      tamper(j);
      expect(
        () => LegacyImportGuard.validatePlan(plan, LegacyImportManifest.fromJson(j)),
        throwsA(isA<LegacyImportRejectedException>()),
      );
    }
  });

  test('DB sạch → nhập nguyên tử + xác minh → nhập lại: đã nhập, không tạo mới', timeout: long, () async {
    final db = fresh();
    final base = await LegacyImportGuard.checkBaseline(db, plan);
    expect(base.problems, isEmpty);
    expect(base.alreadyImported, isFalse);

    await db.transaction(() async {
      final r = await LegacyLedgerImporter(db).run(plan);
      expect(r.transactionsCreated, manifest.finalTransactions);
    });
    final m = await LegacyImportGuard.measure(db);
    expect(LegacyImportGuard.diff(m, manifest), isEmpty);

    final again = await LegacyImportGuard.checkBaseline(db, plan);
    expect(again.alreadyImported, isTrue);
    expect(again.clean, isTrue);
    await db.close();
  });

  test('DB không sạch bị chặn (đã có 1 giao dịch lạ)', () async {
    final db = fresh();
    await db.customStatement(
      "INSERT INTO category_rows (id, name, color_value, type, is_default) "
      "VALUES ('x_user','X',0,'expense',0)",
    );
    final base = await LegacyImportGuard.checkBaseline(db, plan);
    expect(base.clean, isFalse);
    await db.close();
  });

  test('sai lệch số liệu sau nhập ⇒ rollback toàn bộ', timeout: long, () async {
    final db = fresh();
    final j = read('import_manifest.json');
    (j['totals'] as Map)['revenue'] = 1;
    final bad = LegacyImportManifest.fromJson(j);
    await expectLater(
      db.transaction(() async {
        await LegacyLedgerImporter(db).run(plan);
        final problems = LegacyImportGuard.diff(await LegacyImportGuard.measure(db), bad);
        if (problems.isNotEmpty) throw LegacyImportRejectedException(problems);
      }),
      throwsA(isA<LegacyImportRejectedException>()),
    );
    final base = await LegacyImportGuard.checkBaseline(db, plan);
    expect(base.clean, isTrue);
    expect(base.facts['transactions'], 0);
    await db.close();
  });
}
