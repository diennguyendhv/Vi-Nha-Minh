import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/application/commands/create_transaction_command_factory.dart';
import 'package:vi_nha_minh/application/currency/currency_context.dart';
import 'package:vi_nha_minh/application/use_cases/add_transaction_use_case.dart';
import 'package:vi_nha_minh/application/use_cases/change_transaction_status_use_case.dart';
import 'package:vi_nha_minh/application/use_cases/get_transaction_by_id_use_case.dart';
import 'package:vi_nha_minh/application/use_cases/reverse_transaction_use_case.dart';
import 'package:vi_nha_minh/application/use_cases/update_transaction_use_case.dart';
import 'package:vi_nha_minh/application/use_cases/watch_transactions_use_case.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/repositories/transaction_repository.dart';
import 'package:vi_nha_minh/presentation/providers/currency_providers.dart';
import 'package:vi_nha_minh/presentation/providers/database_provider.dart';
import 'package:vi_nha_minh/presentation/providers/transaction_providers.dart';

import '../../application/support/recording_transaction_repository.dart';

/// Fake `CurrencyContext` cố định (khác `FixedCurrencyContext` production —
/// đây chỉ là test double để override provider).
class _TestCurrencyContext implements CurrencyContext {
  const _TestCurrencyContext(this.value);
  final String value;

  @override
  Future<String> getBaseCurrencyCode() async => value;
}

void main() {
  group('Provider graph — resolve (Phase 5 mục 25)', () {
    test('1 — appDatabaseProvider resolve được (LazyDatabase, chưa mở kết nối thật)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(appDatabaseProvider), isNotNull);
    });

    test('2/3 — transactionRepositoryProvider resolve thành TransactionRepository, cache theo container', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final repo = container.read(transactionRepositoryProvider);
      expect(repo, isA<TransactionRepository>());
      expect(
        identical(container.read(transactionRepositoryProvider), repo),
        isTrue,
        reason: 'không tạo Repository/DB mới mỗi lần đọc lại trong cùng container',
      );
    });

    test('4 — currencyContextProvider resolve được', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(currencyContextProvider), isA<CurrencyContext>());
    });

    test('5 — createTransactionCommandFactoryProvider dùng CurrencyContext', () async {
      final container = ProviderContainer(
        overrides: [
          currencyContextProvider.overrideWithValue(const _TestCurrencyContext('USD')),
        ],
      );
      addTearDown(container.dispose);
      final factory = container.read(createTransactionCommandFactoryProvider);
      expect(factory, isA<CreateTransactionCommandFactory>());
      final command = await factory.create(
        type: TransactionType.income,
        categoryId: 'thu_nhap',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 1000,
        transactionDate: DateTime(2026, 9, 1),
      );
      expect(command.baseCurrencyCode, 'USD');
    });

    test('6 — addTransactionUseCaseProvider resolve được', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(addTransactionUseCaseProvider), isA<AddTransactionUseCase>());
    });

    test('7 — updateTransactionUseCaseProvider resolve được', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(updateTransactionUseCaseProvider), isA<UpdateTransactionUseCase>());
    });

    test('8 — reverseTransactionUseCaseProvider resolve được', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(reverseTransactionUseCaseProvider), isA<ReverseTransactionUseCase>());
    });

    test('9 — changeTransactionStatusUseCaseProvider resolve được', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(changeTransactionStatusUseCaseProvider),
        isA<ChangeTransactionStatusUseCase>(),
      );
    });

    test('10 — getTransactionByIdUseCaseProvider/watchTransactionsUseCaseProvider resolve được', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(getTransactionByIdUseCaseProvider), isA<GetTransactionByIdUseCase>());
      expect(container.read(watchTransactionsUseCaseProvider), isA<WatchTransactionsUseCase>());
    });
  });

  group('Provider graph — override (Phase 5 mục 26)', () {
    test('11/12 — override TransactionRepository bằng fake, provider dùng đúng fake đã override', () {
      final fakeRepo = RecordingTransactionRepository();
      final container = ProviderContainer(
        overrides: [transactionRepositoryProvider.overrideWithValue(fakeRepo)],
      );
      addTearDown(container.dispose);

      expect(container.read(transactionRepositoryProvider), same(fakeRepo));
      expect(() => container.read(addTransactionUseCaseProvider), returnsNormally);
    });

    test('13/14 — override CurrencyContext, CommandFactory lấy đúng currency từ context đã override', () async {
      final container = ProviderContainer(
        overrides: [
          currencyContextProvider.overrideWithValue(const _TestCurrencyContext('EUR')),
        ],
      );
      addTearDown(container.dispose);

      final factory = container.read(createTransactionCommandFactoryProvider);
      final command = await factory.create(
        type: TransactionType.income,
        categoryId: 'thu_nhap',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 1000,
        transactionDate: DateTime(2026, 9, 1),
      );
      expect(command.baseCurrencyCode, 'EUR');
    });

    test(
      '15 — override TransactionRepository trực tiếp không đòi hỏi production AppDatabase phải sẵn sàng',
      () {
        // Không watch appDatabaseProvider ở test này — nếu addTransactionUseCaseProvider
        // vô tình phụ thuộc production DB dù đã override Repository, việc đọc
        // provider này sẽ throw. Vì phụ thuộc đúng qua transactionRepositoryProvider
        // (đã override), không có production dependency nào bị khởi tạo ngoài ý muốn.
        final fakeRepo = RecordingTransactionRepository();
        final container = ProviderContainer(
          overrides: [transactionRepositoryProvider.overrideWithValue(fakeRepo)],
        );
        addTearDown(container.dispose);
        expect(() => container.read(addTransactionUseCaseProvider), returnsNormally);
      },
    );
  });
}
