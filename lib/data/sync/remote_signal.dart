import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/auth/cloud_session.dart';

/// P10 — tín hiệu "đầu cloud có thể đã đổi" cho ví Family (2 người ghi).
///
/// Máy chủ gửi FCM data-only `{t: 'head'}` sau mỗi batch Family đã commit tới các máy
/// thành viên KHÁC. Tín hiệu không chứa walletId/số tiền/nội dung — chỉ là lời nhắc;
/// máy nhận kéo delta bằng phiên P7.1 của chính mình. Không thăm dò định kỳ: rảnh ⇒
/// 0 lời gọi cloud.
abstract class RemoteChangeSignal {
  /// Tín hiệu tới khi app đang mở.
  Stream<void> get signals;

  /// Tín hiệu tới khi app ở nền/đã tắt (ghi cờ bền) — đọc + xoá khi app quay lại.
  Future<bool> consumePending();

  /// Token FCM hiện tại của máy (null nếu không khả dụng).
  Future<String?> token();
  Stream<String> get tokenRefresh;
}

const _pendingKey = 'hw_remote_head_pending';

/// Chạy trong isolate nền của firebase_messaging: CHỈ ghi 1 cờ bền. Không mở DB, không
/// gọi mạng, không cần khoá nào.
@pragma('vm:entry-point')
Future<void> remoteSignalBackgroundHandler(RemoteMessage message) async {
  if (message.data['t'] != 'head') return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_pendingKey, true);
}

class FcmRemoteChangeSignal implements RemoteChangeSignal {
  FcmRemoteChangeSignal() {
    FirebaseMessaging.onBackgroundMessage(remoteSignalBackgroundHandler);
  }

  @override
  Stream<void> get signals => FirebaseMessaging.onMessage
      .where((m) => m.data['t'] == 'head')
      .map((_) {});

  @override
  Future<bool> consumePending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final pending = prefs.getBool(_pendingKey) ?? false;
    if (pending) await prefs.remove(_pendingKey);
    return pending;
  }

  @override
  Future<String?> token() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } on Object {
      return null; // không có Play services / mạng: đồng bộ vẫn chạy khi mở app/bấm tay
    }
  }

  @override
  Stream<String> get tokenRefresh => FirebaseMessaging.instance.onTokenRefresh;
}

/// Đăng ký token FCM của máy này cho 1 ví Family — CHỈ khi token/ví/Account đổi so với
/// lần đăng ký thành công trước (nhớ ở SharedPreferences thiết bị) ⇒ mở app bình
/// thường không phát sinh lời gọi cloud nào.
class RemoteSignalRegistrar {
  RemoteSignalRegistrar({
    required this.session,
    required SessionTransport transport,
    this.prefs,
  }) : _send = transport;

  final CloudSession session;
  final SessionTransport _send;
  final Future<SharedPreferences> Function()? prefs;
  int calls = 0;

  static String _key(String uid, String walletId) => 'hw_signal_$uid:$walletId';

  /// Máy chủ đã xoá token của membership cũ (thu hồi) ⇒ quên dấu "đã đăng ký" của
  /// (Account, ví) này để lần mở ví sau (tham gia lại) đăng ký token đúng 1 lần. Nếu
  /// không, dấu cũ khớp token ⇒ không bao giờ đăng ký lại ⇒ Member mất tín hiệu.
  static Future<void> forget(
    String uid,
    String walletId, {
    Future<SharedPreferences> Function()? prefs,
  }) async {
    final store = await (prefs ?? SharedPreferences.getInstance)();
    await store.remove(_key(uid, walletId));
  }

  Future<bool> ensureRegistered(String walletId, String token) async {
    final uid = session.accountId();
    if (uid == null) return false;
    final store = await (prefs ?? SharedPreferences.getInstance)();
    final credential = await session.credential();
    final marker = '${credential['installationId']}|$token';
    if (store.getString(_key(uid, walletId)) == marker) return false;
    calls++;
    await _send('registerSyncSignal', {
      ...credential,
      'walletId': walletId,
      'token': token,
    });
    await store.setString(_key(uid, walletId), marker);
    return true;
  }
}
