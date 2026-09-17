import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import 'seed_defaults.dart';

part 'app_database.g.dart';

/// Bảng giao dịch — khớp 1-1 với domain entity `Transaction` (Financial
/// Core V2, `docs/financial-core-v2.md` mục 6) để migrate lên Firestore ở
/// Giai đoạn B chỉ là copy nguyên văn, không transform. Append-only cho mọi
/// field ảnh hưởng balance — sửa/xoá luôn tạo bản ghi mới (mục 21).
///
/// Không có cột `familyId`: Giai đoạn A là local-first, 1 gia đình ngầm
/// định/máy (`spec.md` dòng 73-74 — `families/{familyId}` chỉ sinh ra trên
/// Firestore khi có người thứ 2 tham gia ở Giai đoạn B). `clientTxId` do đó
/// unique toàn cục là đủ tương đương `UNIQUE(familyId, clientTxId)`.
///
/// `sourceRefId`/`destinationRefId` KHÔNG có FK — polymorphic theo
/// `sourceKind`/`destinationKind` (member enum/`FundRows`/
/// `SavingsAssetTypeRows`/external), SQLite không biểu diễn được FK có điều
/// kiện. Integrity phần này do Domain/Repository đảm nhiệm.
@TableIndex(name: 'ux_transaction_client_tx_id', columns: {#clientTxId}, unique: true)
@TableIndex(name: 'ix_transaction_source', columns: {#sourceKind, #sourceRefId})
@TableIndex(
  name: 'ix_transaction_destination',
  columns: {#destinationKind, #destinationRefId},
)
@TableIndex(name: 'ix_transaction_category_status', columns: {#categoryId, #statusId})
@TableIndex(name: 'ix_transaction_recovery_of', columns: {#recoveryOfTxId})
class TransactionRows extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()();
  TextColumn get transferKind => text().nullable()();
  TextColumn get categoryId => text().references(CategoryRows, #id)();
  TextColumn get sourceKind => text()();
  TextColumn get sourceRefId => text().nullable()();
  TextColumn get destinationKind => text()();
  TextColumn get destinationRefId => text().nullable()();
  IntColumn get amountMinor => integer()();
  TextColumn get currency => text().withDefault(const Constant('VND'))();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get statusId => text().nullable().references(StatusRows, #id)();
  DateTimeColumn get statusUpdatedAt => dateTime().nullable()();
  DateTimeColumn get transactionDate => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get reversalOfTxId => text().nullable()();
  TextColumn get correctsTxId => text().nullable()();
  TextColumn get reversedByTxId => text().nullable()();
  /// Phase 8.6 — giao dịch THU HỒI/HOÀN TIỀN trỏ về `id` của giao dịch Chi
  /// gốc. KHÔNG khai báo FK (giống 3 field self-reference phía trên) — lý
  /// do tương tự: tương thích sync Firestore Giai đoạn B (eventual
  /// consistency, bản ghi con có thể tới trước bản gốc).
  TextColumn get recoveryOfTxId => text().nullable()();
  TextColumn get clientTxId => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Danh mục — nhãn báo cáo, KHÔNG quyết định dòng tiền (`Category`, mục 11).
class CategoryRows extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get colorValue => integer()();
  TextColumn get type => text()();
  BoolColumn get statsEnabled => boolean().withDefault(const Constant(false))();
  BoolColumn get excludeFromTotals =>
      boolean().withDefault(const Constant(false))();
  TextColumn get linkedExpenseCategoryId => text().nullable()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(true))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Bước trạng thái con của 1 danh mục (`Status`) — bảng riêng để CRUD/sắp
/// xếp độc lập từng bước, khớp shape subcollection Firestore ở Giai đoạn B.
@TableIndex(name: 'ix_status_category', columns: {#categoryId})
class StatusRows extends Table {
  TextColumn get id => text()();
  TextColumn get categoryId => text().references(CategoryRows, #id)();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Quỹ — chỉ còn identity (id/tên/màu), KHÔNG cache `balance` (tính động từ
/// `TransactionRows`, xem `computeFundBalance`).
class FundRows extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get colorValue => integer()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Loại tài sản tiết kiệm tự đặt (Tiền mặt, Ngân hàng, Chứng khoán, Bất
/// động sản...) — mỗi loại là 1 pool riêng CHO TỪNG thành viên (khác
/// `FundRows`, dùng chung cả nhà). KHÔNG cache balance, tương tự `FundRows`.
class SavingsAssetTypeRows extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get colorValue => integer()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [TransactionRows, CategoryRows, StatusRows, FundRows, SavingsAssetTypeRows],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Dùng cho unit/widget test: cơ sở dữ liệu tạm trong bộ nhớ, không đụng
  /// file thật trên máy.
  AppDatabase.forTesting(super.executor);

  /// Tăng mỗi lần đổi schema. Version 1-3: app chưa từng phát hành, chưa có
  /// dữ liệu người dùng thật cần giữ, nên `onUpgrade` cho các version cũ này
  /// vẫn xoá sạch rồi tạo lại (giữ nguyên hành vi lịch sử, không sửa lại).
  /// Từ version 4 trở đi (Phase 2 — Database Foundation), migration PHẢI
  /// giữ dữ liệu thật: thêm FK (`categoryId`/`statusId`) + unique index
  /// (`clientTxId`) yêu cầu SQLite recreate bảng (FK chỉ khai báo được lúc
  /// `CREATE TABLE`), nên dùng pattern rename → tạo bảng mới → copy dữ liệu
  /// → xoá bảng cũ, không `DROP` thẳng. Version 5 (Phase 8.6) thêm
  /// `recovery_of_tx_id` — cùng pattern, cùng lý do (cột mới + index mới
  /// trên bảng đã có FK/unique index từ v4).
  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 3) {
        await customStatement('DROP TABLE IF EXISTS transaction_rows');
        await customStatement('DROP TABLE IF EXISTS fund_entry_rows');
        await customStatement('DROP TABLE IF EXISTS category_rows');
        await customStatement('DROP TABLE IF EXISTS status_rows');
        await customStatement('DROP TABLE IF EXISTS fund_rows');
        await customStatement('DROP TABLE IF EXISTS savings_asset_type_rows');
        await m.createAll();
        return;
      }
      if (from < 4) {
        // Bọc trong transaction() để nếu 1 bước giữa chừng fail (vd dữ liệu
        // cũ vô tình có 2 row trùng clientTxId — vi phạm unique index mới),
        // toàn bộ rename/create/copy/drop đều rollback sạch thay vì để DB
        // kẹt ở trạng thái nửa vời (vd bảng `_v3` đã rename nhưng bảng mới
        // chưa kịp tạo). Phát hiện khi code review Phase 2 — sửa theo yêu
        // cầu review, không tự ý đổi thêm gì khác ngoài phạm vi này.
        await transaction(() => _migrateToV4(m));
      }
      if (from < 5) {
        // Cùng lý do atomicity như v3→v4 — rollback sạch nếu copy giữa
        // chừng lỗi, không để bảng `_v4` tạm sót lại.
        await transaction(() => _migrateToV5(m));
      }
    },
    beforeOpen: (details) async {
      // sqlite3 tắt FK enforcement theo mặc định mỗi connection — phải bật
      // lại mỗi lần mở DB (không chỉ lúc tạo mới).
      await customStatement('PRAGMA foreign_keys = ON');
      if (details.wasCreated) {
        await seedDefaults(this);
      }
    },
  );

  /// v3 → v4: thêm FK `status_rows.category_id`, `transaction_rows.
  /// categoryId/statusId`, và unique index `clientTxId` — giữ nguyên dữ
  /// liệu hiện có bằng cách rename bảng cũ, tạo bảng mới theo schema hiện
  /// tại (đã có FK/index qua `@TableIndex`/`.references()`), copy dữ liệu,
  /// rồi xoá bảng cũ.
  ///
  /// KHÔNG cần tự bật/tắt `PRAGMA foreign_keys` ở đây: connection còn đang
  /// ở trạng thái mặc định (OFF) lúc migration chạy — Drift chỉ bật FK thật
  /// sự ở `beforeOpen` (chạy SAU khi `onUpgrade` xong), và SQLite còn không
  /// cho phép đổi pragma này giữa 1 transaction đang mở (no-op) — gọi ở đây
  /// sẽ không có tác dụng gì, dễ gây hiểu lầm nên đã bỏ.
  ///
  /// Thứ tự copy (status_rows trước, rồi mới transaction_rows) đã đảm bảo
  /// FK hợp lệ theo đúng dữ liệu gốc mà không cần tắt enforcement.
  Future<void> _migrateToV4(Migrator m) async {
    await customStatement('ALTER TABLE status_rows RENAME TO status_rows_v3');
    await m.createTable(statusRows);
    await m.createIndex(ixStatusCategory);
    await customStatement(
      'INSERT INTO status_rows (id, category_id, name, sort_order, is_active) '
      'SELECT id, category_id, name, sort_order, is_active FROM status_rows_v3',
    );
    await customStatement('DROP TABLE status_rows_v3');

    await customStatement(
      'ALTER TABLE transaction_rows RENAME TO transaction_rows_v3',
    );
    await m.createTable(transactionRows);
    await m.createIndex(uxTransactionClientTxId);
    await m.createIndex(ixTransactionSource);
    await m.createIndex(ixTransactionDestination);
    await m.createIndex(ixTransactionCategoryStatus);
    await customStatement(
      'INSERT INTO transaction_rows (id, type, transfer_kind, category_id, '
      'source_kind, source_ref_id, destination_kind, destination_ref_id, '
      'amount_minor, currency, note, status_id, status_updated_at, '
      'transaction_date, created_at, reversal_of_tx_id, corrects_tx_id, '
      'reversed_by_tx_id, client_tx_id, version) '
      'SELECT id, type, transfer_kind, category_id, source_kind, '
      'source_ref_id, destination_kind, destination_ref_id, amount_minor, '
      'currency, note, status_id, status_updated_at, transaction_date, '
      'created_at, reversal_of_tx_id, corrects_tx_id, reversed_by_tx_id, '
      'client_tx_id, version FROM transaction_rows_v3',
    );
    await customStatement('DROP TABLE transaction_rows_v3');
  }

  /// v4 → v5 (Phase 8.6): thêm cột `recovery_of_tx_id` (TEXT NULL, không FK
  /// — xem doc-comment trên field) + index `ix_transaction_recovery_of`.
  /// Cùng pattern rename → tạo bảng mới theo schema hiện tại → copy dữ liệu
  /// (cột mới mặc định NULL cho mọi row cũ — KHÔNG reinterpret dữ liệu có
  /// sẵn) → xoá bảng cũ.
  Future<void> _migrateToV5(Migrator m) async {
    await customStatement(
      'ALTER TABLE transaction_rows RENAME TO transaction_rows_v4',
    );
    // SQLite giữ nguyên TÊN index qua ALTER TABLE RENAME (index vẫn tên
    // "ux_transaction_client_tx_id" dù giờ trỏ vào transaction_rows_v4) —
    // phải drop tường minh trước khi tạo lại cùng tên trên bảng mới, nếu
    // không CREATE INDEX bên dưới sẽ báo "already exists".
    await customStatement('DROP INDEX IF EXISTS ux_transaction_client_tx_id');
    await customStatement('DROP INDEX IF EXISTS ix_transaction_source');
    await customStatement('DROP INDEX IF EXISTS ix_transaction_destination');
    await customStatement('DROP INDEX IF EXISTS ix_transaction_category_status');
    await m.createTable(transactionRows);
    await m.createIndex(uxTransactionClientTxId);
    await m.createIndex(ixTransactionSource);
    await m.createIndex(ixTransactionDestination);
    await m.createIndex(ixTransactionCategoryStatus);
    await m.createIndex(ixTransactionRecoveryOf);
    await customStatement(
      'INSERT INTO transaction_rows (id, type, transfer_kind, category_id, '
      'source_kind, source_ref_id, destination_kind, destination_ref_id, '
      'amount_minor, currency, note, status_id, status_updated_at, '
      'transaction_date, created_at, reversal_of_tx_id, corrects_tx_id, '
      'reversed_by_tx_id, recovery_of_tx_id, client_tx_id, version) '
      'SELECT id, type, transfer_kind, category_id, source_kind, '
      'source_ref_id, destination_kind, destination_ref_id, amount_minor, '
      'currency, note, status_id, status_updated_at, transaction_date, '
      'created_at, reversal_of_tx_id, corrects_tx_id, reversed_by_tx_id, '
      'NULL, client_tx_id, version FROM transaction_rows_v4',
    );
    await customStatement('DROP TABLE transaction_rows_v4');
  }
}

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'vi_nha_minh.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
