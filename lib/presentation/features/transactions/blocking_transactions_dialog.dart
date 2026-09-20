import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/usecases/deletion_check.dart';
import '../../../domain/usecases/transaction_member_label.dart';
import 'transaction_detail_screen.dart';

/// Chuyển danh sách id giao dịch "đang cản" (từ lỗi xóa/sửa làm pool âm) thành
/// [DeletionBlocker] để dùng chung 1 hộp thoại với chặn xóa danh mục/trạng thái.
List<DeletionBlocker> blockersFromTransactionIds(
  Iterable<String> ids,
  Iterable<Transaction> transactions,
  Iterable<Category> categories,
) {
  final byId = {for (final t in transactions) t.id: t};
  final categoryById = {for (final c in categories) c.id: c};
  final statusName = {
    for (final c in categories)
      for (final s in c.statuses) s.id: s.name,
  };
  return [
    for (final id in ids)
      if (byId[id] != null)
        DeletionBlocker(
          kind: DeletionBlockerKind.transaction,
          transactionId: id,
          date: byId[id]!.transactionDate,
          amountMinor: byId[id]!.amountMinor,
          categoryName: categoryById[byId[id]!.categoryId]?.name,
          statusName: byId[id]!.statusId == null
              ? null
              : statusName[byId[id]!.statusId!],
          memberLabel: transactionMemberLabel(byId[id]!),
        ),
  ];
}

/// Hộp thoại "vì sao chưa xóa/sửa được": [message] + từng giao dịch đang cản, mỗi
/// dòng có nút [Mở giao dịch] → mở đúng màn chi tiết giao dịch đó để người dùng
/// tự xử lý.
Future<void> showBlockingTransactions(
  BuildContext context, {
  required String title,
  required String message,
  required List<DeletionBlocker> blockers,
}) async {
  final items = [
    for (final b in blockers)
      if (b.kind == DeletionBlockerKind.transaction) b,
  ];
  final openId = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('blocking_transactions_dialog'),
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 8),
            for (final b in items)
              ListTile(
                key: Key('blocker_${b.transactionId}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                // "20/09/2026 · Chồng" / "300.000 đ" / "Sinh hoạt · Chưa trả".
                title: Text(
                  [
                    Formatters.dayMonthYear(b.date!),
                    if (b.memberLabel != null) b.memberLabel!,
                  ].join(' · '),
                  key: Key('blocker_header_${b.transactionId}'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Formatters.amount(b.amountMinor!),
                      key: Key('blocker_amount_${b.transactionId}'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (b.categoryName != null || b.statusName != null)
                      Text(
                        [
                          if (b.categoryName != null) b.categoryName!,
                          if (b.statusName != null) b.statusName!,
                        ].join(' · '),
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                  ],
                ),
                trailing: TextButton(
                  key: Key('open_blocker_${b.transactionId}'),
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(b.transactionId),
                  child: const Text('Mở giao dịch'),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Đóng'),
        ),
      ],
    ),
  );
  if (openId == null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TransactionDetailScreen(transactionId: openId),
    ),
  );
}
