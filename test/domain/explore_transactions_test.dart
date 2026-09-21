import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
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
      expect(computeMemberNetIncome('vo', ledger, _cats), 10000000 - 4000000);
    });

    test('B — Chồng = Doanh thu Chồng nhận − Chi phí KD Chồng chi', () {
      expect(computeMemberNetIncome('chong', ledger, _cats), 5000000 - 500000);
    });

    test('C — Chi tiêu gia đình = tổng Chi tiêu của cả nhà (không gồm Chi phí KD)', () {
      expect(computeGroupedTotals(ledger, _cats).spending, 3000000 + 1000000);
    });

    test('Không chia đôi số cả nhà: Vợ + Chồng == Thu nhập ròng gia đình khi mọi giao dịch đều thuộc 1 thành viên', () {
      final vo = computeMemberNetIncome('vo', ledger, _cats);
      final chong = computeMemberNetIncome('chong', ledger, _cats);
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
      expect(computeMemberNetIncome('vo', [...ledger, fromFund], _cats), 6000000);
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
      final r = _run(ledger, const TransactionFilter(memberId: 'vo'));
      expect(r.rows.map((t) => t.note), containsAll(['HP lớp Excel', 'Bán lại quạt', 'Đi chợ', 'Lương cô Lam', 'gửi chồng']));
      expect(r.rows.any((t) => t.note == 'web bán hàng'), isFalse);
    });

    test('E — Chồng: gồm cả Chuyển Chồng nhận', () {
      final r = _run(ledger, const TransactionFilter(memberId: 'chong'));
      expect(r.rows.map((t) => t.note), containsAll(['web bán hàng', 'gửi xe', 'CĐ tháng 9', 'gửi chồng']));
      expect(r.rows.any((t) => t.note == 'Đi chợ'), isFalse);
    });

    test('F — nhóm chính suy từ cờ của Category (chỉ để phân nhóm hiển thị); Chuyển không thuộc nhóm nào', () {
      MainGroup? g(String id) => categoryGroupOf(_byId[id]!, _hidden);
      expect(g('hoc_phi'), MainGroup.revenue);
      expect(g('thu_khac'), MainGroup.otherInflow);
      expect(g('sinh_hoat'), MainGroup.spending);
      expect(g('luong_gv'), MainGroup.businessExpense);
      expect(g('tiet_kiem'), isNull);
      expect(g('vay_no'), isNull, reason: 'danh mục hệ thống nâng cao');
    });

    test('G — danh mục', () {
      final r = _run(ledger, const TransactionFilter(categoryIds: {'sinh_hoat'}));
      expect(r.count, 2);
      expect(r.outflow, 125000, reason: 'khoản nhỏ 5.000đ vẫn có mặt và được cộng');
    });

    test('H — trạng thái', () {
      final r = _run(ledger, const TransactionFilter(categoryIds: {'cho_di'}, statusIds: {'st_chua'}));
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
            memberId: 'vo',
            categoryIds: {'sinh_hoat'},
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

    test('K — Tháng 9 + Vợ + Sinh hoạt + note "chợ" = đúng giao', () {
      var f = TransactionFilter(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30));
      f = f.withMember('vo');
      f = f.withCategories({'sinh_hoat'});
      f = f.withQuery('chợ');
      final r = _run(ledger, f);
      expect(r.count, 1);
      expect(r.rows.single.amountMinor, 120000);
      expect(r.outflow, 120000);
    });

    test('Bỏ bớt từng điều kiện thì tập rộng dần', () {
      var f = TransactionFilter(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30))
          .withMember('vo')
          .withCategories({'sinh_hoat'});
      expect(_run(ledger, f).count, 2);
      f = f.withMember(null);
      expect(_run(ledger, f).count, 3);
      f = f.withRange(null, null);
      expect(_run(ledger, f).count, 4);
    });
  });

  group('Excel-like: nhiều lựa chọn, chiều độc lập, OR trong chiều / AND giữa chiều', () {
    // st_chua/st_gui thuộc cho_di; st_khac thuộc dang_hien (cùng tên "ĐD" ở bài test riêng).
    final ledger = [
      _out('sinh_hoat', 1000, id: 'sh1', from: 'chong', note: 'gửi xe'),
      _out('sinh_hoat', 120000, id: 'sh2', from: 'vo', note: 'Đi chợ'),
      _out('luong_gv', 700000, id: 'gv1', from: 'chong', note: 'Lương cô Lam'),
      _out('cho_di', 300000, id: 'cd1', from: 'chong', statusId: 'st_chua'),
      _out('cho_di', 200000, id: 'cd2', from: 'chong', statusId: 'st_gui', note: 'lương tháng'),
      _out('dang_hien', 150000, id: 'dh1', from: 'chong', statusId: 'st_khac'),
      _in('hoc_phi', 2000000, id: 'in1', to: 'chong', note: 'HP lớp Excel'),
    ];
    Set<String> ids(ExplorerResult r) => {for (final t in r.rows) t.id};

    test('Nhiều danh mục = OR; 0 danh mục = tất cả', () {
      expect(ids(_run(ledger, const TransactionFilter(categoryIds: {'sinh_hoat', 'luong_gv'}))), {'sh1', 'sh2', 'gv1'});
      expect(_run(ledger, const TransactionFilter()).count, ledger.length);
      expect(_run(ledger, const TransactionFilter(categoryIds: {'khong_co'})).count, 0);
    });

    test('Nhiều trạng thái = OR, không phụ thuộc danh mục', () {
      final r = _run(ledger, const TransactionFilter(statusIds: {'st_chua', 'st_khac'}));
      expect(ids(r), {'cd1', 'dh1'});
    });

    test('Trạng thái trùng tên ở 2 danh mục là 2 id khác nhau: chọn cả hai → giao dịch của CẢ HAI danh mục', () {
      // "ĐD" của cho_di và "ĐD" của dang_hien: tạo bộ danh mục riêng.
      const a = Status(id: 'dd_cd', categoryId: 'cho_di', name: 'ĐD', sortOrder: 0);
      const b = Status(id: 'dd_dh', categoryId: 'dang_hien', name: 'ĐD', sortOrder: 0);
      final cats = [
        _cat('cho_di', TransactionType.expense, statuses: const [a]),
        _cat('dang_hien', TransactionType.expense, statuses: const [b]),
      ];
      final txs = [
        _out('cho_di', 10000, id: 'x1', statusId: 'dd_cd'),
        _out('dang_hien', 20000, id: 'x2', statusId: 'dd_dh'),
      ];
      final both = exploreTransactions(txs, cats, const TransactionFilter(statusIds: {'dd_cd', 'dd_dh'}));
      expect(ids(both), {'x1', 'x2'});
      final onlyOne = exploreTransactions(txs, cats, const TransactionFilter(statusIds: {'dd_dh'}));
      expect(ids(onlyOne), {'x2'});
      final opts = explorerStatusOptions(cats, txs);
      expect(opts.map((o) => o.label), ['ĐD · cho_di', 'ĐD · dang_hien'], reason: 'phân biệt bằng tên danh mục');
    });

    test('"Không có trạng thái" = statusId null; kết hợp với trạng thái khác = null OR X', () {
      final none = _run(ledger, const TransactionFilter(includeNoStatus: true));
      expect(ids(none), {'sh1', 'sh2', 'gv1', 'in1'});
      final noneOrChua = _run(ledger, const TransactionFilter(statusIds: {'st_chua'}, includeNoStatus: true));
      expect(ids(noneOrChua), {'sh1', 'sh2', 'gv1', 'in1', 'cd1'});
    });

    test('Chéo chiều: Năm + Chồng + (A|B) + (X|Y) + note = giao đúng', () {
      final f = TransactionFilter(from: DateTime(2026, 1, 1), to: DateTime(2026, 12, 31))
          .withMember('chong')
          .withCategories({'luong_gv', 'cho_di', 'dang_hien'})
          .withStatuses({'st_gui', 'st_khac'}, includeNone: true)
          .withQuery('luong');
      // gv1: luong_gv, không trạng thái, note "Lương cô Lam" → khớp.
      // cd2: cho_di, st_gui, note "lương tháng" → khớp. cd1 sai note; dh1 sai note.
      expect(ids(_run(ledger, f)), {'gv1', 'cd2'});
    });

    test('Giao rỗng → 0 kết quả, bộ lọc giữ nguyên (không tự nới)', () {
      final f = const TransactionFilter().withCategories({'sinh_hoat'}).withStatuses({'st_khac'});
      expect(_run(ledger, f).count, 0);
      expect(f.categoryIds, {'sinh_hoat'});
      expect(f.statusIds, {'st_khac'});
    });

    test('Độc lập thứ tự: chọn theo 2 thứ tự khác nhau ra cùng kết quả', () {
      final range = (DateTime(2026, 1, 1), DateTime(2026, 12, 31));
      final a = const TransactionFilter()
          .withRange(range.$1, range.$2)
          .withMember('chong')
          .withCategories({'cho_di', 'dang_hien'})
          .withStatuses({'st_chua', 'st_khac'});
      final b = const TransactionFilter()
          .withStatuses({'st_chua', 'st_khac'})
          .withCategories({'cho_di', 'dang_hien'})
          .withMember('chong')
          .withRange(range.$1, range.$2);
      expect(ids(_run(ledger, a)), ids(_run(ledger, b)));
      expect(ids(_run(ledger, a)), {'cd1', 'dh1'});
    });

    test('Đổi/bỏ 1 chiều KHÔNG làm đổi chiều khác', () {
      var f = const TransactionFilter().withCategories({'cho_di'}).withStatuses({'st_khac'});
      f = f.withCategories({'dang_hien'});
      expect(f.statusIds, {'st_khac'});
      f = f.withCategories({});
      expect(f.statusIds, {'st_khac'});
      expect(f.hasStatusFilter, isTrue);
    });

    // Bộ dữ liệu điều khiển: 19/09 {50.000, 800.000} và 20/09 {20.000, 100.000, 600.000}.
    List<Transaction> twoDays() => [
      _out('sinh_hoat', 50000, id: 'd19-50', date: DateTime(2026, 9, 19, 9)),
      _out('sinh_hoat', 800000, id: 'd19-800', date: DateTime(2026, 9, 19, 15)),
      _out('sinh_hoat', 20000, id: 'd20-20', date: DateTime(2026, 9, 20, 8)),
      _out('sinh_hoat', 100000, id: 'd20-100', date: DateTime(2026, 9, 20, 12)),
      _out('sinh_hoat', 600000, id: 'd20-600', date: DateTime(2026, 9, 20, 18)),
    ];
    // Bộ có số tiền BẰNG NHAU khác ngày (để thấy vai trò khóa phụ).
    List<Transaction> ties() => [
      _out('sinh_hoat', 100000, id: 't19-100', date: DateTime(2026, 9, 19, 10)),
      _out('sinh_hoat', 100000, id: 't20-100', date: DateTime(2026, 9, 20, 10)),
      _out('sinh_hoat', 100000, id: 't21-100', date: DateTime(2026, 9, 21, 10)),
      _out('sinh_hoat', 50000, id: 't20-50', date: DateTime(2026, 9, 20, 11)),
    ];
    List<String> order(List<Transaction> t, ExplorerSort s) => [
      for (final r in _run(t, TransactionFilter(sort: s)).rows) r.id,
    ];
    ExplorerSort sortOf(List<(SortKey, bool)> rules) => ExplorerSort([
      for (final r in rules) SortRule(r.$1, ascending: r.$2),
    ]);
    const dateKey = SortKey.date, amountKey = SortKey.amount;
    const desc = false, asc = true;

    test('Mặc định = CHỈ Ngày ↓ (không âm thầm có khóa Số tiền)', () {
      expect(ExplorerSort.defaultSort.isDefault, isTrue);
      expect(ExplorerSort.defaultSort.rules, [const SortRule(SortKey.date)]);
      expect(const TransactionFilter().sort.isDefault, isTrue);
      expect(_run(twoDays()).rows.map((t) => t.id).toList(), ['d20-20', 'd20-100', 'd20-600', 'd19-50', 'd19-800'],
          reason: 'trong cùng ngày: tie-break cố định (giờ ↑), KHÔNG dùng số tiền');
    });

    group('Ma trận 12 cấu hình', () {
      final cases = <String, (List<(SortKey, bool)>, List<String>)>{
        '1. Ngày ↓ only': ([(dateKey, desc)], ['d20-20', 'd20-100', 'd20-600', 'd19-50', 'd19-800']),
        '2. Ngày ↑ only': ([(dateKey, asc)], ['d19-50', 'd19-800', 'd20-20', 'd20-100', 'd20-600']),
        '3. Số tiền ↓ only': ([(amountKey, desc)], ['d19-800', 'd20-600', 'd20-100', 'd19-50', 'd20-20']),
        '4. Số tiền ↑ only': ([(amountKey, asc)], ['d20-20', 'd19-50', 'd20-100', 'd20-600', 'd19-800']),
        '5. Ngày ↓ → Số tiền ↓': ([(dateKey, desc), (amountKey, desc)], ['d20-600', 'd20-100', 'd20-20', 'd19-800', 'd19-50']),
        '6. Ngày ↓ → Số tiền ↑': ([(dateKey, desc), (amountKey, asc)], ['d20-20', 'd20-100', 'd20-600', 'd19-50', 'd19-800']),
        '7. Ngày ↑ → Số tiền ↓': ([(dateKey, asc), (amountKey, desc)], ['d19-800', 'd19-50', 'd20-600', 'd20-100', 'd20-20']),
        '8. Ngày ↑ → Số tiền ↑': ([(dateKey, asc), (amountKey, asc)], ['d19-50', 'd19-800', 'd20-20', 'd20-100', 'd20-600']),
      };
      cases.forEach((name, c) {
        test(name, () => expect(order(twoDays(), sortOf(c.$1)), c.$2));
      });

      final tieCases = <String, (List<(SortKey, bool)>, List<String>)>{
        '9. Số tiền ↓ → Ngày ↓': ([(amountKey, desc), (dateKey, desc)], ['t21-100', 't20-100', 't19-100', 't20-50']),
        '10. Số tiền ↓ → Ngày ↑': ([(amountKey, desc), (dateKey, asc)], ['t19-100', 't20-100', 't21-100', 't20-50']),
        '11. Số tiền ↑ → Ngày ↓': ([(amountKey, asc), (dateKey, desc)], ['t20-50', 't21-100', 't20-100', 't19-100']),
        '12. Số tiền ↑ → Ngày ↑': ([(amountKey, asc), (dateKey, asc)], ['t20-50', 't19-100', 't20-100', 't21-100']),
      };
      tieCases.forEach((name, c) {
        test(name, () => expect(order(ties(), sortOf(c.$1)), c.$2));
      });
    });

    test('A — chỉ Ngày: 20/09 20k đứng trên 19/09 8tr (Ngày ↓)', () {
      final t = [
        _out('sinh_hoat', 8000000, id: 'old-big', date: DateTime(2026, 9, 19, 10)),
        _out('sinh_hoat', 20000, id: 'new-small', date: DateTime(2026, 9, 20, 10)),
      ];
      expect(order(t, sortOf([(dateKey, desc)])), ['new-small', 'old-big']);
    });

    test('B — chỉ Số tiền: 8tr (19/09) đứng trên 20k (20/09); Ngày KHÔNG là khóa chính ẩn', () {
      final t = [
        _out('sinh_hoat', 8000000, id: 'old-big', date: DateTime(2026, 9, 19, 10)),
        _out('sinh_hoat', 20000, id: 'new-small', date: DateTime(2026, 9, 20, 10)),
        _out('sinh_hoat', 600000, id: 'new-600', date: DateTime(2026, 9, 20, 9)),
        _out('sinh_hoat', 500000, id: 'aug-500', date: DateTime(2026, 8, 3, 9)),
      ];
      expect(order(t, sortOf([(amountKey, desc)])), ['old-big', 'new-600', 'aug-500', 'new-small']);
    });

    test('C — Ngày trước: số tiền lớn ở ngày cũ KHÔNG vượt qua nhóm ngày mới hơn', () {
      final t = [
        _out('sinh_hoat', 8000000, id: 'old-big', date: DateTime(2026, 9, 19, 10)),
        _out('sinh_hoat', 20000, id: 'new-small', date: DateTime(2026, 9, 20, 10)),
      ];
      expect(order(t, sortOf([(dateKey, desc), (amountKey, desc)])), ['new-small', 'old-big']);
    });

    test('D — Số tiền trước: số tiền nhỏ ở ngày mới KHÔNG vượt số tiền lớn hơn ở ngày cũ', () {
      final t = [
        _out('sinh_hoat', 8000000, id: 'old-big', date: DateTime(2026, 9, 19, 10)),
        _out('sinh_hoat', 20000, id: 'new-small', date: DateTime(2026, 9, 20, 10)),
      ];
      expect(order(t, sortOf([(amountKey, desc), (dateKey, desc)])), ['old-big', 'new-small']);
    });

    test('Khóa KHÔNG bật không được ngầm làm khóa phụ (chỉ Ngày: đổi số tiền không làm đổi thứ tự trong ngày)', () {
      final day20 = twoDays().where((t) => t.transactionDate.day == 20).toList();
      final dateOnlyDesc = order(day20, sortOf([(dateKey, desc)]));
      expect(dateOnlyDesc, ['d20-20', 'd20-100', 'd20-600'], reason: 'tie-break cố định giờ ↑');
      expect(order(day20, sortOf([(dateKey, asc)])), dateOnlyDesc, reason: 'chiều Ngày không đổi thứ tự BÊN TRONG ngày');
      expect(order(day20, sortOf([(dateKey, desc), (amountKey, desc)])), ['d20-600', 'd20-100', 'd20-20']);
    });

    test('So sánh theo NGÀY LỊCH: giờ trong ngày không lấn Số tiền khi Ngày là khóa chính', () {
      final t = [
        _out('sinh_hoat', 100, id: 'late-small', date: DateTime(2026, 9, 20, 23, 59)),
        _out('sinh_hoat', 900, id: 'early-big', date: DateTime(2026, 9, 20, 0, 1)),
      ];
      expect(order(t, sortOf([(dateKey, desc), (amountKey, desc)])), ['early-big', 'late-small']);
    });

    test('Cùng mọi khóa bật: tie-break CỐ ĐỊNH (giờ ↑, giờ tạo ↑, id), không đổi theo chiều; xác định', () {
      final t = [
        _out('sinh_hoat', 100, id: 'c', date: DateTime(2026, 9, 20, 10)),
        _out('sinh_hoat', 100, id: 'a', date: DateTime(2026, 9, 20, 8)),
        _out('sinh_hoat', 100, id: 'b', date: DateTime(2026, 9, 20, 9)),
      ];
      for (final s in [
        sortOf([(dateKey, desc)]),
        sortOf([(dateKey, asc)]),
        sortOf([(amountKey, desc)]),
        sortOf([(amountKey, asc), (dateKey, desc)]),
      ]) {
        expect(order(t, s), ['a', 'b', 'c']);
        expect(order(t, s), order(t.reversed.toList(), s), reason: 'không phụ thuộc thứ tự đầu vào');
      }
    });

    test('Sắp xếp KHÔNG đổi bộ lọc/số dòng/tổng Thu-Chi — chỉ đổi thứ tự (mọi cấu hình)', () {
      final t = twoDays();
      final def = _run(t, const TransactionFilter());
      for (final s in [
        sortOf([(amountKey, asc)]),
        sortOf([(dateKey, asc)]),
        sortOf([(amountKey, desc), (dateKey, asc)]),
        sortOf([(dateKey, asc), (amountKey, asc)]),
      ]) {
        final r = _run(t, TransactionFilter(sort: s));
        expect((r.count, r.inflow, r.outflow), (def.count, def.inflow, def.outflow));
        expect({for (final x in r.rows) x.id}, {for (final x in def.rows) x.id});
      }
    });

    test('Lọc rồi sắp xếp: sắp xếp áp lên tập đã lọc', () {
      final t = [
        ...twoDays(),
        _out('cho_di', 999999, id: 'other-cat', date: DateTime(2026, 9, 20, 11)),
      ];
      final f = const TransactionFilter().withCategories({'sinh_hoat'}).withSort(sortOf([(amountKey, asc)]));
      expect([for (final r in _run(t, f).rows) r.id], ['d20-20', 'd19-50', 'd20-100', 'd20-600', 'd19-800']);
    });

    test('encode/decode: khứ hồi giữ khóa bật, thứ tự ưu tiên, chiều; sai định dạng → mặc định', () {
      for (final s in [
        sortOf([(dateKey, desc)]),
        sortOf([(amountKey, asc), (dateKey, desc)]),
        sortOf([(dateKey, asc), (amountKey, asc)]),
      ]) {
        expect(ExplorerSort.decode(s.encode()), s);
      }
      expect(sortOf([(amountKey, desc), (dateKey, asc)]).encode(), 'amount:desc,date:asc');
      for (final bad in [null, '', 'x', 'date:up', 'date:asc,date:desc', 'foo:asc', 'date']) {
        expect(ExplorerSort.decode(bad), ExplorerSort.defaultSort, reason: '$bad');
      }
      expect(sortOf([(amountKey, desc)]) == sortOf([(dateKey, desc)]), isFalse);
    });

    test('Tổng của tập đã lọc: Thu/Chi tách riêng; Chuyển chỉ đếm dòng', () {
      final withMove = [...ledger, _move('chuyen', 500000)];
      final r = _run(withMove, const TransactionFilter(categoryIds: {'sinh_hoat', 'hoc_phi', 'chuyen'}));
      expect(r.count, 4);
      expect(r.inflow, 2000000);
      expect(r.outflow, 121000);
    });

    test('Bộ chọn danh mục: đang dùng luôn có; ngừng chỉ khi còn giao dịch; danh mục hệ thống ẩn', () {
      final cats = [
        _cat('a_live', TransactionType.expense),
        Category(id: 'b_stopped_used', name: 'b_stopped_used', color: Colors.grey, type: TransactionType.expense, isActive: false),
        Category(id: 'c_stopped_empty', name: 'c_stopped_empty', color: Colors.grey, type: TransactionType.expense, isActive: false),
        _cat('vay_no', TransactionType.income),
      ];
      final txs = [_out('b_stopped_used', 1000, id: 'u')];
      final opts = explorerCategoryOptions(cats, txs, hiddenCategoryIds: _hidden);
      expect(opts.map((o) => o.id), ['a_live', 'b_stopped_used']);
      expect(opts.last.label, 'b_stopped_used (đã ngừng)');
      expect(opts.last.active, isFalse);
    });

    test('Danh mục hệ thống nâng cao: ẩn khi KHÔNG còn giao dịch dùng; còn lịch sử thì vẫn tìm lại được (nhóm "Nâng cao")', () {
      final cats = [_cat('a_live', TransactionType.expense), _cat('hoan_tien_thu_hoi', TransactionType.income), _cat('vay_no', TransactionType.income)];
      final txs = [_in('hoan_tien_thu_hoi', 1000)];
      final opts = explorerCategoryOptions(cats, txs, hiddenCategoryIds: _hidden);
      expect(opts.map((o) => o.id), ['a_live', 'hoan_tien_thu_hoi'], reason: 'vay_no không có giao dịch nên vẫn ẩn');
      expect(opts.last.groupLabel, 'Nâng cao');
    });

    test('Bộ chọn trạng thái: trạng thái ngừng chỉ hiện khi còn giao dịch dùng; độc lập với danh mục đã chọn', () {
      final txs = [_out('cho_di', 1000, id: 'u', statusId: 'st_cu')];
      final opts = explorerStatusOptions(_cats, txs);
      expect(opts.map((o) => o.id), containsAll(['st_chua', 'st_gui', 'st_cu', 'st_khac']));
      expect(explorerStatusOptions(_cats, const []).map((o) => o.id), isNot(contains('st_cu')));
      expect(opts.firstWhere((o) => o.id == 'st_cu').label, 'Cũ (đã ẩn) · cho_di');
    });

    test('hasNonDateFilter / advancedCount phản ánh đúng để hiện "Xoá bộ lọc"', () {
      expect(const TransactionFilter().hasNonDateFilter, isFalse);
      expect(const TransactionFilter(query: ' ').hasNonDateFilter, isFalse);
      expect(const TransactionFilter(memberId: 'vo').hasNonDateFilter, isTrue);
      expect(const TransactionFilter(sort: ExplorerSort([SortRule(SortKey.amount)])).hasNonDateFilter, isTrue);
      expect(const TransactionFilter(sort: ExplorerSort.defaultSort).hasNonDateFilter, isFalse);
      final f = const TransactionFilter(categoryIds: {'sinh_hoat'}, includeNoStatus: true);
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
      for (final id in ['hoan_tien_thu_hoi', 'vay_no', 'cho_vay']) {
        expect(categoryGroupOf(_byId[id]!, _hidden), isNull, reason: id);
      }
      // Lọc theo thành viên vẫn an toàn với dòng có đích là khoản vay.
      expect(_run(ledger, const TransactionFilter(memberId: 'vo')).count, greaterThanOrEqualTo(3));
    });
  });

  group('Thẻ tổng quan theo KỲ THỜI GIAN (không theo Danh mục/Trạng thái/Ghi chú)', () {
    // Vợ: doanh thu 10tr (15/08), 5tr (10/09); chi phí KD 1tr (11/09); chi tiêu 200k (12/09).
    // Chồng: doanh thu 2tr (20/09); chi tiêu 300k (20/09); chi phí KD 500k (20/09/2027).
    final ledger = [
      _in('hoc_phi', 10000000, to: 'vo', date: DateTime(2026, 8, 15)),
      _in('hoc_phi', 5000000, to: 'vo', date: DateTime(2026, 9, 10)),
      _out('luong_gv', 1000000, from: 'vo', date: DateTime(2026, 9, 11)),
      _out('sinh_hoat', 200000, from: 'vo', date: DateTime(2026, 9, 12)),
      _in('hoc_phi', 2000000, to: 'chong', date: DateTime(2026, 9, 20)),
      _out('sinh_hoat', 300000, from: 'chong', date: DateTime(2026, 9, 20)),
      _out('luong_gv', 500000, from: 'chong', date: DateTime(2027, 9, 20)),
    ];
    int net(String m, {DateTime? from, DateTime? to}) =>
        computeMemberNetIncome(m, ledger, _cats, from: from, to: to);
    int spend({DateTime? from, DateTime? to}) =>
        computeGroupedTotals(ledger, _cats, from: from, to: to).spending;

    test('Ngày: chỉ giao dịch đúng ngày đó', () {
      final d = DateTime(2026, 9, 20);
      expect(net('vo', from: d, to: d), 0);
      expect(net('chong', from: d, to: d), 2000000);
      expect(spend(from: d, to: d), 300000);
    });

    test('Tháng: đúng tháng, khớp kết quả cũ theo `month`', () {
      final from = DateTime(2026, 9, 1);
      final to = DateTime(2026, 9, 30);
      expect(net('vo', from: from, to: to), 5000000 - 1000000);
      expect(spend(from: from, to: to), 500000);
      expect(net('vo', from: from, to: to), computeMemberNetIncome('vo', ledger, _cats, month: DateTime(2026, 9)));
      expect(spend(from: from, to: to), computeGroupedTotals(ledger, _cats, month: DateTime(2026, 9)).spending);
    });

    test('Năm: cả năm (không lấn sang năm khác)', () {
      final from = DateTime(2026, 1, 1);
      final to = DateTime(2026, 12, 31);
      expect(net('vo', from: from, to: to), 10000000 + 5000000 - 1000000);
      expect(net('chong', from: from, to: to), 2000000, reason: 'chi phí KD 500k thuộc năm 2027');
      expect(spend(from: from, to: to), 500000);
    });

    test('Khoảng ngày (bao gồm 2 đầu) và Tất cả thời gian', () {
      expect(net('vo', from: DateTime(2026, 9, 10), to: DateTime(2026, 9, 11)), 4000000);
      expect(net('vo'), 10000000 + 5000000 - 1000000, reason: 'Tất cả: không giới hạn');
      expect(net('chong'), 2000000 - 500000);
      expect(spend(), 500000);
    });

    test('Không phụ thuộc bộ lọc Explorer: đổi Danh mục/Trạng thái/Ghi chú không đổi số tổng quan', () {
      final f = TransactionFilter(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30)).withCategories({'sinh_hoat'});
      // Explorer chỉ thấy Chi tiêu; số tổng quan của kỳ vẫn tính đủ Doanh thu/Chi phí KD.
      expect(_run(ledger, f).outflow, 500000);
      expect(net('vo', from: f.from, to: f.to), 4000000);
    });
  });

  group('Hiệu năng ~1.800 giao dịch (smoke)', () {
    test('V2 — kịch bản Excel đầy đủ: Năm 2026 + 5 danh mục + 5 trạng thái + tìm ghi chú + sắp xếp Ngày ↓ rồi Số tiền ↓', () {
      const sts = [
        Status(id: 'p1', categoryId: 'c1', name: 'A', sortOrder: 0),
        Status(id: 'p2', categoryId: 'c2', name: 'B', sortOrder: 0),
        Status(id: 'p3', categoryId: 'c3', name: 'C', sortOrder: 0),
        Status(id: 'p4', categoryId: 'c4', name: 'D', sortOrder: 0),
        Status(id: 'p5', categoryId: 'c5', name: 'E', sortOrder: 0),
      ];
      final cats = [
        for (var i = 1; i <= 6; i++)
          _cat('c$i', TransactionType.expense, statuses: i <= 5 ? [sts[i - 1]] : const []),
      ];
      final ledger = <Transaction>[
        for (var i = 0; i < 1900; i++)
          _out(
            'c${1 + i % 6}',
            1000 + (i * 37) % 900000,
            from: i.isEven ? 'vo' : 'chong',
            date: DateTime(2026, 1 + i % 12, 1 + i % 28),
            statusId: (i % 6) < 5 && i % 3 != 0 ? 'p${1 + i % 6}' : null,
            note: i % 4 == 0 ? 'Lương tháng $i' : 'chi $i',
          ),
      ];
      final f = TransactionFilter(from: DateTime(2026, 1, 1), to: DateTime(2026, 12, 31))
          .withCategories({'c1', 'c2', 'c3', 'c4', 'c5'})
          .withStatuses({'p1', 'p2', 'p3', 'p4', 'p5'}, includeNone: true)
          .withQuery('luong')
          .withSort(const ExplorerSort([SortRule(SortKey.date), SortRule(SortKey.amount)]));
      final sw = Stopwatch()..start();
      late ExplorerResult r;
      for (var i = 0; i < 5; i++) {
        r = exploreTransactions(ledger, cats, f);
      }
      sw.stop();
      // ignore: avoid_print
      print('V2: 5 lần lọc+sắp xếp 1.900 dòng = ${sw.elapsedMilliseconds}ms; ${r.count} dòng khớp');
      expect(r.count, greaterThan(0));
      expect(r.rows.every((t) => t.note.contains('Lương') && t.categoryId != 'c6'), isTrue);
      for (var i = 1; i < r.rows.length; i++) {
        final a = r.rows[i - 1];
        final b = r.rows[i];
        final da = DateTime(a.transactionDate.year, a.transactionDate.month, a.transactionDate.day);
        final db = DateTime(b.transactionDate.year, b.transactionDate.month, b.transactionDate.day);
        final byDate = da.compareTo(db);
        expect(byDate > 0 || (byDate == 0 && a.amountMinor >= b.amountMinor), isTrue);
      }
      expect(sw.elapsedMilliseconds, lessThan(2500));
    });

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
      final vo = _run(ledger, const TransactionFilter(memberId: 'vo'));
      final combo = _run(
        ledger,
        TransactionFilter(from: DateTime(2026, 3, 1), to: DateTime(2026, 6, 30))
            .withMember('vo')
            .withCategories({'sinh_hoat', 'luong_gv'})
            .withQuery('chợ')
            .withSort(ExplorerSort.defaultSort),
      );
      final search = _run(ledger, const TransactionFilter(query: 'chi 1'));
      sw.stop();

      expect(all.count, 1800);
      expect(vo.count, lessThan(all.count));
      expect(combo.rows.every((t) => t.note.contains('chợ') && involvesMember(t, 'vo')), isTrue);
      expect(search.count, greaterThan(0));
      expect(sw.elapsedMilliseconds, lessThan(1500), reason: '4 truy vấn trên 1.800 dòng phải rất nhanh (thường < 50ms)');
      // Sắp xếp mới nhất lên đầu.
      for (var i = 1; i < all.rows.length; i++) {
        expect(all.rows[i - 1].transactionDate.compareTo(all.rows[i].transactionDate) >= 0, isTrue);
      }
    });
  });
}
