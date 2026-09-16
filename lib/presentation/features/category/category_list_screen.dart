import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../providers/category_providers.dart';
import 'category_edit_screen.dart';

/// Màn "Danh mục — Danh sách" (`docs/design.html` màn 06) — 3 nhóm Thu/Chi
/// (tự tạo được)/Chuyển (hệ thống, không tự tạo/xoá).
class CategoryListScreen extends ConsumerWidget {
  const CategoryListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesStreamProvider).valueOrNull ?? [];
    final active = categories.where((c) => c.isActive).toList();
    final income = active.where((c) => c.type == TransactionType.income).toList();
    final expense = active.where((c) => c.type == TransactionType.expense).toList();
    final transfer = active.where((c) => c.type == TransactionType.transfer).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Danh mục')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _GroupLabel('Thu'),
          for (final c in income) _CategoryRow(category: c, editable: true),
          const SizedBox(height: 12),
          const _GroupLabel('Chi'),
          for (final c in expense) _CategoryRow(category: c, editable: true),
          const SizedBox(height: 12),
          const _GroupLabel('Chuyển · hệ thống, không tự tạo/xoá được'),
          for (final c in transfer) _CategoryRow(category: c, editable: false),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CategoryEditScreen()),
            ),
            child: const Text('+ Thêm danh mục Thu/Chi'),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.editable});

  final Category category;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[];
    if (category.hasStatus) {
      subtitleParts.add('${category.statuses.length} trạng thái');
    } else {
      subtitleParts.add('Không theo dõi trạng thái');
    }
    if (category.statsEnabled) subtitleParts.add('Thống kê: bật');
    if (category.excludeFromTotals) subtitleParts.add('Không tính vào Tổng thu');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(backgroundColor: category.color),
      title: Text(category.name),
      subtitle: Text(subtitleParts.join(' · ')),
      trailing: editable ? const Icon(Icons.chevron_right) : null,
      onTap: editable
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CategoryEditScreen(categoryId: category.id),
              ),
            )
          : null,
    );
  }
}
