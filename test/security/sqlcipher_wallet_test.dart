import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:vi_nha_minh/core/crypto/backup_crypto.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/db_encryption/db_key_store.dart';
import 'package:vi_nha_minh/data/local/db_encryption/db_preflight.dart';
import 'package:vi_nha_minh/presentation/features/security/db_recovery_screen.dart';
import 'package:vi_nha_minh/data/local/db_encryption/sqlcipher_wallet.dart';
import 'package:vi_nha_minh/data/local/seed_defaults.dart';
import 'package:vi_nha_minh/data/local/wallet_descriptor.dart';
import 'package:vi_nha_minh/domain/entities/wallet_identity.dart';

import '../support/memory_db_key_store.dart';


const fileName = 'vi_nha_minh.sqlite';

/// Plaintext (current schema) Wallet with the full demo seed + transactions (incl. notes).
Future<File> plaintextFixture(Directory dir, {int transactions = 40}) async {
  final file = File('${dir.path}/$fileName');
  final db = AppDatabase.forTesting(NativeDatabase(file), seed: SeedProfile.demo);
  final category = (await db.select(db.categoryRows).get()).first.id;
  final now = DateTime(2026, 9, 1);
  for (var i = 0; i < transactions; i++) {
    await db.into(db.transactionRows).insert(TransactionRowsCompanion.insert(
      id: 'tx-$i',
      type: 'income',
      categoryId: category,
      sourceKind: 'external',
      destinationKind: 'memberAvailable',
      destinationRefId: const Value('vo'),
      amountMinor: 1000 + i * 137,
      note: Value('Ghi chú riêng tư $i — Tiền chợ'),
      transactionDate: now.add(Duration(days: i)),
      createdAt: now,
      clientTxId: 'client-$i',
    ));
  }
  await db.close();
  return file;
}

DbSnapshot snapshotPlain(File f) {
  final db = sqlite3.open(f.path, mode: OpenMode.readOnly);
  try {
    return captureSnapshot(db);
  } finally {
    db.close();
  }
}

DbSnapshot snapshotKeyed(File f, Uint8List key) {
  final db = sqlite3.open(f.path, mode: OpenMode.readOnly);
  try {
    applySqlcipherKey(db, key);
    return captureSnapshot(db);
  } finally {
    db.close();
  }
}

void expectUnreadableWithout(File f, {Uint8List? wrongKey}) {
  final db = sqlite3.open(f.path, mode: OpenMode.readOnly);
  try {
    if (wrongKey != null) {
      expect(() => applySqlcipherKey(db, wrongKey), throwsA(isA<SqliteException>()));
    } else {
      expect(() => db.select('SELECT count(*) FROM sqlite_master'),
          throwsA(isA<SqliteException>()));
    }
  } finally {
    db.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('sqlcipher_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('linked library is SQLCipher', () {
    final db = sqlite3.openInMemory();
    expect('${db.select('PRAGMA cipher_version').first.values.first}', startsWith('4.'));
    db.close();
  });

  test('fresh Wallet is created encrypted; key bound to its walletId', () async {
    final keys = MemoryDbKeyStore();
    final db = AppDatabase(keyStore: keys, directory: () async => dir);
    final walletId = (await db.select(db.walletMeta).getSingle()).walletId;
    await db.close();
    final file = File('${dir.path}/$fileName');
    expect(probeDbFile(file), DbFileState.encrypted);
    expect(keys.entries[fileName]!.walletId, walletId);
    expectUnreadableWithout(file);
    expectUnreadableWithout(file, wrongKey: BackupCrypto.randomBytes(32));
    expect(snapshotKeyed(file, keys.entries[fileName]!.key).walletId, walletId);
    // Raw bytes carry no plaintext SQLite header / schema text.
    final bytes = file.readAsBytesSync();
    expect(String.fromCharCodes(bytes).contains('wallet_meta'), isFalse);
  });

  test('plaintext Wallet → SQLCipher: every table/field/ids/walletId identical', () async {
    final file = await plaintextFixture(dir);
    final before = snapshotPlain(file);
    expect(before.healthy, isTrue);
    expect(before.userVersion, 10);
    expect(before.count('transaction_rows'), 40);
    final keys = MemoryDbKeyStore();
    final plan = await WalletDbEncryption(keys).prepare(file, fileName);
    expect(plan.migratedNow, isTrue);
    expect(plan.status, DbEncryptionStatus.encrypted);
    expect(probeDbFile(file), DbFileState.encrypted);
    expect(WalletDbEncryption.rollbackFor(file).existsSync(), isFalse);
    expect(WalletDbEncryption.tempFor(file).existsSync(), isFalse);
    final after = snapshotKeyed(file, plan.key!);
    expect(after.sameDataAs(before), isTrue);
    expect(after.healthy, isTrue);
    expect(keys.entries[fileName]!.walletId, before.walletId);
    expectUnreadableWithout(file);
    expectUnreadableWithout(file, wrongKey: BackupCrypto.randomBytes(32));
    final raw = String.fromCharCodes(file.readAsBytesSync());
    expect(raw.contains('Tiền chợ'), isFalse);
    expect(raw.contains('Ghi ch'), isFalse);
    // The app opens it normally through drift; second prepare is a no-op.
    final db = AppDatabase(keyStore: keys, directory: () async => dir);
    expect((await db.select(db.transactionRows).get()).length, 40);
    expect(await db.customSelect('PRAGMA foreign_keys').getSingle()
        .then((r) => r.data.values.first), 1);
    await db.close();
    expect(keys.creates, 1);
    expect(snapshotKeyed(file, plan.key!).sameDataAs(before), isTrue);
  });

  test('snapshot detects a single changed field (negative control)', () async {
    final file = await plaintextFixture(dir, transactions: 3);
    final before = snapshotPlain(file);
    final db = sqlite3.open(file.path);
    db.execute("UPDATE transaction_rows SET note = 'x' WHERE id = 'tx-1'");
    db.close();
    expect(snapshotPlain(file).sameDataAs(before), isFalse);
    final db2 = sqlite3.open(file.path);
    db2.execute("UPDATE transaction_rows SET amount_minor = amount_minor WHERE id = 'tx-2'");
    db2.close();
  });

  for (final stage in ['after-source-snapshot', 'after-key', 'after-export',
    'after-verify', 'after-rename-original', 'after-swap', 'after-final-verify']) {
    test('injected failure at $stage: original plaintext kept and usable, retry succeeds', () async {
      final file = await plaintextFixture(dir, transactions: 12);
      final original = file.readAsBytesSync();
      final before = snapshotPlain(file);
      final keys = MemoryDbKeyStore();
      final plan = await WalletDbEncryption(keys, fault: (s) => s == stage)
          .prepare(file, fileName);
      expect(plan.status, DbEncryptionStatus.plaintextMigrationPending);
      expect(plan.key, isNull);
      expect(file.readAsBytesSync(), original, reason: 'byte-identical original');
      expect(WalletDbEncryption.tempFor(file).existsSync(), isFalse);
      expect(WalletDbEncryption.rollbackFor(file).existsSync(), isFalse);
      // Still usable as before (plaintext) in this session.
      final db = AppDatabase(
        keyStore: _FailingOnce(keys, stage), directory: () async => dir);
      expect((await db.select(db.transactionRows).get()).length, 12);
      await db.close();
      // Next launch: migration retried with the SAME key entry (no second key).
      final retry = await WalletDbEncryption(keys).prepare(file, fileName);
      expect(retry.status, DbEncryptionStatus.encrypted);
      expect(snapshotKeyed(file, retry.key!).sameDataAs(before), isTrue);
      expect(keys.creates, 1);
    });
  }

  test('interrupted after swap (crash): next launch finishes or restores safely', () async {
    final file = await plaintextFixture(dir, transactions: 5);
    final before = snapshotPlain(file);
    final keys = MemoryDbKeyStore();
    // Simulate a crash right after the swap: leave .pre-sqlcipher behind.
    final original = file.readAsBytesSync();
    await WalletDbEncryption(keys).prepare(file, fileName);
    WalletDbEncryption.rollbackFor(file).writeAsBytesSync(original);
    final plan = await WalletDbEncryption(keys).prepare(file, fileName);
    expect(plan.status, DbEncryptionStatus.encrypted);
    expect(WalletDbEncryption.rollbackFor(file).existsSync(), isFalse);
    expect(snapshotKeyed(file, plan.key!).sameDataAs(before), isTrue);
    // Crash with a broken/missing encrypted file: plaintext original restored.
    file.deleteSync();
    final file2 = await plaintextFixture(Directory('${dir.path}/b')..createSync());
    final keys2 = MemoryDbKeyStore();
    final original2 = file2.readAsBytesSync();
    WalletDbEncryption.rollbackFor(file2).writeAsBytesSync(original2);
    file2.writeAsBytesSync(List.filled(4096, 7)); // garbage "encrypted" file
    WalletDbEncryption.tempFor(file2).writeAsBytesSync([1, 2, 3]);
    final plan2 = await WalletDbEncryption(keys2).prepare(file2, fileName);
    expect(plan2.migratedNow, isTrue);
    expect(WalletDbEncryption.tempFor(file2).existsSync(), isFalse);
    expect(snapshotKeyed(file2, plan2.key!).count('transaction_rows'), 40);
  });

  test('key loss: encrypted DB preserved, recovery required, no new key', () async {
    final keys = MemoryDbKeyStore();
    final db = AppDatabase(keyStore: keys, directory: () async => dir);
    await db.select(db.walletMeta).getSingle();
    await db.close();
    final file = File('${dir.path}/$fileName');
    final bytes = file.readAsBytesSync();
    // (a) entry gone
    final lost = MemoryDbKeyStore();
    await expectLater(WalletDbEncryption(lost).prepare(file, fileName),
        throwsA(isA<DbRecoveryRequired>().having((e) => e.reason, 'reason', 'key-missing')));
    expect(lost.creates, 0);
    // (b) Keystore cannot unwrap
    keys.unavailable = true;
    await expectLater(WalletDbEncryption(keys).prepare(file, fileName),
        throwsA(isA<DbRecoveryRequired>().having((e) => e.reason, 'reason', 'key-unavailable')));
    // (c) wrong key
    final wrong = MemoryDbKeyStore()
      ..entries[fileName] = DbKeyEntry(BackupCrypto.randomBytes(32), null, 1);
    await expectLater(WalletDbEncryption(wrong).prepare(file, fileName),
        throwsA(isA<DbRecoveryRequired>().having((e) => e.reason, 'reason', 'key-mismatch')));
    // The app DB open surfaces the same state and never rewrites the file.
    final app = AppDatabase(keyStore: lost, directory: () async => dir);
    await expectLater(app.select(app.walletMeta).get(), throwsA(isA<DbRecoveryRequired>()));
    expect(file.readAsBytesSync(), bytes);
  });

  test('two Wallets: independent keys; one key cannot open the other', () async {
    final keys = MemoryDbKeyStore();
    final a = AppDatabase(keyStore: keys, directory: () async => dir);
    final b = AppDatabase(
      keyStore: keys,
      directory: () async => dir,
      wallet: const WalletDescriptor(kind: WalletKind.local, dbFileName: 'wallet_b.sqlite'),
    );
    await a.select(a.walletMeta).get();
    await b.select(b.walletMeta).get();
    await a.close();
    await b.close();
    final ka = keys.entries[fileName]!.key, kb = keys.entries['wallet_b.sqlite']!.key;
    expect(ka, isNot(kb));
    expectUnreadableWithout(File('${dir.path}/wallet_b.sqlite'), wrongKey: ka);
    expectUnreadableWithout(File('${dir.path}/$fileName'), wrongKey: kb);
  });

  test('App Lock independence: PIN/biometric code never touches the DB key', () {
    for (final path in [
      'android/app/src/main/kotlin/com/vinhamimh/vi_nha_minh/AppLockBridge.kt',
      'lib/presentation/providers/app_lock_provider.dart',
      'lib/data/security/method_channel_app_lock_platform.dart',
      'lib/domain/security/app_lock.dart',
    ]) {
      expect(File(path).readAsStringSync(),
          isNot(matches(RegExp(r'db_key|DbKey|sqlcipher|homewallet_db_wrap', caseSensitive: false))),
          reason: path);
    }
    final bridge = File(
      'android/app/src/main/kotlin/com/vinhamimh/vi_nha_minh/DbKeyBridge.kt',
    ).readAsStringSync();
    // Not user-auth bound, not derived from any PIN/password: a separate key.
    expect(bridge, isNot(matches(RegExp(r'setUserAuthentication|app_lock|AppLock|verifyPin|pbkdf'))));
  });

  test('preflight: migrates on first launch; key loss ⇒ recovery state, file untouched', () async {
    final file = await plaintextFixture(dir, transactions: 8);
    final before = snapshotPlain(file);
    final keys = MemoryDbKeyStore();
    expect(await preflightLocalWalletDatabase(keyStore: keys, directory: () async => dir), isNull);
    expect(snapshotKeyed(file, keys.entries[fileName]!.key).sameDataAs(before), isTrue);
    final bytes = file.readAsBytesSync();
    final recovery = await preflightLocalWalletDatabase(
      keyStore: MemoryDbKeyStore(), directory: () async => dir);
    expect(recovery?.reason, 'key-missing');
    expect(file.readAsBytesSync(), bytes);
  });

  testWidgets('recovery screen offers no reset/overwrite action', (t) async {
    await t.pumpWidget(const DbRecoveryRequiredApp(reason: 'key-missing'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('db_recovery_title')), findsOneWidget);
    expect(find.byType(ButtonStyleButton), findsNothing);
  });

  test('Keystore bridge contract + static hygiene', () async {
    final native = File(
      'android/app/src/main/kotlin/com/vinhamimh/vi_nha_minh/DbKeyBridge.kt',
    ).readAsStringSync();
    expect(native, contains('AndroidKeyStore'));
    expect(native, contains('homewallet_db_wrap_v1'));
    expect(native, contains('SecureRandom'));
    expect(native, contains('"db_key_exists"'));
    expect(native, isNot(matches(RegExp(r'Log\.|println|remove\(|clear\('))));
    for (final path in [
      'lib/data/local/db_encryption/sqlcipher_wallet.dart',
      'lib/data/local/db_encryption/db_key_store.dart',
    ]) {
      expect(File(path).readAsStringSync(),
          isNot(matches(RegExp(r'print\(|debugPrint\(|shared_preferences|firebase|app_lock'))),
          reason: path);
    }
    expect(File('pubspec.yaml').readAsStringSync(), contains('source: sqlcipher'));
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(KeystoreDbKeyStore.channel, (call) async {
      calls.add(call);
      if (call.method == 'load') {
        throw PlatformException(code: 'db_key_unavailable');
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(KeystoreDbKeyStore.channel, null));
    await expectLater(const KeystoreDbKeyStore().load(fileName),
        throwsA(isA<DbKeyUnavailable>()));
    expect(DbKeyEntry(Uint8List(32), 'w', 1).toString(), isNot(contains('0, 0')));
  });
}

/// Migration fails on the first launch (fault) but the SAME key store is used
/// afterwards; wraps it only so the app open in that session also skips.
class _FailingOnce implements DbKeyStore {
  _FailingOnce(this.inner, this.stage);
  final MemoryDbKeyStore inner;
  final String stage;
  @override
  Future<DbKeyEntry?> load(String f) async {
    // Force the in-session open to see a failed migration too.
    throw const DbKeyUnavailable();
  }

  @override
  Future<DbKeyEntry> create(String f, {String? walletId}) async =>
      throw const DbKeyUnavailable();
  @override
  Future<void> bindWallet(String f, String walletId) => inner.bindWallet(f, walletId);
}
