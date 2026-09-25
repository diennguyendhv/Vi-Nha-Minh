import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/pool_kind.dart';
import '../../domain/entities/savings_asset_type.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/entities/transaction_type.dart';
import '../../domain/entities/transfer_kind.dart';
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
    final locale = Localizations.localeOf(context).toLanguageTag();
    final t = transaction;
    final member = transactionMemberLabel(t, members);
    final title = transactionPrimaryLabel(t, category, assetTypes);
    final contextLabel = transactionContextLabel(t, members, assetTypes);
    final secondary = contextLabel ?? member;
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
                  if (secondary != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        secondary,
                        key: Key('transaction_member_${t.id}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.history,
                          size: 13,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            DateFormat(
                              'dd/MM/yyyy HH:mm:ss',
                              locale,
                            ).format(t.createdAt.toLocal()),
                            key: Key('transaction_created_at_${t.id}'),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      ],
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

String transactionPrimaryLabel(
  Transaction t,
  Category? category,
  Iterable<SavingsAssetType> assetTypes,
) {
  final savings = savingsTransferLabel(t, assetTypes);
  if (savings != null) return savings;
  switch (t.transferKind) {
    case TransferKind.fundTopup:
      return 'Nạp quỹ';
    case TransferKind.fundWithdraw:
      return 'Rút từ quỹ';
    case TransferKind.memberToMember:
      return 'Chuyển tiền thành viên';
    default:
      return categoryDisplayLabel(category);
  }
}

String? transactionContextLabel(
  Transaction t,
  Iterable<FinancialMember> members,
  Iterable<SavingsAssetType> assetTypes,
) {
  String poolLabel(PoolKind kind, String? refId) {
    if (kind == PoolKind.memberAvailable) {
      return members.where((m) => m.memberId == refId).firstOrNull?.label ??
          'Ví';
    }
    if (kind == PoolKind.memberSavingsAsset && refId != null) {
      final parsed = parseSavingsAssetRefId(refId);
      final asset = parsed == null
          ? null
          : resolveSavingsAsset(parsed.assetTypeId, assetTypes);
      final member = parsed == null
          ? null
          : members.where((m) => m.memberId == parsed.memberId).firstOrNull;
      return '${member?.label ?? 'Thành viên'} · ${asset?.name ?? 'Tiết kiệm'}';
    }
    if (kind == PoolKind.fund) return 'Quỹ';
    if (kind == PoolKind.receivable) return 'Khoản vay';
    return 'Bên ngoài';
  }

  if (t.type == TransactionType.transfer) {
    return '${poolLabel(t.sourceKind, t.sourceRefId)} → '
        '${poolLabel(t.destinationKind, t.destinationRefId)}';
  }
  if (t.sourceKind == PoolKind.fund) return 'Chi từ Quỹ';
  return null;
}
