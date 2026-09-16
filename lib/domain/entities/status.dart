/// 1 bước tiến độ con của [Category] (`docs/financial-core-v2.md` mục 11) —
/// nhãn tiến độ cam kết cá nhân (vd Cho đi: Chưa chuẩn bị → Đã chuẩn bị → Đã
/// gửi), KHÔNG bao giờ ảnh hưởng balance (mục 12). Tên và thứ tự do chính
/// gia đình tự đặt qua màn "Danh mục — Chỉnh sửa", không giới hạn số bước.
class Status {
  const Status({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.sortOrder,
    this.isActive = true,
  });

  final String id;
  final String categoryId;
  final String name;
  final int sortOrder;
  final bool isActive;

  Status copyWith({String? name, int? sortOrder, bool? isActive}) {
    return Status(
      id: id,
      categoryId: categoryId,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
    );
  }
}
