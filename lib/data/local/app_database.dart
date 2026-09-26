import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/utils/opaque_id.dart';
import '../../domain/entities/wallet_identity.dart';
import 'db_encryption/db_key_store.dart';
import 'db_encryption/sqlcipher_wallet.dart';
import 'seed_defaults.dart';
import 'sync/sync_capture.dart';
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
  /// v9 — người thực hiện khoản Chi từ Quỹ (nullable; dòng cũ luôn null, không suy ngược).
  TextColumn get actorMemberId => text().nullable()();
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

/// v10 (P8.1) — ràng buộc Wallet ↔ cloud. SINGLETON; KHÔNG có dòng = `NONE`
/// (chưa claim). DB là nguồn sự thật; `wallet_registry.json` chỉ là cache. Chỉ đổi
/// qua `LocalCloudBindingRepository` bằng hành động claim TƯỜNG MINH (người dùng chọn
/// `selfMemberId`) — không bao giờ tự gắn chỉ vì đã đăng nhập Firebase.
@DataClassName('CloudBindingRow')
class CloudBinding extends Table {
  IntColumn get singleton =>
      // ignore: recursive_getters
      integer().withDefault(const Constant(1)).check(singleton.equals(1))();
  TextColumn get walletId => text()();
  TextColumn get accountId => text()();
  TextColumn get selfMemberId => text()();
  TextColumn get environment => text()();
  TextColumn get state =>
      // ignore: recursive_getters
      text().check(state.isIn(const ['NONE', 'CLAIMING', 'ACTIVE']))();
  TextColumn get claimRequestId => text().nullable()();

  /// Chỉ metadata phiên bản (KHÔNG khoá): cryptoVersion + rev keyring đã biết.
  IntColumn get cryptoVersion => integer().nullable()();
  IntColumn get keyringRev => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {singleton};

  @override
  List<String> get customConstraints => [
    "CHECK (state <> 'CLAIMING' OR claim_request_id IS NOT NULL)",
  ];
}

/// v10 (P8.1) — hàng đợi thay đổi bền cho sao lưu mã hoá. CHỈ danh tính + ý định
/// (loại thực thể, id cục bộ, upsert/delete) — KHÔNG BAO GIỜ chứa nội dung tài chính;
/// envelope mã hoá chỉ được tạo lúc đẩy, từ dòng HIỆN TẠI. Mỗi thực thể tối đa 1 dòng
/// (gộp); đổi lại ⇒ dòng mới với `seq` mới (AUTOINCREMENT, không tái dùng) để xác
/// nhận theo `seq` không nuốt thay đổi đến sau. Được ghi bởi trigger (`sync_capture`).
@DataClassName('SyncOutboxRow')
class SyncOutbox extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get entityKind => text()();
  TextColumn get entityId => text()();
  TextColumn get op =>
      // ignore: recursive_getters
      text().check(op.isIn(const ['upsert', 'delete']))();
  DateTimeColumn get changedAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {entityKind, entityId},
  ];
}

/// v10 (P8.1) — trạng thái đồng bộ cục bộ. SINGLETON; không có dòng = mặc định.
/// `captureSuppressed` chỉ được bật TRONG 1 DB transaction (`withoutSyncCapture`) —
/// crash/lỗi ⇒ rollback, cờ không bao giờ kẹt ở 1.
@DataClassName('SyncStateRow')
class SyncState extends Table {
  IntColumn get singleton =>
      // ignore: recursive_getters
      integer().withDefault(const Constant(1)).check(singleton.equals(1))();
  BoolColumn get captureSuppressed =>
      boolean().withDefault(const Constant(false))();

  /// `headRev` máy chủ đã biết gần nhất (con trỏ pull/CAS đẩy) — P8.2 dùng.
  IntColumn get serverHeadRev => integer().nullable()();
  DateTimeColumn get lastPushAt => dateTime().nullable()();
  DateTimeColumn get lastPullAt => dateTime().nullable()();

  /// v11 (P8.3): sao lưu mã hoá của ví này. `null` = chưa bật; `SEEDING` = đã bật,
  /// mốc nền đang được đẩy; `COMPLETE` = mốc nền đã được máy chủ xác nhận trọn vẹn
  /// (checkpoint) — từ đó chỉ còn delta.
  TextColumn get backupState => text().nullable().check(
    // ignore: recursive_getters
    backupState.isIn(const ['SEEDING', 'COMPLETE']),
  )();

  @override
  Set<Column> get primaryKey => {singleton};
}

/// v11 (P8.4/Family) — thay đổi cục bộ CHƯA đẩy bị thay thế bởi phiên bản máy chủ
/// (người khác đã sửa/xoá cùng thực thể trước). KHÔNG ghi đè im lặng: bản cục bộ được
/// giữ nguyên văn ở đây để người dùng xem lại. Chỉ nằm trong DB cục bộ (SQLCipher),
/// không bao giờ đồng bộ.
@DataClassName('SyncConflictRow')
class SyncConflicts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityKind => text()();
  TextColumn get entityId => text()();

  /// Dòng cục bộ (JSON chuẩn tắc của `entity_codec`) — `null` nếu thay đổi cục bộ là xoá.
  TextColumn get localBody => text().nullable()();

  /// Máy chủ: `upsert` hoặc `delete` đã thắng, tại revision [serverRev].
  TextColumn get serverOp => text()();
  IntColumn get serverRev => integer()();
  DateTimeColumn get detectedAt => dateTime()();
  BoolColumn get resolved => boolean().withDefault(const Constant(false))();
}

/// v10 (P8.1) — cài đặt thuộc WALLET (đồng bộ cùng ví), dạng khoá/giá trị. Khác
/// SharedPreferences (thiết bị). Hiện có: `primary_fund_id` (xem
/// `LocalWalletSettingsRepository`).
class WalletSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
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
    CloudBinding,
    SyncOutbox,
    SyncState,
    WalletSettings,
    SyncConflicts,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// DB thật trên máy: người dùng mới bắt đầu với bộ seed TỐI GIẢN
  /// ([SeedProfile.fresh]).
  ///
  /// Mọi file ví được mở bằng SQLCipher với khoá riêng của ví (Keystore) —
  /// xem `db_encryption/`. [directory] chỉ để test trỏ tới thư mục tạm.
  AppDatabase({
    this.seedProfile = SeedProfile.fresh,
    WalletDescriptor wallet = WalletDescriptor.legacyLocal,
    DbKeyStore keyStore = const KeystoreDbKeyStore(),
    Future<Directory> Function()? directory,
  }) : _keyStore = keyStore,
       _dbFileName = wallet.dbFileName,
       super(_openWalletConnection(wallet, keyStore, directory));

  /// Dùng cho unit/widget test: cơ sở dữ liệu tạm trong bộ nhớ, không đụng
  /// file thật trên máy. Mặc định seed đầy đủ của hộ chủ dự án
  /// ([SeedProfile.demo]) để test cũ/golden không đổi; test seed mới truyền
  /// `seed: SeedProfile.fresh`.
  AppDatabase.forTesting(
    super.executor, {
    SeedProfile seed = SeedProfile.demo,
  }) : seedProfile = seed,
       _keyStore = null,
       _dbFileName = null;

  final DbKeyStore? _keyStore;
  final String? _dbFileName;

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
  /// Version 10 (P8.1): 4 bảng THUẦN CỘNG THÊM (`cloud_binding`, `sync_outbox`,
  /// `sync_state`, `wallet_settings`) + trigger ghi nhận thay đổi; không ghi dòng nào.
  /// Version 11 (P8.3): `sync_state.backup_state` + bảng `sync_conflicts` (cộng thêm).
  @override
  int get schemaVersion => 11;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await installSyncCaptureTriggers(this);
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
      if (from < 9) {
        // v8 → v9: chỉ ADD COLUMN nullable `actor_member_id`; không viết lại dòng nào.
        // Các bước v4–v6 tạo lại bảng theo schema HIỆN TẠI (đã có cột) nên chỉ thêm khi thiếu.
        await transaction(() async {
          final cols = await customSelect('PRAGMA table_info(transaction_rows)').get();
          if (!cols.any((c) => c.read<String>('name') == 'actor_member_id')) {
            await m.addColumn(transactionRows, transactionRows.actorMemberId);
          }
        });
      }
      if (from < 10) {
        // v9 → v10: CHỈ tạo bảng mới + trigger. Không INSERT/UPDATE dòng nào; chưa có
        // cloud_binding ⇒ trigger không ghi gì. Lỗi ⇒ rollback, DB vẫn là v9.
        await transaction(() async {
          await m.createTable(cloudBinding);
          await m.createTable(syncOutbox);
          await m.createTable(syncState);
          await m.createTable(walletSettings);
          await installSyncCaptureTriggers(this);
        });
      }
      if (from < 11) {
        // v10 → v11 (P8.3): 1 cột nullable + 1 bảng mới. Không ghi dòng nào.
        // Idempotent như v9 (bảng tạo mới theo schema HIỆN TẠI đã có cột).
        await transaction(() async {
          final cols = await customSelect('PRAGMA table_info(sync_state)').get();
          if (!cols.any((c) => c.read<String>('name') == 'backup_state')) {
            await m.addColumn(syncState, syncState.backupState);
          }
          await m.createTable(syncConflicts);
        });
      }
    },
    beforeOpen: (details) async {
      // sqlite3 tắt FK enforcement theo mặc định mỗi connection — phải bật
      // lại mỗi lần mở DB (không chỉ lúc tạo mới).
      await customStatement('PRAGMA foreign_keys = ON');
      // Để INSERT OR REPLACE xoá ngầm 1 dòng vẫn kích hoạt trigger DELETE (tombstone).
      // Trigger chỉ ghi `sync_outbox` (không có trigger) ⇒ không đệ quy thật.
      await customStatement('PRAGMA recursive_triggers = ON');
      // SeedProfile.none: ví RỖNG TUYỆT ĐỐI cho khôi phục — kể cả wallet_meta/thành
      // viên (walletId lấy từ bản sao lưu, do engine khôi phục ghi).
      if (details.wasCreated && seedProfile != SeedProfile.none) {
        await seedDefaults(this, seedProfile);
        await _ensureWalletIdentity(
          legacyIds: seedProfile == SeedProfile.demo,
        );
      }
      // Ví mới: khoá DB được tạo trước khi có walletId ⇒ gắn ngay lần mở đầu.
      // Idempotent; khoá đã gắn ví khác ⇒ native từ chối.
      final store = _keyStore;
      final file = _dbFileName;
      if (store != null && file != null && lastDbEncryptionStatus[file] ==
          DbEncryptionStatus.encrypted) {
        final meta = await select(walletMeta).getSingleOrNull();
        if (meta != null) await store.bindWallet(file, meta.walletId);
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

/// Trạng thái mã hoá của lần mở gần nhất theo file ví (chỉ bộ nhớ; không có
/// khoá). Dùng cho màn Cài đặt/nghiệm thu.
final lastDbEncryptionStatus = <String, DbEncryptionStatus>{};

QueryExecutor _openWalletConnection(
  WalletDescriptor wallet,
  DbKeyStore keyStore,
  Future<Directory> Function()? directory,
) {
  return LazyDatabase(() async {
    final dbFolder = await (directory ?? getApplicationDocumentsDirectory)();
    final file = File(p.join(dbFolder.path, wallet.dbFileName));
    // Di trú bản rõ → SQLCipher (một lần, có kiểm chứng + rollback) hoặc lấy khoá.
    // Khoá mất ⇒ ném DbRecoveryRequired: KHÔNG bao giờ tạo khoá mới cho DB đã mã hoá.
    final plan = await WalletDbEncryption(keyStore).prepare(
      file,
      wallet.dbFileName,
    );
    lastDbEncryptionStatus[wallet.dbFileName] = plan.status;
    final key = plan.key;
    return NativeDatabase.createInBackground(
      file,
      setup: key == null ? null : (db) => applySqlcipherKey(db, key),
    );
  });
}
