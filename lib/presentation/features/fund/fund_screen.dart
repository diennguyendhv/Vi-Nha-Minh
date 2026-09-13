import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/default_funds.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/id_generator.dart';
import '../../../domain/entities/fund.dart';
import '../../../domain/entities/fund_entry.dart';
import '../../../domain/usecases/compute_fund_balance.dart';
import '../../providers/fund_providers.dart';

class FundScreen extends ConsumerWidget {
  const FundScreen({super.key, this.fundId = DefaultFunds.anUongId});

  final String fundId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fund = DefaultFunds.byId(fundId);
    final entriesAsync = ref.watch(fundEntriesStreamProvider(fundId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(fund.name)),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Lỗi tải dữ liệu: $err')),
        data: (entries) {
          final sorted = [...entries]..sort((a, b) => b.date.compareTo(a.date));
          final balance = computeFundBalance(entries);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            children: [
              _BalanceCard(fund: fund, balance: balance),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: 'Nạp tiền',
                      icon: Icons.add_circle_outline_rounded,
                      color: AppColors.accent,
                      onTap: () => _showEntryDialog(
                        context,
                        ref,
                        fundId: fundId,
                        kind: FundEntryKind.topUp,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionButton(
                      label: 'Ghi khoản mua',
                      icon: Icons.remove_circle_outline_rounded,
                      color: AppColors.expenseAmount,
                      onTap: () => _showEntryDialog(
                        context,
                        ref,
                        fundId: fundId,
                        kind: FundEntryKind.purchase,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Lịch sử',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (sorted.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Chưa có khoản nào trong quỹ',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              else
                ...sorted.map((e) => _EntryRow(entry: e)),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showEntryDialog(
    BuildContext context,
    WidgetRef ref, {
    required String fundId,
    required FundEntryKind kind,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => _AddEntryDialog(fundId: fundId, kind: kind),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.fund, required this.balance});

  final Fund fund;
  final int balance;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SỐ DƯ QUỸ',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            Formatters.amount(balance),
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: balance < 0
                  ? AppColors.expenseAmount
                  : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final FundEntry entry;

  @override
  Widget build(BuildContext context) {
    final isTopUp = entry.kind == FundEntryKind.topUp;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Icon(
            isTopUp ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
            size: 18,
            color: isTopUp ? AppColors.accent : AppColors.expenseAmount,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.note.isEmpty
                      ? (isTopUp ? 'Nạp quỹ' : 'Mua')
                      : entry.note,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                Text(
                  Formatters.dayMonth(entry.date),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${isTopUp ? '+' : '-'} ${Formatters.amount(entry.amount)}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
              color: isTopUp ? AppColors.accent : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddEntryDialog extends ConsumerStatefulWidget {
  const _AddEntryDialog({required this.fundId, required this.kind});

  final String fundId;
  final FundEntryKind kind;

  @override
  ConsumerState<_AddEntryDialog> createState() => _AddEntryDialogState();
}

class _AddEntryDialogState extends ConsumerState<_AddEntryDialog> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTopUp = widget.kind == FundEntryKind.topUp;
    return AlertDialog(
      title: Text(isTopUp ? 'Nạp tiền vào quỹ' : 'Ghi khoản đã mua'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Số tiền (đ)'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            decoration: InputDecoration(
              labelText: isTopUp ? 'Ghi chú (không bắt buộc)' : 'Đã mua gì',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: () {
            final amount = int.tryParse(_amountController.text.trim()) ?? 0;
            if (amount <= 0) return;
            final entry = FundEntry(
              id: IdGenerator.generate(),
              fundId: widget.fundId,
              kind: widget.kind,
              amount: amount,
              date: DateTime.now(),
              note: _noteController.text.trim(),
            );
            ref.read(fundRepositoryProvider).addEntry(entry);
            Navigator.of(context).pop();
          },
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}
