/// Loại Wallet. P2 chỉ dùng [local] (chưa gắn Account nào). `personal` / `family`
/// dành cho các phase Account/Family sau — chưa có logic nào dùng chúng.
enum WalletKind { local, personal, family }

/// Danh tính tài chính ổn định của 1 người trong Wallet (KHÔNG phải tài khoản, KHÔNG
/// phải email). Lịch sử tài chính thuộc [memberId]; tài khoản đại diện cho thành
/// viên này (nếu có) là chuyện của phase Membership, không nằm ở đây.
///
/// [memberId] của Wallet CŨ (di sản) là `vo` / `chong` — đúng chuỗi đang nằm trong
/// `source_ref_id` / `destination_ref_id` của mọi giao dịch, nên không phải viết lại
/// dòng nào. Wallet MỚI (phase sau) dùng ID mờ (`OpaqueId`) — đừng bao giờ giả định
/// `memberId == 'vo' | 'chong'` ở nơi khác ngoài lớp tương thích di sản.
class FinancialMember {
  const FinancialMember({
    required this.memberId,
    required this.label,
    required this.displayOrder,
  });

  final String memberId;

  /// Nhãn vai trò hiển thị (Vợ, Chồng, hoặc tên tuỳ chọn) — là DỮ LIỆU, không phải ID.
  final String label;
  final int displayOrder;

  @override
  bool operator ==(Object other) =>
      other is FinancialMember &&
      other.memberId == memberId &&
      other.label == label &&
      other.displayOrder == displayOrder;

  @override
  int get hashCode => Object.hash(memberId, label, displayOrder);

  @override
  String toString() => 'FinancialMember($memberId, $label, #$displayOrder)';
}

/// Danh tính tường minh của 1 Wallet cục bộ: `walletId` mờ + thành viên tài chính.
class WalletIdentity {
  const WalletIdentity({
    required this.walletId,
    required this.kind,
    required this.createdAt,
    required this.members,
  });

  final String walletId;
  final WalletKind kind;
  final DateTime createdAt;

  /// Theo `displayOrder`.
  final List<FinancialMember> members;

  FinancialMember? memberById(String memberId) {
    for (final m in members) {
      if (m.memberId == memberId) return m;
    }
    return null;
  }
}
