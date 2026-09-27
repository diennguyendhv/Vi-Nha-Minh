import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/backup/backup_key_store.dart';
import 'data/backup/backup_service.dart';
import 'data/auth/firebase_bootstrap.dart';
import 'data/auth/firebase_auth_repository.dart';
import 'presentation/features/settings/sync_lifecycle_host.dart';
import 'presentation/providers/session_provider.dart';
import 'l10n/session_localizations.dart';
import 'data/local/db_encryption/db_preflight.dart';
import 'data/local/wallet_registry_bootstrap.dart';
import 'domain/entities/wallet_access_scope.dart';
import 'data/repositories/local_wallet_settings_repository.dart';
import 'data/security/method_channel_app_lock_platform.dart';
import 'presentation/features/security/db_recovery_screen.dart';
import 'presentation/features/security/lock_gate.dart';
import 'presentation/features/wallet_access/wallet_access_gate.dart';
import 'presentation/providers/app_lock_provider.dart';
import 'presentation/providers/auth_providers.dart';
import 'presentation/providers/database_provider.dart';
import 'presentation/providers/explorer_sort_provider.dart';
import 'presentation/providers/primary_fund_provider.dart';
import 'presentation/widgets/tap_guard.dart';

import 'package:google_fonts/google_fonts.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

// P5/P7: Firebase dùng cho Authentication và cổng phiên DEV. Dữ liệu tài chính vẫn
// hoàn toàn local-first (SQLite); không có đường tải dữ liệu tài chính lên cloud.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // App local-first không được phụ thuộc mạng để hiển thị đúng — tắt việc
  // google_fonts tự tải font qua mạng lúc chạy (mặc định của package), nếu
  // không sẽ ném Unhandled Exception khi máy không có internet (đã bắt được
  // lỗi này khi chạy thật trên điện thoại lúc không có mạng). Font sẽ dùng
  // font hệ thống thay Manrope cho tới khi bundle file font tĩnh vào app.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Quỹ chính của Trang chủ lưu bền vững (thiết lập hiển thị, không phải sổ cái).
  final prefs = await SharedPreferences.getInstance();

  // Mã hoá DB cục bộ (SQLCipher): di trú bản rõ → mã hoá một lần (kiểm chứng +
  // rollback) TRƯỚC khi bất kỳ thứ gì mở ví. Mất khoá ⇒ màn khôi phục, KHÔNG mở,
  // KHÔNG tạo khoá mới, KHÔNG ghi đè file.
  final dbRecovery = await preflightLocalWalletDatabase();
  if (dbRecovery != null) {
    runApp(DbRecoveryRequiredApp(reason: dbRecovery.reason));
    return;
  }

  // Khoá ứng dụng: đọc trạng thái từ native TRƯỚC `runApp` để nếu đã bật thì khung hình
  // đầu tiên là màn khoá (không có khung hình UI tài chính nào lộ ra).
  // Lỗi đọc ⇒ coi như bật + khoá (fail-closed) chỉ khi native báo bật; nếu không đọc được
  // hoàn toàn thì rơi về "tắt" sẽ mở app — nên ném lỗi thay vì đoán.
  final lockPlatform = MethodChannelAppLockPlatform();
  final lockStatus = await lockPlatform.status();

  // Không bao giờ ném: thiếu/sai cấu hình ⇒ Auth tắt, app local vẫn chạy.
  final authRepository = await bootstrapAuth();

  // Registry Wallet: đăng ký ví cục bộ hiện tại TẠI CHỖ (không di chuyển file, không
  // gắn Account). Không bao giờ ném.
  final walletRegistry = await bootstrapWalletRegistry();

  // Ví đang hoạt động không phải ví di sản (vd ví đã khôi phục): thiếu file/khoá ⇒ màn
  // cần khôi phục, không tạo ví rỗng mới, không lặng lẽ chuyển sang ví bootstrap.
  final uid = authRepository.currentAccount()?.uid;
  final active = walletRegistry.resolveActive(
    uid == null
        ? const WalletAccessScope.local()
        : WalletAccessScope.account(uid),
  );
  if (active != null) {
    final walletRecovery = await preflightRegisteredWallet(active.dbFileName);
    if (walletRecovery != null) {
      runApp(DbRecoveryRequiredApp(reason: walletRecovery.reason));
      return;
    }
  }

  runApp(
    ProviderScope(
      overrides: [
        walletRegistryProvider.overrideWithValue(walletRegistry),
        authRepositoryProvider.overrideWithValue(authRepository),
        cloudSessionProvider.overrideWithValue(
          authRepository is FirebaseAuthRepository
              ? authRepository.cloudSession
              : null,
        ),
        backupServiceProvider.overrideWithValue(
          authRepository is FirebaseAuthRepository &&
                  authRepository.cloudSession != null
              ? BackupService(
                  session: authRepository.cloudSession!,
                  transport: authRepository.cloudSession!.transport,
                  keyStore: KeystoreBackupKeyStore(),
                )
              : null,
        ),
        appLockPlatformProvider.overrideWithValue(lockPlatform),
        deviceAuthenticatorProvider.overrideWithValue(
          LocalAuthDeviceAuthenticator(),
        ),
        appLockInitialStatusProvider.overrideWithValue(lockStatus),
        primaryFundIdProvider.overrideWith(
          (ref) => createWalletPrimaryFundController(
            prefs,
            ref.watch(activeWalletProvider),
            LocalWalletSettingsRepository(ref.watch(appDatabaseProvider)),
          ),
        ),
        explorerSortProvider.overrideWith(
          (ref) => createPersistentExplorerSortController(prefs),
        ),
      ],
      child: const ViNhaMinhApp(),
    ),
  );
}

class ViNhaMinhApp extends StatelessWidget {
  const ViNhaMinhApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'HomeWallet',
      localizationsDelegates: SessionLocalizations.localizationsDelegates,
      supportedLocales: SessionLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: appRouter,
      builder: (context, child) => LockGate(
        child: WalletAccessGate(
          child: SyncLifecycleHost(
            child: TapGuardScope(child: child ?? const SizedBox.shrink()),
          ),
        ),
      ),
    );
  }
}
