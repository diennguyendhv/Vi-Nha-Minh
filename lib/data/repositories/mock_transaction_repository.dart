import 'dart:async';

import '../../domain/entities/transaction.dart';
import '../../domain/entities/transaction_type.dart';
import '../../domain/repositories/transaction_repository.dart';

/// In-memory stand-in for the Firestore-backed repository (Phase 1).
///
/// Seeded with the same demo data used in the design prototype so the UI
/// can be built and reviewed before a real Firebase project exists.
class MockTransactionRepository implements TransactionRepository {
  MockTransactionRepository() {
    _transactions.addAll(_seed);
  }

  final _controller = StreamController<List<Transaction>>.broadcast();
  final List<Transaction> _transactions = [];

  static final _seed = <Transaction>[
    Transaction(
      id: '1',
      type: TransactionType.income,
      categoryId: 'luong',
      amount: 15000000,
      date: DateTime(2026, 9, 1),
      note: 'Lương tháng 9',
      spenderName: 'Chồng',
    ),
    Transaction(
      id: '2',
      type: TransactionType.expense,
      categoryId: 'sinhhoat',
      amount: 1500000,
      date: DateTime(2026, 9, 2),
      note: 'Tiền nhà tháng 9',
      spenderName: 'Vợ',
    ),
    Transaction(
      id: '3',
      type: TransactionType.expense,
      categoryId: 'anuong',
      amount: 180000,
      date: DateTime(2026, 9, 2),
      note: 'Đi chợ',
      spenderName: 'Vợ',
    ),
    Transaction(
      id: '4',
      type: TransactionType.expense,
      categoryId: 'danghien',
      amount: 1500000,
      date: DateTime(2026, 9, 3),
      note: 'Dâng hiến tháng 9',
      spenderName: 'Chồng',
    ),
    Transaction(
      id: '5',
      type: TransactionType.expense,
      categoryId: 'dichuyen',
      amount: 250000,
      date: DateTime(2026, 9, 5),
      note: 'Xăng xe',
      spenderName: 'Chồng',
    ),
    Transaction(
      id: '6',
      type: TransactionType.expense,
      categoryId: 'tuthuong',
      amount: 120000,
      date: DateTime(2026, 9, 7),
      note: 'Cà phê cuối tuần',
      spenderName: 'Vợ',
    ),
    Transaction(
      id: '7',
      type: TransactionType.expense,
      categoryId: 'chodi',
      amount: 200000,
      date: DateTime(2026, 9, 10),
      note: 'Ủng hộ quỹ lớp',
      spenderName: 'Vợ',
    ),
    Transaction(
      id: '8',
      type: TransactionType.income,
      categoryId: 'thuong',
      amount: 2000000,
      date: DateTime(2026, 9, 11),
      note: 'Thưởng dự án',
      spenderName: 'Vợ',
    ),
    Transaction(
      id: '9',
      type: TransactionType.expense,
      categoryId: 'anuong',
      amount: 95000,
      date: DateTime(2026, 9, 12),
      note: 'Ăn sáng',
      spenderName: 'Chồng',
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
}
