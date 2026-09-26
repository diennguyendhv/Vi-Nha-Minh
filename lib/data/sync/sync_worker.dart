import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart';

import '../../domain/auth/cloud_session.dart';
import '../local/app_database.dart';
import '../local/sync/sync_capture.dart';
import 'cloud_sync_engine.dart';

/// Kết quả 1 lượt chạy (cho UI trạng thái/test).
enum SyncRunOutcome { synced, idle, blocked, retrying }

/// P8.4 — worker đẩy/kéo nền, KHÔNG thăm dò khi rảnh.
///
/// Kích hoạt bởi: [start] (mở app/quay lại foreground) và thay đổi trên các bảng dữ
/// liệu Wallet (Drift `tableUpdates`) → gom trong [debounce] → `syncNow`. Lỗi mạng /
/// HEAD_MOVED dai dẳng ⇒ thử lại lùi luỹ thừa (tối đa [maxBackoff]). Điều kiện chưa đủ
/// (đăng xuất, sai Account, chưa claim/bật sao lưu, thiếu BMK, phiên cũ/bị thu hồi) ⇒
/// dừng im, outbox GIỮ NGUYÊN, chờ trigger kế tiếp (đăng nhập lại/kích hoạt thiết bị).
/// Ghi của chính lượt kéo không tự kích hoạt lượt mới (bỏ qua thông báo khi đang chạy).
class SyncWorker {
  SyncWorker({
    required this.engine,
    required this.db,
    this.debounce = const Duration(seconds: 3),
    this.baseBackoff = const Duration(seconds: 5),
    this.maxBackoff = const Duration(minutes: 15),
  });

  final CloudSyncEngine engine;
  final AppDatabase db;
  final Duration debounce;
  final Duration baseBackoff;
  final Duration maxBackoff;

  Timer? _timer;
  StreamSubscription<Set<TableUpdate>>? _sub;
  bool _running = false;
  int _failures = 0;
  int runs = 0;
  SyncRunOutcome? lastOutcome;
  Object? lastError;
  final _outcomes = StreamController<SyncRunOutcome>.broadcast();
  Stream<SyncRunOutcome> get outcomes => _outcomes.stream;

  static final _captured = syncCapturedTables.keys.toSet();

  static const _blockedReasons = {
    'blocked-environment',
    'not-bound',
    'other-account',
    'no-key',
    'key-wallet-mismatch',
    'backup-not-enabled',
  };

  /// Mở app / foreground: đẩy phần outbox còn lại + kéo 1 lần.
  void start() {
    _sub ??= db
        .tableUpdates(TableUpdateQuery.any())
        .listen((updates) {
          if (_running) return;
          if (updates.any((u) => _captured.contains(u.table))) _schedule(debounce);
        });
    _schedule(Duration.zero);
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> dispose() async {
    await stop();
    await _outcomes.close();
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(runOnce()));
  }

  Duration backoffFor(int failures) {
    final ms = baseBackoff.inMilliseconds * pow(2, min(failures - 1, 16));
    return Duration(milliseconds: min(ms.toInt(), maxBackoff.inMilliseconds));
  }

  /// 1 lượt đồng bộ (tuần tự; gọi chồng ⇒ lượt sau bị bỏ, lượt đang chạy tự lên lịch lại).
  Future<SyncRunOutcome> runOnce() async {
    if (_running) return SyncRunOutcome.idle;
    _running = true;
    runs++;
    SyncRunOutcome outcome;
    try {
      await engine.syncNow();
      _failures = 0;
      lastError = null;
      outcome = SyncRunOutcome.synced;
    } on CloudSyncException catch (e) {
      lastError = e;
      outcome = _blockedReasons.contains(e.reason)
          ? SyncRunOutcome.blocked
          : SyncRunOutcome.retrying;
    } on SessionFailure catch (e) {
      lastError = e;
      // Phiên cũ/bị thu hồi/đăng xuất ⇒ cần người dùng; lỗi mạng ⇒ thử lại.
      outcome = e.denied ? SyncRunOutcome.blocked : SyncRunOutcome.retrying;
    } on Object catch (e) {
      lastError = e;
      outcome = SyncRunOutcome.retrying;
    } finally {
      _running = false;
    }
    if (outcome == SyncRunOutcome.retrying) {
      _failures++;
      if (_sub != null) _schedule(backoffFor(_failures));
    } else if (outcome == SyncRunOutcome.synced &&
        _sub != null &&
        await SyncOutboxStore(db).count() > 0) {
      // Người dùng ghi thêm trong lúc đang đồng bộ.
      _schedule(debounce);
    }
    lastOutcome = outcome;
    if (!_outcomes.isClosed) _outcomes.add(outcome);
    return outcome;
  }
}
