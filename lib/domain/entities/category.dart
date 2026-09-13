import 'package:flutter/material.dart';

import 'category_kind.dart';
import 'family_member.dart';

/// Hạng mục là DỮ LIỆU do từng gia đình tự định nghĩa (đúng như
/// `families/{familyId}/categories/{categoryId}` trong spec.md) — không có
/// hạng mục nào được ưu tiên "đặc biệt" trong code.
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.color,
    required this.kind,
    this.statuses = const [],
    this.transferFrom,
    this.transferTo,
    this.isDefault = true,
  });

  final String id;
  final String name;
  final Color color;
  final CategoryKind kind;

  /// Danh sách các bước trạng thái do CHÍNH gia đình đặt ra cho hạng mục
  /// này, theo đúng thứ tự (vd Cho đi: ['Chưa chuẩn bị', 'Đã chuẩn bị', 'Đã
  /// gửi']). Rỗng nghĩa là hạng mục này không theo dõi trạng thái. Không có
  /// giới hạn cứng về số bước hay tên bước — gia đình khác có thể đặt 2
  /// bước, 5 bước, tên khác hẳn.
  final List<String> statuses;

  bool get hasStatus => statuses.isNotEmpty;

  /// Chỉ có ý nghĩa khi kind == transfer: ai bị trừ, ai được cộng.
  final FamilyMember? transferFrom;
  final FamilyMember? transferTo;

  final bool isDefault;

  String get initial => name.isEmpty ? '' : name.substring(0, 1).toUpperCase();
}
