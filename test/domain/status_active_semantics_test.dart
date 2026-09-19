import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/status.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/usecases/compute_status_breakdown.dart';

/// F30: status ẩn (`isActive == false`) không chọn được cho giao dịch mới,
/// nhưng giao dịch lịch sử vẫn resolve được tên và vẫn được đếm ở Tổng hợp.
void main() {
  Category category(List<Status> statuses) => Category(
    id: 'cho_di',
    name: 'CĐ',
    color: const Color(0xFF000000),
    type: TransactionType.expense,
    statuses: statuses,
    statsEnabled: true,
  );

  const s1 = Status(id: 's1', categoryId: 'cho_di', name: 'CCB', sortOrder: 0);
  const s2 = Status(id: 's2', categoryId: 'cho_di', name: 'ĐCB', sortOrder: 1, isActive: false);
  const s3 = Status(id: 's3', categoryId: 'cho_di', name: 'ĐG', sortOrder: 2);

  Transaction tx(String id, int amount, String? statusId) => Transaction(
    id: id,
    type: TransactionType.expense,
    categoryId: 'cho_di',
    sourceKind: PoolKind.memberAvailable,
    sourceRefId: 'vo',
    destinationKind: PoolKind.external,
    amountMinor: amount,
    statusId: statusId,
    transactionDate: DateTime(2026, 9, 1),
    createdAt: DateTime(2026, 9, 1),
    clientTxId: 'c-$id',
  );

  test('activeStatuses loại bước đã ẩn, statuses giữ đủ (để resolve lịch sử)', () {
    final c = category([s1, s2, s3]);
    expect(c.activeStatuses.map((s) => s.id), ['s1', 's3']);
    expect(c.statuses.map((s) => s.id), ['s1', 's2', 's3']);
    expect(c.hasStatus, isTrue);
  });

  test('statusById resolve cả bước đã ẩn (giao dịch lịch sử vẫn thấy tên)', () {
    final c = category([s1, s2, s3]);
    expect(c.statusById('s2')?.name, 'ĐCB');
    expect(c.statusById('s2')?.isActive, isFalse);
    expect(c.statusById(null), isNull);
    expect(c.statusById('không-có'), isNull);
  });

  test('hasStatus = false khi mọi bước đã ẩn (giao dịch mới không có trạng thái)', () {
    final c = category([s2.copyWith(isActive: false)]);
    expect(c.hasStatus, isFalse);
    expect(c.activeStatuses, isEmpty);
    expect(c.statusById('s2')?.name, 'ĐCB', reason: 'lịch sử vẫn resolve');
  });

  test('breakdown: giao dịch ở bước đã ẩn vẫn được đếm đúng bước; chưa gán status vào bước ĐANG DÙNG đầu', () {
    final c = category([s1, s2, s3]);
    final b = computeStatusBreakdown([
      tx('a', 100, 's2'), // bước đã ẩn — vẫn đếm ở s2
      tx('b', 200, 's3'),
      tx('c', 50, null), // chưa gán → bước đang dùng đầu tiên (s1)
    ], c);
    expect(b.totals['s1'], 50);
    expect(b.totals['s2'], 100);
    expect(b.totals['s3'], 200);
    expect(b.total, 350);
  });

  test('breakdown: bước đầu đã ẩn thì giao dịch chưa gán status vào bước đang dùng đầu tiên, không vào bước ẩn', () {
    final hiddenFirst = s1.copyWith(isActive: false);
    final c = category([hiddenFirst, s2.copyWith(isActive: true), s3]);
    final b = computeStatusBreakdown([tx('a', 70, null)], c);
    expect(b.totals['s2'], 70);
    expect(b.totals['s1'], 0);
  });
}
