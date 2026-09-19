import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/commands/settle_obligation_command.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/id_generator.dart';
import '../../../domain/engine/obligation_settlement.dart';
import '../../../domain/entities/family_member.dart';
import '../../../domain/entities/obligation_direction.dart';
import '../../widgets/amount_input_formatter.dart';
import '../../widgets/amount_preview.dart';
import '../../widgets/sheet_error_banner.dart';
import '../../widgets/tap_guard.dart';
import '../../providers/obligation_providers.dart';
import 'loan_error_mapping.dart';

/// Phase 8.8 — "Nhận tiền"/"Trả tiền" (mục 13/15), và cũng dùng lại cho
/// "Sửa" 1 lần tất toán (mục 20, `correctingAnchorTransactionId != null`).
/// Preview gốc/lãi dùng ĐÚNG [buildObligationSettlementLegs] (thuần domain,
/// đã có từ Phase 8.7) — KHÔNG viết lại allocation math ở đây (mục 13).
Future<void> showSettleLoanSheet(
  BuildContext context, {
  required ObligationDirection direction,
  required String obligationId,
  required int outstandingBaseline,
  required String categoryId,
  required String interestCategoryId,
  FamilyMember initialMember = FamilyMember.vo,
  String? correctingAnchorTransactionId,
  int? initialAmountMinor,
  DateTime? initialDate,
  String initialNote = '',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (context) => SettleLoanSheet(
      direction: direction,
      obligationId: obligationId,
      outstandingBaseline: outstandingBaseline,
      categoryId: categoryId,
      interestCategoryId: interestCategoryId,
      initialMember: initialMember,
      correctingAnchorTransactionId: correctingAnchorTransactionId,
      initialAmountMinor: initialAmountMinor,
      initialDate: initialDate,
      initialNote: initialNote,
    ),
  );
}

class SettleLoanSheet extends ConsumerStatefulWidget {
  const SettleLoanSheet({
    super.key,
    required this.direction,
    required this.obligationId,
    required this.outstandingBaseline,
    required this.categoryId,
    required this.interestCategoryId,
    required this.initialMember,
    this.correctingAnchorTransactionId,
    this.initialAmountMinor,
    this.initialDate,
    this.initialNote = '',
  });

  final ObligationDirection direction;
  final String obligationId;

  /// Outstanding dùng để tính preview — với tất toán MỚI là outstanding
  /// hiện tại; với SỬA 1 lần tất toán cũ là outstanding đã khôi phục
  /// (outstanding hiện tại + phần gốc của chính lần đang sửa, do màn gọi
  /// truyền vào — xem `loan_detail_screen.dart`).
  final int outstandingBaseline;
  final String categoryId;
  final String interestCategoryId;
  final FamilyMember initialMember;

  /// Khác `null` khi đang SỬA (không phải tạo mới) — id 1 leg bất kỳ của
  /// lần tất toán đang sửa, truyền thẳng cho `correctObligationSettlement`.
  final String? correctingAnchorTransactionId;
  final int? initialAmountMinor;
  final DateTime? initialDate;
  final String initialNote;

  bool get isCorrecting => correctingAnchorTransactionId != null;

  @override
  ConsumerState<SettleLoanSheet> createState() => _SettleLoanSheetState();
}

class _SettleLoanSheetState extends ConsumerState<SettleLoanSheet> {
  late final _amountController = TextEditingController(
    text: widget.initialAmountMinor?.toString() ?? '',
  );
  late final _noteController = TextEditingController(text: widget.initialNote);
  late FamilyMember _member = widget.initialMember;
  late DateTime _date = widget.initialDate ?? DateTime.now();
  bool _submitting = false;

  /// Lỗi của lần Lưu gần nhất — hiện NGAY TRONG sheet (F1: SnackBar bị che sau
  /// lớp modal). Xoá khi bấm Lưu lại.
  String? _errorText;

  // Idempotency freeze (mục 21) — chỉ áp dụng cho chế độ TẠO MỚI tất toán;
  // chế độ SỬA luôn là 1 hành động mới mỗi lần gọi (đúng convention
  // `CorrectObligationSettlementUseCase`, không cần freeze).
  late final String _principalId = IdGenerator.generate();
  late final String _principalClientTxId = IdGenerator.generate();
  late final String _interestId = IdGenerator.generate();
  late final String _interestClientTxId = IdGenerator.generate();

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  int get _amount => int.tryParse(_amountController.text.trim()) ?? 0;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        _date = picked;
        _errorText = null;
      });
    }
  }

  Future<void> _save() async {
    if (_submitting) return;
    if (_amount <= 0) return;
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    try {
      if (widget.isCorrecting) {
        await ref.read(correctObligationSettlementUseCaseProvider)(
          widget.correctingAnchorTransactionId!,
          newAmountMinor: _amount,
          categoryId: widget.categoryId,
          interestCategoryId: widget.interestCategoryId,
        );
      } else {
        final command = SettleObligationCommand(
          obligationId: widget.obligationId,
          direction: widget.direction,
          memberRefId: _member.name,
          amountMinor: _amount,
          transactionDate: _date,
          categoryId: widget.categoryId,
          interestCategoryId: widget.interestCategoryId,
          note: _noteController.text.trim(),
          principalId: _principalId,
          principalClientTxId: _principalClientTxId,
          interestId: _interestId,
          interestClientTxId: _interestClientTxId,
        );
        await ref.read(settleObligationUseCaseProvider).call(command);
      }
      if (mounted) closeSheetAfterSave(context, ref);
    } catch (error) {
      if (mounted) setState(() => _errorText = mapLoanError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReceivable = widget.direction == ObligationDirection.receivable;
    final legs = _amount > 0
        ? buildObligationSettlementLegs(
            direction: widget.direction,
            obligationId: widget.obligationId,
            memberRefId: _member.name,
            outstanding: widget.outstandingBaseline,
            paymentAmount: _amount,
            categoryId: widget.categoryId,
            interestCategoryId: widget.interestCategoryId,
            currency: 'VND',
            principalId: 'preview-principal',
            principalClientTxId: 'preview-principal-client',
            interestId: 'preview-interest',
            interestClientTxId: 'preview-interest-client',
            transactionDate: _date,
            now: _date,
          )
        : null;
    final canSave = _amount > 0 && !_submitting;

    return PopScope(
      canPop: !_submitting,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.45,
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
                          widget.isCorrecting
                              ? 'Sửa'
                              : (isReceivable ? 'Nhận tiền' : 'Trả tiền'),
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
                        Text(
                          isReceivable ? 'Còn phải thu' : 'Còn phải trả',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                        Text(
                          Formatters.amount(widget.outstandingBaseline),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _FieldLabel(
                          isReceivable ? 'Số tiền nhận' : 'Số tiền trả',
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          key: const Key('settleLoan_amount'),
                          controller: _amountController,
                          keyboardType: TextInputType.number,
                          inputFormatters: const [AmountInputFormatter()],
                          onChanged: (_) => setState(() => _errorText = null),
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
                        AmountPreview(amountMinor: _amount),
                        // Mục 13/16 — CHỈ hiện breakdown khi thật sự có phần lãi
                        // (nhận/trả vượt outstanding). Khi <= outstanding, số
                        // tiền người dùng gõ ở trên đã là câu trả lời đầy đủ —
                        // hiện thêm "Thu hồi gốc: X" (trùng y hệt số vừa gõ) chỉ
                        // gây rối, không phải lỗi tính toán nhưng KHÔNG đúng UX
                        // đã chốt ("không có dòng lãi" nghĩa là không hiện
                        // breakdown gì, không phải ẩn mỗi dòng lãi).
                        if (legs != null && legs.interest != null) ...[
                          const SizedBox(height: 12),
                          _PreviewCard(isReceivable: isReceivable, legs: legs),
                        ],
                        const SizedBox(height: 16),
                        _FieldLabel(isReceivable ? 'Người nhận' : 'Người trả'),
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
                          onSelectionChanged: (s) => setState(() {
                            _member = s.first;
                            _errorText = null;
                          }),
                        ),
                        const SizedBox(height: 16),
                        _FieldLabel('Ngày'),
                        const SizedBox(height: 6),
                        OutlinedButton.icon(
                          onPressed: _pickDate,
                          icon: const Icon(
                            Icons.calendar_today_rounded,
                            size: 16,
                          ),
                          label: Text(Formatters.dayMonthYear(_date)),
                        ),
                        const SizedBox(height: 16),
                        _FieldLabel('Ghi chú (không bắt buộc)'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _noteController,
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
                            key: const Key('settleLoan_save'),
                            onPressed: canSave ? _save : null,
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
                              _submitting ? 'Đang lưu...' : 'Lưu',
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

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.isReceivable, required this.legs});

  final bool isReceivable;
  final ObligationSettlementLegs legs;

  @override
  Widget build(BuildContext context) {
    final hasInterest = legs.interest != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.incomeTile,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PreviewRow(
            label: isReceivable ? 'Thu hồi gốc' : 'Trả gốc',
            value: legs.principal.amountMinor,
          ),
          if (hasInterest)
            _PreviewRow(
              label: isReceivable ? 'Tiền lãi' : 'Tiền lãi',
              value: legs.interest!.amountMinor,
            ),
          if (hasInterest) ...[
            const Divider(height: 16),
            _PreviewRow(
              label: isReceivable ? 'Tổng nhận' : 'Tổng trả',
              value: legs.principal.amountMinor + legs.interest!.amountMinor,
              emphasize: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final int value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w500,
              color: emphasize
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
            ),
          ),
          Text(
            Formatters.amount(value),
            style: TextStyle(
              fontSize: 13,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
            ),
          ),
        ],
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
