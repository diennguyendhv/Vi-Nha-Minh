import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/advanced_system_categories.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../providers/category_providers.dart';
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
        ],
      ),
    );
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
