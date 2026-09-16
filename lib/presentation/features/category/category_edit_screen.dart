import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/id_generator.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/status.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../../domain/usecases/compute_net_income.dart';
import '../../providers/category_providers.dart';
import '../../providers/status_providers.dart';
import '../../providers/transaction_providers.dart';

const _swatches = <Color>[
  Color(0xFFE8A23E),
  Color(0xFF3E6FB0),
  Color(0xFF8A4FB0),
  Color(0xFFC14F7A),
  Color(0xFF12805C),
  Color(0xFF8FA3B3),
];

/// Màn "Danh mục — Chỉnh sửa" (`docs/design.html` màn 07) — CRUD danh mục +
/// trạng thái con (phase 12). `categoryId == null` = tạo mới.
class CategoryEditScreen extends ConsumerStatefulWidget {
  const CategoryEditScreen({super.key, this.categoryId});

  final String? categoryId;

  @override
  ConsumerState<CategoryEditScreen> createState() => _CategoryEditScreenState();
}

class _CategoryEditScreenState extends ConsumerState<CategoryEditScreen> {
  final _nameController = TextEditingController();
  final _newStatusController = TextEditingController();
  TransactionType _type = TransactionType.expense;
  Color _color = _swatches.first;
  bool _statsEnabled = false;
  bool _excludeFromTotals = false;
  String? _linkedExpenseCategoryId;
  List<Status> _statuses = [];
  List<Status> _originalStatuses = [];
  bool _initialized = false;
  late final String _categoryId = widget.categoryId ?? IdGenerator.generate();

  bool get _isNew => widget.categoryId == null;

  @override
  void dispose() {
    _nameController.dispose();
    _newStatusController.dispose();
    super.dispose();
  }

  void _initFrom(Category category) {
    _nameController.text = category.name;
    _type = category.type;
    _color = category.color;
    _statsEnabled = category.statsEnabled;
    _excludeFromTotals = category.excludeFromTotals;
    _linkedExpenseCategoryId = category.linkedExpenseCategoryId;
    _statuses = List.of(category.statuses);
    _originalStatuses = List.of(category.statuses);
  }

  void _addStatus() {
    final name = _newStatusController.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _statuses = [
        ..._statuses,
        Status(
          id: IdGenerator.generate(),
          categoryId: _categoryId,
          name: name,
          sortOrder: _statuses.length,
        ),
      ];
      _newStatusController.clear();
    });
  }

  void _removeStatus(Status status) {
    setState(() => _statuses = _statuses.where((s) => s.id != status.id).toList());
  }

  Future<void> _save(List<Category> allCategories) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final category = Category(
      id: _categoryId,
      name: name,
      color: _color,
      type: _type,
      statuses: _statuses,
      statsEnabled: _statsEnabled,
      excludeFromTotals: _excludeFromTotals,
      linkedExpenseCategoryId:
          _type == TransactionType.income ? _linkedExpenseCategoryId : null,
      isDefault: false,
    );

    final categoryRepository = ref.read(categoryRepositoryProvider);
    if (_isNew) {
      await categoryRepository.addCategory(category);
    } else {
      await categoryRepository.updateCategory(category);
    }

    final statusRepository = ref.read(statusRepositoryProvider);
    final originalIds = _originalStatuses.map((s) => s.id).toSet();
    final currentIds = _statuses.map((s) => s.id).toSet();

    for (final removed in _originalStatuses) {
      if (!currentIds.contains(removed.id)) {
        await statusRepository.softDeleteStatus(removed.id);
      }
    }
    for (final s in _statuses) {
      if (originalIds.contains(s.id)) {
        final original = _originalStatuses.firstWhere((o) => o.id == s.id);
        if (original.name != s.name) {
          await statusRepository.renameStatus(s.id, s.name);
        }
      } else {
        await statusRepository.addStatus(s);
      }
    }
    await statusRepository.reorderStatuses(
      _categoryId,
      _statuses.map((s) => s.id).toList(),
    );

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    await ref.read(categoryRepositoryProvider).softDeleteCategory(_categoryId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesStreamProvider).valueOrNull ?? [];
    final transactions = ref.watch(transactionsStreamProvider).valueOrNull ?? [];

    if (!_isNew && !_initialized) {
      for (final c in categories) {
        if (c.id == widget.categoryId) {
          _initFrom(c);
          break;
        }
      }
      _initialized = true;
    }

    final expenseCategoriesForLink = categories
        .where((c) => c.type == TransactionType.expense && c.id != _categoryId)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Thêm danh mục' : 'Sửa danh mục'),
        actions: [
          if (!_isNew)
            TextButton(
              onPressed: _delete,
              child: const Text('Xoá', style: TextStyle(color: AppColors.expenseAmount)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Tên danh mục', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 18),
          const Text('Phân loại', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          SegmentedButton<TransactionType>(
            segments: const [
              ButtonSegment(value: TransactionType.income, label: Text('Thu')),
              ButtonSegment(value: TransactionType.expense, label: Text('Chi')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          if (_type == TransactionType.income) ...[
            const SizedBox(height: 18),
            const Text(
              'Danh mục chi liên kết (tuỳ chọn, để tính Thu nhập ròng)',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String?>(
              value: _linkedExpenseCategoryId,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: null, child: Text('Không liên kết')),
                for (final c in expenseCategoriesForLink)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (id) => setState(() => _linkedExpenseCategoryId = id),
            ),
            if (_linkedExpenseCategoryId != null) ...[
              const SizedBox(height: 10),
              Builder(
                builder: (context) {
                  final linked = expenseCategoriesForLink.firstWhere(
                    (c) => c.id == _linkedExpenseCategoryId,
                  );
                  final draft = Category(
                    id: _categoryId,
                    name: _nameController.text,
                    color: _color,
                    type: TransactionType.income,
                  );
                  final net = computeNetIncome(draft, linked, transactions) ?? 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Thu nhập ròng hiện tại: ${Formatters.amount(net)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Không tính vào Tổng thu'),
              subtitle: const Text('excludeFromTotals — vd "Số dư ban đầu"'),
              value: _excludeFromTotals,
              onChanged: (v) => setState(() => _excludeFromTotals = v),
            ),
          ],
          const SizedBox(height: 18),
          const Text('Màu', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _swatches
                .map(
                  (c) => GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: CircleAvatar(
                      backgroundColor: c,
                      radius: 16,
                      child: _color == c
                          ? const Icon(Icons.check, color: Colors.white, size: 16)
                          : null,
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 18),
          const Text(
            'Trạng thái (để trống nếu không cần theo dõi)',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          for (final s in _statuses)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.drag_handle),
              title: Text(s.name),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => _removeStatus(s),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newStatusController,
                  decoration: const InputDecoration(hintText: 'Thêm bước trạng thái...'),
                  onSubmitted: (_) => _addStatus(),
                ),
              ),
              IconButton(icon: const Icon(Icons.add_circle), onPressed: _addStatus),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Thống kê'),
            subtitle: const Text('Hiện danh mục này ở màn Tổng hợp trạng thái'),
            value: _statsEnabled,
            onChanged: (v) => setState(() => _statsEnabled = v),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => _save(categories),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Lưu danh mục'),
          ),
        ],
      ),
    );
  }
}
