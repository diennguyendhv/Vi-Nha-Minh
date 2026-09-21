import '../entities/wallet_identity.dart';

/// Nguồn DUY NHẤT của danh sách [FinancialMember] cho Financial Core và UI. Mọi màn
/// hình/logic cần "những ai trong Wallet" phải đi qua đây — không đọc bảng thô, không
/// dùng hằng số Vợ/Chồng.
abstract class MemberRepository {
  /// Theo `displayOrder` tăng dần (hoà thì theo `memberId` để ổn định).
  Stream<List<FinancialMember>> watchMembers();

  Future<List<FinancialMember>> getMembers();

  /// `null` nếu `memberId` không thuộc Wallet này.
  Future<FinancialMember?> getMemberById(String memberId);

  /// Tạo thành viên mới với `memberId` MỜ (không suy từ nhãn/vai trò/email/thiết bị),
  /// `displayOrder` nối vào cuối. Không đụng dòng tài chính nào.
  Future<FinancialMember> createMember({required String label});
}
