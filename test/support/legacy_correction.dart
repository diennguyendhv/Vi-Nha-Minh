import 'package:vi_nha_minh/data/repositories/local_transaction_repository.dart';
import 'package:vi_nha_minh/domain/engine/financial_engine.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart' as domain;

var _legacySeq = 0;

/// Dựng lại 1 họ giao dịch "kiểu cũ" (gốc → hoàn tác → bản thay thế) — dữ liệu do
/// phiên bản trước để lại. Sửa giao dịch MỚI không còn tạo họ này (nó thay dòng
/// trực tiếp), nên test dữ liệu legacy phải tự dựng bằng hàm này.
Future<domain.Transaction> legacyCorrect(
  LocalTransactionRepository repo,
  String id, {
  required int amount,
  String? categoryId,
  String? note,
}) async {
  final original = (await repo.getTransactionById(id))!;
  await repo.reverseTransaction(id);
  _legacySeq++;
  final result = buildCorrection(
    original,
    newAmountMinor: amount,
    newCategoryId: categoryId,
    newNote: note,
    reversalId: 'lg-r-$_legacySeq',
    replacementId: 'lg-p-$_legacySeq',
    clientTxId: 'lg-c-$_legacySeq',
    now: DateTime(2026, 9, 2),
  );
  return repo.addTransaction(result.replacement);
}
