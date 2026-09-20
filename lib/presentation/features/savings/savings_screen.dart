import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/id_generator.dart';
import '../../../domain/entities/family_member.dart';
import '../../../domain/entities/savings_asset_type.dart';
import '../../../domain/errors/domain_exceptions.dart';
import '../../../domain/usecases/compute_savings_breakdown.dart';
import '../../providers/savings_asset_type_providers.dart';
import '../../providers/transaction_providers.dart';
import '../add_transaction/add_transaction_sheet.dart';

const _assetColors = <Color>[
  Color(0xFF12805C),
  Color(0xFFC9A23E),
  Color(0xFF8A4FB0),
  Color(0xFFC14F7A),
  Color(0xFF3E6FB0),
];

String _norm(String v) =>
    v.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// Màn "Tiết kiệm" 2 tầng của MỘT thành viên (Vợ / Chồng tách riêng):
///  • Tầng 1 — tổng tiết kiệm + [Thêm vào tiết kiệm] / [Rút về số dư]; thêm vào
///    KHÔNG cần chọn loại tài sản (tiền vào "Chưa phân bổ");
///  • Tầng 2 — "Phân bổ": Chưa phân bổ + các loại tài sản; chuyển giữa các loại
///    (Phân bổ), rút từ 1 loại về Số dư. Không có tiền nào tồn tại mà không
///    hiện ra ở đây (kể cả loại đã ngừng còn số dư).
///
/// Chỉ theo GIÁ TRỊ GHI SỔ — không kỳ hạn, lãi suất, giá thị trường.
class SavingsScreen extends ConsumerStatefulWidget {
  const SavingsScreen({super.key, this.initialMember});

  final FamilyMember? initialMember;

  @override
  ConsumerState<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends ConsumerState<SavingsScreen> {
  late FamilyMember _member = widget.initialMember ?? FamilyMember.vo;

  /// Chặn bấm liên tiếp mở trùng sheet/hộp thoại.
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

  Future<void> _openSheet({
    required SavingsAction action,
    String? assetTypeId,
  }) => _once(
    () => showAddTransactionSheet(
      context,
      initialType: EntryType.chuyen,
      initialTransferSubKind: TransferSubKind.savings,
      initialSavingsAction: action,
      initialSavingsAssetTypeId: assetTypeId,
      initialMember: _member,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final assetTypes =
        ref.watch(savingsAssetTypesStreamProvider).valueOrNull ?? [];
    final transactions =
        ref.watch(transactionsStreamProvider).valueOrNull ?? [];
    final deletable = ref.watch(deletableSavingsAssetTypeIdsProvider);

    final breakdown = computeMemberSavingsBreakdown(
      _member,
      transactions,
      assetTypes,
    );
    // Loại đã ngừng và KHÔNG còn tiền ở cả 2 thành viên → khu "Ngừng sử dụng".
    final allBreakdowns = [
      for (final m in FamilyMember.values)
        computeMemberSavingsBreakdown(m, transactions, assetTypes),
    ];
    bool holdsMoney(String id) => allBreakdowns.any(
      (b) => b.rows.any((r) => r.assetTypeId == id && r.balance != 0),
    );
    final stopped = [
      for (final a in assetTypes)
        if (!a.isActive && !holdsMoney(a.id)) a,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Tiết kiệm')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<FamilyMember>(
            key: const Key('savings_member'),
            segments: FamilyMember.values
                .map((m) => ButtonSegment(value: m, label: Text(m.label)))
                .toList(),
            selected: {_member},
            onSelectionChanged: (s) => setState(() => _member = s.first),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TIẾT KIỆM ${_member.label.toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  Formatters.amount(breakdown.total),
                  key: const Key('savings_total'),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: const Key('savings_add'),
                  onPressed: () => _openSheet(action: SavingsAction.topup),
                  child: const Text('+ Thêm vào tiết kiệm'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  key: const Key('savings_withdraw'),
                  onPressed: breakdown.total > 0
                      ? () => _openSheet(action: SavingsAction.withdraw)
                      : null,
                  child: const Text('Rút về số dư'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            'Phân bổ',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final row in breakdown.rows)
            _AllocationTile(
              row: row,
              onWithdraw: () => _openSheet(
                action: SavingsAction.withdraw,
                assetTypeId: row.assetTypeId,
              ),
              onAllocate: () => _openSheet(
                action: SavingsAction.convert,
                assetTypeId: row.assetTypeId,
              ),
              onRename: row.isSystem || row.asset == null
                  ? null
                  : () => _once(() => _renameAssetType(row.asset!)),
              onStop: row.isSystem || row.asset == null || row.isInactive
                  ? null
                  : () => _once(() => _stopAssetType(row.asset!)),
            ),
          const SizedBox(height: 4),
          OutlinedButton(
            key: const Key('savings_add_type'),
            onPressed: () => _once(() => _createAssetType(assetTypes)),
            child: const Text('+ Thêm loại'),
          ),
          if (stopped.isNotEmpty) ...[
            const SizedBox(height: 20),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: const Key('savings_stopped_section'),
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
                  for (final a in stopped)
                    ListTile(
                      key: Key('stopped_asset_${a.id}'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: CircleAvatar(
                        radius: 9,
                        backgroundColor: a.color,
                      ),
                      title: Text(
                        a.name,
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                      subtitle: deletable.contains(a.id)
                          ? null
                          : const Text(
                              'Đã được dùng trong lịch sử nên không thể xóa.',
                              style: TextStyle(fontSize: 11.5),
                            ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            key: Key('reuse_asset_${a.id}'),
                            onPressed: () => ref
                                .read(savingsAssetTypeRepositoryProvider)
                                .reactivateAssetType(a.id),
                            child: const Text('Sử dụng lại'),
                          ),
                          if (deletable.contains(a.id))
                            TextButton(
                              key: Key('delete_asset_${a.id}'),
                              onPressed: () => _once(() => _deleteAsset(a)),
                              child: const Text(
                                'Xóa hẳn',
                                style: TextStyle(color: AppColors.expenseAmount),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _stopAssetType(SavingsAssetType asset) async {
    try {
      await ref
          .read(savingsAssetTypeRepositoryProvider)
          .softDeleteAssetType(asset.id);
    } on SavingsAssetTypeNotEmptyException {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Chưa thể ngừng sử dụng loại này'),
          content: const Text(
            'Vẫn còn tiền trong loại này — rút hoặc phân bổ hết trước.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Đã hiểu'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _deleteAsset(SavingsAssetType asset) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Xóa hẳn "${asset.name}"?'),
        content: const Text('Loại tài sản sẽ biến mất và không thể khôi phục.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            key: const Key('confirm_delete_asset'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xóa hẳn'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(savingsAssetTypeRepositoryProvider)
          .deleteAssetTypePermanently(asset.id);
    } on SavingsAssetTypeNotDeletableException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Loại này vừa được dùng nên không thể xóa.'),
          ),
        );
      }
    }
  }

  Future<void> _renameAssetType(SavingsAssetType asset) async {
    final all = ref.read(savingsAssetTypesStreamProvider).valueOrNull ?? [];
    final controller = TextEditingController(text: asset.name);
    String? error;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Đổi tên loại tài sản'),
          content: TextField(
            key: const Key('asset_rename_field'),
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(errorText: error),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Huỷ'),
            ),
            FilledButton(
              key: const Key('asset_rename_save'),
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) return;
                final clash =
                    _norm(value) ==
                        _norm(SystemSavingsAssets.unallocated.name) ||
                    all.any(
                      (a) => a.id != asset.id && _norm(a.name) == _norm(value),
                    );
                if (clash) {
                  setLocal(() => error = 'Đã có loại tài sản tên này');
                  return;
                }
                Navigator.of(context).pop(value);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (name == null || name.isEmpty || name == asset.name) return;
    await ref
        .read(savingsAssetTypeRepositoryProvider)
        .renameAssetType(asset.id, name);
  }

  Future<void> _createAssetType(List<SavingsAssetType> existing) async {
    final controller = TextEditingController();
    SavingsAssetType? inactiveClash;
    String? error;
    final result = await showDialog<Object?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Thêm loại tài sản tiết kiệm'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('asset_name_field'),
                controller: controller,
                autofocus: true,
                onChanged: (_) => setLocal(() {
                  error = null;
                  inactiveClash = null;
                }),
                decoration: const InputDecoration(
                  labelText: 'Tên (vd Gửi NH 3 tháng, Vàng, USD...)',
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    key: const Key('asset_dup_notice'),
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.expenseAmount,
                    ),
                  ),
                ),
              if (inactiveClash != null)
                TextButton(
                  key: const Key('asset_dup_reuse'),
                  onPressed: () => Navigator.of(context).pop(inactiveClash),
                  child: const Text('Sử dụng lại'),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Huỷ'),
            ),
            FilledButton(
              key: const Key('asset_create_save'),
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) return;
                if (_norm(value) ==
                    _norm(SystemSavingsAssets.unallocated.name)) {
                  setLocal(() => error = 'Đã có loại tài sản tên này');
                  return;
                }
                final clash = existing.where(
                  (a) => _norm(a.name) == _norm(value),
                );
                if (clash.isNotEmpty) {
                  final c = clash.first;
                  setLocal(() {
                    error = c.isActive
                        ? 'Đã có loại tài sản tên này'
                        : 'Loại này đã tồn tại nhưng đang ngừng sử dụng.';
                    inactiveClash = c.isActive ? null : c;
                  });
                  return;
                }
                Navigator.of(context).pop(value);
              },
              child: const Text('Tạo'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final repo = ref.read(savingsAssetTypeRepositoryProvider);
    if (result is SavingsAssetType) {
      await repo.reactivateAssetType(result.id);
      return;
    }
    final color =
        _assetColors[DateTime.now().millisecond % _assetColors.length];
    await repo.addAssetType(
      SavingsAssetType(
        id: IdGenerator.generate(),
        name: result as String,
        color: color,
      ),
    );
  }
}

class _AllocationTile extends StatelessWidget {
  const _AllocationTile({
    required this.row,
    required this.onWithdraw,
    required this.onAllocate,
    required this.onRename,
    required this.onStop,
  });

  final SavingsAllocationRow row;
  final VoidCallback onWithdraw;
  final VoidCallback onAllocate;
  final VoidCallback? onRename;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final name = row.asset?.name ?? 'Loại tài sản khác';
    final hasMoney = row.balance > 0;
    return Container(
      key: Key('savings_row_${row.assetTypeId}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 9,
            backgroundColor: row.asset?.color ?? AppColors.textMuted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (row.isInactive)
                  const Text(
                    'Ngừng sử dụng',
                    key: Key('savings_inactive_tag'),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            Formatters.amount(row.balance),
            key: Key('savings_balance_${row.assetTypeId}'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          PopupMenuButton<String>(
            key: Key('savings_menu_${row.assetTypeId}'),
            icon: const Icon(Icons.more_vert_rounded, size: 20),
            onSelected: (v) {
              switch (v) {
                case 'allocate':
                  onAllocate();
                case 'withdraw':
                  onWithdraw();
                case 'rename':
                  onRename?.call();
                case 'stop':
                  onStop?.call();
              }
            },
            itemBuilder: (context) => [
              if (hasMoney)
                const PopupMenuItem(
                  value: 'allocate',
                  child: Text('Phân bổ / chuyển'),
                ),
              if (hasMoney)
                const PopupMenuItem(
                  value: 'withdraw',
                  child: Text('Rút về số dư'),
                ),
              if (onRename != null)
                const PopupMenuItem(value: 'rename', child: Text('Đổi tên')),
              if (onStop != null)
                const PopupMenuItem(
                  value: 'stop',
                  child: Text('Ngừng sử dụng'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
