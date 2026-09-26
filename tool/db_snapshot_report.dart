// Host-side, read-only: prints the same DbSnapshot summary (counts, digests,
// walletId — no row contents) for a PLAINTEXT SQLite file, e.g. a verified
// pre-migration backup. Usage:
//   flutter test tool/db_snapshot_report.dart --dart-define=DB=<path>
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:vi_nha_minh/data/local/db_encryption/sqlcipher_wallet.dart';

void main() {
  test('report', () {
    const path = String.fromEnvironment('DB');
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      // ignore: avoid_print
      print('REPORT ${jsonEncode(captureSnapshot(db).summary())}');
    } finally {
      db.close();
    }
  });
}
