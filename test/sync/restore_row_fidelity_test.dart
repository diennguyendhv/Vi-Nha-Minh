import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/application/commands/create_transaction_command.dart';
import 'package:vi_nha_minh/application/use_cases/add_transaction_use_case.dart';
import 'package:vi_nha_minh/core/config/app_environment.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/wallet_registry.dart';
import 'package:vi_nha_minh/data/repositories/local_transaction_repository.dart';
import 'package:vi_nha_minh/data/sync/restore_engine.dart';
import 'package:vi_nha_minh/data/sync/restore_storage.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';

import '../support/fake_cloud.dart';
import '../support/memory_db_key_store.dart';

/// P8.5 — khôi phục phải tái tạo TỪNG Ô của mọi dòng (giá trị + kiểu lưu SQLite),
/// không chỉ số dòng/số dư: so `SELECT *` + `typeof()` từng cột nguồn ↔ ví khôi phục.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vnm_restore_fidelity_'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<Map<String, Map<String, String>>> cells(AppDatabase db, String table) async {
    final cols = [
      for (final r in await db.customSelect('PRAGMA table_info($table)').get())
        r.read<String>('name'),
    ];
    final sel = cols.map((c) => "typeof($c) || ':' || quote($c) AS $c").join(', ');
    return {
      for (final r in await db.customSelect('SELECT id AS _k, $sel FROM $table').get())
        r.read<String>('_k'): {for (final c in cols) c: r.read<String>(c)},
    };
  }

  test('giao dịch tạo/sửa/xoá qua repository ⇒ khôi phục trùng từng ô', () async {
    final cloud = FakeCloud();
    final a = FakeDevice(cloud, db: AppDatabase.forTesting(NativeDatabase.memory()));
    await a.signIn('uid-f');
    await a.claim();
    await a.engine.enableBackup('Mật khẩu sao lưu fidelity');
    await a.engine.push();

    final repo = LocalTransactionRepository(a.db);
    final add = AddTransactionUseCase(repo);
    await add(CreateTransactionCommand(
      baseCurrencyCode: 'VND', type: TransactionType.income, categoryId: 'thu_nhap',
      sourceKind: PoolKind.external, destinationKind: PoolKind.memberAvailable,
      destinationRefId: 'vo', amountMinor: 1000000, transactionDate: DateTime(2026, 9, 26),
    ));
    final e = await add(CreateTransactionCommand(
      baseCurrencyCode: 'VND', type: TransactionType.expense, categoryId: 'sinh_hoat',
      sourceKind: PoolKind.memberAvailable, sourceRefId: 'vo',
      destinationKind: PoolKind.external, amountMinor: 12345,
      transactionDate: DateTime.now(), note: 'P84',
    ));
    await a.engine.push();
    await repo.updateTransaction(e.id, amountMinor: 12346);
    await a.engine.push();
    await add(CreateTransactionCommand(
      baseCurrencyCode: 'VND', type: TransactionType.expense, categoryId: 'sinh_hoat',
      sourceKind: PoolKind.memberAvailable, sourceRefId: 'vo',
      destinationKind: PoolKind.external, amountMinor: 777,
      transactionDate: DateTime.now(), note: 'offline',
    ));
    await repo.deleteTransaction(e.id);
    await a.engine.push();
    final source = await cells(a.db, 'transaction_rows');
    final walletId = await a.walletId();

    final c = FakeDevice(cloud, installation: '44444444-4444-4444-8444-444444444444');
    await c.signIn('uid-f');
    final keys = MemoryDbKeyStore();
    final registry = WalletRegistry.inMemory();
    final result = await RestoreEngine(
      session: c.session, transport: cloud.call, keyStore: c.keys, registry: registry,
      storage: SqlcipherRestoreStorage(keyStore: keys, directory: () async => dir),
      env: AppEnvironment.dev,
    ).restore(walletId: walletId, password: 'Mật khẩu sao lưu fidelity');
    final restored = AppDatabase(
      wallet: registry.byWalletId(walletId)!.toDescriptor(),
      keyStore: keys,
      directory: () async => dir,
    );
    final got = await cells(restored, 'transaction_rows');
    await restored.close();
    await a.db.close();
    expect(result.walletId, walletId);
    expect(got.keys.toSet(), source.keys.toSet());
    for (final id in source.keys) {
      for (final col in source[id]!.keys) {
        expect(got[id]![col], source[id]![col], reason: '$id.$col');
      }
    }
  });
}
