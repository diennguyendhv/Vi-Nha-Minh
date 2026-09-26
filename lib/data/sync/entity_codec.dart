import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/sync/sync_capture.dart';

/// Nội dung sao lưu không hợp lệ (sai schema, cột lạ, id lệch…). Không ghi gì.
class EntityCodecException implements Exception {
  const EntityCodecException(this.reason);
  final String reason;
  @override
  String toString() => 'EntityCodecException($reason)';
}

/// P8.3 — tuần tự hoá CHUẨN TẮC 1 dòng dữ liệu Wallet (nằm BÊN TRONG ciphertext).
///
/// Body = `{"s": <schema>, "c": {cột: giá trị SQLite thô}}` hoặc tombstone
/// `{"s": <schema>, "deleted": true}`. Giá trị lấy nguyên văn từ SQLite (số nguyên,
/// chuỗi, NULL; blob → `{"$b": base64}`) nên khôi phục là CHÍNH XÁC từng cột, không
/// phụ thuộc locale/định dạng ngày/tiền. Khoá sắp xếp ⇒ cùng dòng ⇒ cùng JSON.
/// Loại thực thể + id cục bộ thật đi kèm ở lớp envelope (cũng bên trong ciphertext).
abstract final class EntityCodec {
  /// kind → (bảng, cột khoá chính) — đảo từ [syncCapturedTables].
  static final Map<String, ({String table, String pk})> tables = {
    for (final MapEntry(key: table, value: spec) in syncCapturedTables.entries)
      spec.kind: (table: table, pk: spec.pk),
  };

  static ({String table, String pk}) _spec(String kind) =>
      tables[kind] ?? (throw const EntityCodecException('unknown-kind'));

  static Object? _encodeValue(Object? v) => switch (v) {
    null || int() || String() => v,
    double() => v.isFinite ? v : throw const EntityCodecException('non-finite'),
    Uint8List() => {r'$b': base64.encode(v)},
    _ => throw const EntityCodecException('unsupported-value'),
  };

  static Object? _decodeValue(Object? v) {
    if (v == null || v is int || v is String || v is double) return v;
    if (v is Map && v.length == 1 && v[r'$b'] is String) {
      return base64.decode(v[r'$b'] as String);
    }
    throw const EntityCodecException('unsupported-value');
  }

  /// JSON chuẩn tắc (khoá sắp xếp đệ quy) — dùng cho so sánh/digest.
  static String canonicalJson(Object? value) => jsonEncode(_sorted(value));
  static Object? _sorted(Object? v) => switch (v) {
    Map() => {
      for (final k in (v.keys.map((k) => k as String).toList()..sort()))
        k: _sorted(v[k]),
    },
    List() => [for (final e in v) _sorted(e)],
    _ => v,
  };

  /// Body hiện tại của thực thể; `null` nếu dòng không còn (⇒ đẩy tombstone).
  static Future<Map<String, Object?>?> read(
    AppDatabase db,
    String kind,
    String localId,
  ) async {
    final spec = _spec(kind);
    final row = await db
        .customSelect(
          'SELECT * FROM ${spec.table} WHERE ${spec.pk} = ?',
          variables: [Variable.withString(localId)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    final cols = <String, Object?>{};
    final names = row.data.keys.toList()..sort();
    for (final name in names) {
      cols[name] = _encodeValue(row.data[name]);
    }
    return {'s': db.schemaVersion, 'c': cols};
  }

  static Map<String, Object?> tombstone(AppDatabase db) => {
    's': db.schemaVersion,
    'deleted': true,
  };

  static bool isTombstone(Map<String, Object?> body) => body['deleted'] == true;

  static Future<Map<String, ({bool notNull, bool hasDefault})>> _columns(
    AppDatabase db,
    String table,
  ) async => {
    for (final r in await db.customSelect('PRAGMA table_info($table)').get())
      r.read<String>('name'): (
        notNull: r.read<int>('notnull') == 1,
        hasDefault: r.data['dflt_value'] != null,
      ),
  };

  /// Kiểm tra body theo schema cục bộ; trả về các cột đã giải mã.
  static Future<Map<String, Object?>> validate(
    AppDatabase db,
    String kind,
    String localId,
    Map<String, Object?> body,
  ) async {
    final spec = _spec(kind);
    final schema = body['s'];
    if (schema is! int || schema < 10) {
      throw const EntityCodecException('bad-schema');
    }
    // Bản sao lưu từ app MỚI hơn: không đoán nghĩa cột lạ — cần cập nhật app.
    if (schema > db.schemaVersion) {
      throw const EntityCodecException('newer-schema');
    }
    if (isTombstone(body)) {
      if (body.keys.toSet().difference({'s', 'deleted'}).isNotEmpty) {
        throw const EntityCodecException('bad-tombstone');
      }
      return const {};
    }
    final raw = body['c'];
    if (raw is! Map || body.keys.toSet().difference({'s', 'c'}).isNotEmpty) {
      throw const EntityCodecException('bad-body');
    }
    final local = await _columns(db, spec.table);
    final cols = <String, Object?>{};
    for (final MapEntry(:key, :value) in raw.entries) {
      if (key is! String || !local.containsKey(key)) {
        throw const EntityCodecException('unknown-column');
      }
      cols[key] = _decodeValue(value);
    }
    // Cột thêm ở schema sau (thuần cộng thêm) phải nullable hoặc có mặc định.
    for (final MapEntry(key: name, value: c) in local.entries) {
      if (!cols.containsKey(name) && c.notNull && !c.hasDefault) {
        throw const EntityCodecException('missing-column');
      }
    }
    if (cols[spec.pk] != localId) throw const EntityCodecException('id-mismatch');
    return cols;
  }

  /// Ghi (upsert) hoặc xoá 1 thực thể đã [validate]. Gọi TRONG `withoutSyncCapture`.
  /// Upsert dùng `ON CONFLICT DO UPDATE` (không `OR REPLACE`: không xoá ngầm).
  static Future<void> apply(
    AppDatabase db,
    String kind,
    String localId,
    Map<String, Object?> body,
  ) async {
    final spec = _spec(kind);
    final cols = await validate(db, kind, localId, body);
    if (isTombstone(body)) {
      await db.customStatement(
        'DELETE FROM ${spec.table} WHERE ${spec.pk} = ?',
        [localId],
      );
      return;
    }
    final names = cols.keys.toList()..sort();
    final updates = [
      for (final n in names)
        if (n != spec.pk) '$n = excluded.$n',
    ];
    await db.customStatement(
      'INSERT INTO ${spec.table} (${names.join(', ')}) '
      'VALUES (${List.filled(names.length, '?').join(', ')}) '
      'ON CONFLICT(${spec.pk}) DO '
      '${updates.isEmpty ? 'NOTHING' : 'UPDATE SET ${updates.join(', ')}'}',
      [for (final n in names) cols[n]],
    );
  }
}
