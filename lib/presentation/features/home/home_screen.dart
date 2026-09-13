import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/default_categories.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/category_kind.dart';
import '../../../domain/entities/family_member.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/usecases/compute_member_financials.dart';
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
    final voFinancials = computeMemberFinancials(FamilyMember.vo, transactions);
    final chongFinancials = computeMemberFinancials(FamilyMember.chong, transactions);
    final sorted = [...transactions]
      ..sort((a, b) => b.date.compareTo(a.date));
    final monthLabel = 'Tháng ${DateTime.now().month}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Xin chào,',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Ví Nhà Mình · $monthLabel',
                  style: const TextStyle(
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _MemberCard(financials: voFinancials)),
            const SizedBox(width: 12),
            Expanded(child: _MemberCard(financials: chongFinancials)),
          ],
        ),
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

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.financials});

  final MemberFinancials financials;

  @override
  Widget build(BuildContext context) {
    final isNegative = financials.balance < 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
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
            financials.member.label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Số dư',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          Text(
            Formatters.amount(financials.balance),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: isNegative ? AppColors.expenseAmount : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.incomeTile,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tiết kiệm',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
                Text(
                  Formatters.amount(financials.savingsTotal),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Hiện tại ${Formatters.amount(financials.savingsOnHand)}',
                  style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                ),
                Text(
                  'Ngân hàng ${Formatters.amount(financials.savingsInBank)}',
                  style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                ),
              ],
            ),
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
    final isIncome = category.kind == CategoryKind.income;
    final amountColor = isIncome ? AppColors.accent : AppColors.textPrimary;
    final sign = transaction.amount < 0 ? '' : (isIncome ? '+ ' : '- ');
    final amountText = '$sign${Formatters.amount(transaction.amount)}';

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
                  transaction.note.isEmpty
                      ? transaction.spender.label
                      : '${transaction.note} · ${transaction.spender.label}',
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
