import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/family_member.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../../domain/usecases/compute_member_financials.dart';
import '../../providers/category_providers.dart';
import '../../providers/transaction_providers.dart';
import '../settings/settings_screen.dart';
import '../transactions/transaction_detail_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(transactionsStreamProvider);
    final categoriesAsync = ref.watch(categoriesStreamProvider);

    if (transactionsAsync.isLoading || categoriesAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = transactionsAsync.error ?? categoriesAsync.error;
    if (error != null) {
      return Center(child: Text('Lỗi tải dữ liệu: $error'));
    }

    return _HomeContent(
      transactions: transactionsAsync.value ?? const [],
      categories: categoriesAsync.value ?? const [],
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({required this.transactions, required this.categories});

  final List<Transaction> transactions;
  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    final voFinancials = computeMemberFinancials(FamilyMember.vo, transactions);
    final chongFinancials = computeMemberFinancials(
      FamilyMember.chong,
      transactions,
    );
    final categoryById = {for (final c in categories) c.id: c};
    final visible = transactions.where(isVisible).toList()
      ..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
    final monthLabel = 'Tháng ${DateTime.now().month}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              ),
              child: const _AvatarBadge(),
            ),
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
        _TransactionList(sorted: visible, categoryById: categoryById),
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
          const Text(
            'Số dư còn lại',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          Text(
            Formatters.amount(financials.balance),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: isNegative
                  ? AppColors.expenseAmount
                  : AppColors.textPrimary,
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
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  Formatters.amount(financials.savingsTotal),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Xem theo từng loại tài sản ở Cài đặt › Tiết kiệm',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
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
  const _TransactionList({required this.sorted, required this.categoryById});

  final List<Transaction> sorted;
  final Map<String, Category> categoryById;

  @override
  Widget build(BuildContext context) {
    if (sorted.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text(
          'Chưa có giao dịch nào — bấm nút + để ghi khoản đầu tiên.',
          style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
        ),
      );
    }
    String? lastDateLabel;
    final children = <Widget>[];
    for (final t in sorted.take(10)) {
      final dateLabel = Formatters.dayMonth(t.transactionDate);
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
      children.add(
        _TransactionRow(transaction: t, category: categoryById[t.categoryId]),
      );
    }
    return Column(children: children);
  }
}

String? _memberLabelForRefId(String? refId) {
  if (refId == null) return null;
  for (final m in FamilyMember.values) {
    if (m.name == refId) return m.label;
  }
  return null;
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.transaction, required this.category});

  final Transaction transaction;
  final Category? category;

  @override
  Widget build(BuildContext context) {
    final color = category?.color ?? AppColors.textMuted;
    final name = category?.name ?? 'Đã xoá danh mục';
    final initial = category == null || category!.name.isEmpty
        ? '?'
        : category!.name.substring(0, 1).toUpperCase();
    final isIncome = transaction.type == TransactionType.income;
    final isTransfer = transaction.type == TransactionType.transfer;
    final amountColor = isTransfer
        ? AppColors.textSecondary
        : (isIncome ? AppColors.accent : AppColors.textPrimary);
    final sign = isTransfer ? '⇄ ' : (isIncome ? '+ ' : '- ');
    final amountText = '$sign${Formatters.amount(transaction.amountMinor)}';
    final participant =
        _memberLabelForRefId(transaction.sourceRefId) ??
        _memberLabelForRefId(transaction.destinationRefId) ??
        '';
    final subtitle = transaction.note.isEmpty
        ? participant
        : (participant.isEmpty
              ? transaction.note
              : '${transaction.note} · $participant');

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TransactionDetailScreen(transactionId: transaction.id),
        ),
      ),
      child: Container(
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
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Text(
              initial,
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
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
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
      ),
    );
  }
}
