import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/savings_asset_type.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/entities/transaction_type.dart';
import '../../domain/entities/wallet_identity.dart';
import 'category_label.dart';

/// Một dòng giao dịch dùng chung cho Lịch sử và kết quả Tổng hợp.
/// Ý nghĩa giao dịch đứng trước, ngữ cảnh (ghi chú / thành viên) đứng sau.
class TransactionRow extends StatelessWidget {
  const TransactionRow({
    super.key,
    required this.transaction,
    required this.category,
    required this.onTap,
    this.assetTypes = const [],
    this.members = const [],
    this.showDate = false,
  });

  final Transaction transaction;
  final Category? category;
  final VoidCallback onTap;
  final List<SavingsAssetType> assetTypes;
  final List<FinancialMember> members;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final member = transactionMemberLabel(t, members);
    final savingsLabel = savingsTransferLabel(t, assetTypes);
    final title = savingsLabel ?? categoryDisplayLabel(category);
    final status = category?.statusById(t.statusId)?.name;
    final isIncome = t.type == TransactionType.income;
    final isTransfer = t.type == TransactionType.transfer;
    final color = isTransfer
        ? AppColors.textSecondary
        : isIncome
        ? AppColors.accent
        : AppColors.textPrimary;
    final sign = isTransfer
        ? '⇄'
        : isIncome
        ? '+'
        : '-';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showDate)
              SizedBox(
                width: 42,
                child: Text(
                  Formatters.dayMonth(t.transactionDate),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            Container(
              width: 9,
              height: 9,
              margin: const EdgeInsets.only(top: 5, right: 11),
              decoration: BoxDecoration(
                color: category?.color ?? AppColors.textMuted,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (t.note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        t.note,
                        key: Key('transaction_note_${t.id}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  if (member != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        member,
                        key: Key('transaction_member_${t.id}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  if (status != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        status,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$sign ${Formatters.amount(t.amountMinor)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
