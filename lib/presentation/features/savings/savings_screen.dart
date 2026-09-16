import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/id_generator.dart';
import '../../../domain/entities/family_member.dart';
import '../../../domain/entities/savings_asset_type.dart';
import '../../../domain/errors/domain_exceptions.dart';
import '../../../domain/usecases/compute_pool_balance.dart';
import '../../providers/savings_asset_type_providers.dart';
import '../../providers/transaction_providers.dart';
import '../add_transaction/add_transaction_sheet.dart';

const _assetColors = <Color>[
  Color(0xFF8FA3B3),
  Color(0xFF12805C),
  Color(0xFFC9A23E),
  Color(0xFF8A4FB0),
  Color(0xFFC14F7A),
];

/// Màn "Tiết kiệm" — không còn cố định 2 loại "Hiện tại"/"Ngân hàng" như
/// bản trước (`docs/financial-core-v2.md` mục 9). Gia đình tự tạo bao
/// nhiêu loại tài sản tuỳ ý (Chứng khoán, Bất động sản, Vàng...) — xoá
/// được khi cả 2 thành viên đều đã về 0 ở loại đó.
class SavingsScreen extends ConsumerStatefulWidget {
  const SavingsScreen({super.key});

  @override
  ConsumerState<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends ConsumerState<SavingsScreen> {
  FamilyMember _member = FamilyMember.vo;

  @override
  Widget build(BuildContext context) {
    final assetTypes = ref.watch(savingsAssetTypesStreamProvider).valueOrNull ?? [];
    final transactions = ref.watch(transactionsStreamProvider).valueOrNull ?? [];
    final active = assetTypes.where((a) => a.isActive).toList();

    final total = active.fold<int>(
      0,
      (sum, a) => sum + computeMemberSavingsByAssetType(a.id, _member, transactions),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Tiết kiệm')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<FamilyMember>(
            segments: FamilyMember.values
                .map((m) => ButtonSegment(value: m, label: Text(m.label)))
                .toList(),
            selected: {_member},
            onSelectionChanged: (s) => setState(() => _member = s.first),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tổng tiết kiệm của ${_member.label}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  Formatters.amount(total),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final a in active)
            _AssetTypeTile(
              assetType: a,
              member: _member,
              balance: computeMemberSavingsByAssetType(a.id, _member, transactions),
            ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => _createAssetType(context, ref),
            child: const Text('+ Thêm loại tài sản'),
          ),
        ],
      ),
    );
  }

  Future<void> _createAssetType(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thêm loại tài sản tiết kiệm'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tên (vd Chứng khoán, Bất động sản...)',
          ),
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
    final color = _assetColors[DateTime.now().millisecond % _assetColors.length];
    await ref.read(savingsAssetTypeRepositoryProvider).addAssetType(
      SavingsAssetType(id: IdGenerator.generate(), name: name, color: color),
    );
  }
}

class _AssetTypeTile extends ConsumerWidget {
  const _AssetTypeTile({
    required this.assetType,
    required this.member,
    required this.balance,
  });

  final SavingsAssetType assetType;
  final FamilyMember member;
  final int balance;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    if (balance != 0) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Chưa thể xoá loại tài sản này'),
          content: const Text(
            'Vẫn còn thành viên có số dư khác 0 ở loại này — rút/chuyển hết trước khi xoá.',
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
      await ref.read(savingsAssetTypeRepositoryProvider).softDeleteAssetType(assetType.id);
    } on SavingsAssetTypeNotEmptyException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vừa có giao dịch mới, thử lại sau.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: assetType.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(assetType.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  Formatters.amount(balance),
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Nạp',
            icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.accent),
            onPressed: () => showAddTransactionSheet(
              context,
              initialType: EntryType.chuyen,
              initialTransferSubKind: TransferSubKind.savings,
              initialSavingsAction: SavingsAction.topup,
              initialSavingsAssetTypeId: assetType.id,
              initialMember: member,
            ),
          ),
          IconButton(
            tooltip: 'Rút',
            icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.expenseAmount),
            onPressed: () => showAddTransactionSheet(
              context,
              initialType: EntryType.chuyen,
              initialTransferSubKind: TransferSubKind.savings,
              initialSavingsAction: SavingsAction.withdraw,
              initialSavingsAssetTypeId: assetType.id,
              initialMember: member,
            ),
          ),
          IconButton(
            tooltip: 'Xoá loại này',
            icon: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 18),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
    );
  }
}
