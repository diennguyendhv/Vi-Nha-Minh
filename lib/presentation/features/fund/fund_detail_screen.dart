import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../../domain/entities/fund.dart';
import '../../../domain/entities/pool_kind.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/errors/domain_exceptions.dart';
import '../../../domain/usecases/compute_pool_balance.dart';
import '../../providers/fund_providers.dart';
import '../../providers/transaction_providers.dart';
import '../add_transaction/add_transaction_sheet.dart';

/// Màn "Quỹ — Chi tiết" (`docs/design.html` màn 15). Chỉ xem số dư + lịch
/// sử — "Nạp quỹ"/"Ghi khoản mua" mở thẳng màn Thêm giao dịch điền sẵn,
/// không nhập trực tiếp ở đây (1 nơi tạo giao dịch duy nhất, mục 9).
class FundDetailScreen extends ConsumerWidget {
  const FundDetailScreen({super.key, required this.fundId});

  final String fundId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final funds = ref.watch(fundsStreamProvider).valueOrNull ?? [];
    final transactions = ref.watch(transactionsStreamProvider).valueOrNull ?? [];
    Fund? fund;
    for (final f in funds) {
      if (f.id == fundId) fund = f;
    }
    if (fund == null) {
      return const Scaffold(body: Center(child: Text('Quỹ không tồn tại.')));
    }

    final balance = computeFundBalance(fundId, transactions);
    final history = transactions
        .where(
          (t) =>
              isVisible(t) &&
              ((t.sourceKind == PoolKind.fund && t.sourceRefId == fundId) ||
                  (t.destinationKind == PoolKind.fund && t.destinationRefId == fundId)),
        )
        .toList()
      ..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));

    return Scaffold(
      appBar: AppBar(title: Text(fund.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          _BalanceCard(balance: balance),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => showAddTransactionSheet(
                    context,
                    initialType: EntryType.chuyen,
                    initialTransferSubKind: TransferSubKind.fund,
                    initialFundId: fundId,
                  ),
                  child: const Text('Nạp quỹ'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => showAddTransactionSheet(
                    context,
                    initialFundId: fundId,
                  ),
                  child: const Text('Ghi khoản mua'),
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
          if (history.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Chưa có khoản nào trong quỹ',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            ...history.map((t) => _EntryRow(transaction: t, fundId: fundId)),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () => _deleteFund(context, ref, balance),
            child: const Text(
              'Xoá quỹ này',
              style: TextStyle(color: AppColors.expenseAmount),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFund(BuildContext context, WidgetRef ref, int balance) async {
    if (balance != 0) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Chưa thể xoá quỹ này'),
          content: Text(
            'Quỹ còn ${Formatters.amount(balance)} — rút hết về ví (nút "Nạp quỹ" → chọn "Rút") trước khi xoá.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Đã hiểu'),
            ),
          ],
        ),
      );
      return;
    }
    try {
      await ref.read(fundRepositoryProvider).softDeleteFund(fundId);
      if (context.mounted) Navigator.of(context).pop();
    } on FundNotEmptyException {
      // Race condition hiếm gặp — số dư vừa đổi giữa lúc đọc và lúc xoá.
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quỹ vừa có giao dịch mới, thử lại sau.')),
        );
      }
    }
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance});

  final int balance;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(color: AppColors.shadow, blurRadius: 16, offset: const Offset(0, 4)),
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
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.transaction, required this.fundId});

  final Transaction transaction;
  final String fundId;

  @override
  Widget build(BuildContext context) {
    final isTopUp = transaction.destinationRefId == fundId;
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
                  transaction.note.isEmpty
                      ? (isTopUp ? 'Nạp quỹ' : 'Ghi khoản mua')
                      : transaction.note,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                Text(
                  Formatters.dayMonth(transaction.transactionDate),
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            '${isTopUp ? '+' : '-'} ${Formatters.amount(transaction.amountMinor)}',
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
