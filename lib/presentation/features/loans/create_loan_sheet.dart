import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/commands/create_obligation_command.dart';
import '../../../core/constants/default_categories.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/id_generator.dart';
import '../../../domain/entities/counterparty.dart';
import '../../../domain/entities/family_member.dart';
import '../../../domain/entities/obligation.dart';
import '../../../domain/entities/obligation_direction.dart';
import '../../../domain/entities/pool_kind.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../widgets/amount_input_formatter.dart';
import '../../widgets/amount_preview.dart';
import '../../widgets/sheet_error_banner.dart';
import '../../widgets/tap_guard.dart';
import '../../providers/counterparty_providers.dart';
import '../../providers/obligation_providers.dart';
import '../../providers/transaction_providers.dart';
import 'loan_error_mapping.dart';

/// Phase 8.8 — "Cho vay"/"Đi vay" (mục 9/11). Presentation KHÔNG tự build
/// financial effect. The opening command uses the shared factory, then the
/// atomic CreateObligationUseCase commits metadata + opening together.
Future<void> showCreateLoanSheet(
  BuildContext context, {
  required ObligationDirection direction,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (context) => CreateLoanSheet(direction: direction),
  );
}

class CreateLoanSheet extends ConsumerStatefulWidget {
  const CreateLoanSheet({super.key, required this.direction});

  final ObligationDirection direction;

  @override
  ConsumerState<CreateLoanSheet> createState() => _CreateLoanSheetState();
}

class _CreateLoanSheetState extends ConsumerState<CreateLoanSheet> {
  final _counterpartyController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  FamilyMember _member = FamilyMember.vo;
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  DateTime? _dueDate;
  bool _submitting = false;

  // Frozen state — đóng băng dần qua các bước để 1 lần retry (sau lỗi giữa
  // chừng, KHÔNG đổi form) không tạo trùng Counterparty/Obligation/giao dịch
  // (mục 21 — double-submit; Counterparty/Obligation KHÔNG có clientTxId
  // riêng nên Presentation tự đảm bảo mỗi bước chỉ chạy đúng 1 lần).
  String? _resolvedCounterpartyId;
  Counterparty? _counterpartyToCreate;
  bool _counterpartyPersisted = false;
  CreateObligationCommand? _pendingCommand;

  @override
  void dispose() {
    _counterpartyController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// Lỗi của lần Lưu gần nhất — hiện NGAY TRONG sheet (F1: SnackBar bị che sau
  /// lớp modal). Xoá khi người dùng đổi form hoặc bấm Lưu lại.
  String? _errorText;

  void _resetPending() {
    if (_submitting) return;
    _errorText = null;
    _resolvedCounterpartyId = null;
    _counterpartyToCreate = null;
    _counterpartyPersisted = false;
    _pendingCommand = null;
  }

  Future<void> _pickDate({required bool isDueDate}) async {
    if (_submitting) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: isDueDate ? (_dueDate ?? _date) : _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked == null || !mounted || _submitting) return;
    setState(() {
      _resetPending();
      if (isDueDate) {
        _dueDate = picked;
      } else {
        _date = picked;
      }
    });
  }

  bool get _isReceivable => widget.direction == ObligationDirection.receivable;

  Future<void> _save(List<Counterparty> counterparties) async {
    if (_submitting) return;
    final amount = int.tryParse(_amountController.text.trim()) ?? 0;
    final name = _counterpartyController.text.trim();
    if (amount <= 0 || name.isEmpty) return;

    setState(() {
      _submitting = true;
      _errorText = null;
    });
    try {
      if (_resolvedCounterpartyId == null) {
        Counterparty? existing;
        for (final c in counterparties) {
          if (c.displayName.toLowerCase() == name.toLowerCase()) {
            existing = c;
            break;
          }
        }
        if (existing != null) {
          _resolvedCounterpartyId = existing.id;
          _counterpartyPersisted = true;
        } else {
          _counterpartyToCreate = Counterparty(
            id: IdGenerator.generate(),
            displayName: name,
          );
          _resolvedCounterpartyId = _counterpartyToCreate!.id;
        }
      }
      if (_pendingCommand == null) {
        // Capture EVERY form value before awaiting currency resolution or I/O.
        final obligation = Obligation(
          id: IdGenerator.generate(),
          counterpartyId: _resolvedCounterpartyId!,
          direction: widget.direction,
          dueDate: _dueDate,
          note: _noteController.text.trim(),
        );
        final opening = await ref
            .read(createTransactionCommandFactoryProvider)
            .create(
              type: _isReceivable
                  ? TransactionType.transfer
                  : TransactionType.income,
              categoryId: _isReceivable
                  ? DefaultCategories.choVay.id
                  : DefaultCategories.vayNo.id,
              sourceKind: _isReceivable
                  ? PoolKind.memberAvailable
                  : PoolKind.external,
              sourceRefId: _isReceivable ? _member.name : null,
              destinationKind: _isReceivable
                  ? PoolKind.receivable
                  : PoolKind.memberAvailable,
              destinationRefId: _isReceivable ? obligation.id : _member.name,
              amountMinor: amount,
              transactionDate: _date,
              note: _noteController.text.trim(),
              obligationId: obligation.id,
            );
        _pendingCommand = CreateObligationCommand(
          obligation: obligation,
          opening: opening,
        );
      }
      if (!_counterpartyPersisted && _counterpartyToCreate != null) {
        await ref
            .read(counterpartyRepositoryProvider)
            .addCounterparty(_counterpartyToCreate!);
        _counterpartyPersisted = true;
      }
      await ref.read(createObligationUseCaseProvider)(_pendingCommand!);

      if (mounted) closeSheetAfterSave(context, ref);
    } catch (error) {
      if (mounted) setState(() => _errorText = mapLoanError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final counterpartiesAsync = ref.watch(counterpartiesStreamProvider);
    final counterparties = counterpartiesAsync.value ?? const <Counterparty>[];
    final suggestions = _counterpartyController.text.trim().isEmpty
        ? counterparties
        : counterparties
              .where(
                (c) => c.displayName.toLowerCase().contains(
                  _counterpartyController.text.trim().toLowerCase(),
                ),
              )
              .toList();
    final amount = int.tryParse(_amountController.text.trim()) ?? 0;
    final canSave =
        amount > 0 &&
        _counterpartyController.text.trim().isNotEmpty &&
        !_submitting;

    return PopScope(
      canPop: !_submitting,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          shouldCloseOnMinExtent: false,
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
                          _isReceivable ? 'Cho vay' : 'Đi vay',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        IconButton(
                          onPressed: _submitting
                              ? null
                              : () => Navigator.of(context).pop(),
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
                        _FieldLabel(
                          _isReceivable ? 'Người vay' : 'Người cho vay',
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          key: const Key('createLoan_counterparty'),
                          enabled: !_submitting,
                          controller: _counterpartyController,
                          onChanged: (_) => setState(_resetPending),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                            hintText: 'Nhập tên...',
                          ),
                        ),
                        if (suggestions.isNotEmpty &&
                            _counterpartyController.text.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: suggestions
                                .map(
                                  (c) => ActionChip(
                                    label: Text(c.displayName),
                                    onPressed: _submitting
                                        ? null
                                        : () => setState(() {
                                            _counterpartyController.text =
                                                c.displayName;
                                            _resetPending();
                                          }),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                        const SizedBox(height: 16),
                        _FieldLabel('Số tiền'),
                        const SizedBox(height: 6),
                        TextField(
                          key: const Key('createLoan_amount'),
                          enabled: !_submitting,
                          controller: _amountController,
                          keyboardType: TextInputType.number,
                          inputFormatters: const [AmountInputFormatter()],
                          onChanged: (_) => setState(_resetPending),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                            suffixText: 'đ',
                          ),
                        ),
                        AmountPreview(amountMinor: amount),
                        const SizedBox(height: 16),
                        _FieldLabel('Ngày'),
                        const SizedBox(height: 6),
                        OutlinedButton.icon(
                          onPressed: _submitting
                              ? null
                              : () => _pickDate(isDueDate: false),
                          icon: const Icon(
                            Icons.calendar_today_rounded,
                            size: 16,
                          ),
                          label: Text(Formatters.dayMonthYear(_date)),
                        ),
                        const SizedBox(height: 16),
                        _FieldLabel('Hạn trả (không bắt buộc)'),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _submitting
                                  ? null
                                  : () => _pickDate(isDueDate: true),
                              icon: const Icon(Icons.event_rounded, size: 16),
                              label: Text(
                                _dueDate == null
                                    ? 'Chọn ngày'
                                    : Formatters.dayMonthYear(_dueDate!),
                              ),
                            ),
                            if (_dueDate != null)
                              IconButton(
                                onPressed: _submitting
                                    ? null
                                    : () => setState(() {
                                        _resetPending();
                                        _dueDate = null;
                                      }),
                                icon: const Icon(Icons.close_rounded, size: 18),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _FieldLabel(
                          _isReceivable
                              ? 'Người cho vay / nguồn tiền'
                              : 'Người nhận tiền',
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<FamilyMember>(
                          segments: FamilyMember.values
                              .map(
                                (m) => ButtonSegment(
                                  value: m,
                                  label: Text(m.label),
                                ),
                              )
                              .toList(),
                          selected: {_member},
                          onSelectionChanged: _submitting
                              ? null
                              : (s) => setState(() {
                                  _resetPending();
                                  _member = s.first;
                                }),
                        ),
                        const SizedBox(height: 16),
                        _FieldLabel('Ghi chú (không bắt buộc)'),
                        const SizedBox(height: 6),
                        TextField(
                          key: const Key('createLoan_note'),
                          enabled: !_submitting,
                          controller: _noteController,
                          onChanged: (_) => setState(_resetPending),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      8,
                      20,
                      12 + MediaQuery.of(context).padding.bottom,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_errorText != null) ...[
                          SheetErrorBanner(message: _errorText!),
                          const SizedBox(height: 12),
                        ],
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            key: const Key('createLoan_save'),
                            onPressed: canSave
                                ? () => _save(counterparties)
                                : null,
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
                              _submitting
                                  ? 'Đang lưu...'
                                  : (_isReceivable
                                        ? 'Lưu khoản cho vay'
                                        : 'Lưu khoản đi vay'),
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
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: AppColors.textMuted,
        letterSpacing: 0.3,
      ),
    );
  }
}
