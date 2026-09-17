import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/application/commands/create_transaction_command_factory.dart';
import 'package:vi_nha_minh/application/currency/currency_context.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';

/// Fake `CurrencyContext` MUTABLE — chỉ dùng để mô phỏng "context đổi giá
/// trị theo thời gian" trong test (Phase 4.1 mục 10/11). Production chỉ
/// dùng `FixedCurrencyContext` (immutable) ở Layer 1.
class _MutableCurrencyContext implements CurrencyContext {
  _MutableCurrencyContext(this.value);
  String value;

  @override
  Future<String> getBaseCurrencyCode() async => value;
}

void main() {
  group('CreateTransactionCommandFactory (mục 4/10/11)', () {
    late _MutableCurrencyContext context;
    late CreateTransactionCommandFactory factory;

    setUp(() {
      context = _MutableCurrencyContext('VND');
      factory = CreateTransactionCommandFactory(context);
    });

    Future<dynamic> createIncome() {
      return factory.create(
        type: TransactionType.income,
        categoryId: 'thu_nhap',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 100000,
        transactionDate: DateTime(2026, 9, 1),
      );
    }

    test('command mới snapshot đúng baseCurrencyCode hiện tại của context', () async {
      final command = await createIncome();
      expect(command.baseCurrencyCode, 'VND');
    });

    test(
      '10 — đổi context SAU KHI command đã tạo không ảnh hưởng command cũ (retry vẫn giữ VND)',
      () async {
        final commandX = await createIncome();
        expect(commandX.baseCurrencyCode, 'VND');

        // Context đổi USD SAU khi commandX đã được snapshot.
        context.value = 'USD';

        // "Retry" nghĩa là dùng LẠI commandX — KHÔNG gọi factory.create() lần
        // nữa. Field vẫn phải là VND, không tự resolve lại USD.
        expect(commandX.baseCurrencyCode, 'VND');
      },
    );

    test(
      '11 — command MỚI tạo sau khi context đổi phải nhận currency mới; command cũ không bị viết lại',
      () async {
        final commandA = await createIncome(); // context = VND lúc này.
        expect(commandA.baseCurrencyCode, 'VND');

        context.value = 'USD';
        final commandB = await createIncome(); // context = USD lúc này.

        expect(commandA.baseCurrencyCode, 'VND', reason: 'A không bị viết lại bởi thay đổi context sau đó');
        expect(commandB.baseCurrencyCode, 'USD', reason: 'B là logical request mới, dùng currency mới');
        expect(commandA.clientTxId, isNot(commandB.clientTxId));
      },
    );
  });
}
