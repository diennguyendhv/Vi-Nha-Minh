import 'package:flutter/material.dart';

import '../../domain/entities/fund.dart';

/// Quỹ seed mặc định — chỉ dùng để SEED database rỗng lúc khởi tạo (xem
/// `DefaultCategories`). Gia đình tự tạo thêm quỹ khác qua UI, không giới
/// hạn 1 quỹ như tên file gợi ý.
class DefaultFunds {
  DefaultFunds._();

  static const anUongId = 'an_uong';

  static const anUong = Fund(
    id: anUongId,
    name: 'Quỹ tiền ăn',
    color: Color(0xFFC98A3E),
  );

  static const all = <Fund>[anUong];
}
