import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../domain/usecases/deletion_check.dart';
import '../features/transactions/blocking_transactions_dialog.dart';

/// Câu giải thích DỄ HIỂU vì sao 1 mục dữ liệu do gia đình tạo (danh mục, quỹ,
/// loại tiết kiệm…) chưa xóa hẳn được — dùng chung để mọi màn cư xử giống nhau.
/// Không lộ thuật ngữ kỹ thuật (pool, ledger, id…).
String deletionReasonText(
  DeletionCheckResult check, {
  String noun = 'mục này',
}) {
  if (check.isSystemProtected) {
    return 'Đây là mục hệ thống của ứng dụng nên không thể xóa.';
  }
  final parts = <String>[];
  final balance = check.remainingBalance;
  if (balance != null) {
    parts.add(
      'Vẫn còn ${Formatters.amount(balance)} — hãy rút hoặc chuyển đi trước.',
    );
  }
  final n = check.transactionBlockers.length;
  if (n > 0) parts.add('Đang được sử dụng bởi $n giao dịch.');
  if (check.hasHiddenHistory && parts.isEmpty) {
    parts.add('Còn giao dịch đã xóa/sửa trước đây (đang ẩn).');
  }
  if (parts.isEmpty) return '';
  return 'Chưa thể xóa $noun. ${parts.join(' ')}';
}

/// 1 dòng trong khu "Ngừng sử dụng" của Quỹ / Loại tiết kiệm: [Sử dụng lại],
/// [Xem giao dịch] (nếu có giao dịch đang giữ → mở từng giao dịch để sửa/xóa) và
/// [Xóa hẳn] CHỈ khi an toàn. Trạng thái suy ra từ [check] (dữ liệu hiện tại)
/// nên tự cập nhật ngay khi quay lại từ màn giao dịch.
class StoppedItemTile extends StatelessWidget {
  const StoppedItemTile({
    super.key,
    required this.idKey,
    required this.name,
    required this.color,
    required this.check,
    required this.noun,
    required this.onReuse,
    required this.onDelete,
  });

  /// Dùng để dựng key ổn định cho các nút (`reuse_<idKey>`, `delete_<idKey>`,
  /// `blockers_<idKey>`).
  final String idKey;
  final String name;
  final Color color;
  final DeletionCheckResult check;
  final String noun;
  final VoidCallback onReuse;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final reason = deletionReasonText(check, noun: noun);
    final hasBlockingTransactions = check.transactionBlockers.isNotEmpty;
    return ListTile(
      key: Key('stopped_$idKey'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: CircleAvatar(radius: 9, backgroundColor: color),
      title: Text(name, style: const TextStyle(color: AppColors.textMuted)),
      subtitle: reason.isEmpty
          ? null
          : Text(reason, style: const TextStyle(fontSize: 11.5)),
      trailing: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton(
            key: Key('reuse_$idKey'),
            onPressed: onReuse,
            child: const Text('Sử dụng lại'),
          ),
          if (hasBlockingTransactions)
            TextButton(
              key: Key('blockers_$idKey'),
              onPressed: () => showBlockingTransactions(
                context,
                title: 'Chưa thể xóa "$name"',
                message: reason,
                blockers: check.blockers,
              ),
              child: const Text('Xem giao dịch'),
            ),
          if (check.canDelete)
            TextButton(
              key: Key('delete_$idKey'),
              onPressed: onDelete,
              child: const Text(
                'Xóa hẳn',
                style: TextStyle(color: AppColors.expenseAmount),
              ),
            ),
        ],
      ),
    );
  }
}
