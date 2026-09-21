import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/auth/auth_repository.dart';
import 'package:vi_nha_minh/presentation/features/settings/account_settings_card.dart';
import 'package:vi_nha_minh/presentation/providers/auth_providers.dart';

import 'support/fake_auth_repository.dart';

void main() {
  Future<void> pump(WidgetTester t, FakeAuthRepository repo) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: AccountSettingsCard()),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('chưa đăng nhập: nói rõ tuỳ chọn; không nói đã sao lưu/đồng bộ', (
    t,
  ) async {
    await pump(t, FakeAuthRepository());
    expect(find.text('Chưa đăng nhập'), findsOneWidget);
    expect(find.byKey(const Key('google_sign_in_button')), findsOneWidget);
    final texts = t
        .widgetList<Text>(find.byType(Text))
        .map((e) => e.data ?? '')
        .join(' ');
    expect(texts, contains('tuỳ chọn'));
    expect(texts, isNot(contains('Đã sao lưu')));
    expect(texts, isNot(contains('Đã đồng bộ')));
  });

  testWidgets('đăng nhập → danh tính + ghi chú "chưa sao lưu/đồng bộ"; đăng xuất → quay lại', (
    t,
  ) async {
    final repo = FakeAuthRepository();
    await pump(t, repo);
    await t.tap(find.byKey(const Key('google_sign_in_button')));
    await t.pumpAndSettle();
    expect(find.text('Người Thử'), findsOneWidget);
    expect(find.byKey(const Key('account_local_note')), findsOneWidget);

    await t.tap(find.byKey(const Key('sign_out_button')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('confirm_sign_out')));
    await t.pumpAndSettle();
    expect(find.text('Chưa đăng nhập'), findsOneWidget);
    expect(repo.signOutCalls, 1);
  });

  testWidgets('huỷ: không có lỗi; lỗi mạng: có thông báo', (t) async {
    final repo = FakeAuthRepository()..nextFailure = AuthFailureReason.cancelled;
    await pump(t, repo);
    await t.tap(find.byKey(const Key('google_sign_in_button')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('account_error')), findsNothing);

    repo.nextFailure = AuthFailureReason.network;
    await t.tap(find.byKey(const Key('google_sign_in_button')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('account_error')), findsOneWidget);
  });

  testWidgets('môi trường chưa cấu hình: nút khoá, có giải thích', (t) async {
    await pump(t, FakeAuthRepository(available: false));
    final btn = t.widget<ButtonStyleButton>(
      find.byKey(const Key('google_sign_in_button')),
    );
    expect(btn.onPressed, isNull);
    expect(find.textContaining('chưa khả dụng'), findsOneWidget);
  });
}
