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

  /// Id các danh mục ĐÃ NGỪNG SỬ DỤNG và an toàn để xoá hẳn (chưa từng có
  /// giao dịch, không phải danh mục hệ thống, không ai trỏ tới, các bước con
  /// cũng chưa từng dùng). Tự cập nhật khi dữ liệu đổi.
  Stream<Set<String>> watchDeletableCategoryIds();

  /// Xoá HẲN 1 danh mục (kèm các bước trạng thái con) trong 1 transaction DB.
  /// Kiểm tra lại điều kiện ngay trong transaction — không tin trạng thái UI —
  /// và ném [CategoryNotDeletableException] nếu không đủ điều kiện. Không bao
  /// giờ chạm vào giao dịch.
  Future<void> deleteCategoryPermanently(String categoryId);
}
