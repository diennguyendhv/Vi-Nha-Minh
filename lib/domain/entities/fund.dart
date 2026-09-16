import 'package:flutter/material.dart';

/// 1 "pool" tiền dạng quỹ (`docs/financial-core-v2.md` mục 8) — vd Quỹ tiền
/// ăn, Quỹ sinh hoạt. Tạo được nhiều quỹ tự đặt tên, không còn 1 quỹ cố
/// định như V1.
///
/// KHÔNG cache `balance` trên entity này — số dư luôn tính động từ toàn bộ
/// `Transaction` chưa bị hoàn tác có `sourceRefId`/`destinationRefId ==
/// id` (đúng Invariant 10, xem `computePoolBalance`).
class Fund {
  const Fund({
    required this.id,
    required this.name,
    required this.color,
    this.isActive = true,
  });

  final String id;
  final String name;
  final Color color;

  /// Soft delete — chỉ được phép khi balance == 0 (mục 8), lịch sử giao
  /// dịch cũ vẫn hiển thị đúng tên quỹ.
  final bool isActive;

  Fund copyWith({String? name, Color? color, bool? isActive}) {
    return Fund(
      id: id,
      name: name ?? this.name,
      color: color ?? this.color,
      isActive: isActive ?? this.isActive,
    );
  }
}
