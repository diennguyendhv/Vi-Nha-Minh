import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/advanced_system_categories.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/family_member.dart';
import '../../../domain/entities/savings_asset_type.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../../domain/usecases/compute_grouped_totals.dart';
import '../../../domain/usecases/explore_transactions.dart';
import '../../../domain/usecases/time_selection.dart';
import '../../providers/explorer_sort_provider.dart';
import '../../providers/category_providers.dart';
import '../../providers/savings_asset_type_providers.dart';
import '../../providers/transaction_providers.dart';
import '../../widgets/category_label.dart';
import '../transactions/transaction_detail_screen.dart';

/// Màn "Tổng hợp" — hai phần rõ ràng:
///
/// - **TỔNG QUAN**: vài con số nhìn nhanh (Thu nhập ròng của Vợ / Chồng, Chi
///   tiêu gia đình) theo KỲ THỜI GIAN đang chọn.
/// - **GIAO DỊCH** (Transaction Explorer): mọi giao dịch đang hiệu lực, lọc kiểu
///   Excel — Thời gian (Ngày/Tháng/Năm/Tất cả) · Vợ/Chồng · nhiều
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
      _time == TimeSelection.month(DateTime.now()) &&
      !_filter.hasNonDateFilter;

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
    final netVo = computeMemberNetIncome(
      FamilyMember.vo,
      transactions,
      categories,
      from: _time.from,
      to: _time.to,
    );
    final netChong = computeMemberNetIncome(
      FamilyMember.chong,
      transactions,
      categories,
      from: _time.from,
      to: _time.to,
    );
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
    final categoryOptions = explorerCategoryOptions(
      categories,
      transactions,
      hiddenCategoryIds: _hidden,
    );
    final statusOptions = explorerStatusOptions(categories, transactions);

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
                  Expanded(
                    child: _NetIncomeCard(
                      key: const Key('summary_net_vo'),
                      label: 'Vợ · Thu nhập ròng',
                      period: periodLabel,
                      value: netVo,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _NetIncomeCard(
                      key: const Key('summary_net_chong'),
                      label: 'Chồng · Thu nhập ròng',
                      period: periodLabel,
                      value: netChong,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _SpendingCard(
                key: const Key('summary_household_spending'),
                period: periodLabel,
                value: spending,
              ),
              const SizedBox(height: 20),
              const _SectionTitle('Giao dịch'),
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
                selected: _filter.member,
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
              ),
              if (_showFilters)
                _FilterPanel(
                  filter: _filter,
                  categoryOptions: categoryOptions,
                  statusOptions: statusOptions,
                  onCategories: (ids) =>
                      setState(() => _filter = _filter.withCategories(ids)),
                  onStatuses: (ids, none) => setState(
                    () => _filter = _filter.withStatuses(ids, includeNone: none),
                  ),
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
                return _ExplorerRow(
                  key: ValueKey(t.id),
                  transaction: t,
                  category: categoryById[t.categoryId],
                  assetTypes: savingsAssetTypes,
                );
              },
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  static String _sortLabel(ExplorerSort sort) => [
    for (final r in sort.rules) '${r.key.label} ${r.ascending ? '↑' : '↓'}',
  ].join(' · ');

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

String _dateLabel(DateTime d) => Formatters.dayMonthYear(d);

String timeSelectionLabel(TimeSelection s) {
  switch (s.kind) {
    case TimeKind.day:
      return _dateLabel(s.anchor);
    case TimeKind.month:
      return 'Tháng ${s.anchor.month}/${s.anchor.year}';
    case TimeKind.year:
      return 'Năm ${s.anchor.year}';
    case TimeKind.all:
      return 'Mọi thời gian';
  }
}

/// Thời gian: [Ngày] [Tháng] [Năm] [Tất cả]. Bấm 1 chip = về KỲ HIỆN TẠI (hôm
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
      case TimeKind.all:
        break;
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

    final navigable = selection.kind == TimeKind.day ||
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
        // Xuống dòng thay vì cuộn ngang: mọi kiểu thời gian (kể cả "Tất cả")
        // luôn nhìn thấy, không phải đoán là có thể vuốt.
        Wrap(
          runSpacing: 6,
          children: [
            chip('day', 'Ngày', TimeKind.day),
            chip('month', 'Tháng', TimeKind.month),
            chip('year', 'Năm', TimeKind.year),
            chip('all', 'Tất cả', TimeKind.all),
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
  });

  final TransactionFilter filter;
  final VoidCallback onClearCategories;
  final VoidCallback onClearStatuses;

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
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(spacing: 8, runSpacing: 4, children: chips),
    );
  }
}

/// Bảng bộ lọc: Danh mục (nhiều) · Trạng thái (nhiều) · Số tiền. Mỗi chiều độc
/// lập với chiều còn lại.
class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.filter,
    required this.categoryOptions,
    required this.statusOptions,
    required this.onCategories,
    required this.onStatuses,
  });

  final TransactionFilter filter;
  final List<ExplorerOption> categoryOptions;
  final List<ExplorerOption> statusOptions;
  final ValueChanged<Set<String>> onCategories;
  final void Function(Set<String> ids, bool includeNone) onStatuses;

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
            onClear: filter.hasStatusFilter ? () => onStatuses({}, false) : null,
          ),
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
        return (ia < 0 ? order.length : ia).compareTo(ib < 0 ? order.length : ib);
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
                style: TextStyle(fontSize: 12.5, color: AppColors.expenseAmount),
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
  const _ResultHeader({super.key, required this.result, required this.selection});

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

/// Dòng giao dịch: ngày · Vợ/Chồng · Nhóm · Danh mục · số tiền · ghi chú ·
/// trạng thái. Chuyển hiện đời thường ("Vợ → Chồng"). Không lộ enum/pool/cờ.
class _ExplorerRow extends StatelessWidget {
  const _ExplorerRow({
    super.key,
    required this.transaction,
    required this.category,
    this.assetTypes = const [],
  });

  final Transaction transaction;
  final Category? category;

  /// Để hiện tên loại tài sản trong dòng Tiết kiệm (không bắt buộc).
  final List<SavingsAssetType> assetTypes;

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final memberLabel = transactionMemberLabel(t);
    final isTransfer = t.type == TransactionType.transfer;
    final savingsLabel = savingsTransferLabel(t, assetTypes);
    final title = savingsLabel != null
        ? [memberLabel, savingsLabel].whereType<String>().join(' · ')
        : (isTransfer && memberLabel != null && memberLabel.contains('→'))
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

