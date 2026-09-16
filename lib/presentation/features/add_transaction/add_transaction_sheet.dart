import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/default_categories.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/id_generator.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/family_member.dart';
import '../../../domain/entities/fund.dart';
import '../../../domain/entities/pool_kind.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../../domain/entities/transfer_kind.dart';
import '../../../domain/errors/domain_exceptions.dart';
import '../../../domain/usecases/compute_pool_balance.dart';
import '../../providers/category_providers.dart';
import '../../providers/fund_providers.dart';
import '../../providers/transaction_providers.dart';

/// Màn "Thêm giao dịch" (`docs/design.html` màn 09) — nơi tạo giao dịch DUY
/// NHẤT trong app: Nạp quỹ/Ghi khoản mua (màn Quỹ) và Rút về ví/Gửi ngân
/// hàng (màn Tiết kiệm) đều mở lại sheet này, chỉ khác panel/giá trị điền
/// sẵn. Sửa giao dịch đã ghi (chỉ amount + status) dùng
/// `transaction_detail_screen.dart` riêng, không dùng sheet này.
Future<void> showAddTransactionSheet(
  BuildContext context, {
  EntryType initialType = EntryType.chi,
  TransferSubKind? initialTransferSubKind,
  String? initialFundId,
  SavingsAction? initialSavingsAction,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => AddTransactionSheet(
      initialType: initialType,
      initialTransferSubKind: initialTransferSubKind,
      initialFundId: initialFundId,
      initialSavingsAction: initialSavingsAction,
    ),
  );
}

enum EntryType { thu, chi, chuyen }

enum TransferSubKind { member, fund, savings }

enum SavingsAction { topup, withdraw, toBank }

class AddTransactionSheet extends ConsumerStatefulWidget {
  const AddTransactionSheet({
    super.key,
    this.initialType = EntryType.chi,
    this.initialTransferSubKind,
    this.initialFundId,
    this.initialSavingsAction,
  });

  final EntryType initialType;
  final TransferSubKind? initialTransferSubKind;
  final String? initialFundId;
  final SavingsAction? initialSavingsAction;

  @override
  ConsumerState<AddTransactionSheet> createState() =>
      _AddTransactionSheetState();
}

class _AddTransactionSheetState extends ConsumerState<AddTransactionSheet> {
  late EntryType _entryType = widget.initialType;
  String? _categoryId;
  FamilyMember _member = FamilyMember.vo;
  String? _statusId;
  late String? _sourceFundId =
      widget.initialTransferSubKind == null ? widget.initialFundId : null;

  late TransferSubKind _transferSubKind =
      widget.initialTransferSubKind ?? TransferSubKind.member;
  FamilyMember _transferFrom = FamilyMember.vo;
  FamilyMember _transferTo = FamilyMember.chong;
  late String? _transferFundId =
      widget.initialTransferSubKind == TransferSubKind.fund
      ? widget.initialFundId
      : null;
  late SavingsAction _savingsAction =
      widget.initialSavingsAction ?? SavingsAction.topup;

  String _amountDigits = '';
  String _note = '';

  int get _amount =>
      int.tryParse(_amountDigits.isEmpty ? '0' : _amountDigits) ?? 0;

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

  Category? _findCategory(List<Category> categories, String? id) {
    if (id == null) return null;
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  void _pickCategory(Category category) {
    setState(() {
      _categoryId = category.id;
      _statusId = category.hasStatus ? category.statuses.first.id : null;
    });
  }

  Future<void> _save(List<Category> categories) async {
    final tx = _buildTransaction(categories);
    if (tx == null) return;
    try {
      await ref.read(transactionRepositoryProvider).addTransaction(tx);
      if (mounted) Navigator.of(context).pop();
    } on InsufficientBalanceException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Số dư không đủ để ghi giao dịch này.')),
        );
      }
    }
  }

  Transaction? _buildTransaction(List<Category> categories) {
    if (_amount <= 0) return null;
    final now = DateTime.now();
    final id = IdGenerator.generate();
    final clientTxId = IdGenerator.generate();

    switch (_entryType) {
      case EntryType.thu:
        final category = _findCategory(categories, _categoryId);
        if (category == null) return null;
        return Transaction(
          id: id,
          type: TransactionType.income,
          categoryId: category.id,
          sourceKind: PoolKind.external,
          destinationKind: PoolKind.memberAvailable,
          destinationRefId: _member.name,
          amountMinor: _amount,
          note: _note,
          statusId: category.hasStatus ? _statusId : null,
          transactionDate: now,
          createdAt: now,
          clientTxId: clientTxId,
        );

      case EntryType.chi:
        final category = _findCategory(categories, _categoryId);
        if (category == null) return null;
        final fundId = _sourceFundId;
        return Transaction(
          id: id,
          type: TransactionType.expense,
          categoryId: category.id,
          sourceKind: fundId == null ? PoolKind.memberAvailable : PoolKind.fund,
          sourceRefId: fundId ?? _member.name,
          destinationKind: PoolKind.external,
          amountMinor: _amount,
          note: _note,
          statusId: category.hasStatus ? _statusId : null,
          transactionDate: now,
          createdAt: now,
          clientTxId: clientTxId,
        );

      case EntryType.chuyen:
        switch (_transferSubKind) {
          case TransferSubKind.member:
            if (_transferFrom == _transferTo) return null;
            return Transaction(
              id: id,
              type: TransactionType.transfer,
              transferKind: TransferKind.memberToMember,
              categoryId: DefaultCategories.chuyenTienThanhVien.id,
              sourceKind: PoolKind.memberAvailable,
              sourceRefId: _transferFrom.name,
              destinationKind: PoolKind.memberAvailable,
              destinationRefId: _transferTo.name,
              amountMinor: _amount,
              note: _note,
              transactionDate: now,
              createdAt: now,
              clientTxId: clientTxId,
            );
          case TransferSubKind.fund:
            final fundId = _transferFundId;
            if (fundId == null) return null;
            return Transaction(
              id: id,
              type: TransactionType.transfer,
              transferKind: TransferKind.fundTopup,
              categoryId: DefaultCategories.napQuy.id,
              sourceKind: PoolKind.memberAvailable,
              sourceRefId: _member.name,
              destinationKind: PoolKind.fund,
              destinationRefId: fundId,
              amountMinor: _amount,
              note: _note,
              transactionDate: now,
              createdAt: now,
              clientTxId: clientTxId,
            );
          case TransferSubKind.savings:
            final member = _member;
            final (
              PoolKind sourceKind,
              PoolKind destinationKind,
              TransferKind transferKind,
            ) = switch (_savingsAction) {
              SavingsAction.topup => (
                PoolKind.memberAvailable,
                PoolKind.memberSavingsCash,
                TransferKind.savingsTopup,
              ),
              SavingsAction.withdraw => (
                PoolKind.memberSavingsCash,
                PoolKind.memberAvailable,
                TransferKind.savingsWithdraw,
              ),
              SavingsAction.toBank => (
                PoolKind.memberSavingsCash,
                PoolKind.memberSavingsBank,
                TransferKind.savingsToBank,
              ),
            };
            return Transaction(
              id: id,
              type: TransactionType.transfer,
              transferKind: transferKind,
              categoryId: DefaultCategories.tietKiem.id,
              sourceKind: sourceKind,
              sourceRefId: member.name,
              destinationKind: destinationKind,
              destinationRefId: member.name,
              amountMinor: _amount,
              note: _note,
              transactionDate: now,
              createdAt: now,
              clientTxId: clientTxId,
            );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesStreamProvider).valueOrNull ?? [];
    final funds = ref.watch(fundsStreamProvider).valueOrNull ?? [];
    final transactions = ref.watch(transactionsStreamProvider).valueOrNull ?? [];

    final activeCategories = categories.where((c) => c.isActive).toList();
    final incomeCategories = activeCategories
        .where((c) => c.type == TransactionType.income)
        .toList();
    final expenseCategories = activeCategories
        .where((c) => c.type == TransactionType.expense)
        .toList();
    final activeFunds = funds.where((f) => f.isActive).toList();

    final canSave = _buildTransaction(categories) != null;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
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
                    const _SectionLabel('Loại giao dịch'),
                    const SizedBox(height: 8),
                    _TypeSegmented(
                      value: _entryType,
                      onChanged: (t) => setState(() => _entryType = t),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        Formatters.amount(_amount),
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ..._buildPanel(
                      incomeCategories: incomeCategories,
                      expenseCategories: expenseCategories,
                      funds: activeFunds,
                      transactions: transactions,
                    ),
                    const SizedBox(height: 16),
                    const _SectionLabel('Ghi chú'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: DefaultCategories.quickNotes
                          .map(
                            (n) => _NoteChip(
                              label: n,
                              selected: n == _note,
                              onTap: () =>
                                  setState(() => _note = n == _note ? '' : n),
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
                        onPressed: canSave ? () => _save(categories) : null,
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

  List<Widget> _buildPanel({
    required List<Category> incomeCategories,
    required List<Category> expenseCategories,
    required List<Fund> funds,
    required List<Transaction> transactions,
  }) {
    switch (_entryType) {
      case EntryType.thu:
        final category = _findCategory(incomeCategories, _categoryId);
        return [
          const _SectionLabel('Hạng mục'),
          const SizedBox(height: 8),
          _CategoryChipGrid(
            categories: incomeCategories,
            selectedId: _categoryId,
            onTap: _pickCategory,
          ),
          if (category != null && category.hasStatus) ...[
            const SizedBox(height: 16),
            const _SectionLabel('Trạng thái'),
            const SizedBox(height: 8),
            _StatusChips(
              category: category,
              selectedId: _statusId,
              onTap: (s) => setState(() => _statusId = s),
            ),
          ],
          const SizedBox(height: 16),
          const _SectionLabel('Người nhận'),
          const SizedBox(height: 8),
          _MemberToggle(
            member: _member,
            onChanged: (m) => setState(() => _member = m),
          ),
        ];

      case EntryType.chi:
        final category = _findCategory(expenseCategories, _categoryId);
        return [
          const _SectionLabel('Hạng mục'),
          const SizedBox(height: 8),
          _CategoryChipGrid(
            categories: expenseCategories,
            selectedId: _categoryId,
            onTap: _pickCategory,
          ),
          if (category != null && category.hasStatus) ...[
            const SizedBox(height: 16),
            const _SectionLabel('Trạng thái'),
            const SizedBox(height: 8),
            _StatusChips(
              category: category,
              selectedId: _statusId,
              onTap: (s) => setState(() => _statusId = s),
            ),
          ],
          const SizedBox(height: 16),
          const _SectionLabel('Người chi'),
          const SizedBox(height: 8),
          _MemberToggle(
            member: _member,
            onChanged: (m) => setState(() {
              _member = m;
              _sourceFundId = null;
            }),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('Nguồn tiền'),
          const SizedBox(height: 8),
          _FundPickRow(
            walletLabel: 'Ví của ${_member.label}',
            funds: funds,
            selectedFundId: _sourceFundId,
            amount: _amount,
            transactions: transactions,
            onSelect: (fundId) => setState(() => _sourceFundId = fundId),
          ),
        ];

      case EntryType.chuyen:
        return [
          const _SectionLabel('Loại chuyển'),
          const SizedBox(height: 8),
          _TransferSubSegmented(
            value: _transferSubKind,
            onChanged: (v) => setState(() => _transferSubKind = v),
          ),
          const SizedBox(height: 16),
          ..._buildTransferSubPanel(funds: funds, transactions: transactions),
        ];
    }
  }

  List<Widget> _buildTransferSubPanel({
    required List<Fund> funds,
    required List<Transaction> transactions,
  }) {
    switch (_transferSubKind) {
      case TransferSubKind.member:
        return [
          const _SectionLabel('Người gửi'),
          const SizedBox(height: 8),
          _MemberToggle(
            member: _transferFrom,
            onChanged: (m) => setState(() => _transferFrom = m),
          ),
          const SizedBox(height: 12),
          const _SectionLabel('Người nhận'),
          const SizedBox(height: 8),
          _MemberToggle(
            member: _transferTo,
            onChanged: (m) => setState(() => _transferTo = m),
          ),
        ];
      case TransferSubKind.fund:
        return [
          const _SectionLabel('Người nạp'),
          const SizedBox(height: 8),
          _MemberToggle(
            member: _member,
            onChanged: (m) => setState(() => _member = m),
          ),
          const SizedBox(height: 12),
          const _SectionLabel('Quỹ đích'),
          const SizedBox(height: 8),
          _FundPickRow(
            walletLabel: null,
            funds: funds,
            selectedFundId: _transferFundId,
            amount: 0,
            transactions: transactions,
            onSelect: (fundId) => setState(() => _transferFundId = fundId),
          ),
        ];
      case TransferSubKind.savings:
        return [
          const _SectionLabel('Của ai'),
          const SizedBox(height: 8),
          _MemberToggle(
            member: _member,
            onChanged: (m) => setState(() => _member = m),
          ),
          const SizedBox(height: 12),
          const _SectionLabel('Hành động'),
          const SizedBox(height: 8),
          _SavingsActionSegmented(
            value: _savingsAction,
            onChanged: (v) => setState(() => _savingsAction = v),
          ),
        ];
    }
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

class _TypeSegmented extends StatelessWidget {
  const _TypeSegmented({required this.value, required this.onChanged});

  final EntryType value;
  final ValueChanged<EntryType> onChanged;

  static const _labels = {
    EntryType.thu: 'Thu',
    EntryType.chi: 'Chi',
    EntryType.chuyen: 'Chuyển',
  };

  @override
  Widget build(BuildContext context) {
    return _Segmented<EntryType>(
      value: value,
      options: EntryType.values,
      labelOf: (t) => _labels[t]!,
      onChanged: onChanged,
    );
  }
}

class _TransferSubSegmented extends StatelessWidget {
  const _TransferSubSegmented({required this.value, required this.onChanged});

  final TransferSubKind value;
  final ValueChanged<TransferSubKind> onChanged;

  static const _labels = {
    TransferSubKind.member: 'Thành viên khác',
    TransferSubKind.fund: 'Nạp quỹ',
    TransferSubKind.savings: 'Tiết kiệm',
  };

  @override
  Widget build(BuildContext context) {
    return _Segmented<TransferSubKind>(
      value: value,
      options: TransferSubKind.values,
      labelOf: (t) => _labels[t]!,
      onChanged: onChanged,
    );
  }
}

class _SavingsActionSegmented extends StatelessWidget {
  const _SavingsActionSegmented({required this.value, required this.onChanged});

  final SavingsAction value;
  final ValueChanged<SavingsAction> onChanged;

  static const _labels = {
    SavingsAction.topup: 'Nạp',
    SavingsAction.withdraw: 'Rút về ví',
    SavingsAction.toBank: 'Gửi NH',
  };

  @override
  Widget build(BuildContext context) {
    return _Segmented<SavingsAction>(
      value: value,
      options: SavingsAction.values,
      labelOf: (t) => _labels[t]!,
      onChanged: onChanged,
    );
  }
}

class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    super.key,
  });

  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.chipBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: options.map((o) {
          final selected = o == value;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(o),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? AppColors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Text(
                  labelOf(o),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _MemberToggle extends StatelessWidget {
  const _MemberToggle({required this.member, required this.onChanged});

  final FamilyMember member;
  final ValueChanged<FamilyMember> onChanged;

  @override
  Widget build(BuildContext context) {
    return _Segmented<FamilyMember>(
      value: member,
      options: FamilyMember.values,
      labelOf: (m) => m.label,
      onChanged: onChanged,
    );
  }
}

class _CategoryChipGrid extends StatelessWidget {
  const _CategoryChipGrid({
    required this.categories,
    required this.selectedId,
    required this.onTap,
  });

  final List<Category> categories;
  final String? selectedId;
  final ValueChanged<Category> onTap;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return const Text(
        'Chưa có danh mục nào — tạo ở tab Danh mục trước.',
        style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: categories
          .map(
            (c) => _CategoryChip(
              category: c,
              selected: c.id == selectedId,
              onTap: () => onTap(c),
            ),
          )
          .toList(),
    );
  }
}

class _StatusChips extends StatelessWidget {
  const _StatusChips({
    required this.category,
    required this.selectedId,
    required this.onTap,
  });

  final Category category;
  final String? selectedId;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: category.statuses
          .map(
            (s) => _ChoiceChip(
              label: s.name,
              selected: s.id == selectedId,
              accent: category.color,
              onTap: () => onTap(s.id),
            ),
          )
          .toList(),
    );
  }
}

class _FundPickRow extends StatelessWidget {
  const _FundPickRow({
    required this.walletLabel,
    required this.funds,
    required this.selectedFundId,
    required this.amount,
    required this.transactions,
    required this.onSelect,
  });

  /// null khi không có lựa chọn "Ví" (vd panel Nạp quỹ — luôn chọn 1 quỹ).
  final String? walletLabel;
  final List<Fund> funds;
  final String? selectedFundId;
  final int amount;
  final List<Transaction> transactions;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (walletLabel != null)
          _FundPickChip(
            label: walletLabel!,
            selected: selectedFundId == null,
            balanceLabel: null,
            disabled: false,
            onTap: () => onSelect(null),
          ),
        for (final f in funds)
          Builder(
            builder: (context) {
              final balance = computeFundBalance(f.id, transactions);
              final insufficient = amount > 0 && amount > balance;
              return _FundPickChip(
                label: f.name,
                selected: selectedFundId == f.id,
                balanceLabel: 'còn ${Formatters.amount(balance)}',
                disabled: insufficient,
                onTap: insufficient ? null : () => onSelect(f.id),
              );
            },
          ),
      ],
    );
  }
}

class _FundPickChip extends StatelessWidget {
  const _FundPickChip({
    required this.label,
    required this.selected,
    required this.balanceLabel,
    required this.disabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final String? balanceLabel;
  final bool disabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = disabled
        ? AppColors.textMuted
        : (selected ? AppColors.accent : const Color(0xFF4B4F49));
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.12)
              : AppColors.chipBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color),
            ),
            if (balanceLabel != null)
              Text(
                balanceLabel!,
                style: TextStyle(fontSize: 11, color: color),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.14)
              : AppColors.chipBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? accent : Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? accent : const Color(0xFF4B4F49),
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

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
          color: selected
              ? category.color.withValues(alpha: 0.14)
              : AppColors.chipBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? category.color : Colors.transparent,
            width: 1.5,
          ),
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
  const _NoteChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

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
          color: selected
              ? AppColors.accent.withValues(alpha: 0.14)
              : AppColors.chipBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
          ),
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

  static const _keys = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '000',
    '0',
    '⌫',
  ];

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
