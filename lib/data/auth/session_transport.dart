import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/auth/cloud_session.dart';

/// Firebase callable wire protocol over HTTPS. Only fixed session/backup
/// endpoints. Backup endpoints carry wrapped keys and ciphertext envelopes only
/// (never plaintext financial payloads); no retries, outbox or request logging.
class SessionTransportClient {
  SessionTransportClient(this.auth, this.projectId);
  final FirebaseAuth auth;
  final String projectId;
  static const operations = {
    'activateSession',
    'protectedPing',
    'deactivateSession',
    'requestTakeover',
    'approveTakeover',
    'rejectTakeover',
    'completeTakeover',
    'recoverSession',
    'putBackupKeyring',
    'getBackupKeyring',
    'listBackupWallets',
    'putEncryptedBatch',
    'getEncryptedChanges',
    // P8.2: ownership metadata only (no financial payload).
    'claimWallet',
    'getWalletClaim',
    'abandonClaim',
  };

  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, dynamic> data,
  ) async {
    if (!operations.contains(operation)) {
      throw const SessionFailure(true);
    }
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final user = auth.currentUser;
      if (user == null || user.uid != data['accountId']) {
        throw const SessionFailure(true);
      }
      final token = await user.getIdToken().timeout(
        const Duration(seconds: 10),
      );
      if (token == null) throw const SessionFailure(true);
      final request = await http.postUrl(
        Uri.https('us-central1-$projectId.cloudfunctions.net', '/$operation'),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.write(jsonEncode({'data': data}));
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final body = jsonDecode(
        await response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 10)),
      ) as Map<String, dynamic>;
      if (response.statusCode != 200 || body['error'] != null) {
        final error = body['error'] as Map?;
        final status = error?['status'];
        final details = error?['details'];
        throw SessionFailure(
          status == 'PERMISSION_DENIED' || status == 'UNAUTHENTICATED',
          details is Map && details['reason'] is String
              ? details['reason'] as String
              : null,
        );
      }
      return Map<String, dynamic>.from(body['result'] as Map);
    } on SessionFailure {
      rethrow;
    } on Object {
      throw const SessionFailure(false);
    } finally {
      http.close(force: true);
    }
  }
}
