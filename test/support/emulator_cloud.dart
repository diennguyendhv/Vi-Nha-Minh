import 'dart:convert';
import 'dart:io';

import 'package:vi_nha_minh/domain/auth/cloud_session.dart';

/// Test-only: Firebase emulator (demo project, never live). Chạy khi
/// `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080` (do `emulators:exec` đặt) và emulator auth/firestore/functions đang chạy
/// (`firebase emulators:exec --project demo-homewallet-p7 ...`).
final emulatorEnabled =
    const bool.fromEnvironment('HW_EMULATOR') ||
    Platform.environment['FIRESTORE_EMULATOR_HOST'] == '127.0.0.1:8080';
const emulatorProject = 'demo-homewallet-p7';

Future<Map<String, dynamic>> _post(Uri uri, Object body, {String? bearer}) async {
  final http = HttpClient();
  try {
    final req = await http.postUrl(uri);
    req.headers.contentType = ContentType.json;
    if (bearer != null) req.headers.set('Authorization', 'Bearer $bearer');
    req.write(jsonEncode(body));
    final res = await req.close();
    return jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
  } finally {
    http.close(force: true);
  }
}

class EmulatorAccount {
  EmulatorAccount(this.uid, this.idToken);
  final String uid;
  final String idToken;

  static Future<EmulatorAccount> create() async {
    final r = await _post(
      Uri.parse(
        'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake',
      ),
      {'returnSecureToken': true},
    );
    return EmulatorAccount(r['localId'] as String, r['idToken'] as String);
  }

  /// P10: Account có email ĐÃ XÁC MINH (emulator chấp nhận token không ký nên có thể
  /// đặt `email_verified`, như functions/test/family.test.js). Không bao giờ live.
  static Future<({EmulatorAccount account, String email})> createWithEmail() async {
    final email =
        'u${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}@example.test';
    final r = await _post(
      Uri.parse(
        'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake',
      ),
      {'email': email, 'password': 'emulator-only-pw', 'returnSecureToken': true},
    );
    final parts = (r['idToken'] as String).split('.');
    final claims =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
            as Map<String, dynamic>;
    claims['email_verified'] = true;
    final payload = base64Url
        .encode(utf8.encode(jsonEncode(claims)))
        .replaceAll('=', '');
    return (
      account: EmulatorAccount(r['localId'] as String, '${parts[0]}.$payload.'),
      email: email,
    );
  }
}

/// Callable wire protocol → Functions emulator. Same error mapping as the app's
/// `SessionTransportClient` (PERMISSION_DENIED/UNAUTHENTICATED ⇒ auth failure,
/// `details.reason` preserved). [current] = the Account signed in on this device.
class EmulatorTransport {
  EmulatorAccount? current;
  int calls = 0;

  Future<Map<String, dynamic>> call(String op, Map<String, dynamic> data) async {
    final account = current;
    if (account == null || account.uid != data['accountId']) {
      throw const SessionFailure(true);
    }
    calls++;
    final body = await _post(
      Uri.parse('http://127.0.0.1:5001/$emulatorProject/us-central1/$op'),
      {'data': {'clientEnv': 'dev', ...data}},
      bearer: account.idToken,
    );
    final error = body['error'] as Map?;
    if (error != null) {
      final details = error['details'];
      throw SessionFailure(
        error['status'] == 'PERMISSION_DENIED' || error['status'] == 'UNAUTHENTICATED',
        details is Map && details['reason'] is String ? details['reason'] as String : null,
      );
    }
    return Map<String, dynamic>.from(body['result'] as Map);
  }
}

/// Everything Firestore stores under [paths] (admin view, emulator only) as raw JSON.
Future<String> firestoreDump(List<String> paths) async {
  final http = HttpClient();
  final out = StringBuffer();
  Future<void> walk(String path) async {
    final base =
        'http://127.0.0.1:8080/v1/projects/$emulatorProject/databases/(default)/documents/$path';
    final docReq = await http.getUrl(Uri.parse(base));
    docReq.headers.set('Authorization', 'Bearer owner');
    final docRes = await docReq.close();
    out.writeln(await docRes.transform(utf8.decoder).join());
    final colReq = await http.postUrl(Uri.parse('$base:listCollectionIds'));
    colReq.headers
      ..set('Authorization', 'Bearer owner')
      ..contentType = ContentType.json;
    colReq.write('{}');
    final cols = jsonDecode(await (await colReq.close()).transform(utf8.decoder).join()) as Map;
    for (final c in (cols['collectionIds'] as List?) ?? const []) {
      String? pageToken;
      do {
        final listReq = await http.getUrl(
          Uri.parse('$base/$c?pageSize=300${pageToken == null ? '' : '&pageToken=$pageToken'}'),
        );
        listReq.headers.set('Authorization', 'Bearer owner');
        final list =
            jsonDecode(await (await listReq.close()).transform(utf8.decoder).join()) as Map;
        for (final d in (list['documents'] as List?) ?? const []) {
          final name = (d as Map)['name'] as String;
          await walk(name.substring(name.indexOf('/documents/') + 11));
        }
        pageToken = list['nextPageToken'] as String?;
      } while (pageToken != null);
    }
  }

  try {
    for (final p in paths) {
      await walk(p);
    }
  } finally {
    http.close(force: true);
  }
  return out.toString();
}
