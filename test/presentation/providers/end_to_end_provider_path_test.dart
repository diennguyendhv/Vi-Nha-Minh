import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/application/currency/currency_context.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/presentation/providers/currency_providers.dart';
import 'package:vi_nha_minh/presentation/providers/transaction_providers.dart';

import '../../application/support/recording_transaction_repository.dart';

/// Fake `CurrencyContext` MUTABLE — chỉ dùng để mô phỏng context đổi giá trị
/// giữa các lần gọi trong test retry (Phase 5 mục 29), giống hệt cách Phase
/// 4.1 đã test `CreateTransactionCommandFactory`.
class _MutableTestCurrencyContext implements CurrencyContext {
  _MutableTestCurrencyContext(this.value);
  String value;

  @override
  Future<String> getBaseCurrencyCode() async => value;
}

void main() {
  group('End-to-end provider path (Phase 5 mục 28) — CurrencyContext → CommandFactory → AddTransactionUseCase → Repository', () {
    test('21-25 — command tạo qua factory, currency snapshot đúng, use case nhận đúng, repository nhận đúng transaction', () async {
      final fakeRepo = RecordingTransactionRepository();
      final container = ProviderContainer(
        overrides: [
          transactionRepositoryProvider.overrideWithValue(fakeRepo),
          currencyContextProvider.overrideWithValue(_MutableTestCurrencyContext('USD')),
        ],
      );
      addTearDown(container.dispose);

      final factory = container.read(createTransactionCommandFactoryProvider);
      final businessDate = DateTime(2026, 5, 20);
      final command = await factory.create(
        type: TransactionType.income,
        categoryId: 'thu_nhap',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 250000,
        transactionDate: businessDate,
        note: 'Lương',
      );
      expect(command.baseCurrencyCode, 'USD', reason: 'Test 22 — currency snapshot đúng ngay lúc tạo command');

      final addUseCase = container.read(addTransactionUseCaseProvider);
      final result = await addUseCase(command); // Test 23

      expect(fakeRepo.lastAdded, isNotNull, reason: 'Test 24 — Repository nhận đúng transaction');
      expect(fakeRepo.lastAdded!.id, command.id);
      expect(result.amountMinor, 250000, reason: 'Test 25 — amountMinor giữ nguyên');
      expect(result.transactionDate, businessDate, reason: 'Test 25 — date giữ nguyên');
      expect(result.clientTxId, command.clientTxId, reason: 'Test 25 — clientTxId giữ nguyên');
      expect(result.currency, 'USD', reason: 'Test 25 — currency giữ nguyên');
    });
  });

  group('Retry qua provider graph (Phase 5 mục 29) — không phá invariant Phase 4.1', () {
    test('26-30 — đổi CurrencyContext sau khi command đã tạo qua provider, retry vẫn giữ currency cũ', () async {
      final fakeRepo = RecordingTransactionRepository();
      final mutableCurrency = _MutableTestCurrencyContext('VND');
      final container = ProviderContainer(
        overrides: [
          transactionRepositoryProvider.overrideWithValue(fakeRepo),
          currencyContextProvider.overrideWithValue(mutableCurrency),
        ],
      );
      addTearDown(container.dispose);

      final factory = container.read(createTransactionCommandFactoryProvider);
      final command = await factory.create(
        // Test 26 — tạo command X qua provider/factory, context = VND lúc này.
        type: TransactionType.income,
        categoryId: 'thu_nhap',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 100000,
        transactionDate: DateTime(2026, 9, 1),
      );
      expect(command.baseCurrencyCode, 'VND');

      final addUseCase = container.read(addTransactionUseCaseProvider);
      final first = await addUseCase(command); // Test 27 — gọi Add use case với X.

      mutableCurrency.value = 'USD'; // Test 28 — đổi fake CurrencyContext.

      final retryResult = await addUseCase(command); // Test 29 — retry cùng X.

      expect(command.baseCurrencyCode, 'VND', reason: 'Test 30 — currency của X không đổi');
      expect(retryResult.id, first.id, reason: 'idempotent — vẫn cùng 1 transaction gốc');
      expect(retryResult.currency, 'VND', reason: 'retry không vô tình đổi sang USD');
    });
  });
}
