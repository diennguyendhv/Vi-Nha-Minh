import 'package:flutter/material.dart';

import '../../domain/entities/fund.dart';

/// Quỹ mặc định — hiện chỉ có Quỹ tiền ăn (Giai đoạn A, phase 13-14).
/// Cũng là dữ liệu seed, không phải logic hardcode — về sau gia đình có thể
/// tự tạo thêm quỹ khác (quỹ du lịch, hiếu hỉ...) qua cùng cơ chế.
class DefaultFunds {
  DefaultFunds._();

  static const anUongId = 'an_uong';

  static const anUong = Fund(
    id: anUongId,
    name: 'Quỹ tiền ăn',
    color: Color(0xFFC98A3E),
  );

  static const all = <Fund>[anUong];

  static Fund byId(String id) {
    return all.firstWhere(
      (f) => f.id == id,
      orElse: () => const Fund(id: '', name: '', color: Color(0xFF9A9D97)),
    );
  }
}
