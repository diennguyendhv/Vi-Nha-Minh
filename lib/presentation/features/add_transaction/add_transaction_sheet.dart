import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/default_categories.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../providers/transaction_providers.dart';

Future<void> showAddTransactionSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const AddTransactionSheet(),
  );
}

class AddTransactionSheet extends ConsumerStatefulWidget {
  const AddTransactionSheet({super.key});

  @override
  ConsumerState<AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends ConsumerState<AddTransactionSheet> {
  TransactionType _type = TransactionType.expense;
  String? _selectedCategoryId;
  String _amountDigits = '';
  String _note = '';

  int get _amount => int.tryParse(_amountDigits.isEmpty ? '0' : _amountDigits) ?? 0;

  void _pressKey(String key) {
    setState(() {
      if (key == '⌫') {
        _amountDigits = _amountDigits.isEmpty
            ? ''
            : _amountDigits.substring(0, _amountDigits.length - 1);
        return;
      }
      final next = (_amountDigits + key).replaceFirst(RegExp(r'^0+(?=\d)'), '');
      if (next.length > 9) return;
      _amountDigits = next;
    });
  }

  void _save() {
    if (_selectedCategoryId == null || _amount <= 0) return;
    final transaction = Transaction(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: _type,
      categoryId: _selectedCategoryId!,
      amount: _amount,
      date: DateTime.now(),
      note: _note.isEmpty ? 'Không ghi chú' : _note,
      spenderName: 'Bạn',
    );
    ref.read(transactionRepositoryProvider).addTransaction(transaction);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        _type == TransactionType.expense ? DefaultCategories.expense : DefaultCategories.income;
    final canSave = _selectedCategoryId != null && _amount > 0;
    final amountColor = _type == TransactionType.income
        ? AppColors.accent
        : AppColors.textPrimary;

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E3DB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 12, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Thêm giao dịch',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.chipBackground,
                        shape: const CircleBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
                  children: [
                    _TypeToggle(
                      type: _type,
                      onChanged: (t) => setState(() {
                        _type = t;
                        _selectedCategoryId = null;
                      }),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        Formatters.amount(_amount),
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          color: amountColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const _SectionLabel('Hạng mục'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: categories
                          .map(
                            (c) => _CategoryChip(
                              category: c,
                              selected: c.id == _selectedCategoryId,
                              onTap: () => setState(() => _selectedCategoryId = c.id),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 18),
                    const _SectionLabel('Ghi chú nhanh'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: DefaultCategories.quickNotes
                          .map(
                            (n) => _NoteChip(
                              label: n,
                              selected: n == _note,
                              onTap: () => setState(() => _note = n == _note ? '' : n),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 14),
                    _Keypad(onKey: _pressKey),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: canSave ? _save : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          disabledBackgroundColor: AppColors.disabledButton,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        child: const Text(
                          'Lưu giao dịch',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: AppColors.textMuted,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _TypeToggle extends StatelessWidget {
  const _TypeToggle({required this.type, required this.onChanged});

  final TransactionType type;
  final ValueChanged<TransactionType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.chipBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ToggleButton(
              label: 'Chi tiêu',
              selected: type == TransactionType.expense,
              selectedBg: AppColors.textPrimary,
              onTap: () => onChanged(TransactionType.expense),
            ),
          ),
          Expanded(
            child: _ToggleButton(
              label: 'Thu nhập',
              selected: type == TransactionType.income,
              selectedBg: AppColors.accent,
              onTap: () => onChanged(TransactionType.income),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.label,
    required this.selected,
    required this.selectedBg,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color selectedBg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? selectedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category, required this.selected, required this.onTap});

  final Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? category.color.withValues(alpha: 0.14) : AppColors.chipBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? category.color : Colors.transparent, width: 1.5),
        ),
        child: Text(
          category.name,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? category.color : const Color(0xFF4B4F49),
          ),
        ),
      ),
    );
  }
}

class _NoteChip extends StatelessWidget {
  const _NoteChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent.withValues(alpha: 0.14) : AppColors.chipBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.accent : Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.accent : const Color(0xFF4B4F49),
          ),
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onKey});

  final ValueChanged<String> onKey;

  static const _keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '000', '0', '⌫'];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.4,
      children: _keys
          .map(
            (k) => Material(
              color: AppColors.keypadTile,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onKey(k),
                child: Center(
                  child: Text(
                    k,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
