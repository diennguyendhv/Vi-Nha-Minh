import '../entities/fund_entry.dart';

abstract class FundRepository {
  Stream<List<FundEntry>> watchEntries(String fundId);

  Future<void> addEntry(FundEntry entry);
}
