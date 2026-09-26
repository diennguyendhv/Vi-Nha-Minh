import 'dart:io';

import 'package:drift/native.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/seed_defaults.dart';
import 'package:vi_nha_minh/data/sync/restore_engine.dart';

/// Test: ví khôi phục là file tạm KHÔNG mã hoá (SQLCipher thật: `restore_storage.dart`).
class TempRestoreStorage implements RestoreStorage {
  TempRestoreStorage(this.dir);
  final Directory dir;
  final opened = <AppDatabase>[];
  File _f(String n) => File('${dir.path}/$n');
  @override
  Future<AppDatabase> open(String n) async {
    final db = AppDatabase.forTesting(NativeDatabase(_f(n)), seed: SeedProfile.none);
    opened.add(db);
    return db;
  }

  @override
  Future<void> markRestoring(String n) => _f('$n.restoring').writeAsString('');
  @override
  Future<void> clearMarker(String n) => _f('$n.restoring').delete();
  @override
  Future<void> discard(String n) async {
    for (final s in ['', '-wal', '-shm', '-journal', '.restoring']) {
      if (_f('$n$s').existsSync()) _f('$n$s').deleteSync();
    }
  }
}

