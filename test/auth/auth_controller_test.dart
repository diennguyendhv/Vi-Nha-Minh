import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/data/auth/firebase_auth_repository.dart';
import 'package:vi_nha_minh/domain/auth/account_identity.dart';
import 'package:vi_nha_minh/domain/auth/auth_repository.dart';
import 'package:vi_nha_minh/presentation/providers/auth_providers.dart';

import 'support/fake_auth_repository.dart';

void main() {
  test('chưa đăng nhập: accountProvider = null', () async {
    final c = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())],
    );
    addTearDown(c.dispose);
    c.listen(accountProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    expect(c.read(accountProvider).valueOrNull, isNull);
  });

  test('đăng nhập → phát AccountIdentity; đăng xuất → null (stream)', () async {
    final repo = FakeAuthRepository();
    final seen = <AccountIdentity?>[];
    final sub = repo.watchAuthState().listen(seen.add);
    await Future<void>.delayed(Duration.zero);
    await repo.signInWithGoogle();
    await repo.signOut();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(seen, [null, testAccount, null]);
  });

  test('huỷ Google: không phải lỗi hiển thị, không đăng nhập', () async {
    final repo = FakeAuthRepository()..nextFailure = AuthFailureReason.cancelled;
    final ctl = AuthActionController(repo);
    expect(await ctl.signIn(), isFalse);
    expect(ctl.state.failure, isNull);
    expect(ctl.state.busy, isFalse);
    expect(repo.currentAccount(), isNull);
  });

  for (final r in [
    AuthFailureReason.network,
    AuthFailureReason.providerFailure,
    AuthFailureReason.authFailure,
    AuthFailureReason.notConfigured,
  ]) {
    test('lỗi ${r.name}: báo lỗi, nhả khoá busy, thử lại được', () async {
      final repo = FakeAuthRepository()..nextFailure = r;
      final ctl = AuthActionController(repo);
      expect(await ctl.signIn(), isFalse);
      expect(ctl.state.failure, r);
      expect(ctl.state.busy, isFalse);
      repo.nextFailure = null;
      expect(await ctl.signIn(), isTrue);
      expect(ctl.state.failure, isNull);
    });
  }

  test('bấm đúp: chỉ 1 lần đăng nhập chạy', () async {
    final repo = FakeAuthRepository()..gate = Completer<void>();
    final ctl = AuthActionController(repo);
    final first = ctl.signIn();
    final second = await ctl.signIn();
    expect(second, isFalse);
    repo.gate!.complete();
    expect(await first, isTrue);
    expect(repo.signInCalls, 1);
  });

  test('controller bị dispose giữa chừng: không ném', () async {
    final repo = FakeAuthRepository()..gate = Completer<void>();
    final ctl = AuthActionController(repo);
    final f = ctl.signIn();
    ctl.dispose();
    repo.gate!.complete();
    expect(await f, isTrue);
  });

  test('đăng xuất xoá tài khoản', () async {
    final repo = FakeAuthRepository(initial: testAccount);
    final ctl = AuthActionController(repo);
    expect(await ctl.signOut(), isTrue);
    expect(repo.currentAccount(), isNull);
    expect(repo.signOutCalls, 1);
  });

  test('UnavailableAuthRepository: không khả dụng, đăng xuất không ném', () async {
    const r = UnavailableAuthRepository();
    expect(r.isAvailable, isFalse);
    expect(await r.watchAuthState().first, isNull);
    await expectLater(
      r.signInWithGoogle(),
      throwsA(
        isA<AuthFailure>().having(
          (e) => e.reason,
          'reason',
          AuthFailureReason.notConfigured,
        ),
      ),
    );
    await r.signOut();
  });

  test('ánh xạ user → AccountIdentity; toString/log đã che', () {
    final a = mapFirebaseUser(
      uid: 'abcd1234efgh',
      email: 'someone@example.com',
      displayName: 'X',
    );
    expect(a.uid, 'abcd1234efgh');
    expect(a.provider, 'google');
    expect(a.toString(), isNot(contains('abcd1234')));
    expect(a.toString(), isNot(contains('someone')));
    expect(redactEmail('someone@example.com'), 's***@example.com');
  });
}
