import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/sync/cloud_binding_store.dart';
import '../../../data/sync/family_foreground_sync.dart';
import '../../../data/sync/sync_worker.dart';
import '../../../domain/entities/cloud_binding.dart';
import '../../../domain/entities/wallet_identity.dart';
import '../../providers/sync_provider.dart';

/// P8.4: khởi động worker đồng bộ của ví đang mở khi app mở / quay lại foreground.
/// Chỉ dựng BÊN TRONG `WalletAccessGate` (ví bị ẩn ⇒ không có worker). Worker tự
/// không gọi mạng khi outbox rỗng và không có tín hiệu kéo.
///
/// P10: ví Family ⇒ nghe tín hiệu FCM "đầu cloud có thể đã đổi" (app đang mở) và cờ
/// bền do isolate nền ghi (app ở nền/tắt) ⇒ `requestPull`. Token FCM chỉ đăng ký lại
/// khi đổi. Mở/quay lại app ⇒ kéo 1 lần và thử gắn tín hiệu lại (vd vừa chuyển ví
/// sang Family, hoặc FCM lúc trước báo `SERVICE_NOT_AVAILABLE`). Máy không có tín
/// hiệu đẩy ⇒ kéo định kỳ CHỈ khi app ở foreground ([FamilyForegroundSync]).
class SyncLifecycleHost extends ConsumerStatefulWidget {
  const SyncLifecycleHost({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<SyncLifecycleHost> createState() => _SyncLifecycleHostState();
}

class _SyncLifecycleHostState extends ConsumerState<SyncLifecycleHost>
    with WidgetsBindingObserver {
  SyncWorker? _started;
  StreamSubscription<void>? _signals;
  StreamSubscription<String>? _tokens;
  FamilyForegroundSync? _foreground;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _signals?.cancel();
    _tokens?.cancel();
    _foreground?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final worker = _started;
    if (state == AppLifecycleState.resumed) {
      worker?.start();
      _foreground?.resumed();
      // Thử gắn lại tín hiệu (ví vừa thành Family / FCM lần trước chưa sẵn sàng).
      // Đã đăng ký cùng token ⇒ không gọi mạng.
      if (worker != null) unawaited(_attachSignals(worker, pullNow: false));
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _foreground?.paused();
    }
  }

  Future<void> _consumePending() async {
    final signal = ref.read(remoteChangeSignalProvider);
    final worker = _started;
    if (signal == null || worker == null) return;
    if (await signal.consumePending()) worker.requestPull();
  }

  /// Ví đang mở là Family đã gắn ⇒ walletId; còn lại ⇒ null (không cần tín hiệu).
  Future<String?> _familyWalletId(SyncWorker worker) async {
    final db = worker.db;
    final meta = await db.select(db.walletMeta).getSingle();
    final binding = await CloudBindingStore(db).read();
    if (meta.kind != WalletKind.family.name ||
        binding?.state != CloudBindingState.active) {
      return null;
    }
    return meta.walletId;
  }

  Future<void> _attachSignals(SyncWorker worker, {bool pullNow = true}) async {
    await _signals?.cancel();
    await _tokens?.cancel();
    _signals = null;
    _tokens = null;
    var family = false;
    var signalOk = false;
    try {
      final walletId = await _familyWalletId(worker);
      if (!identical(worker, _started)) return;
      family = walletId != null;
      final signal = ref.read(remoteChangeSignalProvider);
      final registrar = ref.read(remoteSignalRegistrarProvider);
      if (walletId != null && signal != null && registrar != null) {
        _signals = signal.signals.listen((_) => worker.requestPull());
        Future<bool> register(String? token) async {
          if (token == null) return false;
          try {
            await registrar.ensureRegistered(walletId, token);
            return true;
          } on Object catch (e) {
            if (kDebugMode) {
              debugPrint('[signal] register failed ${e.runtimeType}');
            }
            return false;
          }
        }

        _tokens = signal.tokenRefresh.listen((t) async {
          if (await register(t) && identical(worker, _started)) {
            _foreground?.attached(family: true, signalOk: true);
          }
        });
        signalOk = await register(await signal.token());
        await _consumePending();
      }
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[signal] unavailable ${e.runtimeType}');
    }
    if (!identical(worker, _started)) return;
    final fg = _foreground;
    if (fg == null) return;
    if (pullNow) {
      fg.attached(family: family, signalOk: signalOk);
    } else {
      // Quay lại app: resumed() đã kéo; chỉ cập nhật trạng thái tín hiệu/định kỳ.
      fg.attachedQuietly(family: family, signalOk: signalOk);
    }
  }

  @override
  Widget build(BuildContext context) {
    final worker = ref.watch(syncWorkerProvider);
    if (!identical(worker, _started)) {
      _started = worker;
      _foreground?.dispose();
      _foreground = worker == null
          ? null
          : FamilyForegroundSync(pull: worker.requestPull);
      worker?.start();
      if (worker != null) {
        unawaited(_attachSignals(worker));
      } else {
        _signals?.cancel();
        _tokens?.cancel();
        _signals = null;
        _tokens = null;
      }
    }
    return widget.child;
  }
}
