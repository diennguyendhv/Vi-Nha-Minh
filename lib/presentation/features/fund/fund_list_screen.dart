import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/id_generator.dart';
import '../../../domain/entities/fund.dart';
import '../../../domain/errors/domain_exceptions.dart';
import '../../../domain/usecases/compute_pool_balance.dart';
import '../../../domain/usecases/deletion_check.dart';
import '../../providers/category_providers.dart';
import '../../widgets/stopped_item_tile.dart';
import '../../providers/fund_providers.dart';
import '../../providers/member_providers.dart';
import '../../providers/primary_fund_provider.dart';
import '../../providers/transaction_providers.dart';
import 'fund_detail_screen.dart';

const _fundColors = <Color>[
  Color(0xFFC98A3E),
  Color(0xFF3E6FB0),
  Color(0xFF8FA3B3),
  Color(0xFFC14F7A),
];

/// Màn "Quỹ — Danh sách" (`docs/design.html` màn 14). Tạo được nhiều quỹ,
/// không còn 1 quỹ cố định (phase 15-16).
class FundListScreen extends ConsumerWidget {
  const FundListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final funds = ref.watch(fundsStreamProvider).valueOrNull ?? [];
    final transactions =
        ref.watch(transactionsStreamProvider).valueOrNull ?? [];
    final categories =
        ref.watch(categoriesStreamProvider).valueOrNull ?? const [];
    final deletable = ref.watch(deletableFundIdsProvider);
    final primaryFundId = ref.watch(primaryFundIdProvider);
    final active = funds.where((f) => f.isActive).toList();
    final stopped = funds.where((f) => !f.isActive).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Quỹ')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (active.isEmpty)
            const Padding(
              key: Key('fund_list_empty'),
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Chưa có quỹ nào.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          for (final f in active)
            _FundTile(
              fund: f,
              balance: computeFundBalance(f.id, transactions),
              isPrimary: f.id == primaryFundId,
              onSetPrimary: () =>
                  ref.read(primaryFundIdProvider.notifier).select(f.id),
            ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('fund_create'),
            onPressed: () => _createFund(context, ref),
            child: const Text('+ Tạo quỹ mới'),
          ),
          if (stopped.isNotEmpty) ...[
            const SizedBox(height: 20),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: const Key('fund_stopped_section'),
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'Ngừng sử dụng (${stopped.length})',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textMuted,
                  ),
                ),
                children: [
                  for (final f in stopped)
                    StoppedItemTile(
                      idKey: 'fund_${f.id}',
                      name: f.name,
                      color: f.color,
                      noun: 'quỹ này',
                      check: checkFundDeletion(
                        f.id,
                        categories,
                        transactions,
                        members: ref.watch(memberDirectoryProvider).members,
                      ),
                      onReuse: () =>
                          ref.read(fundRepositoryProvider).reactivateFund(f.id),
                      onDelete: () => _confirmDelete(context, ref, f, deletable),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Fund fund,
    Set<String> deletable,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Xóa hẳn "${fund.name}"?'),
        content: const Text('Quỹ sẽ biến mất và không thể khôi phục.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            key: const Key('confirm_delete_fund'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xóa hẳn'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(fundRepositoryProvider).deleteFundPermanently(fund.id);
      // Xóa đúng quỹ chính → bỏ chọn (Trang chủ hiện "Chưa chọn quỹ chính"), không
      // tự chọn quỹ khác.
      await ref.read(primaryFundIdProvider.notifier).clearIfPrimary(fund.id);
    } on FundNotDeletableException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Quỹ này vừa có giao dịch mới nên không thể xóa.'),
          ),
        );
      }
    }
  }

  Future<void> _createFund(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tạo quỹ mới'),
        content: TextField(
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
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Tạo'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final color = _fundColors[DateTime.now().millisecond % _fundColors.length];
    await ref
        .read(fundRepositoryProvider)
        .addFund(Fund(id: IdGenerator.generate(), name: name, color: color));
  }
}

class _FundTile extends StatelessWidget {
  const _FundTile({
    required this.fund,
    required this.balance,
    required this.isPrimary,
    required this.onSetPrimary,
  });

  final Fund fund;
  final int balance;
  final bool isPrimary;
  final VoidCallback onSetPrimary;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(backgroundColor: fund.color),
      title: Text(fund.name),
      subtitle: Text('Số dư ${Formatters.amount(balance)}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPrimary)
            Chip(
              key: Key('fund_primary_badge_${fund.id}'),
              label: const Text('Quỹ chính'),
              visualDensity: VisualDensity.compact,
            )
          else
            TextButton(
              key: Key('fund_set_primary_${fund.id}'),
              onPressed: onSetPrimary,
              child: const Text('Đặt làm quỹ chính'),
            ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FundDetailScreen(fundId: fund.id),
        ),
      ),
    );
  }
}
