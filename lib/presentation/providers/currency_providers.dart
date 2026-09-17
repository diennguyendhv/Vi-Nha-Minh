import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/currency/currency_context.dart';
import '../../application/currency/fixed_currency_context.dart';

/// Nguồn `CurrencyContext` cho toàn app — Phase 5 mục 6.
///
/// Giai đoạn A (Layer 1, Phase 4.1): luôn `FixedCurrencyContext` — trả cố
/// định `'VND'` (default configuration cho Giai đoạn A Việt Nam, không phải
/// business assumption trong Use Case — literal `'VND'` chỉ nằm ở
/// `FixedCurrencyContext`, xem `docs` Phase 4.1).
///
/// **Layer 2 (tương lai, KHÔNG làm ở Phase 5):** khi base currency trở
/// thành setting mutable/persisted, chỉ cần đổi implementation được trả về
/// ở đây (vd đọc từ 1 bảng settings) — không cần sửa
/// `CreateTransactionCommandFactory`/`AddTransactionUseCase`/bất kỳ
/// provider nào phụ thuộc `currencyContextProvider`.
final currencyContextProvider = Provider<CurrencyContext>((ref) {
  return const FixedCurrencyContext();
});
