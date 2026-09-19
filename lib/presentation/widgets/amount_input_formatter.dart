import 'package:flutter/services.dart';

/// Formatter cho ô nhập số tiền dùng bàn phím số của hệ điều hành.
///
/// VND lưu bằng số nguyên (minor units) nên chỉ nhận chữ số: mọi ký tự khác
/// (khoảng trắng, dấu chấm/phẩy/trừ của bàn phím số, chữ dán vào) bị loại.
/// Số 0 đứng đầu bị bỏ ("007" → "7"), tối đa [maxDigits] chữ số. KHÔNG chèn
/// dấu phân cách nghìn trong lúc gõ — tránh nhảy con trỏ; định dạng hiển thị
/// thân thiện nằm ở dòng xem trước riêng.
class AmountInputFormatter extends TextInputFormatter {
  const AmountInputFormatter({this.maxDigits = 9});

  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 1) {
      digits = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    }
    if (digits.length > maxDigits) return oldValue;
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}
