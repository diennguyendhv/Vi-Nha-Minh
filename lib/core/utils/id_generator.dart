import 'dart:math';

/// Sinh id duy nhất cho bản ghi tạo trên máy (giao dịch, khoản quỹ...).
/// Ghép giờ hệ thống (micro giây) với số ngẫu nhiên để tránh trùng khi
/// người dùng bấm Lưu 2 lần liên tiếp rất nhanh (double-tap) — chỉ dùng
/// timestamp đơn thuần không đủ an toàn cho trường hợp đó.
class IdGenerator {
  IdGenerator._();

  static final _random = Random();

  static String generate() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final rand = _random.nextInt(1 << 32);
    return '$micros-$rand';
  }
}
