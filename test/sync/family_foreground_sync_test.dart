import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/data/sync/family_foreground_sync.dart';

/// Pilot thật 2026-09-27: máy Xiaomi của vợ không lấy được token FCM
/// (`SERVICE_NOT_AVAILABLE`) ⇒ không bao giờ biết có thay đổi. Dự phòng: kéo khi
/// mở/quay lại app; không có tín hiệu ⇒ kéo định kỳ CHỈ khi app ở foreground.
void main() {
  const tick = Duration(milliseconds: 40);
  Future<void> wait(int ticks) =>
      Future<void>.delayed(tick * ticks + const Duration(milliseconds: 15));

  test('ví Family + tín hiệu OK: kéo khi mở/quay lại, KHÔNG kéo định kỳ', () async {
    var pulls = 0;
    final s = FamilyForegroundSync(pull: () => pulls++, fallbackEvery: tick);
    s.attached(family: true, signalOk: true);
    expect(pulls, 1);
    await wait(3);
    expect(pulls, 1);
    expect(s.fallbackActive, isFalse);
    s.paused();
    s.resumed();
    expect(pulls, 2);
    s.dispose();
  });

  test('ví Family KHÔNG có tín hiệu: kéo định kỳ khi foreground, dừng khi vào nền', () async {
    var pulls = 0;
    final s = FamilyForegroundSync(pull: () => pulls++, fallbackEvery: tick);
    s.attached(family: true, signalOk: false);
    expect(pulls, 1);
    expect(s.fallbackActive, isTrue);
    await wait(3);
    expect(pulls, greaterThanOrEqualTo(3));
    s.paused();
    expect(s.fallbackActive, isFalse);
    final atPause = pulls;
    await wait(3);
    expect(pulls, atPause, reason: 'app ở nền ⇒ 0 lời gọi');
    s.resumed();
    expect(pulls, atPause + 1);
    expect(s.fallbackActive, isTrue);
    // Token tới sau (FCM sẵn sàng lại) ⇒ tắt định kỳ.
    s.attachedQuietly(family: true, signalOk: true);
    expect(s.fallbackActive, isFalse);
    s.dispose();
  });

  test('ví không phải Family: không kéo gì', () async {
    var pulls = 0;
    final s = FamilyForegroundSync(pull: () => pulls++, fallbackEvery: tick);
    s.attached(family: false, signalOk: false);
    s.resumed();
    await wait(3);
    expect(pulls, 0);
    expect(s.fallbackActive, isFalse);
    s.dispose();
  });
}
