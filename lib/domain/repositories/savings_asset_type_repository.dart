import '../entities/savings_asset_type.dart';

/// Loại tài sản tiết kiệm là DỮ LIỆU gia đình tự tạo (Tiền mặt, Ngân hàng,
/// Chứng khoán, Bất động sản...) — CRUD đầy đủ, không hardcode danh sách.
abstract class SavingsAssetTypeRepository {
  Stream<List<SavingsAssetType>> watchAssetTypes();

  Future<void> addAssetType(SavingsAssetType assetType);

  Future<void> updateAssetType(SavingsAssetType assetType);

  /// Ném [SavingsAssetTypeNotEmptyException] nếu còn thành viên nào có số
  /// dư khác 0 ở loại tài sản này.
  Future<void> softDeleteAssetType(String assetTypeId);
}
