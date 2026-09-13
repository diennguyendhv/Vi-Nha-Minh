import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

part 'app_database.g.dart';

/// Bảng giao dịch lưu cục bộ trên máy (Giai đoạn A — local-first, trước khi
/// có Firebase). Khớp 1-1 với domain entity `Transaction` để việc migrate
/// lên Firestore sau này (Giai đoạn B, phase 27) chỉ là copy dữ liệu.
class TransactionRows extends Table {
  TextColumn get id => text()();
  TextColumn get categoryId => text()();
  IntColumn get amount => integer()();
  DateTimeColumn get date => dateTime()();
  TextColumn get spender => text()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get status => text().nullable()();
  TextColumn get savingsDestination => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Bảng nạp/mua của Quỹ (vd Quỹ tiền ăn), khớp domain entity `FundEntry`.
class FundEntryRows extends Table {
  TextColumn get id => text()();
  TextColumn get fundId => text()();
  TextColumn get kind => text()();
  IntColumn get amount => integer()();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [TransactionRows, FundEntryRows])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Dùng cho unit test: cơ sở dữ liệu tạm trong bộ nhớ, không đụng file thật.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;
}

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'vi_nha_minh.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
