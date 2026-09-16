import 'package:flutter/material.dart';

/// 1 "loại tài sản tiết kiệm" tự đặt — không còn cố định 2 loại "Hiện
/// tại"/"Ngân hàng" như bản trước. Gia đình tạo thêm bao nhiêu loại tuỳ ý:
/// Chứng khoán, Bất động sản, Vàng, Ngân hàng ABC... (`spec.md`/
/// `docs/financial-core-v2.md` mục 9). Mỗi loại là 1 pool RIÊNG cho TỪNG
/// thành viên (khác `Fund` — dùng chung cả nhà) — xem `PoolKind.
/// memberSavingsAsset` và `savingsAssetRefId`.
class SavingsAssetType {
  const SavingsAssetType({
    required this.id,
    required this.name,
    required this.color,
    this.isActive = true,
  });

  final String id;
  final String name;
  final Color color;

  /// Soft delete — chỉ nên xoá khi mọi thành viên đều có số dư 0 ở loại
  /// này (giống nguyên tắc Fund mục 8), UI tự kiểm tra trước khi cho xoá.
  final bool isActive;

  SavingsAssetType copyWith({String? name, Color? color, bool? isActive}) {
    return SavingsAssetType(
      id: id,
      name: name ?? this.name,
      color: color ?? this.color,
      isActive: isActive ?? this.isActive,
    );
  }
}
