import 'package:flutter/material.dart';

/// 1 "loại tài sản tiết kiệm" tự đặt — không còn cố định 2 loại "Hiện
/// tại"/"Ngân hàng" như bản trước. Gia đình tạo thêm bao nhiêu loại tuỳ ý:
/// Gửi ngân hàng, Vàng, Chứng khoán, Bất động sản... (`spec.md`/
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

/// Tài sản tiết kiệm HỆ THỐNG (ảo) — KHÔNG có dòng trong `SavingsAssetTypeRows`
/// nên không thể bị đổi tên/ngừng/xoá, và không cần migration. Chỉ là 1 id ổn
/// định dùng trong `savingsAssetRefId` của pool `memberSavingsAsset`; tên hiển
/// thị do lớp trình bày resolve qua [resolveSavingsAsset].
///
/// "Chưa phân bổ" = tiền đã để dành (rời khỏi Số dư khả dụng) nhưng người dùng
/// chưa chọn Vàng/Ngân hàng/Chứng khoán… — nạp tiết kiệm mặc định vào đây.
class SystemSavingsAssets {
  SystemSavingsAssets._();

  static const unallocatedId = 'savings_unallocated';

  static const unallocated = SavingsAssetType(
    id: unallocatedId,
    name: 'Chưa phân bổ',
    color: Color(0xFF8FA3B3),
  );

  static bool isSystem(String assetTypeId) => assetTypeId == unallocatedId;
}

/// Điểm resolve DUY NHẤT id → loại tài sản: id hệ thống trả về bản ảo, id
/// thường tra trong [dbTypes] (kể cả loại đã ngừng), không có → null. Mọi nơi
/// hiển thị tên loại tài sản phải đi qua đây (không rải `if (id == ...)`).
SavingsAssetType? resolveSavingsAsset(
  String assetTypeId,
  Iterable<SavingsAssetType> dbTypes,
) {
  if (SystemSavingsAssets.isSystem(assetTypeId)) {
    return SystemSavingsAssets.unallocated;
  }
  for (final a in dbTypes) {
    if (a.id == assetTypeId) return a;
  }
  return null;
}

