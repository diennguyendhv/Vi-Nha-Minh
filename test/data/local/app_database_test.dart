import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3_pkg;
import 'package:vi_nha_minh/data/local/app_database.dart';

/// Persistence tests cho Phase 2 — Database Foundation. Không đụng UI/full
/// Repository (đúng phạm vi Phase 2), thao tác thẳng qua `AppDatabase`
/// (Drift) để kiểm tra schema/constraint/migration/atomic transaction.
void main() {
  // File này cố ý mở nhiều instance AppDatabase (1 cho mỗi test qua `setUp`,
  // 1 riêng cho fixture migration) trên các file/executor hoàn toàn khác
  // nhau — không phải race condition thật, chỉ tắt cảnh báo debug-only của
  // Drift cho gọn log test.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertCategory(String id, {String type = 'expense'}) {
    return db
        .into(db.categoryRows)
        .insert(
          CategoryRowsCompanion.insert(id: id, name: id, colorValue: 0xFF000000, type: type),
        );
  }

  Future<void> insertStatus(String id, String categoryId, {int sortOrder = 0}) {
    return db
        .into(db.statusRows)
        .insert(
          StatusRowsCompanion.insert(
            id: id,
            categoryId: categoryId,
            name: id,
            sortOrder: sortOrder,
          ),
        );
  }

  TransactionRowsCompanion txCompanion({
    required String id,
    required String categoryId,
    String sourceKind = 'external',
    String? sourceRefId,
    String destinationKind = 'memberAvailable',
    String? destinationRefId = 'vo',
    int amountMinor = 1000,
    String clientTxId = 'client-1',
    String? statusId,
    String? reversalOfTxId,
    String? correctsTxId,
  }) {
    final now = DateTime(2026, 9, 1);
    return TransactionRowsCompanion.insert(
      id: id,
      type: 'income',
      categoryId: categoryId,
      sourceKind: sourceKind,
      sourceRefId: Value(sourceRefId),
      destinationKind: destinationKind,
      destinationRefId: Value(destinationRefId),
      amountMinor: amountMinor,
      transactionDate: now,
      createdAt: now,
      clientTxId: clientTxId,
      statusId: Value(statusId),
      reversalOfTxId: Value(reversalOfTxId),
      correctsTxId: Value(correctsTxId),
    );
  }

  group('Insert cơ bản từng bảng', () {
    test('Test 1/4/5 — insert Fund/SavingsAssetType/Category thành công', () async {
      await db
          .into(db.fundRows)
          .insert(FundRowsCompanion.insert(id: 'f1', name: 'Quỹ tiền ăn', colorValue: 1));
      await db
          .into(db.savingsAssetTypeRows)
          .insert(SavingsAssetTypeRowsCompanion.insert(id: 's1', name: 'Tiền mặt', colorValue: 1));
      await insertCategory('c1');

      // DB được seed sẵn dữ liệu mặc định lúc tạo mới (`seedDefaults`) —
      // chỉ kiểm tra đúng bản ghi vừa thêm có mặt, không giả định DB rỗng.
      expect(
        await (db.select(db.fundRows)..where((r) => r.id.equals('f1'))).getSingleOrNull(),
        isNotNull,
      );
      expect(
        await (db.select(
          db.savingsAssetTypeRows,
        )..where((r) => r.id.equals('s1'))).getSingleOrNull(),
        isNotNull,
      );
      expect(
        await (db.select(db.categoryRows)..where((r) => r.id.equals('c1'))).getSingleOrNull(),
        isNotNull,
      );
    });

    test('Test 2 — insert Status thuộc đúng Category (qua FK)', () async {
      await insertCategory('c1');
      await insertStatus('st1', 'c1');

      final row = await (db.select(
        db.statusRows,
      )..where((r) => r.id.equals('st1'))).getSingle();
      expect(row.categoryId, 'c1');
    });

    test('Test 6 — insert Transaction lưu đầy đủ source/destination', () async {
      await insertCategory('c1');
      await db
          .into(db.transactionRows)
          .insert(txCompanion(id: 'tx1', categoryId: 'c1', destinationRefId: 'vo'));

      final row = await db.select(db.transactionRows).getSingle();
      expect(row.sourceKind, 'external');
      expect(row.destinationKind, 'memberAvailable');
      expect(row.destinationRefId, 'vo');
      expect(row.amountMinor, 1000);
    });
  });

  group('clientTxId unique (idempotency contract)', () {
    test('Test 7 — 2 giao dịch cùng clientTxId → cái thứ 2 bị reject', () async {
      await insertCategory('c1');
      await db
          .into(db.transactionRows)
          .insert(txCompanion(id: 'tx1', categoryId: 'c1', clientTxId: 'dup'));

      expect(
        () => db
            .into(db.transactionRows)
            .insert(txCompanion(id: 'tx2', categoryId: 'c1', clientTxId: 'dup')),
        throwsA(isA<SqliteException>()),
      );

      expect(await db.select(db.transactionRows).get(), hasLength(1));
    });

    test(
      'clientTxId khác nhau (kể cả trùng ý nghĩa nghiệp vụ) vẫn insert được bình thường',
      () async {
        await insertCategory('c1');
        await db
            .into(db.transactionRows)
            .insert(txCompanion(id: 'tx1', categoryId: 'c1', clientTxId: 'a'));
        await db
            .into(db.transactionRows)
            .insert(txCompanion(id: 'tx2', categoryId: 'c1', clientTxId: 'b'));

        expect(await db.select(db.transactionRows).get(), hasLength(2));
      },
    );
  });

  group('Foreign key thật sự enforce', () {
    test('Test 9 — Transaction.categoryId trỏ tới category không tồn tại → reject', () async {
      expect(
        () => db.into(db.transactionRows).insert(txCompanion(id: 'tx1', categoryId: 'khong_ton_tai')),
        throwsA(isA<SqliteException>()),
      );
    });

    test('Test 9 — Transaction.statusId trỏ tới status không tồn tại → reject', () async {
      await insertCategory('c1');
      expect(
        () => db.into(db.transactionRows).insert(
          txCompanion(id: 'tx1', categoryId: 'c1', statusId: 'khong_ton_tai'),
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('Status.categoryId trỏ tới category không tồn tại → reject', () async {
      expect(() => insertStatus('st1', 'khong_ton_tai'), throwsA(isA<SqliteException>()));
    });
  });

  group('Atomic database transaction', () {
    test('Test 11 — write A + write B lỗi → cả A và B đều rollback', () async {
      await insertCategory('c1');

      await expectLater(
        db.transaction(() async {
          await db.into(db.categoryRows).insert(
            CategoryRowsCompanion.insert(id: 'c2', name: 'c2', colorValue: 0, type: 'expense'),
          );
          // Vi phạm FK (category không tồn tại) để buộc transaction fail.
          await db.into(db.transactionRows).insert(txCompanion(id: 'tx1', categoryId: 'khong_ton_tai'));
        }),
        throwsA(isA<SqliteException>()),
      );

      // c2 phải bị rollback theo cùng transaction với tx1, dù bản thân
      // câu insert c2 không lỗi (DB có seed data mặc định, chỉ kiểm tra c2
      // không tồn tại chứ không giả định category rỗng).
      final c2 = await (db.select(
        db.categoryRows,
      )..where((r) => r.id.equals('c2'))).getSingleOrNull();
      expect(c2, isNull, reason: 'c2 phải rollback cùng transaction với tx1 lỗi');
      expect(await db.select(db.transactionRows).get(), isEmpty);
    });
  });

  group('Reversal ledger persistence', () {
    test('Test 12 — lưu được Original/Reversal/Replacement và đúng quan hệ', () async {
      await insertCategory('c1');
      await db.into(db.transactionRows).insert(txCompanion(id: 'orig', categoryId: 'c1', clientTxId: 'a'));

      // Sửa giao dịch = reversal + replacement (mục 21) — 3 bản ghi tồn tại
      // song song, KHÔNG update/xoá bản gốc.
      await db
          .into(db.transactionRows)
          .insert(txCompanion(id: 'rev', categoryId: 'c1', clientTxId: 'a-reversal', reversalOfTxId: 'orig'));
      await db.into(db.transactionRows).insert(
        txCompanion(id: 'repl', categoryId: 'c1', clientTxId: 'a-2', correctsTxId: 'orig', amountMinor: 2000),
      );
      await (db.update(db.transactionRows)..where((r) => r.id.equals('orig'))).write(
        const TransactionRowsCompanion(reversedByTxId: Value('rev')),
      );

      final rows = {for (final r in await db.select(db.transactionRows).get()) r.id: r};
      expect(rows['orig']!.reversedByTxId, 'rev');
      expect(rows['orig']!.amountMinor, 1000, reason: 'bản gốc KHÔNG bị mutate');
      expect(rows['rev']!.reversalOfTxId, 'orig');
      expect(rows['repl']!.correctsTxId, 'orig');
      expect(rows['repl']!.amountMinor, 2000);
      expect(await db.select(db.transactionRows).get(), hasLength(3), reason: 'append-only, không xoá bản gốc');
    });

    test('Không hoàn tác 2 lần trên cùng 1 giao dịch (Invariant 13, enforce ở domain/DB lưu đủ tin để kiểm tra)', () async {
      await insertCategory('c1');
      await db.into(db.transactionRows).insert(txCompanion(id: 'orig', categoryId: 'c1', clientTxId: 'a'));
      await (db.update(db.transactionRows)..where((r) => r.id.equals('orig'))).write(
        const TransactionRowsCompanion(reversedByTxId: Value('rev1')),
      );

      final row = await (db.select(
        db.transactionRows,
      )..where((r) => r.id.equals('orig'))).getSingle();
      expect(
        row.reversedByTxId != null,
        isTrue,
        reason: 'repository/domain dựa vào field này để chặn hoàn tác lần 2',
      );
    });
  });

  group('Migration v3 → v4 (giữ dữ liệu, thêm FK + unique index)', () {
    test('Test 10 — migrate từ schema v3 (không FK/index) lên v4 không mất dữ liệu hợp lệ', () async {
      final dir = Directory.systemTemp.createTempSync('vnm_migration_test');
      final file = File('${dir.path}/legacy.sqlite');
      addTearDown(() => dir.deleteSync(recursive: true));

      // Dựng thủ công 1 file sqlite đúng shape schema v3 (trước Phase 2:
      // không FK, không unique index) bằng package:sqlite3 trực tiếp, rồi
      // seed vài dòng dữ liệu "đã có từ trước".
      final legacy = sqlite3_pkg.sqlite3.open(file.path);
      legacy.execute('''
        CREATE TABLE category_rows (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          color_value INTEGER NOT NULL,
          type TEXT NOT NULL,
          stats_enabled INTEGER NOT NULL DEFAULT 0,
          exclude_from_totals INTEGER NOT NULL DEFAULT 0,
          linked_expense_category_id TEXT NULL,
          is_default INTEGER NOT NULL DEFAULT 1,
          is_active INTEGER NOT NULL DEFAULT 1
        );
        CREATE TABLE status_rows (
          id TEXT NOT NULL PRIMARY KEY,
          category_id TEXT NOT NULL,
          name TEXT NOT NULL,
          sort_order INTEGER NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1
        );
        CREATE TABLE transaction_rows (
          id TEXT NOT NULL PRIMARY KEY,
          type TEXT NOT NULL,
          transfer_kind TEXT NULL,
          category_id TEXT NOT NULL,
          source_kind TEXT NOT NULL,
          source_ref_id TEXT NULL,
          destination_kind TEXT NOT NULL,
          destination_ref_id TEXT NULL,
          amount_minor INTEGER NOT NULL,
          currency TEXT NOT NULL DEFAULT 'VND',
          note TEXT NOT NULL DEFAULT '',
          status_id TEXT NULL,
          status_updated_at INTEGER NULL,
          transaction_date INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          reversal_of_tx_id TEXT NULL,
          corrects_tx_id TEXT NULL,
          reversed_by_tx_id TEXT NULL,
          client_tx_id TEXT NOT NULL,
          version INTEGER NOT NULL DEFAULT 1
        );
        CREATE TABLE fund_rows (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          color_value INTEGER NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1
        );
        CREATE TABLE savings_asset_type_rows (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          color_value INTEGER NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1
        );
      ''');
      legacy.execute('''
        INSERT INTO category_rows (id, name, color_value, type)
        VALUES ('c1', 'Sinh hoạt', 255, 'expense');
      ''');
      legacy.execute('''
        INSERT INTO transaction_rows
          (id, type, category_id, source_kind, destination_kind, destination_ref_id,
           amount_minor, transaction_date, created_at, client_tx_id)
        VALUES
          ('tx-old', 'income', 'c1', 'external', 'memberAvailable', 'vo',
           500000, 1756684800000, 1756684800000, 'legacy-client-1');
      ''');
      legacy.execute('PRAGMA user_version = 3;');
      legacy.close();

      // Mở lại đúng file đó bằng AppDatabase hiện tại (schemaVersion 4) —
      // Drift phải tự chạy onUpgrade(3, 4) = `_migrateToV4`.
      final migrated = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(migrated.close);

      final categories = await migrated.select(migrated.categoryRows).get();
      final txs = await migrated.select(migrated.transactionRows).get();
      expect(categories.map((c) => c.id), ['c1']);
      expect(txs, hasLength(1));
      expect(txs.single.id, 'tx-old');
      expect(txs.single.amountMinor, 500000);
      expect(txs.single.clientTxId, 'legacy-client-1');

      // Constraint MỚI (FK + unique clientTxId) phải có hiệu lực sau migrate.
      expect(
        () => migrated
            .into(migrated.transactionRows)
            .insert(txCompanion(id: 'tx-new', categoryId: 'khong_ton_tai')),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => migrated
            .into(migrated.transactionRows)
            .insert(txCompanion(id: 'tx-new-2', categoryId: 'c1', clientTxId: 'legacy-client-1')),
        throwsA(isA<SqliteException>()),
      );
    });

    test(
      'Migration rollback — dữ liệu v3 vi phạm unique index mới → migration fail sạch, '
      'không kẹt DB ở trạng thái dở dang (bảng cũ mất, bảng mới chưa xong)',
      () async {
        final dir = Directory.systemTemp.createTempSync('vnm_migration_rollback_test');
        final file = File('${dir.path}/legacy_bad.sqlite');
        addTearDown(() => dir.deleteSync(recursive: true));

        // 2 transaction cùng client_tx_id — HỢP LỆ ở schema v3 (chưa có
        // unique), nhưng sẽ vi phạm unique index mới lúc copy sang v4.
        final legacy = sqlite3_pkg.sqlite3.open(file.path);
        legacy.execute('''
          CREATE TABLE category_rows (
            id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, color_value INTEGER NOT NULL,
            type TEXT NOT NULL, stats_enabled INTEGER NOT NULL DEFAULT 0,
            exclude_from_totals INTEGER NOT NULL DEFAULT 0, linked_expense_category_id TEXT NULL,
            is_default INTEGER NOT NULL DEFAULT 1, is_active INTEGER NOT NULL DEFAULT 1
          );
          CREATE TABLE status_rows (
            id TEXT NOT NULL PRIMARY KEY, category_id TEXT NOT NULL, name TEXT NOT NULL,
            sort_order INTEGER NOT NULL, is_active INTEGER NOT NULL DEFAULT 1
          );
          CREATE TABLE transaction_rows (
            id TEXT NOT NULL PRIMARY KEY, type TEXT NOT NULL, transfer_kind TEXT NULL,
            category_id TEXT NOT NULL, source_kind TEXT NOT NULL, source_ref_id TEXT NULL,
            destination_kind TEXT NOT NULL, destination_ref_id TEXT NULL, amount_minor INTEGER NOT NULL,
            currency TEXT NOT NULL DEFAULT 'VND', note TEXT NOT NULL DEFAULT '', status_id TEXT NULL,
            status_updated_at INTEGER NULL, transaction_date INTEGER NOT NULL, created_at INTEGER NOT NULL,
            reversal_of_tx_id TEXT NULL, corrects_tx_id TEXT NULL, reversed_by_tx_id TEXT NULL,
            client_tx_id TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1
          );
          CREATE TABLE fund_rows (
            id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, color_value INTEGER NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1
          );
          CREATE TABLE savings_asset_type_rows (
            id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, color_value INTEGER NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1
          );
        ''');
        legacy.execute('''
          INSERT INTO category_rows (id, name, color_value, type) VALUES ('c1', 'Sinh hoạt', 255, 'expense');
        ''');
        legacy.execute('''
          INSERT INTO transaction_rows
            (id, type, category_id, source_kind, destination_kind, destination_ref_id,
             amount_minor, transaction_date, created_at, client_tx_id)
          VALUES
            ('tx-a', 'income', 'c1', 'external', 'memberAvailable', 'vo', 1000, 1756684800000, 1756684800000, 'dup'),
            ('tx-b', 'income', 'c1', 'external', 'memberAvailable', 'vo', 2000, 1756684800000, 1756684800000, 'dup');
        ''');
        legacy.execute('PRAGMA user_version = 3;');
        legacy.close();

        final migrated = AppDatabase.forTesting(NativeDatabase(file));
        await expectLater(
          migrated.select(migrated.categoryRows).get(),
          throwsA(anything),
        );
        try {
          await migrated.close();
        } catch (_) {
          // Migration fail khi mở — close() có thể ném lại lỗi tương tự, bỏ qua.
        }

        // Mở lại file thô bằng sqlite3 (không qua Drift) để xác nhận rollback
        // sạch: bảng gốc `transaction_rows` (v3, 2 row) còn nguyên, KHÔNG có
        // bảng tạm `_v3` nào sót lại từ nửa chừng migration.
        final raw = sqlite3_pkg.sqlite3.open(file.path);
        addTearDown(raw.close);
        final tableNames = raw
            .select("SELECT name FROM sqlite_master WHERE type = 'table'")
            .map((row) => row['name'] as String)
            .toSet();
        expect(tableNames, contains('transaction_rows'));
        expect(tableNames, isNot(contains('transaction_rows_v3')));
        expect(tableNames, isNot(contains('status_rows_v3')));
        final rowCount =
            raw.select('SELECT COUNT(*) AS c FROM transaction_rows').first['c'];
        expect(rowCount, 2, reason: 'dữ liệu gốc phải còn nguyên vẹn sau rollback, không mất/nhân đôi');
      },
    );
  });

  group('Migration v4 → v5 (Phase 8.6 — thêm recovery_of_tx_id)', () {
    /// Dựng file schema v4 thủ công (đúng shape trước Phase 8.6: có FK +
    /// unique index nhưng CHƯA có `recovery_of_tx_id`), seed vài dòng dữ
    /// liệu đã có từ trước.
    File buildV4Fixture(String path) {
      final file = File(path);
      final legacy = sqlite3_pkg.sqlite3.open(file.path);
      legacy.execute('''
        CREATE TABLE category_rows (
          id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, color_value INTEGER NOT NULL,
          type TEXT NOT NULL, stats_enabled INTEGER NOT NULL DEFAULT 0,
          exclude_from_totals INTEGER NOT NULL DEFAULT 0, linked_expense_category_id TEXT NULL,
          is_default INTEGER NOT NULL DEFAULT 1, is_active INTEGER NOT NULL DEFAULT 1
        );
        CREATE TABLE status_rows (
          id TEXT NOT NULL PRIMARY KEY,
          category_id TEXT NOT NULL REFERENCES category_rows (id),
          name TEXT NOT NULL, sort_order INTEGER NOT NULL, is_active INTEGER NOT NULL DEFAULT 1
        );
        CREATE INDEX ix_status_category ON status_rows (category_id);
        CREATE TABLE transaction_rows (
          id TEXT NOT NULL PRIMARY KEY, type TEXT NOT NULL, transfer_kind TEXT NULL,
          category_id TEXT NOT NULL REFERENCES category_rows (id), source_kind TEXT NOT NULL,
          source_ref_id TEXT NULL, destination_kind TEXT NOT NULL, destination_ref_id TEXT NULL,
          amount_minor INTEGER NOT NULL, currency TEXT NOT NULL DEFAULT 'VND',
          note TEXT NOT NULL DEFAULT '', status_id TEXT NULL REFERENCES status_rows (id),
          status_updated_at INTEGER NULL, transaction_date INTEGER NOT NULL, created_at INTEGER NOT NULL,
          reversal_of_tx_id TEXT NULL, corrects_tx_id TEXT NULL, reversed_by_tx_id TEXT NULL,
          client_tx_id TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1
        );
        CREATE UNIQUE INDEX ux_transaction_client_tx_id ON transaction_rows (client_tx_id);
        CREATE INDEX ix_transaction_source ON transaction_rows (source_kind, source_ref_id);
        CREATE INDEX ix_transaction_destination ON transaction_rows (destination_kind, destination_ref_id);
        CREATE INDEX ix_transaction_category_status ON transaction_rows (category_id, status_id);
        CREATE TABLE fund_rows (
          id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, color_value INTEGER NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1
        );
        CREATE TABLE savings_asset_type_rows (
          id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, color_value INTEGER NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1
        );
      ''');
      legacy.execute('''
        INSERT INTO category_rows (id, name, color_value, type) VALUES ('c1', 'Sinh hoạt', 255, 'expense');
      ''');
      legacy.execute('''
        INSERT INTO transaction_rows
          (id, type, category_id, source_kind, destination_kind, destination_ref_id,
           amount_minor, transaction_date, created_at, client_tx_id)
        VALUES
          ('tx-old', 'expense', 'c1', 'memberAvailable', 'external', NULL,
           2000000, 1756684800000, 1756684800000, 'v4-client-1');
      ''');
      legacy.execute('PRAGMA user_version = 4;');
      legacy.close();
      return file;
    }

    test(
      'migrate từ schema v4 (chưa có recovery_of_tx_id) lên v5 không mất dữ liệu, '
      'mọi row cũ có recoveryOfTxId = null',
      () async {
        final dir = Directory.systemTemp.createTempSync('vnm_migration_v5_test');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = buildV4Fixture('${dir.path}/v4.sqlite');

        final migrated = AppDatabase.forTesting(NativeDatabase(file));
        addTearDown(migrated.close);

        final txs = await migrated.select(migrated.transactionRows).get();
        expect(txs, hasLength(1));
        expect(txs.single.id, 'tx-old');
        expect(txs.single.amountMinor, 2000000);
        expect(
          txs.single.recoveryOfTxId,
          isNull,
          reason: 'dữ liệu cũ KHÔNG được reinterpret — mục 3 MIGRATION STRATEGY',
        );

        // Constraint cũ (FK + unique clientTxId) vẫn còn hiệu lực sau migrate.
        expect(
          () => migrated
              .into(migrated.transactionRows)
              .insert(txCompanion(id: 'tx-new', categoryId: 'khong_ton_tai')),
          throwsA(isA<SqliteException>()),
        );

        // Cột/field mới dùng được bình thường.
        await migrated.into(migrated.transactionRows).insert(
          txCompanion(id: 'recovery-1', categoryId: 'c1', clientTxId: 'v5-client-1'),
        );
        await (migrated.update(migrated.transactionRows)..where((r) => r.id.equals('recovery-1')))
            .write(const TransactionRowsCompanion(recoveryOfTxId: Value('tx-old')));
        final recovery = await (migrated.select(
          migrated.transactionRows,
        )..where((r) => r.id.equals('recovery-1'))).getSingle();
        expect(recovery.recoveryOfTxId, 'tx-old');
      },
    );

    test(
      'Migration rollback — nếu bước rename giữa chừng fail (bảng tạm _v4 đã tồn tại '
      'sẵn từ 1 lần migrate dở dang trước đó) → dữ liệu gốc v4 còn nguyên, không kẹt DB',
      () async {
        final dir = Directory.systemTemp.createTempSync('vnm_migration_v5_rollback_test');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = buildV4Fixture('${dir.path}/v4_bad.sqlite');

        // Mô phỏng 1 lần migrate dở dang trước đó: bảng tạm `_v4` đã tồn
        // tại sẵn — bước `ALTER TABLE ... RENAME TO transaction_rows_v4`
        // thật sẽ fail vì trùng tên, buộc toàn bộ `transaction()` rollback.
        final raw = sqlite3_pkg.sqlite3.open(file.path);
        raw.execute('CREATE TABLE transaction_rows_v4 (dummy INTEGER)');
        raw.close();

        final migrated = AppDatabase.forTesting(NativeDatabase(file));
        await expectLater(
          migrated.select(migrated.categoryRows).get(),
          throwsA(anything),
        );
        try {
          await migrated.close();
        } catch (_) {
          // Migration fail khi mở — close() có thể ném lại lỗi tương tự.
        }

        final rawAfter = sqlite3_pkg.sqlite3.open(file.path);
        addTearDown(rawAfter.close);
        final tableNames = rawAfter
            .select("SELECT name FROM sqlite_master WHERE type = 'table'")
            .map((row) => row['name'] as String)
            .toSet();
        expect(tableNames, contains('transaction_rows'), reason: 'bảng gốc phải còn nguyên (chưa từng đổi tên thành công)');
        expect(
          tableNames.where((n) => n == 'transaction_rows_v4').length,
          1,
          reason: 'chỉ còn đúng cái bảng dummy đã tạo TRƯỚC migration — không có bảng _v4 THẬT nào được tạo thêm',
        );
        final rowCount =
            rawAfter.select('SELECT COUNT(*) AS c FROM transaction_rows').first['c'];
        expect(rowCount, 1, reason: 'dữ liệu v4 gốc còn nguyên vẹn sau rollback');

        final cols = rawAfter
            .select("PRAGMA table_info(transaction_rows)")
            .map((row) => row['name'] as String)
            .toSet();
        expect(
          cols,
          isNot(contains('recovery_of_tx_id')),
          reason: 'schema chưa hề được nâng cấp — đúng nghĩa rollback sạch, không nửa vời',
        );
      },
    );
  });
}
