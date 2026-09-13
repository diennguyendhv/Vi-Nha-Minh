import 'family_member.dart';
import 'savings_destination.dart';

class Transaction {
  const Transaction({
    required this.id,
    required this.categoryId,
    required this.amount,
    required this.date,
    required this.spender,
    this.note = '',
    this.status,
    this.savingsDestination,
  });

  final String id;
  final String categoryId;

  /// Có thể âm — sheet thật dùng số âm cho các khoản điều chỉnh/hoàn tiền
  /// (Thu nhập) hoặc rút tiết kiệm (Tiết kiệm).
  final int amount;
  final DateTime date;
  final FamilyMember spender;
  final String note;

  /// Phải là một trong các giá trị của `category.statuses` khi hạng mục có
  /// theo dõi trạng thái; null nghĩa là chưa chọn (coi như ở bước đầu tiên).
  final String? status;

  /// Chỉ có ý nghĩa khi hạng mục có kind == savings.
  final SavingsDestination? savingsDestination;
}
