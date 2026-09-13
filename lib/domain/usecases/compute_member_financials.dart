import '../../core/constants/default_categories.dart';
import '../entities/category_kind.dart';
import '../entities/family_member.dart';
import '../entities/savings_destination.dart';
import '../entities/transaction.dart';

class MemberFinancials {
  const MemberFinancials({
    required this.member,
    required this.balance,
    required this.savingsOnHand,
    required this.savingsInBank,
  });

  final FamilyMember member;
  final int balance;
  final int savingsOnHand;
  final int savingsInBank;

  int get savingsTotal => savingsOnHand + savingsInBank;
}

/// Số dư & tiết kiệm riêng cho một người, đúng cơ chế cột "Người tiêu" +
/// hai hạng mục chuyển khoản (Chồng đưa vợ / Vợ đưa chồng) trong sheet thật.
MemberFinancials computeMemberFinancials(
  FamilyMember member,
  List<Transaction> transactions,
) {
  var balance = 0;
  var savingsOnHand = 0;
  var savingsInBank = 0;

  for (final t in transactions) {
    final category = DefaultCategories.byId(t.categoryId);
    switch (category.kind) {
      case CategoryKind.income:
        if (t.spender == member) balance += t.amount;
      case CategoryKind.expense:
        if (t.spender == member) balance -= t.amount;
      case CategoryKind.savings:
        if (t.spender == member) {
          balance -= t.amount;
          if (t.savingsDestination == SavingsDestination.bank) {
            savingsInBank += t.amount;
          } else {
            savingsOnHand += t.amount;
          }
        }
      case CategoryKind.transfer:
        if (category.transferFrom == member) balance -= t.amount;
        if (category.transferTo == member) balance += t.amount;
    }
  }

  return MemberFinancials(
    member: member,
    balance: balance,
    savingsOnHand: savingsOnHand,
    savingsInBank: savingsInBank,
  );
}
