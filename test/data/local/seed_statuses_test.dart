import 'package:drift/native.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/constants/default_categories.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';

/// Seed DB MỚI của CĐ/DH phải giữ đúng bộ 4 trạng thái đang dùng thật trên
/// Pixel (tên + thứ tự đọc nguyên văn từ DB); hai hạng mục giữ workflow RIÊNG.
void main() {
  test('CĐ: CCB → ĐCB → ĐG → ĐD; DH: CCB → ĐCB → ĐD → ĐG (mỗi bộ 4 bước, id ổn định)', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    Future<List<String>> names(String categoryId) async {
      final rows = await (db.select(db.statusRows)
            ..where((s) => s.categoryId.equals(categoryId))
            ..orderBy([(s) => OrderingTerm.asc(s.sortOrder)]))
          .get();
      expect(rows.every((r) => r.isActive), isTrue);
      return rows.map((r) => r.name).toList();
    }

    expect(await names('cho_di'), ['CCB', 'ĐCB', 'ĐG', 'ĐD']);
    expect(await names('dang_hien'), ['CCB', 'ĐCB', 'ĐD', 'ĐG']);

    final ids = (await db.select(db.statusRows).get()).map((r) => r.id).toList();
    expect(ids.toSet().length, ids.length, reason: 'không trùng id');
    expect(DefaultCategories.choDi.statuses.length, 4);
    expect(DefaultCategories.dangHien.statuses.length, 4);
  });
}
