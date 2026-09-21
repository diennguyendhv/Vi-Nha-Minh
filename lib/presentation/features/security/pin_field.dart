import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/security/app_lock.dart';

/// Ô nhập PIN 6 số: che ký tự, bàn phím số hệ thống, không gợi ý/đoán chữ, tự gửi khi đủ
/// 6 số. Bên cha xoá ô bằng `controller.clear()` sau khi xử lý.
class PinField extends StatelessWidget {
  const PinField({
    super.key,
    required this.controller,
    required this.onCompleted,
    this.enabled = true,
    this.autofocus = true,
    this.hint = '••••••',
  });

  final TextEditingController controller;
  final ValueChanged<String> onCompleted;
  final bool enabled;
  final bool autofocus;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('pin_field'),
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      obscureText: true,
      obscuringCharacter: '•',
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      textAlign: TextAlign.center,
      enableSuggestions: false,
      autocorrect: false,
      enableInteractiveSelection: false,
      autofillHints: const [],
      maxLength: kPinLength,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: 10,
      ),
      decoration: InputDecoration(
        counterText: '',
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: (v) {
        if (v.length == kPinLength) onCompleted(v);
      },
    );
  }
}

/// Màu báo lỗi dùng chung cho các màn bảo mật.
const kPinErrorColor = Color(0xFFB3261E);
