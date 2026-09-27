import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/sync/sync_worker.dart';
import '../../providers/sync_provider.dart';

/// P8.4: khởi động worker đồng bộ của ví đang mở khi app mở / quay lại foreground.
/// Chỉ dựng BÊN TRONG `WalletAccessGate` (ví bị ẩn ⇒ không có worker). Worker tự
/// không gọi mạng khi outbox rỗng và không có tín hiệu kéo.
class SyncLifecycleHost extends ConsumerStatefulWidget {
  const SyncLifecycleHost({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<SyncLifecycleHost> createState() => _SyncLifecycleHostState();
}

class _SyncLifecycleHostState extends ConsumerState<SyncLifecycleHost>
    with WidgetsBindingObserver {
  SyncWorker? _started;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _started?.start();
  }

  @override
  Widget build(BuildContext context) {
    final worker = ref.watch(syncWorkerProvider);
    if (!identical(worker, _started)) {
      _started = worker;
      worker?.start();
    }
    return widget.child;
  }
}
