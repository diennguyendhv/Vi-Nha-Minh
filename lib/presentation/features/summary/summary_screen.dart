import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/family_member.dart';
import '../../../domain/entities/pool_kind.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../../domain/usecases/compute_expense_breakdown.dart';
import '../../../domain/usecases/compute_pool_balance.dart';
import '../../../domain/usecases/compute_status_breakdown.dart';
import '../../../domain/usecases/compute_three_totals.dart';
import '../../providers/category_providers.dart';
import '../../providers/transaction_providers.dart';

/// Màn "Tổng hợp" (`docs/design.html` màn 12-13) — 3 tổng tách biệt
/// (Financial Core V2, thay công thức "Tổng thu = Tổng chi + Số tiền còn
/// lại" đã bị audit sai), tab theo từng thành viên với "Số dư còn lại"
/// cộng dồn không reset tháng, và card trạng thái tự sinh theo danh mục có
/// `statsEnabled = true`.
class SummaryScreen extends ConsumerStatefulWidget {
  const SummaryScreen({super.key});

  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen> {
  FamilyMember _member = FamilyMember.vo;

  @override
  Widget build(BuildContext context) {
    final transactionsAsync = ref.watch(transactionsStreamProvider);
    final categoriesAsync = ref.watch(categoriesStreamProvider);

    if (transactionsAsync.isLoading || categoriesAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = transactionsAsync.error ?? categoriesAsync.error;
    if (error != null) return Center(child: Text('Lỗi tải dữ liệu: $error'));

    final transactions = transactionsAsync.value ?? const [];
    final categories = categoriesAsync.value ?? const [];
    final categoryById = {for (final c in categories) c.id: c};

    final now = DateTime.now();
    final totals = computeThreeTotals(transactions, categories, month: now);
    final availableBalance = computeMemberAvailableBalance(_member, transactions);

    final memberExpenses = transactions
        .where(
          (t) =>
              isVisible(t) &&
              t.type == TransactionType.expense &&
              t.sourceKind == PoolKind.memberAvailable &&
              t.sourceRefId == _member.name &&
              t.transactionDate.year == now.year &&
              t.transactionDate.month == now.month,
        )
        .toList();
    final breakdown = computeExpenseBreakdown(memberExpenses);
    final totalMemberExpense = breakdown.fold<int>(0, (s, c) => s + c.total);

    final statsCategories = categories.where((c) => c.statsEnabled).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        const Text(
          'Tổng hợp',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.2),
        ),
        const SizedBox(height: 14),
        _MemberSegmented(value: _member, onChanged: (m) => setState(() => _member = m)),
        const SizedBox(height: 16),
        _BalanceHeadline(member: _member, balance: availableBalance),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _StatStrip(label: 'Tổng thu', value: totals.totalIncome)),
            const SizedBox(width: 8),
            Expanded(child: _StatStrip(label: 'Tổng chi', value: totals.totalExpense)),
            const SizedBox(width: 8),
            Expanded(child: _StatStrip(label: 'Chuyển khoản', value: totals.totalTransfer)),
          ],
        ),
        const SizedBox(height: 22),
        Text(
          'Chi tiêu của ${_member.label} tháng ${now.month}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        _Donut(
          breakdown: breakdown,
          totalExpense: totalMemberExpense,
          categoryById: categoryById,
        ),
        const SizedBox(height: 12),
        if (breakdown.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Chưa có khoản chi nào tháng này',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          )
        else
          ...breakdown.map(
            (item) => _LegendRow(
              item: item,
              totalExpense: totalMemberExpense,
              category: categoryById[item.categoryId],
            ),
          ),
        for (final category in statsCategories) ...[
          const SizedBox(height: 16),
          _StatusCard(
            category: category,
            breakdown: computeStatusBreakdown(transactions, category),
          ),
        ],
      ],
    );
  }
}

class _MemberSegmented extends StatelessWidget {
  const _MemberSegmented({required this.value, required this.onChanged});

  final FamilyMember value;
  final ValueChanged<FamilyMember> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<FamilyMember>(
      segments: FamilyMember.values
          .map((m) => ButtonSegment(value: m, label: Text(m.label)))
          .toList(),
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class _BalanceHeadline extends StatelessWidget {
  const _BalanceHeadline({required this.member, required this.balance});

  final FamilyMember member;
  final int balance;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Số dư còn lại của ${member.label} (cộng dồn, không reset tháng)',
            style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            Formatters.amount(balance),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _StatStrip extends StatelessWidget {
  const _StatStrip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text(
            Formatters.amount(value),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _Donut extends StatelessWidget {
  const _Donut({
    required this.breakdown,
    required this.totalExpense,
    required this.categoryById,
  });

  final List<CategoryTotal> breakdown;
  final int totalExpense;
  final Map<String, Category> categoryById;

  @override
  Widget build(BuildContext context) {
    final sections = breakdown.isEmpty
        ? [
            PieChartSectionData(
              value: 1,
              color: AppColors.progressTrack,
              showTitle: false,
              radius: 24,
            ),
          ]
        : breakdown.map((item) {
            final color = categoryById[item.categoryId]?.color ?? AppColors.textMuted;
            return PieChartSectionData(
              value: item.total.toDouble(),
              color: color,
              showTitle: false,
              radius: 24,
            );
          }).toList();

    return Center(
      child: SizedBox(
        width: 172,
        height: 172,
        child: Stack(
          alignment: Alignment.center,
          children: [
            PieChart(
              PieChartData(sections: sections, centerSpaceRadius: 62, sectionsSpace: 2),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Tổng chi',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                ),
                Text(
                  Formatters.amount(totalExpense),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.category, required this.breakdown});

  final Category category;
  final StatusBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: category.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(category.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(
                Formatters.amount(breakdown.total),
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final step in category.statuses)
            _StatusRow(label: step.name, amount: breakdown.totals[step.id] ?? 0),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.amount});

  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          ),
          Text(
            Formatters.amount(amount),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.item, required this.totalExpense, required this.category});

  final CategoryTotal item;
  final int totalExpense;
  final Category? category;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: category?.color ?? AppColors.textMuted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              category?.name ?? 'Đã xoá danh mục',
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '${item.percentOf(totalExpense)}%',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              Formatters.amount(item.total),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
