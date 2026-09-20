import '../entities/fund.dart';

/// Quỹ chính hiện trên Trang chủ: quỹ ĐANG SỬ DỤNG có id = [primaryFundId].
/// `null` khi chưa chọn, hoặc quỹ đã bị xóa/ngừng — KHÔNG tự chọn thay quỹ khác
/// (chỉ người dùng mới quyết định quỹ chính).
Fund? resolvePrimaryFund(Iterable<Fund> funds, String? primaryFundId) {
  if (primaryFundId == null) return null;
  for (final f in funds) {
    if (f.id == primaryFundId && f.isActive) return f;
  }
  return null;
}
