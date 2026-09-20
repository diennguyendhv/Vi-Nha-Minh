import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/id_generator.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/status.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../../domain/errors/domain_exceptions.dart';
import '../../providers/category_providers.dart';
import '../../providers/status_providers.dart';
import '../../providers/transaction_providers.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/usecases/deletion_check.dart';
import '../transactions/blocking_transactions_dialog.dart';

const _swatches = <Color>[
  Color(0xFFE8A23E),
  Color(0xFF3E6FB0),
  Color(0xFF8A4FB0),
  Color(0xFFC14F7A),
  Color(0xFF12805C),
  Color(0xFF8FA3B3),
];

/// Màn "Danh mục — Thêm/Sửa" (`docs/design.html` màn 07) — CRUD danh mục +
/// bước trạng thái con. `categoryId == null` = tạo mới.
///
/// SIMPLE BY DEFAULT, POWERFUL WHEN NEEDED: mặc định chỉ có Tên + Phân loại
/// (Thu/Chi) + Lưu. Mọi thiết lập nâng cao (màu, theo dõi tiến độ, hiện ở
/// Tổng hợp, không tính vào thu nhập, thu nhập ròng) nằm trong "Tuỳ chọn
/// nâng cao" — thu gọn khi Thêm, tự mở khi Sửa một danh mục đã có thiết lập
/// nâng cao. Các giá trị luôn nằm trong state của màn này nên thu gọn phần
/// nâng cao KHÔNG làm mất cấu hình đã có.
class CategoryEditScreen extends ConsumerStatefulWidget {
  const CategoryEditScreen({
    super.key,
    this.categoryId,
    this.initialType,
    this.initialSecondGroup = false,
  });

  final String? categoryId;

  /// Chỉ dùng khi TẠO MỚI từ 1 nhóm trong màn Danh mục: điền sẵn Thu/Chi và
  /// nhóm thứ hai (Khoản thu khác / Chi phí kinh doanh) để giảm thao tác.
  final TransactionType? initialType;
  final bool initialSecondGroup;

  @override
  ConsumerState<CategoryEditScreen> createState() => _CategoryEditScreenState();
}

class _CategoryEditScreenState extends ConsumerState<CategoryEditScreen> {
  final _nameController = TextEditingController();
  final _newStatusController = TextEditingController();
  TransactionType _type = TransactionType.expense;
  Color _color = _swatches.first;
  bool _statsEnabled = false;

  /// Nhóm của danh mục THU: false = Doanh thu, true = Khoản thu khác (chính
  /// là cờ `excludeFromTotals` — không có trường thứ hai).
  bool _excludeFromTotals = false;

  /// Nhóm của danh mục CHI: null = Chi tiêu, `business_expense` = Chi phí
  /// kinh doanh (`Category.groupKey`).
  String? _groupKey;

  /// Cấu hình "thu nhập ròng" cũ (`linkedExpenseCategoryId`) KHÔNG còn hiện
  /// trên UI (quyết định sản phẩm: đơn giản trước, chi tiết đi trong Ghi
  /// chú). Giá trị đã có vẫn được ĐỌC vào đây và GHI LẠI nguyên vẹn khi lưu,
  /// để mở/lưu danh mục cũ không làm mất dữ liệu.
  String? _linkedExpenseCategoryId;

  /// TẤT CẢ các bước, kể cả bước đã ẩn (`isActive == false`) — để cho phép
  /// "Sử dụng lại" và không làm mất bước khi lưu.
  List<Status> _statuses = [];
  List<Status> _originalStatuses = [];
  bool _initialized = false;
  bool _advancedOpen = false;
  bool _nameError = false;

  /// Id của bước trạng thái mà tên vừa nhập trùng (đang dùng hoặc ngừng sử
  /// dụng) — hiện thông báo thay vì âm thầm tạo bản trùng.
  String? _duplicateStatusId;

  /// Danh mục CÙNG LOẠI, CÙNG TÊN với tên vừa nhập khi TẠO MỚI (đang dùng hoặc
  /// đã ngừng) — hiện thông báo/"Sử dụng lại" thay vì âm thầm tạo bản trùng.
  Category? _duplicateCategory;
  late final String _categoryId = widget.categoryId ?? IdGenerator.generate();

  bool get _isNew => widget.categoryId == null;

  @override
  void initState() {
    super.initState();
    if (_isNew) {
      _type = widget.initialType ?? _type;
      if (widget.initialSecondGroup) {
        if (_type == TransactionType.income) {
          _excludeFromTotals = true;
        } else {
          _groupKey = CategoryGroupKey.businessExpense;
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _newStatusController.dispose();
    super.dispose();
  }

  /// Danh mục đã có thiết lập nâng cao nào không (không tính màu — màu luôn
  /// có giá trị). Dùng để tự mở "Tuỳ chọn nâng cao" khi Sửa.
  static bool _hasAdvancedConfig(Category c) =>
      c.statuses.isNotEmpty || c.statsEnabled;

  void _initFrom(Category category) {
    _nameController.text = category.name;
    _type = category.type;
    _color = category.color;
    _statsEnabled = category.statsEnabled;
    _excludeFromTotals = category.excludeFromTotals;
    _groupKey = category.groupKey;
    _linkedExpenseCategoryId = category.linkedExpenseCategoryId;
    _statuses = List.of(category.statuses);
    _originalStatuses = List.of(category.statuses);
    _advancedOpen = _hasAdvancedConfig(category);
  }

  static String _norm(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  void _addStatus() {
    final name = _newStatusController.text.trim();
    if (name.isEmpty) return;
    // Kiểm tra CẢ bước đang dùng lẫn đã ngừng sử dụng: không âm thầm tạo bản
    // trùng (mỗi bản trùng là 1 status id thừa).
    final clash = _statuses.where((s) => _norm(s.name) == _norm(name));
    if (clash.isNotEmpty) {
      setState(() => _duplicateStatusId = clash.first.id);
      return;
    }
    setState(() {
      _duplicateStatusId = null;
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

  /// "Ngừng sử dụng": bước đã lưu chỉ đặt `isActive = false` (KHÔNG xoá cứng —
  /// giao dịch cũ vẫn giữ `statusId` và vẫn thấy tên). Bước mới chưa từng
  /// lưu thì bỏ hẳn khỏi danh sách nháp.
  void _stopUsingStatus(Status status) {
    final existed = _originalStatuses.any((o) => o.id == status.id);
    setState(() {
      _statuses = existed
          ? [
              for (final s in _statuses)
                s.id == status.id ? s.copyWith(isActive: false) : s,
            ]
          : _statuses.where((s) => s.id != status.id).toList();
    });
  }

  /// "Sử dụng lại": giữ NGUYÊN id cũ, chỉ `isActive = true`.
  void _reuseStatus(Status status) {
    setState(() {
      _statuses = [
        for (final s in _statuses)
          s.id == status.id ? s.copyWith(isActive: true) : s,
      ];
      if (_duplicateStatusId == status.id) {
        _duplicateStatusId = null;
        _newStatusController.clear();
      }
    });
  }

  Future<void> _renameStatus(Status status) async {
    final controller = TextEditingController(text: status.name);
    String? error;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Đổi tên trạng thái'),
          content: TextField(
            key: const Key('status_rename_field'),
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(errorText: error),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Huỷ'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) return;
                final clash = _statuses.any(
                  (s) => s.id != status.id && _norm(s.name) == _norm(value),
                );
                if (clash) {
                  setLocal(() => error = 'Đã có trạng thái tên này');
                  return;
                }
                Navigator.of(context).pop(value);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (name == null || name.isEmpty) return;
    setState(() {
      _statuses = [
        for (final s in _statuses)
          s.id == status.id ? s.copyWith(name: name) : s,
      ];
    });
  }

  Future<void> _save(List<Category> allCategories) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = true);
      return;
    }

    if (_isNew) {
      final clash = allCategories.where(
        (c) => c.type == _type && _norm(c.name) == _norm(name),
      );
      if (clash.isNotEmpty) {
        setState(() => _duplicateCategory = clash.first);
        return;
      }
    }

    final category = Category(
      id: _categoryId,
      name: name,
      color: _color,
      type: _type,
      statuses: _statuses,
      statsEnabled: _statsEnabled,
      excludeFromTotals: _excludeFromTotals,
      groupKey: _type == TransactionType.expense ? _groupKey : null,
      linkedExpenseCategoryId: _type == TransactionType.income
          ? _linkedExpenseCategoryId
          : null,
      isDefault: false,
    );

    final categoryRepository = ref.read(categoryRepositoryProvider);
    if (_isNew) {
      await categoryRepository.addCategory(category);
    } else {
      await categoryRepository.updateCategory(category);
    }

    final statusRepository = ref.read(statusRepositoryProvider);
    for (final s in _statuses) {
      final matches = _originalStatuses.where((o) => o.id == s.id);
      if (matches.isEmpty) {
        await statusRepository.addStatus(s);
        continue;
      }
      final original = matches.first;
      if (original.name != s.name) {
        await statusRepository.renameStatus(s.id, s.name);
      }
      if (original.isActive && !s.isActive) {
        await statusRepository.softDeleteStatus(s.id);
      } else if (!original.isActive && s.isActive) {
        await statusRepository.reactivateStatus(s.id);
      }
    }
    if (_statuses.isNotEmpty) {
      await statusRepository.reorderStatuses(
        _categoryId,
        _statuses.map((s) => s.id).toList(),
      );
    }

    if (mounted) Navigator.of(context).pop();
  }

  /// "Ngừng sử dụng" danh mục (ẩn khỏi bộ chọn; giao dịch cũ vẫn đọc được).
  Future<void> _delete() async {
    await ref.read(categoryRepositoryProvider).softDeleteCategory(_categoryId);
    if (mounted) Navigator.of(context).pop();
  }

  /// "Sử dụng lại" danh mục cùng tên đã ngừng: giữ NGUYÊN id, không tạo bản mới.
  Future<void> _reuseDuplicateCategory(Category category) async {
    await ref
        .read(categoryRepositoryProvider)
        .updateCategory(category.copyWith(isActive: true));
    if (mounted) Navigator.of(context).pop();
  }

  /// "Xóa hẳn" 1 bước đã ngừng và chưa từng dùng: xoá thật khỏi DB rồi bỏ khỏi
  /// danh sách nháp (không cần bấm Lưu).
  Future<void> _deleteStatusPermanently(Status status) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Xóa hẳn "${status.name}"?'),
        content: const Text('Trạng thái sẽ biến mất và không thể khôi phục.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            key: const Key('confirm_delete_status'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xóa hẳn'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(statusRepositoryProvider).deleteStatusPermanently(status.id);
    } on StatusNotDeletableException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trạng thái này vừa được dùng nên không thể xóa.'),
          ),
        );
      }
      return;
    }
    setState(() {
      _statuses = _statuses.where((s) => s.id != status.id).toList();
      _originalStatuses = _originalStatuses
          .where((s) => s.id != status.id)
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesStreamProvider).valueOrNull ?? [];

    if (!_isNew && !_initialized) {
      for (final c in categories) {
        if (c.id == widget.categoryId) {
          _initFrom(c);
          _initialized = true;
          break;
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Thêm danh mục' : 'Sửa danh mục'),
        actions: [
          if (!_isNew)
            TextButton(
              onPressed: _delete,
              child: const Text(
                'Ngừng sử dụng',
                style: TextStyle(color: AppColors.expenseAmount),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Tên danh mục',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          TextField(
            key: const Key('category_name'),
            controller: _nameController,
            onChanged: (_) {
              if (_nameError || _duplicateCategory != null) {
                setState(() {
                  _nameError = false;
                  _duplicateCategory = null;
                });
              }
            },
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              errorText: _nameError ? 'Nhập tên danh mục' : null,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Phân loại',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          SegmentedButton<TransactionType>(
            key: const Key('category_type'),
            segments: const [
              ButtonSegment(value: TransactionType.income, label: Text('Thu')),
              ButtonSegment(value: TransactionType.expense, label: Text('Chi')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() {
              _type = s.first;
              _excludeFromTotals = false;
              _groupKey = null;
            }),
          ),
          const SizedBox(height: 18),
          const Text(
            'Thuộc nhóm',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          if (_type == TransactionType.income)
            SegmentedButton<bool>(
              key: const Key('category_group'),
              segments: const [
                ButtonSegment(value: false, label: Text('Doanh thu')),
                ButtonSegment(value: true, label: Text('Khoản thu khác')),
              ],
              selected: {_excludeFromTotals},
              onSelectionChanged: (s) =>
                  setState(() => _excludeFromTotals = s.first),
            )
          else
            SegmentedButton<bool>(
              key: const Key('category_group'),
              segments: const [
                ButtonSegment(value: false, label: Text('Chi tiêu')),
                ButtonSegment(value: true, label: Text('Chi phí kinh doanh')),
              ],
              selected: {_groupKey == CategoryGroupKey.businessExpense},
              onSelectionChanged: (s) => setState(
                () => _groupKey = s.first
                    ? CategoryGroupKey.businessExpense
                    : null,
              ),
            ),
          const SizedBox(height: 8),
          InkWell(
            key: const Key('category_advanced_toggle'),
            onTap: () => setState(() => _advancedOpen = !_advancedOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(
                    _advancedOpen
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Tuỳ chọn nâng cao',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_advancedOpen) ..._advancedSection(),
          if (_duplicateCategory != null) _duplicateCategoryNotice(),
          const SizedBox(height: 12),
          ElevatedButton(
            key: const Key('category_save'),
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

  Widget _duplicateCategoryNotice() {
    final c = _duplicateCategory!;
    return Padding(
      key: const Key('category_duplicate_notice'),
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              c.isActive
                  ? 'Đã có danh mục tên này.'
                  : 'Danh mục này đã tồn tại nhưng đang ngừng sử dụng.',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.expenseAmount,
              ),
            ),
          ),
          if (!c.isActive)
            _StatusAction(
              key: const Key('category_duplicate_reuse'),
              label: 'Sử dụng lại',
              onPressed: () => _reuseDuplicateCategory(c),
            ),
        ],
      ),
    );
  }

  List<Widget> _advancedSection() {
    final hasActiveStatus = _statuses.any((s) => s.isActive);

    return [
      const Text(
        'Màu',
        style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
      ),
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
        'Theo dõi tiến độ',
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 2),
      const Text(
        'Tuỳ chọn — ví dụ: Chưa chuẩn bị → Đã chuẩn bị → Đã gửi. Để trống nếu không cần.',
        style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
      ),
      const SizedBox(height: 8),
      ..._statusSection(),
      if (hasActiveStatus) ...[
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Hiện ở màn Tổng hợp'),
          subtitle: const Text('Xem tổng tiền theo từng bước tiến độ'),
          value: _statsEnabled,
          onChanged: (v) => setState(() => _statsEnabled = v),
        ),
      ],
      const SizedBox(height: 8),
    ];
  }

  List<Widget> _statusSection() {
    final active = _statuses.where((s) => s.isActive).toList();
    final stopped = _statuses.where((s) => !s.isActive).toList();
    final deletable = ref.watch(deletableStatusIdsProvider);
    // Chỉ bước ĐÃ LƯU là ngừng sử dụng mới có thể xoá hẳn (bước vừa bấm
    // "Ngừng sử dụng" trong bản nháp thì phải Lưu trước).
    bool canDelete(Status s) =>
        deletable.contains(s.id) &&
        _originalStatuses.any((o) => o.id == s.id && !o.isActive);
    final categories =
        ref.watch(categoriesStreamProvider).valueOrNull ?? const <Category>[];
    final transactions = ref.watch(transactionsStreamProvider).valueOrNull ??
        const <Transaction>[];
    // Bước đã lưu + ngừng sử dụng nhưng chưa xóa hẳn được (còn giao dịch giữ).
    final heldStopped = [
      for (final s in stopped)
        if (_originalStatuses.any((o) => o.id == s.id && !o.isActive) &&
            !deletable.contains(s.id))
          s,
    ];
    DeletionCheckResult checkOf(Status s) =>
        checkStatusDeletion(s.id, categories, transactions);
    final duplicate = _duplicateStatusId == null
        ? null
        : _statuses.where((s) => s.id == _duplicateStatusId).firstOrNull;

    return [
      if (active.isNotEmpty) ...[
        const Text(
          'Đang sử dụng',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        for (final s in active)
          Padding(
            key: Key('status_${s.id}'),
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(child: Text(s.name)),
                _StatusAction(
                  key: Key('status_edit_${s.id}'),
                  label: 'Sửa',
                  onPressed: () => _renameStatus(s),
                ),
                _StatusAction(
                  key: Key('status_stop_${s.id}'),
                  label: 'Ngừng sử dụng',
                  onPressed: () => _stopUsingStatus(s),
                ),
              ],
            ),
          ),
      ],
      Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('status_add_field'),
              controller: _newStatusController,
              decoration: const InputDecoration(hintText: '+ Thêm trạng thái'),
              onChanged: (_) {
                if (_duplicateStatusId != null) {
                  setState(() => _duplicateStatusId = null);
                }
              },
              onSubmitted: (_) => _addStatus(),
            ),
          ),
          IconButton(
            key: const Key('status_add_button'),
            icon: const Icon(Icons.add_circle),
            onPressed: _addStatus,
          ),
        ],
      ),
      if (duplicate != null)
        Padding(
          key: const Key('status_duplicate_notice'),
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  duplicate.isActive
                      ? 'Trạng thái này đã có.'
                      : 'Trạng thái này đã tồn tại nhưng đang ngừng sử dụng.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.expenseAmount,
                  ),
                ),
              ),
              if (!duplicate.isActive)
                _StatusAction(
                  key: const Key('status_duplicate_reuse'),
                  label: 'Sử dụng lại',
                  onPressed: () => _reuseStatus(duplicate),
                ),
            ],
          ),
        ),
      if (stopped.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text(
          'Ngừng sử dụng (${stopped.length})',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        for (final s in stopped)
          Padding(
            key: Key('status_${s.id}'),
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.name,
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ),
                _StatusAction(
                  key: Key('status_reuse_${s.id}'),
                  label: 'Sử dụng lại',
                  onPressed: () => _reuseStatus(s),
                ),
                if (heldStopped.contains(s) &&
                    checkOf(s).transactionBlockers.isNotEmpty)
                  _StatusAction(
                    key: Key('status_blockers_${s.id}'),
                    label: 'Xem giao dịch',
                    onPressed: () => showBlockingTransactions(
                      context,
                      title: 'Chưa thể xóa "${s.name}"',
                      message:
                          'Trạng thái này đang được ${checkOf(s).transactionBlockers.length} giao dịch sử dụng.',
                      blockers: checkOf(s).blockers,
                    ),
                  ),
                if (heldStopped.contains(s) && checkOf(s).hasHiddenHistory)
                  _StatusAction(
                    key: Key('status_purge_${s.id}'),
                    label: 'Dọn lịch sử đã xóa',
                    onPressed: () => ref
                        .read(transactionRepositoryProvider)
                        .purgeDeletedHistoryForStatus(s.id),
                  ),
                if (canDelete(s))
                  _StatusAction(
                    key: Key('status_delete_${s.id}'),
                    label: 'Xóa hẳn',
                    onPressed: () => _deleteStatusPermanently(s),
                  ),
              ],
            ),
          ),
        if (heldStopped.isNotEmpty)
          Padding(
            key: const Key('status_used_note'),
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              heldStopped.any((s) => checkOf(s).transactionBlockers.isNotEmpty)
                  ? 'Bước đang được giao dịch sử dụng chưa thể xóa hẳn — bấm "Xem giao dịch" để mở và sửa.'
                  : 'Còn lịch sử đã xóa/sửa trước đây (đang ẩn) — dọn lịch sử để xóa hẳn.',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textMuted,
              ),
            ),
          ),
      ],
    ];
  }
}

class _StatusAction extends StatelessWidget {
  const _StatusAction({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}
