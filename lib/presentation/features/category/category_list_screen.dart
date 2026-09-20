import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/advanced_system_categories.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../../domain/errors/domain_exceptions.dart';
import '../../providers/category_providers.dart';
import '../../providers/transaction_providers.dart';
import '../../../domain/usecases/deletion_check.dart';
import '../transactions/blocking_transactions_dialog.dart';
import 'category_edit_screen.dart';

/// Màn "Danh mục" — 2 tầng: 4 NHÓM CHÍNH cố định (hệ thống định nghĩa, không
/// xoá/đổi được) → danh mục con do người dùng tự thêm/sửa/ngừng sử dụng.
///
///   THU: Doanh thu · Khoản thu khác        CHI: Chi tiêu · Chi phí kinh doanh
///
/// Nhóm của danh mục Thu = cờ `excludeFromTotals` (false = Doanh thu, true =
/// Khoản thu khác); nhóm của danh mục Chi = `Category.groupKey`. Danh mục hệ
/// thống của tính năng nâng cao (Vay, Hoàn tiền…) và Chuyển được ẩn khỏi màn
/// này — lịch sử giao dịch vẫn hiện đủ tên.
class CategoryListScreen extends ConsumerWidget {
  const CategoryListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesStreamProvider).valueOrNull ?? [];
    final visible = categories
        .where((c) => c.isActive && !AdvancedSystemCategories.contains(c.id))
        .toList();

    List<Category> pick(TransactionType type, bool Function(Category) test) =>
        visible.where((c) => c.type == type && test(c)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Danh mục')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _MainHeader('Thu'),
          _Group(
            keyName: 'revenue',
            title: 'Doanh thu',
            type: TransactionType.income,
            secondGroup: false,
            categories: pick(
              TransactionType.income,
              (c) => !c.excludeFromTotals,
            ),
          ),
          _Group(
            keyName: 'other_inflow',
            title: 'Khoản thu khác',
            type: TransactionType.income,
            secondGroup: true,
            categories: pick(
              TransactionType.income,
              (c) => c.excludeFromTotals,
            ),
          ),
          const SizedBox(height: 12),
          const _MainHeader('Chi'),
          _Group(
            keyName: 'spending',
            title: 'Chi tiêu',
            type: TransactionType.expense,
            secondGroup: false,
            categories: pick(
              TransactionType.expense,
              (c) => !c.isBusinessExpense,
            ),
          ),
          _Group(
            keyName: 'business_expense',
            title: 'Chi phí kinh doanh',
            type: TransactionType.expense,
            secondGroup: true,
            categories: pick(
              TransactionType.expense,
              (c) => c.isBusinessExpense,
            ),
          ),
          _StoppedSection(
            categories: categories
                .where(
                  (c) =>
                      !c.isActive &&
                      c.type != TransactionType.transfer &&
                      !AdvancedSystemCategories.contains(c.id),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

/// "Ngừng sử dụng (n)" — danh mục đã ngừng. "Sử dụng lại" giữ NGUYÊN id;
/// "Xóa hẳn" chỉ hiện khi danh mục chưa từng được dùng trong giao dịch nào
/// (người dùng không cần biết soft/hard delete — chỉ thấy nút khi an toàn).
class _StoppedSection extends ConsumerWidget {
  const _StoppedSection({required this.categories});

  final List<Category> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (categories.isEmpty) return const SizedBox.shrink();
    final deletable = ref.watch(deletableCategoryIdsProvider);
    final transactions =
        ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
    final allCategories =
        ref.watch(categoriesStreamProvider).valueOrNull ?? const [];
    // Vì sao chưa xóa hẳn được — suy ra từ dữ liệu ĐANG XEM nên tự cập nhật ngay
    // khi người dùng sửa/xóa giao dịch đang giữ danh mục.
    DeletionCheckResult checkOf(Category c) =>
        checkCategoryDeletion(c, allCategories, transactions);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('category_stopped_section'),
          tilePadding: EdgeInsets.zero,
          title: Text(
            'Ngừng sử dụng (${categories.length})',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.textMuted,
            ),
          ),
          children: [
            for (final c in categories)
              ListTile(
                key: Key('stopped_category_${c.id}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: CircleAvatar(radius: 9, backgroundColor: c.color),
                title: Text(
                  c.name,
                  style: const TextStyle(color: AppColors.textMuted),
                ),
                subtitle: deletable.contains(c.id)
                    ? null
                    : Text(
                        _holdReason(checkOf(c)),
                        style: const TextStyle(fontSize: 11.5),
                      ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      key: Key('reuse_category_${c.id}'),
                      onPressed: () => ref
                          .read(categoryRepositoryProvider)
                          .updateCategory(c.copyWith(isActive: true)),
                      child: const Text('Sử dụng lại'),
                    ),
                    if (!deletable.contains(c.id) &&
                        checkOf(c).transactionBlockers.isNotEmpty)
                      TextButton(
                        key: Key('show_blockers_${c.id}'),
                        onPressed: () => showBlockingTransactions(
                          context,
                          title: 'Chưa thể xóa "${c.name}"',
                          message: _holdReason(checkOf(c)),
                          blockers: checkOf(c).blockers,
                        ),
                        child: const Text('Xem giao dịch'),
                      ),
                    if (!deletable.contains(c.id) && checkOf(c).hasHiddenHistory)
                      TextButton(
                        key: Key('purge_history_${c.id}'),
                        onPressed: () => _confirmPurge(context, ref, c),
                        child: const Text('Dọn lịch sử đã xóa'),
                      ),
                    if (deletable.contains(c.id))
                      TextButton(
                        key: Key('delete_category_${c.id}'),
                        onPressed: () => _confirmDelete(context, ref, c),
                        child: const Text(
                          'Xóa hẳn',
                          style: TextStyle(color: AppColors.expenseAmount),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// "Đang được sử dụng bởi n giao dịch." / lịch sử ẩn / danh mục hệ thống.
  static String _holdReason(DeletionCheckResult check) {
    final n = check.transactionBlockers.length;
    if (n > 0) {
      return 'Chưa thể xóa danh mục này. Đang được sử dụng bởi $n giao dịch.';
    }
    if (check.hasHiddenHistory) {
      return 'Còn giao dịch đã xóa/sửa trước đây (đang ẩn) — dọn lịch sử để xóa.';
    }
    return 'Danh mục hệ thống nên không thể xóa.';
  }

  Future<void> _confirmPurge(
    BuildContext context,
    WidgetRef ref,
    Category category,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dọn lịch sử đã xóa?'),
        content: Text(
          'Các giao dịch đã xóa trước đây (đang ẩn) của "${category.name}" sẽ bị xóa hẳn khỏi dữ liệu. Số dư không thay đổi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            key: const Key('confirm_purge_history'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Dọn'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(transactionRepositoryProvider).purgeDeletedHistory(category.id);
    } on DeleteWouldOverdrawException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chưa thể dọn vì số liệu đang phụ thuộc vào các giao dịch này.')),
        );
      }
    } on TransactionDeleteBlockedException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chưa thể dọn vì có giao dịch liên quan khoản vay / hoàn tiền.')),
        );
      }
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Category category,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Xóa hẳn "${category.name}"?'),
        content: const Text('Danh mục sẽ biến mất và không thể khôi phục.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            key: const Key('confirm_delete_category'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xóa hẳn'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(categoryRepositoryProvider)
          .deleteCategoryPermanently(category.id);
    } on CategoryNotDeletableException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Danh mục này vừa được dùng nên không thể xóa.'),
          ),
        );
      }
    }
  }
}

class _MainHeader extends StatelessWidget {
  const _MainHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppColors.textMuted,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.keyName,
    required this.title,
    required this.type,
    required this.secondGroup,
    required this.categories,
  });

  final String keyName;
  final String title;
  final TransactionType type;
  final bool secondGroup;
  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('category_group_$keyName'),
      margin: const EdgeInsets.only(top: 8),
      elevation: 0,
      color: AppColors.chipBackground,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            for (final c in categories) _CategoryRow(category: c),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: Key('add_category_$keyName'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CategoryEditScreen(
                      initialType: type,
                      initialSecondGroup: secondGroup,
                    ),
                  ),
                ),
                child: const Text('+ Thêm danh mục'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('category_row_${category.id}'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: CircleAvatar(radius: 9, backgroundColor: category.color),
      title: Text(category.name),
      subtitle: category.hasStatus
          ? Text('${category.activeStatuses.length} trạng thái')
          : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CategoryEditScreen(categoryId: category.id),
        ),
      ),
    );
  }
}
