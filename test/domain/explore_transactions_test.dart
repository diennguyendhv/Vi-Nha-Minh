import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/family_member.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/status.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/usecases/compute_grouped_totals.dart';
import 'package:vi_nha_minh/domain/usecases/explore_transactions.dart';

Category _cat(
  String id,
  TransactionType type, {
  bool exclude = false,
  String? group,
  List<Status> statuses = const [],
}) => Category(
  id: id,
  name: id,
  color: Colors.grey,
  type: type,
  excludeFromTotals: exclude,
  groupKey: group,
  statuses: statuses,
);

const _stChua = Status(id: 'st_chua', categoryId: 'cho_di', name: 'CCB', sortOrder: 0);
const _stGui = Status(id: 'st_gui', categoryId: 'cho_di', name: 'ĐG', sortOrder: 1);
const _stCu = Status(id: 'st_cu', categoryId: 'cho_di', name: 'Cũ', sortOrder: 2, isActive: false);
const _stKhac = Status(id: 'st_khac', categoryId: 'dang_hien', name: 'ĐD', sortOrder: 0);

final _cats = <Category>[
  _cat('hoc_phi', TransactionType.income),
  _cat('lap_trinh', TransactionType.income),
  _cat('so_du_ban_dau', TransactionType.income, exclude: true),
  _cat('thu_khac', TransactionType.income, exclude: true),
  _cat('sinh_hoat', TransactionType.expense),
  _cat('cho_di', TransactionType.expense, statuses: const [_stChua, _stGui, _stCu]),
  _cat('dang_hien', TransactionType.expense, statuses: const [_stKhac]),
  _cat('luong_gv', TransactionType.expense, group: CategoryGroupKey.businessExpense),
  _cat('quang_cao', TransactionType.expense, group: CategoryGroupKey.businessExpense),
  _cat('tiet_kiem', TransactionType.transfer),
  _cat('chuyen', TransactionType.transfer),
  _cat('cho_vay', TransactionType.transfer),
  _cat('vay_no', TransactionType.income),
  _cat('hoan_tien_thu_hoi', TransactionType.income, exclude: true),
];
final _byId = {for (final c in _cats) c.id: c};
const _hidden = {'cho_vay', 'vay_no', 'hoan_tien_thu_hoi'};

int _n = 0;
Transaction _in(
  String category,
  int amount, {
  String to = 'vo',
  DateTime? date,
  String note = '',
  String? reversedBy,
  String? reversalOf,
  String? correctsTxId,
  String? id,
  String? recoveryOf,
  String? obligation,
}) {
  _n++;
  final d = date ?? DateTime(2026, 9, 10);
  return Transaction(
    id: id ?? 'in-$_n',
    type: TransactionType.income,
    categoryId: category,
    sourceKind: PoolKind.external,
    destinationKind: PoolKind.memberAvailable,
    destinationRefId: to,
    amountMinor: amount,
    note: note,
    transactionDate: d,
    createdAt: d.add(Duration(seconds: _n)),
    clientTxId: 'c-in-$_n',
    reversedByTxId: reversedBy,
    reversalOfTxId: reversalOf,
    correctsTxId: correctsTxId,
    recoveryOfTxId: recoveryOf,
    obligationId: obligation,
  );
}

Transaction _out(
  String category,
  int amount, {
  String from = 'vo',
  DateTime? date,
  String note = '',
  String? statusId,
  String? reversedBy,
  String? reversalOf,
  String? correctsTxId,
  String? id,
}) {
  _n++;
  final d = date ?? DateTime(2026, 9, 10);
  return Transaction(
    id: id ?? 'out-$_n',
    type: TransactionType.expense,
    categoryId: category,
    sourceKind: PoolKind.memberAvailable,
    sourceRefId: from,
    destinationKind: PoolKind.external,
    amountMinor: amount,
    note: note,
    statusId: statusId,
    transactionDate: d,
    createdAt: d.add(Duration(seconds: _n)),
    clientTxId: 'c-out-$_n',
    reversedByTxId: reversedBy,
    reversalOfTxId: reversalOf,
    correctsTxId: correctsTxId,
  );
}

Transaction _move(String category, int amount, {String from = 'vo', String? to = 'chong', PoolKind toKind = PoolKind.memberAvailable, String note = ''}) {
  _n++;
  final d = DateTime(2026, 9, 10);
  return Transaction(
    id: 'mv-$_n',
    type: TransactionType.transfer,
    categoryId: category,
    sourceKind: PoolKind.memberAvailable,
    sourceRefId: from,
    destinationKind: toKind,
    destinationRefId: to,
    amountMinor: amount,
    note: note,
    transactionDate: d,
    createdAt: d.add(Duration(seconds: _n)),
    clientTxId: 'c-mv-$_n',
  );
}

ExplorerResult _run(List<Transaction> t, [TransactionFilter f = const TransactionFilter()]) =>
    exploreTransactions(t, _cats, f, hiddenCategoryIds: _hidden);

void main() {
  group('Thu nhập ròng theo thành viên (yêu cầu bắt buộc)', () {
    final ledger = [
      _in('hoc_phi', 10000000, to: 'vo'),
      _in('lap_trinh', 5000000, to: 'chong'),
      _in('so_du_ban_dau', 2000000, to: 'vo'),
      _in('thu_khac', 450000, to: 'chong'),
      _out('sinh_hoat', 3000000, from: 'vo'),
      _out('dang_hien', 1000000, from: 'chong'),
      _out('luong_gv', 4000000, from: 'vo'),
      _out('quang_cao', 500000, from: 'chong'),
    ];

    test('A — Vợ = Doanh thu Vợ nhận − Chi phí KD Vợ chi (không trừ Chi tiêu, không cộng Khoản thu khác)', () {
      expect(computeMemberNetIncome(FamilyMember.vo, ledger, _cats), 10000000 - 4000000);
    });

    test('B — Chồng = Doanh thu Chồng nhận − Chi phí KD Chồng chi', () {
      expect(computeMemberNetIncome(FamilyMember.chong, ledger, _cats), 5000000 - 500000);
    });

    test('C — Chi tiêu gia đình = tổng Chi tiêu của cả nhà (không gồm Chi phí KD)', () {
      expect(computeGroupedTotals(ledger, _cats).spending, 3000000 + 1000000);
    });

    test('Không chia đôi số cả nhà: Vợ + Chồng == Thu nhập ròng gia đình khi mọi giao dịch đều thuộc 1 thành viên', () {
      final vo = computeMemberNetIncome(FamilyMember.vo, ledger, _cats);
      final chong = computeMemberNetIncome(FamilyMember.chong, ledger, _cats);
      expect(vo + chong, computeGroupedTotals(ledger, _cats).netIncome);
    });

    test('Chi phí KD chi từ Quỹ (không thuộc ai) không tính cho thành viên nào', () {
      _n++;
      final fromFund = Transaction(
        id: 'fund-biz',
        type: TransactionType.expense,
        categoryId: 'luong_gv',
        sourceKind: PoolKind.fund,
        sourceRefId: 'fund-1',
        destinationKind: PoolKind.external,
        amountMinor: 900000,
        transactionDate: DateTime(2026, 9, 10),
        createdAt: DateTime(2026, 9, 10),
        clientTxId: 'c-fund-biz',
      );
      expect(computeMemberNetIncome(FamilyMember.vo, [...ledger, fromFund], _cats), 6000000);
      expect(computeGroupedTotals([...ledger, fromFund], _cats).businessExpense, 4500000 + 900000);
    });
  });

  group('Bộ lọc đơn', () {
    final ledger = [
      _in('hoc_phi', 2000000, to: 'vo', note: 'HP lớp Excel'),
      _in('lap_trinh', 500000, to: 'chong', note: 'web bán hàng'),
      _in('thu_khac', 450000, to: 'vo', note: 'Bán lại quạt'),
      _out('sinh_hoat', 120000, from: 'vo', note: 'Đi chợ'),
      _out('sinh_hoat', 5000, from: 'chong', note: 'gửi xe'),
      _out('luong_gv', 700000, from: 'vo', note: 'Lương cô Lam'),
      _out('cho_di', 300000, from: 'chong', statusId: 'st_chua', note: 'CĐ tháng 9'),
      _out('cho_di', 200000, from: 'vo', statusId: 'st_gui'),
      _move('chuyen', 500000, note: 'gửi chồng'),
    ];

    test('không filter → mọi dòng; tổng vào/ra chỉ tính Thu/Chi (Chuyển chỉ đếm số dòng)', () {
      final r = _run(ledger);
      expect(r.count, 9);
      expect(r.inflow, 2000000 + 500000 + 450000);
      expect(r.outflow, 120000 + 5000 + 700000 + 300000 + 200000);
    });

    test('D — Vợ: gồm Thu người nhận Vợ, Chi Vợ chi, và Chuyển Vợ gửi', () {
      final r = _run(ledger, const TransactionFilter(member: FamilyMember.vo));
      expect(r.rows.map((t) => t.note), containsAll(['HP lớp Excel', 'Bán lại quạt', 'Đi chợ', 'Lương cô Lam', 'gửi chồng']));
      expect(r.rows.any((t) => t.note == 'web bán hàng'), isFalse);
    });

    test('E — Chồng: gồm cả Chuyển Chồng nhận', () {
      final r = _run(ledger, const TransactionFilter(member: FamilyMember.chong));
      expect(r.rows.map((t) => t.note), containsAll(['web bán hàng', 'gửi xe', 'CĐ tháng 9', 'gửi chồng']));
      expect(r.rows.any((t) => t.note == 'Đi chợ'), isFalse);
    });

    test('F — nhóm chính; Chuyển không thuộc nhóm nào', () {
      final byGroup = {
        for (final g in MainGroup.values) g: _run(ledger, TransactionFilter(group: g)),
      };
      expect(byGroup[MainGroup.revenue]!.count, 2);
      expect(byGroup[MainGroup.otherInflow]!.count, 1);
      expect(byGroup[MainGroup.spending]!.count, 4);
      expect(byGroup[MainGroup.businessExpense]!.count, 1);
      expect(byGroup.values.fold<int>(0, (s, r) => s + r.count), 8, reason: '1 dòng Chuyển không thuộc nhóm nào');
    });

    test('G — danh mục', () {
      final r = _run(ledger, const TransactionFilter(categoryId: 'sinh_hoat'));
      expect(r.count, 2);
      expect(r.outflow, 125000, reason: 'khoản nhỏ 5.000đ vẫn có mặt và được cộng');
    });

    test('H — trạng thái', () {
      final r = _run(ledger, const TransactionFilter(categoryId: 'cho_di', statusId: 'st_chua'));
      expect(r.count, 1);
      expect(r.rows.single.note, 'CĐ tháng 9');
    });

    test('I — tìm Note: không phân biệt hoa/thường, khớp một phần, cắt khoảng trắng; rỗng = không lọc', () {
      // Bỏ dấu: "chợ" → "cho" cũng là chuỗi con của "gửi chồng" → "gui chong".
      // Đây là hệ quả đúng của tìm không dấu (khớp một phần), không phải lỗi.
      expect(_run(ledger, const TransactionFilter(query: '  CHỢ ')).count, 2);
      expect(_run(ledger, const TransactionFilter(query: '  CHỢ ')).rows.any((t) => t.note == 'Đi chợ'), isTrue);
      expect(_run(ledger, const TransactionFilter(query: 'lương')).count, 1);
      expect(_run(ledger, const TransactionFilter(query: 'hp')).count, 1);
      expect(_run(ledger, const TransactionFilter(query: 'lam')).count, 1);
      expect(_run(ledger, const TransactionFilter(query: '   ')).count, ledger.length);
      expect(_run(ledger, const TransactionFilter(query: 'xyzabc')).count, 0);
    });

    test('Tìm Note không phân biệt dấu tiếng Việt: "cho" khớp "Đi chợ"; "lam" khớp "Lương cô Lam"', () {
      expect(_run(ledger, const TransactionFilter(query: 'cho')).rows.any((t) => t.note == 'Đi chợ'), isTrue);
      expect(_run(ledger, const TransactionFilter(query: 'luong co lam')).count, 1);
    });

    group('Tìm Note có dấu ↔ không dấu (chỉ truy xuất văn bản)', () {
      List<Transaction> notes(List<String> ns) => [
        for (final n in ns) _out('sinh_hoat', 1000, note: n),
      ];
      int count(List<String> ns, String q) =>
          _run(notes(ns), TransactionFilter(query: q)).count;

      test('note có dấu, query không dấu', () {
        expect(count(['Lương giáo viên'], 'luong'), 1);
        expect(count(['Quảng cáo Facebook'], 'quang cao'), 1);
        expect(count(['Dâng hiến tháng 9'], 'dang hien'), 1);
        expect(count(['chị Lam'], 'chi lam'), 1);
      });

      test('note không dấu, query có dấu', () {
        expect(count(['luong giao vien'], 'lương'), 1);
        expect(count(['quang cao facebook'], 'Quảng Cáo'), 1);
      });

      test('đ / Đ → d, hoa/thường, dấu gõ rời (NFD)', () {
        expect(count(['Đi siêu thị'], 'di sieu'), 1);
        expect(count(['di sieu thi'], 'ĐI SIÊU'), 1);
        expect(count(['Đèn'], 'den'), 1);
        expect(count(['Việt'], 'viet'), 1, reason: 'e + dấu rời');
      });

      test('một phần, cắt khoảng trắng đầu/cuối, khoảng trắng kép; rỗng = không lọc', () {
        expect(count(['Lương giáo viên'], 'giao'), 1);
        expect(count(['Lương giáo viên'], '  giáo  '), 1);
        expect(count(['Dâng  hiến'], 'dang hien'), 1);
        expect(count(['Lương giáo viên', 'x'], ''), 2);
        expect(count(['Lương giáo viên', 'x'], '   '), 2);
      });

      test('không khớp: khác chữ cái gốc vẫn không khớp', () {
        expect(count(['Lương giáo viên'], 'xyz'), 0);
        expect(count(['chợ'], 'chu'), 0, reason: 'o ≠ u, không bỏ dấu quá tay');
        expect(count(['Đi chợ'], 'ci'), 0);
      });

      test('kết hợp AND: bỏ dấu không làm lỏng các bộ lọc khác', () {
        final ledger = [
          _out('sinh_hoat', 300000, from: 'vo', note: 'Đi siêu thị'),
          _out('sinh_hoat', 200000, from: 'chong', note: 'Đi chợ'),
          _out('luong_gv', 100000, from: 'vo', note: 'Đi dạy'),
        ];
        final r = _run(
          ledger,
          const TransactionFilter(
            member: FamilyMember.vo,
            categoryId: 'sinh_hoat',
            query: 'di',
          ),
        );
        expect(r.count, 1);
        expect(r.outflow, 300000);
      });
    });

    test('J — khoảng ngày (2 đầu bao gồm, so theo ngày, bỏ giờ)', () {
      final dated = [
        _out('sinh_hoat', 1000, date: DateTime(2026, 9, 1, 0, 5)),
        _out('sinh_hoat', 2000, date: DateTime(2026, 9, 15, 23, 59)),
        _out('sinh_hoat', 4000, date: DateTime(2026, 9, 30, 12)),
        _out('sinh_hoat', 8000, date: DateTime(2026, 10, 1)),
      ];
      final r = _run(dated, TransactionFilter(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30, 23, 59)));
      expect(r.outflow, 7000);
      final today = _run(dated, TransactionFilter(from: DateTime(2026, 9, 15), to: DateTime(2026, 9, 15)));
      expect(today.outflow, 2000);
    });
  });

  group('Kết hợp (AND, không phải OR)', () {
    final ledger = [
      _out('sinh_hoat', 120000, from: 'vo', note: 'Đi chợ', date: DateTime(2026, 9, 16)),
      _out('sinh_hoat', 80000, from: 'chong', note: 'đi chợ', date: DateTime(2026, 9, 16)),
      _out('sinh_hoat', 60000, from: 'vo', note: 'cà phê', date: DateTime(2026, 9, 16)),
      _out('sinh_hoat', 40000, from: 'vo', note: 'Đi chợ', date: DateTime(2026, 8, 20)),
      _out('luong_gv', 500000, from: 'vo', note: 'chợ', date: DateTime(2026, 9, 16)),
    ];

    test('K — Tháng 9 + Vợ + Chi tiêu + Sinh hoạt + note "chợ" = đúng giao', () {
      var f = TransactionFilter(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30));
      f = f.withMember(FamilyMember.vo);
      f = f.withGroup(MainGroup.spending, _byId, hiddenCategoryIds: _hidden);
      f = f.withCategory('sinh_hoat', _byId);
      f = f.withQuery('chợ');
      final r = _run(ledger, f);
      expect(r.count, 1);
      expect(r.rows.single.amountMinor, 120000);
      expect(r.outflow, 120000);
    });

    test('Bỏ bớt từng điều kiện thì tập rộng dần', () {
      var f = TransactionFilter(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30))
          .withMember(FamilyMember.vo)
          .withCategory('sinh_hoat', _byId);
      expect(_run(ledger, f).count, 2);
      f = f.withMember(null);
      expect(_run(ledger, f).count, 3);
      f = f.withRange(null, null);
      expect(_run(ledger, f).count, 4);
    });
  });

  group('Quy tắc phụ thuộc Nhóm → Danh mục → Trạng thái', () {
    test('đổi nhóm → xoá danh mục (và trạng thái) không còn thuộc nhóm', () {
      var f = const TransactionFilter()
          .withCategory('cho_di', _byId)
          .withStatus('st_gui');
      expect(f.categoryId, 'cho_di');
      f = f.withGroup(MainGroup.businessExpense, _byId, hiddenCategoryIds: _hidden);
      expect(f.group, MainGroup.businessExpense);
      expect(f.categoryId, isNull);
      expect(f.statusId, isNull);
    });

    test('đổi nhóm sang nhóm CHỨA danh mục hiện tại → giữ danh mục và trạng thái', () {
      var f = const TransactionFilter().withCategory('cho_di', _byId).withStatus('st_gui');
      f = f.withGroup(MainGroup.spending, _byId, hiddenCategoryIds: _hidden);
      expect(f.categoryId, 'cho_di');
      expect(f.statusId, 'st_gui');
      f = f.withGroup(null, _byId);
      expect(f.categoryId, 'cho_di');
    });

    test('Q — đổi sang danh mục không có / khác bộ trạng thái → xoá trạng thái', () {
      var f = const TransactionFilter().withCategory('cho_di', _byId).withStatus('st_gui');
      f = f.withCategory('sinh_hoat', _byId);
      expect(f.statusId, isNull, reason: 'sinh_hoat không có trạng thái');
      f = const TransactionFilter().withCategory('cho_di', _byId).withStatus('st_gui').withCategory('dang_hien', _byId);
      expect(f.statusId, isNull, reason: 'st_gui không thuộc dang_hien');
      f = const TransactionFilter().withCategory('cho_di', _byId).withStatus('st_gui').withCategory(null, _byId);
      expect(f.statusId, isNull);
    });

    test('Q — trạng thái đã ẩn (lịch sử) vẫn lọc được và vẫn resolve tên', () {
      final ledger = [_out('cho_di', 70000, statusId: 'st_cu', note: 'cũ'), _out('cho_di', 1000, statusId: 'st_chua')];
      final r = _run(ledger, const TransactionFilter(categoryId: 'cho_di', statusId: 'st_cu'));
      expect(r.count, 1);
      expect(_byId['cho_di']!.statusById('st_cu')!.name, 'Cũ');
    });

    test('hasNonDateFilter / advancedCount phản ánh đúng để hiện "Xoá bộ lọc"', () {
      expect(const TransactionFilter().hasNonDateFilter, isFalse);
      expect(const TransactionFilter(query: ' ').hasNonDateFilter, isFalse);
      expect(const TransactionFilter(member: FamilyMember.vo).hasNonDateFilter, isTrue);
      final f = const TransactionFilter(group: MainGroup.spending, categoryId: 'sinh_hoat');
      expect(f.advancedCount, 2);
    });
  });

  group('Reversal / correction / lịch sử ẩn', () {
    test('R — correction: chỉ bản mới nhất xuất hiện; tổng không đếm đôi', () {
      final old = _out('sinh_hoat', 500000, id: 'old', reversedBy: 'rev', note: 'sai');
      final rev = _in('sinh_hoat', 500000, reversalOf: 'old');
      final fixed = _out('sinh_hoat', 350000, correctsTxId: 'old', note: 'đúng');
      final r = _run([old, rev, fixed]);
      expect(r.count, 1);
      expect(r.rows.single.note, 'đúng');
      expect(r.outflow, 350000);
      expect(r.inflow, 0, reason: 'bản reversal nội bộ không phải khoản thu');
    });

    test('S — reversed (xoá): không hiện, không tính', () {
      final gone = _out('luong_gv', 700000, id: 'gone', reversedBy: 'rev2');
      final rev = _in('luong_gv', 700000, reversalOf: 'gone');
      final r = _run([gone, rev, _out('sinh_hoat', 10000)]);
      expect(r.count, 1);
      expect(r.outflow, 10000);
    });

    test('T/U — lịch sử Recovery/Vay cũ: không crash, hiện khi "Tất cả", không thuộc nhóm nào', () {
      final buy = _out('sinh_hoat', 2000000, id: 'buy', note: 'mua quạt');
      final sell = _in('hoan_tien_thu_hoi', 450000, recoveryOf: 'buy', note: 'bán lại quạt');
      final loan = _in('vay_no', 1000000, obligation: 'ob-1', note: 'vay');
      final lend = _move('cho_vay', 300000, to: 'ob-2', toKind: PoolKind.receivable, note: 'cho vay');
      final ledger = [buy, sell, loan, lend];

      expect(_run(ledger).count, 4);
      expect(_run(ledger, const TransactionFilter(query: 'quạt')).count, 2);
      for (final g in MainGroup.values) {
        final r = _run(ledger, TransactionFilter(group: g));
        expect(r.rows.any((t) => t.categoryId == 'hoan_tien_thu_hoi' || t.categoryId == 'vay_no' || t.categoryId == 'cho_vay'), isFalse);
      }
      // Lọc theo thành viên vẫn an toàn với dòng có đích là khoản vay.
      expect(_run(ledger, const TransactionFilter(member: FamilyMember.vo)).count, greaterThanOrEqualTo(3));
    });
  });

  group('Hiệu năng ~1.800 giao dịch (smoke)', () {
    test('V — lọc/tìm/kết hợp trên 1.800 dòng nhanh và đúng', () {
      final ledger = <Transaction>[];
      for (var i = 0; i < 1800; i++) {
        final day = DateTime(2026, 1 + (i % 9), 1 + (i % 28));
        if (i % 3 == 0) {
          ledger.add(_in(i % 2 == 0 ? 'hoc_phi' : 'thu_khac', 1000 + i, to: i % 2 == 0 ? 'vo' : 'chong', date: day, note: 'thu $i'));
        } else {
          ledger.add(_out(i % 5 == 0 ? 'luong_gv' : 'sinh_hoat', 1000 + i, from: i % 2 == 0 ? 'vo' : 'chong', date: day, note: i % 7 == 0 ? 'đi chợ $i' : 'chi $i'));
        }
      }
      final sw = Stopwatch()..start();
      final all = _run(ledger);
      final vo = _run(ledger, const TransactionFilter(member: FamilyMember.vo));
      final combo = _run(
        ledger,
        TransactionFilter(from: DateTime(2026, 3, 1), to: DateTime(2026, 6, 30))
            .withMember(FamilyMember.vo)
            .withGroup(MainGroup.spending, _byId, hiddenCategoryIds: _hidden)
            .withQuery('chợ'),
      );
      final search = _run(ledger, const TransactionFilter(query: 'chi 1'));
      sw.stop();

      expect(all.count, 1800);
      expect(vo.count, lessThan(all.count));
      expect(combo.rows.every((t) => t.note.contains('chợ') && involvesMember(t, FamilyMember.vo)), isTrue);
      expect(search.count, greaterThan(0));
      expect(sw.elapsedMilliseconds, lessThan(1500), reason: '4 truy vấn trên 1.800 dòng phải rất nhanh (thường < 50ms)');
      // Sắp xếp mới nhất lên đầu.
      for (var i = 1; i < all.rows.length; i++) {
        expect(all.rows[i - 1].transactionDate.compareTo(all.rows[i].transactionDate) >= 0, isTrue);
      }
    });
  });
}
