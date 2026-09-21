import 'wallet_identity.dart';

/// Ảnh chụp bất biến danh sách [FinancialMember] của Wallet đang mở (đã sắp theo
/// `displayOrder`). Là thứ UI/logic dùng để liệt kê, tra nhãn và tìm "người còn lại" —
/// thay cho các hằng số Vợ/Chồng. Không quy ước gì từ chuỗi `memberId`.
class MemberDirectory {
  MemberDirectory(Iterable<FinancialMember> members)
    : members = List.unmodifiable(members);

  static final empty = MemberDirectory(const []);

  final List<FinancialMember> members;

  bool get isEmpty => members.isEmpty;

  List<String> get ids => [for (final m in members) m.memberId];

  FinancialMember? byId(String? memberId) {
    if (memberId == null) return null;
    for (final m in members) {
      if (m.memberId == memberId) return m;
    }
    return null;
  }

  bool contains(String? memberId) => byId(memberId) != null;

  /// Nhãn hiển thị; `null` nếu không có thành viên đó (không đoán từ `memberId`).
  String? labelOf(String? memberId) => byId(memberId)?.label;

  /// Thành viên mặc định = người đầu tiên theo `displayOrder`. Quy tắc tương thích tạm
  /// thời (hiện là Vợ vì thứ tự seed); phase Account sau sẽ thay bằng danh tính đã gắn.
  String? get defaultMemberId => members.isEmpty ? null : members.first.memberId;

  /// `memberId` nếu thuộc Wallet, ngược lại thành viên mặc định (có thể null nếu rỗng).
  String? resolveOrDefault(String? memberId) =>
      contains(memberId) ? memberId : defaultMemberId;

  /// Thành viên đầu tiên (theo `displayOrder`) khác [memberId]; `null` nếu không có —
  /// dùng làm mặc định cho "người nhận" khi chuyển tiền giữa các thành viên.
  String? firstOtherThan(String memberId) {
    for (final m in members) {
      if (m.memberId != memberId) return m.memberId;
    }
    return null;
  }

  /// "Người còn lại" của [memberId]: chỉ xác định được khi Wallet có ĐÚNG 2 thành viên
  /// và [memberId] là 1 trong 2; ngược lại `null` (không đoán).
  String? otherThan(String memberId) {
    if (members.length != 2 || !contains(memberId)) return null;
    return members.firstWhere((m) => m.memberId != memberId).memberId;
  }
}
