import 'dart:async';

import '../../domain/entities/fund_entry.dart';
import '../../domain/repositories/fund_repository.dart';

/// In-memory stand-in for the Firestore-backed repository (Phase 1).
class MockFundRepository implements FundRepository {
  MockFundRepository() {
    _entries.addAll(_seed);
  }

  final _controller = StreamController<List<FundEntry>>.broadcast();
  final List<FundEntry> _entries = [];

  static final _seed = <FundEntry>[
    FundEntry(
      id: 'f1',
      fundId: 'an_uong',
      kind: FundEntryKind.topUp,
      amount: 2000000,
      date: DateTime(2026, 9, 1),
      note: 'Nạp quỹ tiền ăn tháng 9',
    ),
    FundEntry(
      id: 'f2',
      fundId: 'an_uong',
      kind: FundEntryKind.purchase,
      amount: 180000,
      date: DateTime(2026, 9, 2),
      note: 'Đi chợ',
    ),
    FundEntry(
      id: 'f3',
      fundId: 'an_uong',
      kind: FundEntryKind.purchase,
      amount: 95000,
      date: DateTime(2026, 9, 12),
      note: 'Ăn sáng',
    ),
    FundEntry(
      id: 'f4',
      fundId: 'an_uong',
      kind: FundEntryKind.purchase,
      amount: 116000,
      date: DateTime(2026, 9, 3),
      note: 'Bánh kẹo',
    ),
  ];

  @override
  Stream<List<FundEntry>> watchEntries(String fundId) async* {
    yield List.unmodifiable(_entries.where((e) => e.fundId == fundId));
    yield* _controller.stream.map(
      (all) => all.where((e) => e.fundId == fundId).toList(),
    );
  }

  @override
  Future<void> addEntry(FundEntry entry) async {
    _entries.add(entry);
    _controller.add(List.unmodifiable(_entries));
  }
}
