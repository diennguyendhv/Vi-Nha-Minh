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
class TransactionRows extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()();
  TextColumn get transferKind => text().nullable()();
  TextColumn get categoryId => text()();
  TextColumn get sourceKind => text()();
  TextColumn get sourceRefId => text().nullable()();
  TextColumn get destinationKind => text()();
  TextColumn get destinationRefId => text().nullable()();
  IntColumn get amountMinor => integer()();
  TextColumn get currency => text().withDefault(const Constant('VND'))();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get statusId => text().nullable()();
  DateTimeColumn get statusUpdatedAt => dateTime().nullable()();
  DateTimeColumn get transactionDate => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get reversalOfTxId => text().nullable()();
  TextColumn get correctsTxId => text().nullable()();
  TextColumn get reversedByTxId => text().nullable()();
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
class StatusRows extends Table {
  TextColumn get id => text()();
  TextColumn get categoryId => text()();
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

@DriftDatabase(tables: [TransactionRows, CategoryRows, StatusRows, FundRows])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Dùng cho unit/widget test: cơ sở dữ liệu tạm trong bộ nhớ, không đụng
  /// file thật trên máy.
  AppDatabase.forTesting(super.executor);

  /// V2 — schema cũ (V1: `TransactionRows` shape cũ + `FundEntryRows`) chưa
  /// từng phát hành, chưa có dữ liệu người dùng thật cần giữ lại. Nâng cấp
  /// đơn giản là xoá sạch bảng cũ rồi tạo lại theo schema mới, KHÔNG có
  /// bước migrate/transform dữ liệu — máy đang có data demo V1 sẽ mất khi
  /// cập nhật app.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      await customStatement('DROP TABLE IF EXISTS transaction_rows');
      await customStatement('DROP TABLE IF EXISTS fund_entry_rows');
      await customStatement('DROP TABLE IF EXISTS category_rows');
      await customStatement('DROP TABLE IF EXISTS status_rows');
      await customStatement('DROP TABLE IF EXISTS fund_rows');
      await m.createAll();
    },
    beforeOpen: (details) async {
      if (details.wasCreated) {
        await seedDefaults(this);
      }
    },
  );
}

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'vi_nha_minh.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
