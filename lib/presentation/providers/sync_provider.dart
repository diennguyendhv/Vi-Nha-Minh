import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_environment.dart';
import '../../data/backup/backup_key_store.dart';
import '../../data/cloud/family_device_key_store.dart';
import '../../data/cloud/family_service.dart';
import '../../domain/entities/wallet_identity.dart';
import '../../data/sync/cloud_sync_engine.dart';
import '../../data/sync/remote_signal.dart';
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
  final registry = ref.watch(walletRegistryProvider);
  return CloudSyncEngine(
    db: ref.watch(appDatabaseProvider),
    session: session,
    transport: session.transport,
    keyStore: ref.watch(backupKeyStoreProvider),
    // P10: Owner đã thu hồi ⇒ ẩn ví Family này khỏi UI thường (file/khoá giữ nguyên).
    onMembershipLost: (walletId) async {
      if (registry.byWalletId(walletId)?.kind != WalletKind.family) return;
      await registry.setFamilyFlags(walletId, accessRevoked: true);
      ref.read(walletRegistryRevisionProvider.notifier).state++;
    },
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

/// P10 tín hiệu thay đổi từ xa (FCM). `main` override khi có Firebase; test/không
/// Firebase ⇒ null (đồng bộ vẫn chạy khi mở app / bấm "Đồng bộ ngay").
final remoteChangeSignalProvider = Provider<RemoteChangeSignal?>((ref) => null);

final remoteSignalRegistrarProvider = Provider<RemoteSignalRegistrar?>((ref) {
  final session = ref.watch(cloudSessionProvider);
  if (session == null || ref.watch(remoteChangeSignalProvider) == null) {
    return null;
  }
  return RemoteSignalRegistrar(session: session, transport: session.transport);
});

/// P10: Account trên máy này là MEMBER (không phải Owner) của ví Family đang mở ⇒ ẩn
/// thao tác chỉ Owner có (đổi Mật khẩu sao lưu, tạo lại Recovery Key).
final activeWalletIsFamilyMemberProvider = Provider<bool>((ref) {
  ref.watch(walletRegistryRevisionProvider);
  final walletId = ref.watch(activeWalletProvider).walletId;
  if (walletId == null) return false;
  return ref.watch(walletRegistryProvider).byWalletId(walletId)?.familyMember ??
      false;
});

/// P10 khoá thiết bị Family (Keystore). Test override bằng bản bộ nhớ.
final familyDeviceKeyStoreProvider = Provider<FamilyDeviceKeyStore>(
  (ref) => KeystoreFamilyDeviceKeyStore(),
);

/// P10 Family (chỉ DEV + có phiên cloud). Gắn với ví đang mở (phía Owner); phía
/// Member dùng để tham gia ví (khôi phục vào ví MỚI).
final familyServiceProvider = Provider<FamilyService?>((ref) {
  final session = ref.watch(cloudSessionProvider);
  if (session == null || !FamilyService.allowedIn(AppEnvironment.current)) {
    return null;
  }
  final denied = ref.watch(walletAccessDeniedProvider);
  return FamilyService(
    session: session,
    transport: session.transport,
    keyStore: ref.watch(backupKeyStoreProvider),
    deviceKeys: ref.watch(familyDeviceKeyStoreProvider),
    registry: ref.watch(walletRegistryProvider),
    db: denied ? null : ref.watch(appDatabaseProvider),
    dbFileName: denied ? null : ref.watch(activeWalletProvider).dbFileName,
    restore: ref.watch(restoreEngineProvider),
  );
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
