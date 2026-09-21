import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/constants/default_savings_asset_types.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/savings_asset_type.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/entities/transfer_kind.dart';
import 'package:vi_nha_minh/presentation/widgets/category_label.dart';
import '../../support/legacy_members.dart';

Transaction _t(
  TransferKind kind,
  PoolKind from,
  String? fromRef,
  PoolKind to,
  String? toRef,
) => Transaction(
  id: 't',
  type: TransactionType.transfer,
  transferKind: kind,
  categoryId: 'tiet_kiem',
  sourceKind: from,
  sourceRefId: fromRef,
  destinationKind: to,
  destinationRefId: toRef,
  amountMinor: 1000,
  transactionDate: DateTime(2026, 9, 1),
  createdAt: DateTime(2026, 9, 1),
  clientTxId: 'c',
);

void main() {
  final types = DefaultSavingsAssetTypes.all;
  String ref(String a, String m) => savingsAssetRefId(a, m);

  final topup = _t(TransferKind.savingsTopup, PoolKind.memberAvailable, 'chong',
      PoolKind.memberSavingsAsset, ref(SystemSavingsAssets.unallocatedId, 'chong'));
  final withdraw = _t(TransferKind.savingsWithdraw, PoolKind.memberSavingsAsset,
      ref(DefaultSavingsAssetTypes.goldId, 'vo'), PoolKind.memberAvailable, 'vo');
  final convert = _t(TransferKind.savingsConvert, PoolKind.memberSavingsAsset,
      ref(DefaultSavingsAssetTypes.goldId, 'vo'), PoolKind.memberSavingsAsset,
      ref(DefaultSavingsAssetTypes.bankId, 'vo'));

  test('Nhãn đời thường: Thêm vào / Rút từ / Tiết kiệm · A → B, không lộ enum hay id', () {
    expect(savingsTransferLabel(topup, types), 'Thêm vào tiết kiệm');
    expect(savingsTransferLabel(withdraw, types), 'Rút từ tiết kiệm · Vàng');
    expect(savingsTransferLabel(convert, types), 'Tiết kiệm · Vàng → Gửi ngân hàng');
    for (final label in [
      savingsTransferLabel(topup, types)!,
      savingsTransferLabel(withdraw, types)!,
      savingsTransferLabel(convert, types)!,
    ]) {
      expect(label, isNot(contains('savings')));
      expect(label, isNot(contains('|')));
      expect(label, isNot(contains('SAVINGS')));
    }
  });

  test('Phân bổ từ "Chưa phân bổ" và loại đã ngừng / không rõ vẫn có tên an toàn (không null)', () {
    final fromUnalloc = _t(TransferKind.savingsConvert, PoolKind.memberSavingsAsset,
        ref(SystemSavingsAssets.unallocatedId, 'chong'), PoolKind.memberSavingsAsset,
        ref(DefaultSavingsAssetTypes.goldId, 'chong'));
    expect(savingsTransferLabel(fromUnalloc, types), 'Tiết kiệm · Chưa phân bổ → Vàng');
    // Không có danh sách loại (DB chưa tải) → loại thường có tên chung, hệ thống vẫn đúng.
    expect(savingsTransferLabel(fromUnalloc, const []), 'Tiết kiệm · Chưa phân bổ → Loại tài sản khác');
    final stopped = [types.first.copyWith(isActive: false), ...types.skip(1)];
    expect(savingsTransferLabel(convert, stopped), 'Tiết kiệm · Vàng → Gửi ngân hàng');
  });

  test('Không phải giao dịch tiết kiệm → null (Chuyển thành viên, Thu, Chi giữ nhãn cũ)', () {
    final member = _t(TransferKind.memberToMember, PoolKind.memberAvailable, 'vo',
        PoolKind.memberAvailable, 'chong');
    expect(savingsTransferLabel(member, types), isNull);
    expect(transactionMemberLabel(member, legacyMembers), 'Vợ → Chồng');
  });

  test('Nhãn thành viên: nạp/rút/phân bổ tiết kiệm hiện ĐÚNG 1 tên (không "Vợ → Vợ", không rỗng)', () {
    expect(transactionMemberLabel(topup, legacyMembers), 'Chồng');
    expect(transactionMemberLabel(withdraw, legacyMembers), 'Vợ');
    expect(transactionMemberLabel(convert, legacyMembers), 'Vợ', reason: 'trước đây phân bổ không hiện thành viên nào');
  });
}
