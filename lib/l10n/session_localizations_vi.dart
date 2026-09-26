// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'session_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class SessionLocalizationsVi extends SessionLocalizations {
  SessionLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get activateSession => 'Kích hoạt thiết bị này';

  @override
  String get checkSession => 'Kiểm tra phiên cloud';

  @override
  String get confirmSession =>
      'Dùng thiết bị này để truy cập cloud? Thiết bị trước sẽ mất quyền truy cập cloud. Dữ liệu cục bộ trên cả hai máy vẫn được giữ nguyên.';

  @override
  String get cancelSession => 'Hủy';

  @override
  String get sessionReady =>
      'Server đã chấp nhận phiên tại lần kiểm tra vừa rồi.';

  @override
  String get sessionDenied =>
      'Thiết bị này chưa có phiên cloud hiện hành. Hãy kích hoạt nếu muốn dùng lại.';

  @override
  String get sessionUnknown =>
      'Chưa xác minh được phiên cloud. Dữ liệu cục bộ vẫn dùng được.';

  @override
  String get sessionUnchecked => 'Chưa kiểm tra phiên cloud.';
}
