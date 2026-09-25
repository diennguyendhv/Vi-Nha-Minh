import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../../domain/entities/fund.dart';
import '../../../domain/entities/pool_kind.dart';
import '../../../domain/errors/domain_exceptions.dart';
import '../../../domain/usecases/compute_pool_balance.dart';
import '../../providers/category_providers.dart';
import '../../providers/member_providers.dart';
import '../../providers/savings_asset_type_providers.dart';
import '../../providers/fund_providers.dart';
import '../../providers/transaction_providers.dart';
import '../../widgets/transaction_row.dart';
import '../add_transaction/add_transaction_sheet.dart';
import '../transactions/transaction_detail_screen.dart';

/// Màn "Quỹ — Chi tiết" (`docs/design.html` màn 15). Chỉ xem số dư + lịch
/// sử — "Nạp quỹ"/"Ghi khoản mua" mở thẳng màn Thêm giao dịch điền sẵn,
/// không nhập trực tiếp ở đây (1 nơi tạo giao dịch duy nhất, mục 9).
class FundDetailScreen extends ConsumerWidget {
  const FundDetailScreen({super.key, required this.fundId});

  final String fundId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final funds = ref.watch(fundsStreamProvider).valueOrNull ?? [];
    final transactions =
        ref.watch(transactionsStreamProvider).valueOrNull ?? [];
    final categories = ref.watch(categoriesStreamProvider).valueOrNull ?? [];
    final categoryById = {for (final c in categories) c.id: c};
    final members = ref.watch(memberDirectoryProvider).members;
    final assetTypes =
        ref.watch(savingsAssetTypesStreamProvider).valueOrNull ?? const [];
    Fund? fund;
    for (final f in funds) {
      if (f.id == fundId) fund = f;
    }
    if (fund == null) {
      return const Scaffold(body: Center(child: Text('Quỹ không tồn tại.')));
    }

    final balance = computeFundBalance(fundId, transactions);
    final history =
        transactions
            .where(
              (t) =>
                  isVisible(t) &&
                  ((t.sourceKind == PoolKind.fund && t.sourceRefId == fundId) ||
                      (t.destinationKind == PoolKind.fund &&
                          t.destinationRefId == fundId)),
            )
            .toList()
          ..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));

    return Scaffold(
      appBar: AppBar(
        title: Text(fund.name),
        actions: [
          IconButton(
            key: const Key('fund_rename'),
            tooltip: 'Đổi tên quỹ',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _rename(context, ref, fund!),
          ),
        ],
      ),
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
                  onPressed: () =>
                      showAddTransactionSheet(context, initialFundId: fundId),
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
            ...history.map(
              (t) => TransactionRow(
                key: Key('fund_transaction_${t.id}'),
                transaction: t,
                category: categoryById[t.categoryId],
                members: members,
                assetTypes: assetTypes,
                showDate: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        TransactionDetailScreen(transactionId: t.id),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
          TextButton(
            key: const Key('fund_stop'),
            onPressed: () => _deleteFund(context, ref, balance),
            child: const Text(
              'Ngừng sử dụng quỹ này',
              style: TextStyle(color: AppColors.expenseAmount),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, Fund fund) async {
    final controller = TextEditingController(text: fund.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đổi tên quỹ'),
        content: TextField(
          key: const Key('fund_rename_field'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tên quỹ'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            key: const Key('fund_rename_save'),
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == fund.name) return;
    await ref
        .read(fundRepositoryProvider)
        .updateFund(fund.copyWith(name: name));
  }

  Future<void> _deleteFund(
    BuildContext context,
    WidgetRef ref,
    int balance,
  ) async {
    if (balance != 0) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Chưa thể ngừng sử dụng quỹ này'),
          content: Text(
            'Quỹ vẫn còn ${Formatters.amount(balance)} — rút hết về ví (nút "Nạp quỹ" → chọn "Rút") trước khi ngừng sử dụng.',
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
          const SnackBar(
            content: Text('Quỹ vừa có giao dịch mới, thử lại sau.'),
          ),
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
