import 'package:drift/drift.dart';

import '../app_database.dart';

/// P8.1 — ghi nhận thay đổi cục bộ cho sao lưu mã hoá tăng dần.
///
/// Cơ chế: trigger SQLite AFTER INSERT/UPDATE/DELETE trên MỌI bảng dữ liệu Wallet
/// ([syncCapturedTables]). Trigger nằm ở tầng DB nên mọi đường ghi (repository,
/// xoá cả họ, customUpdate, migration tương lai) đều được bắt — không phụ thuộc
/// từng repository nhớ gọi. Trigger CHỈ ghi khi:
///  - `cloud_binding.state = 'ACTIVE'` (ví chưa claim ⇒ không sinh việc đồng bộ), và
///  - không đang ở cửa sổ [withoutSyncCapture] (ghi nội bộ của restore/sync).
///
/// Outbox chỉ lưu (loại, id cục bộ, upsert|delete) — KHÔNG nội dung. Gộp: mỗi thực
/// thể 1 dòng, thay đổi sau thắng (xoá ⇒ tombstone; tạo lại ⇒ upsert).

/// Bảng dữ liệu Wallet được đồng bộ → (loại thực thể, cột khoá chính).
/// Loại thực thể chỉ nằm trong DB cục bộ (đã mã hoá SQLCipher) và BÊN TRONG
/// ciphertext trên cloud (id cloud = HMAC(IDK, kind‖localId)).
const syncCapturedTables = <String, ({String kind, String pk})>{
  'transaction_rows': (kind: 'transaction', pk: 'id'),
  'category_rows': (kind: 'category', pk: 'id'),
  'status_rows': (kind: 'status', pk: 'id'),
  'fund_rows': (kind: 'fund', pk: 'id'),
  'savings_asset_type_rows': (kind: 'savingsAssetType', pk: 'id'),
  'counterparty_rows': (kind: 'counterparty', pk: 'id'),
  'obligation_rows': (kind: 'obligation', pk: 'id'),
  'financial_member_rows': (kind: 'financialMember', pk: 'member_id'),
  'wallet_settings': (kind: 'walletSetting', pk: 'key'),
};

/// Bảng CỐ Ý không đồng bộ, kèm lý do. Mọi bảng trong DB phải nằm ở đúng 1 trong
/// 2 danh sách (test phủ `test/data/local/sync_capture_test.dart`) — bảng tài chính
/// mới không thể lặng lẽ bị bỏ sót.
const syncExcludedTables = <String, String>{
  'wallet_meta':
      'danh tính container: walletId là khoá cloud, engine khôi phục ghi lại',
  'cloud_binding': 'hạ tầng đồng bộ cục bộ (ràng buộc Account/thiết bị)',
  'sync_outbox': 'hạ tầng đồng bộ cục bộ',
  'sync_state': 'hạ tầng đồng bộ cục bộ (con trỏ/cờ tắt ghi nhận)',
  'sync_conflicts': 'bản cục bộ bị máy chủ thay thế — chỉ để người dùng xem lại',
};

String _triggerName(String table, String op) => 'sync_capture_${table}_$op';

/// Tên 3 trigger của [table] (dùng cho test phủ).
List<String> syncTriggerNames(String table) => [
  for (final op in const ['insert', 'update', 'delete']) _triggerName(table, op),
];

const _when =
    "EXISTS (SELECT 1 FROM cloud_binding WHERE state = 'ACTIVE') "
    'AND NOT EXISTS (SELECT 1 FROM sync_state WHERE capture_suppressed = 1)';

const _now = "CAST(strftime('%s', 'now') AS INTEGER)";

/// DELETE rồi INSERT thường (không OR REPLACE): chính sách xung đột của câu lệnh
/// NGOÀI (vd INSERT OR IGNORE) ghi đè chính sách trong trigger, nên OR REPLACE
/// trong trigger có thể bị biến thành IGNORE và làm hỏng việc gộp.
String _enqueue(String kind, String idExpr, String op) =>
    "DELETE FROM sync_outbox WHERE entity_kind = '$kind' AND entity_id = $idExpr; "
    'INSERT INTO sync_outbox (entity_kind, entity_id, op, changed_at, attempts) '
    "VALUES ('$kind', $idExpr, '$op', $_now, 0);";

/// Tạo (lại) trigger ghi nhận — idempotent. Gọi ở `onCreate` và migration v10.
Future<void> installSyncCaptureTriggers(GeneratedDatabase db) async {
  for (final MapEntry(key: table, value: spec) in syncCapturedTables.entries) {
    final k = spec.kind;
    final pk = spec.pk;
    for (final name in syncTriggerNames(table)) {
      await db.customStatement('DROP TRIGGER IF EXISTS $name');
    }
    await db.customStatement(
      'CREATE TRIGGER ${_triggerName(table, 'insert')} AFTER INSERT ON $table '
      'WHEN $_when BEGIN ${_enqueue(k, 'NEW.$pk', 'upsert')} END',
    );
    // Đổi khoá chính (hiếm) = tombstone id cũ + upsert id mới.
    await db.customStatement(
      'CREATE TRIGGER ${_triggerName(table, 'update')} AFTER UPDATE ON $table '
      'WHEN $_when BEGIN '
      "DELETE FROM sync_outbox WHERE entity_kind = '$k' AND entity_id = OLD.$pk "
      'AND OLD.$pk IS NOT NEW.$pk; '
      'INSERT INTO sync_outbox (entity_kind, entity_id, op, changed_at, attempts) '
      "SELECT '$k', OLD.$pk, 'delete', $_now, 0 WHERE OLD.$pk IS NOT NEW.$pk; "
      '${_enqueue(k, 'NEW.$pk', 'upsert')} END',
    );
    await db.customStatement(
      'CREATE TRIGGER ${_triggerName(table, 'delete')} AFTER DELETE ON $table '
      'WHEN $_when BEGIN ${_enqueue(k, 'OLD.$pk', 'delete')} END',
    );
  }
}

/// Chạy [action] (ghi nội bộ của restore/đồng bộ kéo về) mà KHÔNG sinh outbox.
/// Cờ được bật và tắt trong CÙNG 1 DB transaction: lỗi/crash ⇒ rollback cả cờ,
/// không bao giờ để ghi nhận bị tắt vĩnh viễn. Drift tuần tự hoá transaction nên
/// ghi của người dùng không thể chen vào cửa sổ này.
Future<T> withoutSyncCapture<T>(AppDatabase db, Future<T> Function() action) =>
    db.transaction(() async {
      await db.customStatement(
        'INSERT INTO sync_state (singleton, capture_suppressed) VALUES (1, 1) '
        'ON CONFLICT(singleton) DO UPDATE SET capture_suppressed = 1',
      );
      final result = await action();
      await db.customStatement(
        'UPDATE sync_state SET capture_suppressed = 0 WHERE singleton = 1',
      );
      return result;
    });

/// Hàng đợi outbox cho engine đẩy (P8.2). Chỉ đọc danh tính/ý định.
class SyncOutboxStore {
  SyncOutboxStore(this._db);
  final AppDatabase _db;

  Future<List<SyncOutboxRow>> pending({int limit = 100}) =>
      (_db.select(_db.syncOutbox)
            ..orderBy([(o) => OrderingTerm.asc(o.seq)])
            ..limit(limit))
          .get();

  Future<int> count() async =>
      (await _db.customSelect('SELECT COUNT(*) AS n FROM sync_outbox').getSingle())
          .read<int>('n');

  /// Xác nhận đã đẩy — theo `seq` CHÍNH XÁC: thay đổi mới hơn của cùng thực thể
  /// (đã có `seq` mới) không bị xoá.
  Future<void> acknowledge(Iterable<int> seqs) =>
      (_db.delete(_db.syncOutbox)..where((o) => o.seq.isIn(seqs))).go();

  /// Mốc nền khi claim chuyển ACTIVE (P8.2 gọi): xếp hàng upsert MỌI dòng hiện có
  /// của mọi bảng đồng bộ (kể cả danh mục hệ thống — ví khôi phục là rỗng tuyệt đối).
  Future<void> enqueueFullSnapshot() => _db.transaction(() async {
    for (final MapEntry(key: table, value: spec) in syncCapturedTables.entries) {
      await _db.customStatement(
        "DELETE FROM sync_outbox WHERE entity_kind = '${spec.kind}' "
        'AND entity_id IN (SELECT ${spec.pk} FROM $table)',
      );
      await _db.customStatement(
        'INSERT INTO sync_outbox (entity_kind, entity_id, op, changed_at, attempts) '
        "SELECT '${spec.kind}', ${spec.pk}, 'upsert', $_now, 0 FROM $table",
      );
    }
  });
}
