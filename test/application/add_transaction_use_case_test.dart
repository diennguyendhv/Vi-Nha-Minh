import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/application/commands/create_transaction_command.dart';
import 'package:vi_nha_minh/application/use_cases/add_transaction_use_case.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/repositories/local_transaction_repository.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/entities/transfer_kind.dart';
import 'package:vi_nha_minh/domain/errors/domain_exceptions.dart';

import 'support/recording_transaction_repository.dart';

void main() {
  group('Create (mapping command → domain Transaction — fake repository)', () {
    late RecordingTransactionRepository fakeRepo;
    late AddTransactionUseCase useCase;

    setUp(() {
      fakeRepo = RecordingTransactionRepository();
      useCase = AddTransactionUseCase(fakeRepo);
    });

    test('2 — add income thành công, Transaction build đúng từ command (5/6/7)', () async {
      final command = CreateTransactionCommand(
        baseCurrencyCode: 'VND',
        type: TransactionType.income,
        categoryId: 'thu_nhap',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 16000000,
        transactionDate: DateTime(2026, 9, 1),
        note: 'Lương tháng 9',
        statusId: null,
      );

      final result = await useCase(command);

      expect(result, fakeRepo.lastAdded);
      expect(result.id, command.id);
      expect(result.clientTxId, command.clientTxId);
      expect(result.type, TransactionType.income);
      expect(result.categoryId, 'thu_nhap');
      expect(result.sourceKind, PoolKind.external);
      expect(result.destinationKind, PoolKind.memberAvailable);
      expect(result.destinationRefId, 'vo');
      expect(result.amountMinor, 16000000, reason: 'Test 6 — amountMinor giữ nguyên integer');
      expect(result.note, 'Lương tháng 9', reason: 'Test 7 — note mapping đúng');
      expect(result.transactionDate, DateTime(2026, 9, 1), reason: 'Test 7 — date mapping đúng');
      expect(result.statusId, isNull, reason: 'Test 7 — status mapping đúng (null)');
      expect(result.createdAt, isNotNull);
    });

    test('3 — add expense thành công', () async {
      final command = CreateTransactionCommand(
        baseCurrencyCode: 'VND',
        type: TransactionType.expense,
        categoryId: 'sinh_hoat',
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: 200000,
        transactionDate: DateTime(2026, 9, 2),
        note: 'Mua đồ ăn',
      );

      final result = await useCase(command);

      expect(result.type, TransactionType.expense);
      expect(result.sourceKind, PoolKind.memberAvailable);
      expect(result.sourceRefId, 'vo');
      expect(result.destinationKind, PoolKind.external);
      expect(result.destinationRefId, isNull);
      expect(result.amountMinor, 200000);
    });

    test('4 — add transfer thành công', () async {
      final command = CreateTransactionCommand(
        baseCurrencyCode: 'VND',
        type: TransactionType.transfer,
        transferKind: TransferKind.memberToMember,
        categoryId: 'chuyen_tien_thanh_vien',
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'chong',
        amountMinor: 50000,
        transactionDate: DateTime(2026, 9, 3),
      );

      final result = await useCase(command);

      expect(result.type, TransactionType.transfer);
      expect(result.transferKind, TransferKind.memberToMember);
      expect(result.sourceRefId, 'vo');
      expect(result.destinationRefId, 'chong');
    });

    test('Category không đổi từ command sang statusId khác câu chuyện — status có giá trị vẫn giữ nguyên', () async {
      final command = CreateTransactionCommand(
        baseCurrencyCode: 'VND',
        type: TransactionType.expense,
        categoryId: 'cho_di',
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: 100000,
        transactionDate: DateTime(2026, 9, 4),
        statusId: 'cho_di_chua_chuan_bi',
      );

      final result = await useCase(command);

      expect(result.statusId, 'cho_di_chua_chuan_bi');
    });
  });

  group('Idempotency / retry (Repository thật — LocalTransactionRepository trên DB in-memory)', () {
    late AppDatabase db;
    late AddTransactionUseCase useCase;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      useCase = AddTransactionUseCase(LocalTransactionRepository(db));
    });

    tearDown(() async => db.close());

    test('8 — gọi cùng 1 command 2 lần → chỉ 1 logical transaction', () async {
      final command = CreateTransactionCommand(
        baseCurrencyCode: 'VND',
        type: TransactionType.income,
        categoryId: 'thu_nhap',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 100000,
        transactionDate: DateTime(2026, 9, 1),
      );

      final first = await useCase(command);
      final second = await useCase(command); // reuse SAME command instance — không tạo mới.

      expect(second.id, first.id);
      expect(await db.select(db.transactionRows).get(), hasLength(1));
    });

    test('9 — retry giữ nguyên clientTxId', () async {
      final command = CreateTransactionCommand(
        baseCurrencyCode: 'VND',
        type: TransactionType.income,
        categoryId: 'thu_nhap',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 100000,
        transactionDate: DateTime(2026, 9, 1),
      );

      final first = await useCase(command);
      final second = await useCase(command);

      expect(first.clientTxId, command.clientTxId);
      expect(second.clientTxId, command.clientTxId);
    });

    test('10 — retry giữ nguyên transactionDate', () async {
      final businessDate = DateTime(2026, 3, 15);
      final command = CreateTransactionCommand(
        baseCurrencyCode: 'VND',
        type: TransactionType.income,
        categoryId: 'thu_nhap',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 100000,
        transactionDate: businessDate,
      );

      final first = await useCase(command);
      final second = await useCase(command);

      expect(first.transactionDate, businessDate);
      expect(second.transactionDate, businessDate);
    });

    test('11 — retry giữ nguyên toàn bộ payload', () async {
      await db.into(db.fundRows).insert(
        FundRowsCompanion.insert(id: 'fund1', name: 'Quỹ', colorValue: 1),
      );
      // Nạp quỹ trước để expense hợp lệ (cần thu nhập trước để ví vo có tiền).
      await useCase(
        CreateTransactionCommand(
          baseCurrencyCode: 'VND',
          type: TransactionType.income,
          categoryId: 'thu_nhap',
          sourceKind: PoolKind.external,
          destinationKind: PoolKind.memberAvailable,
          destinationRefId: 'vo',
          amountMinor: 100000,
          transactionDate: DateTime(2026, 9, 4),
        ),
      );
      await useCase(
        CreateTransactionCommand(
          baseCurrencyCode: 'VND',
          type: TransactionType.transfer,
          transferKind: TransferKind.fundTopup,
          categoryId: 'nap_quy',
          sourceKind: PoolKind.memberAvailable,
          sourceRefId: 'vo',
          destinationKind: PoolKind.fund,
          destinationRefId: 'fund1',
          amountMinor: 50000,
          transactionDate: DateTime(2026, 9, 4),
        ),
      );

      final command = CreateTransactionCommand(
        baseCurrencyCode: 'VND',
        type: TransactionType.expense,
        categoryId: 'sinh_hoat',
        sourceKind: PoolKind.fund,
        sourceRefId: 'fund1',
        destinationKind: PoolKind.external,
        amountMinor: 30000,
        transactionDate: DateTime(2026, 9, 5),
        note: 'Đi chợ',
      );

      final first = await useCase(command);
      final second = await useCase(command);

      expect(second.categoryId, first.categoryId);
      expect(second.sourceKind, first.sourceKind);
      expect(second.sourceRefId, first.sourceRefId);
      expect(second.destinationKind, first.destinationKind);
      expect(second.amountMinor, first.amountMinor);
      expect(second.note, first.note);
      expect(
        await db.select(db.transactionRows).get(),
        hasLength(3),
        reason: '2 seed (thu nhập + nạp quỹ) + đúng 1 bản ghi cho command (không nhân đôi dù gọi 2 lần)',
      );
    });

    test('12 — 2 command khác nhau (clientTxId khác nhau) → 2 transaction riêng biệt', () async {
      final commandA = CreateTransactionCommand(
        baseCurrencyCode: 'VND',
        type: TransactionType.income,
        categoryId: 'thu_nhap',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 100000,
        transactionDate: DateTime(2026, 9, 1),
      );
      final commandB = CreateTransactionCommand(
        baseCurrencyCode: 'VND',
        type: TransactionType.income,
        categoryId: 'thu_nhap',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 100000,
        transactionDate: DateTime(2026, 9, 1),
      );

      expect(commandA.clientTxId, isNot(commandB.clientTxId));
      await useCase(commandA);
      await useCase(commandB);
      expect(await db.select(db.transactionRows).get(), hasLength(2));
    });

    test('13 — cùng clientTxId nhưng payload khác → ClientTxIdConflictException', () async {
      final first = CreateTransactionCommand(
        baseCurrencyCode: 'VND',
        id: 'tx-a',
        clientTxId: 'shared-client-tx-id',
        type: TransactionType.income,
        categoryId: 'thu_nhap',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 100000,
        transactionDate: DateTime(2026, 9, 1),
      );
      final differentPayload = CreateTransactionCommand(
        baseCurrencyCode: 'VND',
        id: 'tx-b',
        clientTxId: 'shared-client-tx-id',
        type: TransactionType.income,
        categoryId: 'thu_nhap',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 500000, // khác amount — không phải retry hợp lệ.
        transactionDate: DateTime(2026, 9, 1),
      );

      await useCase(first);
      await expectLater(useCase(differentPayload), throwsA(isA<ClientTxIdConflictException>()));
    });
  });

  group('Business date semantics (mục 14/26 Phase 3.5 audit)', () {
    late RecordingTransactionRepository fakeRepo;
    late AddTransactionUseCase useCase;

    setUp(() {
      fakeRepo = RecordingTransactionRepository();
      useCase = AddTransactionUseCase(fakeRepo);
    });

    test('14 — user chọn business date D → Domain Transaction giữ đúng D', () async {
      final businessDate = DateTime(2026, 12, 31);
      final command = CreateTransactionCommand(
        baseCurrencyCode: 'VND',
        type: TransactionType.income,
        categoryId: 'thu_nhap',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 1000,
        transactionDate: businessDate,
      );

      final result = await useCase(command);

      expect(result.transactionDate, businessDate);
    });

    test('15 — transactionDate khác createdAt, đúng semantics (business date vs audit timestamp)', () async {
      final businessDate = DateTime(2020, 1, 1); // cố tình rất xa "hôm nay".
      final command = CreateTransactionCommand(
        baseCurrencyCode: 'VND',
        type: TransactionType.income,
        categoryId: 'thu_nhap',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 1000,
        transactionDate: businessDate,
      );

      final result = await useCase(command);

      expect(result.transactionDate, businessDate);
      expect(
        result.createdAt.isAfter(DateTime(2026, 1, 1)),
        isTrue,
        reason: 'createdAt là audit timestamp lúc chạy test, không phải business date đã chọn',
      );
      expect(result.createdAt, isNot(result.transactionDate));
    });

    test(
      '16 — business date không bị đổi do conversion không cần thiết (kể cả giờ sát nửa đêm)',
      () async {
        // Không có timezone utility nào trong project (xác nhận ở
        // docs/global-readiness-audit.md mục 11/15) — test này xác nhận
        // Application KHÔNG tự thêm bất kỳ .toUtc()/.toLocal()/làm tròn nào:
        // DateTime truyền vào phải ra y hệt (đến từng microsecond) ở đầu ra.
        final nearMidnight = DateTime(2026, 6, 30, 23, 59, 59, 999);
        final command = CreateTransactionCommand(
          baseCurrencyCode: 'VND',
          type: TransactionType.income,
          categoryId: 'thu_nhap',
          sourceKind: PoolKind.external,
          destinationKind: PoolKind.memberAvailable,
          destinationRefId: 'vo',
          amountMinor: 1000,
          transactionDate: nearMidnight,
        );

        final result = await useCase(command);

        expect(result.transactionDate.microsecondsSinceEpoch, nearMidnight.microsecondsSinceEpoch);
        expect(result.transactionDate.day, 30, reason: 'không bị lùi/tiến sang ngày khác');
        expect(result.transactionDate.month, 6);
        expect(result.transactionDate.year, 2026);
      },
    );
  });

  group('Error propagation liên quan Add (mục 26/27/29 — chi tiết đầy đủ ở error_propagation_and_query_use_cases_test.dart)', () {
    test('InsufficientBalanceException propagate nguyên vẹn qua AddTransactionUseCase', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final useCase = AddTransactionUseCase(LocalTransactionRepository(db));

      final command = CreateTransactionCommand(
        baseCurrencyCode: 'VND',
        type: TransactionType.expense,
        categoryId: 'sinh_hoat',
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        amountMinor: 999999999,
        transactionDate: DateTime(2026, 9, 1),
      );

      await expectLater(useCase(command), throwsA(isA<InsufficientBalanceException>()));
    });
  });

  group('Currency snapshot (Phase 4.1 mục 9/13)', () {
    late AppDatabase db;
    late AddTransactionUseCase useCase;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      useCase = AddTransactionUseCase(LocalTransactionRepository(db));
    });

    tearDown(() async => db.close());

    for (final currency in ['VND', 'USD', 'JPY']) {
      test('injected $currency → transaction persist đúng $currency, amountMinor không đổi', () async {
        final command = CreateTransactionCommand(
          baseCurrencyCode: currency,
          type: TransactionType.income,
          categoryId: 'thu_nhap',
          sourceKind: PoolKind.external,
          destinationKind: PoolKind.memberAvailable,
          destinationRefId: 'vo',
          amountMinor: 12345,
          transactionDate: DateTime(2026, 9, 1),
        );

        final result = await useCase(command);

        expect(result.currency, currency);
        expect(
          result.amountMinor,
          12345,
          reason: 'Test 13 — không ×100/÷100/conversion/formatting theo currency',
        );
        final row = await (db.select(
          db.transactionRows,
        )..where((r) => r.id.equals(result.id))).getSingle();
        expect(row.currency, currency);
        expect(row.amountMinor, 12345);
      });
    }

    test('A — same clientTxId + same payload + same currency → idempotent success', () async {
      final command = CreateTransactionCommand(
        baseCurrencyCode: 'USD',
        clientTxId: 'cur-a',
        type: TransactionType.income,
        categoryId: 'thu_nhap',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 5000,
        transactionDate: DateTime(2026, 9, 1),
      );

      final first = await useCase(command);
      final second = await useCase(command); // reuse SAME command — retry hợp lệ.

      expect(second.id, first.id);
      expect(second.currency, 'USD');
      expect(await db.select(db.transactionRows).get(), hasLength(1));
    });

    test(
      'B — same clientTxId + identical everything except currency → ClientTxIdConflictException',
      () async {
        final first = CreateTransactionCommand(
          id: 'tx-cur-b1',
          clientTxId: 'cur-b',
          baseCurrencyCode: 'VND',
          type: TransactionType.income,
          categoryId: 'thu_nhap',
          sourceKind: PoolKind.external,
          destinationKind: PoolKind.memberAvailable,
          destinationRefId: 'vo',
          amountMinor: 100000,
          transactionDate: DateTime(2026, 9, 1),
        );
        final sameExceptCurrency = CreateTransactionCommand(
          id: 'tx-cur-b2',
          clientTxId: 'cur-b',
          baseCurrencyCode: 'USD',
          type: TransactionType.income,
          categoryId: 'thu_nhap',
          sourceKind: PoolKind.external,
          destinationKind: PoolKind.memberAvailable,
          destinationRefId: 'vo',
          amountMinor: 100000,
          transactionDate: DateTime(2026, 9, 1),
        );

        await useCase(first);
        await expectLater(
          useCase(sameExceptCurrency),
          throwsA(isA<ClientTxIdConflictException>()),
        );
        expect(
          await db.select(db.transactionRows).get(),
          hasLength(1),
          reason: 'không tạo bản ghi thứ 2, không âm thầm bỏ qua currency mới',
        );
      },
    );
  });
}
