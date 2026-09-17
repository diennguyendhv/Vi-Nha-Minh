import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/application/commands/create_transaction_command.dart';
import 'package:vi_nha_minh/application/use_cases/add_transaction_use_case.dart';
import 'package:vi_nha_minh/application/use_cases/change_transaction_status_use_case.dart';
import 'package:vi_nha_minh/application/use_cases/reverse_transaction_use_case.dart';
import 'package:vi_nha_minh/application/use_cases/update_transaction_use_case.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/repositories/local_transaction_repository.dart';
import 'package:vi_nha_minh/domain/engine/financial_engine.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/errors/domain_exceptions.dart';

void main() {
  late AppDatabase db;
  late LocalTransactionRepository repo;
  late AddTransactionUseCase addUseCase;
  late ReverseTransactionUseCase reverseUseCase;
  late UpdateTransactionUseCase updateUseCase;
  late ChangeTransactionStatusUseCase statusUseCase;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LocalTransactionRepository(db);
    addUseCase = AddTransactionUseCase(repo);
    reverseUseCase = ReverseTransactionUseCase(repo);
    updateUseCase = UpdateTransactionUseCase(repo);
    statusUseCase = ChangeTransactionStatusUseCase(repo);

    await db.into(db.statusRows).insert(
      StatusRowsCompanion.insert(id: 'st1', categoryId: 'cho_di', name: 'Bước 1', sortOrder: 0),
    );
  });

  tearDown(() async => db.close());

  group('Reversal', () {
    test('17 — reverse existing transaction thành công', () async {
      final tx = await addUseCase(
        CreateTransactionCommand(
          baseCurrencyCode: 'VND',
          type: TransactionType.income,
          categoryId: 'thu_nhap',
          sourceKind: PoolKind.external,
          destinationKind: PoolKind.memberAvailable,
          destinationRefId: 'vo',
          amountMinor: 100000,
          transactionDate: DateTime(2026, 9, 1),
        ),
      );

      await reverseUseCase(tx.id);

      final original = await repo.getTransactionById(tx.id);
      expect(original!.reversedByTxId, isNotNull);
      expect(await db.select(db.transactionRows).get(), hasLength(2));
    });

    test('18 — reverse non-existing → TransactionNotFoundException', () async {
      await expectLater(
        reverseUseCase('khong-ton-tai'),
        throwsA(isA<TransactionNotFoundException>()),
      );
    });

    test('19 — reverse đã reversed → AlreadyReversedException', () async {
      final tx = await addUseCase(
        CreateTransactionCommand(
          baseCurrencyCode: 'VND',
          type: TransactionType.income,
          categoryId: 'thu_nhap',
          sourceKind: PoolKind.external,
          destinationKind: PoolKind.memberAvailable,
          destinationRefId: 'vo',
          amountMinor: 100000,
          transactionDate: DateTime(2026, 9, 1),
        ),
      );
      await reverseUseCase(tx.id);

      await expectLater(reverseUseCase(tx.id), throwsA(isA<AlreadyReversedException>()));
    });
  });

  group('Update / Correction', () {
    test('20 — update tài chính (amountMinor) đi đúng Repository contract (reversal + replacement)', () async {
      final tx = await addUseCase(
        CreateTransactionCommand(
          baseCurrencyCode: 'VND',
          type: TransactionType.income,
          categoryId: 'thu_nhap',
          sourceKind: PoolKind.external,
          destinationKind: PoolKind.memberAvailable,
          destinationRefId: 'vo',
          amountMinor: 100000,
          transactionDate: DateTime(2026, 9, 1),
        ),
      );

      await updateUseCase(tx.id, amountMinor: 250000);

      final rows = await db.select(db.transactionRows).get();
      expect(rows, hasLength(3), reason: 'original + reversal + replacement');
      final replacement = rows.firstWhere((r) => r.correctsTxId == tx.id);
      expect(replacement.amountMinor, 250000);
      final original = rows.firstWhere((r) => r.id == tx.id);
      expect(original.amountMinor, 100000, reason: 'bản gốc không bị mutate');
    });

    test('21 — update non-existing → TransactionNotFoundException', () async {
      await expectLater(
        updateUseCase('khong-ton-tai', amountMinor: 999),
        throwsA(isA<TransactionNotFoundException>()),
      );
    });

    test('22 — update phi tài chính (note/category/date/status) không tạo financial effect', () async {
      final tx = await addUseCase(
        CreateTransactionCommand(
          baseCurrencyCode: 'VND',
          type: TransactionType.income,
          categoryId: 'thu_nhap',
          sourceKind: PoolKind.external,
          destinationKind: PoolKind.memberAvailable,
          destinationRefId: 'vo',
          amountMinor: 100000,
          transactionDate: DateTime(2026, 9, 1),
        ),
      );

      await updateUseCase(tx.id, note: 'ghi chú mới', transactionDate: DateTime(2026, 9, 2));

      expect(
        await db.select(db.transactionRows).get(),
        hasLength(1),
        reason: 'không tạo reversal/replacement nào — update thẳng tại chỗ',
      );
      final row = await repo.getTransactionById(tx.id);
      expect(row!.note, 'ghi chú mới');
      expect(row.transactionDate, DateTime(2026, 9, 2));
      expect(row.reversalOfTxId, isNull);
      expect(row.correctsTxId, isNull);
    });
  });

  group('Status', () {
    test('23/24 — change status thành công, statusUpdatedAt cập nhật đúng', () async {
      await addUseCase(
        CreateTransactionCommand(
          baseCurrencyCode: 'VND',
          type: TransactionType.income,
          categoryId: 'thu_nhap',
          sourceKind: PoolKind.external,
          destinationKind: PoolKind.memberAvailable,
          destinationRefId: 'vo',
          amountMinor: 200000,
          transactionDate: DateTime(2026, 9, 1),
        ),
      );
      final tx = await addUseCase(
        CreateTransactionCommand(
          baseCurrencyCode: 'VND',
          type: TransactionType.expense,
          categoryId: 'cho_di',
          sourceKind: PoolKind.memberAvailable,
          sourceRefId: 'vo',
          destinationKind: PoolKind.external,
          amountMinor: 50000,
          transactionDate: DateTime(2026, 9, 1),
        ),
      );
      expect(tx.statusUpdatedAt, isNull);

      await statusUseCase(tx.id, 'st1');

      final updated = await repo.getTransactionById(tx.id);
      expect(updated!.statusId, 'st1');
      expect(updated.statusUpdatedAt, isNotNull, reason: 'Test 24');
    });

    test('25 — balance/financial effect không đổi sau status-only update', () async {
      await addUseCase(
        CreateTransactionCommand(
          baseCurrencyCode: 'VND',
          type: TransactionType.income,
          categoryId: 'thu_nhap',
          sourceKind: PoolKind.external,
          destinationKind: PoolKind.memberAvailable,
          destinationRefId: 'vo',
          amountMinor: 200000,
          transactionDate: DateTime(2026, 9, 1),
        ),
      );
      final tx = await addUseCase(
        CreateTransactionCommand(
          baseCurrencyCode: 'VND',
          type: TransactionType.expense,
          categoryId: 'cho_di',
          sourceKind: PoolKind.memberAvailable,
          sourceRefId: 'vo',
          destinationKind: PoolKind.external,
          amountMinor: 50000,
          transactionDate: DateTime(2026, 9, 1),
        ),
      );

      final before = computeAllPoolBalances(await repo.watchTransactions().first);
      await statusUseCase(tx.id, 'st1');
      final after = computeAllPoolBalances(await repo.watchTransactions().first);

      expect(after, equals(before));
    });
  });
}
