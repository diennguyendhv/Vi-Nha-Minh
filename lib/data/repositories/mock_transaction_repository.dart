import 'dart:async';

import '../../domain/entities/family_member.dart';
import '../../domain/entities/savings_destination.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';

/// In-memory stand-in for the Firestore-backed repository (Phase 1).
///
/// Dữ liệu mẫu phỏng theo đúng sheet "Quản lý tài chính 2026" thật (hạng
/// mục, người tiêu, trạng thái) để dựng UI trước khi có Firebase project.
class MockTransactionRepository implements TransactionRepository {
  MockTransactionRepository() {
    _transactions.addAll(_seed);
  }

  final _controller = StreamController<List<Transaction>>.broadcast();
  final List<Transaction> _transactions = [];

  static final _seed = <Transaction>[
    Transaction(
      id: '1',
      categoryId: 'thu_nhap',
      amount: 15000000,
      date: DateTime(2026, 9, 1),
      spender: FamilyMember.chong,
      note: 'Lương tháng 9',
    ),
    Transaction(
      id: '2',
      categoryId: 'sinh_hoat',
      amount: 1500000,
      date: DateTime(2026, 9, 2),
      spender: FamilyMember.vo,
      note: 'Tiền nhà tháng 9',
    ),
    Transaction(
      id: '3',
      categoryId: 'dang_hien',
      amount: 1500000,
      date: DateTime(2026, 9, 3),
      spender: FamilyMember.chong,
      note: 'Dâng hiến tháng 9',
      status: 'Đã dâng',
    ),
    Transaction(
      id: '4',
      categoryId: 'dau_tu',
      amount: 250000,
      date: DateTime(2026, 9, 5),
      spender: FamilyMember.chong,
      note: 'Sách + vở',
    ),
    Transaction(
      id: '5',
      categoryId: 'tu_thuong',
      amount: 120000,
      date: DateTime(2026, 9, 7),
      spender: FamilyMember.vo,
      note: 'Cà phê cuối tuần',
    ),
    Transaction(
      id: '6',
      categoryId: 'cho_di',
      amount: 200000,
      date: DateTime(2026, 9, 10),
      spender: FamilyMember.vo,
      note: 'Ủng hộ quỹ lớp',
      status: 'Đã chuẩn bị',
    ),
    Transaction(
      id: '7',
      categoryId: 'cho_di',
      amount: 130000,
      date: DateTime(2026, 9, 10),
      spender: FamilyMember.chong,
      note: 'ctps sb tuần 4',
      status: 'Chưa chuẩn bị',
    ),
    Transaction(
      id: '8',
      categoryId: 'thu_nhap',
      amount: 2000000,
      date: DateTime(2026, 9, 11),
      spender: FamilyMember.vo,
      note: 'Thưởng dự án',
    ),
    Transaction(
      id: '9',
      categoryId: 'tiet_kiem',
      amount: 850000,
      date: DateTime(2026, 9, 3),
      spender: FamilyMember.chong,
      savingsDestination: SavingsDestination.onHand,
    ),
    Transaction(
      id: '10',
      categoryId: 'tiet_kiem',
      amount: 500000,
      date: DateTime(2026, 9, 13),
      spender: FamilyMember.vo,
      note: 'Gửi tiết kiệm ngân hàng',
      savingsDestination: SavingsDestination.bank,
    ),
    Transaction(
      id: '11',
      categoryId: 'chong_dua_vo',
      amount: 500000,
      date: DateTime(2026, 9, 8),
      spender: FamilyMember.chong,
      note: 'Đưa vợ tiêu tuần này',
    ),
  ];

  @override
  Stream<List<Transaction>> watchTransactions() async* {
    // Phát ngay ảnh chụp hiện tại rồi mới nối vào stream cập nhật, tránh phụ
    // thuộc thời điểm subscribe của broadcast controller (sự kiện phát trước
    // khi có listener sẽ bị mất).
    yield List.unmodifiable(_transactions);
    yield* _controller.stream;
  }

  @override
  Future<void> addTransaction(Transaction transaction) async {
    _transactions.add(transaction);
    _controller.add(List.unmodifiable(_transactions));
  }

  @override
  Future<void> updateTransaction(Transaction transaction) async {
    final index = _transactions.indexWhere((t) => t.id == transaction.id);
    if (index == -1) return;
    _transactions[index] = transaction;
    _controller.add(List.unmodifiable(_transactions));
  }

  @override
  Future<void> deleteTransaction(String id) async {
    _transactions.removeWhere((t) => t.id == id);
    _controller.add(List.unmodifiable(_transactions));
  }
}
