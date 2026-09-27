import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:cryptography/dart.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../core/crypto/backup_crypto.dart';
import '../../repositories/local_transaction_repository.dart';
import '../app_database.dart';
import '../seed_defaults.dart';
import 'db_key_store.dart';
import 'sqlcipher_wallet.dart';

/// DEV/debug-only: compares plaintext vs SQLCipher on the SAME synthetic data
/// (temp files, ephemeral key; never the real Wallet, never the Keystore).
/// Returns median milliseconds per operation. Temp files are deleted.
Future<Map<String, ({int plain, int encrypted})>> runDebugDbBenchmark({
  int transactions = 2000,
  int rounds = 5,
}) async {
  final root = await getTemporaryDirectory();
  final dir = Directory(
    '${root.path}/db_bench_${DateTime.now().microsecondsSinceEpoch}',
  )..createSync();
  try {
    final plainFile = File('${dir.path}/plain.sqlite');
    await _fixture(plainFile, transactions);
    final encFile = File('${dir.path}/enc.sqlite');
    await plainFile.copy(encFile.path);
    final key = BackupCrypto.randomBytes(32);
    await _encryptInPlaceForBenchmark(encFile, key);

    AppDatabase open(File f, Uint8List? k) => AppDatabase.forTesting(
      NativeDatabase.createInBackground(
        f,
        setup: k == null ? null : (db) => applySqlcipherKey(db, k),
      ),
    );

    Future<int> median(Future<void> Function() op) async {
      final samples = <int>[];
      for (var i = 0; i < rounds; i++) {
        final sw = Stopwatch()..start();
        await op();
        samples.add(sw.elapsedMilliseconds);
      }
      samples.sort();
      return samples[samples.length ~/ 2];
    }

    Future<Map<String, int>> measure(File f, Uint8List? k) async {
      final result = <String, int>{};
      result['cold open + first query'] = await median(() async {
        final db = open(f, k);
        await db.select(db.walletMeta).get();
        await db.close();
      });
      final db = open(f, k);
      await db.select(db.walletMeta).get();
      final repo = LocalTransactionRepository(db);
      result['load all tx (Summary/list source)'] = await median(
        () => repo.watchTransactions().first,
      );
      result['month page query (100 rows, date desc)'] = await median(() async {
        await (db.select(db.transactionRows)
              ..where(
                (t) =>
                    t.transactionDate.isBiggerOrEqualValue(DateTime(2026, 9)),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.transactionDate)])
              ..limit(100))
            .get();
      });
      var n = 0;
      result['add+edit+delete (1 tx each, own transaction)'] = await median(
        () async {
          final id = 'bench-${n++}';
          final category = (await db.select(db.categoryRows).get()).first.id;
          await db.transaction(
            () => db.into(db.transactionRows).insert(_row(id, category, 1)),
          );
          await db.transaction(
            () => (db.update(db.transactionRows)..where((t) => t.id.equals(id)))
                .write(
                  const TransactionRowsCompanion(amountMinor: Value(4242)),
                ),
          );
          await db.transaction(
            () => (db.delete(
              db.transactionRows,
            )..where((t) => t.id.equals(id))).go(),
          );
        },
      );
      await db.close();
      return result;
    }

    final plain = await measure(plainFile, null);
    final encrypted = await measure(encFile, key);
    return {
      for (final k in plain.keys)
        k: (plain: plain[k]!, encrypted: encrypted[k]!),
    };
  } finally {
    dir.deleteSync(recursive: true);
  }
}

TransactionRowsCompanion _row(String id, String categoryId, int i) {
  final date = DateTime(2026, 1, 1).add(Duration(hours: i * 3));
  return TransactionRowsCompanion.insert(
    id: id,
    type: 'expense',
    categoryId: categoryId,
    sourceKind: 'memberAvailable',
    sourceRefId: const Value('vo'),
    destinationKind: 'external',
    amountMinor: 10000 + i,
    note: Value('bench note $i'),
    transactionDate: date,
    createdAt: date,
    clientTxId: 'c-$id',
  );
}

Future<void> _fixture(File file, int transactions) async {
  final db = AppDatabase.forTesting(
    NativeDatabase(file),
    seed: SeedProfile.demo,
  );
  final category = (await db.select(db.categoryRows).get()).first.id;
  await db.batch((b) {
    for (var i = 0; i < transactions; i++) {
      b.insert(db.transactionRows, _row('tx-$i', category, i));
    }
  });
  await db.close();
}

/// Same sqlcipher_export mechanism as the real migration, ephemeral key.
Future<void> _encryptInPlaceForBenchmark(File file, Uint8List key) async {
  final store = _EphemeralKeys(key);
  await WalletDbEncryption(store).prepare(file, 'bench.sqlite');
}

class _EphemeralKeys implements DbKeyStore {
  _EphemeralKeys(this.key);
  final Uint8List key;
  DbKeyEntry? entry;
  @override
  Future<DbKeyEntry?> load(String f) async => entry;
  @override
  Future<DbKeyEntry> create(String f, {String? walletId}) async =>
      entry = DbKeyEntry(key, walletId, 1);
  @override
  Future<void> bindWallet(String f, String walletId) async {}
}

/// DEV/debug-only, READ-ONLY integrity report of an on-device Wallet file:
/// counts, per-table digests, walletId, integrity, FK — never row contents.
/// Same algorithm as the migration verifier, so it can be compared with a
/// host-side report of the pre-migration plaintext backup.
Future<Map<String, Object?>> debugWalletIntegrityReport(
  String dbFileName, {
  DbKeyStore keyStore = const KeystoreDbKeyStore(),
}) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$dbFileName');
  final state = probeDbFile(file);
  final db = sqlite3.open(file.path, mode: OpenMode.readOnly);
  try {
    if (state == DbFileState.encrypted) {
      final entry = await keyStore.load(dbFileName);
      if (entry == null) return {'state': 'encrypted', 'error': 'key-missing'};
      applySqlcipherKey(db, entry.key);
    }
    return {
      'state': state.name,
      'cipher': '${db.select('PRAGMA cipher_version').first.values.first}',
      ...captureSnapshot(db).summary(),
      ..._transactionBreakdown(db),
      ..._conflictBreakdown(db),
    };
  } finally {
    db.close();
  }
}

/// Debug-only chẩn đoán: digest theo CỘT và theo DÒNG của `transaction_rows` (kiểu
/// lưu + giá trị qua `typeof`/`quote`) + id/clientTxId + id thành viên. Chỉ id mờ và
/// băm — không số tiền/ghi chú/nhãn.
Map<String, Object?> _transactionBreakdown(Database db) {
  String h(String v) => const DartSha256()
      .hashSync(utf8.encode(v))
      .bytes
      .take(6)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  final physical = [
    for (final r in db.select('PRAGMA table_info(transaction_rows)'))
      r['name'] as String,
  ];
  // Theo TÊN cột (không phụ thuộc thứ tự vật lý: ví migrate có cột ALTER ADD ở cuối,
  // ví tạo mới theo thứ tự khai báo).
  final cols = [...physical]..sort();
  final sel = cols
      .map((c) => "typeof($c) || ':' || quote($c) AS $c")
      .join(', ');
  final rows = db.select('SELECT $sel FROM transaction_rows ORDER BY id');
  return {
    // Digest cùng thuật toán `captureSnapshot` nhưng với `actor_member_id` (v9, ALTER
    // ADD COLUMN) ở CUỐI — thứ tự vật lý của ví tạo trước v9.
    'txDigestV9AppendOrder': _orderedDigest(db, [
      ...physical.where((c) => c != 'actor_member_id'),
      'actor_member_id',
    ]),
    'txColumns': {
      for (final c in cols) c: h(rows.map((r) => r[c] as String).join('')),
    },
    'txRows': {
      for (final r in rows)
        '${r['id']}': h(cols.map((c) => r[c] as String).join('')),
    },
    'txClientIds': {
      for (final r in db.select(
        'SELECT id, client_tx_id FROM transaction_rows ORDER BY id',
      ))
        '${r['id']}': r['client_tx_id'],
    },
    'memberIds': [
      for (final r in db.select(
        'SELECT member_id FROM financial_member_rows ORDER BY member_id',
      ))
        r['member_id'],
    ],
  };
}

/// Debug-only (P10 kiểm chứng xung đột): mỗi dòng `sync_conflicts` với id thực thể,
/// thao tác máy chủ đã thắng + revision, và SỐ TIỀN của bản cục bộ bị thay thế (để
/// chứng minh bản thua không bị bỏ im lặng). Chỉ chạy tay trên bản debug DEV.
Map<String, Object?> _conflictBreakdown(Database db) {
  final has = db.select(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'sync_conflicts'",
  );
  if (has.isEmpty) return const {};
  return {
    'syncConflicts': [
      for (final r in db.select(
        'SELECT entity_kind, entity_id, local_body, server_op, server_rev, '
        'resolved FROM sync_conflicts ORDER BY id',
      ))
        {
          'kind': r['entity_kind'],
          'id': r['entity_id'],
          'serverOp': r['server_op'],
          'serverRev': r['server_rev'],
          'resolved': r['resolved'],
          'localAmount': switch (r['local_body']) {
            final String body =>
              ((jsonDecode(body) as Map)['c'] as Map?)?['amount_minor'],
            _ => null,
          },
        },
    ],
  };
}

String _orderedDigest(Database db, List<String> cols) {
  String cell(Object? v) => switch (v) {
    null => 'N',
    int() => 'I$v',
    double() => 'R$v',
    String() => 'T${v.length}:$v',
    List<int>() =>
      'B${v.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}',
    _ => 'U$v',
  };
  final order = [for (var i = 1; i <= cols.length; i++) '$i'].join(', ');
  final buf = StringBuffer();
  for (final row in db.select(
    'SELECT ${cols.join(', ')} FROM transaction_rows ORDER BY $order',
  )) {
    buf.write('${row.values.map(cell).join('')}');
  }
  return const DartSha256()
      .hashSync(utf8.encode(buf.toString()))
      .bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}
