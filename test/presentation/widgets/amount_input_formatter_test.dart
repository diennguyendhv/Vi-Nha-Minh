import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/presentation/widgets/amount_input_formatter.dart';

void main() {
  const formatter = AmountInputFormatter();

  String run(String text, {String old = ''}) => formatter
      .formatEditUpdate(
        TextEditingValue(text: old),
        TextEditingValue(text: text),
      )
      .text;

  test('chỉ giữ chữ số', () {
    expect(run('1 200.000,5-'), '12000005');
    expect(run('abc'), '');
    expect(run(' '), '');
  });

  test('bỏ số 0 đứng đầu nhưng giữ "0" đơn', () {
    expect(run('0'), '0');
    expect(run('000'), '0');
    expect(run('0012'), '12');
    expect(run('100'), '100');
  });

  test('vượt 9 chữ số → giữ giá trị cũ', () {
    expect(run('1234567890', old: '123456789'), '123456789');
    expect(run('123456789'), '123456789');
  });

  test('con trỏ luôn ở cuối', () {
    final v = formatter.formatEditUpdate(
      const TextEditingValue(text: ''),
      const TextEditingValue(text: '12a'),
    );
    expect(v.selection.baseOffset, 2);
  });
}
