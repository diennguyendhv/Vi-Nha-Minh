import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/application/currency/fixed_currency_context.dart';

void main() {
  group('FixedCurrencyContext (mục 12)', () {
    test('constructor mặc định trả VND', () async {
      final context = FixedCurrencyContext();
      expect(await context.getBaseCurrencyCode(), 'VND');
    });

    test('trả đúng USD khi cấu hình USD', () async {
      final context = FixedCurrencyContext('USD');
      expect(await context.getBaseCurrencyCode(), 'USD');
    });

    test('trả đúng JPY khi cấu hình JPY — không giả định 2 chữ số thập phân', () async {
      // JPY có 0 chữ số thập phân trong thực tế sử dụng — FixedCurrencyContext
      // chỉ trả stable currency code, không liên quan gì tới decimal digits
      // (đúng mục 12: "Không hard-code assumption rằng mọi currency đều có
      // 2 decimal digits" — ở tầng này đơn giản vì nó không hề biết/quan tâm
      // decimal digits, chỉ là 1 chuỗi mã currency).
      final context = FixedCurrencyContext('JPY');
      expect(await context.getBaseCurrencyCode(), 'JPY');
    });

    test('trả đúng liên tục nhiều lần gọi (stateless, không đổi giữa các lần đọc)', () async {
      final context = FixedCurrencyContext('EUR');
      expect(await context.getBaseCurrencyCode(), 'EUR');
      expect(await context.getBaseCurrencyCode(), 'EUR');
    });
  });
}
