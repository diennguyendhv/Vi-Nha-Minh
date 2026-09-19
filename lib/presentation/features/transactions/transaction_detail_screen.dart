import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/status.dart';
import '../../../domain/entities/family_member.dart';
import '../../../domain/entities/pool_kind.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../../domain/errors/domain_exceptions.dart';
import '../../../domain/usecases/compute_recovery_summary.dart';
import '../../providers/category_providers.dart';
import '../../providers/feature_providers.dart';
import '../../providers/obligation_providers.dart';
import '../../providers/transaction_providers.dart';
import '../../widgets/amount_input_formatter.dart';
import '../../widgets/amount_preview.dart';
import '../add_transaction/add_transaction_sheet.dart';
import '../loans/loan_detail_screen.dart';

/// Màn "Chi tiết giao dịch" (`docs/design.html` màn 11) — sửa được toàn bộ:
/// hạng mục (trong cùng loại Thu/Chi/Chuyển gốc), số tiền, ghi chú, người
/// tiêu, ngày tháng, trạng thái. `amountMinor`/người tiêu ảnh hưởng balance
/// nên tự động đi qua reversal ledger (mục 21) — các field còn lại update
/// thẳng. Không đổi được LOẠI giao dịch (Thu/Chi/Chuyển) — nhập sai loại
/// thì xoá rồi ghi lại từ màn Thêm giao dịch.
class TransactionDetailScreen extends ConsumerStatefulWidget {
  const TransactionDetailScreen({super.key, required this.transactionId});

  final String transactionId;

  @override
  ConsumerState<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState
    extends ConsumerState<TransactionDetailScreen> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  bool _initialized = false;

  /// Chặn double-tap Lưu/Xoá (Phase 7 mục 11) — 2 hành động dùng chung 1 cờ
  /// vì loại trừ lẫn nhau trên cùng 1 giao dịch (không thể vừa sửa vừa xoá
  /// cùng lúc). KHÔNG thay thế bảo vệ thật của Repository
  /// (`AlreadyReversedException`/idempotency) — chỉ là UX guard.
  bool _submitting = false;

  late String _categoryId;
  late DateTime _transactionDate;
  String? _statusId;

  /// Các bước có thể chọn: các bước ĐANG DÙNG của hạng mục, cộng thêm bước
  /// hiện tại của giao dịch nếu nó đã bị ẩn (để giao dịch lịch sử vẫn hiển
  /// thị đúng trạng thái của nó, không bị đổi ngầm).
  List<Status> _statusChoices(Category category) {
    final choices = category.activeStatuses;
    final current = category.statusById(_statusId);
    if (current != null && !current.isActive) return [...choices, current];
    return choices;
  }

  String? _statusValue(Category category) {
    final choices = _statusChoices(category);
    if (choices.any((s) => s.id == _statusId)) return _statusId;
    return choices.isEmpty ? null : choices.first.id;
  }

  FamilyMember? _member;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Transaction? _findTransaction(List<Transaction> all) {
    for (final t in all) {
      if (t.id == widget.transactionId) return t;
    }
    return null;
  }

  // Re-check the stream snapshot as well as the captured callback argument.
  // A callback or confirmation dialog can outlive the frame that created it.
  // This is Presentation containment; repository protection remains separate.
  bool _canMutateGeneric(Transaction captured) {
    if (!mounted || captured.obligationId != null) return false;
    final latest = _findTransaction(
      ref.read(transactionsStreamProvider).valueOrNull ?? const [],
    );
    return latest != null &&
        latest.obligationId == null &&
        latest.reversedByTxId == null;
  }

  /// Chỉ khác null khi giao dịch có đúng 1 "người tiêu" rõ ràng có thể sửa
  /// — INCOME (người nhận) hoặc EXPENSE nguồn ví (người chi). TRANSFER và
  /// EXPENSE nguồn Quỹ không có field này để sửa.
  FamilyMember? _currentMember(Transaction t) {
    final refId = t.type == TransactionType.income
        ? t.destinationRefId
        : (t.type == TransactionType.expense &&
                  t.sourceKind == PoolKind.memberAvailable
              ? t.sourceRefId
              : null);
    if (refId == null) return null;
    for (final m in FamilyMember.values) {
      if (m.name == refId) return m;
    }
    return null;
  }

  /// Số tiền đang nhập (0 nếu trống/không hợp lệ) — Lưu bị khoá khi <= 0.
  int get _enteredAmount =>
      int.tryParse(_amountController.text.replaceAll('.', '')) ?? 0;

  void _initFrom(Transaction t) {
    _amountController.text = t.amountMinor.toString();
    _noteController.text = t.note;
    _categoryId = t.categoryId;
    _transactionDate = t.transactionDate;
    _statusId = t.statusId;
    _member = _currentMember(t);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _transactionDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _transactionDate = picked);
  }

  /// Canonical mutation path (Phase 7 mục 2/3/4/5): UI chỉ cung cấp Ý ĐỊNH
  /// (toàn bộ field hiện tại của form), `UpdateTransactionUseCase` →
  /// `TransactionRepository` (frozen) tự quyết định field nào ảnh hưởng
  /// balance (đi qua reversal ledger) hay update thẳng — KHÔNG phân biệt
  /// "financial vs non-financial" ở đây, tránh lặp lại logic đã có sẵn ở
  /// Repository (mục 4: "Do not duplicate logic... if Repository already
  /// owns that distinction").
  Future<void> _save(Transaction current) async {
    if (!_canMutateGeneric(current)) return;
    if (_submitting) return; // chặn double-tap.
    final newAmount = int.tryParse(_amountController.text.replaceAll('.', ''));
    if (newAmount == null || newAmount <= 0) return;

    setState(() => _submitting = true);
    try {
      await ref.read(updateTransactionUseCaseProvider)(
        current.id,
        amountMinor: newAmount,
        categoryId: _categoryId,
        note: _noteController.text.trim(),
        memberRefId: _member?.name,
        transactionDate: _transactionDate,
        statusId: _statusId,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Phase 8.6 mục 12 — mở lại ĐÚNG 1 nơi tạo giao dịch duy nhất
  /// (`add_transaction_sheet.dart`), truyền `recoveryTarget` để sheet tự
  /// khoá loại giao dịch/category, không dựng form/pipeline riêng nào ở
  /// đây.
  void _openRecoverySheet(Transaction current) {
    if (!_canMutateGeneric(current)) return;
    showAddTransactionSheet(context, recoveryTarget: current);
  }

  /// Reverse — Phase 7 mục 6: gọi thẳng `ReverseTransactionUseCase`, KHÔNG
  /// tự build bản hoàn tác/tính hiệu ứng ngược nào ở Presentation. Không
  /// xoá cứng — Repository (frozen) tạo bản reversal mới, đánh dấu
  /// `reversedByTxId` lên bản gốc.
  Future<void> _delete(Transaction current) async {
    if (!_canMutateGeneric(current)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá giao dịch này?'),
        content: const Text(
          'Giao dịch sẽ được hoàn tác (số dư trở lại đúng trước khi ghi) — vẫn lưu trong lịch sử để đối chiếu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huỷ'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!_canMutateGeneric(current)) return;
    if (_submitting) return; // chặn double-tap.

    setState(() => _submitting = true);
    try {
      await ref.read(reverseTransactionUseCaseProvider)(current.id);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Ánh xạ typed exception (Domain/Repository/Application, đã frozen) sang
  /// message tiếng Việt — Phase 7 mục 10. KHÔNG lộ SqliteException/message
  /// SQLite/tên class/stack trace. Trùng lặp có chủ đích với
  /// `add_transaction_sheet.dart._errorMessage` (không refactor màn Thêm
  /// giao dịch đã frozen ở Phase 6 chỉ để dùng chung 1 hàm nhỏ).
  String _errorMessage(Object error) {
    if (error is TransactionNotFoundException) {
      return 'Giao dịch không còn tồn tại — có thể đã bị xoá ở nơi khác.';
    }
    if (error is AlreadyReversedException) {
      return 'Giao dịch này đã được xử lý rồi, vui lòng tải lại.';
    }
    if (error is InvalidAmountException) return 'Số tiền không hợp lệ.';
    if (error is SameSourceDestinationException) {
      return 'Nguồn và đích không được trùng nhau.';
    }
    if (error is InsufficientBalanceException) {
      return 'Số dư không đủ để lưu thay đổi này.';
    }
    if (error is PersistenceConstraintException) {
      return 'Dữ liệu tham chiếu không hợp lệ, vui lòng thử lại.';
    }
    if (error is PersistenceException) {
      return 'Có lỗi khi lưu dữ liệu, vui lòng thử lại.';
    }
    return 'Có lỗi xảy ra, vui lòng thử lại.';
  }

  @override
  Widget build(BuildContext context) {
    final transactions =
        ref.watch(transactionsStreamProvider).valueOrNull ?? [];
    final categories = ref.watch(categoriesStreamProvider).valueOrNull ?? [];
    final transaction = _findTransaction(transactions);

    if (transaction == null) {
      return const Scaffold(
        body: Center(child: Text('Giao dịch không tồn tại.')),
      );
    }
    if (transaction.obligationId != null) {
      return _loanTransactionDetail(transaction, categories);
    }
    if (transaction.reversedByTxId != null) {
      return const Scaffold(
        body: Center(child: Text('Giao dịch này đã bị xoá.')),
      );
    }

    if (!_initialized) {
      _initFrom(transaction);
      _initialized = true;
    }

    Category? selectedCategory;
    for (final c in categories) {
      if (c.id == _categoryId) selectedCategory = c;
    }
    final sameTypeCategories = categories
        .where(
          (c) =>
              c.type == transaction.type && (c.isActive || c.id == _categoryId),
        )
        .toList();
    final canEditCategory = transaction.type != TransactionType.transfer;
    final canEditMember = _currentMember(transaction) != null;

    // Phase 8.6 — chỉ giao dịch Chi CHƯA từng là 1 khoản recovery mới được
    // phép làm target ("Hoàn tiền/Thu hồi") — khớp đúng
    // `validateRecoveryRelation` (target phải là expense, không phải
    // chain). Giao dịch đã bị hoàn tác không tới được đây (return sớm ở
    // trên) nên không cần check lại `reversedByTxId`.
    final canRecover =
        ref.watch(advancedFeaturesEnabledProvider) &&
        transaction.type == TransactionType.expense &&
        transaction.recoveryOfTxId == null;
    final recoverySummary = computeRecoverySummary(transaction, transactions);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Chi tiết giao dịch · ${Formatters.dayMonth(transaction.transactionDate)}',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'HẠNG MỤC',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          if (canEditCategory)
            DropdownButtonFormField<String>(
              value: sameTypeCategories.any((c) => c.id == _categoryId)
                  ? _categoryId
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: sameTypeCategories
                  .map(
                    (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                  )
                  .toList(),
              onChanged: (id) {
                if (id == null) return;
                setState(() {
                  _categoryId = id;
                  Category? newCategory;
                  for (final c in sameTypeCategories) {
                    if (c.id == id) newCategory = c;
                  }
                  // Đổi hạng mục có thể đổi luôn bộ statuses hợp lệ: giữ
                  // status hiện tại nếu nó thuộc hạng mục mới (kể cả đã ẩn —
                  // đó là trạng thái lịch sử của chính giao dịch này), ngược
                  // lại lấy bước ĐANG DÙNG đầu tiên (hoặc null).
                  if (newCategory != null &&
                      newCategory.statuses.every((s) => s.id != _statusId)) {
                    _statusId = newCategory.hasStatus
                        ? newCategory.activeStatuses.first.id
                        : null;
                  }
                });
              },
            )
          else
            _ReadOnlyRow(
              label: 'Danh mục hệ thống, không sửa được',
              value: selectedCategory?.name ?? '—',
            ),
          const SizedBox(height: 16),
          const Text(
            'SỐ TIỀN',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            key: const Key('detail_amount_field'),
            controller: _amountController,
            keyboardType: TextInputType.number,
            inputFormatters: const [AmountInputFormatter()],
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              suffixText: 'đ',
            ),
          ),
          AmountPreview(amountMinor: _enteredAmount),
          const SizedBox(height: 16),
          const Text(
            'GHI CHÚ',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          if (recoverySummary.totalRecovered > 0) ...[
            const SizedBox(height: 16),
            _RecoverySummaryCard(summary: recoverySummary),
          ],
          if (canEditMember) ...[
            const SizedBox(height: 16),
            const Text(
              'NGƯỜI TIÊU',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<FamilyMember>(
              segments: FamilyMember.values
                  .map((m) => ButtonSegment(value: m, label: Text(m.label)))
                  .toList(),
              selected: {_member ?? FamilyMember.vo},
              onSelectionChanged: (s) => setState(() => _member = s.first),
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            'NGÀY',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_rounded, size: 16),
            label: Text(
              '${_transactionDate.day.toString().padLeft(2, '0')}/'
              '${_transactionDate.month.toString().padLeft(2, '0')}/${_transactionDate.year}',
            ),
          ),
          if (selectedCategory != null &&
              _statusChoices(selectedCategory).isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'TRẠNG THÁI',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _statusValue(selectedCategory),
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: _statusChoices(selectedCategory)
                  .map(
                    (s) => DropdownMenuItem(
                      value: s.id,
                      child: Text(
                        s.isActive ? s.name : '${s.name} (ngừng sử dụng)',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (id) {
                if (id != null) setState(() => _statusId = id);
              },
            ),
            if (transaction.statusUpdatedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Cập nhật lần cuối: ${Formatters.dayMonth(transaction.statusUpdatedAt!)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: (_submitting || _enteredAmount <= 0)
                ? null
                : () => _save(transaction),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(_submitting ? 'Đang lưu...' : 'Lưu thay đổi'),
          ),
          if (canRecover) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _submitting
                  ? null
                  : () => _openRecoverySheet(transaction),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: const BorderSide(color: AppColors.accent),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Hoàn tiền / Thu hồi'),
            ),
          ],
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _submitting ? null : () => _delete(transaction),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.expenseAmount,
              side: const BorderSide(color: AppColors.expenseAmount),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Xoá giao dịch'),
          ),
        ],
      ),
    );
  }

  Widget _loanTransactionDetail(
    Transaction transaction,
    List<Category> categories,
  ) {
    final obligations = ref.watch(obligationsStreamProvider);
    final matches = obligations.valueOrNull?.where(
      (o) => o.id == transaction.obligationId,
    );
    final obligation = matches != null && matches.isNotEmpty
        ? matches.first
        : null;
    final categoryMatches = categories.where(
      (c) => c.id == transaction.categoryId,
    );
    final category = categoryMatches.isEmpty ? null : categoryMatches.first;
    final statuses = category?.statuses.where(
      (s) => s.id == transaction.statusId,
    );
    final member = _currentMember(transaction);

    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết giao dịch')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _ReadOnlyRow(label: 'Hạng mục', value: category?.name ?? '—'),
          const SizedBox(height: 16),
          _ReadOnlyRow(
            label: 'Số tiền',
            value: Formatters.amount(transaction.amountMinor),
          ),
          const SizedBox(height: 16),
          _ReadOnlyRow(
            label: 'Ngày',
            value: Formatters.dayMonthYear(transaction.transactionDate),
          ),
          const SizedBox(height: 16),
          _ReadOnlyRow(label: 'Ghi chú', value: transaction.note),
          if (member != null) ...[
            const SizedBox(height: 16),
            _ReadOnlyRow(label: 'Người tiêu', value: member.label),
          ],
          if (statuses != null && statuses.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ReadOnlyRow(label: 'Trạng thái', value: statuses.first.name),
          ],
          const SizedBox(height: 24),
          const Text(
            'Giao dịch này thuộc một khoản vay. Hãy quản lý giao dịch từ mục Vay & Cho vay.',
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed:
                obligation == null ||
                    obligations.isLoading ||
                    obligations.hasError
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LoanDetailScreen(
                        obligationId: obligation.id,
                        direction: obligation.direction,
                      ),
                    ),
                  ),
            child: const Text('Xem khoản vay'),
          ),
        ],
      ),
    );
  }
}

/// Phase 8.6 mục 13 — "Mua iPad 10.000.000đ / Đã thu hồi 2.800.000đ / Chi
/// phí ròng 7.200.000đ". Chỉ hiện khi `totalRecovered > 0` (đã có ít nhất 1
/// recovery đang hiệu lực) — netCost là derived metric HIỂN THỊ, không sửa
/// `amountMinor` của giao dịch gốc ở đâu cả.
class _RecoverySummaryCard extends StatelessWidget {
  const _RecoverySummaryCard({required this.summary});

  final RecoverySummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.incomeTile,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                summary.recoveries.length > 1
                    ? 'Đã thu hồi · ${summary.recoveries.length} giao dịch'
                    : 'Đã thu hồi',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                Formatters.amount(summary.totalRecovered),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Chi phí ròng',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                Formatters.amount(summary.netCost),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          // Phase 8.6B — chỉ hiện khi thu hồi VƯỢT chi phí gốc (bán có lãi):
          // phần vượt là lợi nhuận thật, đã được tính vào Tổng thu tháng
          // (`computeThreeTotals`/`computeFinancialSummary`) — không tự tính
          // lại ở đây, chỉ hiển thị field domain đã tính sẵn.
          if (summary.totalProfit > 0) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Lợi nhuận',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  Formatters.amount(summary.totalProfit),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            color: AppColors.textSecondary,
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
