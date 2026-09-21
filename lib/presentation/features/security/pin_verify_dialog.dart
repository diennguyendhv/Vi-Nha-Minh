import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/security/app_lock.dart';
import '../../providers/app_lock_provider.dart';
import 'pin_field.dart';

/// Yêu cầu nhập PIN hiện tại trước thao tác nhạy cảm (đổi PIN, tắt khoá).
/// Trả về true khi PIN đúng. Lần sai vẫn tính vào bộ đếm chặn tạm thời.
Future<bool> showPinVerifyDialog(
  BuildContext context, {
  required String title,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PinVerifyDialog(title: title),
  );
  return ok ?? false;
}

class _PinVerifyDialog extends ConsumerStatefulWidget {
  const _PinVerifyDialog({required this.title});

  final String title;

  @override
  ConsumerState<_PinVerifyDialog> createState() => _PinVerifyDialogState();
}

class _PinVerifyDialogState extends ConsumerState<_PinVerifyDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _locked = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit(String pin) async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = await ref.read(appLockProvider.notifier).verifyCurrentPin(pin);
    if (!mounted) return;
    if (r.isOk) {
      Navigator.of(context).pop(true);
      return;
    }
    _controller.clear();
    setState(() {
      _busy = false;
      _locked =
          r.outcome == PinVerifyOutcome.lockedOut ||
          r.lockoutRemaining > Duration.zero;
      _error = switch (r.outcome) {
        PinVerifyOutcome.lockedOut =>
          'Nhập sai quá nhiều lần. Vui lòng thử lại sau '
              '${r.lockoutRemaining.inSeconds} giây.',
        PinVerifyOutcome.wrong =>
          r.lockoutRemaining > Duration.zero
              ? 'Mã PIN không đúng. Tạm khóa ${r.lockoutRemaining.inSeconds} giây.'
              : 'Mã PIN không đúng.',
        _ => 'Không kiểm tra được mã PIN.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Nhập mã PIN hiện tại'),
          const SizedBox(height: 12),
          PinField(
            controller: _controller,
            enabled: !_busy && !_locked,
            onCompleted: _submit,
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              key: const Key('pin_verify_error'),
              style: const TextStyle(color: kPinErrorColor, fontSize: 13),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const Key('pin_verify_cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Hủy'),
        ),
      ],
    );
  }
}
