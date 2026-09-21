import 'package:flutter/services.dart' show appFlavor;

/// Môi trường build — NGUỒN SỰ THẬT DUY NHẤT (P5). Mã nghiệp vụ chỉ hỏi
/// `AppEnvironment.current`; không rải kiểm tra `kDebugMode`/tên package.
///
/// Chọn khi build bằng `--flavor dev|pilot|prod` (Flutter đặt `appFlavor`).
/// DEV: dữ liệu giả/thử. PILOT: thử nghiệm hai người có kiểm soát. PROD: bản Play.
enum AppEnvironment {
  dev('dev', 'com.vinhamimh.vi_nha_minh.dev'),
  pilot('pilot', 'com.vinhamimh.vi_nha_minh.pilot'),
  prod('prod', 'com.vinhamimh.vi_nha_minh');

  const AppEnvironment(this.flavor, this.applicationId);

  /// Tên flavor Gradle/Flutter.
  final String flavor;

  /// `applicationId` Android tương ứng (mỗi môi trường = sandbox riêng).
  final String applicationId;

  /// Không có flavor (vd `flutter test`, `flutter run` trần) ⇒ `dev`. Đây chỉ là
  /// mặc định an toàn: DEV không có cấu hình Firebase thật thì Auth tự tắt.
  static AppEnvironment fromFlavor(String? flavor) {
    for (final e in values) {
      if (e.flavor == flavor) return e;
    }
    return AppEnvironment.dev;
  }

  static AppEnvironment? _override;
  static AppEnvironment get current =>
      _override ?? fromFlavor(appFlavor);

  /// Chỉ dùng trong test.
  static void debugOverride(AppEnvironment? env) => _override = env;

  bool get isProd => this == AppEnvironment.prod;
}
