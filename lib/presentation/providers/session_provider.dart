import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_environment.dart';
import '../../data/backup/backup_service.dart';
import '../../data/cloud/wallet_claim_service.dart';
import '../../domain/auth/cloud_session.dart';
import 'database_provider.dart';

final cloudSessionProvider = Provider<CloudSession?>((ref) => null);

/// DEV-only zero-knowledge backup (fixture data; SQLCipher gate still closed).
final backupServiceProvider = Provider<BackupService?>((ref) => null);

/// P8.2 claim ví đang mở (DEV only; null khi không có phiên cloud). Dựng lại theo DB
/// của ví đang hoạt động — không giữ tham chiếu tới ví trước.
final walletClaimServiceProvider = Provider<WalletClaimService?>((ref) {
  final session = ref.watch(cloudSessionProvider);
  if (session == null || !WalletClaimService.allowedIn(AppEnvironment.current)) {
    return null;
  }
  return WalletClaimService(
    session: session,
    transport: session.transport,
    db: ref.watch(appDatabaseProvider),
    registry: ref.watch(walletRegistryProvider),
    dbFileName: ref.watch(activeWalletProvider).dbFileName,
  );
});
