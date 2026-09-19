/// Phase 8.7 — 1 bên ngoài gia đình liên quan tới khoản vay/cho vay (người
/// thân, bạn bè, nhân viên, khách hàng, công ty...). Cố tình CHUNG CHUNG,
/// không gắn với bất kỳ workflow riêng nào (CLAUDE.md mục 9) — không có
/// field "loại" (person/company), chỉ là 1 cái tên + trạng thái hoạt động,
/// giống hệt nguyên tắc `Fund`/`SavingsAssetType` (dữ liệu gia đình tự tạo,
/// không hardcode).
///
/// KHÔNG đại diện cho thành viên gia đình (`FamilyMember` đã có sẵn, đảm
/// nhiệm việc "pool này của ai" — `Counterparty` chỉ là bên NGOÀI hệ pool
/// gia đình).
class Counterparty {
  const Counterparty({
    required this.id,
    required this.displayName,
    this.isActive = true,
  });

  final String id;
  final String displayName;

  /// Soft delete — chỉ nên xoá khi không còn `Obligation` nào đang mở
  /// (outstanding > 0) tham chiếu tới counterparty này. UI/Repository tự
  /// kiểm tra trước khi cho xoá, giống nguyên tắc `FundNotEmptyException`.
  final bool isActive;

  Counterparty copyWith({String? displayName, bool? isActive}) {
    return Counterparty(
      id: id,
      displayName: displayName ?? this.displayName,
      isActive: isActive ?? this.isActive,
    );
  }
}
