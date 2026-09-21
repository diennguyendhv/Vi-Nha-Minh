import '../../core/constants/advanced_system_categories.dart';
import '../entities/category.dart';
import '../entities/transaction_type.dart';

/// Danh mục HẠ TẦNG (hệ thống): Chuyển / Nạp quỹ / Tiết kiệm (type = transfer, chỉ
/// dùng bởi luồng riêng của chúng) và các danh mục tính năng nâng cao (Vay & Cho
/// vay, Hoàn tiền / Thu hồi — nhận diện bằng ID ổn định). KHÔNG bao giờ được đưa
/// vào bộ chọn danh mục của giao dịch Thu/Chi thường; nhận diện bằng ID/loại, không
/// bằng tên hiển thị. Dòng DB vẫn còn (engine/tương thích), không xóa.
bool isSystemInfrastructureCategory(Category c) =>
    c.type == TransactionType.transfer || AdvancedSystemCategories.contains(c.id);

/// Danh mục thường (người dùng tự tạo / nhập từ Excel) đang dùng — điều kiện chung
/// để được CHỌN MỚI khi thêm/sửa giao dịch Thu/Chi.
bool isOrdinarySelectableCategory(Category c) =>
    c.isActive && !isSystemInfrastructureCategory(c);

/// Các danh mục được phép chọn cho giao dịch loại [type]. Nếu [currentCategoryId]
/// là danh mục hiện tại của 1 giao dịch ĐÃ CÓ (đã ngừng hoặc là danh mục hệ thống
/// từ dữ liệu cũ) nó vẫn được giữ trong danh sách CHỈ để hiển thị đúng giá trị hiện
/// tại — các danh mục hệ thống/ngừng khác không được đề nghị.
List<Category> selectableCategories(
  Iterable<Category> all, {
  required TransactionType type,
  String? currentCategoryId,
}) => [
  for (final c in all)
    if (c.type == type &&
        (isOrdinarySelectableCategory(c) || c.id == currentCategoryId))
      c,
];
