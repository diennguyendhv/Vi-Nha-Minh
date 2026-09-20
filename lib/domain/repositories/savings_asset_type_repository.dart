import '../entities/savings_asset_type.dart';

/// Loại tài sản tiết kiệm là DỮ LIỆU gia đình tự tạo (Gửi ngân hàng, Vàng,
/// Chứng khoán, Bất động sản...) — CRUD đầy đủ, không hardcode danh sách.
abstract class SavingsAssetTypeRepository {
  Stream<List<SavingsAssetType>> watchAssetTypes();

  /// Ném [ArgumentError] nếu id trùng tài sản hệ thống (`savings_unallocated`).
  Future<void> addAssetType(SavingsAssetType assetType);

  /// Chỉ cập nhật tên/màu — KHÔNG đổi `isActive` (dùng [softDeleteAssetType] /
  /// [reactivateAssetType] để có kiểm tra số dư).
  Future<void> updateAssetType(SavingsAssetType assetType);

  /// Đổi tên, giữ NGUYÊN id (lịch sử thấy tên mới).
  Future<void> renameAssetType(String assetTypeId, String newName);

  /// "Sử dụng lại" loại đã ngừng — giữ NGUYÊN id.
  Future<void> reactivateAssetType(String assetTypeId);

  /// Ném [SavingsAssetTypeNotEmptyException] nếu còn thành viên nào có số
  /// dư khác 0 ở loại tài sản này.
  Future<void> softDeleteAssetType(String assetTypeId);

  /// Id loại tài sản ĐÃ NGỪNG và CHƯA TỪNG được giao dịch nào tham chiếu (mọi
  /// dòng sổ, kể cả đã hoàn tác) — an toàn để xoá hẳn. Không dựa vào khoá
  /// ngoại (tham chiếu là chuỗi `assetTypeId|member`).
  Stream<Set<String>> watchDeletableAssetTypeIds();

  /// Xoá HẲN 1 loại tài sản; kiểm tra lại trong 1 DB transaction. Ném
  /// [SavingsAssetTypeNotDeletableException] nếu còn đang dùng, đã từng có
  /// giao dịch, hoặc là tài sản hệ thống.
  Future<void> deleteAssetTypePermanently(String assetTypeId);
}

