import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/advanced_system_categories.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/family_member.dart';
import '../../../domain/entities/status.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../../domain/usecases/compute_grouped_totals.dart';
import '../../../domain/usecases/compute_status_breakdown.dart';
import '../../../domain/usecases/explore_transactions.dart';
import '../../providers/category_providers.dart';
import '../../providers/transaction_providers.dart';
import '../../widgets/category_label.dart';
import '../transactions/transaction_detail_screen.dart';

enum _TimePreset { today, thisMonth, lastMonth, custom }

/// Màn "Tổng hợp" — SIMPLE AT FIRST GLANCE, POWERFUL WHEN DRILLING DOWN.
///
/// Mặc định chỉ có: Thu nhập ròng THÁNG NÀY của Vợ, của Chồng và Chi tiêu gia
/// đình. Bên dưới là **Transaction Explorer**: mọi giao dịch đang hiệu lực,
/// lọc kết hợp (AND) theo Thời gian · Thành viên · Nhóm chính · Danh mục ·
/// Trạng thái · Tìm trong Ghi chú, kèm tổng của CHÍNH tập đang xem.
///
/// Không có logic báo cáo thứ hai: số Thu nhập ròng lấy từ
/// [computeMemberNetIncome], lọc/tổng lấy từ [exploreTransactions].
class SummaryScreen extends ConsumerStatefulWidget {
  const SummaryScreen({super.key});

  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen> {
  final _searchController = TextEditingController();
  _TimePreset _preset = _TimePreset.thisMonth;
  late TransactionFilter _filter = _rangeFor(_TimePreset.thisMonth, null);
  bool _showAdvanced = false;

  static final _hidden = AdvancedSystemCategories.ids;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  TransactionFilter _rangeFor(
    _TimePreset preset,
    DateTimeRange? custom, [
    TransactionFilter? base,
  ]) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime from;
    DateTime to;
    switch (preset) {
      case _TimePreset.today:
        from = today;
        to = today;
      case _TimePreset.thisMonth:
        from = DateTime(now.year, now.month);
        to = DateTime(now.year, now.month + 1, 0);
      case _TimePreset.lastMonth:
        from = DateTime(now.year, now.month - 1);
        to = DateTime(now.year, now.month, 0);
      case _TimePreset.custom:
        from = custom!.start;
        to = custom.end;
    }
    return (base ?? const TransactionFilter()).withRange(from, to);
  }

  void _setPreset(_TimePreset preset) {
    setState(() {
      _preset = preset;
      _filter = _rangeFor(preset, null, _filter);
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(
        start: _filter.from ?? DateTime(now.year, now.month),
        end: _filter.to ?? now,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _preset = _TimePreset.custom;
      _filter = _rangeFor(_TimePreset.custom, picked, _filter);
    });
  }

  bool get _isDefaultFilter =>
      _preset == _TimePreset.thisMonth && !_filter.hasNonDateFilter;

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _preset = _TimePreset.thisMonth;
      _filter = _rangeFor(_TimePreset.thisMonth, null);
      _showAdvanced = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final transactionsAsync = ref.watch(transactionsStreamProvider);
    final categoriesAsync = ref.watch(categoriesStreamProvider);

    if (transactionsAsync.isLoading || categoriesAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = transactionsAsync.error ?? categoriesAsync.error;
    if (error != null) return Center(child: Text('Lỗi tải dữ liệu: $error'));

    final transactions = transactionsAsync.value ?? const <Transaction>[];
    final categories = categoriesAsync.value ?? const <Category>[];
    final categoryById = {for (final c in categories) c.id: c};
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);

    final netVo = computeMemberNetIncome(
      FamilyMember.vo,
      transactions,
      categories,
      month: month,
    );
    final netChong = computeMemberNetIncome(
      FamilyMember.chong,
      transactions,
      categories,
      month: month,
    );
    final spending = computeGroupedTotals(
      transactions,
      categories,
      month: month,
    ).spending;

    final result = exploreTransactions(
      transactions,
      categories,
      _filter,
      hiddenCategoryIds: _hidden,
    );
    final statsCategories = categories.where((c) => c.statsEnabled).toList();

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const Text(
                'Tổng hợp',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _NetIncomeCard(
                      key: const Key('summary_net_vo'),
                      label: 'Vợ · Thu nhập ròng',
                      month: now.month,
                      value: netVo,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _NetIncomeCard(
                      key: const Key('summary_net_chong'),
                      label: 'Chồng · Thu nhập ròng',
                      month: now.month,
                      value: netChong,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _SpendingCard(
                key: const Key('summary_household_spending'),
                month: now.month,
                value: spending,
              ),
              if (statsCategories.isNotEmpty) ...[
                const SizedBox(height: 6),
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    key: const Key('summary_status_section'),
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'Tổng theo trạng thái',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    children: [
                      for (final category in statsCategories) ...[
                        _StatusCard(
                          category: category,
                          breakdown: computeStatusBreakdown(
                            transactions,
                            category,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const Text(
                'Giao dịch',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              _MemberChips(
                selected: _filter.member,
                onChanged: (m) =>
                    setState(() => _filter = _filter.withMember(m)),
              ),
              const SizedBox(height: 8),
              _TimeChips(
                preset: _preset,
                filter: _filter,
                onPreset: _setPreset,
                onCustom: _pickCustomRange,
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('summary_search'),
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  hintText: 'Tìm trong ghi chú',
                  border: const OutlineInputBorder(),
                  suffixIcon: _filter.query.isEmpty
                      ? null
                      : IconButton(
                          key: const Key('summary_search_clear'),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _filter = _filter.withQuery(''));
                          },
                        ),
                ),
                onChanged: (v) =>
                    setState(() => _filter = _filter.withQuery(v)),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  TextButton.icon(
                    key: const Key('summary_filter_toggle'),
                    onPressed: () =>
                        setState(() => _showAdvanced = !_showAdvanced),
                    icon: Icon(
                      _showAdvanced
                          ? Icons.expand_less_rounded
                          : Icons.tune_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _filter.advancedCount == 0
                          ? 'Bộ lọc'
                          : 'Bộ lọc (${_filter.advancedCount})',
                    ),
                  ),
                  const Spacer(),
                  if (!_isDefaultFilter)
                    TextButton(
                      key: const Key('summary_clear_filters'),
                      onPressed: _clearFilters,
                      child: const Text('Xóa bộ lọc'),
                    ),
                ],
              ),
              if (_showAdvanced)
                _AdvancedFilters(
                  filter: _filter,
                  usedStatusIds: {
                    for (final t in transactions)
                      if (t.statusId != null &&
                          t.categoryId == _filter.categoryId)
                        t.statusId!,
                  },
                  categories: categories,
                  categoryById: categoryById,
                  hidden: _hidden,
                  onChanged: (f) => setState(() => _filter = f),
                ),
              const SizedBox(height: 6),
              _ResultHeader(
                key: const Key('summary_result_header'),
                result: result,
                filter: _filter,
              ),
              const SizedBox(height: 4),
            ]),
          ),
        ),
        if (result.rows.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
              child: Column(
                key: const Key('summary_empty'),
                children: [
                  const Text(
                    'Không tìm thấy giao dịch',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const Key('summary_empty_clear'),
                    onPressed: _clearFilters,
                    child: const Text('Xóa bộ lọc'),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.builder(
              itemCount: result.rows.length,
              itemBuilder: (context, i) {
                final t = result.rows[i];
                return _ExplorerRow(
                  key: ValueKey(t.id),
                  transaction: t,
                  category: categoryById[t.categoryId],
                );
              },
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _NetIncomeCard extends StatelessWidget {
  const _NetIncomeCard({
    super.key,
    required this.label,
    required this.month,
    required this.value,
  });

  final String label;
  final int month;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            Formatters.amount(value),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          Text(
            'Tháng $month',
            style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _SpendingCard extends StatelessWidget {
  const _SpendingCard({super.key, required this.month, required this.value});

  final int month;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Chi tiêu gia đình · tháng $month',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            Formatters.amount(value),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _cardDecoration() => BoxDecoration(
  color: AppColors.surface,
  borderRadius: BorderRadius.circular(16),
  boxShadow: [
    BoxShadow(
      color: AppColors.shadow,
      blurRadius: 12,
      offset: const Offset(0, 3),
    ),
  ],
);

class _MemberChips extends StatelessWidget {
  const _MemberChips({required this.selected, required this.onChanged});

  final FamilyMember? selected;
  final ValueChanged<FamilyMember?> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String keyName, String label, FamilyMember? value) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          key: Key('summary_member_$keyName'),
          label: Text(label),
          selected: selected == value,
          onSelected: (_) => onChanged(value),
        ),
      );
    }

    return Row(
      children: [
        chip('all', 'Tất cả', null),
        chip('vo', 'Vợ', FamilyMember.vo),
        chip('chong', 'Chồng', FamilyMember.chong),
      ],
    );
  }
}

class _TimeChips extends StatelessWidget {
  const _TimeChips({
    required this.preset,
    required this.filter,
    required this.onPreset,
    required this.onCustom,
  });

  final _TimePreset preset;
  final TransactionFilter filter;
  final ValueChanged<_TimePreset> onPreset;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    Widget chip(String keyName, String label, _TimePreset value) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          key: Key('summary_time_$keyName'),
          label: Text(label),
          selected: preset == value,
          onSelected: (_) => onPreset(value),
        ),
      );
    }

    final customLabel = preset == _TimePreset.custom && filter.from != null
        ? '${Formatters.dayMonth(filter.from!)} – ${Formatters.dayMonth(filter.to ?? filter.from!)}'
        : 'Tuỳ chọn';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('today', 'Hôm nay', _TimePreset.today),
          chip('this_month', 'Tháng này', _TimePreset.thisMonth),
          chip('last_month', 'Tháng trước', _TimePreset.lastMonth),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              key: const Key('summary_time_custom'),
              avatar: const Icon(Icons.date_range_rounded, size: 16),
              label: Text(customLabel),
              selected: preset == _TimePreset.custom,
              onSelected: (_) => onCustom(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Nhóm chính → Danh mục → Trạng thái. Đổi nhóm/danh mục tự xoá lựa chọn cũ
/// không còn hợp lệ (logic nằm trong [TransactionFilter], được test riêng).
class _AdvancedFilters extends StatelessWidget {
  const _AdvancedFilters({
    required this.filter,
    required this.usedStatusIds,
    required this.categories,
    required this.categoryById,
    required this.hidden,
    required this.onChanged,
  });

  final TransactionFilter filter;

  /// Trạng thái đang có giao dịch (kể cả giao dịch đã bị ẩn/hoàn tác) — bước
  /// đã ngừng sử dụng chỉ được liệt kê khi còn lịch sử dùng nó.
  final Set<String> usedStatusIds;
  final List<Category> categories;
  final Map<String, Category> categoryById;
  final Set<String> hidden;
  final ValueChanged<TransactionFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final options =
        categories.where((c) {
          if (hidden.contains(c.id)) return false;
          if (filter.group == null) return true;
          return categoryGroupOf(c, hidden) == filter.group;
        }).toList()..sort((a, b) {
          if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
          return a.name.compareTo(b.name);
        });
    final selectedCategory = filter.categoryId == null
        ? null
        : categoryById[filter.categoryId];
    final statuses = [
      for (final s in selectedCategory?.statuses ?? const <Status>[])
        if (s.isActive || usedStatusIds.contains(s.id)) s,
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.chipBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nhóm',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ChoiceChip(
                key: const Key('summary_group_all'),
                label: const Text('Tất cả'),
                selected: filter.group == null,
                onSelected: (_) => onChanged(
                  filter.withGroup(
                    null,
                    categoryById,
                    hiddenCategoryIds: hidden,
                  ),
                ),
              ),
              for (final g in MainGroup.values)
                ChoiceChip(
                  key: Key('summary_group_${g.name}'),
                  label: Text(g.label),
                  selected: filter.group == g,
                  onSelected: (_) => onChanged(
                    filter.withGroup(
                      g,
                      categoryById,
                      hiddenCategoryIds: hidden,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Danh mục',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String?>(
            key: ValueKey(
              'summary_category_${filter.group?.name}_${filter.categoryId}',
            ),
            initialValue: options.any((c) => c.id == filter.categoryId)
                ? filter.categoryId
                : null,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Tất cả danh mục'),
              ),
              for (final c in options)
                DropdownMenuItem<String?>(
                  value: c.id,
                  child: Text(c.isActive ? c.name : '${c.name} (đã ngừng)'),
                ),
            ],
            onChanged: (v) => onChanged(filter.withCategory(v, categoryById)),
          ),
          if (statuses.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Trạng thái',
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  key: const Key('summary_status_all'),
                  label: const Text('Tất cả'),
                  selected: filter.statusId == null,
                  onSelected: (_) => onChanged(filter.withStatus(null)),
                ),
                for (final s in statuses)
                  ChoiceChip(
                    key: Key('summary_status_${s.id}'),
                    label: Text(s.isActive ? s.name : '${s.name} (đã ẩn)'),
                    selected: filter.statusId == s.id,
                    onSelected: (_) => onChanged(filter.withStatus(s.id)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// "27 giao dịch · 01/09 – 30/09" + Thu/Chi của CHÍNH tập đang xem (không
/// gộp thành một con số mơ hồ; Chuyển không tính vào Thu/Chi).
class _ResultHeader extends StatelessWidget {
  const _ResultHeader({super.key, required this.result, required this.filter});

  final ExplorerResult result;
  final TransactionFilter filter;

  @override
  Widget build(BuildContext context) {
    final range = filter.from == null
        ? 'Mọi ngày'
        : (filter.to == null || filter.from == filter.to)
        ? Formatters.dayMonth(filter.from!)
        : '${Formatters.dayMonth(filter.from!)} – ${Formatters.dayMonth(filter.to!)}';
    final parts = <String>[
      if (result.inflow > 0) 'Thu ${Formatters.amount(result.inflow)}',
      if (result.outflow > 0) 'Chi ${Formatters.amount(result.outflow)}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${result.count} giao dịch · $range',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        if (parts.isNotEmpty)
          Text(
            parts.join('   ·   '),
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
          ),
      ],
    );
  }
}

/// Dòng giao dịch: ngày · Vợ/Chồng · Nhóm · Danh mục · số tiền · ghi chú ·
/// trạng thái. Chuyển hiện đời thường ("Vợ → Chồng"). Không lộ enum/pool/cờ.
class _ExplorerRow extends StatelessWidget {
  const _ExplorerRow({
    super.key,
    required this.transaction,
    required this.category,
  });

  final Transaction transaction;
  final Category? category;

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final memberLabel = transactionMemberLabel(t);
    final isTransfer = t.type == TransactionType.transfer;
    final title =
        (isTransfer && memberLabel != null && memberLabel.contains('→'))
        ? memberLabel
        : [
            memberLabel,
            categoryDisplayLabel(category),
          ].whereType<String>().join(' · ');
    final status = category?.statusById(t.statusId)?.name;
    final isIncome = t.type == TransactionType.income;
    final amountColor = isTransfer
        ? AppColors.textSecondary
        : (isIncome ? AppColors.accent : AppColors.textPrimary);
    final sign = isTransfer ? '⇄' : (isIncome ? '+' : '-');

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TransactionDetailScreen(transactionId: t.id),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 44,
              child: Text(
                Formatters.dayMonth(t.transactionDate),
                key: Key('explorer_date_${t.id}'),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (t.note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        t.note,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  if (status != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.chipBackground,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          status,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$sign ${Formatters.amount(t.amountMinor)}',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: amountColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tổng tiền theo từng bước trạng thái của danh mục có `statsEnabled`
/// (giữ nguyên tính năng cũ, thu gọn mặc định).
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.category, required this.breakdown});

  final Category category;
  final StatusBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: category.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                category.name,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                Formatters.amount(breakdown.total),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Bước đã ẩn chỉ hiện khi còn giao dịch lịch sử ở bước đó.
          for (final step in category.statuses)
            if (step.isActive || (breakdown.totals[step.id] ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        step.name,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      Formatters.amount(breakdown.totals[step.id] ?? 0),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
