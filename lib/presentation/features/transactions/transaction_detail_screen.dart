import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/family_member.dart';
import '../../../domain/entities/pool_kind.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../../domain/errors/domain_exceptions.dart';
import '../../providers/category_providers.dart';
import '../../providers/transaction_providers.dart';

/// Màn "Chi tiết giao dịch" (`docs/design.html` màn 11) — sửa được toàn bộ:
/// hạng mục (trong cùng loại Thu/Chi/Chuyển gốc), số tiền, ghi chú, người
/// tiêu, ngày tháng, trạng thái. `amountMinor`/người tiêu ảnh hưởng balance
/// nên tự động đi qua reversal ledger (mục 21) — các field còn lại update
/// thẳng. Không đổi được LOẠI giao dịch (Thu/Chi/Chuyển) — nhập sai loại
/// thì xoá rồi ghi lại từ màn Thêm giao dịch.
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
  final _noteController = TextEditingController();
  bool _initialized = false;

  late String _categoryId;
  late DateTime _transactionDate;
  String? _statusId;
  FamilyMember? _member;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Transaction? _findTransaction(List<Transaction> all) {
    for (final t in all) {
      if (t.id == widget.transactionId) return t;
    }
    return null;
  }

  /// Chỉ khác null khi giao dịch có đúng 1 "người tiêu" rõ ràng có thể sửa
  /// — INCOME (người nhận) hoặc EXPENSE nguồn ví (người chi). TRANSFER và
  /// EXPENSE nguồn Quỹ không có field này để sửa.
  FamilyMember? _currentMember(Transaction t) {
    final refId = t.type == TransactionType.income
        ? t.destinationRefId
        : (t.type == TransactionType.expense && t.sourceKind == PoolKind.memberAvailable
              ? t.sourceRefId
              : null);
    if (refId == null) return null;
    for (final m in FamilyMember.values) {
      if (m.name == refId) return m;
    }
    return null;
  }

  void _initFrom(Transaction t) {
    _amountController.text = t.amountMinor.toString();
    _noteController.text = t.note;
    _categoryId = t.categoryId;
    _transactionDate = t.transactionDate;
    _statusId = t.statusId;
    _member = _currentMember(t);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _transactionDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _transactionDate = picked);
  }

  Future<void> _save(Transaction current) async {
    final newAmount = int.tryParse(_amountController.text.replaceAll('.', ''));
    if (newAmount == null || newAmount <= 0) return;
    try {
      await ref.read(transactionRepositoryProvider).updateTransaction(
        current.id,
        amountMinor: newAmount,
        categoryId: _categoryId,
        note: _noteController.text.trim(),
        memberRefId: _member?.name,
        transactionDate: _transactionDate,
        statusId: _statusId,
      );
      if (mounted) Navigator.of(context).pop();
    } on InsufficientBalanceException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Số dư không đủ để lưu thay đổi này.')),
        );
      }
    }
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

    if (!_initialized) {
      _initFrom(transaction);
      _initialized = true;
    }

    Category? selectedCategory;
    for (final c in categories) {
      if (c.id == _categoryId) selectedCategory = c;
    }
    final sameTypeCategories = categories
        .where((c) => c.type == transaction.type && (c.isActive || c.id == _categoryId))
        .toList();
    final canEditCategory = transaction.type != TransactionType.transfer;
    final canEditMember = _currentMember(transaction) != null;

    return Scaffold(
      appBar: AppBar(
        title: Text('Chi tiết giao dịch · ${Formatters.dayMonth(transaction.transactionDate)}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'HẠNG MỤC',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          if (canEditCategory)
            DropdownButtonFormField<String>(
              value: sameTypeCategories.any((c) => c.id == _categoryId) ? _categoryId : null,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
              items: sameTypeCategories
                  .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: (id) {
                if (id == null) return;
                setState(() {
                  _categoryId = id;
                  Category? newCategory;
                  for (final c in sameTypeCategories) {
                    if (c.id == id) newCategory = c;
                  }
                  // Đổi hạng mục có thể đổi luôn bộ statuses hợp lệ.
                  if (newCategory != null &&
                      (!newCategory.hasStatus ||
                          newCategory.statuses.every((s) => s.id != _statusId))) {
                    _statusId = newCategory.hasStatus ? newCategory.statuses.first.id : null;
                  }
                });
              },
            )
          else
            _ReadOnlyRow(label: 'Danh mục hệ thống, không sửa được', value: selectedCategory?.name ?? '—'),
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
          const Text(
            'GHI CHÚ',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textMuted),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          if (canEditMember) ...[
            const SizedBox(height: 16),
            const Text(
              'NGƯỜI TIÊU',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            SegmentedButton<FamilyMember>(
              segments: FamilyMember.values
                  .map((m) => ButtonSegment(value: m, label: Text(m.label)))
                  .toList(),
              selected: {_member ?? FamilyMember.vo},
              onSelectionChanged: (s) => setState(() => _member = s.first),
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            'NGÀY',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textMuted),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_rounded, size: 16),
            label: Text(
              '${_transactionDate.day.toString().padLeft(2, '0')}/'
              '${_transactionDate.month.toString().padLeft(2, '0')}/${_transactionDate.year}',
            ),
          ),
          if (selectedCategory != null && selectedCategory.hasStatus) ...[
            const SizedBox(height: 20),
            const Text(
              'TRẠNG THÁI',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _statusId ?? selectedCategory.statuses.first.id,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
              items: selectedCategory.statuses
                  .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                  .toList(),
              onChanged: (id) {
                if (id != null) setState(() => _statusId = id);
              },
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
            onPressed: () => _save(transaction),
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
