import 'dart:async';

import 'package:vi_nha_minh/domain/auth/account_identity.dart';
import 'package:vi_nha_minh/domain/auth/auth_repository.dart';

const testAccount = AccountIdentity(
  uid: 'uid-123456',
  provider: AccountIdentity.providerGoogle,
  email: 'someone@example.com',
  displayName: 'Người Thử',
);

/// Giả lập Auth cho test: không mạng, không Firebase.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.available = true, AccountIdentity? initial})
    : _current = initial;

  final bool available;
  AccountIdentity? _current;
  final _ctrl = StreamController<AccountIdentity?>.broadcast();

  /// Lỗi cho lần signIn kế tiếp: null = thành công.
  AuthFailureReason? nextFailure;
  Completer<void>? gate;
  int signInCalls = 0;
  int signOutCalls = 0;

  @override
  bool get isAvailable => available;
  @override
  AccountIdentity? currentAccount() => _current;

  @override
  Stream<AccountIdentity?> watchAuthState() async* {
    yield _current;
    yield* _ctrl.stream;
  }

  @override
  Future<AccountIdentity> signInWithGoogle() async {
    signInCalls++;
    if (gate != null) await gate!.future;
    final f = nextFailure;
    if (f != null) throw AuthFailure(f);
    _current = testAccount;
    _ctrl.add(_current);
    return testAccount;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _current = null;
    _ctrl.add(null);
  }
}
