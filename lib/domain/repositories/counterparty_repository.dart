import '../entities/counterparty.dart';

/// Phase 8.7 — bên ngoài gia đình liên quan Cho vay/Đi vay. CRUD thuần,
/// cùng convention `FundRepository`.
abstract class CounterpartyRepository {
  Stream<List<Counterparty>> watchCounterparties();

  Future<void> addCounterparty(Counterparty counterparty);

  Future<void> updateCounterparty(Counterparty counterparty);

  /// Soft delete — ném [CounterpartyHasOpenObligationsException] nếu còn
  /// `Obligation` đang mở (outstanding > 0) tham chiếu tới counterparty
  /// này. Caller (Application/Presentation) tự đọc `Obligation`s + tính
  /// `computeObligationSummary` để kiểm tra trước khi gọi — giống pattern
  /// `FundRepository.softDeleteFund` cần `TransactionRepository` để tính
  /// `balance`.
  Future<void> softDeleteCounterparty(String counterpartyId);
}
