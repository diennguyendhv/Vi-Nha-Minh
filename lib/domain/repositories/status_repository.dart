import '../entities/status.dart';

/// CRUD từng bước trạng thái con của 1 danh mục (`docs/design.html` màn 07)
/// — thêm/sửa tên/sắp xếp lại/xoá độc lập từng bước, không giới hạn số
/// bước. Không bao giờ ảnh hưởng balance.
abstract class StatusRepository {
  Stream<List<Status>> watchStatuses(String categoryId);

  Future<void> addStatus(Status status);

  Future<void> renameStatus(String statusId, String newName);

  /// Ghi lại toàn bộ thứ tự mới cho các status của 1 category (kéo-thả).
  Future<void> reorderStatuses(String categoryId, List<String> orderedStatusIds);

  /// Ẩn 1 bước (`isActive = false`) — KHÔNG xoá cứng: giao dịch lịch sử vẫn
  /// giữ `statusId` và vẫn resolve được tên.
  Future<void> softDeleteStatus(String statusId);

  /// "Sử dụng lại" 1 bước đã ẩn (`isActive = true`).
  Future<void> reactivateStatus(String statusId);
}
