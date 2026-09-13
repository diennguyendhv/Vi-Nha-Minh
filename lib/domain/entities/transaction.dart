import 'transaction_type.dart';

class Transaction {
  const Transaction({
    required this.id,
    required this.type,
    required this.categoryId,
    required this.amount,
    required this.date,
    this.note = '',
    this.spenderName = '',
  });

  final String id;
  final TransactionType type;
  final String categoryId;
  final int amount;
  final DateTime date;
  final String note;
  final String spenderName;
}
