import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/config/app_environment.dart';
import 'package:vi_nha_minh/core/config/firebase_env_config.dart';

FirebaseEnvConfig cfg(String env, {String key = 'k'}) => FirebaseEnvConfig(
  envName: env,
  apiKey: key,
  appId: 'a',
  messagingSenderId: 's',
  projectId: 'p-$env',
  googleServerClientId: 'c',
);

String read(String p) => File(p).readAsStringSync();

Iterable<File> dartFiles(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  group('AppEnvironment', () {
    test('chọn theo flavor; không rõ ⇒ dev', () {
      expect(AppEnvironment.fromFlavor('dev'), AppEnvironment.dev);
      expect(AppEnvironment.fromFlavor('pilot'), AppEnvironment.pilot);
      expect(AppEnvironment.fromFlavor('prod'), AppEnvironment.prod);
      expect(AppEnvironment.fromFlavor(null), AppEnvironment.dev);
      expect(AppEnvironment.fromFlavor('lol'), AppEnvironment.dev);
    });

    test('applicationId 3 môi trường khác nhau; PROD giữ id đã phát hành', () {
      final ids = AppEnvironment.values.map((e) => e.applicationId).toSet();
      expect(ids.length, 3);
      expect(AppEnvironment.prod.applicationId, 'com.vinhamimh.vi_nha_minh');
    });

    test('Gradle khai báo đúng 3 flavor khớp AppEnvironment', () {
      final g = read('android/app/build.gradle.kts');
      expect(g, contains('create("dev")'));
      expect(g, contains('create("pilot")'));
      expect(g, contains('applicationIdSuffix = ".dev"'));
      expect(g, contains('applicationIdSuffix = ".pilot"'));
      expect(g, contains('applicationId = "com.vinhamimh.vi_nha_minh"'));
      final prod = g.substring(g.indexOf('create("prod")'));
      expect(prod.split('}').first, isNot(contains('applicationIdSuffix')));
    });
  });

  group('FirebaseEnvConfig', () {
    test('DEV không thể dùng cấu hình PROD (và ngược lại)', () {
      expect(cfg('prod').isUsableFor(AppEnvironment.dev), isFalse);
      expect(cfg('dev').isUsableFor(AppEnvironment.prod), isFalse);
      expect(cfg('pilot').isUsableFor(AppEnvironment.prod), isFalse);
      expect(cfg('dev').isUsableFor(AppEnvironment.dev), isTrue);
    });

    test('thiếu/giá trị mẫu ⇒ không dùng được (Auth tắt)', () {
      expect(cfg('dev', key: '').isUsableFor(AppEnvironment.dev), isFalse);
      expect(
        cfg('dev', key: 'REPLACE_ME').isUsableFor(AppEnvironment.dev),
        isFalse,
      );
      expect(cfg('').isUsableFor(AppEnvironment.dev), isFalse);
      // Không truyền --dart-define ⇒ trống ⇒ không dùng được.
      expect(FirebaseEnvConfig.fromDartDefine.isUsable, isFalse);
    });

    test('file mẫu env/*.example.json khớp tên môi trường, chỉ là giá trị mẫu', () {
      for (final e in AppEnvironment.values) {
        final j = read('env/${e.flavor}.example.json');
        expect(j, contains('"APP_ENV": "${e.flavor}"'));
        expect(j, contains('REPLACE_ME'));
      }
    });
  });

  group('Không đóng gói bí mật/dữ liệu thật; không tải dữ liệu tài chính', () {
    test('không có google-services.json/service account/env thật trong Git', () {
      final tracked = Process.runSync('git', ['ls-files']).stdout as String;
      expect(tracked, isNot(contains('google-services.json')));
      expect(
        tracked,
        isNot(matches(RegExp(r'service[-_]?account', caseSensitive: false))),
      );
      expect(
        tracked,
        isNot(matches(RegExp(r'^env/(dev|pilot|prod)\.json$', multiLine: true))),
      );
      expect(
        tracked,
        isNot(matches(RegExp(r'\.(sqlite|db|xlsx)$', multiLine: true))),
      );
    });

    test('mã Auth/Firebase không chạm dữ liệu tài chính hay Firestore', () {
      final files = [
        ...dartFiles('lib/domain/auth'),
        ...dartFiles('lib/data/auth'),
        ...dartFiles('lib/core/config'),
        File('lib/presentation/providers/auth_providers.dart'),
        File('lib/presentation/features/settings/account_settings_card.dart'),
      ];
      final banned = RegExp(
        r'cloud_firestore|firebase_storage|database_provider|drift|/data/local|/data/repositories|entities/transaction',
      );
      for (final f in files) {
        expect(f.readAsStringSync(), isNot(matches(banned)), reason: f.path);
      }
    });

    test('toàn bộ lib/ không import Firestore/Storage (không có đường tải dữ liệu)', () {
      for (final f in dartFiles('lib')) {
        final s = f.readAsStringSync();
        expect(s, isNot(contains('package:cloud_firestore')), reason: f.path);
        expect(s, isNot(contains('package:firebase_storage')), reason: f.path);
      }
    });

    test('AccountIdentity không có walletId/memberId/vai trò/gói', () {
      final s = read('lib/domain/auth/account_identity.dart');
      final fields = RegExp(
        r'final \w+\??\s+(\w+);',
      ).allMatches(s).map((m) => m.group(1)).toSet();
      expect(fields, {'uid', 'provider', 'email', 'displayName', 'photoUrl'});
    });
  });

  group('App Lock độc lập với Auth', () {
    test('code khoá ứng dụng không import Auth và ngược lại', () {
      for (final f in [
        ...dartFiles('lib/domain/security'),
        ...dartFiles('lib/data/security'),
        ...dartFiles('lib/presentation/features/security'),
        File('lib/presentation/providers/app_lock_provider.dart'),
      ]) {
        final s = f.readAsStringSync();
        expect(s, isNot(matches(RegExp(r'(domain|data)/auth/'))), reason: f.path);
        expect(s, isNot(contains('auth_providers')), reason: f.path);
      }
      for (final f in [
        ...dartFiles('lib/domain/auth'),
        ...dartFiles('lib/data/auth'),
        File('lib/presentation/providers/auth_providers.dart'),
      ]) {
        final s = f.readAsStringSync();
        expect(s, isNot(contains('app_lock')), reason: f.path);
        expect(s, isNot(contains('local_auth')), reason: f.path);
      }
    });
  });

  test('manifest chính khai báo INTERNET (P5) và vẫn tắt allowBackup', () {
    final m = read('android/app/src/main/AndroidManifest.xml');
    expect(m, contains('android.permission.INTERNET'));
    expect(m, contains('allowBackup="false"'));
  });
}
