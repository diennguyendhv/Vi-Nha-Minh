import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/family_member.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/status.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/entities/transfer_kind.dart';
import 'package:vi_nha_minh/domain/usecases/compute_expense_breakdown.dart';
import 'package:vi_nha_minh/domain/usecases/compute_member_financials.dart';
import 'package:vi_nha_minh/domain/usecases/compute_net_income.dart';
import 'package:vi_nha_minh/domain/usecases/compute_status_breakdown.dart';
import 'package:vi_nha_minh/domain/usecases/compute_three_totals.dart';

int _seq = 0;

Transaction _income(String categoryId, int amount, {String memberRefId = 'vo'}) {
  _seq++;
  return Transaction(
    id: 'tx-$_seq',
    type: TransactionType.income,
    categoryId: categoryId,
    sourceKind: PoolKind.external,
    destinationKind: PoolKind.memberAvailable,
    destinationRefId: memberRefId,
    amountMinor: amount,
    transactionDate: DateTime(2026, 9, 1),
    createdAt: DateTime(2026, 9, 1),
    clientTxId: 'client-$_seq',
  );
}

Transaction _expense(
  String categoryId,
  int amount, {
  String memberRefId = 'vo',
  String? statusId,
}) {
  _seq++;
  return Transaction(
    id: 'tx-$_seq',
    type: TransactionType.expense,
    categoryId: categoryId,
    sourceKind: PoolKind.memberAvailable,
    sourceRefId: memberRefId,
    destinationKind: PoolKind.external,
    amountMinor: amount,
    statusId: statusId,
    transactionDate: DateTime(2026, 9, 1),
    createdAt: DateTime(2026, 9, 1),
    clientTxId: 'client-$_seq',
  );
}

Transaction _memberTransfer(int amount, {required String from, required String to}) {
  _seq++;
  return Transaction(
    id: 'tx-$_seq',
    type: TransactionType.transfer,
    transferKind: TransferKind.memberToMember,
    categoryId: 'chuyen_tien_thanh_vien',
    sourceKind: PoolKind.memberAvailable,
    sourceRefId: from,
    destinationKind: PoolKind.memberAvailable,
    destinationRefId: to,
    amountMinor: amount,
    transactionDate: DateTime(2026, 9, 1),
    createdAt: DateTime(2026, 9, 1),
    clientTxId: 'client-$_seq',
  );
}

const _choDi = Category(
  id: 'cho_di',
  name: 'Cho đi',
  color: Color(0xFF8A4FB0),
  type: TransactionType.expense,
  statsEnabled: true,
  statuses: [
    Status(id: 's1', categoryId: 'cho_di', name: 'Chưa chuẩn bị', sortOrder: 0),
    Status(id: 's2', categoryId: 'cho_di', name: 'Đã chuẩn bị', sortOrder: 1),
    Status(id: 's3', categoryId: 'cho_di', name: 'Đã gửi', sortOrder: 2),
  ],
);

const _sinhHoat = Category(
  id: 'sinh_hoat',
  name: 'Sinh hoạt',
  color: Color(0xFF3E6FB0),
  type: TransactionType.expense,
);

void main() {
  group('computeThreeTotals — 3 tổng tách biệt, Transfer không lẫn vào Income/Expense', () {
    test('tính đúng thu/chi/chuyển, bỏ qua category excludeFromTotals', () {
      const soDuBanDau = Category(
        id: 'so_du_ban_dau',
        name: 'Số dư ban đầu',
        color: Color(0xFF2F8F4F),
        type: TransactionType.income,
        excludeFromTotals: true,
      );
      const thuNhap = Category(
        id: 'thu_nhap',
        name: 'Thu nhập',
        color: Color(0xFF12805C),
        type: TransactionType.income,
      );

      final transactions = [
        _income('so_du_ban_dau', 5000000),
        _income('thu_nhap', 10000000),
        _expense('sinh_hoat', 3000000),
        _memberTransfer(2000000, from: 'chong', to: 'vo'),
      ];

      final totals = computeThreeTotals(transactions, [soDuBanDau, thuNhap, _sinhHoat]);

      expect(totals.totalIncome, 10000000);
      expect(totals.totalExpense, 3000000);
      expect(totals.totalTransfer, 2000000);
      expect(totals.balance, 7000000);
    });

    test('Test 16 — excludeFromTotals: availableBalance vẫn cộng đủ, totalIncome bỏ qua', () {
      const soDuBanDau = Category(
        id: 'so_du_ban_dau',
        name: 'Số dư ban đầu',
        color: Color(0xFF2F8F4F),
        type: TransactionType.income,
        excludeFromTotals: true,
      );
      const thuNhap = Category(
        id: 'thu_nhap',
        name: 'Lương',
        color: Color(0xFF12805C),
        type: TransactionType.income,
      );
      final transactions = [
        _income('so_du_ban_dau', 5000000),
        _income('thu_nhap', 10000000),
      ];

      final totals = computeThreeTotals(transactions, [soDuBanDau, thuNhap]);
      final voBalance = computeMemberFinancials(FamilyMember.vo, transactions).balance;

      expect(voBalance, 15000000);
      expect(totals.totalIncome, 10000000);
    });
  });

  group('computeExpenseBreakdown', () {
    test('gộp theo hạng mục, chỉ tính EXPENSE, sắp xếp giảm dần', () {
      final transactions = [
        _expense('sinh_hoat', 100000),
        _expense('sinh_hoat', 50000),
        _expense('dau_tu', 200000),
        _income('thu_nhap', 5000000),
        _memberTransfer(500000, from: 'vo', to: 'chong'),
      ];

      final breakdown = computeExpenseBreakdown(transactions);

      expect(breakdown.length, 2);
      expect(breakdown.first.categoryId, 'dau_tu');
      expect(breakdown.first.total, 200000);
      expect(breakdown.last.categoryId, 'sinh_hoat');
      expect(breakdown.last.total, 150000);
    });
  });

  group('computeMemberFinancials', () {
    test('số dư chỉ tính đúng pool của từng người, transfer đổi cả 2 bên', () {
      final transactions = [
        _income('thu_nhap', 10000000, memberRefId: 'chong'),
        _expense('sinh_hoat', 1000000, memberRefId: 'vo'),
        _memberTransfer(500000, from: 'chong', to: 'vo'),
      ];

      final vo = computeMemberFinancials(FamilyMember.vo, transactions);
      final chong = computeMemberFinancials(FamilyMember.chong, transactions);

      expect(vo.balance, -1000000 + 500000);
      expect(chong.balance, 10000000 - 500000);
    });
  });

  group('computeStatusBreakdown', () {
    test('gộp theo statusId, giao dịch chưa có statusId tính vào bước đầu tiên', () {
      final transactions = [
        _expense('cho_di', 100000, statusId: 's1'),
        _expense('cho_di', 50000),
        _expense('cho_di', 200000, statusId: 's2'),
        _expense('cho_di', 300000, statusId: 's3'),
      ];

      final breakdown = computeStatusBreakdown(transactions, _choDi);

      expect(breakdown.totals['s1'], 150000);
      expect(breakdown.totals['s2'], 200000);
      expect(breakdown.totals['s3'], 300000);
      expect(breakdown.total, 650000);
    });

    test('hạng mục không có statuses trả về breakdown rỗng', () {
      final breakdown = computeStatusBreakdown([], _sinhHoat);
      expect(breakdown.totals, isEmpty);
      expect(breakdown.total, 0);
    });
  });

  group('computeNetIncome — Test 18, mục 17', () {
    test('Thu nhập ròng = tổng thu − tổng chi liên kết (cả 2 status)', () {
      const traLuongGv = Category(
        id: 'tra_luong_gv',
        name: 'Trả lương giáo viên',
        color: Color(0xFF8FA3B3),
        type: TransactionType.expense,
        statsEnabled: true,
        statuses: [
          Status(id: 'chua_gui', categoryId: 'tra_luong_gv', name: 'Chưa gửi', sortOrder: 0),
          Status(id: 'da_gui', categoryId: 'tra_luong_gv', name: 'Đã gửi', sortOrder: 1),
        ],
      );
      const hocPhi = Category(
        id: 'hoc_phi',
        name: 'Học phí',
        color: Color(0xFF12805C),
        type: TransactionType.income,
        linkedExpenseCategoryId: 'tra_luong_gv',
      );

      final transactions = [
        _income('hoc_phi', 5000000),
        _expense('tra_luong_gv', 2000000, statusId: 'chua_gui'),
        _expense('tra_luong_gv', 1000000, statusId: 'da_gui'),
      ];

      final net = computeNetIncome(hocPhi, traLuongGv, transactions);
      expect(net, 5000000 - 3000000);
    });

    test('trả về null khi category Thu chưa liên kết', () {
      const thuNhap = Category(
        id: 'thu_nhap',
        name: 'Thu nhập',
        color: Color(0xFF12805C),
        type: TransactionType.income,
      );
      expect(computeNetIncome(thuNhap, null, []), isNull);
    });
  });
}
