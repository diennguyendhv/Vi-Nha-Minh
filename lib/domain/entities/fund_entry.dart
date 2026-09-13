/// topUp = nạp tiền vào quỹ; purchase = mua một khoản gì đó từ quỹ.
enum FundEntryKind { topUp, purchase }

class FundEntry {
  const FundEntry({
    required this.id,
    required this.fundId,
    required this.kind,
    required this.amount,
    required this.date,
    this.note = '',
  });

  final String id;
  final String fundId;
  final FundEntryKind kind;
  final int amount;
  final DateTime date;
  final String note;
}
