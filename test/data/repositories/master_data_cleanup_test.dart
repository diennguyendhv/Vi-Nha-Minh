import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/repositories/local_category_repository.dart';
import 'package:vi_nha_minh/data/repositories/local_status_repository.dart';
import 'package:vi_nha_minh/data/repositories/local_transaction_repository.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/status.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart' as domain;
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/errors/domain_exceptions.dart';

/// Master data cleanup (Category / Status): CHƯA TỪNG DÙNG + ĐÃ NGỪNG →
/// xoá hẳn được; ĐÃ TỪNG DÙNG (kể cả giao dịch đã hoàn tác) → chỉ ngừng sử
/// dụng. Chạy trên DB Drift thật (in-memory / file), không fake.
void main() {
  late AppDatabase db;
  late LocalCategoryRepository categories;
  late LocalStatusRepository statuses;
  late LocalTransactionRepository transactions;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    categories = LocalCategoryRepository(db);
    statuses = LocalStatusRepository(db);
    transactions = LocalTransactionRepository(db);
  });

  tearDown(() async => db.close());

  Category cat(String id, {String? linked, TransactionType type = TransactionType.expense, List<Status> st = const []}) =>
      Category(
        id: id,
        name: 'Tên $id',
        color: Colors.teal,
        type: type,
        statuses: st,
        linkedExpenseCategoryId: linked,
        isDefault: false,
      );

  Status stat(String id, String categoryId, {int order = 0}) =>
      Status(id: id, categoryId: categoryId, name: 'Bước $id', sortOrder: order);

  domain.Transaction spend(
    String id,
    String categoryId, {
    String? statusId,
    int amount = 1000,
  }) => domain.Transaction(
    id: id,
    type: TransactionType.expense,
    categoryId: categoryId,
    sourceKind: PoolKind.memberAvailable,
    sourceRefId: 'vo',
    destinationKind: PoolKind.external,
    amountMinor: amount,
    statusId: statusId,
    transactionDate: DateTime(2026, 9, 1),
    createdAt: DateTime(2026, 9, 1),
    clientTxId: 'client-$id',
  );

  Future<void> fundWife() => transactions.addTransaction(
    domain.Transaction(
      id: 'open',
      type: TransactionType.income,
      categoryId: 'thu_nhap',
      sourceKind: PoolKind.external,
      destinationKind: PoolKind.memberAvailable,
      destinationRefId: 'vo',
      amountMinor: 1000000,
      transactionDate: DateTime(2026, 9, 1),
      createdAt: DateTime(2026, 9, 1),
      clientTxId: 'client-open',
    ),
  );

  Future<Set<String>> deletableCats() => categories.watchDeletableCategoryIds().first;
  Future<Set<String>> deletableStatuses() => statuses.watchDeletableStatusIds().first;
  Future<int> txCount() async => (await db.select(db.transactionRows).get()).length;
  Future<bool> catExists(String id) async =>
      (await (db.select(db.categoryRows)..where((r) => r.id.equals(id))).get()).isNotEmpty;
  Future<bool> statusExists(String id) async =>
      (await (db.select(db.statusRows)..where((r) => r.id.equals(id))).get()).isNotEmpty;

  Future<void> expectDbHealthy(AppDatabase d) async {
    final integrity = await d.customSelect('PRAGMA integrity_check').get();
    expect(integrity.single.data.values.single, 'ok');
    expect(await d.customSelect('PRAGMA foreign_key_check').get(), isEmpty, reason: 'không FK treo');
    final orphans = await d
        .customSelect(
          'SELECT s.id FROM status_rows s WHERE s.category_id NOT IN (SELECT id FROM category_rows)',
        )
        .get();
    expect(orphans, isEmpty, reason: 'không status mồ côi');
  }

  group('Category', () {
    test('1 — ngừng + 0 giao dịch → xoá hẳn thành công', () async {
      await categories.addCategory(cat('c_unused'));
      await categories.softDeleteCategory('c_unused');
      expect(await deletableCats(), contains('c_unused'));

      await categories.deleteCategoryPermanently('c_unused');

      expect(await catExists('c_unused'), isFalse);
      await expectDbHealthy(db);
    });

    test('2 — ngừng + có giao dịch cũ → bị chặn, danh mục còn nguyên và vẫn đọc được tên', () async {
      await fundWife();
      await categories.addCategory(cat('c_used'));
      await transactions.addTransaction(spend('t1', 'c_used'));
      await categories.softDeleteCategory('c_used');

      expect(await deletableCats(), isNot(contains('c_used')));
      await expectLater(
        categories.deleteCategoryPermanently('c_used'),
        throwsA(isA<CategoryNotDeletableException>()),
      );

      final all = await categories.watchCategories().first;
      expect(all.firstWhere((c) => c.id == 'c_used').name, 'Tên c_used', reason: 'lịch sử vẫn resolve tên');
      await expectDbHealthy(db);
    });

    test('3 — xoá danh mục chưa dùng: số giao dịch + dữ liệu giao dịch không đổi', () async {
      await fundWife();
      await categories.addCategory(cat('c_used'));
      await transactions.addTransaction(spend('t1', 'c_used', amount: 4000));
      await categories.addCategory(cat('c_unused'));
      await categories.softDeleteCategory('c_unused');
      final before = await db.select(db.transactionRows).get();

      await categories.deleteCategoryPermanently('c_unused');

      final after = await db.select(db.transactionRows).get();
      expect(after.length, before.length);
      expect(after.map((r) => (r.id, r.amountMinor, r.categoryId)).toSet(),
          before.map((r) => (r.id, r.amountMinor, r.categoryId)).toSet());
    });

    test('4 — danh mục có các bước con chưa từng dùng → xoá cả danh mục lẫn bước, không mồ côi', () async {
      await categories.addCategory(cat('c_steps', st: [stat('s_a', 'c_steps'), stat('s_b', 'c_steps', order: 1)]));
      await statuses.addStatus(stat('s_a', 'c_steps'));
      await statuses.addStatus(stat('s_b', 'c_steps', order: 1));
      await categories.softDeleteCategory('c_steps');
      expect(await deletableCats(), contains('c_steps'));

      await categories.deleteCategoryPermanently('c_steps');

      expect(await catExists('c_steps'), isFalse);
      expect(await statusExists('s_a'), isFalse);
      expect(await statusExists('s_b'), isFalse);
      await expectDbHealthy(db);
    });

    test('5 — 1 bước con đã được giao dịch dùng → không xoá hẳn danh mục', () async {
      await fundWife();
      await categories.addCategory(cat('c_owner'));
      await statuses.addStatus(stat('s_used', 'c_owner'));
      // Giao dịch dùng bước này nhưng thuộc danh mục KHÁC: danh mục owner tự nó
      // chưa có giao dịch, chỉ bước con bị dùng.
      await transactions.addTransaction(spend('t1', 'sinh_hoat'));
      // Dữ liệu CŨ bị lệch (giao dịch Sinh hoạt gắn trạng thái của danh mục khác —
      // trường hợp "Chi Phí Vận Hành" thật). Bất biến mới chặn tạo mới kiểu này,
      // nên giả lập bằng SQL để kiểm tra luật xoá vẫn coi bước đó là đã dùng.
      await db.customStatement("UPDATE transaction_rows SET status_id = 's_used' WHERE id = 't1'");
      await categories.softDeleteCategory('c_owner');

      expect(await deletableCats(), isNot(contains('c_owner')));
      await expectLater(
        categories.deleteCategoryPermanently('c_owner'),
        throwsA(isA<CategoryNotDeletableException>()),
      );
      expect(await statusExists('s_used'), isTrue);
    });

    test('Giao dịch ĐÃ HOÀN TÁC vẫn là 1 dòng sổ: danh mục vẫn không xoá hẳn được', () async {
      await fundWife();
      await categories.addCategory(cat('c_rev'));
      await transactions.addTransaction(spend('t1', 'c_rev'));
      await transactions.reverseTransaction('t1');
      await categories.softDeleteCategory('c_rev');

      expect(await deletableCats(), isNot(contains('c_rev')));
      await expectLater(
        categories.deleteCategoryPermanently('c_rev'),
        throwsA(isA<CategoryNotDeletableException>()),
      );
    });

    test('Đang dùng (chưa ngừng) → không xoá hẳn, dù chưa có giao dịch', () async {
      await categories.addCategory(cat('c_active'));
      expect(await deletableCats(), isNot(contains('c_active')));
      await expectLater(
        categories.deleteCategoryPermanently('c_active'),
        throwsA(isA<CategoryNotDeletableException>()),
      );
      expect(await catExists('c_active'), isTrue);
    });

    test('Danh mục hệ thống (Chuyển / Vay / Hoàn tiền) không bao giờ xoá hẳn được, kể cả khi đã ngừng và chưa dùng', () async {
      for (final id in ['tiet_kiem', 'nap_quy', 'chuyen_tien_thanh_vien', 'cho_vay', 'vay_no', 'tra_no', 'lai_cho_vay', 'hoan_tien_thu_hoi']) {
        await categories.softDeleteCategory(id);
      }
      final deletable = await deletableCats();
      for (final id in ['tiet_kiem', 'nap_quy', 'chuyen_tien_thanh_vien', 'cho_vay', 'vay_no', 'tra_no', 'lai_cho_vay', 'hoan_tien_thu_hoi']) {
        expect(deletable, isNot(contains(id)), reason: id);
        await expectLater(
          categories.deleteCategoryPermanently(id),
          throwsA(isA<CategoryNotDeletableException>()),
          reason: id,
        );
        expect(await catExists(id), isTrue);
      }
    });

    test('linkedExpenseCategoryId là metadata cũ: KHÔNG chặn xoá; xoá danh mục đích thì gỡ liên kết (cùng 1 DB transaction), danh mục kia còn nguyên', () async {
      await categories.addCategory(cat('c_target'));
      await categories.addCategory(cat('c_income', type: TransactionType.income, linked: 'c_target'));
      await categories.softDeleteCategory('c_target');

      expect(await deletableCats(), contains('c_target'));
      await categories.deleteCategoryPermanently('c_target');

      expect(await catExists('c_target'), isFalse);
      expect(await catExists('c_income'), isTrue);
      final row = await (db.select(db.categoryRows)..where((r) => r.id.equals('c_income'))).getSingle();
      expect(row.linkedExpenseCategoryId, isNull, reason: 'không để tham chiếu treo');
    });

    test('Danh mục đích có giao dịch thật → vẫn bị chặn và liên kết KHÔNG bị đụng', () async {
      await fundWife();
      await categories.addCategory(cat('c_target'));
      await categories.addCategory(cat('c_income', type: TransactionType.income, linked: 'c_target'));
      await transactions.addTransaction(spend('s_real', 'c_target'));
      await categories.softDeleteCategory('c_target');

      await expectLater(
        categories.deleteCategoryPermanently('c_target'),
        throwsA(isA<CategoryNotDeletableException>()),
      );
      final row = await (db.select(db.categoryRows)..where((r) => r.id.equals('c_income'))).getSingle();
      expect(row.linkedExpenseCategoryId, 'c_target');
    });

    test('Kiểm tra lại trong lúc xoá: giao dịch mới xuất hiện sau khi UI thấy "an toàn" vẫn bị chặn', () async {
      await fundWife();
      await categories.addCategory(cat('c_race'));
      await categories.softDeleteCategory('c_race');
      expect(await deletableCats(), contains('c_race'), reason: 'UI thấy an toàn');

      // Trong lúc đó 1 giao dịch dùng nó (danh mục ngừng vẫn ghi được qua repo).
      await transactions.addTransaction(spend('t_late', 'c_race'));

      await expectLater(
        categories.deleteCategoryPermanently('c_race'),
        throwsA(isA<CategoryNotDeletableException>()),
      );
      expect(await catExists('c_race'), isTrue);
    });

    test('Stream tự cập nhật: danh mục chưa dùng xuất hiện rồi biến mất khỏi danh sách "an toàn"', () async {
      await categories.addCategory(cat('c_live'));
      await categories.softDeleteCategory('c_live');
      expect(await deletableCats(), contains('c_live'));
      await fundWife();
      await transactions.addTransaction(spend('t1', 'c_live'));
      expect(await deletableCats(), isNot(contains('c_live')));
    });

    test('Sử dụng lại danh mục đã ngừng: cùng id, quay lại danh sách đang dùng', () async {
      await categories.addCategory(cat('c_back'));
      await categories.softDeleteCategory('c_back');
      final stopped = (await categories.watchCategories().first).firstWhere((c) => c.id == 'c_back');
      expect(stopped.isActive, isFalse);

      await categories.updateCategory(stopped.copyWith(isActive: true));

      final back = (await categories.watchCategories().first).firstWhere((c) => c.id == 'c_back');
      expect(back.isActive, isTrue);
      expect(await deletableCats(), isNot(contains('c_back')));
    });
  });

  group('Status', () {
    test('7 — ngừng + 0 giao dịch → xoá hẳn thành công', () async {
      await statuses.softDeleteStatus('cho_di_da_gui');
      // Bước seed này chưa có giao dịch nào dùng.
      expect(await deletableStatuses(), contains('cho_di_da_gui'));

      await statuses.deleteStatusPermanently('cho_di_da_gui');

      expect(await statusExists('cho_di_da_gui'), isFalse);
      expect(await statusExists('cho_di_da_chuan_bi'), isTrue, reason: 'bước khác không bị đụng');
      await expectDbHealthy(db);
    });

    test('8 — ngừng + có giao dịch → bị chặn; lịch sử vẫn resolve tên', () async {
      await fundWife();
      await transactions.addTransaction(spend('t1', 'cho_di', statusId: 'cho_di_da_chuan_bi'));
      await statuses.softDeleteStatus('cho_di_da_chuan_bi');

      expect(await deletableStatuses(), isNot(contains('cho_di_da_chuan_bi')));
      await expectLater(
        statuses.deleteStatusPermanently('cho_di_da_chuan_bi'),
        throwsA(isA<StatusNotDeletableException>()),
      );
      final choDi = (await categories.watchCategories().first).firstWhere((c) => c.id == 'cho_di');
      expect(choDi.statusById('cho_di_da_chuan_bi')?.name, 'ĐCB');
      await expectDbHealthy(db);
    });

    test('Bước đang dùng (chưa ngừng) → không xoá hẳn', () async {
      expect(await deletableStatuses(), isNot(contains('cho_di_chua_chuan_bi')));
      await expectLater(
        statuses.deleteStatusPermanently('cho_di_chua_chuan_bi'),
        throwsA(isA<StatusNotDeletableException>()),
      );
      expect(await statusExists('cho_di_chua_chuan_bi'), isTrue);
    });

    test('Giao dịch đã hoàn tác vẫn giữ statusId → bước không xoá hẳn được', () async {
      await fundWife();
      await transactions.addTransaction(spend('t1', 'cho_di', statusId: 'cho_di_da_gui'));
      await transactions.reverseTransaction('t1');
      await statuses.softDeleteStatus('cho_di_da_gui');

      expect(await deletableStatuses(), isNot(contains('cho_di_da_gui')));
      await expectLater(
        statuses.deleteStatusPermanently('cho_di_da_gui'),
        throwsA(isA<StatusNotDeletableException>()),
      );
    });

    test('9 — Sử dụng lại giữ NGUYÊN id', () async {
      await statuses.softDeleteStatus('cho_di_da_gui');
      await statuses.reactivateStatus('cho_di_da_gui');
      final choDi = (await categories.watchCategories().first).firstWhere((c) => c.id == 'cho_di');
      expect(choDi.statusById('cho_di_da_gui')?.isActive, isTrue);
      expect(choDi.statuses.where((s) => s.name == 'ĐG').length, 1, reason: 'không tạo bản trùng');
    });

    test('10 — Đổi tên giữ id, lịch sử thấy tên mới', () async {
      await fundWife();
      await transactions.addTransaction(spend('t1', 'cho_di', statusId: 'cho_di_da_gui'));
      await statuses.renameStatus('cho_di_da_gui', 'Đã gửi đi');
      final choDi = (await categories.watchCategories().first).firstWhere((c) => c.id == 'cho_di');
      final row = await (db.select(db.transactionRows)..where((r) => r.id.equals('t1'))).getSingle();
      expect(row.statusId, 'cho_di_da_gui');
      expect(choDi.statusById(row.statusId)?.name, 'Đã gửi đi');
    });

    test('Xoá hẳn bước không thay đổi số giao dịch hay số dư', () async {
      await fundWife();
      await transactions.addTransaction(spend('t1', 'sinh_hoat', amount: 5000));
      await statuses.softDeleteStatus('cho_di_da_gui');
      final before = await txCount();

      await statuses.deleteStatusPermanently('cho_di_da_gui');

      expect(await txCount(), before);
    });
  });

  test('6 — khởi động lại app (mở lại file DB): mục đã xoá hẳn không quay lại; mục còn lại vẫn nguyên', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final dir = await Directory.systemTemp.createTemp('vnm_cleanup_');
    final file = File('${dir.path}/vi_nha_minh.sqlite');
    addTearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    var fileDb = AppDatabase.forTesting(NativeDatabase(file));
    var cats = LocalCategoryRepository(fileDb);
    var sts = LocalStatusRepository(fileDb);
    await cats.addCategory(cat('c_gone', st: [stat('s_gone', 'c_gone')]));
    await sts.addStatus(stat('s_gone', 'c_gone'));
    await cats.addCategory(cat('c_kept'));
    await cats.softDeleteCategory('c_gone');
    await cats.deleteCategoryPermanently('c_gone');
    await sts.softDeleteStatus('cho_di_da_gui');
    await sts.deleteStatusPermanently('cho_di_da_gui');
    await fileDb.close();

    fileDb = AppDatabase.forTesting(NativeDatabase(file));
    cats = LocalCategoryRepository(fileDb);
    final all = await cats.watchCategories().first;
    expect(all.map((c) => c.id), isNot(contains('c_gone')));
    expect(all.map((c) => c.id), contains('c_kept'));
    expect(all.firstWhere((c) => c.id == 'cho_di').statuses.map((s) => s.id), isNot(contains('cho_di_da_gui')),
        reason: 'seed chỉ chạy lúc TẠO DB, không nạp lại mục đã xoá');
    await expectDbHealthy(fileDb);
    await fileDb.close();
  });
}
