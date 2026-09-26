import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../domain/auth/account_identity.dart';
import '../../domain/auth/auth_repository.dart';
import '../../domain/auth/cloud_session.dart';

/// Ánh xạ `User` Firebase → [AccountIdentity] (tách hàm thuần để test).
AccountIdentity mapFirebaseUser({
  required String uid,
  String? email,
  String? displayName,
  String? photoUrl,
  String provider = AccountIdentity.providerGoogle,
}) => AccountIdentity(
  uid: uid,
  provider: provider,
  email: email,
  displayName: displayName,
  photoUrl: photoUrl,
);

AccountIdentity? _fromUser(fb.User? u) => u == null
    ? null
    : mapFirebaseUser(
        uid: u.uid,
        email: u.email,
        displayName: u.displayName,
        photoUrl: u.photoURL,
      );

/// Cài đặt Firebase của [AuthRepository]. Chỉ Authentication — không Firestore,
/// không đọc/ghi dữ liệu tài chính.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    required this.googleServerClientId,
    fb.FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
  }) : _auth = auth ?? fb.FirebaseAuth.instance,
       _google = googleSignIn ?? GoogleSignIn.instance;

  final String googleServerClientId;
  final fb.FirebaseAuth _auth;
  CloudSession? cloudSession;
  final GoogleSignIn _google;
  Future<void>? _googleInit;

  @override
  bool get isAvailable => true;

  @override
  AccountIdentity? currentAccount() => _fromUser(_auth.currentUser);

  @override
  Stream<AccountIdentity?> watchAuthState() =>
      _auth.authStateChanges().map(_fromUser);

  Future<void> _ensureGoogleInit() =>
      _googleInit ??= _google.initialize(serverClientId: googleServerClientId);

  @override
  Future<AccountIdentity> signInWithGoogle() async {
    try {
      await _ensureGoogleInit();
      final account = await _google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const AuthFailure(AuthFailureReason.providerFailure);
      }
      final cred = await _auth.signInWithCredential(
        fb.GoogleAuthProvider.credential(idToken: idToken),
      );
      final identity = _fromUser(cred.user);
      if (identity == null) {
        throw const AuthFailure(AuthFailureReason.authFailure);
      }
      return identity;
    } on AuthFailure {
      rethrow;
    } on GoogleSignInException catch (e) {
      _log('google', e.code.name);
      switch (e.code) {
        case GoogleSignInExceptionCode.canceled:
        case GoogleSignInExceptionCode.interrupted:
          throw const AuthFailure(AuthFailureReason.cancelled);
        default:
          throw const AuthFailure(AuthFailureReason.providerFailure);
      }
    } on fb.FirebaseAuthException catch (e) {
      _log('firebase', e.code);
      throw AuthFailure(
        e.code == 'network-request-failed'
            ? AuthFailureReason.network
            : AuthFailureReason.authFailure,
      );
    } on Exception catch (e) {
      _log('other', e.runtimeType.toString());
      throw const AuthFailure(AuthFailureReason.providerFailure);
    }
  }

  /// Step-up for sensitive cloud actions: fresh Google re-authentication of the
  /// CURRENT user (refreshes `auth_time`) WITHOUT signing out, so an active
  /// device keeps its P7 session while approving a takeover.
  Future<void> reauthenticate() async {
    final user = _auth.currentUser;
    if (user == null) throw const AuthFailure(AuthFailureReason.authFailure);
    try {
      await _ensureGoogleInit();
      final account = await _google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const AuthFailure(AuthFailureReason.providerFailure);
      }
      await user.reauthenticateWithCredential(
        fb.GoogleAuthProvider.credential(idToken: idToken),
      );
      await user.getIdToken(true);
    } on AuthFailure {
      rethrow;
    } on GoogleSignInException catch (e) {
      _log('google-reauth', e.code.name);
      throw const AuthFailure(AuthFailureReason.cancelled);
    } on fb.FirebaseAuthException catch (e) {
      // e.g. user-mismatch: a different Google account was picked.
      _log('firebase-reauth', e.code);
      throw const AuthFailure(AuthFailureReason.authFailure);
    }
  }

  @override
  Future<void> signOut() async {
    final session = cloudSession;
    if (session != null) {
      await session.signOut(_signOutAuth);
    } else {
      await _signOutAuth();
    }
  }

  Future<void> _signOutAuth() async {
    // Xoá phiên Firebase trước (nguồn sự thật); lỗi ở Google không được giữ
    // phiên Firebase còn sống.
    try {
      await _auth.signOut();
    } finally {
      try {
        await _ensureGoogleInit();
        await _google.signOut();
      } on Exception catch (e) {
        _log('google-signout', e.runtimeType.toString());
      }
    }
  }

  /// Chỉ mã lỗi/loại — không token, không email.
  void _log(String source, String code) {
    if (kDebugMode) debugPrint('[auth] $source: $code');
  }
}

/// Dùng khi môi trường chưa cấu hình Firebase: không bao giờ chạm vào Firebase.
class UnavailableAuthRepository implements AuthRepository {
  const UnavailableAuthRepository();

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
