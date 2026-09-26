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

  @override
  String get takeoverTitle => 'Thiết bị khác đang hoạt động';

  @override
  String get takeoverBody =>
      'Chỉ đăng nhập thôi không đủ để thay thiết bị đang hoạt động. Hãy xin thiết bị đó chấp thuận, hoặc dùng khôi phục khi mất máy.';

  @override
  String get takeoverRequest => 'Xin thiết bị đang hoạt động';

  @override
  String get takeoverLost => 'Thiết bị cũ đã mất';

  @override
  String takeoverWaiting(String code) {
    return 'Mã $code. Trên thiết bị đang hoạt động, bấm Kiểm tra phiên cloud và chỉ chấp thuận nếu thấy đúng mã này. Sau đó bấm Hoàn tất chuyển ở đây.';
  }

  @override
  String get takeoverFinish => 'Hoàn tất chuyển';

  @override
  String get takeoverPending => 'Thiết bị đang hoạt động chưa chấp thuận.';

  @override
  String get approveTitle => 'Yêu cầu chuyển thiết bị';

  @override
  String approveBody(String code) {
    return 'Một thiết bị đăng nhập tài khoản này xin trở thành thiết bị hoạt động. Mã: $code. Chỉ chấp thuận nếu thiết bị mới hiện đúng mã này. Thiết bị này sẽ mất quyền truy cập cloud.';
  }

  @override
  String get approve => 'Chấp thuận';

  @override
  String get reject => 'Từ chối';

  @override
  String get recoveryRequired =>
      'Thiết bị này đã bị thay bằng khôi phục khi mất máy. Cần Mật khẩu sao lưu hoặc Recovery Key.';

  @override
  String get recentLoginRequired =>
      'Để an toàn, hãy đăng xuất rồi đăng nhập lại, sau đó thử lại trong 30 phút.';

  @override
  String get lostTitle => 'Khôi phục khi mất thiết bị';

  @override
  String get lostBody =>
      'Nhập Mật khẩu sao lưu hoặc Recovery Key. Thiết bị cũ sẽ bị khoá vĩnh viễn khỏi cloud. Không dùng PIN khoá ứng dụng ở đây.';

  @override
  String get usePassword => 'Mật khẩu sao lưu';

  @override
  String get useRecoveryKey => 'Recovery Key';

  @override
  String get recover => 'Khôi phục';

  @override
  String get recoverFailed => 'Khôi phục thất bại. Kiểm tra lại rồi thử lại.';

  @override
  String get noBackup =>
      'Tài khoản này chưa có bản sao lưu cloud nên không khôi phục khi mất máy được.';

  @override
  String get backupTitle => 'Sao lưu mã hoá (DEV fixture)';

  @override
  String get backupOff =>
      'Chưa bật trên thiết bị này. Chỉ dữ liệu giả DEV được tải lên cho tới khi mã hoá DB cục bộ hoàn tất.';

  @override
  String get backupOn =>
      'Đã bật. Khoá sao lưu được bảo vệ bằng Android Keystore.';

  @override
  String get backupEnable => 'Bật sao lưu';

  @override
  String get backupUpload => 'Tải fixture DEV lên';

  @override
  String get backupVerify => 'Tải về & giải mã';

  @override
  String get backupChangePassword => 'Đổi Mật khẩu sao lưu';

  @override
  String get backupPassword => 'Mật khẩu sao lưu (tối thiểu 10 ký tự)';

  @override
  String get backupPasswordRepeat => 'Nhập lại Mật khẩu sao lưu';

  @override
  String get backupOldPassword =>
      'Mật khẩu sao lưu hiện tại (không bắt buộc trên thiết bị tin cậy này)';

  @override
  String get backupPasswordHint =>
      'Tách biệt với tài khoản Google, PIN khoá ứng dụng và PIN điện thoại. Không bao giờ gửi lên máy chủ.';

  @override
  String get recoveryKeyTitle => 'Lưu Recovery Key';

  @override
  String get recoveryKeyBody =>
      'Chỉ hiện 1 lần. Nếu mất Mật khẩu sao lưu, Recovery Key này VÀ mọi thiết bị tin cậy thì không ai (kể cả quản trị) khôi phục được bản sao lưu.';

  @override
  String get recoveryKeySaved => 'Tôi đã lưu Recovery Key ở nơi an toàn';

  @override
  String get done => 'Xong';

  @override
  String backupResult(String result) {
    return '$result';
  }

  @override
  String get backupFailed => 'Thao tác sao lưu thất bại.';

  @override
  String get stepUpReason => 'Xác minh chủ máy cho thao tác bảo mật này';

  @override
  String get reauthenticate => 'Xác thực lại';

  @override
  String get stepUpFailed => 'Chưa xác minh xong.';

  @override
  String get deviceRevoked =>
      'Thiết bị này đã bị thay bằng khôi phục khi mất máy. Credential cloud và khoá sao lưu trên máy này đã được xoá.';
}
