import 'currency_context.dart';

/// Implementation Giai đoạn A (Layer 1, Phase 4.1) — trả về đúng 1 giá trị
/// cố định, không đọc bất kỳ storage nào. `'VND'` ở đây là **INITIAL/DEFAULT
/// CONFIGURATION cho Giai đoạn A Việt Nam** (dữ liệu cấu hình, có thể thay
/// bằng instance `FixedCurrencyContext('USD')` khác cho gia đình khác) —
/// KHÔNG phải business assumption cứng trong Application code: literal
/// `'VND'` không xuất hiện ở `AddTransactionUseCase`/
/// `CreateTransactionCommandFactory`, chỉ ở đúng 1 chỗ cấu hình này.
///
/// **Layer 2 (tương lai, KHÔNG làm ở Phase 4.1):** khi base currency trở
/// thành setting mutable/persisted, thay `FixedCurrencyContext` bằng 1
/// implementation đọc từ storage thật — `CreateTransactionCommandFactory`
/// và `AddTransactionUseCase` không cần sửa gì (chỉ đổi instance được
/// inject).
class FixedCurrencyContext implements CurrencyContext {
  const FixedCurrencyContext([this._baseCurrencyCode = 'VND']);

  final String _baseCurrencyCode;

  @override
  Future<String> getBaseCurrencyCode() async => _baseCurrencyCode;
}
