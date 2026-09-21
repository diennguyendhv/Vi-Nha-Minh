import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/auth/account_identity.dart';
import '../../domain/auth/auth_repository.dart';

/// `main` override bằng cài đặt thật; mặc định = không có Auth (an toàn cho test).
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => const _NoAuthRepository(),
);

class _NoAuthRepository implements AuthRepository {
  const _NoAuthRepository();
  @override
  bool get isAvailable => false;
  @override
  AccountIdentity? currentAccount() => null;
  @override
  Stream<AccountIdentity?> watchAuthState() => Stream.value(null);
  @override
  Future<AccountIdentity> signInWithGoogle() =>
      Future.error(const AuthFailure(AuthFailureReason.notConfigured));
  @override
  Future<void> signOut() async {}
}

/// Trạng thái tài khoản (null = chưa đăng nhập). Không ảnh hưởng Wallet cục bộ.
final accountProvider = StreamProvider<AccountIdentity?>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return repo.watchAuthState();
});

class AuthActionState {
  const AuthActionState({this.busy = false, this.failure});
  final bool busy;
  final AuthFailureReason? failure;
}

/// Chạy đăng nhập/đăng xuất, chống bấm đúp (1 thao tác tại 1 thời điểm).
class AuthActionController extends StateNotifier<AuthActionState> {
  AuthActionController(this._repo) : super(const AuthActionState());
  final AuthRepository _repo;
  bool _inFlight = false;

  Future<bool> signIn() => _run(() => _repo.signInWithGoogle());
  Future<bool> signOut() => _run(() => _repo.signOut());

  void clearFailure() {
    if (state.failure != null && mounted) state = const AuthActionState();
  }

  Future<bool> _run(Future<void> Function() action) async {
    if (_inFlight) return false;
    _inFlight = true;
    if (mounted) state = const AuthActionState(busy: true);
    try {
      await action();
      if (mounted) state = const AuthActionState();
      return true;
    } on AuthFailure catch (f) {
      if (mounted) {
        // Huỷ không phải lỗi: không hiện thông báo.
        state = AuthActionState(
          failure: f.reason == AuthFailureReason.cancelled ? null : f.reason,
        );
      }
      return false;
    } on Object {
      if (mounted) {
        state = const AuthActionState(failure: AuthFailureReason.authFailure);
      }
      return false;
    } finally {
      _inFlight = false;
    }
  }
}

final authActionProvider =
    StateNotifierProvider.autoDispose<AuthActionController, AuthActionState>(
      (ref) => AuthActionController(ref.watch(authRepositoryProvider)),
    );
