import 'package:intl/intl.dart';

class Formatters {
  Formatters._();

  static final _numberFormat = NumberFormat.decimalPattern('vi_VN');

  static String amount(num value) => '${_numberFormat.format(value)} đ';

  static String dayMonth(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
}
