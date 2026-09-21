import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/engine/financial_engine.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/usecases/compute_grouped_totals.dart';
import 'package:vi_nha_minh/domain/usecases/compute_three_totals.dart';

Category _cat(
  String id,
  TransactionType type, {
  bool exclude = false,
  String? group,
}) => Category(
  id: id,
  name: id, // tên KHÔNG bao giờ được dùng để phân nhóm
  color: Colors.grey,
  type: type,
  excludeFromTotals: exclude,
  groupKey: group,
);

final _categories = <Category>[
  _cat('hoc_phi', TransactionType.income),
  _cat('lap_trinh', TransactionType.income),
  _cat('so_du_ban_dau', TransactionType.income, exclude: true),
  _cat('thu_khac', TransactionType.income, exclude: true),
  _cat('sinh_hoat', TransactionType.expense),
  _cat('dang_hien', TransactionType.expense),
  // Tên nghe như "chi tiêu" nhưng nhóm do groupKey quyết định.
  _cat('luong_gv', TransactionType.expense, group: CategoryGroupKey.businessExpense),
  _cat('quang_cao', TransactionType.expense, group: CategoryGroupKey.businessExpense),
  _cat('chuyen', TransactionType.transfer),
];

int _n = 0;
final _d = DateTime(2026, 9, 10);

Transaction _in(
  String category,
  int amount, {
  String to = 'vo',
  DateTime? date,
  String? reversedBy,
  String? reversalOf,
}) {
  _n++;
  return Transaction(
    id: 'in-$_n',
    type: TransactionType.income,
    categoryId: category,
    sourceKind: PoolKind.external,
    destinationKind: PoolKind.memberAvailable,
    destinationRefId: to,
    amountMinor: amount,
    transactionDate: date ?? _d,
    createdAt: date ?? _d,
    clientTxId: 'c-in-$_n',
    reversedByTxId: reversedBy,
    reversalOfTxId: reversalOf,
  );
}

Transaction _out(
  String category,
  int amount, {
  String from = 'vo',
  DateTime? date,
  String? reversedBy,
  String? reversalOf,
  String? id,
}) {
  _n++;
  return Transaction(
    id: id ?? 'out-$_n',
    type: TransactionType.expense,
    categoryId: category,
    sourceKind: PoolKind.memberAvailable,
    sourceRefId: from,
    destinationKind: PoolKind.external,
    amountMinor: amount,
    transactionDate: date ?? _d,
    createdAt: date ?? _d,
    clientTxId: 'c-out-$_n',
    reversedByTxId: reversedBy,
    reversalOfTxId: reversalOf,
  );
}

Transaction _move(int amount) {
  _n++;
  return Transaction(
    id: 'mv-$_n',
    type: TransactionType.transfer,
    categoryId: 'chuyen',
    sourceKind: PoolKind.memberAvailable,
    sourceRefId: 'vo',
    destinationKind: PoolKind.memberAvailable,
    destinationRefId: 'chong',
    amountMinor: amount,
    transactionDate: _d,
    createdAt: _d,
    clientTxId: 'c-mv-$_n',
  );
}

GroupedTotals _totals(List<Transaction> t, {DateTime? month, String? member}) =>
    computeGroupedTotals(t, _categories, month: month, memberId: member);

void main() {
  test('1 — chỉ Doanh thu', () {
    final g = _totals([_in('hoc_phi', 2000000), _in('lap_trinh', 500000)]);
    expect((g.revenue, g.otherInflow, g.spending, g.businessExpense), (2500000, 0, 0, 0));
    expect(g.netIncome, 2500000);
    expect(g.cashFlow, 2500000);
  });

  test('2 — chỉ Khoản thu khác', () {
    final g = _totals([_in('thu_khac', 450000)]);
    expect((g.revenue, g.otherInflow), (0, 450000));
    expect(g.netIncome, 0, reason: 'Khoản thu khác không phải thu nhập ròng');
    expect(g.cashFlow, 450000);
  });

  test('3 — chỉ Chi tiêu', () {
    final g = _totals([_out('sinh_hoat', 300000), _out('dang_hien', 100000)]);
    expect((g.spending, g.businessExpense), (400000, 0));
    expect(g.netIncome, 0);
    expect(g.cashFlow, -400000);
  });

  test('4 — chỉ Chi phí kinh doanh (nhóm theo groupKey, không theo tên)', () {
    final g = _totals([_out('luong_gv', 700000), _out('quang_cao', 200000)]);
    expect((g.spending, g.businessExpense), (0, 900000));
    expect(g.netIncome, -900000);
  });

  test('5 — mix 4 nhóm đúng ví dụ của brief', () {
    final g = _totals([
      _in('hoc_phi', 10000000),
      _in('lap_trinh', 5000000),
      _in('so_du_ban_dau', 2000000),
      _in('thu_khac', 450000),
      _out('sinh_hoat', 3000000),
      _out('dang_hien', 1000000),
      _out('luong_gv', 4000000),
      _out('quang_cao', 500000),
    ]);
    expect(g.revenue, 15000000);
    expect(g.otherInflow, 2450000);
    expect(g.spending, 4000000);
    expect(g.businessExpense, 4500000);
    expect(g.netIncome, 10500000);
    expect(g.cashFlow, 8950000);
  });

  test('6 — Số dư ban đầu KHÔNG là Doanh thu', () {
    final g = _totals([_in('so_du_ban_dau', 5000000)]);
    expect(g.revenue, 0);
    expect(g.otherInflow, 5000000);
  });

  test('7/8/9 — Khoản thu khác không tăng, Chi tiêu không giảm, Chi phí KD giảm Thu nhập ròng', () {
    final base = _totals([_in('hoc_phi', 1000000)]);
    expect(_totals([_in('hoc_phi', 1000000), _in('thu_khac', 999)]).netIncome, base.netIncome);
    expect(_totals([_in('hoc_phi', 1000000), _out('sinh_hoat', 400000)]).netIncome, base.netIncome);
    expect(_totals([_in('hoc_phi', 1000000), _out('luong_gv', 400000)]).netIncome, 600000);
  });

  test('10 — reversal: giao dịch đã hoàn tác không được đếm (và bản hoàn tác nội bộ cũng không)', () {
    final original = _out('luong_gv', 700000, id: 'orig', reversedBy: 'rev');
    final reversal = _in('luong_gv', 700000, reversalOf: 'orig');
    final g = _totals([original, reversal, _in('hoc_phi', 1000000)]);
    expect(g.businessExpense, 0);
    expect(g.otherInflow, 0, reason: 'bản reversal nội bộ không phải khoản thu khác');
    expect(g.revenue, 1000000);
  });

  test('11 — correction: chỉ bản mới nhất được đếm', () {
    final old = _out('sinh_hoat', 500000, id: 'old', reversedBy: 'rev');
    final rev = _in('sinh_hoat', 500000, reversalOf: 'old');
    final fixed = _out('sinh_hoat', 350000);
    final g = _totals([old, rev, fixed]);
    expect(g.spending, 350000);
  });

  test('12 — quy theo tháng của transactionDate', () {
    final sep = DateTime(2026, 9, 30);
    final oct = DateTime(2026, 10, 1);
    final all = [
      _in('hoc_phi', 1000000, date: sep),
      _in('hoc_phi', 2000000, date: oct),
      _out('luong_gv', 300000, date: sep),
      _out('luong_gv', 400000, date: oct),
    ];
    final s = _totals(all, month: DateTime(2026, 9));
    final o = _totals(all, month: DateTime(2026, 10));
    expect((s.revenue, s.businessExpense), (1000000, 300000));
    expect((o.revenue, o.businessExpense), (2000000, 400000));
  });

  test('13 — theo thành viên Vợ/Chồng', () {
    final all = [
      _in('hoc_phi', 1000000, to: 'vo'),
      _in('hoc_phi', 4000000, to: 'chong'),
      _out('sinh_hoat', 100000, from: 'vo'),
      _out('luong_gv', 900000, from: 'chong'),
    ];
    final vo = _totals(all, member: 'vo');
    final chong = _totals(all, member: 'chong');
    expect((vo.revenue, vo.spending, vo.businessExpense), (1000000, 100000, 0));
    expect((chong.revenue, chong.spending, chong.businessExpense), (4000000, 0, 900000));
    final family = _totals(all);
    expect(family.revenue, vo.revenue + chong.revenue);
  });

  test('14 — đổi nhóm danh mục Chi → CHỈ đổi báo cáo, KHÔNG đổi sổ/số dư', () {
    final categoriesNull = [
      ..._categories.where((c) => c.id != 'luong_gv'),
      _cat('luong_gv', TransactionType.expense),
    ];
    final categoriesBiz = _categories; // luong_gv = business_expense
    final txs = [_in('hoc_phi', 1000000), _out('luong_gv', 700000)];

    final asSpending = computeGroupedTotals(txs, categoriesNull);
    expect((asSpending.spending, asSpending.businessExpense), (700000, 0));

    final asBusiness = computeGroupedTotals(txs, categoriesBiz);
    expect((asBusiness.spending, asBusiness.businessExpense), (0, 700000));

    // Cùng danh sách giao dịch → số dư/pool y hệt (engine không đọc groupKey).
    expect(computeAllPoolBalances(txs), computeAllPoolBalances(txs));
    expect(txs, hasLength(2));
    expect(asSpending.cashFlow, asBusiness.cashFlow, reason: 'Dòng tiền không đổi khi đổi nhóm');
    expect(asSpending.netIncome, isNot(asBusiness.netIncome), reason: 'Thu nhập ròng thì đổi');
  });

  test('15 — recovery cũ (đang ẩn khỏi UI) vẫn được tính an toàn: lợi nhuận → Doanh thu, hoàn vốn → Khoản thu khác', () {
    final cats = [
      ..._categories,
      _cat('dau_tu', TransactionType.expense),
      _cat('hoan_tien_thu_hoi', TransactionType.income, exclude: true),
    ];
    final buy = _out('dau_tu', 2000000, id: 'buy');
    _n++;
    final sell = Transaction(
      id: 'sell',
      type: TransactionType.income,
      categoryId: 'hoan_tien_thu_hoi',
      sourceKind: PoolKind.external,
      destinationKind: PoolKind.memberAvailable,
      destinationRefId: 'vo',
      amountMinor: 2500000,
      recoveryOfTxId: 'buy',
      transactionDate: _d,
      createdAt: _d,
      clientTxId: 'c-sell',
    );
    final g = computeGroupedTotals([buy, sell], cats);
    expect(g.revenue, 500000, reason: 'phần lãi vượt vốn');
    expect(g.otherInflow, 2000000, reason: 'phần thu hồi vốn');
    expect(g.spending, 2000000);
    // Không nhân đôi: khớp ThreeTotals.
    final three = computeThreeTotals([buy, sell], cats);
    expect(g.revenue, three.totalIncome);
    expect(g.spending + g.businessExpense, three.totalExpense);
  });

  test('16 — giao dịch Vay cũ vẫn được tính an toàn: gốc đi vay không là Doanh thu, khớp ThreeTotals', () {
    final cats = [
      ..._categories,
      _cat('vay_no', TransactionType.income),
      _cat('tra_no', TransactionType.expense),
    ];
    _n++;
    final creation = Transaction(
      id: 'loan-create',
      type: TransactionType.income,
      categoryId: 'vay_no',
      sourceKind: PoolKind.external,
      destinationKind: PoolKind.memberAvailable,
      destinationRefId: 'vo',
      amountMinor: 1000000,
      obligationId: 'ob-1',
      transactionDate: _d,
      createdAt: _d,
      clientTxId: 'c-loan-create',
    );
    final g = computeGroupedTotals([creation], cats);
    expect(g.revenue, 0);
    expect(g.otherInflow, 1000000);
    final three = computeThreeTotals([creation], cats);
    expect(g.revenue, three.totalIncome);
  });

  test('17 — bán lại tài sản nhập tay: mua 2tr (Chi tiêu), bán 2tr (Khoản thu khác) + lãi 500k (Doanh thu)', () {
    final g = _totals([
      _out('sinh_hoat', 2000000),
      _in('thu_khac', 2000000),
      _in('hoc_phi', 500000),
    ]);
    expect(g.spending, 2000000);
    expect(g.otherInflow, 2000000);
    expect(g.revenue, 500000);
    expect(g.netIncome, 500000);
  });

  test('18 — Chuyển không tạo Doanh thu/Chi tiêu; Doanh thu/Chi khớp ThreeTotals trên dữ liệu trộn', () {
    final txs = [
      _in('hoc_phi', 3000000),
      _in('so_du_ban_dau', 100000),
      _out('sinh_hoat', 250000),
      _out('luong_gv', 750000),
      _move(999999),
    ];
    final g = _totals(txs);
    expect(g.revenue + g.spending + g.businessExpense + g.otherInflow, 3000000 + 100000 + 250000 + 750000);
    final three = computeThreeTotals(txs, _categories);
    expect(g.revenue, three.totalIncome);
    expect(g.spending + g.businessExpense, three.totalExpense);
  });
}
