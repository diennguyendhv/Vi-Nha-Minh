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

  @override
  String get dbEncryptionOn =>
      'Mã hoá dữ liệu trên máy: đang bật (SQLCipher, khoá bảo vệ bằng Android Keystore). Độc lập với Khoá ứng dụng.';

  @override
  String get dbEncryptionPending =>
      'Mã hoá dữ liệu trên máy: chưa áp dụng được. App sẽ thử lại ở lần mở sau; dữ liệu của bạn không thay đổi.';

  @override
  String get dbRecoveryTitle => 'Không mở được dữ liệu ví trên máy này';

  @override
  String get dbRecoveryBody =>
      'Khoá mã hoá bảo vệ ví trên máy này không còn dùng được (ví dụ sau khi hệ thống đặt lại bảo mật). Dữ liệu đã mã hoá được giữ nguyên, không bị xoá hay ghi đè. App KHÔNG tạo khoá mới. Khôi phục từ bản sao lưu cloud mã hoá sẽ là cách lấy lại ở phiên bản sau.';

  @override
  String get claimTitle => 'Sao lưu ví này';

  @override
  String get claimNone =>
      'Ví này chỉ nằm trên máy này, chưa gắn với tài khoản nào.';

  @override
  String get claimStart => 'Sao lưu ví này';

  @override
  String get claimNeedSession =>
      'Hãy kích hoạt thiết bị này cho cloud trước (nút Kích hoạt thiết bị này).';

  @override
  String get claimWhoTitle => 'Bạn là ai trong ví này?';

  @override
  String get claimWhoBody =>
      'Chọn thành viên đại diện cho tài khoản đang đăng nhập. Không có lựa chọn mặc định; không giao dịch nào bị thay đổi.';

  @override
  String claimMemberSummary(int count, String range) {
    return '$count giao dịch · $range';
  }

  @override
  String get claimMemberEmpty => 'Chưa có giao dịch';

  @override
  String get claimNext => 'Tiếp tục';

  @override
  String get claimConfirmTitle => 'Xác nhận đăng ký ví';

  @override
  String claimConfirmBody(String account, String member) {
    return '• Tài khoản $account sẽ là Chủ sở hữu cloud của ví này.\n• $member là bạn trong ví này; thành viên còn lại giữ nguyên và chưa gắn tài khoản nào.\n• Ở bước này KHÔNG có dữ liệu tài chính nào được tải lên — chỉ thông tin sở hữu.\n• Đăng xuất sau này không ẩn, không xoá ví trên máy.';
  }

  @override
  String get claimConfirm => 'Đăng ký ví';

  @override
  String get claimPending =>
      'Đang hoàn tất đăng ký ví với máy chủ. Dữ liệu trên máy không thay đổi.';

  @override
  String get claimRetry => 'Thử lại';

  @override
  String claimActive(String member) {
    return 'Ví đã đăng ký với tài khoản này (bạn là $member). Sao lưu mã hoá được quản lý ở mục bên dưới.';
  }

  @override
  String get claimOtherAccount =>
      'Ví này đã đăng ký với một tài khoản khác. Tài khoản đang đăng nhập không có quyền cloud với ví; ví trên máy vẫn dùng bình thường.';

  @override
  String get claimCheck => 'Kiểm tra với máy chủ';

  @override
  String get claimServerOk =>
      'Máy chủ xác nhận: tài khoản này là Chủ sở hữu ví.';

  @override
  String get claimServerMissing =>
      'Máy chủ không có đăng ký nào của ví này cho tài khoản này.';

  @override
  String get claimAbandon => 'Huỷ đăng ký ví';

  @override
  String get claimAbandonBody =>
      'Chỉ huỷ được khi chưa có bản sao lưu nào trên cloud. Dữ liệu trên máy giữ nguyên.';

  @override
  String get claimAbandoned =>
      'Đã huỷ đăng ký. Ví quay về chỉ nằm trên máy này.';

  @override
  String get claimAlreadyClaimed =>
      'Ví này đã được một tài khoản khác đăng ký.';

  @override
  String get claimAccountHasWallet => 'Tài khoản này đã sở hữu một ví khác.';

  @override
  String get claimSelfMismatch =>
      'Máy chủ đã ghi bạn là thành viên khác trong ví này. Hãy chọn lại.';

  @override
  String get claimBackupStarted =>
      'Đã bắt đầu sao lưu nên không huỷ đăng ký được.';

  @override
  String get claimFailed =>
      'Chưa đăng ký được. Dữ liệu trên máy không thay đổi; hãy thử lại sau.';

  @override
  String get walletBackupTitle => 'Sao lưu mã hoá ví này (DEV)';

  @override
  String get walletBackupOff => 'Chưa bật. Ví này chỉ nằm trên máy này.';

  @override
  String get walletBackupSeeding => 'Đang tải bản sao lưu mã hoá đầu tiên…';

  @override
  String get walletBackupComplete =>
      'Đã sao lưu. Thay đổi mới được tự tải lên, mã hoá ngay trên máy.';

  @override
  String walletBackupPending(int count) {
    return 'Chờ tải lên: $count';
  }

  @override
  String walletBackupDiag(int calls, String headRev) {
    return 'Lượt gọi mạng phiên này: $calls · phiên bản máy chủ: $headRev';
  }

  @override
  String get walletBackupEnable => 'Bật sao lưu mã hoá';

  @override
  String get walletBackupSyncNow => 'Đồng bộ ngay';

  @override
  String get restoreAction => 'Khôi phục ví từ bản sao lưu';

  @override
  String get restorePick => 'Chọn bản sao lưu';

  @override
  String get restoreDone => 'Đã khôi phục và kiểm chứng ví.';

  @override
  String get restoreFailed =>
      'Không khôi phục được. Ví hiện tại không bị thay đổi.';

  @override
  String get rotateRecoveryAction => 'Tạo lại Recovery Key';

  @override
  String get rotateRecoveryConfirmTitle => 'Tạo Recovery Key mới?';

  @override
  String get rotateRecoveryConfirmBody =>
      'Recovery Key hiện tại sẽ hết hiệu lực ngay. Mật khẩu sao lưu và dữ liệu sao lưu giữ nguyên. Key mới chỉ hiện 1 lần.';

  @override
  String get rotateRecoveryConfirm => 'Tạo key mới';

  @override
  String get rotateRecoveryFailed =>
      'Chưa thay được Recovery Key. Mật khẩu sao lưu vẫn dùng được; hãy thử lại.';
}
