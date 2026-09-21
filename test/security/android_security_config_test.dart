import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kiểm tra TĨNH cấu hình Android/bảo mật (P3): sao lưu hệ điều hành bị tắt, không rò
/// thông tin nhạy cảm qua log, PIN không nằm trong SharedPreferences/SQLite.
void main() {
  String read(String path) => File(path).readAsStringSync();
  const manifest = 'android/app/src/main/AndroidManifest.xml';
  const domains = ['root', 'file', 'database', 'sharedpref', 'external'];

  group('Android Auto Backup bị tắt', () {
    test('allowBackup="false" + trỏ tới 2 file luật (API < 31 và ≥ 31)', () {
      final m = read(manifest);
      expect(m, contains('android:allowBackup="false"'));
      expect(m, contains('android:fullBackupContent="@xml/backup_rules"'));
      expect(
        m,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
    });

    test('backup_rules.xml loại trừ MỌI domain (DB, prefs, file khoá)', () {
      final x = read('android/app/src/main/res/xml/backup_rules.xml');
      for (final d in domains) {
        expect(x, contains('<exclude domain="$d" path="."/>'), reason: d);
      }
      expect(x, isNot(contains('<include')));
    });

    test('data_extraction_rules.xml loại trừ mọi domain ở cả cloud-backup & device-transfer', () {
      final x = read('android/app/src/main/res/xml/data_extraction_rules.xml');
      for (final section in ['cloud-backup', 'device-transfer']) {
        final start = x.indexOf('<$section>');
        final end = x.indexOf('</$section>');
        expect(start, greaterThanOrEqualTo(0), reason: section);
        final body = x.substring(start, end);
        for (final d in domains) {
          expect(body, contains('<exclude domain="$d" path="."/>'),
              reason: '$section/$d');
        }
        expect(body, isNot(contains('<include')));
      }
    });

    test('manifest xin USE_BIOMETRIC và dùng FragmentActivity (local_auth)', () {
      expect(read(manifest), contains('android.permission.USE_BIOMETRIC'));
      final k = read(
        'android/app/src/main/kotlin/com/vinhamimh/vi_nha_minh/MainActivity.kt',
      );
      expect(k, contains('FlutterFragmentActivity()'));
    });
  });

  group('không rò rỉ / không lưu PIN sai chỗ', () {
    final securityDart = [
      ...Directory('lib/domain/security').listSync(),
      ...Directory('lib/data/security').listSync(),
      ...Directory('lib/presentation/features/security').listSync(),
      File('lib/presentation/providers/app_lock_provider.dart'),
    ].whereType<File>().toList();
    const kotlinDir = 'android/app/src/main/kotlin/com/vinhamimh/vi_nha_minh';

    test('mã bảo mật không có print/debugPrint/log', () {
      for (final f in securityDart) {
        final s = f.readAsStringSync();
        expect(s, isNot(contains('print(')), reason: f.path);
        expect(s, isNot(contains('debugPrint')), reason: f.path);
        expect(s, isNot(contains('developer.log')), reason: f.path);
      }
      final kt = read('$kotlinDir/AppLockBridge.kt') +
          read('$kotlinDir/MainActivity.kt');
      expect(kt, isNot(contains('Log.')));
      expect(kt, isNot(contains('println')));
    });

    test('Dart không dùng SharedPreferences/SQLite cho App Lock', () {
      for (final f in securityDart) {
        final s = f.readAsStringSync();
        expect(s, isNot(contains('shared_preferences')), reason: f.path);
        expect(s, isNot(contains('drift')), reason: f.path);
        expect(s, isNot(contains('data/local')), reason: f.path);
      }
    });

    test('domain/security thuần Dart, không phụ thuộc Flutter/Firebase', () {
      for (final f in Directory('lib/domain/security').listSync().whereType<File>()) {
        final s = f.readAsStringSync();
        expect(s, isNot(contains('package:flutter')), reason: f.path);
        expect(s, isNot(contains('firebase')), reason: f.path);
      }
    });

    test('native: verifier = PBKDF2 + HMAC Keystore, không lưu PIN/SHA-thuần', () {
      final kt = read('$kotlinDir/AppLockBridge.kt');
      expect(kt, contains('PBKDF2'));
      expect(kt, contains('AndroidKeyStore'));
      expect(kt, contains('HMAC_SHA256'));
      expect(kt, contains('SecureRandom'));
      expect(kt, contains('MessageDigest.isEqual'));
      expect(kt, isNot(contains('putString("pin"')));
      expect(kt, isNot(contains('MD5')));
      expect(kt, isNot(contains('"SHA-256"')));
    });

    test('không còn công tắc sinh trắc giả', () {
      expect(read('lib/presentation/providers/app_state_providers.dart'),
          isNot(contains('biometricLockProvider')));
      expect(read('lib/presentation/features/settings/settings_screen.dart'),
          isNot(contains('Khoá vân tay')));
    });
  });
}
