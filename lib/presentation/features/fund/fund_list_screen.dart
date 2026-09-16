import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/id_generator.dart';
import '../../../domain/entities/fund.dart';
import '../../../domain/usecases/compute_pool_balance.dart';
import '../../providers/fund_providers.dart';
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
    final transactions = ref.watch(transactionsStreamProvider).valueOrNull ?? [];
    final active = funds.where((f) => f.isActive).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Quỹ')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final f in active)
            _FundTile(
              fund: f,
              balance: computeFundBalance(f.id, transactions),
            ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => _createFund(context, ref),
            child: const Text('+ Tạo quỹ mới'),
          ),
        ],
      ),
    );
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
    await ref.read(fundRepositoryProvider).addFund(
      Fund(id: IdGenerator.generate(), name: name, color: color),
    );
  }
}

class _FundTile extends StatelessWidget {
  const _FundTile({required this.fund, required this.balance});

  final Fund fund;
  final int balance;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(backgroundColor: fund.color),
      title: Text(fund.name),
      subtitle: Text('Số dư ${Formatters.amount(balance)}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => FundDetailScreen(fundId: fund.id)),
      ),
    );
  }
}
