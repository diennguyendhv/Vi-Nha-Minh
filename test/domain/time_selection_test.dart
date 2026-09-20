import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/usecases/explore_transactions.dart';
import 'package:vi_nha_minh/domain/usecases/time_selection.dart';

Transaction _tx(String id, DateTime date, {int amount = 1000}) => Transaction(
  id: id,
  type: TransactionType.expense,
  categoryId: 'sinh_hoat',
  sourceKind: PoolKind.memberAvailable,
  sourceRefId: 'vo',
  destinationKind: PoolKind.external,
  amountMinor: amount,
  transactionDate: date,
  createdAt: date,
  clientTxId: 'c-$id',
);

final _cats = [
  Category(id: 'sinh_hoat', name: 'Sinh hoạt', color: Colors.grey, type: TransactionType.expense),
];

Set<String> _ids(List<Transaction> txs, TimeSelection sel) {
  final r = exploreTransactions(
    txs,
    _cats,
    const TransactionFilter().withRange(sel.from, sel.to),
  );
  return {for (final t in r.rows) t.id};
}

void main() {
  final txs = [
    _tx('y25_end', DateTime(2025, 12, 31, 23, 59)),
    _tx('y26_start', DateTime(2026, 1, 1, 0, 0)),
    _tx('feb', DateTime(2026, 2, 28, 12)),
    _tx('aug_end', DateTime(2026, 8, 31, 23, 59)),
    _tx('sep1', DateTime(2026, 9, 1, 0, 1)),
    _tx('sep20', DateTime(2026, 9, 20, 9)),
    _tx('sep30', DateTime(2026, 9, 30, 23, 59)),
    _tx('oct1', DateTime(2026, 10, 1)),
    _tx('y26_end', DateTime(2026, 12, 31, 23, 59)),
    _tx('y27', DateTime(2027, 1, 1)),
  ];

  test('Ngày: đúng ngày đó (bỏ giờ)', () {
    expect(_ids(txs, TimeSelection.day(DateTime(2026, 9, 20))), {'sep20'});
    expect(_ids(txs, TimeSelection.day(DateTime(2026, 12, 31, 8))), {'y26_end'});
  });

  test('Tháng: đủ ngày đầu/cuối tháng, không lấn sang tháng bên cạnh', () {
    expect(_ids(txs, TimeSelection.month(DateTime(2026, 9, 15))), {'sep1', 'sep20', 'sep30'});
    expect(_ids(txs, TimeSelection.month(DateTime(2026, 2))), {'feb'});
  });

  test('Năm: toàn bộ giao dịch năm đó, đúng biên 31/12 ↔ 01/01', () {
    expect(
      _ids(txs, TimeSelection.year(DateTime(2026, 6, 6))),
      {'y26_start', 'feb', 'aug_end', 'sep1', 'sep20', 'sep30', 'oct1', 'y26_end'},
    );
    expect(_ids(txs, TimeSelection.year(DateTime(2025))), {'y25_end'});
    expect(_ids(txs, TimeSelection.year(DateTime(2027))), {'y27'});
  });

  test('Tất cả thời gian: không giới hạn ngày', () {
    final all = TimeSelection.all(DateTime(2026, 9, 20));
    expect(all.from, isNull);
    expect(all.to, isNull);
    expect(_ids(txs, all).length, txs.length);
  });

  test('shift: lùi/tiến ngày, tháng (qua năm), năm; "Tất cả" không dịch', () {
    expect(TimeSelection.day(DateTime(2026, 3, 1)).shift(-1).from, DateTime(2026, 2, 28));
    expect(TimeSelection.month(DateTime(2026, 1)).shift(-1).from, DateTime(2025, 12, 1));
    expect(TimeSelection.month(DateTime(2026, 12)).shift(1).to, DateTime(2027, 1, 31));
    expect(TimeSelection.year(DateTime(2026)).shift(1).from, DateTime(2027, 1, 1));
    final all = TimeSelection.all(DateTime(2026, 9, 20));
    expect(all.shift(1), all);
  });

  test('Bấm chip = KỲ HIỆN TẠI: Ngày → hôm nay, Tháng → tháng này, Năm → năm nay (không giữ mốc cũ)', () {
    final today = DateTime(2026, 9, 20, 14, 30);
    final day = TimeSelection.current(TimeKind.day, today);
    expect(day.from, DateTime(2026, 9, 20));
    expect(day.to, DateTime(2026, 9, 20));
    final month = TimeSelection.current(TimeKind.month, today);
    expect(month.from, DateTime(2026, 9, 1));
    expect(month.to, DateTime(2026, 9, 30));
    final year = TimeSelection.current(TimeKind.year, today);
    expect(year.from, DateTime(2026, 1, 1));
    expect(year.to, DateTime(2026, 12, 31));
    final all = TimeSelection.current(TimeKind.all, today);
    expect(all.from, isNull);
    expect(all.to, isNull);
  });

  test('Chỉ còn 4 kiểu thời gian: Ngày / Tháng / Năm / Tất cả (không khoảng ngày)', () {
    expect(TimeKind.values, [TimeKind.day, TimeKind.month, TimeKind.year, TimeKind.all]);
  });
}
