import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/application/commands/create_transaction_command.dart';
import 'package:vi_nha_minh/application/use_cases/add_transaction_use_case.dart';
import 'package:vi_nha_minh/application/use_cases/get_transaction_by_id_use_case.dart';
import 'package:vi_nha_minh/application/use_cases/watch_transactions_use_case.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/repositories/local_transaction_repository.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/errors/domain_exceptions.dart';

import 'support/recording_transaction_repository.dart';

CreateTransactionCommand _incomeCommand({
  String? id,
  String? clientTxId,
  String categoryId = 'thu_nhap',
  int amountMinor = 100000,
}) {
  return CreateTransactionCommand(
    baseCurrencyCode: 'VND',
    id: id,
    clientTxId: clientTxId,
    type: TransactionType.income,
    categoryId: categoryId,
    sourceKind: PoolKind.external,
    destinationKind: PoolKind.memberAvailable,
    destinationRefId: 'vo',
    amountMinor: amountMinor,
    transactionDate: DateTime(2026, 9, 1),
  );
}

void main() {
  group('Error propagation (mục 26-30) — Application không catch/biến đổi exception', () {
    test('26 — InsufficientBalanceException propagate nguyên vẹn', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final useCase = AddTransactionUseCase(LocalTransactionRepository(db));

      await expectLater(
        useCase(
          CreateTransactionCommand(
            baseCurrencyCode: 'VND',
            type: TransactionType.expense,
            categoryId: 'sinh_hoat',
            sourceKind: PoolKind.memberAvailable,
            sourceRefId: 'vo',
            destinationKind: PoolKind.external,
            amountMinor: 999999999,
            transactionDate: DateTime(2026, 9, 1),
          ),
        ),
        throwsA(isA<InsufficientBalanceException>()),
      );
    });

    test('27 — ClientTxIdConflictException propagate nguyên vẹn', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final useCase = AddTransactionUseCase(LocalTransactionRepository(db));

      await useCase(_incomeCommand(id: 'a', clientTxId: 'dup', amountMinor: 100000));
      await expectLater(
        useCase(_incomeCommand(id: 'b', clientTxId: 'dup', amountMinor: 999)),
        throwsA(isA<ClientTxIdConflictException>()),
      );
    });

    test('28 — TransactionNotFoundException propagate nguyên vẹn (qua use case reverse/update)', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = LocalTransactionRepository(db);

      await expectLater(
        repo.reverseTransaction('khong-ton-tai'),
        throwsA(isA<TransactionNotFoundException>()),
      );
    });

    test(
      '29 — PersistenceConstraintException (FK violation) không bị biến thành raw SqliteException/UI string',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final useCase = AddTransactionUseCase(LocalTransactionRepository(db));

        await expectLater(
          useCase(_incomeCommand(categoryId: 'khong_ton_tai')),
          throwsA(
            isA<PersistenceConstraintException>().having(
              (e) => e.kind,
              'kind',
              PersistenceConstraintKind.foreignKey,
            ),
          ),
        );
      },
    );

    test('30 — PersistenceException không bị Application nuốt (fake repository throw thẳng)', () async {
      final fakeRepo = RecordingTransactionRepository()
        ..throwOnAdd = const PersistenceException('lỗi mô phỏng');
      final useCase = AddTransactionUseCase(fakeRepo);

      await expectLater(
        useCase(_incomeCommand()),
        throwsA(isA<PersistenceException>()),
      );
    });
  });

  group('Query use cases (mục 17)', () {
    test('GetTransactionByIdUseCase — forward đúng tới Repository, kể cả null khi không tìm thấy', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = LocalTransactionRepository(db);
      final addUseCase = AddTransactionUseCase(repo);
      final getUseCase = GetTransactionByIdUseCase(repo);

      final tx = await addUseCase(_incomeCommand());
      expect((await getUseCase(tx.id))?.id, tx.id);
      expect(await getUseCase('khong-ton-tai'), isNull);
    });

    test('WatchTransactionsUseCase — forward đúng stream từ Repository', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = LocalTransactionRepository(db);
      final addUseCase = AddTransactionUseCase(repo);
      final watchUseCase = WatchTransactionsUseCase(repo);

      await addUseCase(_incomeCommand());
      final list = await watchUseCase().first;
      expect(list, hasLength(1));
    });
  });
}
