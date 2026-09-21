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

  /// Id các bước trạng thái KHÔNG còn giao dịch nào (kể cả dòng ẩn) tham chiếu —
  /// xoá hẳn được ngay, không cần xác nhận gỡ tham chiếu.
  Stream<Set<String>> watchDeletableStatusIds();

  /// Xoá HẲN 1 bước (đang dùng hay đã ngừng) khi KHÔNG còn giao dịch nào tham
  /// chiếu; ném [StatusNotDeletableException] nếu còn. Chuẩn hoá lại thứ tự các
  /// bước còn lại của danh mục. Không chạm giao dịch.
  Future<void> deleteStatusPermanently(String statusId);

  /// Xoá 1 bước ĐANG được dùng, trong 1 transaction DB duy nhất: đặt `status_id =
  /// NULL` cho MỌI giao dịch đang dùng nó (chỉ cột đó), xoá dòng bước, chuẩn hoá
  /// thứ tự còn lại. Lỗi ở bất kỳ bước nào ⇒ hoàn tác toàn bộ. Trả về số giao
  /// dịch đã được chuyển về "Không có trạng thái". Không ảnh hưởng số dư.
  Future<int> clearAndDeleteStatus(String statusId);
}
