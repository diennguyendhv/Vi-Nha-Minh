import 'dart:math';

/// ID mờ, ổn định, không mang ý nghĩa (UUID v4, 122 bit ngẫu nhiên từ CSPRNG) —
/// dùng cho `walletId` và cho `memberId` của các Wallet MỚI. KHÔNG suy ra từ email,
/// vai trò (Vợ/Chồng), thiết bị, số giao dịch hay số tiền; một khi sinh ra thì là
/// danh tính vĩnh viễn.
class OpaqueId {
  OpaqueId._();

  static final Random _secure = Random.secure();

  /// `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx` (chữ thường). [random] chỉ để test.
  static String generate({Random? random}) {
    final r = random ?? _secure;
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // version 4
    b[8] = (b[8] & 0x3f) | 0x80; // variant RFC 4122
    String h(int from, int to) => [
      for (var i = from; i < to; i++) b[i].toRadixString(16).padLeft(2, '0'),
    ].join();
    return '${h(0, 4)}-${h(4, 6)}-${h(6, 8)}-${h(8, 10)}-${h(10, 16)}';
  }

  static final RegExp _pattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  static bool isValid(String id) => _pattern.hasMatch(id);
}
