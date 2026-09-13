import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/default_categories.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../../domain/usecases/compute_financial_summary.dart';
import '../../providers/transaction_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(transactionsStreamProvider);

    return transactionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Lỗi tải dữ liệu: $err')),
      data: (transactions) => _HomeContent(transactions: transactions),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({required this.transactions});

  final List<Transaction> transactions;

  @override
  Widget build(BuildContext context) {
    final summary = computeFinancialSummary(transactions);
    final sorted = [...transactions]
      ..sort((a, b) => b.date.compareTo(a.date));
    final monthLabel = 'Tháng ${DateTime.now().month}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Xin chào,',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Ví Nhà Mình',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
            const _AvatarBadge(),
          ],
        ),
        const SizedBox(height: 20),
        _BalanceCard(summary: summary, monthLabel: monthLabel),
        const SizedBox(height: 26),
        const Text(
          'Giao dịch gần đây',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        _TransactionList(sorted: sorted),
      ],
    );
  }
}

class _AvatarBadge extends StatelessWidget {
  const _AvatarBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
      ),
      child: const Text(
        'GĐ',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.summary, required this.monthLabel});

  final FinancialSummary summary;
  final String monthLabel;

  @override
  Widget build(BuildContext context) {
    final rate = summary.savingsRatePercent.clamp(0, 100);
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
          Text(
            'Số dư $monthLabel'.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            Formatters.amount(summary.balance),
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  background: AppColors.incomeTile,
                  label: 'Thu nhập',
                  value: Formatters.amount(summary.totalIncome),
                  icon: Icons.arrow_outward_rounded,
                  iconColor: AppColors.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  background: AppColors.expenseTile,
                  label: 'Chi tiêu',
                  value: Formatters.amount(summary.totalExpense),
                  icon: Icons.arrow_downward_rounded,
                  iconColor: AppColors.expenseAmount,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: rate / 100,
              minHeight: 8,
              backgroundColor: AppColors.progressTrack,
              valueColor: const AlwaysStoppedAnimation(AppColors.accent),
            ),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              children: [
                const TextSpan(text: 'Tiết kiệm được '),
                TextSpan(
                  text: '${summary.savingsRatePercent}%',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const TextSpan(text: ' thu nhập tháng này'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.background,
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  final Color background;
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: iconColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _TransactionList extends StatelessWidget {
  const _TransactionList({required this.sorted});

  final List<Transaction> sorted;

  @override
  Widget build(BuildContext context) {
    String? lastDateLabel;
    final children = <Widget>[];
    for (final t in sorted) {
      final dateLabel = Formatters.dayMonth(t.date);
      if (dateLabel != lastDateLabel) {
        lastDateLabel = dateLabel;
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 4),
            child: Text(
              dateLabel,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
                letterSpacing: 0.5,
              ),
            ),
          ),
        );
      }
      children.add(_TransactionRow(transaction: t));
    }
    return Column(children: children);
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final category = DefaultCategories.byId(transaction.categoryId);
    final isIncome = transaction.type == TransactionType.income;
    final amountColor = isIncome ? AppColors.accent : AppColors.textPrimary;
    final amountText =
        '${isIncome ? '+' : '-'} ${Formatters.amount(transaction.amount)}';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: category.color, shape: BoxShape.circle),
            child: Text(
              category.initial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.name,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                Text(
                  '${transaction.note} · ${transaction.spenderName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            amountText,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
              color: amountColor,
            ),
          ),
        ],
      ),
    );
  }
}
