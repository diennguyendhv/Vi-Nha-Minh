/// Nguồn "base currency" của current family/book — Phase 4.1.
///
/// Đặt trong `lib/application/`, KHÔNG đặt trong `lib/domain/`: đây là
/// application context của gia đình đang mở app, không phải business rule
/// — Financial Core không cần và không được biết current family đang dùng
/// currency nào (`docs/global-readiness-audit.md` mục 2/9).
///
/// Contract async ngay từ đầu vì implementation tương lai (Layer 2 — xem
/// `FixedCurrencyContext`) sẽ đọc từ persistent storage/DB, vốn dĩ bất
/// đồng bộ — tránh phải đổi chữ ký khi nâng cấp.
///
/// **Chỉ dùng ở COMMAND CREATION lifecycle** (`CreateTransactionCommandFactory`),
/// KHÔNG dùng ở execution-attempt lifecycle (`AddTransactionUseCase`) — xem
/// doc-comment của 2 class đó để hiểu vì sao tách biệt 2 thời điểm này là
/// bắt buộc cho retry-safety (Phase 4.1 mục 2/7/8).
abstract interface class CurrencyContext {
  Future<String> getBaseCurrencyCode();
}
