import 'default_categories.dart';

/// Danh mục HỆ THỐNG thuộc tính năng nâng cao (Vay & Cho vay, Hoàn tiền /
/// Thu hồi). Engine + lịch sử giữ nguyên; chỉ ẨN khỏi UI mặc định (bộ chọn
/// danh mục, màn Danh mục) để người dùng phổ thông không phải hiểu chúng.
///
/// Nhận diện bằng ID hệ thống ổn định do chính engine dùng (không dùng tên
/// hiển thị, không thêm cột mới). Giao dịch cũ dùng các danh mục này vẫn hiện
/// đúng tên trong lịch sử vì màn lịch sử đọc TOÀN BỘ danh mục.
class AdvancedSystemCategories {
  AdvancedSystemCategories._();

  static final Set<String> ids = {
    DefaultCategories.choVay.id,
    DefaultCategories.vayNo.id,
    DefaultCategories.traNo.id,
    DefaultCategories.laiChoVay.id,
    DefaultCategories.hoanTienThuHoi.id,
  };

  static bool contains(String categoryId) => ids.contains(categoryId);
}
