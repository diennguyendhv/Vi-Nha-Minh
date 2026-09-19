import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Banner lỗi NẰM TRONG bottom sheet (F1, Pixel 7a acceptance).
///
/// Vì sao không dùng `SnackBar`: `ScaffoldMessenger` của app hiển thị
/// SnackBar ở `Scaffold` gốc, nằm DƯỚI lớp modal của bottom sheet — người
/// dùng bấm Lưu khi lỗi (vd thiếu số dư) nhưng thấy như không có phản hồi.
/// Banner này là một phần của chính nội dung sheet nên luôn nhìn thấy, và
/// tự cuộn vào tầm nhìn mỗi khi xuất hiện hoặc đổi nội dung.
class SheetErrorBanner extends StatefulWidget {
  const SheetErrorBanner({super.key, required this.message});

  final String message;

  @override
  State<SheetErrorBanner> createState() => _SheetErrorBannerState();
}

class _SheetErrorBannerState extends State<SheetErrorBanner> {
  @override
  void initState() {
    super.initState();
    _scrollIntoView();
  }

  @override
  void didUpdateWidget(covariant SheetErrorBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) _scrollIntoView();
  }

  void _scrollIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.maybeOf(context)?.position.ensureVisible(
        context.findRenderObject()!,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: const Key('sheet_error_banner'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.expenseAmount.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.expenseAmount.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 18,
              color: AppColors.expenseAmount,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.message,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.expenseAmount,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
