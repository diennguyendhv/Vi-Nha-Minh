import 'package:flutter/material.dart';

import '../../domain/entities/savings_asset_type.dart';

/// 4 loại tài sản tiết kiệm seed mặc định — chỉ dùng để SEED database rỗng
/// lúc khởi tạo. Gia đình tự thêm bao nhiêu loại khác tuỳ ý (Bất động sản...)
/// qua UI, không giới hạn 4 loại như tên gợi ý.
///
/// Tiền mặt và tiền trong tài khoản ngân hàng dùng hằng ngày KHÔNG phải loại
/// tài sản tiết kiệm — cả hai đều là tiền khả dụng (`PoolKind.memberAvailable`).
/// Tiết kiệm là khi tiền rời khỏi khả dụng để thành một dạng tài sản khác:
/// gửi ngân hàng (tiền gửi tiết kiệm/sinh lời, KHÔNG phải tài khoản thanh
/// toán), vàng, chứng khoán... — xem `docs/financial-core-v2.md` mục 9.
///
/// `bankId` giữ nguyên `'savings_bank'` (trước đây hiển thị "Ngân hàng") để
/// tương thích với dữ liệu đã seed; chỉ đổi tên hiển thị.
class DefaultSavingsAssetTypes {
  DefaultSavingsAssetTypes._();

  static const bankId = 'savings_bank';
  static const goldId = 'savings_gold';
  static const stocksId = 'savings_stocks';
  static const otherId = 'savings_other';

  static const bank = SavingsAssetType(
    id: bankId,
    name: 'Gửi ngân hàng',
    color: Color(0xFF12805C),
  );
  static const gold = SavingsAssetType(
    id: goldId,
    name: 'Vàng',
    color: Color(0xFFC9A23E),
  );
  static const stocks = SavingsAssetType(
    id: stocksId,
    name: 'Chứng khoán',
    color: Color(0xFF8A4FB0),
  );
  static const other = SavingsAssetType(
    id: otherId,
    name: 'Khác',
    color: Color(0xFF8FA3B3),
  );

  static const all = <SavingsAssetType>[bank, gold, stocks, other];
}
