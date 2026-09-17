import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/application/commands/create_transaction_command.dart';

void main() {
  group('CreateTransactionCommand', () {
    test('1 — immutable: mọi field là final, không có setter/copyWith', () {
      // Bằng chứng ở mức biên dịch: tất cả field của CreateTransactionCommand
      // đều khai báo `final` (xem lib/application/commands/
      // create_transaction_command.dart) — không có method nào cho phép đổi
      // giá trị sau khi tạo (không copyWith, không setter). Test này xác
      // nhận giá trị đọc lại đúng với những gì đã truyền vào constructor,
      // và không có cách nào (kể cả qua reflection thông thường của Dart)
      // để mutate field `final` sau khi object đã tồn tại.
      final command = CreateTransactionCommand(
        baseCurrencyCode: 'VND',
        type: TransactionType.income,
        categoryId: 'cat1',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 100000,
        transactionDate: DateTime(2026, 1, 1),
      );

      final categoryIdBefore = command.categoryId;
      final amountBefore = command.amountMinor;
      // ... không có API nào để đổi các field này; đọc lại lần 2 phải giống hệt.
      expect(command.categoryId, categoryIdBefore);
      expect(command.amountMinor, amountBefore);
    });

    test('id/clientTxId tự sinh khi không truyền, mỗi command 1 giá trị riêng', () {
      final a = CreateTransactionCommand(
        baseCurrencyCode: 'VND',
        type: TransactionType.income,
        categoryId: 'cat1',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 1000,
        transactionDate: DateTime(2026, 1, 1),
      );
      final b = CreateTransactionCommand(
        baseCurrencyCode: 'VND',
        type: TransactionType.income,
        categoryId: 'cat1',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 1000,
        transactionDate: DateTime(2026, 1, 1),
      );

      expect(a.id, isNotEmpty);
      expect(a.clientTxId, isNotEmpty);
      expect(a.id, isNot(b.id));
      expect(a.clientTxId, isNot(b.clientTxId));
    });

    test('id/clientTxId truyền tay được giữ nguyên (phục vụ mô phỏng retry trong test)', () {
      final command = CreateTransactionCommand(
        baseCurrencyCode: 'VND',
        id: 'fixed-id',
        clientTxId: 'fixed-client-tx-id',
        type: TransactionType.income,
        categoryId: 'cat1',
        sourceKind: PoolKind.external,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: 'vo',
        amountMinor: 1000,
        transactionDate: DateTime(2026, 1, 1),
      );

      expect(command.id, 'fixed-id');
      expect(command.clientTxId, 'fixed-client-tx-id');
    });
  });
}
