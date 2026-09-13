import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/utils/id_generator.dart';

void main() {
  test(
    'sinh id không trùng kể cả khi gọi liên tiếp rất nhanh (double-tap)',
    () {
      final ids = List.generate(1000, (_) => IdGenerator.generate());
      expect(ids.toSet().length, 1000);
    },
  );
}
