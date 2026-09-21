import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/local_member_repository.dart';
import '../../domain/entities/member_directory.dart';
import '../../domain/entities/wallet_identity.dart';
import '../../domain/repositories/member_repository.dart';
import 'database_provider.dart';

final memberRepositoryProvider = Provider<MemberRepository>((ref) {
  return LocalMemberRepository(ref.watch(appDatabaseProvider));
});

/// [FinancialMember] của Wallet đang mở, theo `displayOrder` — nguồn thành viên DUY
/// NHẤT của UI (Trang chủ, Thêm/Sửa giao dịch, Tổng hợp, Tiết kiệm, Vay...).
final membersStreamProvider = StreamProvider<List<FinancialMember>>((ref) {
  return ref.watch(memberRepositoryProvider).watchMembers();
});

/// Bản đồng bộ của [membersStreamProvider]: rỗng khi đang tải (mọi caller phải chịu được
/// danh sách rỗng — xem [MemberDirectory]).
final memberDirectoryProvider = Provider<MemberDirectory>((ref) {
  final members = ref.watch(membersStreamProvider).valueOrNull;
  return members == null ? MemberDirectory.empty : MemberDirectory(members);
});
