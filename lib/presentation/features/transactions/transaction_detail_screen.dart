import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/usecases/selectable_categories.dart';
import '../../../domain/entities/status.dart';
import '../../../domain/entities/member_directory.dart';
import '../../../domain/entities/pool_kind.dart';
import '../../../domain/entities/savings_asset_type.dart';
import '../../../domain/entities/transfer_kind.dart';
import '../../providers/fund_providers.dart';
import '../../providers/savings_asset_type_providers.dart';
import '../../../domain/entities/field_update.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../../domain/errors/domain_exceptions.dart';
import '../../../domain/usecases/compute_recovery_summary.dart';
import '../../providers/category_providers.dart';
import '../../providers/feature_providers.dart';
import '../../providers/member_providers.dart';
import '../../providers/obligation_providers.dart';
import '../../providers/transaction_providers.dart';
import '../../widgets/amount_input_formatter.dart';
import '../../widgets/amount_preview.dart';
import 'blocking_transactions_dialog.dart';
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
  final _amount = ValueNotifier<int>(0);
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

  /// Giá trị đang chọn của ô Trạng thái: bước hiện tại nếu còn hợp lệ, ngược lại
  /// `null` = "Không có trạng thái". KHÔNG tự chọn bước đầu tiên (trạng thái luôn
  /// tùy chọn; ô hiển thị khớp đúng giá trị sẽ được lưu).
  String? _statusValue(Category category) {
    final choices = _statusChoices(category);
    return choices.any((s) => s.id == _statusId) ? _statusId : null;
  }

  /// `memberId` đang chọn ở form Sửa (null = giao dịch không có "người tiêu" sửa được).
  String? _member;

  /// Đầu nguồn/đích đang chọn (chỉ dùng cho giao dịch Chuyển).
  String? _srcRef;
  String? _dstRef;

  MemberDirectory get _directory => ref.read(memberDirectoryProvider);

  @override
  void dispose() {
    _amount.dispose();
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
  String? _currentMember(Transaction t) {
    final refId = t.type == TransactionType.income
        ? t.destinationRefId
        : (t.type == TransactionType.expense &&
                  t.sourceKind == PoolKind.memberAvailable
              ? t.sourceRefId
              : (t.type == TransactionType.expense &&
                        t.sourceKind == PoolKind.fund
                    ? t.actorMemberId
                    : null));
    // ID lạ (không thuộc Wallet) → không sửa người được, không đoán.
    return _directory.contains(refId) ? refId : null;
  }

  /// Số tiền đang nhập (0 nếu trống/không hợp lệ) — Lưu bị khoá khi <= 0.
  int get _enteredAmount => _amount.value;

  void _initFrom(Transaction t) {
    _amountController.text = t.amountMinor.toString();
    _amount.value = t.amountMinor;
    _noteController.text = t.note;
    _categoryId = t.categoryId;
    _transactionDate = t.transactionDate;
    _statusId = t.statusId;
    _member = _currentMember(t);
    _srcRef = t.sourceRefId;
    _dstRef = t.destinationRefId;
  }

  bool _isFundExpense(Transaction t) =>
      t.type == TransactionType.expense && t.sourceKind == PoolKind.fund;

  bool _canPickMember(Transaction t) =>
      _isFundExpense(t) || _currentMember(t) != null;

  bool _isSavingsKind(TransferKind? k) =>
      k == TransferKind.savingsTopup ||
      k == TransferKind.savingsWithdraw ||
      k == TransferKind.savingsConvert;

  /// Chuyển sửa được đầu nguồn/đích khi có `transferKind` chuẩn (không phải Vay/dữ liệu cũ).
  bool _canEditEndpoints(Transaction t) =>
      t.type == TransactionType.transfer &&
      t.transferKind != null &&
      t.obligationId == null;

  String? _savingsMember(Transaction t) {
    for (final e in [
      (t.sourceKind, _srcRef),
      (t.destinationKind, _dstRef),
    ]) {
      if (e.$1 == PoolKind.memberSavingsAsset && e.$2 != null) {
        return parseSavingsAssetRefId(e.$2!)?.memberId;
      }
    }
    return null;
  }

  /// Đặt thành viên cho cả 2 đầu của giao dịch tiết kiệm (luôn cùng 1 người).
  void _setSavingsMember(Transaction t, String m) {
    String? re(PoolKind k, String? ref) {
      if (k == PoolKind.memberAvailable) return m;
      if (k == PoolKind.memberSavingsAsset && ref != null) {
        final p = parseSavingsAssetRefId(ref);
        return p == null ? ref : savingsAssetRefId(p.assetTypeId, m);
      }
      return ref;
    }

    setState(() {
      _srcRef = re(t.sourceKind, _srcRef);
      _dstRef = re(t.destinationKind, _dstRef);
    });
  }

  /// Lựa chọn Chuyển hiện tại có hợp lệ để Lưu không (repository vẫn kiểm lại).
  bool _endpointsValid(Transaction t) {
    if (!_canEditEndpoints(t)) return true;
    final k = t.transferKind;
    if (k == TransferKind.memberToMember) return _srcRef != _dstRef;
    if (k == TransferKind.savingsConvert) {
      final a = _srcRef == null ? null : parseSavingsAssetRefId(_srcRef!);
      final b = _dstRef == null ? null : parseSavingsAssetRefId(_dstRef!);
      return a != null && b != null && a.assetTypeId != b.assetTypeId;
    }
    return true;
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
  /// Ý định của người dùng với trạng thái: không đổi → `null`; đổi sang bước khác
  /// → set; về "Không có trạng thái" → clear (KHÔNG dùng `null` cho cả hai).
  FieldUpdate<String>? _statusUpdateFor(Transaction current) {
    if (_statusId == current.statusId) return null;
    final id = _statusId;
    return id == null ? const FieldUpdate.clear() : FieldUpdate.set(id);
  }

  Future<void> _save(Transaction current) async {
    if (!_canMutateGeneric(current)) return;
    if (_submitting) return; // chặn double-tap.
    final newAmount = _enteredAmount;
    if (newAmount <= 0) return;

    setState(() => _submitting = true);
    try {
      await ref.read(updateTransactionUseCaseProvider)(
        current.id,
        amountMinor: newAmount,
        categoryId: _categoryId,
        note: _noteController.text.trim(),
        memberRefId: _member,
        sourceRefId: _canEditEndpoints(current) && _srcRef != current.sourceRefId
            ? _srcRef
            : null,
        destinationRefId:
            _canEditEndpoints(current) && _dstRef != current.destinationRefId
            ? _dstRef
            : null,
        transactionDate: _transactionDate,
        status: _statusUpdateFor(current),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      await _showError(error);
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

  /// "Xóa giao dịch" = XOÁ THẬT (không còn tạo bản hoàn tác): gọi
  /// `DeleteTransactionUseCase`; Repository xoá vật lý cả họ giao dịch trong 1
  /// DB transaction và số liệu tự tính lại. Bị chặn nếu làm pool âm hoặc dính
  /// Vay/Hoàn tiền — hiện thông báo dễ hiểu, không ghi gì.
  Future<void> _delete(Transaction current) async {
    if (!_canMutateGeneric(current)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa giao dịch này?'),
        content: const Text(
          'Giao dịch sẽ bị xóa khỏi lịch sử và số liệu sẽ được tính lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huỷ'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!_canMutateGeneric(current)) return;
    if (_submitting) return; // chặn double-tap.

    setState(() => _submitting = true);
    try {
      await ref.read(deleteTransactionUseCaseProvider)(current.id);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      await _showError(error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Hiện lỗi: nếu biết giao dịch nào đang cản (xóa/sửa làm số dư âm) thì cho mở
  /// thẳng giao dịch đó; ngược lại chỉ báo bằng SnackBar.
  Future<void> _showError(Object error) async {
    if (!mounted) return;
    final ids = error is DeleteWouldOverdrawException
        ? error.blockingTransactionIds
        : (error is ChangeWouldOverdrawException
              ? error.blockingTransactionIds
              : const <String>[]);
    final blockers = blockersFromTransactionIds(
      ids,
      ref.read(transactionsStreamProvider).valueOrNull ?? const [],
      ref.read(categoriesStreamProvider).valueOrNull ?? const [],
      _directory.members,
    );
    if (blockers.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      return;
    }
    await showBlockingTransactions(
      context,
      title: error is DeleteWouldOverdrawException
          ? 'Chưa thể xóa giao dịch'
          : 'Chưa thể lưu thay đổi',
      message: _errorMessage(error),
      blockers: blockers,
    );
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
    if (error is ReversalWouldOverdrawException) {
      return 'Không thể hoàn tác vì một phần số tiền này đã được chuyển hoặc sử dụng. Hãy xử lý giao dịch phát sinh sau trước.';
    }
    if (error is DeleteWouldOverdrawException) {
      return 'Giao dịch này chưa thể xóa vì số tiền đã được sử dụng ở giao dịch sau.';
    }
    if (error is ChangeWouldOverdrawException) {
      return 'Không thể lưu thay đổi vì số tiền từ giao dịch này đã được sử dụng hoặc chuyển ở giao dịch khác.';
    }
    if (error is TransactionDeleteBlockedException) {
      return error.reason == DeleteBlockReason.linkedLoan
          ? 'Giao dịch này thuộc một khoản vay / cho vay nên chưa thể xóa ở đây.'
          : 'Giao dịch này liên quan đến một khoản hoàn tiền / thu hồi nên chưa thể xóa ở đây.';
    }
    if (error is InvalidTransferEditException) {
      return 'Nguồn / đích đã chọn không hợp lệ cho loại chuyển này.';
    }
    if (error is UnknownEndpointException) {
      return 'Thành viên, quỹ hoặc loại tiết kiệm đã chọn không còn dùng được.';
    }
    if (error is SavingsMemberMismatchException) {
      return 'Giao dịch tiết kiệm phải cùng một thành viên.';
    }
    if (error is MainGroupChangeException) {
      return 'Không thể đổi giao dịch sang nhóm Thu / Chi / Chuyển khác.';
    }
    if (error is InvalidStatusForCategoryException) {
      return 'Trạng thái đã chọn không thuộc danh mục này — vui lòng chọn lại.';
    }
    if (error is PersistenceConstraintException) {
      return 'Dữ liệu tham chiếu không hợp lệ, vui lòng thử lại.';
    }
    if (error is PersistenceException) {
      return 'Có lỗi khi lưu dữ liệu, vui lòng thử lại.';
    }
    return 'Có lỗi xảy ra, vui lòng thử lại.';
  }

  static const _label = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w700,
    color: AppColors.textMuted,
  );

  Widget _dropdown({
    required Key key,
    required String title,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: _label),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            key: key,
            value: items.any((i) => i.value == value) ? value : null,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: items,
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }

  /// Điều khiển sửa đầu nguồn/đích theo loại Chuyển. Chỉ `refId` đổi được; loại pool
  /// cố định. Repository kiểm lại hình dạng, sự tồn tại và số dư khi Lưu.
  List<Widget> _endpointEditor(Transaction t) {
    final members = [
      for (final m in _directory.members)
        DropdownMenuItem(value: m.memberId, child: Text(m.label)),
    ];
    final funds = [
      for (final f in ref.watch(fundsStreamProvider).valueOrNull ?? const [])
        if (f.isActive || f.id == _srcRef || f.id == _dstRef)
          DropdownMenuItem<String>(value: f.id, child: Text(f.name)),
    ];
    final dbAssets =
        ref.watch(savingsAssetTypesStreamProvider).valueOrNull ?? const [];
    final assets = [
      for (final a in [SystemSavingsAssets.unallocated, ...dbAssets])
        DropdownMenuItem<String>(value: a.id, child: Text(a.name)),
    ];

    if (_isSavingsKind(t.transferKind)) {
      final member = _savingsMember(t);
      Widget assetSide(String title, String? refId, bool src) {
        final p = refId == null ? null : parseSavingsAssetRefId(refId);
        return _dropdown(
          key: Key(src ? 'detail_source_asset' : 'detail_destination_asset'),
          title: title,
          value: p?.assetTypeId,
          items: assets,
          onChanged: (a) => setState(() {
            final r = savingsAssetRefId(a, member ?? p!.memberId);
            if (src) {
              _srcRef = r;
            } else {
              _dstRef = r;
            }
          }),
        );
      }

      return [
        _dropdown(
          key: const Key('detail_transfer_member'),
          title: 'THÀNH VIÊN',
          value: member,
          items: members,
          onChanged: (m) => _setSavingsMember(t, m),
        ),
        if (t.sourceKind == PoolKind.memberSavingsAsset)
          assetSide('TỪ LOẠI TIẾT KIỆM', _srcRef, true),
        if (t.destinationKind == PoolKind.memberSavingsAsset)
          assetSide('ĐẾN LOẠI TIẾT KIỆM', _dstRef, false),
        if (!_endpointsValid(t))
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Hai loại tiết kiệm phải khác nhau.',
              style: TextStyle(fontSize: 12, color: AppColors.expenseAmount),
            ),
          ),
      ];
    }

    Widget side(String title, PoolKind kind, String? value, bool src) {
      return _dropdown(
        key: Key(src ? 'detail_source_ref' : 'detail_destination_ref'),
        title: title,
        value: value,
        items: kind == PoolKind.fund ? funds : members,
        onChanged: (v) => setState(() {
          if (src) {
            _srcRef = v;
          } else {
            _dstRef = v;
          }
        }),
      );
    }

    return [
      side('TỪ', t.sourceKind, _srcRef, true),
      side('ĐẾN', t.destinationKind, _dstRef, false),
      if (!_endpointsValid(t))
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Nguồn và đích phải khác nhau.',
            style: TextStyle(fontSize: 12, color: AppColors.expenseAmount),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(memberDirectoryProvider);
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
    // Chỉ đề nghị danh mục thường đang dùng; danh mục hiện tại của giao dịch (kể cả
    // đã ngừng / hệ thống từ dữ liệu cũ) vẫn hiện để hiển thị đúng, không bị đổi ngầm.
    final sameTypeCategories = selectableCategories(
      categories,
      type: transaction.type,
      currentCategoryId: _categoryId,
    );
    final canEditCategory = transaction.type != TransactionType.transfer;
    final canEditMember = _canPickMember(transaction);

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
          _ReadOnlyRow(
            label: 'Loại giao dịch',
            value: switch (transaction.type) {
              TransactionType.income => 'Thu',
              TransactionType.expense => 'Chi',
              TransactionType.transfer => 'Chuyển',
            },
          ),
          const SizedBox(height: 16),
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
                  // Đổi hạng mục: trạng thái cũ (thuộc hạng mục khác) bị xóa ngay —
                  // không giữ ngầm, không tự ánh xạ theo tên. Người dùng tự chọn
                  // trạng thái của hạng mục mới nếu cần.
                  if (newCategory != null &&
                      newCategory.statuses.every((s) => s.id != _statusId)) {
                    _statusId = null;
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
            onChanged: (value) =>
                _amount.value = int.tryParse(value.isEmpty ? '0' : value) ?? 0,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              suffixText: 'đ',
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: _amount,
            builder: (_, amount, _) => AmountPreview(amountMinor: amount),
          ),
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
            Text(
              _isFundExpense(transaction) ? 'NGƯỜI THỰC HIỆN' : 'NGƯỜI TIÊU',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              key: const Key('detail_member_field'),
              emptySelectionAllowed: _isFundExpense(transaction),
              segments: _directory.members
                  .map(
                    (m) =>
                        ButtonSegment(value: m.memberId, label: Text(m.label)),
                  )
                  .toList(),
              selected: _isFundExpense(transaction)
                  ? {if (_member != null) _member!}
                  : {_member ?? _directory.defaultMemberId!},
              onSelectionChanged: (s) =>
                  setState(() => _member = s.isEmpty ? null : s.first),
            ),
          ],
          if (_canEditEndpoints(transaction)) ..._endpointEditor(transaction),
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
            DropdownButtonFormField<String?>(
              key: const Key('detail_status_field'),
              value: _statusValue(selectedCategory),
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Không có trạng thái'),
                ),
                for (final s in _statusChoices(selectedCategory))
                  DropdownMenuItem<String?>(
                    value: s.id,
                    child: Text(
                      s.isActive ? s.name : '${s.name} (ngừng sử dụng)',
                    ),
                  ),
              ],
              onChanged: (id) => setState(() => _statusId = id),
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
          ValueListenableBuilder<int>(
            valueListenable: _amount,
            builder: (_, amount, _) => ElevatedButton(
              onPressed:
                  (_submitting || amount <= 0 || !_endpointsValid(transaction))
                  ? null
                  : () => _save(transaction),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(_submitting ? 'Đang lưu...' : 'Lưu thay đổi'),
            ),
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
            child: const Text('Xóa giao dịch'),
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
            _ReadOnlyRow(
              label: 'Người tiêu',
              value: _directory.labelOf(member) ?? '',
            ),
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
