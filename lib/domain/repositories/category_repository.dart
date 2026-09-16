import '../entities/category.dart';

/// Danh mục là DỮ LIỆU do gia đình tự quản lý (`CLAUDE.md` mục 9) — CRUD
/// đầy đủ ngay từ Giai đoạn A, không đợi tới Phase Premium. Danh mục
/// `type == transfer` là hệ thống, không cho thêm/xoá qua repository này
/// (chỉ seed sẵn lúc khởi tạo DB).
abstract class CategoryRepository {
  /// Kèm sẵn `statuses` đã sắp theo `sortOrder` cho mỗi category.
  Stream<List<Category>> watchCategories();

  Future<void> addCategory(Category category);

  /// Cập nhật thông tin category (không đụng `statuses` — dùng
  /// `StatusRepository` cho việc đó).
  Future<void> updateCategory(Category category);

  /// Soft delete (`isActive = false`) — không đổi bất kỳ số dư nào, giao
  /// dịch cũ vẫn hiển thị đúng tên/màu.
  Future<void> softDeleteCategory(String categoryId);
}
