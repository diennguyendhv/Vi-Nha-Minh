import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/default_funds.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/family_member.dart';
import '../../../domain/entities/fund.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/usecases/compute_grouped_totals.dart';
import '../../../domain/usecases/compute_member_financials.dart';
import '../../../domain/usecases/compute_pool_balance.dart';
import '../../../domain/usecases/explore_transactions.dart';
import '../../providers/app_state_providers.dart';
import '../../providers/category_providers.dart';
import '../../providers/feature_providers.dart';
import '../../providers/fund_providers.dart';
import '../../providers/transaction_providers.dart';
import '../add_transaction/add_transaction_sheet.dart';
import '../fund/fund_detail_screen.dart';
import '../fund/fund_list_screen.dart';
import '../loans/loans_screen.dart';
import '../savings/savings_screen.dart';
import '../settings/settings_screen.dart';

/// Trang chủ — KHÔNG phải báo cáo kế toán, chỉ trả lời nhanh 8 câu hỏi thật:
/// Vợ / Chồng tháng này kiếm được bao nhiêu · đang có bao nhiêu tiền dùng
/// được · đang có bao nhiêu Tiết kiệm · gia đình đã Chi tiêu bao nhiêu · Quỹ
/// tiền ăn còn bao nhiêu.
///
/// Mọi số lấy từ CÙNG nguồn sự thật với Tổng hợp/Financial Engine, không tự
/// tính lại: Thu nhập = `computeMemberNetIncome`; Chi tiêu gia đình =
/// `computeGroupedTotals(...).spending`; Số dư/Tiết kiệm =
/// `computeMemberFinancials` (pool của Engine, KHÔNG suy ra từ Thu − Chi vì
/// Chuyển/Tiết kiệm/Quỹ làm công thức đó lệch); Quỹ = `computeFundBalance`.
///
/// Tổng tài sản / Tài sản ròng / Vay / Phải thu-trả / Doanh thu / Chi phí kinh
/// doanh… vẫn được Engine tính và có ở Tổng hợp; chỉ KHÔNG hiện ở đây.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(transactionsStreamProvider);
    final categoriesAsync = ref.watch(categoriesStreamProvider);
    final fundsAsync = ref.watch(fundsStreamProvider);

    if (transactionsAsync.isLoading ||
        categoriesAsync.isLoading ||
        fundsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error =
        transactionsAsync.error ?? categoriesAsync.error ?? fundsAsync.error;
    if (error != null) {
      return Center(child: Text('Lỗi tải dữ liệu: $error'));
    }

    return _HomeContent(
      transactions: transactionsAsync.value ?? const [],
      categories: categoriesAsync.value ?? const [],
      funds: fundsAsync.value ?? const [],
      showLoans: ref.watch(advancedFeaturesEnabledProvider),
    );
  }
}

class _HomeContent extends ConsumerStatefulWidget {
  const _HomeContent({
    required this.transactions,
    required this.categories,
    required this.funds,
    required this.showLoans,
  });

  final List<Transaction> transactions;
  final List<Category> categories;
  final List<Fund> funds;

  /// Lối tắt Vay & Cho vay chỉ hiện khi bật tính năng nâng cao.
  final bool showLoans;

  @override
  ConsumerState<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends ConsumerState<_HomeContent> {
  /// Chặn bấm liên tiếp mở trùng màn/sheet: tap thứ hai bị bỏ qua cho tới khi
  /// màn vừa mở đóng lại.
  bool _busy = false;

  Future<void> _once(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    try {
      await action();
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final transactions = widget.transactions;
    final categories = widget.categories;

    final members = [
      for (final m in FamilyMember.values)
        (
          member: m,
          income: computeMemberNetIncome(
            m,
            transactions,
            categories,
            month: month,
          ),
          financials: computeMemberFinancials(m, transactions),
        ),
    ];
    final spending = computeGroupedTotals(
      transactions,
      categories,
      month: month,
    ).spending;

    Fund? foodFund;
    for (final f in widget.funds) {
      if (f.id == DefaultFunds.anUongId && f.isActive) foodFund = f;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        _Header(monthLabel: 'Tháng ${now.month}'),
        const SizedBox(height: 20),
        for (final m in members) ...[
          _MemberCard(
            member: m.member,
            income: m.income,
            balance: m.financials.balance,
            savings: m.financials.savingsTotal,
            onSavings: () => _once(
              () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SavingsScreen(initialMember: m.member),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        _SpendingCard(
          monthLabel: 'Tháng ${now.month}',
          amount: spending,
          onDetail: () =>
              ref.read(currentTabProvider.notifier).state = AppTab.summary,
        ),
        if (foodFund == null) ...[
          const SizedBox(height: 14),
          // Quỹ do gia đình tạo/xóa được — thiếu Quỹ tiền ăn thì hiện trạng thái
          // rỗng (KHÔNG tự tạo lại, không crash).
          _NoFundCard(
            onCreate: () => _once(
              () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const FundListScreen()),
              ),
            ),
          ),
        ],
        if (foodFund != null) ...[
          const SizedBox(height: 14),
          _FoodFundCard(
            fund: foodFund,
            balance: computeFundBalance(foodFund.id, transactions),
            onOpen: () => _once(
              () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FundDetailScreen(fundId: foodFund!.id),
                ),
              ),
            ),
            onTopUp: () => _once(
              () => showAddTransactionSheet(
                context,
                initialType: EntryType.chuyen,
                initialTransferSubKind: TransferSubKind.fund,
                initialFundId: foodFund!.id,
              ),
            ),
          ),
        ],
        if (widget.showLoans) ...[
          const SizedBox(height: 14),
          _LoansShortcutCard(
            onTap: () => _once(
              () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => const LoansScreen())),
            ),
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.monthLabel});

  final String monthLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
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

/// Thẻ nền chung — 1 kiểu duy nhất cho mọi khối trên Trang chủ.
class _Card extends StatelessWidget {
  const _Card({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(18), child: child),
        ),
      ),
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
        fontSize: 11,
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// Vợ / Chồng: 3 dòng — Thu nhập tháng này, Số dư hiện tại, Tiết kiệm. Không
/// phải nút (chỉ là số), nên không có hành động chạm.
class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.income,
    required this.balance,
    required this.savings,
    required this.onSavings,
  });

  final FamilyMember member;
  final int income;
  final int balance;
  final int savings;

  /// Chạm dòng "Tiết kiệm" → màn Tiết kiệm của đúng thành viên.
  final VoidCallback onSavings;

  @override
  Widget build(BuildContext context) {
    final key = member.name;
    return _Card(
      key: Key('home_member_$key'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(member.label),
          const SizedBox(height: 12),
          _StatRow(
            valueKey: Key('home_income_$key'),
            label: 'Thu nhập tháng này',
            value: income,
          ),
          const SizedBox(height: 10),
          _StatRow(
            valueKey: Key('home_balance_$key'),
            label: 'Số dư hiện tại',
            value: balance,
            negativeIsRed: true,
          ),
          const SizedBox(height: 10),
          _StatRow(
            valueKey: Key('home_savings_$key'),
            label: 'Tiết kiệm',
            value: savings,
            onTap: onSavings,
            rowKey: Key('home_savings_row_$key'),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.valueKey,
    required this.label,
    required this.value,
    this.negativeIsRed = false,
    this.onTap,
    this.rowKey,
  });

  final VoidCallback? onTap;
  final Key? rowKey;
  final Key valueKey;
  final String label;
  final int value;
  final bool negativeIsRed;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textSecondary,
              ),
            ),
            if (onTap != null)
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textMuted,
              ),
          ],
        ),
        Text(
          Formatters.amount(value),
          key: valueKey,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: negativeIsRed && value < 0
                ? AppColors.expenseAmount
                : AppColors.textPrimary,
          ),
        ),
      ],
    );
    if (onTap == null) return row;
    return InkWell(
      key: rowKey,
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: row),
    );
  }
}

class _SpendingCard extends StatelessWidget {
  const _SpendingCard({
    required this.monthLabel,
    required this.amount,
    required this.onDetail,
  });

  final String monthLabel;
  final int amount;
  final VoidCallback onDetail;

  @override
  Widget build(BuildContext context) {
    return _Card(
      key: const Key('home_household_spending'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('Chi tiêu gia đình'),
          const SizedBox(height: 4),
          Text(
            monthLabel,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          Text(
            Formatters.amount(amount),
            key: const Key('home_spending_amount'),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('home_spending_detail'),
              onPressed: onDetail,
              child: const Text('Xem chi tiết'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FoodFundCard extends StatelessWidget {
  const _FoodFundCard({
    required this.fund,
    required this.balance,
    required this.onOpen,
    required this.onTopUp,
  });

  final Fund fund;
  final int balance;
  final VoidCallback onOpen;
  final VoidCallback onTopUp;

  @override
  Widget build(BuildContext context) {
    return _Card(
      key: const Key('home_food_fund'),
      onTap: onOpen,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionLabel(fund.name),
                const SizedBox(height: 6),
                Text(
                  balance > 0 ? Formatters.amount(balance) : 'Đã hết',
                  key: const Key('home_food_fund_amount'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (balance > 0)
                  const Text(
                    'Còn lại',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
          OutlinedButton(
            key: const Key('home_food_fund_topup'),
            onPressed: onTopUp,
            child: const Text('Nạp quỹ'),
          ),
        ],
      ),
    );
  }
}

class _NoFundCard extends StatelessWidget {
  const _NoFundCard({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return _Card(
      key: const Key('home_no_fund'),
      onTap: onCreate,
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Chưa có Quỹ tiền ăn',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          OutlinedButton(
            key: const Key('home_no_fund_create'),
            onPressed: onCreate,
            child: const Text('Tạo quỹ'),
          ),
        ],
      ),
    );
  }
}

/// Chỉ hiện khi bật tính năng nâng cao (mặc định tắt).
class _LoansShortcutCard extends StatelessWidget {
  const _LoansShortcutCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Card(
      key: const Key('home_loans_shortcut'),
      onTap: onTap,
      child: const Row(
        children: [
          Icon(Icons.handshake_rounded, color: AppColors.accent, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Vay & Cho vay',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ],
      ),
    );
  }
}
