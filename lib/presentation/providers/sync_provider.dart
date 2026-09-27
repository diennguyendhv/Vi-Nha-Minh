import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_environment.dart';
import '../../data/backup/backup_key_store.dart';
import '../../data/sync/cloud_sync_engine.dart';
import '../../data/sync/restore_engine.dart';
import '../../data/sync/restore_storage.dart';
import '../../data/sync/sync_worker.dart';
import 'database_provider.dart';
import 'session_provider.dart';

/// Khoá BMK trên máy (Keystore). Test override bằng bản bộ nhớ.
final backupKeyStoreProvider = Provider<BackupKeyStore>(
  (ref) => KeystoreBackupKeyStore(),
);

/// P8.3/P8.4 engine của ví ĐANG MỞ (chỉ DEV + có phiên cloud). Dựng lại khi đổi ví.
final cloudSyncEngineProvider = Provider<CloudSyncEngine?>((ref) {
  final session = ref.watch(cloudSessionProvider);
  if (session == null || AppEnvironment.current != AppEnvironment.dev) {
    return null;
  }
  if (ref.watch(walletAccessDeniedProvider)) return null;
  return CloudSyncEngine(
    db: ref.watch(appDatabaseProvider),
    session: session,
    transport: session.transport,
    keyStore: ref.watch(backupKeyStoreProvider),
  );
});

/// P8.4 worker nền của ví đang mở. Không thăm dò: chỉ chạy khi mở app/foreground,
/// khi bảng dữ liệu đổi (debounce), hoặc khi người dùng bấm "Đồng bộ ngay".
final syncWorkerProvider = Provider<SyncWorker?>((ref) {
  final engine = ref.watch(cloudSyncEngineProvider);
  if (engine == null) return null;
  final worker = SyncWorker(engine: engine, db: engine.db);
  // Debug-only: kết quả + số lời gọi mạng (không nội dung tài chính, không khoá).
  final sub = worker.outcomes.listen((o) {
    if (kDebugMode) {
      debugPrint(
        '[sync] outcome=${o.name} runs=${worker.runs} calls=${engine.calls}'
        '${worker.lastError == null ? '' : ' error=${worker.lastError}'}',
      );
    }
  });
  ref.onDispose(() {
    sub.cancel();
    worker.dispose();
  });
  return worker;
});

/// P8.5 khôi phục vào 1 ví MỚI (chỉ DEV + có phiên cloud).
final restoreEngineProvider = Provider<RestoreEngine?>((ref) {
  final session = ref.watch(cloudSessionProvider);
  if (session == null || AppEnvironment.current != AppEnvironment.dev) {
    return null;
  }
  return RestoreEngine(
    session: session,
    transport: session.transport,
    keyStore: ref.watch(backupKeyStoreProvider),
    registry: ref.watch(walletRegistryProvider),
    storage: SqlcipherRestoreStorage(),
  );
});
