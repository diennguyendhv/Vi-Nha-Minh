import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/commands/create_transaction_command.dart';
import '../../../core/constants/default_categories.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/family_member.dart';
import '../../../domain/entities/fund.dart';
import '../../../domain/entities/pool_kind.dart';
import '../../../domain/entities/savings_asset_type.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../../domain/entities/transfer_kind.dart';
import '../../../domain/errors/domain_exceptions.dart';
import '../../../domain/usecases/compute_pool_balance.dart';
import '../../providers/category_providers.dart';
import '../../providers/fund_providers.dart';
import '../../providers/savings_asset_type_providers.dart';
import '../../providers/transaction_providers.dart';

/// Snapshot bất biến (Dart record — so sánh cấu trúc bằng `==` tự động) của
/// TOÀN BỘ field ảnh hưởng "đây là logical request nào" — dùng để phát hiện
/// người dùng có đổi form sau 1 lần Lưu thất bại hay không (Phase 6 mục 10).
/// KHÔNG chứa `id`/`clientTxId`/`currency` — những field đó thuộc về
/// `CreateTransactionCommand` (Application layer), không phải "ý định" của
/// người dùng.
typedef _TransactionIntent = ({
  TransactionType type,
  TransferKind? transferKind,
  String categoryId,
  PoolKind sourceKind,
  String? sourceRefId,
  PoolKind destinationKind,
  String? destinationRefId,
  int amountMinor,
  DateTime transactionDate,
  String note,
  String? statusId,
  String? recoveryOfTxId,
});

/// Màn "Thêm giao dịch" (`docs/design.html` màn 09) — nơi tạo giao dịch DUY
/// NHẤT trong app: Nạp quỹ/Ghi khoản mua (màn Quỹ) và Rút về ví/Gửi ngân
/// hàng (màn Tiết kiệm) đều mở lại sheet này, chỉ khác panel/giá trị điền
/// sẵn. Sửa giao dịch đã ghi (chỉ amount + status) dùng
/// `transaction_detail_screen.dart` riêng, không dùng sheet này.
Future<void> showAddTransactionSheet(
  BuildContext context, {
  EntryType initialType = EntryType.chi,
  TransferSubKind? initialTransferSubKind,
  String? initialFundId,
  SavingsAction? initialSavingsAction,
  String? initialSavingsAssetTypeId,
  FamilyMember? initialMember,
  Transaction? recoveryTarget,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => AddTransactionSheet(
      initialType: initialType,
      initialTransferSubKind: initialTransferSubKind,
      initialFundId: initialFundId,
      initialSavingsAction: initialSavingsAction,
      initialSavingsAssetTypeId: initialSavingsAssetTypeId,
      initialMember: initialMember,
      recoveryTarget: recoveryTarget,
    ),
  );
}

String _dateLabel(DateTime date) {
  final now = DateTime.now();
  final isToday =
      date.year == now.year && date.month == now.month && date.day == now.day;
  final text = '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
  return isToday ? 'Hôm nay · $text' : text;
}

enum EntryType { thu, chi, chuyen }

enum TransferSubKind { member, fund, savings }

enum FundAction { topup, withdraw }

enum SavingsAction { topup, withdraw, convert }

class AddTransactionSheet extends ConsumerStatefulWidget {
  const AddTransactionSheet({
    super.key,
    this.initialType = EntryType.chi,
    this.initialTransferSubKind,
    this.initialFundId,
    this.initialSavingsAction,
    this.initialSavingsAssetTypeId,
    this.initialMember,
    this.recoveryTarget,
  });

  final EntryType initialType;
  final TransferSubKind? initialTransferSubKind;
  final String? initialFundId;
  final SavingsAction? initialSavingsAction;
  final String? initialSavingsAssetTypeId;
  final FamilyMember? initialMember;

  /// Phase 8.6 — khác null khi sheet mở ở chế độ "Hoàn tiền / Thu hồi" cho
  /// ĐÚNG giao dịch Chi này (mở từ nút trên Transaction Detail). Khoá loại
  /// giao dịch = Thu và category = `hoanTienThuHoi`; người nhận/số tiền/ghi
  /// chú/ngày vẫn tự do — người dùng không cần biết `TransactionType.income`/
  /// `excludeFromTotals`/`recoveryOfTxId` là gì (mục 12).
  final Transaction? recoveryTarget;

  @override
  ConsumerState<AddTransactionSheet> createState() =>
      _AddTransactionSheetState();
}

class _AddTransactionSheetState extends ConsumerState<AddTransactionSheet> {
  bool get _isRecoveryMode => widget.recoveryTarget != null;
  late EntryType _entryType =
      widget.recoveryTarget != null ? EntryType.thu : widget.initialType;
  String? _categoryId;
  late FamilyMember _member = widget.initialMember ?? FamilyMember.vo;
  String? _statusId;
  late String? _sourceFundId =
      widget.initialTransferSubKind == null ? widget.initialFundId : null;

  late TransferSubKind _transferSubKind =
      widget.initialTransferSubKind ?? TransferSubKind.member;
  FamilyMember _transferFrom = FamilyMember.vo;
  FamilyMember _transferTo = FamilyMember.chong;
  late String? _transferFundId =
      widget.initialTransferSubKind == TransferSubKind.fund
      ? widget.initialFundId
      : null;
  FundAction _fundAction = FundAction.topup;
  late SavingsAction _savingsAction =
      widget.initialSavingsAction ?? SavingsAction.topup;
  late String? _savingsAssetTypeId = widget.initialSavingsAssetTypeId;
  String? _savingsTargetAssetTypeId;

  String _amountDigits = '';
  String _note = '';
  DateTime _transactionDate = DateTime.now();

  /// Logical request đã "đóng băng" từ lần bấm Lưu gần nhất chưa thành công
  /// — Phase 6 mục 9/10. `null` nghĩa là chưa có gì đang chờ (form sạch,
  /// hoặc lần Lưu trước đã thành công/command trước đã bị vô hiệu).
  CreateTransactionCommand? _pendingCommand;

  /// Snapshot các field logic tại thời điểm `_pendingCommand` được tạo —
  /// dùng để phát hiện người dùng đã đổi form hay chưa trước khi quyết định
  /// tái sử dụng `_pendingCommand` hay tạo command mới.
  _TransactionIntent? _pendingIntent;

  /// Chặn double-tap (Phase 6 mục 11) — bảo vệ UX, KHÔNG thay thế idempotency
  /// thật của Repository (`clientTxId`, đã frozen từ Phase 3).
  bool _submitting = false;

  int get _amount =>
      int.tryParse(_amountDigits.isEmpty ? '0' : _amountDigits) ?? 0;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _transactionDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _transactionDate = picked);
  }

  void _pressKey(String key) {
    setState(() {
      if (key == '⌫') {
        _amountDigits = _amountDigits.isEmpty
            ? ''
            : _amountDigits.substring(0, _amountDigits.length - 1);
        return;
      }
      final next = (_amountDigits + key).replaceFirst(RegExp(r'^0+(?=\d)'), '');
      if (next.length > 9) return;
      _amountDigits = next;
    });
  }

  Category? _findCategory(List<Category> categories, String? id) {
    if (id == null) return null;
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  void _pickCategory(Category category) {
    setState(() {
      _categoryId = category.id;
      _statusId = category.hasStatus ? category.statuses.first.id : null;
    });
  }

  /// Canonical write path (Phase 6 mục 3/4/5/9/10):
  /// intent form → (reuse hoặc tạo mới) `CreateTransactionCommand` qua
  /// `createTransactionCommandFactoryProvider` → `addTransactionUseCaseProvider`.
  /// KHÔNG tự build `Transaction`, KHÔNG tự sinh `clientTxId`, KHÔNG tự đọc
  /// `CurrencyContext` — tất cả đã thuộc trách nhiệm Application layer.
  Future<void> _save(List<Category> categories) async {
    if (_submitting) return; // chặn double-tap — mục 11.
    final intent = _buildLogicalIntent(categories);
    if (intent == null) return;

    setState(() => _submitting = true);
    try {
      CreateTransactionCommand command;
      if (_pendingCommand != null && _pendingIntent == intent) {
        // Retry đúng nghĩa: form không đổi từ lần Lưu trước → tái sử dụng
        // NGUYÊN VẸN command cũ (cùng clientTxId/transactionDate/payload) —
        // mục 6/9. KHÔNG gọi factory.create() lại ở đây.
        command = _pendingCommand!;
      } else {
        // Logical request MỚI (lần đầu, hoặc form đã đổi sau lần Lưu trước
        // — mục 10) → tạo command mới, đóng băng đúng 1 lần.
        command = await ref
            .read(createTransactionCommandFactoryProvider)
            .create(
              type: intent.type,
              transferKind: intent.transferKind,
              categoryId: intent.categoryId,
              sourceKind: intent.sourceKind,
              sourceRefId: intent.sourceRefId,
              destinationKind: intent.destinationKind,
              destinationRefId: intent.destinationRefId,
              amountMinor: intent.amountMinor,
              transactionDate: intent.transactionDate,
              note: intent.note,
              statusId: intent.statusId,
              recoveryOfTxId: intent.recoveryOfTxId,
            );
        _pendingCommand = command;
        _pendingIntent = intent;
      }

      await ref.read(addTransactionUseCaseProvider)(command);

      // Thành công — dữ liệu mới sẽ tự trôi tới UI qua
      // transactionsStreamProvider (Drift stream → Repository →
      // WatchTransactionsUseCase), KHÔNG tự thêm vào state nào ở đây (mục 20/21).
      _pendingCommand = null;
      _pendingIntent = null;
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (error is ClientTxIdConflictException) {
        // Xung đột thật trên chính clientTxId đang giữ — retry lại với cùng
        // command sẽ luôn xung đột nữa, nên vô hiệu hoá để lần Lưu kế tiếp
        // bắt buộc tạo command mới (mục 19 — không âm thầm sinh clientTxId
        // mới rồi tự retry ở đây).
        _pendingCommand = null;
        _pendingIntent = null;
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Ánh xạ typed exception (Domain/Repository/Application, đã frozen) sang
  /// message tiếng Việt cho người dùng — Phase 6 mục 18. KHÔNG lộ message
  /// SQLite/tên class/stack trace. Đặt ở Presentation, KHÔNG đổi thành
  /// string ở Provider/Application.
  String _errorMessage(Object error) {
    if (error is InvalidAmountException) return 'Số tiền không hợp lệ.';
    if (error is SameSourceDestinationException) {
      return 'Nguồn và đích không được trùng nhau.';
    }
    if (error is InsufficientBalanceException) {
      return 'Số dư không đủ để ghi giao dịch này.';
    }
    if (error is ClientTxIdConflictException) {
      return 'Giao dịch bị xung đột, vui lòng thử lưu lại.';
    }
    if (error is InvalidRecoveryTargetException) {
      return 'Giao dịch gốc không còn phù hợp để hoàn tiền/thu hồi (có thể đã bị xoá hoặc thay đổi) — vui lòng thử lại.';
    }
    if (error is PersistenceConstraintException) {
      return 'Dữ liệu tham chiếu không hợp lệ, vui lòng thử lại.';
    }
    if (error is PersistenceException) {
      return 'Có lỗi khi lưu dữ liệu, vui lòng thử lại.';
    }
    return 'Có lỗi xảy ra, vui lòng thử lại.';
  }

  /// "Ý định" của người dùng hiện tại trên form — thay thế `_buildTransaction`
  /// cũ (Phase 6 mục 4): CHỈ trả field logic (không `id`/`clientTxId`/
  /// `createdAt`/`currency`), giữ NGUYÊN VẸN mọi nhánh mapping UI→pool đã có
  /// từ trước (Thu/Chi/Chuyển × thành viên/quỹ/tiết kiệm) — không đổi hành
  /// vi nghiệp vụ nào, chỉ đổi kiểu dữ liệu trả về.
  _TransactionIntent? _buildLogicalIntent(List<Category> categories) {
    if (_amount <= 0) return null;

    // Phase 8.6 — chế độ "Hoàn tiền / Thu hồi": intent riêng, KHÔNG đi qua
    // category picker thường (khoá cứng `hoanTienThuHoi`), gắn thêm
    // `recoveryOfTxId` trỏ về đúng giao dịch Chi gốc đã mở sheet này.
    if (_isRecoveryMode) {
      final target = widget.recoveryTarget!;
      return (
        type: TransactionType.income,
        transferKind: null,
        categoryId: DefaultCategories.hoanTienThuHoi.id,
        sourceKind: PoolKind.external,
        sourceRefId: null,
        destinationKind: PoolKind.memberAvailable,
        destinationRefId: _member.name,
        amountMinor: _amount,
        transactionDate: _transactionDate,
        note: _note,
        statusId: null,
        recoveryOfTxId: target.id,
      );
    }

    switch (_entryType) {
      case EntryType.thu:
        final category = _findCategory(categories, _categoryId);
        if (category == null) return null;
        return (
          type: TransactionType.income,
          transferKind: null,
          categoryId: category.id,
          sourceKind: PoolKind.external,
          sourceRefId: null,
          destinationKind: PoolKind.memberAvailable,
          destinationRefId: _member.name,
          amountMinor: _amount,
          transactionDate: _transactionDate,
          note: _note,
          statusId: category.hasStatus ? _statusId : null,
          recoveryOfTxId: null,
        );

      case EntryType.chi:
        final category = _findCategory(categories, _categoryId);
        if (category == null) return null;
        final fundId = _sourceFundId;
        return (
          type: TransactionType.expense,
          transferKind: null,
          categoryId: category.id,
          sourceKind: fundId == null ? PoolKind.memberAvailable : PoolKind.fund,
          sourceRefId: fundId ?? _member.name,
          destinationKind: PoolKind.external,
          destinationRefId: null,
          amountMinor: _amount,
          transactionDate: _transactionDate,
          note: _note,
          statusId: category.hasStatus ? _statusId : null,
          recoveryOfTxId: null,
        );

      case EntryType.chuyen:
        switch (_transferSubKind) {
          case TransferSubKind.member:
            if (_transferFrom == _transferTo) return null;
            return (
              type: TransactionType.transfer,
              transferKind: TransferKind.memberToMember,
              categoryId: DefaultCategories.chuyenTienThanhVien.id,
              sourceKind: PoolKind.memberAvailable,
              sourceRefId: _transferFrom.name,
              destinationKind: PoolKind.memberAvailable,
              destinationRefId: _transferTo.name,
              amountMinor: _amount,
              transactionDate: _transactionDate,
              note: _note,
              statusId: null,
              recoveryOfTxId: null,
            );
          case TransferSubKind.fund:
            final fundId = _transferFundId;
            if (fundId == null) return null;
            switch (_fundAction) {
              case FundAction.topup:
                return (
                  type: TransactionType.transfer,
                  transferKind: TransferKind.fundTopup,
                  categoryId: DefaultCategories.napQuy.id,
                  sourceKind: PoolKind.memberAvailable,
                  sourceRefId: _member.name,
                  destinationKind: PoolKind.fund,
                  destinationRefId: fundId,
                  amountMinor: _amount,
                  transactionDate: _transactionDate,
                  note: _note,
                  statusId: null,
                  recoveryOfTxId: null,
                );
              case FundAction.withdraw:
                return (
                  type: TransactionType.transfer,
                  transferKind: TransferKind.fundWithdraw,
                  categoryId: DefaultCategories.napQuy.id,
                  sourceKind: PoolKind.fund,
                  sourceRefId: fundId,
                  destinationKind: PoolKind.memberAvailable,
                  destinationRefId: _member.name,
                  amountMinor: _amount,
                  transactionDate: _transactionDate,
                  note: _note,
                  statusId: null,
                  recoveryOfTxId: null,
                );
            }
          case TransferSubKind.savings:
            final member = _member;
            final assetTypeId = _savingsAssetTypeId;
            if (assetTypeId == null) return null;
            switch (_savingsAction) {
              case SavingsAction.topup:
                return (
                  type: TransactionType.transfer,
                  transferKind: TransferKind.savingsTopup,
                  categoryId: DefaultCategories.tietKiem.id,
                  sourceKind: PoolKind.memberAvailable,
                  sourceRefId: member.name,
                  destinationKind: PoolKind.memberSavingsAsset,
                  destinationRefId: savingsAssetRefId(assetTypeId, member),
                  amountMinor: _amount,
                  transactionDate: _transactionDate,
                  note: _note,
                  statusId: null,
                  recoveryOfTxId: null,
                );
              case SavingsAction.withdraw:
                return (
                  type: TransactionType.transfer,
                  transferKind: TransferKind.savingsWithdraw,
                  categoryId: DefaultCategories.tietKiem.id,
                  sourceKind: PoolKind.memberSavingsAsset,
                  sourceRefId: savingsAssetRefId(assetTypeId, member),
                  destinationKind: PoolKind.memberAvailable,
                  destinationRefId: member.name,
                  amountMinor: _amount,
                  transactionDate: _transactionDate,
                  note: _note,
                  statusId: null,
                  recoveryOfTxId: null,
                );
              case SavingsAction.convert:
                final targetId = _savingsTargetAssetTypeId;
                if (targetId == null || targetId == assetTypeId) return null;
                return (
                  type: TransactionType.transfer,
                  transferKind: TransferKind.savingsConvert,
                  categoryId: DefaultCategories.tietKiem.id,
                  sourceKind: PoolKind.memberSavingsAsset,
                  sourceRefId: savingsAssetRefId(assetTypeId, member),
                  destinationKind: PoolKind.memberSavingsAsset,
                  destinationRefId: savingsAssetRefId(targetId, member),
                  amountMinor: _amount,
                  transactionDate: _transactionDate,
                  note: _note,
                  statusId: null,
                  recoveryOfTxId: null,
                );
            }
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesStreamProvider).valueOrNull ?? [];
    final funds = ref.watch(fundsStreamProvider).valueOrNull ?? [];
    final transactions = ref.watch(transactionsStreamProvider).valueOrNull ?? [];
    final assetTypes = ref.watch(savingsAssetTypesStreamProvider).valueOrNull ?? [];

    final activeCategories = categories.where((c) => c.isActive).toList();
    final incomeCategories = activeCategories
        .where((c) => c.type == TransactionType.income)
        .toList();
    final expenseCategories = activeCategories
        .where((c) => c.type == TransactionType.expense)
        .toList();
    final activeFunds = funds.where((f) => f.isActive).toList();
    final activeAssetTypes = assetTypes.where((a) => a.isActive).toList();

    final canSave = !_submitting && _buildLogicalIntent(categories) != null;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E3DB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 12, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isRecoveryMode ? 'Hoàn tiền / Thu hồi' : 'Thêm giao dịch',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.chipBackground,
                        shape: const CircleBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
                  children: [
                    if (_isRecoveryMode)
                      _RecoveryTargetBanner(target: widget.recoveryTarget!)
                    else ...[
                      const _SectionLabel('Loại giao dịch'),
                      const SizedBox(height: 8),
                      _TypeSegmented(
                        value: _entryType,
                        onChanged: (t) => setState(() => _entryType = t),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        Formatters.amount(_amount),
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: TextButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_today_rounded, size: 14),
                        label: Text(_dateLabel(_transactionDate)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._buildPanel(
                      incomeCategories: incomeCategories,
                      expenseCategories: expenseCategories,
                      funds: activeFunds,
                      transactions: transactions,
                      assetTypes: activeAssetTypes,
                    ),
                    const SizedBox(height: 16),
                    const _SectionLabel('Ghi chú'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: DefaultCategories.quickNotes
                          .map(
                            (n) => _NoteChip(
                              label: n,
                              selected: n == _note,
                              onTap: () =>
                                  setState(() => _note = n == _note ? '' : n),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 14),
                    _Keypad(onKey: _pressKey),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: canSave ? () => _save(categories) : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          disabledBackgroundColor: AppColors.disabledButton,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        child: Text(
                          _submitting ? 'Đang lưu...' : 'Lưu giao dịch',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildPanel({
    required List<Category> incomeCategories,
    required List<Category> expenseCategories,
    required List<Fund> funds,
    required List<Transaction> transactions,
    required List<SavingsAssetType> assetTypes,
  }) {
    if (_isRecoveryMode) {
      return [
        const _SectionLabel('Người nhận'),
        const SizedBox(height: 8),
        _MemberToggle(
          member: _member,
          onChanged: (m) => setState(() => _member = m),
        ),
      ];
    }
    switch (_entryType) {
      case EntryType.thu:
        final category = _findCategory(incomeCategories, _categoryId);
        return [
          const _SectionLabel('Hạng mục'),
          const SizedBox(height: 8),
          _CategoryChipGrid(
            categories: incomeCategories,
            selectedId: _categoryId,
            onTap: _pickCategory,
          ),
          if (category != null && category.hasStatus) ...[
            const SizedBox(height: 16),
            const _SectionLabel('Trạng thái'),
            const SizedBox(height: 8),
            _StatusChips(
              category: category,
              selectedId: _statusId,
              onTap: (s) => setState(() => _statusId = s),
            ),
          ],
          const SizedBox(height: 16),
          const _SectionLabel('Người nhận'),
          const SizedBox(height: 8),
          _MemberToggle(
            member: _member,
            onChanged: (m) => setState(() => _member = m),
          ),
        ];

      case EntryType.chi:
        final category = _findCategory(expenseCategories, _categoryId);
        return [
          const _SectionLabel('Hạng mục'),
          const SizedBox(height: 8),
          _CategoryChipGrid(
            categories: expenseCategories,
            selectedId: _categoryId,
            onTap: _pickCategory,
          ),
          if (category != null && category.hasStatus) ...[
            const SizedBox(height: 16),
            const _SectionLabel('Trạng thái'),
            const SizedBox(height: 8),
            _StatusChips(
              category: category,
              selectedId: _statusId,
              onTap: (s) => setState(() => _statusId = s),
            ),
          ],
          const SizedBox(height: 16),
          const _SectionLabel('Người chi'),
          const SizedBox(height: 8),
          _MemberToggle(
            member: _member,
            onChanged: (m) => setState(() {
              _member = m;
              _sourceFundId = null;
            }),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('Nguồn tiền'),
          const SizedBox(height: 8),
          _FundPickRow(
            walletLabel: 'Ví của ${_member.label}',
            funds: funds,
            selectedFundId: _sourceFundId,
            amount: _amount,
            transactions: transactions,
            onSelect: (fundId) => setState(() => _sourceFundId = fundId),
          ),
        ];

      case EntryType.chuyen:
        return [
          const _SectionLabel('Loại chuyển'),
          const SizedBox(height: 8),
          _TransferSubSegmented(
            value: _transferSubKind,
            onChanged: (v) => setState(() => _transferSubKind = v),
          ),
          const SizedBox(height: 16),
          ..._buildTransferSubPanel(
            funds: funds,
            transactions: transactions,
            assetTypes: assetTypes,
          ),
        ];
    }
  }

  List<Widget> _buildTransferSubPanel({
    required List<Fund> funds,
    required List<Transaction> transactions,
    required List<SavingsAssetType> assetTypes,
  }) {
    switch (_transferSubKind) {
      case TransferSubKind.member:
        return [
          const _SectionLabel('Người gửi'),
          const SizedBox(height: 8),
          _MemberToggle(
            member: _transferFrom,
            onChanged: (m) => setState(() => _transferFrom = m),
          ),
          const SizedBox(height: 12),
          const _SectionLabel('Người nhận'),
          const SizedBox(height: 8),
          _MemberToggle(
            member: _transferTo,
            onChanged: (m) => setState(() => _transferTo = m),
          ),
        ];
      case TransferSubKind.fund:
        final isWithdraw = _fundAction == FundAction.withdraw;
        return [
          const _SectionLabel('Hành động'),
          const SizedBox(height: 8),
          _FundActionSegmented(
            value: _fundAction,
            onChanged: (v) => setState(() => _fundAction = v),
          ),
          const SizedBox(height: 12),
          _SectionLabel(isWithdraw ? 'Người nhận' : 'Người nạp'),
          const SizedBox(height: 8),
          _MemberToggle(
            member: _member,
            onChanged: (m) => setState(() => _member = m),
          ),
          const SizedBox(height: 12),
          _SectionLabel(isWithdraw ? 'Quỹ nguồn' : 'Quỹ đích'),
          const SizedBox(height: 8),
          _FundPickRow(
            walletLabel: null,
            funds: funds,
            selectedFundId: _transferFundId,
            amount: isWithdraw ? _amount : 0,
            transactions: transactions,
            onSelect: (fundId) => setState(() => _transferFundId = fundId),
          ),
        ];
      case TransferSubKind.savings:
        return [
          const _SectionLabel('Của ai'),
          const SizedBox(height: 8),
          _MemberToggle(
            member: _member,
            onChanged: (m) => setState(() => _member = m),
          ),
          const SizedBox(height: 12),
          const _SectionLabel('Hành động'),
          const SizedBox(height: 8),
          _SavingsActionSegmented(
            value: _savingsAction,
            onChanged: (v) => setState(() => _savingsAction = v),
          ),
          const SizedBox(height: 12),
          _SectionLabel(
            _savingsAction == SavingsAction.convert ? 'Từ loại tài sản' : 'Loại tài sản',
          ),
          const SizedBox(height: 8),
          _AssetTypeChipGrid(
            assetTypes: assetTypes,
            selectedId: _savingsAssetTypeId,
            onTap: (id) => setState(() {
              _savingsAssetTypeId = id;
              if (_savingsTargetAssetTypeId == id) _savingsTargetAssetTypeId = null;
            }),
          ),
          if (_savingsAction == SavingsAction.convert) ...[
            const SizedBox(height: 12),
            const _SectionLabel('Sang loại tài sản'),
            const SizedBox(height: 8),
            _AssetTypeChipGrid(
              assetTypes: assetTypes.where((a) => a.id != _savingsAssetTypeId).toList(),
              selectedId: _savingsTargetAssetTypeId,
              onTap: (id) => setState(() => _savingsTargetAssetTypeId = id),
            ),
          ],
        ];
    }
  }
}

/// Phase 8.6 — banner hiển thị ĐÚNG giao dịch Chi gốc đang được hoàn tiền/
/// thu hồi, khi sheet mở ở chế độ recovery. Chỉ hiển thị số tiền + ghi chú
/// gốc — không lộ bất kỳ thuật ngữ kỹ thuật nào (`TransactionType.income`/
/// `excludeFromTotals`/`recoveryOfTxId`, mục 12).
class _RecoveryTargetBanner extends StatelessWidget {
  const _RecoveryTargetBanner({required this.target});

  final Transaction target;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'HOÀN TIỀN / THU HỒI CHO',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            target.note.isEmpty ? 'Giao dịch chi' : target.note,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          Text(
            Formatters.amount(target.amountMinor),
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: AppColors.textMuted,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _TypeSegmented extends StatelessWidget {
  const _TypeSegmented({required this.value, required this.onChanged});

  final EntryType value;
  final ValueChanged<EntryType> onChanged;

  static const _labels = {
    EntryType.thu: 'Thu',
    EntryType.chi: 'Chi',
    EntryType.chuyen: 'Chuyển',
  };

  @override
  Widget build(BuildContext context) {
    return _Segmented<EntryType>(
      value: value,
      options: EntryType.values,
      labelOf: (t) => _labels[t]!,
      onChanged: onChanged,
    );
  }
}

class _TransferSubSegmented extends StatelessWidget {
  const _TransferSubSegmented({required this.value, required this.onChanged});

  final TransferSubKind value;
  final ValueChanged<TransferSubKind> onChanged;

  static const _labels = {
    TransferSubKind.member: 'Thành viên khác',
    TransferSubKind.fund: 'Nạp quỹ',
    TransferSubKind.savings: 'Tiết kiệm',
  };

  @override
  Widget build(BuildContext context) {
    return _Segmented<TransferSubKind>(
      value: value,
      options: TransferSubKind.values,
      labelOf: (t) => _labels[t]!,
      onChanged: onChanged,
    );
  }
}

class _FundActionSegmented extends StatelessWidget {
  const _FundActionSegmented({required this.value, required this.onChanged});

  final FundAction value;
  final ValueChanged<FundAction> onChanged;

  static const _labels = {
    FundAction.topup: 'Nạp vào quỹ',
    FundAction.withdraw: 'Rút khỏi quỹ',
  };

  @override
  Widget build(BuildContext context) {
    return _Segmented<FundAction>(
      value: value,
      options: FundAction.values,
      labelOf: (t) => _labels[t]!,
      onChanged: onChanged,
    );
  }
}

class _SavingsActionSegmented extends StatelessWidget {
  const _SavingsActionSegmented({required this.value, required this.onChanged});

  final SavingsAction value;
  final ValueChanged<SavingsAction> onChanged;

  static const _labels = {
    SavingsAction.topup: 'Nạp',
    SavingsAction.withdraw: 'Rút về ví',
    SavingsAction.convert: 'Chuyển đổi',
  };

  @override
  Widget build(BuildContext context) {
    return _Segmented<SavingsAction>(
      value: value,
      options: SavingsAction.values,
      labelOf: (t) => _labels[t]!,
      onChanged: onChanged,
    );
  }
}

class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    super.key,
  });

  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.chipBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: options.map((o) {
          final selected = o == value;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(o),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? AppColors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Text(
                  labelOf(o),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _MemberToggle extends StatelessWidget {
  const _MemberToggle({required this.member, required this.onChanged});

  final FamilyMember member;
  final ValueChanged<FamilyMember> onChanged;

  @override
  Widget build(BuildContext context) {
    return _Segmented<FamilyMember>(
      value: member,
      options: FamilyMember.values,
      labelOf: (m) => m.label,
      onChanged: onChanged,
    );
  }
}

class _CategoryChipGrid extends StatelessWidget {
  const _CategoryChipGrid({
    required this.categories,
    required this.selectedId,
    required this.onTap,
  });

  final List<Category> categories;
  final String? selectedId;
  final ValueChanged<Category> onTap;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return const Text(
        'Chưa có danh mục nào — tạo ở tab Danh mục trước.',
        style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
      );
    }
    final validSelectedId = categories.any((c) => c.id == selectedId) ? selectedId : null;
    return DropdownButtonFormField<String>(
      value: validSelectedId,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(),
      ),
      hint: const Text('Chọn hạng mục'),
      items: categories
          .map(
            (c) => DropdownMenuItem(
              value: c.id,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: c.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(c.name),
                ],
              ),
            ),
          )
          .toList(),
      onChanged: (id) {
        for (final c in categories) {
          if (c.id == id) {
            onTap(c);
            return;
          }
        }
      },
    );
  }
}

class _AssetTypeChipGrid extends StatelessWidget {
  const _AssetTypeChipGrid({
    required this.assetTypes,
    required this.selectedId,
    required this.onTap,
  });

  final List<SavingsAssetType> assetTypes;
  final String? selectedId;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    if (assetTypes.isEmpty) {
      return const Text(
        'Chưa có loại tài sản nào — tạo ở màn Tiết kiệm trước.',
        style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
      );
    }
    final validSelectedId = assetTypes.any((a) => a.id == selectedId) ? selectedId : null;
    return DropdownButtonFormField<String>(
      value: validSelectedId,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(),
      ),
      hint: const Text('Chọn loại tài sản'),
      items: assetTypes
          .map(
            (a) => DropdownMenuItem(
              value: a.id,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: a.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(a.name),
                ],
              ),
            ),
          )
          .toList(),
      onChanged: (id) {
        if (id != null) onTap(id);
      },
    );
  }
}

class _StatusChips extends StatelessWidget {
  const _StatusChips({
    required this.category,
    required this.selectedId,
    required this.onTap,
  });

  final Category category;
  final String? selectedId;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final validSelectedId =
        category.statuses.any((s) => s.id == selectedId) ? selectedId : null;
    return DropdownButtonFormField<String>(
      value: validSelectedId,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(),
      ),
      hint: const Text('Chọn trạng thái'),
      items: category.statuses
          .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
          .toList(),
      onChanged: (id) {
        if (id != null) onTap(id);
      },
    );
  }
}

class _FundPickRow extends StatelessWidget {
  const _FundPickRow({
    required this.walletLabel,
    required this.funds,
    required this.selectedFundId,
    required this.amount,
    required this.transactions,
    required this.onSelect,
  });

  /// null khi không có lựa chọn "Ví" (vd panel Nạp quỹ — luôn chọn 1 quỹ).
  final String? walletLabel;
  final List<Fund> funds;
  final String? selectedFundId;
  final int amount;
  final List<Transaction> transactions;
  final ValueChanged<String?> onSelect;

  List<DropdownMenuItem<String?>> _buildItems() {
    final items = <DropdownMenuItem<String?>>[
      if (walletLabel != null) DropdownMenuItem(value: null, child: Text(walletLabel!)),
    ];
    for (final f in funds) {
      final balance = computeFundBalance(f.id, transactions);
      final insufficient = amount > 0 && amount > balance;
      items.add(
        DropdownMenuItem(
          value: f.id,
          enabled: !insufficient,
          child: Text(
            '${f.name} — ${insufficient ? 'không đủ, ' : ''}còn ${Formatters.amount(balance)}',
            style: TextStyle(color: insufficient ? AppColors.textMuted : null),
          ),
        ),
      );
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      value: selectedFundId,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(),
      ),
      items: _buildItems(),
      onChanged: onSelect,
    );
  }
}

class _NoteChip extends StatelessWidget {
  const _NoteChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.14)
              : AppColors.chipBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.accent : const Color(0xFF4B4F49),
          ),
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onKey});

  final ValueChanged<String> onKey;

  static const _keys = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '000',
    '0',
    '⌫',
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.4,
      children: _keys
          .map(
            (k) => Material(
              color: AppColors.keypadTile,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onKey(k),
                child: Center(
                  child: Text(
                    k,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
