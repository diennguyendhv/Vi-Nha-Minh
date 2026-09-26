import 'dart:io';

import 'package:drift/drift.dart';
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
  final dir = Directory('${root.path}/db_bench_${DateTime.now().microsecondsSinceEpoch}')
    ..createSync();
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
              ..where((t) => t.transactionDate.isBiggerOrEqualValue(DateTime(2026, 9)))
              ..orderBy([(t) => OrderingTerm.desc(t.transactionDate)])
              ..limit(100))
            .get();
      });
      var n = 0;
      result['add+edit+delete (1 tx each, own transaction)'] = await median(() async {
        final id = 'bench-${n++}';
        final category = (await db.select(db.categoryRows).get()).first.id;
        await db.transaction(() => db.into(db.transactionRows).insert(_row(id, category, 1)));
        await db.transaction(() => (db.update(db.transactionRows)
              ..where((t) => t.id.equals(id)))
            .write(const TransactionRowsCompanion(amountMinor: Value(4242))));
        await db.transaction(() => (db.delete(db.transactionRows)
              ..where((t) => t.id.equals(id)))
            .go());
      });
      await db.close();
      return result;
    }

    final plain = await measure(plainFile, null);
    final encrypted = await measure(encFile, key);
    return {
      for (final k in plain.keys) k: (plain: plain[k]!, encrypted: encrypted[k]!),
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
  final db = AppDatabase.forTesting(NativeDatabase(file), seed: SeedProfile.demo);
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
    };
  } finally {
    db.close();
  }
}
