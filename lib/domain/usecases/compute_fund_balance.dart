import '../entities/fund_entry.dart';

/// Số dư quỹ = tổng nạp − tổng đã mua.
int computeFundBalance(List<FundEntry> entries) {
  var balance = 0;
  for (final e in entries) {
    balance += e.kind == FundEntryKind.topUp ? e.amount : -e.amount;
  }
  return balance;
}
