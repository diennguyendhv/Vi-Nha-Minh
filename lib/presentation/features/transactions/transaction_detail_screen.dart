import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/transaction.dart';
import '../../providers/category_providers.dart';
import '../../providers/transaction_providers.dart';

/// Màn "Chi tiết & đổi trạng thái" (`docs/design.html` màn 11) — quyết định
/// đã chốt ở `docs/financial-core-v2.md` mục 21: chỉ cho sửa `amountMinor`
/// và `statusId` tại chỗ. Hạng mục/người ghi cố định từ lúc tạo — nhập sai
/// thì xoá giao dịch rồi ghi lại từ màn Thêm giao dịch.
class TransactionDetailScreen extends ConsumerStatefulWidget {
  const TransactionDetailScreen({super.key, required this.transactionId});

  final String transactionId;

  @override
  ConsumerState<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState
    extends ConsumerState<TransactionDetailScreen> {
  final _amountController = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Transaction? _findTransaction(List<Transaction> all) {
    for (final t in all) {
      if (t.id == widget.transactionId) return t;
    }
    return null;
  }

  Future<void> _saveAmount(Transaction current) async {
    final newAmount = int.tryParse(_amountController.text.replaceAll('.', ''));
    if (newAmount == null || newAmount <= 0) return;
    if (newAmount == current.amountMinor) return;
    await ref
        .read(transactionRepositoryProvider)
        .correctTransactionAmount(current.id, newAmount);
  }

  Future<void> _changeStatus(Transaction current, String statusId) async {
    await ref
        .read(transactionRepositoryProvider)
        .updateTransactionStatus(current.id, statusId);
  }

  Future<void> _delete(Transaction current) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá giao dịch này?'),
        content: const Text(
          'Giao dịch sẽ được hoàn tác (số dư trở lại đúng trước khi ghi) — vẫn lưu trong lịch sử để đối chiếu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huỷ'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(transactionRepositoryProvider).reverseTransaction(current.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(transactionsStreamProvider).valueOrNull ?? [];
    final categories = ref.watch(categoriesStreamProvider).valueOrNull ?? [];
    final transaction = _findTransaction(transactions);

    if (transaction == null) {
      return const Scaffold(body: Center(child: Text('Giao dịch không tồn tại.')));
    }
    if (transaction.reversedByTxId != null) {
      return const Scaffold(
        body: Center(child: Text('Giao dịch này đã bị xoá.')),
      );
    }

    Category? category;
    for (final c in categories) {
      if (c.id == transaction.categoryId) category = c;
    }

    if (!_initialized) {
      _amountController.text = transaction.amountMinor.toString();
      _initialized = true;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Chi tiết giao dịch · ${Formatters.dayMonth(transaction.transactionDate)}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _ReadOnlyRow(label: 'Hạng mục (không sửa được)', value: category?.name ?? '—'),
          const SizedBox(height: 16),
          const Text(
            'SỐ TIỀN',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textMuted),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            decoration: const InputDecoration(border: OutlineInputBorder(), suffixText: 'đ'),
          ),
          const SizedBox(height: 16),
          _ReadOnlyRow(label: 'Ghi chú', value: transaction.note.isEmpty ? '—' : transaction.note),
          if (category != null && category.hasStatus) ...[
            const SizedBox(height: 20),
            const Text(
              'TRẠNG THÁI (bấm để đổi)',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: category.statuses.map((s) {
                final selected = s.id == transaction.statusId ||
                    (transaction.statusId == null && s.id == category!.statuses.first.id);
                return ChoiceChip(
                  label: Text(s.name),
                  selected: selected,
                  onSelected: (_) => _changeStatus(transaction, s.id),
                );
              }).toList(),
            ),
            if (transaction.statusUpdatedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Cập nhật lần cuối: ${Formatters.dayMonth(transaction.statusUpdatedAt!)}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => _saveAmount(transaction),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Lưu thay đổi'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => _delete(transaction),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.expenseAmount,
              side: const BorderSide(color: AppColors.expenseAmount),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Xoá giao dịch'),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
