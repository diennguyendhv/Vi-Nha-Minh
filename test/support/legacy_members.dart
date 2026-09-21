import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vi_nha_minh/presentation/providers/member_providers.dart';
import 'package:vi_nha_minh/domain/entities/member_directory.dart';
import 'package:vi_nha_minh/domain/entities/wallet_identity.dart';

/// Fixture test: 2 thành viên của Wallet di sản (`memberId` `vo`/`chong`, đúng như DB
/// đã có dữ liệu thật). Production KHÔNG dùng hằng số này — mọi danh sách thành viên
/// thật đến từ `MemberRepository`.
const legacyMembers = <FinancialMember>[
  FinancialMember(memberId: 'vo', label: 'Vợ', displayOrder: 0),
  FinancialMember(memberId: 'chong', label: 'Chồng', displayOrder: 1),
];

final legacyDirectory = MemberDirectory(legacyMembers);

/// Override Riverpod cho widget test dùng repo giả: cấp danh sách thành viên di sản
/// (thay cho `MemberRepository` thật). Thêm vào `ProviderScope(overrides: [...])`.
final legacyMemberOverrides = <Override>[
  membersStreamProvider.overrideWith((ref) => Stream.value(legacyMembers)),
];
