import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import '../../core/utils/opaque_id.dart';
import '../../domain/entities/wallet_identity.dart';
import 'seed_defaults.dart';
import 'wallet_descriptor.dart';

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
@TableIndex(name: 'ix_transaction_obligation', columns: {#obligationId})
@TableIndex(name: 'ix_transaction_settlement_group', columns: {#settlementGroupId})
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
  /// Phase 8.7 — giao dịch này thuộc `Obligation.id` nào (Cho vay/Đi vay).
  /// KHÔNG khai báo FK — cùng lý do 3 field self-reference + `recovery_of_tx_id`
  /// ở trên (tương thích sync Firestore Giai đoạn B, eventual consistency).
  TextColumn get obligationId => text().nullable()();
  /// Phase 8.7 — ghép cặp 2 leg (gốc + lãi) của CÙNG 1 lần tất toán
  /// Receivable. `null` khi tất toán chỉ có 1 dòng. Xem doc-comment field
  /// tương ứng ở `domain/entities/transaction.dart` — field BẮT BUỘC lưu
  /// riêng (không suy ra được từ `clientTxId`).
  TextColumn get settlementGroupId => text().nullable()();
  TextColumn get clientTxId => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Phase 8.7 — 1 bên ngoài gia đình liên quan Cho vay/Đi vay. Metadata
/// thuần, giống hệt `FundRows` (KHÔNG cache số liệu tài chính nào).
class CounterpartyRows extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Phase 8.7 — neo giữ metadata 1 khoản vay/cho vay (`Obligation`). KHÔNG
/// cache `originalPrincipal`/`outstanding` — tính động từ
/// `TransactionRows.obligationId` (xem `compute_obligation_summary.dart`).
@TableIndex(name: 'ix_obligation_counterparty', columns: {#counterpartyId})
class ObligationRows extends Table {
  TextColumn get id => text()();
  TextColumn get counterpartyId =>
      text().references(CounterpartyRows, #id)();
  TextColumn get direction => text()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

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

  /// v7: phân loại báo cáo cho danh mục Chi (`business_expense` hoặc NULL =
  /// Chi tiêu). Thêm bằng `ADD COLUMN` — không đụng dữ liệu cũ.
  TextColumn get groupKey => text().nullable()();
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

/// Loại tài sản tiết kiệm tự đặt (Gửi ngân hàng, Vàng, Chứng khoán, Bất
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

/// v8 — danh tính Wallet của DB này. SINGLETON: đúng 1 dòng (khóa chính `singleton`
/// bị CHECK = 1 ⇒ không thể có dòng thứ hai, kể cả khi migration chạy lại). `walletId`
/// là ID mờ sinh 1 lần rồi giữ vĩnh viễn — KHÔNG suy ra từ email/vai trò/thiết bị/số
/// liệu. `kind`: `local` (chưa gắn Account nào).
@DataClassName('WalletMetaRow')
class WalletMeta extends Table {
  IntColumn get singleton =>
      // ignore: recursive_getters (cách khai báo CHECK của Drift tham chiếu chính cột)
      integer().withDefault(const Constant(1)).check(singleton.equals(1))();
  TextColumn get walletId => text().unique()();
  TextColumn get kind => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {singleton};
}

/// v8 — danh tính tài chính ổn định của từng người trong Wallet. CHƯA có tài khoản,
/// email, quyền hay lời mời (thuộc các phase Account/Membership). Với Wallet di sản,
/// `member_id` là `vo` / `chong` — đúng chuỗi đang nằm trong `*_ref_id` của giao dịch
/// (không phải viết lại dòng nào); Wallet mới dùng ID mờ.
class FinancialMemberRows extends Table {
  TextColumn get memberId => text()();
  TextColumn get label => text()();
  IntColumn get displayOrder => integer()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {memberId};
}

@DriftDatabase(
  tables: [
    TransactionRows,
    CategoryRows,
    StatusRows,
    FundRows,
    SavingsAssetTypeRows,
    CounterpartyRows,
    ObligationRows,
    WalletMeta,
    FinancialMemberRows,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// DB thật trên máy: người dùng mới bắt đầu với bộ seed TỐI GIẢN
  /// ([SeedProfile.fresh]).
  AppDatabase({
    this.seedProfile = SeedProfile.fresh,
    WalletDescriptor wallet = WalletDescriptor.legacyLocal,
  }) : super(_openWalletConnection(wallet));

  /// Dùng cho unit/widget test: cơ sở dữ liệu tạm trong bộ nhớ, không đụng
  /// file thật trên máy. Mặc định seed đầy đủ của hộ chủ dự án
  /// ([SeedProfile.demo]) để test cũ/golden không đổi; test seed mới truyền
  /// `seed: SeedProfile.fresh`.
  AppDatabase.forTesting(
    super.executor, {
    SeedProfile seed = SeedProfile.demo,
  }) : seedProfile = seed;

  /// Bộ seed dùng khi file DB được tạo mới.
  final SeedProfile seedProfile;

  /// Tăng mỗi lần đổi schema. Version 1-3: app chưa từng phát hành, chưa có
  /// dữ liệu người dùng thật cần giữ, nên `onUpgrade` cho các version cũ này
  /// vẫn xoá sạch rồi tạo lại (giữ nguyên hành vi lịch sử, không sửa lại).
  /// Từ version 4 trở đi (Phase 2 — Database Foundation), migration PHẢI
  /// giữ dữ liệu thật: thêm FK (`categoryId`/`statusId`) + unique index
  /// (`clientTxId`) yêu cầu SQLite recreate bảng (FK chỉ khai báo được lúc
  /// `CREATE TABLE`), nên dùng pattern rename → tạo bảng mới → copy dữ liệu
  /// → xoá bảng cũ, không `DROP` thẳng. Version 5 (Phase 8.6) thêm
  /// `recovery_of_tx_id` — cùng pattern, cùng lý do (cột mới + index mới
  /// trên bảng đã có FK/unique index từ v4). Version 6 (Phase 8.7) thêm 2
  /// bảng mới `counterparty_rows`/`obligation_rows` (thuần cộng thêm,
  /// `createTable` không cần rename gì) + 2 cột mới trên `transaction_rows`
  /// (`obligation_id`, `settlement_group_id`) — cùng pattern rename →
  /// recreate → copy → drop như v4→v5 (bảng đã có FK/unique index từ v4).
  /// Version 8 (P2 — Local Wallet Identity): thêm 2 bảng THUẦN CỘNG THÊM
  /// (`wallet_meta`, `financial_member_rows`), không đụng dòng/cột nào của dữ liệu cũ.
  @override
  int get schemaVersion => 8;

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
      if (from < 6) {
        await transaction(() => _migrateToV6(m));
      }
      if (from < 7) {
        // v6 → v7: chỉ ADD COLUMN nullable (`category_rows.group_key`). Dữ
        // liệu cũ giữ nguyên; danh mục Chi hiện có mặc định NULL (= Chi
        // tiêu) — không UPDATE theo tên/Ghi chú, không viết lại giao dịch.
        await m.addColumn(categoryRows, categoryRows.groupKey);
      }
      if (from < 8) {
        // v7 → v8: 2 bảng mới + danh tính Wallet di sản. ATOMIC: lỗi ở bất kỳ bước
        // nào ⇒ rollback toàn bộ, DB vẫn là v7 hợp lệ (không có Wallet nửa vời).
        await transaction(() => _migrateToV8(m));
      }
    },
    beforeOpen: (details) async {
      // sqlite3 tắt FK enforcement theo mặc định mỗi connection — phải bật
      // lại mỗi lần mở DB (không chỉ lúc tạo mới).
      await customStatement('PRAGMA foreign_keys = ON');
      if (details.wasCreated) {
        await seedDefaults(this, seedProfile);
        await _ensureWalletIdentity(
          legacyIds: seedProfile == SeedProfile.demo,
        );
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
  /// Tạo (idempotent) danh tính Wallet của DB này: đúng 1 dòng `wallet_meta` + 2
  /// thành viên tài chính mặc định. Chạy lại KHÔNG tạo bản sao (singleton + khóa chính
  /// + `insertOrIgnore`).
  ///
  /// [legacyIds] = true (nâng cấp v7→v8 và [SeedProfile.demo]): dùng ID di sản `vo` /
  /// `chong` — đúng chuỗi đã nằm trong `*_ref_id` của giao dịch hiện có (không viết lại
  /// dòng nào). false (Wallet MỚI, [SeedProfile.fresh]): ID mờ ổn định ([OpaqueId]),
  /// không suy từ nhãn/vai trò. Từ P4 mã tài chính không còn phân biệt hai kiểu này —
  /// mọi thành viên đều đi qua bảng `financial_member_rows`.
  Future<void> _ensureWalletIdentity({required bool legacyIds}) async {
    final now = DateTime.now();
    await into(walletMeta).insert(
      WalletMetaCompanion.insert(
        walletId: OpaqueId.generate(),
        kind: WalletKind.local.name,
        createdAt: now,
      ),
      mode: InsertMode.insertOrIgnore,
    );
    // Seed nhãn mặc định (i18n: chuyển sang .arb ở phase i18n).
    const defaults = [('vo', 'Vợ'), ('chong', 'Chồng')];
    if (!legacyIds &&
        (await select(financialMemberRows).get()).isNotEmpty) {
      return;
    }
    for (final (index, member) in defaults.indexed) {
      await into(financialMemberRows).insert(
        FinancialMemberRowsCompanion.insert(
          memberId: legacyIds ? member.$1 : OpaqueId.generate(),
          label: member.$2,
          displayOrder: index,
          createdAt: now,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }

  Future<void> _migrateToV8(Migrator m) async {
    await m.createTable(walletMeta);
    await m.createTable(financialMemberRows);
    await _ensureWalletIdentity(legacyIds: true);
  }

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

  /// v5 → v6 (Phase 8.7): thêm 2 bảng mới (`CounterpartyRows`/
  /// `ObligationRows` — `createTable` thẳng, KHÔNG có dữ liệu cũ cần copy)
  /// + 2 cột mới trên `transaction_rows` (`obligation_id`,
  /// `settlement_group_id`, cả 2 TEXT NULL, không FK — cùng lý do các field
  /// self-reference khác). Cùng pattern rename → recreate → copy → drop như
  /// v4→v5 cho `transaction_rows` (cột mới mặc định NULL cho MỌI row cũ —
  /// KHÔNG reinterpret dữ liệu có sẵn, kể cả dòng "Chị hằng mượn tiền về
  /// quê" trong golden 2026 — vẫn giữ nguyên là Expense bình thường, không
  /// tự gắn `obligationId`).
  Future<void> _migrateToV6(Migrator m) async {
    await m.createTable(counterpartyRows);
    await m.createTable(obligationRows);
    await m.createIndex(ixObligationCounterparty);

    await customStatement(
      'ALTER TABLE transaction_rows RENAME TO transaction_rows_v5',
    );
    await customStatement('DROP INDEX IF EXISTS ux_transaction_client_tx_id');
    await customStatement('DROP INDEX IF EXISTS ix_transaction_source');
    await customStatement('DROP INDEX IF EXISTS ix_transaction_destination');
    await customStatement('DROP INDEX IF EXISTS ix_transaction_category_status');
    await customStatement('DROP INDEX IF EXISTS ix_transaction_recovery_of');
    await m.createTable(transactionRows);
    await m.createIndex(uxTransactionClientTxId);
    await m.createIndex(ixTransactionSource);
    await m.createIndex(ixTransactionDestination);
    await m.createIndex(ixTransactionCategoryStatus);
    await m.createIndex(ixTransactionRecoveryOf);
    await m.createIndex(ixTransactionObligation);
    await m.createIndex(ixTransactionSettlementGroup);
    await customStatement(
      'INSERT INTO transaction_rows (id, type, transfer_kind, category_id, '
      'source_kind, source_ref_id, destination_kind, destination_ref_id, '
      'amount_minor, currency, note, status_id, status_updated_at, '
      'transaction_date, created_at, reversal_of_tx_id, corrects_tx_id, '
      'reversed_by_tx_id, recovery_of_tx_id, obligation_id, '
      'settlement_group_id, client_tx_id, version) '
      'SELECT id, type, transfer_kind, category_id, source_kind, '
      'source_ref_id, destination_kind, destination_ref_id, amount_minor, '
      'currency, note, status_id, status_updated_at, transaction_date, '
      'created_at, reversal_of_tx_id, corrects_tx_id, reversed_by_tx_id, '
      'recovery_of_tx_id, NULL, NULL, client_tx_id, version '
      'FROM transaction_rows_v5',
    );
    await customStatement('DROP TABLE transaction_rows_v5');
  }
}

QueryExecutor _openWalletConnection(WalletDescriptor wallet) {
  return LazyDatabase(() async {
    await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, wallet.dbFileName));
    return NativeDatabase.createInBackground(file);
  });
}
