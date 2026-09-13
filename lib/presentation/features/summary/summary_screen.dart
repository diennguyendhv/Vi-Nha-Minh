import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/default_categories.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/usecases/compute_expense_breakdown.dart';
import '../../providers/transaction_providers.dart';

class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(transactionsStreamProvider);

    return transactionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Lỗi tải dữ liệu: $err')),
      data: (transactions) {
        final breakdown = computeExpenseBreakdown(transactions);
        final totalExpense = breakdown.fold<int>(0, (s, c) => s + c.total);
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            Text(
              'Tổng hợp Tháng ${DateTime.now().month}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            _Donut(breakdown: breakdown, totalExpense: totalExpense),
            const SizedBox(height: 22),
            const Text(
              'Theo hạng mục',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
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
                (item) => _LegendRow(item: item, totalExpense: totalExpense),
              ),
          ],
        );
      },
    );
  }
}

class _Donut extends StatelessWidget {
  const _Donut({required this.breakdown, required this.totalExpense});

  final List<CategoryTotal> breakdown;
  final int totalExpense;

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
            final category = DefaultCategories.byId(item.categoryId);
            return PieChartSectionData(
              value: item.total.toDouble(),
              color: category.color,
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
              PieChartData(
                sections: sections,
                centerSpaceRadius: 62,
                sectionsSpace: 2,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Tổng chi',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
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

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.item, required this.totalExpense});

  final CategoryTotal item;
  final int totalExpense;

  @override
  Widget build(BuildContext context) {
    final category = DefaultCategories.byId(item.categoryId);
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
            decoration: BoxDecoration(color: category.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              category.name,
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
