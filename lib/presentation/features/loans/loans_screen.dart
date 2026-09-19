import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/engine/obligation_settlement.dart';
import '../../../domain/entities/counterparty.dart';
import '../../../domain/entities/obligation.dart';
import '../../../domain/entities/obligation_direction.dart';
import '../../../domain/usecases/compute_obligation_summary.dart';
import '../../providers/counterparty_providers.dart';
import '../../providers/obligation_providers.dart';
import '../../providers/transaction_providers.dart';
import 'create_loan_sheet.dart';
import 'loan_detail_screen.dart';

enum _StatusFilter { open, settled, all }

/// Phase 8.8 — màn "Vay & Cho vay" (product language — KHÔNG dùng
/// Receivable/Payable/Obligation trong UI, xem `docs/financial-core-v2.md`
/// audit Phase 8.8 mục 2). Entry point mới, KHÔNG đổi bottom navigation
/// (audit mục 3) — mở qua `Navigator.push` từ Trang chủ, cùng pattern
/// `FundListScreen`/`SettingsScreen`.
class LoansScreen extends ConsumerStatefulWidget {
  const LoansScreen({
    super.key,
    this.initialDirection = ObligationDirection.receivable,
  });

  final ObligationDirection initialDirection;

  @override
  ConsumerState<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends ConsumerState<LoansScreen> {
  late ObligationDirection _direction = widget.initialDirection;
  _StatusFilter _filter = _StatusFilter.open;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final obligationsAsync = ref.watch(obligationsStreamProvider);
    final transactionsAsync = ref.watch(transactionsStreamProvider);
    final counterpartyListAsync = ref.watch(counterpartiesStreamProvider);

    if (obligationsAsync.isLoading ||
        transactionsAsync.isLoading ||
        counterpartyListAsync.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Vay & Cho vay')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final error =
        obligationsAsync.error ??
        transactionsAsync.error ??
        counterpartyListAsync.error;
    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Vay & Cho vay')),
        body: Center(child: Text('Lỗi tải dữ liệu: $error')),
      );
    }

    final obligations = obligationsAsync.value ?? const <Obligation>[];
    final transactions = transactionsAsync.value ?? const [];
    final counterparties =
        counterpartyListAsync.value ?? const <Counterparty>[];
    final counterpartyById = {for (final c in counterparties) c.id: c};

    final rows =
        <
          ({
            Obligation obligation,
            ObligationSummary summary,
            Counterparty counterparty,
            DateTime creationDate,
          })
        >[];
    for (final o in obligations) {
      if (o.direction != _direction) continue;
      final summary = computeObligationSummary(o, transactions);
      if (summary == null) continue; // chưa từng ghi giao dịch gốc — chưa hiện.
      final counterparty = counterpartyById[o.counterpartyId];
      if (counterparty == null) continue;
      final creation = findObligationCreationTransaction(
        o.direction,
        o.id,
        transactions,
      );
      if (creation == null) continue;
      rows.add((
        obligation: o,
        summary: summary,
        counterparty: counterparty,
        creationDate: creation.transactionDate,
      ));
    }

    final filtered =
        rows
            .where((r) {
              switch (_filter) {
                case _StatusFilter.open:
                  return r.summary.outstanding > 0;
                case _StatusFilter.settled:
                  return r.summary.outstanding <= 0;
                case _StatusFilter.all:
                  return true;
              }
            })
            .where((r) {
              if (_query.trim().isEmpty) return true;
              final q = _query.trim().toLowerCase();
              return r.counterparty.displayName.toLowerCase().contains(q) ||
                  r.obligation.note.toLowerCase().contains(q);
            })
            .toList()
          // Mới nhất trước — theo ngày tạo khoản vay, giống quy ước danh sách
          // giao dịch/Trang chủ (mới nhất lên đầu).
          ..sort((a, b) => b.creationDate.compareTo(a.creationDate));

    final totalOutstandingShown = filtered.fold<int>(
      0,
      (s, r) => s + r.summary.outstanding,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Vay & Cho vay')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCreateLoanSheet(context, direction: _direction),
        icon: const Icon(Icons.add_rounded),
        label: Text(
          _direction == ObligationDirection.receivable ? 'Cho vay' : 'Đi vay',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          children: [
            SegmentedButton<ObligationDirection>(
              segments: const [
                ButtonSegment(
                  value: ObligationDirection.receivable,
                  label: Text('Người khác nợ mình'),
                ),
                ButtonSegment(
                  value: ObligationDirection.payable,
                  label: Text('Mình đang nợ'),
                ),
              ],
              selected: {_direction},
              onSelectionChanged: (s) => setState(() => _direction = s.first),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('loans_search'),
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Tìm theo tên người vay/cho vay...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                filled: true,
                fillColor: AppColors.chipBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() {
                          _searchController.clear();
                          _query = '';
                        }),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                _FilterChip(
                  label: 'Đang còn',
                  selected: _filter == _StatusFilter.open,
                  onTap: () => setState(() => _filter = _StatusFilter.open),
                ),
                _FilterChip(
                  label: 'Đã tất toán',
                  selected: _filter == _StatusFilter.settled,
                  onTap: () => setState(() => _filter = _StatusFilter.settled),
                ),
                _FilterChip(
                  label: 'Tất cả',
                  selected: _filter == _StatusFilter.all,
                  onTap: () => setState(() => _filter = _StatusFilter.all),
                ),
              ],
            ),
            if (_filter == _StatusFilter.open && filtered.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _direction == ObligationDirection.receivable
                    ? 'Tổng còn phải thu: ${Formatters.amount(totalOutstandingShown)}'
                    : 'Tổng còn phải trả: ${Formatters.amount(totalOutstandingShown)}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    obligations.where((o) => o.direction == _direction).isEmpty
                        ? (_direction == ObligationDirection.receivable
                              ? 'Chưa có khoản cho vay nào — bấm "Cho vay" để ghi khoản đầu tiên.'
                              : 'Chưa có khoản đi vay nào — bấm "Đi vay" để ghi khoản đầu tiên.')
                        : 'Không tìm thấy khoản nào khớp.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              )
            else
              for (final row in filtered) ...[
                _LoanCard(
                  direction: _direction,
                  obligation: row.obligation,
                  counterparty: row.counterparty,
                  summary: row.summary,
                  creationDate: row.creationDate,
                ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.accent.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: selected ? AppColors.accent : AppColors.textSecondary,
      ),
      backgroundColor: AppColors.chipBackground,
      side: BorderSide.none,
    );
  }
}

class _LoanCard extends StatelessWidget {
  const _LoanCard({
    required this.direction,
    required this.obligation,
    required this.counterparty,
    required this.summary,
    required this.creationDate,
  });

  final ObligationDirection direction;
  final Obligation obligation;
  final Counterparty counterparty;
  final ObligationSummary summary;
  final DateTime creationDate;

  @override
  Widget build(BuildContext context) {
    final isReceivable = direction == ObligationDirection.receivable;
    final receivedOrPaid =
        summary.totalPrincipalSettled + summary.totalInterest;
    final overdue = summary.isOverdue(obligation.dueDate, DateTime.now());

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LoanDetailScreen(
            obligationId: obligation.id,
            direction: direction,
          ),
        ),
      ),
      child: Container(
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    counterparty.displayName,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _StatusBadge(status: summary.status, overdue: overdue),
              ],
            ),
            const SizedBox(height: 10),
            _AmountRow(label: 'Ban đầu', value: summary.originalPrincipal),
            _AmountRow(
              label: isReceivable ? 'Đã nhận' : 'Đã trả',
              value: receivedOrPaid,
            ),
            _AmountRow(
              label: isReceivable ? 'Còn phải thu' : 'Còn phải trả',
              value: summary.outstanding,
              emphasize: true,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  Formatters.dayMonthYear(creationDate),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
                if (obligation.dueDate != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    'Hạn trả: ${Formatters.dayMonthYear(obligation.dueDate!)}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: overdue
                          ? AppColors.expenseAmount
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
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
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: emphasize
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          Text(
            Formatters.amount(value),
            style: TextStyle(
              fontSize: emphasize ? 14 : 12.5,
              fontWeight: FontWeight.w800,
              color: emphasize ? AppColors.accent : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.overdue});

  final ObligationStatus status;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color color;
    if (overdue) {
      label = 'Quá hạn';
      color = AppColors.expenseAmount;
    } else {
      switch (status) {
        case ObligationStatus.open:
          label = 'Đang còn';
          color = AppColors.textSecondary;
        case ObligationStatus.partiallySettled:
          label = 'Đã thu/trả một phần';
          color = AppColors.accent;
        case ObligationStatus.settled:
          label = 'Đã tất toán';
          color = AppColors.textMuted;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
