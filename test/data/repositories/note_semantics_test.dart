import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/repositories/local_category_repository.dart';
import 'package:vi_nha_minh/data/repositories/local_transaction_repository.dart';
import 'package:vi_nha_minh/domain/engine/financial_engine.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart' as domain;
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/usecases/compute_three_totals.dart';

/// Ghi chú (Note) trên DB thật (Drift in-memory, không widget). Note CHỈ là
/// mô tả: lưu/bền/sửa/correction đúng, KHÔNG đổi Income/Expense/Total Assets
/// và KHÔNG bao giờ được parse để suy luận ý nghĩa tài chính.
void main() {
  late AppDatabase db;
  late LocalTransactionRepository repo;
  late LocalCategoryRepository categories;
  var seq = 0;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LocalTransactionRepository(db);
    categories = LocalCategoryRepository(db);
    seq = 0;
  });

  tearDown(() async => db.close());

  domain.Transaction income(int amount, String note) {
    final n = seq++;
    return domain.Transaction(
      id: 'inc-$n',
      type: TransactionType.income,
      categoryId: 'thu_nhap',
      sourceKind: PoolKind.external,
      destinationKind: PoolKind.memberAvailable,
      destinationRefId: 'vo',
      amountMinor: amount,
      note: note,
      transactionDate: DateTime(2026, 9, 5),
      createdAt: DateTime(2026, 9, 5).add(Duration(seconds: n)),
      clientTxId: 'c-$n',
    );
  }

  domain.Transaction expense(int amount, String note, {String category = 'chi_phi_kinh_doanh', String? id}) {
    final n = seq++;
    return domain.Transaction(
      id: id ?? 'exp-$n',
      type: TransactionType.expense,
      categoryId: category,
      sourceKind: PoolKind.memberAvailable,
      sourceRefId: 'vo',
      destinationKind: PoolKind.external,
      amountMinor: amount,
      note: note,
      transactionDate: DateTime(2026, 9, 6),
      createdAt: DateTime(2026, 9, 6).add(Duration(seconds: n)),
      clientTxId: 'c-$n',
    );
  }

  Future<({int income, int expense, int totalAssets, int rows})> summary() async {
    final all = await repo.watchTransactions().first;
    final cats = await categories.watchCategories().first;
    final t = computeThreeTotals(all, cats, month: DateTime(2026, 9));
    return (
      income: t.totalIncome,
      expense: t.totalExpense,
      totalAssets: computeAllPoolBalances(all).values.fold<int>(0, (s, v) => s + v),
      rows: (await db.select(db.transactionRows).get()).length,
    );
  }

  Future<String> noteOf(String id) async =>
      (await (db.select(db.transactionRows)..where((r) => r.id.equals(id))).getSingle()).note;

  test('Seed: "Chi phí kinh doanh" là Expense bình thường, chỉ 1 bản, không status/link/loại trừ', () async {
    final rows = await db.select(db.categoryRows).get();
    final matches = rows.where((r) => r.id == 'chi_phi_kinh_doanh').toList();
    expect(matches, hasLength(1), reason: 'không sinh bản trùng');
    final c = matches.single;
    expect(c.name, 'Chi phí kinh doanh');
    expect(c.type, 'expense');
    expect(c.excludeFromTotals, isFalse);
    expect(c.statsEnabled, isFalse);
    expect(c.linkedExpenseCategoryId, isNull);
    expect(rows.map((r) => r.id).toSet(), hasLength(rows.length), reason: 'không trùng id nào');
    final statuses = await (db.select(db.statusRows)..where((r) => r.categoryId.equals('chi_phi_kinh_doanh'))).get();
    expect(statuses, isEmpty);
  });

  test('Kịch bản thật: Thu 2.000.000 (HP), Chi phí kinh doanh 700k (lương) + 200k (quảng cáo) → Thu 2tr, Chi 900k, Total +1,1tr', () async {
    await repo.addTransaction(income(2000000, 'HP lớp Excel'));
    await repo.addTransaction(expense(700000, 'Trả lương giáo viên'));
    await repo.addTransaction(expense(200000, 'Quảng cáo'));

    final s = await summary();
    expect(s.income, 2000000);
    expect(s.expense, 900000);
    expect(s.totalAssets, 1100000);
  });

  test('Note tự do lưu đúng và BỀN: tạo repository mới trên cùng DB (mô phỏng mở lại app) vẫn thấy note', () async {
    await repo.addTransaction(income(1000000, 'HP chị Lam'));
    await repo.addTransaction(expense(200000, 'Quảng cáo Facebook', id: 'fb'));

    final reopened = LocalTransactionRepository(db);
    final all = await reopened.watchTransactions().first;
    expect(all.firstWhere((t) => t.id == 'fb').note, 'Quảng cáo Facebook');
    expect(all.firstWhere((t) => t.type == TransactionType.income).note, 'HP chị Lam');
    expect(await noteOf('fb'), 'Quảng cáo Facebook');
  });

  test('Sửa note: cập nhật tại chỗ, không sinh giao dịch, không đổi số dư/Thu/Chi (không double-count)', () async {
    await repo.addTransaction(income(2000000, 'HP lớp Excel'));
    await repo.addTransaction(expense(200000, 'Quảng cáo', id: 'ads'));
    final before = await summary();

    await repo.updateTransaction('ads', note: 'Quảng cáo Facebook tháng 9');

    final after = await summary();
    expect(await noteOf('ads'), 'Quảng cáo Facebook tháng 9');
    expect(after.rows, before.rows, reason: 'không sinh giao dịch mới');
    expect(after.income, before.income);
    expect(after.expense, before.expense);
    expect(after.totalAssets, before.totalAssets);
  });

  test('Sửa số tiền + note: dòng cũ được THAY bằng dòng mới mang note mới, chỉ tính 1 lần, không lịch sử ẩn', () async {
    await repo.addTransaction(income(2000000, 'HP lớp Excel'));
    await repo.addTransaction(expense(200000, 'Quảng cáo', id: 'ads'));

    await repo.updateTransaction('ads', amountMinor: 250000, note: 'Quảng cáo Facebook tháng 9');

    final all = await repo.watchTransactions().first;
    expect(all.any((t) => t.id == 'ads'), isFalse, reason: 'dòng cũ mất hẳn');
    final replacement = all.firstWhere((t) => t.type == TransactionType.expense);
    expect(replacement.note, 'Quảng cáo Facebook tháng 9');
    expect(replacement.amountMinor, 250000);
    expect(all.length, 2);

    final s = await summary();
    expect(s.expense, 250000, reason: 'chỉ bản mới được tính, không phải 200k + 250k');
    expect(s.totalAssets, 2000000 - 250000);
  });

  test('Sửa chỉ đổi số tiền (không truyền note): note cũ được giữ nguyên ở dòng mới', () async {
    await repo.addTransaction(income(2000000, 'HP'));
    await repo.addTransaction(expense(200000, 'Bảo hành máy', id: 'fix'));

    await repo.updateTransaction('fix', amountMinor: 300000);

    final all = await repo.watchTransactions().first;
    expect(all.firstWhere((t) => t.type == TransactionType.expense).note, 'Bảo hành máy');
  });

  test('Note KHÔNG được parse: cùng số tiền/hạng mục, note khác hoàn toàn (hoặc rỗng) → tài chính y hệt', () async {
    Future<({int income, int expense, int totalAssets, int rows})> run(List<String> notes) async {
      final d = AppDatabase.forTesting(NativeDatabase.memory());
      final r = LocalTransactionRepository(d);
      final c = LocalCategoryRepository(d);
      await r.addTransaction(income(2000000, notes[0]));
      await r.addTransaction(expense(700000, notes[1]));
      await r.addTransaction(expense(200000, notes[2], category: 'sinh_hoat'));
      final all = await r.watchTransactions().first;
      final cats = await c.watchCategories().first;
      final t = computeThreeTotals(all, cats, month: DateTime(2026, 9));
      final result = (
        income: t.totalIncome,
        expense: t.totalExpense,
        totalAssets: computeAllPoolBalances(all).values.fold<int>(0, (s, v) => s + v),
        rows: all.length,
      );
      await d.close();
      return result;
    }

    final meaningful = await run(['HP chị Lam', 'Trả lương giáo viên', 'Lợi nhuận kinh doanh']);
    final empty = await run(['', '', '']);
    final misleading = await run(['Số dư ban đầu', 'Hoàn tiền / Thu hồi', 'Đi vay 5 triệu']);
    expect(meaningful, empty);
    expect(misleading, empty);
    expect(empty.income, 2000000);
    expect(empty.expense, 900000);
  });

  test('Hoàn tác giao dịch có note: dòng đảo ngược không làm đổi tổng, note gốc còn nguyên', () async {
    await repo.addTransaction(income(2000000, 'HP lớp Excel'));
    await repo.addTransaction(expense(200000, 'Quảng cáo', id: 'ads'));

    await repo.reverseTransaction('ads');

    expect(await noteOf('ads'), 'Quảng cáo');
    final s = await summary();
    expect(s.expense, 0);
    expect(s.totalAssets, 2000000);
  });
}
