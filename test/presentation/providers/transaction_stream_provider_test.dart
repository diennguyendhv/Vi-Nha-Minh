import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/repositories/transaction_repository.dart';
import 'package:vi_nha_minh/presentation/providers/transaction_providers.dart';

/// Fake `TransactionRepository` với stream ĐIỀU KHIỂN ĐƯỢC — chỉ dùng để
/// test `transactionsStreamProvider` (Phase 5 mục 27), khác
/// `RecordingTransactionRepository` (dùng cho test Application, stream cố
/// định rỗng).
class _ControllableTransactionRepository implements TransactionRepository {
  final _controller = StreamController<List<Transaction>>.broadcast();

  @override
  Stream<List<Transaction>> watchTransactions() => _controller.stream;

  void emit(List<Transaction> list) => _controller.add(list);
  void emitError(Object error) => _controller.addError(error);
  Future<void> dispose() => _controller.close();

  @override
  Future<Transaction> addTransaction(Transaction transaction) =>
      throw UnimplementedError();

  @override
  Future<Transaction?> getTransactionById(String id) =>
      throw UnimplementedError();

  @override
  Future<Transaction?> getTransactionByClientTxId(String clientTxId) =>
      throw UnimplementedError();

  @override
  Future<void> reverseTransaction(String transactionId) =>
      throw UnimplementedError();

  @override
  Future<void> updateTransaction(
    String transactionId, {
    int? amountMinor,
    String? categoryId,
    String? note,
    String? memberRefId,
    DateTime? transactionDate,
    String? statusId,
  }) => throw UnimplementedError();
}

Transaction _tx(String id) {
  return Transaction(
    id: id,
    type: TransactionType.income,
    categoryId: 'thu_nhap',
    sourceKind: PoolKind.external,
    destinationKind: PoolKind.memberAvailable,
    destinationRefId: 'vo',
    amountMinor: 1000,
    transactionDate: DateTime(2026, 9, 1),
    createdAt: DateTime(2026, 9, 1),
    clientTxId: 'client-$id',
  );
}

void main() {
  group('transactionsStreamProvider (Phase 5 mục 9/27) — nguồn qua WatchTransactionsUseCase', () {
    test('16/17/18 — nhận đúng list A rồi cập nhật list B khi Repository emit', () async {
      final fakeRepo = _ControllableTransactionRepository();
      addTearDown(fakeRepo.dispose);
      final container = ProviderContainer(
        overrides: [transactionRepositoryProvider.overrideWithValue(fakeRepo)],
      );
      addTearDown(container.dispose);

      final states = <AsyncValue<List<Transaction>>>[];
      container.listen<AsyncValue<List<Transaction>>>(
        transactionsStreamProvider,
        (previous, next) => states.add(next),
        fireImmediately: true,
      );
      await Future<void>.delayed(Duration.zero);

      fakeRepo.emit([_tx('a')]);
      await Future<void>.delayed(Duration.zero);

      fakeRepo.emit([_tx('a'), _tx('b')]);
      await Future<void>.delayed(Duration.zero);

      final lengths = states.where((s) => s.hasValue).map((s) => s.value!.length).toList();
      expect(lengths, containsAllInOrder([1, 2]));
    });

    test('19 — lỗi từ Repository stream propagate thành AsyncValue.error', () async {
      final fakeRepo = _ControllableTransactionRepository();
      addTearDown(fakeRepo.dispose);
      final container = ProviderContainer(
        overrides: [transactionRepositoryProvider.overrideWithValue(fakeRepo)],
      );
      addTearDown(container.dispose);

      final states = <AsyncValue<List<Transaction>>>[];
      container.listen<AsyncValue<List<Transaction>>>(
        transactionsStreamProvider,
        (previous, next) => states.add(next),
        fireImmediately: true,
      );
      await Future<void>.delayed(Duration.zero);

      fakeRepo.emitError(Exception('lỗi mô phỏng'));
      await Future<void>.delayed(Duration.zero);

      expect(states.any((s) => s.hasError), isTrue);
    });

    test('20 — provider chỉ forward, không copy/mutate/duplicate list đã emit', () async {
      final fakeRepo = _ControllableTransactionRepository();
      addTearDown(fakeRepo.dispose);
      final container = ProviderContainer(
        overrides: [transactionRepositoryProvider.overrideWithValue(fakeRepo)],
      );
      addTearDown(container.dispose);

      final originalList = [_tx('a')];
      final states = <AsyncValue<List<Transaction>>>[];
      container.listen<AsyncValue<List<Transaction>>>(
        transactionsStreamProvider,
        (previous, next) => states.add(next),
        fireImmediately: true,
      );
      await Future<void>.delayed(Duration.zero);

      fakeRepo.emit(originalList);
      await Future<void>.delayed(Duration.zero);

      final received = states.lastWhere((s) => s.hasValue).value;
      expect(
        identical(received, originalList),
        isTrue,
        reason: 'không có logic tính toán/copy nào chen giữa Repository và Presentation',
      );
    });
  });
}
