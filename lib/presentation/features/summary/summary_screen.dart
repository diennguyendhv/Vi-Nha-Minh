import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/advanced_system_categories.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/fund.dart';
import '../../../domain/entities/wallet_identity.dart';
import '../../../domain/entities/savings_asset_type.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../../domain/entities/pool_kind.dart';
import '../../../domain/usecases/compute_financial_summary.dart';
import '../../../domain/usecases/compute_grouped_totals.dart';
import '../../../domain/usecases/explore_transactions.dart';
import '../../../domain/usecases/time_selection.dart';
import '../../providers/explorer_sort_provider.dart';
import '../../providers/fund_providers.dart';
import '../../providers/category_providers.dart';
import '../../providers/member_providers.dart';
import '../../providers/savings_asset_type_providers.dart';
import '../../providers/transaction_providers.dart';
import '../../widgets/transaction_row.dart';
import '../transactions/transaction_detail_screen.dart';

/// Màn "Tổng hợp" — hai phần rõ ràng:
///
/// - **TỔNG QUAN**: vài con số nhìn nhanh (Thu nhập ròng của Vợ / Chồng, Chi
///   tiêu gia đình) theo KỲ THỜI GIAN đang chọn.
/// - **GIAO DỊCH** (Transaction Explorer): mọi giao dịch đang hiệu lực, lọc kiểu
///   Excel — Thời gian (Ngày/Tháng/Năm) · Vợ/Chồng · nhiều
///   Danh mục · nhiều Trạng thái (kể cả "Không có trạng thái") · Ghi chú — và sắp xếp
///   nhiều tầng (kể cả theo Số tiền). OR trong cùng 1 chiều, AND giữa các chiều; các
///   chiều độc lập, chọn theo thứ tự nào cũng ra cùng kết quả.
///
/// Không có logic báo cáo thứ hai: Thu nhập ròng lấy từ
/// [computeMemberNetIncome], lọc/sắp xếp/tổng lấy từ [exploreTransactions].
class SummaryScreen extends ConsumerStatefulWidget {
  const SummaryScreen({super.key});

  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen> {
  final _searchController = TextEditingController();
  late TimeSelection _time = TimeSelection.month(DateTime.now());
  late TransactionFilter _filter = const TransactionFilter()
      .withRange(_time.from, _time.to)
      .withSort(ref.read(explorerSortProvider));
  bool _showFilters = false;

  static final _hidden = AdvancedSystemCategories.ids;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setTime(TimeSelection value) {
    setState(() {
      _time = value;
      _filter = _filter.withRange(value.from, value.to);
    });
  }

  bool get _isDefaultView =>
      _time == TimeSelection.month(DateTime.now()) && !_filter.hasNonDateFilter;

  void _clearAll() {
    _searchController.clear();
    final defaultTime = TimeSelection.month(DateTime.now());
    ref.read(explorerSortProvider.notifier).select(ExplorerSort.defaultSort);
    setState(() {
      _time = defaultTime;
      _filter = const TransactionFilter().withRange(
        defaultTime.from,
        defaultTime.to,
      );
      _showFilters = false;
    });
  }

  void _setPoolKinds(Set<PoolKind> kinds) {
    setState(() {
      _filter = _filter.withPoolKinds(kinds);
      if (!kinds.contains(PoolKind.fund)) {
        _filter = _filter.withFunds({});
      }
    });
  }

  void _setTypes(Set<TransactionType> types, List<Category> categories) {
    final relevant = categories.where(
      (category) => types.isEmpty || types.contains(category.type),
    );
    final categoryIds = relevant.map((category) => category.id).toSet();
    final statusIds = relevant
        .expand((category) => category.statuses)
        .map((status) => status.id)
        .toSet();
    setState(() {
      _filter = _filter
          .withTypes(types)
          .withCategories(_filter.categoryIds.intersection(categoryIds))
          .withStatuses(
            _filter.statusIds.intersection(statusIds),
            includeNone: statusIds.isNotEmpty && _filter.includeNoStatus,
          );
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
    final savingsAssetTypes =
        ref.watch(savingsAssetTypesStreamProvider).valueOrNull ??
        const <SavingsAssetType>[];
    final categoryById = {for (final c in categories) c.id: c};
    // Thẻ tổng quan theo KỲ THỜI GIAN đang chọn (không theo Danh mục/Trạng thái/
    // Ghi chú — phần đó nằm ở tổng của Explorer bên dưới). Dùng lại đúng các hàm
    // báo cáo hiện có, không tính lại công thức.
    final periodLabel = timeSelectionLabel(_time);
    final directory = ref.watch(memberDirectoryProvider);
    final netByMember = [
      for (final m in directory.members)
        (
          member: m,
          net: computeMemberNetIncome(
            m.memberId,
            transactions,
            categories,
            from: _time.from,
            to: _time.to,
          ),
        ),
    ];
    final spending = computeGroupedTotals(
      transactions,
      categories,
      from: _time.from,
      to: _time.to,
    ).spending;

    final result = exploreTransactions(
      transactions,
      categories,
      _filter,
      hiddenCategoryIds: _hidden,
    );
    final relevantCategories = categories
        .where(
          (category) =>
              _filter.types.isEmpty || _filter.types.contains(category.type),
        )
        .toList();
    final categoryOptions = explorerCategoryOptions(
      relevantCategories,
      transactions,
      hiddenCategoryIds: _hidden,
    );
    final statusOptions = explorerStatusOptions(
      relevantCategories,
      transactions,
    );
    final funds = ref.watch(fundsStreamProvider).valueOrNull ?? const <Fund>[];

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
              _SectionTitle('Tổng quan · $periodLabel'),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final (i, e) in netByMember.indexed) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(
                      child: _NetIncomeCard(
                        key: Key('summary_net_${e.member.memberId}'),
                        label: '${e.member.label} · Thu nhập ròng',
                        period: periodLabel,
                        value: e.net,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              _SpendingCard(
                key: const Key('summary_household_spending'),
                period: periodLabel,
                value: spending,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const _SectionTitle('Giao dịch'),
                  TextButton.icon(
                    key: const Key('summary_statistics'),
                    onPressed: () => _showStatistics(
                      context,
                      transactions: transactions,
                      categories: categories,
                      members: directory.members,
                      funds:
                          ref.read(fundsStreamProvider).valueOrNull ??
                          const <Fund>[],
                      assetTypes: savingsAssetTypes,
                      period: _time,
                    ),
                    icon: const Icon(Icons.insights_rounded, size: 18),
                    label: const Text('Số liệu'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _ResultHeader(
                key: const Key('summary_result_header'),
                result: result,
                selection: _time,
              ),
              const SizedBox(height: 10),
              _TimeBar(selection: _time, onChanged: _setTime),
              const SizedBox(height: 8),
              _MemberChips(
                members: directory.members,
                selected: _filter.memberId,
                onChanged: (m) =>
                    setState(() => _filter = _filter.withMember(m)),
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
                        setState(() => _showFilters = !_showFilters),
                    icon: Icon(
                      _showFilters
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
                  // Nhãn dài ("Ngày ↑ · Số tiền ↓") chiếm hết chỗ còn lại và chỉ bị cắt
                  // (…) khi "Xóa bộ lọc" cũng đang hiện trên màn hẹp — không làm tràn hàng.
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('summary_sort_button'),
                        onPressed: () => _openSortSheet(context),
                        icon: const Icon(Icons.swap_vert_rounded, size: 18),
                        label: Text(
                          _sortLabel(_filter.sort),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  if (!_isDefaultView)
                    TextButton(
                      key: const Key('summary_clear_filters'),
                      onPressed: _clearAll,
                      child: const Text('Xóa bộ lọc'),
                    ),
                ],
              ),
              _ActiveChips(
                filter: _filter,
                onClearCategories: () =>
                    setState(() => _filter = _filter.withCategories({})),
                onClearStatuses: () =>
                    setState(() => _filter = _filter.withStatuses({})),
                onClearTypes: () => _setTypes({}, categories),
                onClearPoolKinds: () => _setPoolKinds({}),
                onClearFunds: () =>
                    setState(() => _filter = _filter.withFunds({})),
              ),
              if (_showFilters)
                _FilterPanel(
                  filter: _filter,
                  categoryOptions: categoryOptions,
                  statusOptions: statusOptions,
                  onCategories: (ids) =>
                      setState(() => _filter = _filter.withCategories(ids)),
                  onStatuses: (ids, none) => setState(
                    () =>
                        _filter = _filter.withStatuses(ids, includeNone: none),
                  ),
                  onTypes: (types) => _setTypes(types, categories),
                  onPoolKinds: _setPoolKinds,
                  funds: funds,
                  onFunds: (ids) =>
                      setState(() => _filter = _filter.withFunds(ids)),
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
                    onPressed: _clearAll,
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
                return TransactionRow(
                  key: ValueKey(t.id),
                  transaction: t,
                  category: categoryById[t.categoryId],
                  assetTypes: savingsAssetTypes,
                  members: directory.members,
                  showDate: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          TransactionDetailScreen(transactionId: t.id),
                    ),
                  ),
                );
              },
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  void _showStatistics(
    BuildContext context, {
    required List<Transaction> transactions,
    required List<Category> categories,
    required List<FinancialMember> members,
    required List<Fund> funds,
    required List<SavingsAssetType> assetTypes,
    required TimeSelection period,
  }) {
    final totals = computeGroupedTotals(
      transactions,
      categories,
      from: period.from,
      to: period.to,
    );
    final financial = computeFinancialSummary(
      transactions,
      categories: categories,
      funds: funds.where((fund) => fund.isActive).toList(),
      assetTypes: [
        // The virtual unallocated pool is not stored in the asset repository.
        SystemSavingsAssets.unallocated,
        ...assetTypes.where(
          (type) => type.isActive && !SystemSavingsAssets.isSystem(type.id),
        ),
      ],
      members: members,
    );
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            const Text(
              'Số liệu',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            Text(
              'Dòng tiền · ${timeSelectionLabel(period)}',
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            _StatisticsSection('Dòng tiền', [
              ('Chi tiêu gia đình', totals.spending),
              ('Thu nhập ròng', totals.netIncome),
              ('Doanh thu', totals.revenue),
              ('Khoản thu khác', totals.otherInflow),
              ('Chi phí kinh doanh', totals.businessExpense),
            ]),
            _StatisticsSection('Thành viên', [
              for (final member in members)
                (
                  '${member.label} khả dụng',
                  financial.availableByMember[member.memberId] ?? 0,
                ),
            ]),
            _StatisticsSection('Tiết kiệm & tài sản', [
              for (final member in members)
                (
                  'Tiết kiệm chưa phân bổ của ${member.label}',
                  financial.savingsByMemberAndAssetType[member
                          .memberId]?[SystemSavingsAssets.unallocatedId] ??
                      0,
                ),
              ('Tổng tiết kiệm', financial.totalSavings),
              for (final fund in funds.where((fund) => fund.isActive))
                (fund.name, financial.fundBalances[fund.id] ?? 0),
              ('Tổng tài sản', financial.totalAssets),
            ]),
          ],
        ),
      ),
    );
  }

  static String _sortLabel(ExplorerSort sort) =>
      [for (final r in sort.rules) '${r.key.label} ${r.ascending ? '↑' : '↓'}']
          .join(' · ');

  /// Mở bảng Sắp xếp. Chỉ khi bấm OK (trả về cấu hình mới) mới áp dụng; Hủy / Back /
  /// vuốt đóng đều bỏ thay đổi đang chờ và giữ cấu hình đã áp dụng.
  Future<void> _openSortSheet(BuildContext context) async {
    final result = await showModalBottomSheet<ExplorerSort>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _SortSheet(applied: _filter.sort),
    );
    if (result != null && mounted) {
      ref.read(explorerSortProvider.notifier).select(result);
      setState(() => _filter = _filter.withSort(result));
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
    );
  }
}

class _StatisticsSection extends StatelessWidget {
  const _StatisticsSection(this.title, this.rows);

  final String title;
  final List<(String, int)> rows;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    row.$1,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                Text(
                  Formatters.amount(row.$2),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _NetIncomeCard extends StatelessWidget {
  const _NetIncomeCard({
    super.key,
    required this.label,
    required this.period,
    required this.value,
  });

  final String label;
  final String period;
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
            period,
            style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _SpendingCard extends StatelessWidget {
  const _SpendingCard({super.key, required this.period, required this.value});

  final String period;
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
              'Chi tiêu gia đình · $period',
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
  const _MemberChips({
    required this.members,
    required this.selected,
    required this.onChanged,
  });

  final List<FinancialMember> members;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String keyName, String label, String? value) {
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
        for (final m in members) chip(m.memberId, m.label, m.memberId),
      ],
    );
  }
}

String _dateLabel(DateTime d) => Formatters.dayMonthYear(d);

String timeSelectionLabel(TimeSelection s) {
  switch (s.kind) {
    case TimeKind.day:
      return _dateLabel(s.anchor);
    case TimeKind.month:
      return 'Tháng ${s.anchor.month}/${s.anchor.year}';
    case TimeKind.year:
      return 'Năm ${s.anchor.year}';
  }
}

/// Thời gian: [Ngày] [Tháng] [Năm]. Bấm 1 chip = về KỲ HIỆN TẠI (hôm
/// nay / tháng này / năm nay); mũi tên lùi/tiến để sang kỳ khác, bấm nhãn để chọn
/// ngày cụ thể.
class _TimeBar extends StatelessWidget {
  const _TimeBar({required this.selection, required this.onChanged});

  final TimeSelection selection;
  final ValueChanged<TimeSelection> onChanged;

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selection.anchor,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
    );
    if (picked == null) return;
    switch (selection.kind) {
      case TimeKind.day:
        onChanged(TimeSelection.day(picked));
      case TimeKind.month:
        onChanged(TimeSelection.month(picked));
      case TimeKind.year:
        onChanged(TimeSelection.year(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    Widget chip(String keyName, String label, TimeKind kind) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          key: Key('summary_time_$keyName'),
          label: Text(label),
          selected: selection.kind == kind,
          onSelected: (_) => onChanged(TimeSelection.current(kind, today)),
        ),
      );
    }

    final navigable =
        selection.kind == TimeKind.day ||
        selection.kind == TimeKind.month ||
        selection.kind == TimeKind.year;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Kỳ đang xem (‹ Tháng 9/2026 ›) nằm TRÊN hàng chọn kiểu thời gian.
        Row(
          children: [
            if (navigable)
              IconButton(
                key: const Key('summary_time_prev'),
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () => onChanged(selection.shift(-1)),
              ),
            Expanded(
              child: TextButton(
                key: const Key('summary_time_label'),
                onPressed: navigable ? () => _pickDate(context) : null,
                child: Text(
                  timeSelectionLabel(selection),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            if (navigable)
              IconButton(
                key: const Key('summary_time_next'),
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: () => onChanged(selection.shift(1)),
              ),
          ],
        ),
        const SizedBox(height: 2),
        // Xuống dòng thay vì cuộn ngang: mọi kiểu thời gian luôn nhìn thấy.
        Wrap(
          runSpacing: 6,
          children: [
            chip('day', 'Ngày', TimeKind.day),
            chip('month', 'Tháng', TimeKind.month),
            chip('year', 'Năm', TimeKind.year),
          ],
        ),
      ],
    );
  }
}

class _ActiveChips extends StatelessWidget {
  const _ActiveChips({
    required this.filter,
    required this.onClearCategories,
    required this.onClearStatuses,
    required this.onClearTypes,
    required this.onClearPoolKinds,
    required this.onClearFunds,
  });

  final TransactionFilter filter;
  final VoidCallback onClearCategories;
  final VoidCallback onClearStatuses;
  final VoidCallback onClearTypes;
  final VoidCallback onClearPoolKinds;
  final VoidCallback onClearFunds;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if (filter.categoryIds.isNotEmpty) {
      chips.add(
        InputChip(
          key: const Key('summary_chip_categories'),
          label: Text('Danh mục: ${filter.categoryIds.length}'),
          onDeleted: onClearCategories,
        ),
      );
    }
    if (filter.hasStatusFilter) {
      final n = filter.statusIds.length + (filter.includeNoStatus ? 1 : 0);
      chips.add(
        InputChip(
          key: const Key('summary_chip_statuses'),
          label: Text('Trạng thái: $n'),
          onDeleted: onClearStatuses,
        ),
      );
    }
    if (filter.types.isNotEmpty) {
      chips.add(
        InputChip(
          key: const Key('summary_chip_types'),
          label: Text('Loại: ${filter.types.length}'),
          onDeleted: onClearTypes,
        ),
      );
    }
    if (filter.poolKinds.isNotEmpty) {
      chips.add(
        InputChip(
          key: const Key('summary_chip_pool_kinds'),
          label: Text('Liên quan đến: ${filter.poolKinds.length}'),
          onDeleted: onClearPoolKinds,
        ),
      );
    }
    if (filter.fundIds.isNotEmpty) {
      chips.add(
        InputChip(
          key: const Key('summary_chip_funds'),
          label: Text('Quỹ: ${filter.fundIds.length}'),
          onDeleted: onClearFunds,
        ),
      );
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(spacing: 8, runSpacing: 4, children: chips),
    );
  }
}

/// Compact filters with category/status choices scoped to transaction types.
class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.filter,
    required this.categoryOptions,
    required this.statusOptions,
    required this.onCategories,
    required this.onStatuses,
    required this.onTypes,
    required this.onPoolKinds,
    required this.funds,
    required this.onFunds,
  });

  final TransactionFilter filter;
  final List<ExplorerOption> categoryOptions;
  final List<ExplorerOption> statusOptions;
  final ValueChanged<Set<String>> onCategories;
  final void Function(Set<String> ids, bool includeNone) onStatuses;
  final ValueChanged<Set<TransactionType>> onTypes;
  final ValueChanged<Set<PoolKind>> onPoolKinds;
  final List<Fund> funds;
  final ValueChanged<Set<String>> onFunds;

  static const _categoryGroupOrder = [
    'Doanh thu',
    'Khoản thu khác',
    'Chi tiêu',
    'Chi phí kinh doanh',
    'Chuyển',
  ];

  @override
  Widget build(BuildContext context) {
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
            'Loại giao dịch',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          Wrap(
            spacing: 6,
            children: [
              for (final type in TransactionType.values)
                FilterChip(
                  key: Key('summary_type_${type.name}'),
                  label: Text(switch (type) {
                    TransactionType.income => 'Thu',
                    TransactionType.expense => 'Chi',
                    TransactionType.transfer => 'Chuyển',
                  }),
                  selected: filter.types.contains(type),
                  onSelected: (selected) {
                    final value = {...filter.types};
                    selected ? value.add(type) : value.remove(type);
                    onTypes(value);
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Liên quan đến',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          Wrap(
            spacing: 6,
            children: [
              for (final kind in const [
                PoolKind.fund,
                PoolKind.memberSavingsAsset,
              ])
                FilterChip(
                  key: Key('summary_pool_${kind.name}'),
                  label: Text(kind == PoolKind.fund ? 'Quỹ' : 'Tiết kiệm'),
                  selected: filter.poolKinds.contains(kind),
                  onSelected: (selected) {
                    final value = {...filter.poolKinds};
                    selected ? value.add(kind) : value.remove(kind);
                    onPoolKinds(value);
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (filter.poolKinds.contains(PoolKind.fund) && funds.isNotEmpty) ...[
            const Text(
              'Quỹ cụ thể',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final fund in funds)
                  FilterChip(
                    key: Key('summary_fund_${fund.id}'),
                    label: Text(fund.name),
                    selected: filter.fundIds.contains(fund.id),
                    onSelected: (selected) {
                      final value = {...filter.fundIds};
                      selected ? value.add(fund.id) : value.remove(fund.id);
                      onFunds(value);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          _PickerRow(
            key: const Key('summary_pick_categories'),
            label: 'Danh mục',
            summary: filter.categoryIds.isEmpty
                ? 'Tất cả'
                : '${filter.categoryIds.length} đã chọn',
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => _MultiSelectSheet(
                title: 'Danh mục',
                options: categoryOptions,
                groupOrder: _categoryGroupOrder,
                initial: filter.categoryIds,
                onChanged: (ids, _) => onCategories(ids),
              ),
            ),
            onClear: filter.categoryIds.isEmpty ? null : () => onCategories({}),
          ),
          if (statusOptions.isNotEmpty) ...[
            const SizedBox(height: 10),
            _PickerRow(
              key: const Key('summary_pick_statuses'),
              label: 'Trạng thái',
              summary: !filter.hasStatusFilter
                  ? 'Tất cả'
                  : '${filter.statusIds.length + (filter.includeNoStatus ? 1 : 0)} đã chọn',
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => _MultiSelectSheet(
                  title: 'Trạng thái',
                  options: statusOptions,
                  initial: filter.statusIds,
                  noneLabel: 'Không có trạng thái',
                  initialNone: filter.includeNoStatus,
                  onChanged: onStatuses,
                ),
              ),
              onClear: filter.hasStatusFilter
                  ? () => onStatuses({}, false)
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    super.key,
    required this.label,
    required this.summary,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final String summary;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onTap,
            child: InputDecorator(
              decoration: InputDecoration(
                isDense: true,
                labelText: label,
                border: const OutlineInputBorder(),
                suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
              ),
              child: Text(summary),
            ),
          ),
        ),
        if (onClear != null)
          IconButton(
            key: Key('${(key as ValueKey<String>).value}_clear'),
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: 'Bỏ lọc $label',
            onPressed: onClear,
          ),
      ],
    );
  }
}

/// Bộ chọn NHIỀU mục có đánh dấu. Áp dụng ngay khi chạm (không cần "Xong" để
/// lưu), nhóm chỉ để nhìn cho dễ. [noneLabel] thêm lựa chọn "Không có trạng thái".
class _MultiSelectSheet extends StatefulWidget {
  const _MultiSelectSheet({
    required this.title,
    required this.options,
    required this.initial,
    required this.onChanged,
    this.groupOrder,
    this.noneLabel,
    this.initialNone = false,
  });

  final String title;
  final List<ExplorerOption> options;
  final Set<String> initial;
  final List<String>? groupOrder;
  final String? noneLabel;
  final bool initialNone;
  final void Function(Set<String> ids, bool includeNone) onChanged;

  @override
  State<_MultiSelectSheet> createState() => _MultiSelectSheetState();
}

class _MultiSelectSheetState extends State<_MultiSelectSheet> {
  late Set<String> _selected = {...widget.initial};
  late bool _none = widget.initialNone;

  void _notify() => widget.onChanged({..._selected}, _none);

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<ExplorerOption>>{};
    for (final o in widget.options) {
      (groups[o.groupLabel] ??= []).add(o);
    }
    final order = widget.groupOrder;
    final keys = groups.keys.toList();
    if (order != null) {
      keys.sort((a, b) {
        final ia = order.indexOf(a);
        final ib = order.indexOf(b);
        return (ia < 0 ? order.length : ia).compareTo(
          ib < 0 ? order.length : ib,
        );
      });
    }
    final height = MediaQuery.of(context).size.height * 0.75;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('multi_clear'),
                  onPressed: () {
                    setState(() {
                      _selected = {};
                      _none = false;
                    });
                    _notify();
                  },
                  child: const Text('Bỏ chọn'),
                ),
                TextButton(
                  key: const Key('multi_done'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Xong'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                if (widget.noneLabel != null)
                  CheckboxListTile(
                    key: const Key('multi_none'),
                    dense: true,
                    value: _none,
                    title: Text(widget.noneLabel!),
                    onChanged: (v) {
                      setState(() => _none = v ?? false);
                      _notify();
                    },
                  ),
                for (final g in keys) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
                    child: Text(
                      g.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textMuted,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  for (final o in groups[g]!)
                    CheckboxListTile(
                      key: Key('multi_${o.id}'),
                      dense: true,
                      value: _selected.contains(o.id),
                      title: Text(
                        o.label,
                        style: TextStyle(
                          color: o.active ? null : AppColors.textMuted,
                        ),
                      ),
                      onChanged: (v) {
                        setState(() {
                          if (v ?? false) {
                            _selected.add(o.id);
                          } else {
                            _selected.remove(o.id);
                          }
                        });
                        _notify();
                      },
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bảng Sắp xếp kiểu Excel: 2 dòng (Ngày, Số tiền), mỗi dòng có ô bật/tắt, tay kéo
/// đổi ưu tiên và ĐÚNG 1 mũi tên (↑/↓). Dòng trên = ưu tiên 1 (khi cả hai bật). Mọi
/// thay đổi chỉ là CHỜ trong bảng; danh sách chỉ đổi khi bấm OK (Hủy / Back / vuốt
/// đóng bỏ hết). Luôn phải còn ít nhất 1 khóa bật.
class _SortSheet extends StatefulWidget {
  const _SortSheet({required this.applied});

  /// Cấu hình đang ÁP DỤNG — bảng luôn mở với giá trị này.
  final ExplorerSort applied;

  @override
  State<_SortSheet> createState() => _SortSheetState();
}

class _SortRow {
  _SortRow(this.key, {required this.enabled, required this.ascending});

  final SortKey key;
  bool enabled;
  bool ascending;
}

class _SortSheetState extends State<_SortSheet> {
  late final List<_SortRow> _rows = _fromApplied(widget.applied);
  bool _showMinNotice = false;

  /// Khóa đang bật đứng trước theo đúng thứ tự ưu tiên; khóa tắt xuống dưới.
  static List<_SortRow> _fromApplied(ExplorerSort applied) => [
    for (final r in applied.rules)
      _SortRow(r.key, enabled: true, ascending: r.ascending),
    for (final k in SortKey.values)
      if (!applied.uses(k)) _SortRow(k, enabled: false, ascending: false),
  ];

  ExplorerSort get _pending => ExplorerSort([
    for (final r in _rows)
      if (r.enabled) SortRule(r.key, ascending: r.ascending),
  ]);

  void _toggleEnabled(_SortRow row) {
    setState(() {
      if (row.enabled && _rows.where((r) => r.enabled).length == 1) {
        _showMinNotice = true; // không cho tắt khóa cuối cùng
        return;
      }
      _showMinNotice = false;
      row.enabled = !row.enabled;
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      _rows.insert(newIndex, _rows.removeAt(oldIndex));
    });
  }

  Widget _rowTile(int index, _SortRow row) {
    final name = row.key.name;
    final dim = row.enabled ? null : AppColors.textMuted;
    return Padding(
      key: Key('sort_${name}_row'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          Checkbox(
            key: Key('sort_${name}_check'),
            value: row.enabled,
            onChanged: (_) => _toggleEnabled(row),
          ),
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              key: Key('sort_${name}_drag'),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: const Icon(
                Icons.drag_handle_rounded,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              row.key.label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: dim,
              ),
            ),
          ),
          IconButton(
            key: Key('sort_${name}_toggle'),
            onPressed: () => setState(() => row.ascending = !row.ascending),
            icon: Icon(
              row.ascending
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              key: Key('sort_${name}_${row.ascending ? 'up' : 'down'}'),
              color: row.enabled ? AppColors.accent : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              'Sắp xếp',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          ReorderableListView(
            key: const Key('sort_reorder_list'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: _onReorder,
            children: [
              for (var i = 0; i < _rows.length; i++) _rowTile(i, _rows[i]),
            ],
          ),
          if (_showMinNotice)
            const Padding(
              key: Key('sort_min_notice'),
              padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text(
                'Cần giữ ít nhất một khóa sắp xếp.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.expenseAmount,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const Key('sort_cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Hủy'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('sort_ok'),
                  onPressed: () => Navigator.of(context).pop(_pending),
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Khối tổng kết của tập đang xem, ngay dưới tiêu đề "Giao dịch": "76 giao dịch"
/// + kỳ đang xem, và Thu / Chi của CHÍNH tập đã lọc (2 ô riêng, không gộp thành
/// 1 con số Net mơ hồ; Chuyển không tính vào Thu/Chi).
class _ResultHeader extends StatelessWidget {
  const _ResultHeader({
    super.key,
    required this.result,
    required this.selection,
  });

  final ExplorerResult result;
  final TimeSelection selection;

  @override
  Widget build(BuildContext context) {
    Widget pill({
      required Key key,
      required String text,
      required IconData icon,
      required Color color,
    }) {
      return Container(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final pills = <Widget>[
      if (result.inflow > 0)
        pill(
          key: const Key('summary_result_inflow'),
          text: 'Thu ${Formatters.amount(result.inflow)}',
          icon: Icons.south_west_rounded,
          color: AppColors.accent,
        ),
      if (result.outflow > 0)
        pill(
          key: const Key('summary_result_outflow'),
          text: 'Chi ${Formatters.amount(result.outflow)}',
          icon: Icons.north_east_rounded,
          color: AppColors.expenseAmount,
        ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${result.count} giao dịch',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '· ${timeSelectionLabel(selection)}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          if (pills.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: pills),
          ],
        ],
      ),
    );
  }
}
