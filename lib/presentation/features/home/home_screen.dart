import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/family_member.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../../domain/usecases/compute_financial_summary.dart';
import '../../../domain/usecases/compute_member_financials.dart';
import '../../providers/category_providers.dart';
import '../../providers/fund_providers.dart';
import '../../providers/obligation_providers.dart';
import '../../providers/savings_asset_type_providers.dart';
import '../../providers/feature_providers.dart';
import '../../widgets/category_label.dart';
import '../../providers/transaction_providers.dart';
import '../loans/loans_screen.dart';
import '../settings/settings_screen.dart';
import '../transactions/transaction_detail_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(transactionsStreamProvider);
    final categoriesAsync = ref.watch(categoriesStreamProvider);
    final fundsAsync = ref.watch(fundsStreamProvider);
    final assetTypesAsync = ref.watch(savingsAssetTypesStreamProvider);
    final obligationsAsync = ref.watch(obligationsStreamProvider);

    if (transactionsAsync.isLoading ||
        categoriesAsync.isLoading ||
        fundsAsync.isLoading ||
        assetTypesAsync.isLoading ||
        obligationsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error =
        transactionsAsync.error ??
        categoriesAsync.error ??
        fundsAsync.error ??
        assetTypesAsync.error ??
        obligationsAsync.error;
    if (error != null) {
      return Center(child: Text('Lỗi tải dữ liệu: $error'));
    }

    final transactions = transactionsAsync.value ?? const [];
    final categories = categoriesAsync.value ?? const [];
    final funds = (fundsAsync.value ?? const [])
        .where((f) => f.isActive)
        .toList();
    final assetTypes = (assetTypesAsync.value ?? const [])
        .where((a) => a.isActive)
        .toList();
    final obligations = obligationsAsync.value ?? const [];

    final summary = computeFinancialSummary(
      transactions,
      categories: categories,
      funds: funds,
      assetTypes: assetTypes,
      obligations: obligations,
      month: DateTime.now(),
    );

    return _HomeContent(
      transactions: transactions,
      categories: categories,
      summary: summary,
      showLoans: ref.watch(advancedFeaturesEnabledProvider),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({
    required this.transactions,
    required this.categories,
    required this.summary,
    required this.showLoans,
  });

  final List<Transaction> transactions;
  final List<Category> categories;
  final FinancialSummary summary;

  /// Lối tắt Vay & Cho vay chỉ hiện khi bật tính năng nâng cao.
  final bool showLoans;

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
        const SizedBox(height: 20),
        _AssetOverviewCard(summary: summary),
        if (showLoans) ...[
          const SizedBox(height: 12),
          _LoansShortcutCard(summary: summary),
        ],
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

/// "Tổng quan tài sản" — bản RÚT GỌN của Phase 8 `FinancialSummary` cho
/// Trang chủ (`computeFinancialSummary`, dùng chung 1 nguồn với
/// `summary_screen.dart`, KHÔNG tự tính lại). Chỉ hiện tổng, không hiện
/// breakdown từng Quỹ/loại tài sản — xem bản đầy đủ ở tab "Tổng hợp".
class _AssetOverviewCard extends StatelessWidget {
  const _AssetOverviewCard({required this.summary});

  final FinancialSummary summary;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Container(
      padding: const EdgeInsets.all(18),
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
          const Text(
            'TỔNG TÀI SẢN',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            Formatters.amount(summary.totalAssets),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          // Phase 8.8 — chỉ hiện khi có Payable, tránh người dùng tưởng vừa
          // "giàu thêm" sau khi đi vay (audit mục 24) — Receivable đã nằm
          // TRONG totalAssets rồi nên không hiện dòng riêng ở đây (mục 25:
          // không cộng lại lần 2).
          if (summary.totalPayables > 0) ...[
            const SizedBox(height: 2),
            Text(
              'Tài sản ròng: ${Formatters.amount(summary.netWorth)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Số dư khả dụng',
                  value: summary.totalAvailable,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(
                  label: 'Tiết kiệm',
                  value: summary.totalSavings,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(label: 'Quỹ', value: summary.totalFunds),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Thu tháng ${now.month}',
                  value: summary.monthlyIncome,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(
                  label: 'Chi tháng ${now.month}',
                  value: summary.monthlyExpense,
                  color: AppColors.expenseAmount,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(label: 'Còn lại', value: summary.monthlyNet),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Phase 8.8 — entry point cho màn "Vay & Cho vay" (mục 3) — card riêng,
/// KHÔNG đổi bottom navigation. `totalReceivables`/`totalPayables` đọc
/// thẳng từ [FinancialSummary] đã tính sẵn (Phase 8.7), KHÔNG tự cộng lại
/// (mục 3: "Không duplicate financial calculation trong UI").
class _LoansShortcutCard extends StatelessWidget {
  const _LoansShortcutCard({required this.summary});

  final FinancialSummary summary;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const LoansScreen())),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.handshake_rounded,
                color: AppColors.accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Vay & Cho vay',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Phải thu ${Formatters.amount(summary.totalReceivables)} · Phải trả ${Formatters.amount(summary.totalPayables)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, this.color});

  final String label;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.chipBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
          const SizedBox(height: 2),
          Text(
            Formatters.amount(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: color ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
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
                  style: TextStyle(fontSize: 10, color: AppColors.textMuted),
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

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.transaction, required this.category});

  final Transaction transaction;
  final Category? category;

  @override
  Widget build(BuildContext context) {
    final color = category?.color ?? AppColors.textMuted;
    final name = categoryDisplayLabel(category);
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
    final participant = transactionMemberLabel(transaction) ?? '';
    final subtitle = transaction.note.isEmpty
        ? participant
        : (participant.isEmpty
              ? transaction.note
              : '${transaction.note} · $participant');

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              TransactionDetailScreen(transactionId: transaction.id),
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
