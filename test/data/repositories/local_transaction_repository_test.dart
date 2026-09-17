import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/repositories/local_transaction_repository.dart';
import 'package:vi_nha_minh/domain/engine/financial_engine.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart' as domain;
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/entities/transfer_kind.dart';
import 'package:vi_nha_minh/domain/errors/domain_exceptions.dart';

/// Repository tests cho Phase 3 — Repository + Idempotency. Test qua
/// `LocalTransactionRepository` thật (không mock), trên DB in-memory thật,
/// để phủ đúng orchestration Domain ↔ Financial Engine ↔ Drift mà Phase 3
/// yêu cầu — không test lại logic thuần domain (đã có ở
/// `test/domain/financial_engine_test.dart`), chỉ test phần Repository
/// thêm vào: idempotency, atomicity, mapping, query.
void main() {
  late AppDatabase db;
  late LocalTransactionRepository repo;
  var seq = 0;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LocalTransactionRepository(db);
    seq = 0;
    await db.into(db.categoryRows).insert(
      CategoryRowsCompanion.insert(id: 'cat1', name: 'cat1', colorValue: 1, type: 'expense'),
    );
    await db.into(db.fundRows).insert(
      FundRowsCompanion.insert(id: 'fund1', name: 'Quỹ test', colorValue: 1),
    );
  });

  tearDown(() async {
    await db.close();
  });

  String nextId(String prefix) => '$prefix-${seq++}';

  domain.Transaction buildTx({
    String? id,
    TransactionType type = TransactionType.income,
    TransferKind? transferKind,
    String categoryId = 'cat1',
    PoolKind sourceKind = PoolKind.external,
    String? sourceRefId,
    PoolKind destinationKind = PoolKind.memberAvailable,
    String? destinationRefId = 'vo',
    int amountMinor = 100000,
    String? clientTxId,
    String? note,
    String? recoveryOfTxId,
  }) {
    final now = DateTime(2026, 9, 1);
    return domain.Transaction(
      id: id ?? nextId('tx'),
      type: type,
      transferKind: transferKind,
      categoryId: categoryId,
      sourceKind: sourceKind,
      sourceRefId: sourceRefId,
      destinationKind: destinationKind,
      destinationRefId: destinationRefId,
      amountMinor: amountMinor,
      note: note ?? '',
      recoveryOfTxId: recoveryOfTxId,
      transactionDate: now,
      createdAt: now,
      clientTxId: clientTxId ?? nextId('client'),
    );
  }

  group('Create', () {
    test('1 — create income thành công', () async {
      final tx = buildTx(type: TransactionType.income, destinationRefId: 'vo');
      final result = await repo.addTransaction(tx);
      expect(result, tx);
      final rows = await db.select(db.transactionRows).get();
      expect(rows, hasLength(1));
    });

    test('2 — create expense thành công', () async {
      final tx = buildTx(
        type: TransactionType.expense,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.external,
        destinationRefId: null,
      );
      // Phải nạp tiền trước để không âm ví (Invariant 7).
      await repo.addTransaction(
        buildTx(destinationRefId: 'vo', amountMinor: 200000, clientTxId: 'seed-income'),
      );
      final result = await repo.addTransaction(tx);
      expect(result.type, TransactionType.expense);
      expect(await db.select(db.transactionRows).get(), hasLength(2));
    });

    test('3 — create transfer thành công', () async {
      await repo.addTransaction(
        buildTx(destinationRefId: 'vo', amountMinor: 200000, clientTxId: 'seed-income'),
      );
      final tx = buildTx(
        type: TransactionType.transfer,
        transferKind: TransferKind.memberToMember,
        categoryId: 'cat1',
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'vo',
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'chong',
        amountMinor: 50000,
      );
      final result = await repo.addTransaction(tx);
      expect(result.transferKind, TransferKind.memberToMember);
    });

    test('4 — persist và đọc lại transaction → domain object giống nhau', () async {
      final tx = buildTx(
        note: 'ghi chú test',
        clientTxId: 'roundtrip',
        transferKind: null,
      );
      await repo.addTransaction(tx);
      final reloaded = await repo.getTransactionById(tx.id);
      expect(reloaded, isNotNull);
      expect(reloaded!.id, tx.id);
      expect(reloaded.type, tx.type);
      expect(reloaded.categoryId, tx.categoryId);
      expect(reloaded.sourceKind, tx.sourceKind);
      expect(reloaded.sourceRefId, tx.sourceRefId);
      expect(reloaded.destinationKind, tx.destinationKind);
      expect(reloaded.destinationRefId, tx.destinationRefId);
      expect(reloaded.amountMinor, tx.amountMinor);
      expect(reloaded.note, tx.note);
      expect(reloaded.clientTxId, tx.clientTxId);
      expect(reloaded.reversalOfTxId, isNull);
      expect(reloaded.correctsTxId, isNull);
      expect(reloaded.reversedByTxId, isNull);
    });
  });

  group('Idempotency', () {
    test('5 — create cùng clientTxId 2 lần → chỉ có 1 transaction', () async {
      final tx = buildTx(clientTxId: 'dup-1');
      await repo.addTransaction(tx);
      await repo.addTransaction(buildTx(id: nextId('tx'), clientTxId: 'dup-1'));
      expect(await db.select(db.transactionRows).get(), hasLength(1));
    });

    test('6 — retry cùng clientTxId + cùng payload → idempotent success (trả về bản gốc)', () async {
      final first = buildTx(clientTxId: 'dup-2', amountMinor: 77000, note: 'Mua đồ ăn');
      final firstResult = await repo.addTransaction(first);

      // Payload logic giống hệt (kể cả note/transactionDate/statusId — Phase
      // 3.1 audit: đây là payload người dùng nhập trên màn Thêm giao dịch,
      // 1 retry hợp lệ luôn resend đúng y hệt), chỉ id/createdAt khác (đúng
      // thực tế: mỗi lần gọi lại sinh id/createdAt mới) — vẫn idempotent.
      final retry = buildTx(
        id: nextId('tx'),
        clientTxId: 'dup-2',
        amountMinor: 77000,
        note: 'Mua đồ ăn',
      );
      final retryResult = await repo.addTransaction(retry);

      expect(retryResult.id, firstResult.id, reason: 'phải trả về đúng bản ghi gốc, không phải bản retry');
      expect(await db.select(db.transactionRows).get(), hasLength(1));
    });

    test(
      '6b (Phase 3.1) — retry cùng clientTxId + note khác → ClientTxIdConflictException',
      () async {
        await repo.addTransaction(buildTx(clientTxId: 'dup-note', note: 'Mua đồ ăn'));
        expect(
          () => repo.addTransaction(
            buildTx(id: nextId('tx'), clientTxId: 'dup-note', note: 'Mua đồ khác'),
          ),
          throwsA(isA<ClientTxIdConflictException>()),
        );
      },
    );

    test(
      '6c (Phase 3.1) — retry cùng clientTxId + transactionDate khác → ClientTxIdConflictException',
      () async {
        final first = buildTx(clientTxId: 'dup-date');
        await repo.addTransaction(first);
        final differentDate = domain.Transaction(
          id: nextId('tx'),
          type: first.type,
          categoryId: first.categoryId,
          sourceKind: first.sourceKind,
          destinationKind: first.destinationKind,
          destinationRefId: first.destinationRefId,
          amountMinor: first.amountMinor,
          transactionDate: DateTime(2026, 9, 2),
          createdAt: DateTime(2026, 9, 2),
          clientTxId: 'dup-date',
        );
        expect(
          () => repo.addTransaction(differentDate),
          throwsA(isA<ClientTxIdConflictException>()),
        );
      },
    );

    test(
      '6d (Phase 3.1) — retry cùng clientTxId + statusId khác → ClientTxIdConflictException',
      () async {
        await db.into(db.statusRows).insert(
          StatusRowsCompanion.insert(id: 'st-a', categoryId: 'cat1', name: 'Bước A', sortOrder: 0),
        );
        await db.into(db.statusRows).insert(
          StatusRowsCompanion.insert(id: 'st-b', categoryId: 'cat1', name: 'Bước B', sortOrder: 1),
        );
        final first = buildTx(clientTxId: 'dup-status');
        await repo.addTransaction(first.copyWith(statusId: 'st-a'));
        expect(
          () => repo.addTransaction(
            buildTx(
              id: nextId('tx'),
              clientTxId: 'dup-status',
            ).copyWith(statusId: 'st-b'),
          ),
          throwsA(isA<ClientTxIdConflictException>()),
        );
      },
    );

    test('7 — retry cùng clientTxId + amount khác → ClientTxIdConflictException', () async {
      await repo.addTransaction(buildTx(clientTxId: 'dup-3', amountMinor: 100000));
      expect(
        () => repo.addTransaction(
          buildTx(id: nextId('tx'), clientTxId: 'dup-3', amountMinor: 500000),
        ),
        throwsA(isA<ClientTxIdConflictException>()),
      );
      expect(await db.select(db.transactionRows).get(), hasLength(1));
    });

    test('8 — retry cùng clientTxId + source khác → ClientTxIdConflictException', () async {
      await repo.addTransaction(
        buildTx(clientTxId: 'seed-income', destinationRefId: 'vo', amountMinor: 200000),
      );
      await repo.addTransaction(
        buildTx(
          clientTxId: 'dup-4',
          type: TransactionType.expense,
          sourceKind: PoolKind.memberAvailable,
          sourceRefId: 'vo',
          destinationKind: PoolKind.external,
          destinationRefId: null,
        ),
      );
      expect(
        () => repo.addTransaction(
          buildTx(
            id: nextId('tx'),
            clientTxId: 'dup-4',
            type: TransactionType.expense,
            sourceKind: PoolKind.fund,
            sourceRefId: 'fund1',
            destinationKind: PoolKind.external,
            destinationRefId: null,
          ),
        ),
        throwsA(isA<ClientTxIdConflictException>()),
      );
    });

    test('9 — retry cùng clientTxId + destination khác → ClientTxIdConflictException', () async {
      await repo.addTransaction(buildTx(clientTxId: 'dup-5', destinationRefId: 'vo'));
      expect(
        () => repo.addTransaction(
          buildTx(id: nextId('tx'), clientTxId: 'dup-5', destinationRefId: 'chong'),
        ),
        throwsA(isA<ClientTxIdConflictException>()),
      );
    });

    test(
      '10 — 2 lệnh gọi "đồng thời" cùng clientTxId → DB UNIQUE vẫn bảo vệ, '
      'cuối cùng chỉ 1 logical transaction (giới hạn: single-connection SQLite '
      'serialize statement, không mô phỏng race đa tiến trình thật)',
      () async {
        final txA = buildTx(id: 'race-a', clientTxId: 'race-1', amountMinor: 42000);
        final txB = buildTx(id: 'race-b', clientTxId: 'race-1', amountMinor: 42000);

        final results = await Future.wait([
          repo.addTransaction(txA),
          repo.addTransaction(txB),
        ]);

        expect(await db.select(db.transactionRows).get(), hasLength(1));
        expect(
          results[0].id,
          results[1].id,
          reason: 'cả 2 lệnh gọi phải hội tụ về đúng 1 bản ghi',
        );
      },
    );
  });

  group('Atomicity', () {
    test('11 — reversal fail giữa chừng (pool âm) → rollback toàn bộ, không leak reversal row', () async {
      final original = buildTx(
        clientTxId: 'atomic-1',
        type: TransactionType.expense,
        sourceKind: PoolKind.fund,
        sourceRefId: 'fund1',
        destinationKind: PoolKind.external,
        destinationRefId: null,
        amountMinor: 100000,
      );
      // Nạp quỹ trước để expense hợp lệ (cần thu nhập trước để ví vo có tiền).
      await repo.addTransaction(
        buildTx(clientTxId: 'seed-income', destinationRefId: 'vo', amountMinor: 200000),
      );
      await repo.addTransaction(
        buildTx(
          clientTxId: 'seed-fund',
          type: TransactionType.transfer,
          transferKind: TransferKind.fundTopup,
          sourceKind: PoolKind.memberAvailable,
          sourceRefId: 'vo',
          destinationKind: PoolKind.fund,
          destinationRefId: 'fund1',
          amountMinor: 100000,
        ),
      );
      await repo.addTransaction(original);

      // updateTransaction sửa amount → 999999999 sẽ làm fund1 âm (chỉ còn 0
      // sau khi trừ expense gốc) — phải bị chặn TRƯỚC khi ghi bất kỳ dòng
      // nào, không để lại reversal row mồ côi.
      await expectLater(
        LocalTransactionRepository(db).updateTransaction(original.id, amountMinor: 999999999),
        throwsA(isA<InsufficientBalanceException>()),
      );

      final rows = await db.select(db.transactionRows).get();
      expect(
        rows,
        hasLength(3),
        reason: 'chỉ còn đúng 3 row seed ban đầu (thu nhập + nạp quỹ + expense gốc)',
      );
      expect(
        rows.every((r) => r.reversalOfTxId == null && r.correctsTxId == null),
        isTrue,
        reason: 'không có reversal/replacement row nào bị leak',
      );
    });

    test('12 — không có orphan ledger row sau rollback (reverseTransaction trên id không tồn tại)', () async {
      await repo.addTransaction(buildTx(clientTxId: 'atomic-2'));
      await expectLater(
        repo.reverseTransaction('khong-ton-tai'),
        throwsA(isA<TransactionNotFoundException>()),
      );
      // Chỉ 1 row gốc, không có reversal row nào được tạo dở dang.
      expect(await db.select(db.transactionRows).get(), hasLength(1));
    });
  });

  group('Not found (Phase 3.1 hardening — không leak StateError)', () {
    test('reverseTransaction trên id không tồn tại → TransactionNotFoundException, không phải StateError', () async {
      await expectLater(
        repo.reverseTransaction('khong-ton-tai-1'),
        throwsA(isA<TransactionNotFoundException>()),
      );
    });

    test('updateTransaction trên id không tồn tại → TransactionNotFoundException, không phải StateError', () async {
      await expectLater(
        repo.updateTransaction('khong-ton-tai-2', amountMinor: 999),
        throwsA(isA<TransactionNotFoundException>()),
      );
    });

    test('updateTransaction (chỉ đổi field không ảnh hưởng balance) trên id không tồn tại vẫn báo TransactionNotFoundException', () async {
      await expectLater(
        repo.updateTransaction('khong-ton-tai-3', note: 'note mới'),
        throwsA(isA<TransactionNotFoundException>()),
      );
    });

    test('getTransactionById/getTransactionByClientTxId vẫn giữ contract cũ — trả null, KHÔNG ném exception', () async {
      expect(await repo.getTransactionById('khong-ton-tai-4'), isNull);
      expect(await repo.getTransactionByClientTxId('khong-ton-tai-5'), isNull);
    });
  });

  group('Reversal', () {
    test('13/14/15 — reverse thành công, reversal row đúng, original.reversedByTxId đúng', () async {
      final original = buildTx(clientTxId: 'rev-1', amountMinor: 100000, destinationRefId: 'vo');
      await repo.addTransaction(original);

      await repo.reverseTransaction(original.id);

      final rows = await db.select(db.transactionRows).get();
      expect(rows, hasLength(2));
      final originalRow = rows.firstWhere((r) => r.id == original.id);
      final reversalRow = rows.firstWhere((r) => r.id != original.id);

      expect(originalRow.reversedByTxId, reversalRow.id, reason: 'Test 15');
      expect(reversalRow.reversalOfTxId, original.id, reason: 'Test 14');
      expect(reversalRow.sourceKind, 'memberAvailable', reason: 'reversal đảo ngược source/destination');
      expect(reversalRow.destinationKind, 'external');
      expect(reversalRow.amountMinor, 100000);
    });

    test('16 — không reverse cùng transaction lần 2 (AlreadyReversedException)', () async {
      final original = buildTx(clientTxId: 'rev-2');
      await repo.addTransaction(original);
      await repo.reverseTransaction(original.id);

      expect(
        () => repo.reverseTransaction(original.id),
        throwsA(isA<AlreadyReversedException>()),
      );
    });

    test('17 — không tạo duplicate reversal (sau exception ở lần 2, vẫn chỉ 1 reversal row)', () async {
      final original = buildTx(clientTxId: 'rev-3');
      await repo.addTransaction(original);
      await repo.reverseTransaction(original.id);
      try {
        await repo.reverseTransaction(original.id);
      } on AlreadyReversedException {
        // expected
      }
      final rows = await db.select(db.transactionRows).get();
      expect(rows, hasLength(2), reason: '1 original + đúng 1 reversal, không nhân đôi');
    });

    test('18/19 — correction/replacement được persist đúng, correctsTxId đúng', () async {
      final original = buildTx(clientTxId: 'corr-1', amountMinor: 100000, destinationRefId: 'vo');
      await repo.addTransaction(original);

      await repo.updateTransaction(original.id, amountMinor: 250000);

      final rows = await db.select(db.transactionRows).get();
      expect(rows, hasLength(3), reason: 'original + reversal + replacement');
      final replacementRow = rows.firstWhere((r) => r.correctsTxId == original.id);
      expect(replacementRow.amountMinor, 250000, reason: 'Test 19: correctsTxId trỏ đúng bản gốc');
      expect(replacementRow.reversedByTxId, isNull, reason: 'bản thay thế đang là bản mới nhất, còn hiệu lực');
    });

    test('20 — original financial fields KHÔNG bị mutate sau reverse lẫn correction', () async {
      final original = buildTx(clientTxId: 'nomut-1', amountMinor: 100000, destinationRefId: 'vo');
      await repo.addTransaction(original);
      await repo.updateTransaction(original.id, amountMinor: 999000);

      // DB có 3 row sau correction (original + reversal + replacement) —
      // query đúng bản gốc theo id, không dùng getSingle() trên cả bảng.
      final row = await (db.select(
        db.transactionRows,
      )..where((r) => r.id.equals(original.id))).getSingle();
      expect(row.amountMinor, 100000, reason: 'amount gốc không đổi dù đã bị "sửa"');
      expect(row.type, 'income');
      expect(row.sourceKind, 'external');
      expect(row.destinationKind, 'memberAvailable');
      expect(row.destinationRefId, 'vo');
    });
  });

  group('Status', () {
    test('21 — thay đổi status không làm thay đổi financial effect/balance', () async {
      await db.into(db.statusRows).insert(
        StatusRowsCompanion.insert(id: 'st1', categoryId: 'cat1', name: 'Bước 1', sortOrder: 0),
      );
      final tx = buildTx(clientTxId: 'status-1', destinationRefId: 'vo', amountMinor: 100000);
      await repo.addTransaction(tx);

      final before = computeAllPoolBalances(await repo.watchTransactions().first);

      await repo.updateTransaction(tx.id, statusId: 'st1');

      final after = computeAllPoolBalances(await repo.watchTransactions().first);

      expect(after, equals(before));
      final row = await (db.select(
        db.transactionRows,
      )..where((r) => r.id.equals(tx.id))).getSingle();
      expect(row.statusId, 'st1');
      expect(row.reversalOfTxId, isNull, reason: 'đổi status không đi qua reversal ledger');
      expect(await db.select(db.transactionRows).get(), hasLength(1), reason: 'không tạo thêm row nào');
    });
  });

  group('Query', () {
    test('22 — getById trả đúng domain object', () async {
      final tx = buildTx(clientTxId: 'query-1');
      await repo.addTransaction(tx);
      final result = await repo.getTransactionById(tx.id);
      expect(result?.id, tx.id);
    });

    test('23 — getByClientTxId trả đúng transaction', () async {
      final tx = buildTx(clientTxId: 'query-2');
      await repo.addTransaction(tx);
      final result = await repo.getTransactionByClientTxId('query-2');
      expect(result?.id, tx.id);
    });

    test('24 — không tìm thấy → trả về null, không ném exception', () async {
      expect(await repo.getTransactionById('khong-ton-tai'), isNull);
      expect(await repo.getTransactionByClientTxId('khong-ton-tai'), isNull);
    });
  });

  group('Persistence exception boundary (Phase 3.1 mục 4/5/6)', () {
    test('A — categoryId sai (FK violation) → PersistenceConstraintException, KHÔNG raw SqliteException', () async {
      await expectLater(
        repo.addTransaction(buildTx(categoryId: 'khong_ton_tai', clientTxId: 'fk-1')),
        throwsA(
          isA<PersistenceConstraintException>().having(
            (e) => e.kind,
            'kind',
            PersistenceConstraintKind.foreignKey,
          ),
        ),
      );
    });

    test('B — statusId sai (FK violation) → PersistenceConstraintException, KHÔNG raw SqliteException', () async {
      await expectLater(
        repo.addTransaction(
          buildTx(clientTxId: 'fk-2').copyWith(statusId: 'khong_ton_tai'),
        ),
        throwsA(
          isA<PersistenceConstraintException>().having(
            (e) => e.kind,
            'kind',
            PersistenceConstraintKind.foreignKey,
          ),
        ),
      );
    });

    test('C — duplicate clientTxId + cùng payload logic → vẫn idempotent success', () async {
      final tx = buildTx(clientTxId: 'boundary-c', note: 'ghi chú');
      final first = await repo.addTransaction(tx);
      final second = await repo.addTransaction(
        buildTx(id: nextId('tx'), clientTxId: 'boundary-c', note: 'ghi chú'),
      );
      expect(second.id, first.id);
    });

    test('D — duplicate clientTxId + payload khác → vẫn ClientTxIdConflictException (không đổi thành persistence error)', () async {
      await repo.addTransaction(buildTx(clientTxId: 'boundary-d', amountMinor: 1000));
      expect(
        () => repo.addTransaction(
          buildTx(id: nextId('tx'), clientTxId: 'boundary-d', amountMinor: 2000),
        ),
        throwsA(isA<ClientTxIdConflictException>()),
      );
    });

    test('E — lỗi validate domain (InvalidAmountException) KHÔNG bị wrap thành persistence exception', () async {
      expect(
        () => repo.addTransaction(buildTx(clientTxId: 'boundary-e', amountMinor: 0)),
        throwsA(isA<InvalidAmountException>()),
      );
    });

    test('F — InsufficientBalanceException KHÔNG bị wrap thành persistence exception', () async {
      expect(
        () => repo.addTransaction(
          buildTx(
            clientTxId: 'boundary-f',
            type: TransactionType.expense,
            sourceKind: PoolKind.memberAvailable,
            sourceRefId: 'vo',
            destinationKind: PoolKind.external,
            destinationRefId: null,
            amountMinor: 500000,
          ),
        ),
        throwsA(isA<InsufficientBalanceException>()),
      );
    });
  });

  group('Financial invariants qua persistence layer (mục 14)', () {
    test('Member → Fund: member giảm đúng amount, fund tăng đúng amount', () async {
      await repo.addTransaction(
        buildTx(clientTxId: 'seed', destinationRefId: 'vo', amountMinor: 200000),
      );
      await repo.addTransaction(
        buildTx(
          clientTxId: 'topup-1',
          type: TransactionType.transfer,
          transferKind: TransferKind.fundTopup,
          sourceKind: PoolKind.memberAvailable,
          sourceRefId: 'vo',
          destinationKind: PoolKind.fund,
          destinationRefId: 'fund1',
          amountMinor: 80000,
        ),
      );
      final balances = computeAllPoolBalances(await repo.watchTransactions().first);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'vo'), 120000);
      expect(poolBalance(balances, PoolKind.fund, 'fund1'), 80000);
    });

    test('Fund → Expense: fund giảm, member KHÔNG bị trừ thêm lần nữa (chống trừ kép)', () async {
      await repo.addTransaction(
        buildTx(clientTxId: 'seed', destinationRefId: 'vo', amountMinor: 200000),
      );
      await repo.addTransaction(
        buildTx(
          clientTxId: 'topup-2',
          type: TransactionType.transfer,
          transferKind: TransferKind.fundTopup,
          sourceKind: PoolKind.memberAvailable,
          sourceRefId: 'vo',
          destinationKind: PoolKind.fund,
          destinationRefId: 'fund1',
          amountMinor: 80000,
        ),
      );
      final memberBalanceAfterTopup = poolBalance(
        computeAllPoolBalances(await repo.watchTransactions().first),
        PoolKind.memberAvailable,
        'vo',
      );

      await repo.addTransaction(
        buildTx(
          clientTxId: 'fund-expense-1',
          type: TransactionType.expense,
          sourceKind: PoolKind.fund,
          sourceRefId: 'fund1',
          destinationKind: PoolKind.external,
          destinationRefId: null,
          amountMinor: 30000,
        ),
      );

      final balances = computeAllPoolBalances(await repo.watchTransactions().first);
      expect(poolBalance(balances, PoolKind.fund, 'fund1'), 50000);
      expect(
        poolBalance(balances, PoolKind.memberAvailable, 'vo'),
        memberBalanceAfterTopup,
        reason: 'member không bị trừ thêm lần nữa khi Quỹ chi tiêu',
      );
    });

    test('Reversal: original effect + reversal effect = net 0', () async {
      final original = buildTx(clientTxId: 'net-1', destinationRefId: 'vo', amountMinor: 150000);
      await repo.addTransaction(original);
      await repo.reverseTransaction(original.id);

      final balances = computeAllPoolBalances(await repo.watchTransactions().first);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'vo'), 0);
    });

    test('Correction: Original → Reversal → Replacement phản ánh đúng chuỗi ledger', () async {
      final original = buildTx(clientTxId: 'chain-1', destinationRefId: 'vo', amountMinor: 100000);
      await repo.addTransaction(original);
      await repo.updateTransaction(original.id, amountMinor: 300000);

      final balances = computeAllPoolBalances(await repo.watchTransactions().first);
      expect(
        poolBalance(balances, PoolKind.memberAvailable, 'vo'),
        300000,
        reason: 'balance cuối phản ánh đúng giá trị SAU khi sửa, không phải 100000+300000',
      );
    });
  });

  group('Fund Withdraw — Phase 7.1 (qua Repository thật, InsufficientBalance atomic)', () {
    test('Success: Fund giảm đúng amount, member nhận tăng đúng amount, Total Assets không đổi', () async {
      await repo.addTransaction(
        buildTx(clientTxId: 'seed', destinationRefId: 'vo', amountMinor: 6000000),
      );
      await repo.addTransaction(
        buildTx(
          clientTxId: 'topup',
          type: TransactionType.transfer,
          transferKind: TransferKind.fundTopup,
          sourceKind: PoolKind.memberAvailable,
          sourceRefId: 'vo',
          destinationKind: PoolKind.fund,
          destinationRefId: 'fund1',
          amountMinor: 5000000,
        ),
      );
      final beforeWithdraw = computeAllPoolBalances(await repo.watchTransactions().first);
      final totalBefore = beforeWithdraw.values.fold<int>(0, (s, v) => s + v);

      await repo.addTransaction(
        buildTx(
          clientTxId: 'withdraw-1',
          type: TransactionType.transfer,
          transferKind: TransferKind.fundWithdraw,
          sourceKind: PoolKind.fund,
          sourceRefId: 'fund1',
          destinationKind: PoolKind.memberAvailable,
          destinationRefId: 'chong',
          amountMinor: 1000000,
        ),
      );

      final balances = computeAllPoolBalances(await repo.watchTransactions().first);
      expect(poolBalance(balances, PoolKind.fund, 'fund1'), 4000000);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'chong'), 1000000);
      final totalAfter = balances.values.fold<int>(0, (s, v) => s + v);
      expect(
        totalAfter,
        totalBefore,
        reason: 'Total Assets không đổi bởi RIÊNG giao dịch Fund Withdraw — Transfer tự cân bằng nội bộ',
      );
    });

    test('Insufficient balance: rút 600k khi Fund chỉ còn 500k → InsufficientBalanceException, không persist, không đổi balance', () async {
      await repo.addTransaction(
        buildTx(clientTxId: 'seed', destinationRefId: 'vo', amountMinor: 2000000),
      );
      await repo.addTransaction(
        buildTx(
          clientTxId: 'topup',
          type: TransactionType.transfer,
          transferKind: TransferKind.fundTopup,
          sourceKind: PoolKind.memberAvailable,
          sourceRefId: 'vo',
          destinationKind: PoolKind.fund,
          destinationRefId: 'fund1',
          amountMinor: 500000,
        ),
      );

      expect(
        () => repo.addTransaction(
          buildTx(
            clientTxId: 'withdraw-fail',
            type: TransactionType.transfer,
            transferKind: TransferKind.fundWithdraw,
            sourceKind: PoolKind.fund,
            sourceRefId: 'fund1',
            destinationKind: PoolKind.memberAvailable,
            destinationRefId: 'chong',
            amountMinor: 600000,
          ),
        ),
        throwsA(isA<InsufficientBalanceException>()),
      );

      final rows = await db.select(db.transactionRows).get();
      expect(rows, hasLength(2), reason: 'seed + topup only — no orphan withdraw/reversal row');
      final balances = computeAllPoolBalances(await repo.watchTransactions().first);
      expect(poolBalance(balances, PoolKind.fund, 'fund1'), 500000, reason: 'Fund balance không đổi');
      expect(
        poolBalance(balances, PoolKind.memberAvailable, 'chong'),
        0,
        reason: 'Member balance không đổi',
      );
    });

    test('Reversal: original FUND_WITHDRAW + reversal triệt tiêu về 0 cho cả fund lẫn member', () async {
      await repo.addTransaction(
        buildTx(clientTxId: 'seed', destinationRefId: 'vo', amountMinor: 6000000),
      );
      await repo.addTransaction(
        buildTx(
          clientTxId: 'topup',
          type: TransactionType.transfer,
          transferKind: TransferKind.fundTopup,
          sourceKind: PoolKind.memberAvailable,
          sourceRefId: 'vo',
          destinationKind: PoolKind.fund,
          destinationRefId: 'fund1',
          amountMinor: 5000000,
        ),
      );
      final withdraw = buildTx(
        clientTxId: 'withdraw-rev',
        type: TransactionType.transfer,
        transferKind: TransferKind.fundWithdraw,
        sourceKind: PoolKind.fund,
        sourceRefId: 'fund1',
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'chong',
        amountMinor: 1000000,
      );
      await repo.addTransaction(withdraw);
      await repo.reverseTransaction(withdraw.id);

      final balances = computeAllPoolBalances(await repo.watchTransactions().first);
      expect(poolBalance(balances, PoolKind.fund, 'fund1'), 5000000, reason: 'quay lại đúng balance trước khi rút');
      expect(poolBalance(balances, PoolKind.memberAvailable, 'chong'), 0);
    });
  });

  group('Phase 8.6 — Linked refund/recovery, qua Repository thật', () {
    Future<domain.Transaction> seedExpense({int amountMinor = 2000000}) async {
      await repo.addTransaction(
        buildTx(clientTxId: 'seed-income', destinationRefId: 'chong', amountMinor: amountMinor + 5000000),
      );
      final expense = buildTx(
        clientTxId: 'seed-expense',
        type: TransactionType.expense,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'chong',
        destinationKind: PoolKind.external,
        destinationRefId: null,
        amountMinor: amountMinor,
      );
      await repo.addTransaction(expense);
      return expense;
    }

    domain.Transaction recoveryTx({
      required String recoveryOfTxId,
      int amountMinor = 450000,
      String? clientTxId,
      String destinationRefId = 'chong',
    }) {
      return buildTx(
        type: TransactionType.income,
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: destinationRefId,
        amountMinor: amountMinor,
        recoveryOfTxId: recoveryOfTxId,
        clientTxId: clientTxId,
      );
    }

    test('1 — recovery relation persist đúng: đọc lại từ DB có recoveryOfTxId khớp', () async {
      final expense = await seedExpense();
      final recovery = recoveryTx(recoveryOfTxId: expense.id);
      await repo.addTransaction(recovery);

      final stored = await repo.getTransactionById(recovery.id);
      expect(stored, isNotNull);
      expect(stored!.recoveryOfTxId, expense.id);
    });

    test('3/4 — 1 original → nhiều recovery, mỗi cái persist độc lập', () async {
      final expense = await seedExpense(amountMinor: 10000000);
      await repo.addTransaction(recoveryTx(recoveryOfTxId: expense.id, amountMinor: 2800000, clientTxId: 'r1'));
      await repo.addTransaction(recoveryTx(recoveryOfTxId: expense.id, amountMinor: 300000, clientTxId: 'r2'));
      await repo.addTransaction(recoveryTx(recoveryOfTxId: expense.id, amountMinor: 100000, clientTxId: 'r3'));

      final all = await repo.watchTransactions().first;
      final recoveries = all.where((t) => t.recoveryOfTxId == expense.id).toList();
      expect(recoveries, hasLength(3));
    });

    test('5/6 — Available/Total Assets: expense -10tr, 3 recovery cộng lại +3.2tr', () async {
      final expense = await seedExpense(amountMinor: 10000000);
      await repo.addTransaction(recoveryTx(recoveryOfTxId: expense.id, amountMinor: 2800000, clientTxId: 'r1'));
      await repo.addTransaction(recoveryTx(recoveryOfTxId: expense.id, amountMinor: 300000, clientTxId: 'r2'));
      await repo.addTransaction(recoveryTx(recoveryOfTxId: expense.id, amountMinor: 100000, clientTxId: 'r3'));

      final balances = computeAllPoolBalances(await repo.watchTransactions().first);
      // seed 5tr + (-10tr expense) + 3.2tr recovery = -1.8tr
      expect(poolBalance(balances, PoolKind.memberAvailable, 'chong'), 5000000 + 3200000);
    });

    test('8 — Historical Expense KHÔNG bị mutate bởi recovery', () async {
      final expense = await seedExpense(amountMinor: 2000000);
      await repo.addTransaction(recoveryTx(recoveryOfTxId: expense.id, amountMinor: 450000));

      final storedExpense = await repo.getTransactionById(expense.id);
      expect(storedExpense!.amountMinor, 2000000, reason: 'append-only — amount gốc không đổi');
    });

    test('13 — self-link bị reject, không persist', () async {
      final selfLinked = buildTx(
        id: 'self-linked-id',
        type: TransactionType.income,
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'chong',
        amountMinor: 100000,
        recoveryOfTxId: 'self-linked-id',
      );
      expect(
        () => repo.addTransaction(selfLinked),
        throwsA(isA<InvalidRecoveryTargetException>().having((e) => e.reason, 'reason', InvalidRecoveryReason.selfLink)),
      );
      expect(await repo.getTransactionById('self-linked-id'), isNull);
    });

    test('14 — target không tồn tại → InvalidRecoveryTargetException(targetNotFound), không persist', () async {
      expect(
        () => repo.addTransaction(recoveryTx(recoveryOfTxId: 'khong-ton-tai')),
        throwsA(
          isA<InvalidRecoveryTargetException>().having((e) => e.reason, 'reason', InvalidRecoveryReason.targetNotFound),
        ),
      );
    });

    test('14 — target KHÔNG phải EXPENSE (vd income) → InvalidRecoveryTargetException(targetNotExpense)', () async {
      final income = buildTx(clientTxId: 'income-target', destinationRefId: 'vo', amountMinor: 100000);
      await repo.addTransaction(income);
      expect(
        () => repo.addTransaction(recoveryTx(recoveryOfTxId: income.id)),
        throwsA(
          isA<InvalidRecoveryTargetException>().having((e) => e.reason, 'reason', InvalidRecoveryReason.targetNotExpense),
        ),
      );
    });

    test('target đã reversed → InvalidRecoveryTargetException(targetReversed)', () async {
      final expense = await seedExpense();
      await repo.reverseTransaction(expense.id);
      expect(
        () => repo.addTransaction(recoveryTx(recoveryOfTxId: expense.id)),
        throwsA(
          isA<InvalidRecoveryTargetException>().having((e) => e.reason, 'reason', InvalidRecoveryReason.targetReversed),
        ),
      );
    });

    test(
      '15 — recovery chain (recovery trỏ vào recovery khác) bị reject qua pipeline thật '
      '— chặn bởi targetNotExpense (recovery thật luôn type=income nên không bao giờ '
      'lọt qua rule A để chạm tới rule "no chain" — xem test riêng ở financial_engine_test.dart '
      'cho rule "no chain" độc lập)',
      () async {
      final expense = await seedExpense();
      final firstRecovery = recoveryTx(recoveryOfTxId: expense.id, clientTxId: 'first-recovery');
      await repo.addTransaction(firstRecovery);

      expect(
        () => repo.addTransaction(recoveryTx(recoveryOfTxId: firstRecovery.id, clientTxId: 'chained-recovery')),
        throwsA(
          isA<InvalidRecoveryTargetException>().having((e) => e.reason, 'reason', InvalidRecoveryReason.targetNotExpense),
        ),
      );
    });

    test('11 — reversed recovery: reverse xong, hiệu ứng available triệt tiêu hoàn toàn', () async {
      final expense = await seedExpense(amountMinor: 1000000);
      final recovery = recoveryTx(recoveryOfTxId: expense.id, amountMinor: 400000);
      await repo.addTransaction(recovery);
      await repo.reverseTransaction(recovery.id);

      final balances = computeAllPoolBalances(await repo.watchTransactions().first);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'chong'), 5000000);
    });

    test('12 — corrected recovery: sửa amount vẫn giữ đúng relationship, balance phản ánh giá trị mới', () async {
      final expense = await seedExpense(amountMinor: 2000000);
      final recovery = recoveryTx(recoveryOfTxId: expense.id, amountMinor: 450000);
      await repo.addTransaction(recovery);
      await repo.updateTransaction(recovery.id, amountMinor: 400000);

      final all = await repo.watchTransactions().first;
      final visibleRecovery = all.where((t) => t.recoveryOfTxId == expense.id && isVisible(t)).toList();
      expect(visibleRecovery, hasLength(1));
      expect(visibleRecovery.single.amountMinor, 400000);

      final balances = computeAllPoolBalances(all);
      expect(poolBalance(balances, PoolKind.memberAvailable, 'chong'), 5000000 + 400000);
    });

    test('16 — idempotent retry: cùng clientTxId + cùng recoveryOfTxId → không tạo bản ghi thứ 2', () async {
      final expense = await seedExpense();
      final recovery = recoveryTx(recoveryOfTxId: expense.id, clientTxId: 'retry-recovery');
      final first = await repo.addTransaction(recovery);
      final second = await repo.addTransaction(recovery);
      expect(second.id, first.id);

      final all = await repo.watchTransactions().first;
      expect(all.where((t) => t.clientTxId == 'retry-recovery'), hasLength(1));
    });

    test('17 — cùng clientTxId nhưng khác recoveryOfTxId → ClientTxIdConflictException', () async {
      final expenseA = await seedExpense(amountMinor: 1000000);
      final expenseB = buildTx(
        clientTxId: 'expense-b',
        type: TransactionType.expense,
        sourceKind: PoolKind.memberAvailable,
        sourceRefId: 'chong',
        destinationKind: PoolKind.external,
        amountMinor: 500000,
      );
      await repo.addTransaction(expenseB);

      final recoveryToA = recoveryTx(recoveryOfTxId: expenseA.id, clientTxId: 'same-client-tx-id');
      await repo.addTransaction(recoveryToA);

      final recoveryToB = recoveryTx(recoveryOfTxId: expenseB.id, clientTxId: 'same-client-tx-id');
      expect(() => repo.addTransaction(recoveryToB), throwsA(isA<ClientTxIdConflictException>()));
    });
  });
}
