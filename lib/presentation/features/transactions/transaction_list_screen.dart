import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../providers/category_providers.dart';
import '../../providers/transaction_providers.dart';
import 'transaction_detail_screen.dart';

/// Màn "Danh sách" (`docs/design.html` màn 10) — nhóm theo ngày kèm tổng
/// ngày, chuyển tháng bằng mũi tên (phase 9). Chỉ hiện transaction đang
/// hiệu lực (`isVisible`).
class TransactionListScreen extends ConsumerStatefulWidget {
  const TransactionListScreen({super.key});

  @override
  ConsumerState<TransactionListScreen> createState() => _TransactionListScreenState();
}

class _TransactionListScreenState extends ConsumerState<TransactionListScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(transactionsStreamProvider).valueOrNull ?? [];
    final categories = ref.watch(categoriesStreamProvider).valueOrNull ?? [];
    final categoryById = {for (final c in categories) c.id: c};

    final inMonth = transactions
        .where(
          (t) =>
              isVisible(t) &&
              t.transactionDate.year == _month.year &&
              t.transactionDate.month == _month.month,
        )
        .toList()
      ..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));

    // STT theo đúng thứ tự thời gian ghi trong tháng (cũ nhất = 1), dù danh
    // sách hiển thị mới nhất lên đầu — khớp cách đánh số 1 sổ ghi chép thật.
    final chronological = [...inMonth]..sort((a, b) => a.transactionDate.compareTo(b.transactionDate));
    final sttById = {for (var i = 0; i < chronological.length; i++) chronological[i].id: i + 1};

    final grouped = <DateTime, List<Transaction>>{};
    for (final t in inMonth) {
      final day = DateTime(
        t.transactionDate.year,
        t.transactionDate.month,
        t.transactionDate.day,
      );
      (grouped[day] ??= []).add(t);
    }
    final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(title: const Text('Giao dịch')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () => _shiftMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  'Tháng ${_month.month}, ${_month.year}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                IconButton(
                  onPressed: () => _shiftMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          Expanded(
            child: days.isEmpty
                ? const Center(
                    child: Text(
                      'Không có giao dịch nào trong tháng này.',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: days.length,
                    itemBuilder: (context, i) {
                      final day = days[i];
                      final dayTransactions = grouped[day]!;
                      final dayTotal = dayTransactions.fold<int>(
                        0,
                        (sum, t) => sum + _signedAmount(t),
                      );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  Formatters.dayMonth(day),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                                Text(
                                  Formatters.amount(dayTotal),
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                            for (final t in dayTransactions)
                              _TransactionTile(
                                transaction: t,
                                category: categoryById[t.categoryId],
                                stt: sttById[t.id],
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

int _signedAmount(Transaction t) {
  return switch (t.type) {
    TransactionType.income => t.amountMinor,
    TransactionType.expense => -t.amountMinor,
    TransactionType.transfer => 0,
  };
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.transaction, required this.category, this.stt});

  final Transaction transaction;
  final Category? category;

  /// Số thứ tự theo thời gian ghi trong tháng — chỉ để hiển thị, không
  /// lưu vào `Transaction` (tính lại mỗi lần render từ danh sách hiện có).
  final int? stt;

  @override
  Widget build(BuildContext context) {
    final signed = _signedAmount(transaction);
    final color = signed > 0
        ? AppColors.accent
        : (signed < 0 ? AppColors.textPrimary : AppColors.textSecondary);
    final sign = signed > 0 ? '+' : (signed < 0 ? '-' : '⇄');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: category?.color ?? AppColors.textMuted,
        child: Text(
          (category?.name.isNotEmpty ?? false) ? category!.name.substring(0, 1) : '?',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
      title: Text('${stt != null ? '$stt. ' : ''}${category?.name ?? 'Đã xoá danh mục'}'),
      subtitle: transaction.note.isEmpty ? null : Text(transaction.note),
      trailing: Text(
        '$sign ${Formatters.amount(transaction.amountMinor)}',
        style: TextStyle(fontWeight: FontWeight.w800, color: color),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TransactionDetailScreen(transactionId: transaction.id),
        ),
      ),
    );
  }
}
