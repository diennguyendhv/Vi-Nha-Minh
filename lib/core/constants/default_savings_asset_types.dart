import 'package:flutter/material.dart';

import '../../domain/entities/savings_asset_type.dart';

/// 2 loại tài sản tiết kiệm seed mặc định — chỉ dùng để SEED database rỗng
/// lúc khởi tạo. Gia đình tự thêm bao nhiêu loại khác tuỳ ý (Chứng khoán,
/// Bất động sản, Vàng...) qua UI, không giới hạn 2 loại như tên gợi ý.
class DefaultSavingsAssetTypes {
  DefaultSavingsAssetTypes._();

  static const cashId = 'savings_cash';
  static const bankId = 'savings_bank';

  static const cash = SavingsAssetType(
    id: cashId,
    name: 'Tiền mặt',
    color: Color(0xFF8FA3B3),
  );
  static const bank = SavingsAssetType(
    id: bankId,
    name: 'Ngân hàng',
    color: Color(0xFF12805C),
  );

  static const all = <SavingsAssetType>[cash, bank];
}
