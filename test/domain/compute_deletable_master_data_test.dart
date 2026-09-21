import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/status.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/usecases/compute_deletable_master_data.dart';
import 'package:vi_nha_minh/domain/usecases/deletion_check.dart';

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

  test('Danh mục đang dùng / có bước con đang được dùng → không xóa hẳn; linkedExpenseCategoryId (metadata cũ) KHÔNG chặn', () {
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
    expect(d, contains('c4'), reason: 'c3 trỏ tới c4 nhưng đó chỉ là metadata cũ, không chặn');
    expect(d, contains('c3'));
  });

  test('Bước trạng thái: không giao dịch nào dùng → xóa hẳn được (đang dùng hay đã ngừng); còn giao dịch giữ → không', () {
    const stopped = Status(id: 's_stop', categoryId: 'c1', name: 'A', sortOrder: 0, isActive: false);
    const held = Status(id: 's_held', categoryId: 'c1', name: 'B', sortOrder: 1, isActive: false);
    const live = Status(id: 's_live', categoryId: 'c1', name: 'C', sortOrder: 2);
    final cats = [_c('c1', active: true, statuses: [stopped, held, live])];
    final d = computeDeletableStatusIds(cats, [_t('a', statusId: 's_held')]);
    expect(d, {'s_stop', 's_live'});
    expect(computeDeletableStatusIds(cats, const []), {'s_stop', 's_held', 's_live'}, reason: 'giao dịch cuối cùng đã bị xóa thật');
  });

  group('Lịch sử ẩn (dữ liệu của cơ chế cũ)', () {
    final pair = [
      _t('o', category: 'zz', reversedBy: 'r'),
      _t('r', category: 'zz', reversalOf: 'o'),
    ];
    bool holdsZz(Transaction t) => t.categoryId == 'zz';

    test('Cặp gốc + hoàn tác không còn dòng hiệu lực → xoá cả họ; danh mục khác → rỗng', () {
      expect(hiddenHistoryPurge(holdsZz, pair).deleteIds, {'o', 'r'});
      expect(hiddenHistoryPurge((t) => t.categoryId == 'khac', pair).isEmpty, isTrue);
    });

    test('Họ còn dòng hiệu lực (đã sửa kiểu cũ): chỉ xoá dòng ẩn, giữ bản thay thế và bỏ correctsTxId treo', () {
      final chain = [
        _t('o2', category: 'zz', reversedBy: 'r2'),
        _t('r2', category: 'zz', reversalOf: 'o2'),
        _t('p2', category: 'khac', corrects: 'o2'),
      ];
      final p = hiddenHistoryPurge(holdsZz, chain);
      expect(p.deleteIds, {'o2', 'r2'});
      expect(p.relinkIds, {'p2'});
    });
  });

  group('DeletionCheckResult / blockers', () {
    test('Danh mục còn giao dịch đang hiệu lực → blocker có ngày, số tiền, tên trạng thái', () {
      const s = Status(id: 'zs', categoryId: 'zz', name: 'Đã trả', sortOrder: 0);
      final cats = [_c('zz', statuses: [s])];
      final ledger = [_t('a', category: 'zz', statusId: 'zs')];
      final r = checkCategoryDeletion(cats.first, cats, ledger);
      expect(r.canDelete, isFalse);
      expect(r.transactionBlockers.single.transactionId, 'a');
      expect(r.transactionBlockers.single.statusName, 'Đã trả');
      expect(r.transactionBlockers.single.categoryName, 'zz');
    });

    test('Hết giao dịch → canDelete; lịch sử ẩn tách riêng khỏi giao dịch sống', () {
      final cats = [_c('zz')];
      expect(checkCategoryDeletion(cats.first, cats, const []).canDelete, isTrue);
      final hidden = [
        _t('o', category: 'zz', reversedBy: 'r'),
        _t('r', category: 'zz', reversalOf: 'o'),
      ];
      final r = checkCategoryDeletion(cats.first, cats, hidden);
      expect(r.transactionBlockers, isEmpty);
      expect(r.onlyHiddenHistory, isTrue);
    });

    test('Trạng thái được 2 giao dịch dùng → 2 blocker; gỡ 1 vẫn chặn; gỡ hết → xoá được', () {
      const s = Status(id: 's1', categoryId: 'c1', name: 'B', sortOrder: 0, isActive: false);
      final cats = [_c('c1', statuses: [s])];
      final two = [_t('a', statusId: 's1'), _t('b', statusId: 's1')];
      expect(checkStatusDeletion('s1', cats, two).transactionBlockers.length, 2);
      expect(checkStatusDeletion('s1', cats, [two.first]).canDelete, isFalse);
      expect(checkStatusDeletion('s1', cats, const []).canDelete, isTrue);
    });
  });
}
