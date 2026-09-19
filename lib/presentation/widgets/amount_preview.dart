import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';

/// Dòng xem trước số tiền dưới ô nhập ("1200000" → "1.200.000 đ"), dùng
/// `Formatters.amount` chuẩn của app. Chỉ hiện khi có số > 0; ô nhập giữ chữ
/// số thô nên không có nhảy con trỏ. Không bao giờ là nguồn dữ liệu lưu.
class AmountPreview extends StatelessWidget {
  const AmountPreview({super.key, required this.amountMinor});

  final int amountMinor;

  @override
  Widget build(BuildContext context) {
    if (amountMinor <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        Formatters.amount(amountMinor),
        key: const Key('amount_preview'),
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}
