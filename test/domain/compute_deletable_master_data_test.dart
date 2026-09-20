import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/status.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/usecases/compute_deletable_master_data.dart';

Transaction _t(
  String id, {
  String category = 'c1',
  String? statusId,
  String? reversalOf,
  String? reversedBy,
  String? corrects,
}) => Transaction(
  id: id,
  type: TransactionType.expense,
  categoryId: category,
  statusId: statusId,
  sourceKind: PoolKind.memberAvailable,
  sourceRefId: 'vo',
  destinationKind: PoolKind.external,
  amountMinor: 1000,
  reversalOfTxId: reversalOf,
  reversedByTxId: reversedBy,
  correctsTxId: corrects,
  transactionDate: DateTime(2026, 9, 1),
  createdAt: DateTime(2026, 9, 1),
  clientTxId: 'k$id',
);

Category _c(String id, {bool active = false, List<Status> statuses = const [], String? linked}) => Category(
  id: id,
  name: id,
  color: const Color(0xFF000000),
  type: TransactionType.expense,
  isActive: active,
  isDefault: false,
  statuses: statuses,
  linkedExpenseCategoryId: linked,
);

void main() {
  test('Danh mục: xóa hết giao dịch dùng nó → xóa hẳn được NGAY (suy ra từ dữ liệu hiện tại)', () {
    final cats = [_c('c1')];
    expect(computeDeletableCategoryIds(cats, [_t('a')]), isEmpty);
    expect(computeDeletableCategoryIds(cats, const []), {'c1'});
  });

  test('Danh mục đang dùng / bị danh mục khác trỏ tới / có bước con đang được dùng → không xóa hẳn', () {
    final s = const Status(id: 's1', categoryId: 'c2', name: 'B', sortOrder: 0);
    final cats = [
      _c('active', active: true),
      _c('c2', statuses: [s]),
      _c('c3', linked: 'c4'),
      _c('c4'),
    ];
    final ledger = [_t('x', category: 'khac', statusId: 's1')];
    final d = computeDeletableCategoryIds(cats, ledger);
    expect(d, isNot(contains('active')));
    expect(d, isNot(contains('c2')), reason: 'bước con s1 đang được giao dịch dùng');
    expect(d, isNot(contains('c4')), reason: 'c3 trỏ tới c4');
    expect(d, contains('c3'));
  });

  test('Bước trạng thái: đã ngừng + không giao dịch nào dùng → xóa hẳn được; đang dùng / đang được giao dịch giữ → không', () {
    const stopped = Status(id: 's_stop', categoryId: 'c1', name: 'A', sortOrder: 0, isActive: false);
    const held = Status(id: 's_held', categoryId: 'c1', name: 'B', sortOrder: 1, isActive: false);
    const live = Status(id: 's_live', categoryId: 'c1', name: 'C', sortOrder: 2);
    final cats = [_c('c1', active: true, statuses: [stopped, held, live])];
    final d = computeDeletableStatusIds(cats, [_t('a', statusId: 's_held')]);
    expect(d, {'s_stop'});
    expect(computeDeletableStatusIds(cats, const []), {'s_stop', 's_held'}, reason: 'giao dịch cuối cùng đã bị xóa thật');
  });

  group('Lịch sử ẩn đã xóa theo cách cũ', () {
    final pair = [
      _t('o', category: 'zz', reversedBy: 'r'),
      _t('r', category: 'zz', reversalOf: 'o'),
    ];

    test('Cặp gốc + hoàn tác (không còn dòng hiệu lực) được nhận diện; giao dịch sống thì không', () {
      expect(deletedHistoryIdsForCategory('zz', pair), {'o', 'r'});
      expect(deletedHistoryIdsForCategory('zz', [...pair, _t('live', category: 'zz')]), {'o', 'r'});
      expect(deletedHistoryIdsForCategory('khac', pair), isEmpty);
      // Họ còn dòng đang hiệu lực (đã sửa số tiền, bản thay thế còn sống) → KHÔNG phải lịch sử ẩn.
      final chain = [
        _t('o2', category: 'zz', reversedBy: 'r2'),
        _t('r2', category: 'zz', reversalOf: 'o2'),
        _t('p2', category: 'zz', corrects: 'o2'),
      ];
      expect(deletedHistoryIdsForCategory('zz', chain), isEmpty);
    });

    test('Danh mục ngừng chỉ bị giữ bởi lịch sử ẩn → cho phép "Dọn"; còn giao dịch sống → không', () {
      final cats = [_c('zz')];
      expect(categoryHeldOnlyByDeletedHistory(cats.first, pair, cats), isTrue);
      expect(categoryHeldOnlyByDeletedHistory(cats.first, [...pair, _t('live', category: 'zz')], cats), isFalse);
      expect(categoryHeldOnlyByDeletedHistory(cats.first, const [], cats), isFalse, reason: 'không có gì để dọn');
    });
  });
}
