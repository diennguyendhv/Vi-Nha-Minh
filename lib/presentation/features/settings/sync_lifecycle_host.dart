import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/sync/cloud_binding_store.dart';
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
/// khi đổi (không có lời gọi cloud khi mở app bình thường). Không thăm dò.
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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _started?.start();
      unawaited(_consumePending());
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

  Future<void> _attachSignals(SyncWorker worker) async {
    await _signals?.cancel();
    await _tokens?.cancel();
    _signals = null;
    _tokens = null;
    final signal = ref.read(remoteChangeSignalProvider);
    final registrar = ref.read(remoteSignalRegistrarProvider);
    if (signal == null || registrar == null) return;
    try {
      final walletId = await _familyWalletId(worker);
      if (walletId == null || !identical(worker, _started)) return;
      _signals = signal.signals.listen((_) => worker.requestPull());
      Future<void> register(String? token) async {
        if (token == null) return;
        try {
          await registrar.ensureRegistered(walletId, token);
        } on Object catch (e) {
          if (kDebugMode) debugPrint('[signal] register failed ${e.runtimeType}');
        }
      }

      _tokens = signal.tokenRefresh.listen(register);
      await register(await signal.token());
      await _consumePending();
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[signal] unavailable ${e.runtimeType}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final worker = ref.watch(syncWorkerProvider);
    if (!identical(worker, _started)) {
      _started = worker;
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
