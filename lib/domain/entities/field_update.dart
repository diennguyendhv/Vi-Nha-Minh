/// Cập nhật 1 field CÓ THỂ null của bản ghi, phân biệt rõ 3 ý định (không dùng
/// `null` cho cả "không đổi" lẫn "xóa"):
///
///  - tham số `null` (không truyền)  → KHÔNG ĐỔI field;
///  - [FieldUpdate.set]              → đặt field = giá trị cụ thể;
///  - [FieldUpdate.clear]            → đặt field = `null`.
///
/// Chỉ dùng cho field thật sự nullable (hiện chỉ `statusId`). Field không-null
/// (số tiền, danh mục, ghi chú, ngày, thành viên) vẫn dùng `T?` với `null` =
/// không đổi — không có ý nghĩa "xóa" nào bị lẫn.
class FieldUpdate<T extends Object> {
  const FieldUpdate.set(T this.value);
  const FieldUpdate.clear() : value = null;

  /// Giá trị mới; `null` khi là [FieldUpdate.clear].
  final T? value;

  bool get isClear => value == null;

  @override
  bool operator ==(Object other) =>
      other is FieldUpdate<T> && other.value == value;

  @override
  int get hashCode => Object.hash(FieldUpdate, value);

  @override
  String toString() => isClear ? 'FieldUpdate.clear()' : 'FieldUpdate.set($value)';
}
