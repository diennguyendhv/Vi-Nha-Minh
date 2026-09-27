import 'dart:async';

/// Ví Family đang mở ở foreground: khi nào kéo thay đổi của người kia.
///
/// - Mở app / quay lại app ⇒ kéo 1 lần (bắt kịp những gì đã đổi lúc app ở nền hoặc
///   tín hiệu FCM bị lỡ).
/// - Máy KHÔNG có tín hiệu đẩy (FCM trả `SERVICE_NOT_AVAILABLE`, không có Play
///   services…) ⇒ trong lúc app ở foreground kéo mỗi [fallbackEvery]; vào nền ⇒ dừng.
///   Máy có tín hiệu ⇒ không kéo định kỳ. App không mở ⇒ 0 lời gọi.
class FamilyForegroundSync {
  FamilyForegroundSync({
    required this.pull,
    this.fallbackEvery = const Duration(seconds: 30),
  });

  final void Function() pull;
  final Duration fallbackEvery;

  bool _family = false;
  bool _signalOk = false;
  bool _foreground = true;
  Timer? _timer;

  bool get fallbackActive => _timer != null;

  /// Kết quả gắn tín hiệu cho ví đang mở. [family] = ví Family đã gắn; [signalOk] =
  /// đã có token FCM và đăng ký được với máy chủ.
  void attached({required bool family, required bool signalOk}) {
    _family = family;
    _signalOk = signalOk;
    if (_family && _foreground) pull();
    _arm();
  }

  /// Như [attached] nhưng không kéo ngay (dùng sau [resumed], vốn đã kéo).
  void attachedQuietly({required bool family, required bool signalOk}) {
    _family = family;
    _signalOk = signalOk;
    _arm();
  }

  void resumed() {
    _foreground = true;
    if (_family) pull();
    _arm();
  }

  void paused() {
    _foreground = false;
    _arm();
  }

  void detach() {
    _family = false;
    _arm();
  }

  void _arm() {
    final want = _family && !_signalOk && _foreground;
    if (want && _timer == null) {
      _timer = Timer.periodic(fallbackEvery, (_) => pull());
    } else if (!want) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
