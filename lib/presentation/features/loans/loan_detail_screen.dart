import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/default_categories.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/counterparty.dart';
import '../../../domain/entities/member_directory.dart';
import '../../../domain/entities/obligation.dart';
import '../../../domain/entities/obligation_direction.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/usecases/compute_obligation_summary.dart';
import '../../providers/counterparty_providers.dart';
import '../../providers/member_providers.dart';
import '../../providers/obligation_providers.dart';
import '../../providers/transaction_providers.dart';
import 'loan_error_mapping.dart';
import 'loan_history.dart';
import 'settle_loan_sheet.dart';

/// Phase 8.8 — Chi tiết 1 khoản vay (mục 12/14). Dùng CHUNG cho cả 2 chiều
/// (Receivable/Payable) — chỉ khác nhãn hiển thị, mọi số liệu đọc thẳng từ
/// `computeObligationSummary`/`buildLoanHistory` (KHÔNG tự tính lại — mục
/// 23, Source of truth).
class LoanDetailScreen extends ConsumerWidget {
  const LoanDetailScreen({
    super.key,
    required this.obligationId,
    required this.direction,
  });

  final String obligationId;
  final ObligationDirection direction;

  String get _categoryId => direction == ObligationDirection.receivable
      ? DefaultCategories.choVay.id
      : DefaultCategories.traNo.id;
  String get _interestCategoryId => direction == ObligationDirection.receivable
      ? DefaultCategories.laiChoVay.id
      : DefaultCategories.traNo.id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isReceivable = direction == ObligationDirection.receivable;
    final obligationsAsync = ref.watch(obligationsStreamProvider);
    final counterpartiesAsync = ref.watch(counterpartiesStreamProvider);
    final transactionsAsync = ref.watch(transactionsStreamProvider);

    if (obligationsAsync.isLoading ||
        counterpartiesAsync.isLoading ||
        transactionsAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final error =
        obligationsAsync.error ??
        counterpartiesAsync.error ??
        transactionsAsync.error;
    if (error != null) {
      return Scaffold(body: Center(child: Text('Lỗi tải dữ liệu: $error')));
    }

    final obligations = obligationsAsync.value ?? const <Obligation>[];
    final counterparties = counterpartiesAsync.value ?? const <Counterparty>[];
    final transactions = transactionsAsync.value ?? const [];

    Obligation? obligation;
    for (final o in obligations) {
      if (o.id == obligationId) obligation = o;
    }
    if (obligation == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(isReceivable ? 'Khoản cho vay' : 'Khoản đi vay'),
        ),
        body: const Center(child: Text('Khoản vay không còn tồn tại.')),
      );
    }

    Counterparty? counterparty;
    for (final c in counterparties) {
      if (c.id == obligation.counterpartyId) counterparty = c;
    }

    final summary = computeObligationSummary(obligation, transactions);
    final history = buildLoanHistory(direction, obligationId, transactions);

    if (summary == null || history.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(counterparty?.displayName ?? '—')),
        body: const Center(child: Text('Chưa có dữ liệu cho khoản vay này.')),
      );
    }

    final creationDate = history.first.date;
    final defaultMember =
        _resolveMember(
          ref.read(memberDirectoryProvider),
          direction,
          transactions,
          history.first.anchorTransactionId,
        ) ??
        ref.read(memberDirectoryProvider).defaultMemberId;

    return Scaffold(
      appBar: AppBar(title: Text(counterparty?.displayName ?? '—')),
      floatingActionButton: summary.outstanding > 0
          ? FloatingActionButton.extended(
              onPressed: () => showSettleLoanSheet(
                context,
                direction: direction,
                obligationId: obligationId,
                outstandingBaseline: summary.outstanding,
                categoryId: _categoryId,
                interestCategoryId: _interestCategoryId,
                initialMemberId: defaultMember,
              ),
              icon: const Icon(Icons.add_rounded),
              label: Text(isReceivable ? 'Nhận tiền' : 'Trả tiền'),
            )
          : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          children: [
            _SummaryCard(isReceivable: isReceivable, summary: summary),
            const SizedBox(height: 16),
            _InfoCard(obligation: obligation, creationDate: creationDate),
            const SizedBox(height: 20),
            const Text(
              'Lịch sử',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final entry in history.reversed)
              _HistoryRow(
                isReceivable: isReceivable,
                entry: entry,
                onUndo: () => _undo(context, ref, entry),
                onEdit: entry.isLatestSettlement
                    ? () => _edit(
                        context,
                        ref,
                        direction,
                        obligationId,
                        summary,
                        entry,
                        defaultMember,
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  String? _resolveMember(
    MemberDirectory directory,
    ObligationDirection direction,
    List<Transaction> transactions,
    String creationTransactionId,
  ) {
    Transaction? creation;
    for (final t in transactions) {
      if (t.id == creationTransactionId) creation = t;
    }
    if (creation == null) return null;
    final refId = direction == ObligationDirection.receivable
        ? creation.sourceRefId
        : creation.destinationRefId;
    return directory.contains(refId) ? refId : null;
  }

  Future<void> _undo(
    BuildContext context,
    WidgetRef ref,
    LoanHistoryEntry entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận hoàn tác'),
        content: Text(
          direction == ObligationDirection.receivable
              ? 'Hoàn tác lần nhận tiền ${Formatters.amount(entry.amountMinor)}?'
              : 'Hoàn tác lần trả tiền ${Formatters.amount(entry.amountMinor)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huỷ'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hoàn tác'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(reverseObligationSettlementUseCaseProvider)(
        entry.anchorTransactionId,
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(mapLoanError(error))));
      }
    }
  }

  void _edit(
    BuildContext context,
    WidgetRef ref,
    ObligationDirection direction,
    String obligationId,
    ObligationSummary summary,
    LoanHistoryEntry entry,
    String? defaultMember,
  ) {
    showSettleLoanSheet(
      context,
      direction: direction,
      obligationId: obligationId,
      // Khôi phục outstanding TRƯỚC lần tất toán đang sửa — cộng lại đúng
      // phần gốc của chính lần đó (đã đọc thẳng từ ledger, không tự suy).
      outstandingBaseline:
          summary.outstanding + (entry.principalPortion ?? entry.amountMinor),
      categoryId: _categoryId,
      interestCategoryId: _interestCategoryId,
      initialMemberId: defaultMember,
      correctingAnchorTransactionId: entry.anchorTransactionId,
      initialAmountMinor: entry.amountMinor,
      initialDate: entry.date,
      initialNote: entry.note,
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.isReceivable, required this.summary});

  final bool isReceivable;
  final ObligationSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
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
          _Row(
            label: isReceivable ? 'Cho vay ban đầu' : 'Đã vay',
            value: summary.originalPrincipal,
          ),
          _Row(
            label: isReceivable ? 'Đã thu' : 'Đã trả',
            value: summary.totalPrincipalSettled,
          ),
          _Row(
            label: isReceivable ? 'Còn phải thu' : 'Còn phải trả',
            value: summary.outstanding,
            emphasize: true,
          ),
          _Row(
            label: isReceivable ? 'Lãi đã nhận' : 'Chi phí lãi',
            value: summary.totalInterest,
          ),
          if (summary.outstanding <= 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.chipBackground,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Đã tất toán',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final int value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
              color: emphasize
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
            ),
          ),
          Text(
            Formatters.amount(value),
            style: TextStyle(
              fontSize: emphasize ? 16 : 13.5,
              fontWeight: FontWeight.w800,
              color: emphasize ? AppColors.accent : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.obligation, required this.creationDate});

  final Obligation obligation;
  final DateTime creationDate;

  @override
  Widget build(BuildContext context) {
    final overdue =
        obligation.dueDate != null &&
        obligation.dueDate!.isBefore(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
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
          _InfoLine(
            label: 'Ngày',
            value: Formatters.dayMonthYear(creationDate),
          ),
          if (obligation.dueDate != null)
            _InfoLine(
              label: 'Hạn trả',
              value: Formatters.dayMonthYear(obligation.dueDate!),
              valueColor: overdue ? AppColors.expenseAmount : null,
            ),
          if (obligation.note.isNotEmpty)
            _InfoLine(label: 'Ghi chú', value: obligation.note),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.isReceivable,
    required this.entry,
    required this.onUndo,
    required this.onEdit,
  });

  final bool isReceivable;
  final LoanHistoryEntry entry;
  final VoidCallback onUndo;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final isCreation = entry.kind == LoanHistoryEntryKind.creation;
    final label = isCreation
        ? (isReceivable ? 'Cho vay' : 'Đi vay')
        : (isReceivable ? 'Đã nhận' : 'Đã trả');

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              Formatters.dayMonthYear(entry.date),
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (entry.interestPortion != null)
                  Text(
                    'Gồm gốc ${Formatters.amount(entry.principalPortion!)} + lãi ${Formatters.amount(entry.interestPortion!)}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textMuted,
                    ),
                  )
                else if (entry.note.isNotEmpty)
                  Text(
                    entry.note,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            Formatters.amount(entry.amountMinor),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          if (!isCreation)
            PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_vert_rounded,
                size: 18,
                color: AppColors.textMuted,
              ),
              onSelected: (value) {
                if (value == 'undo') onUndo();
                if (value == 'edit') onEdit?.call();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'undo',
                  child: Text(
                    isReceivable
                        ? 'Hoàn tác lần nhận tiền'
                        : 'Hoàn tác lần trả tiền',
                  ),
                ),
                if (onEdit != null)
                  const PopupMenuItem(value: 'edit', child: Text('Sửa')),
              ],
            ),
        ],
      ),
    );
  }
}
