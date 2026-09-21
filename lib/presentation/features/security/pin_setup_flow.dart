import 'package:flutter/material.dart';

import '../../../domain/security/app_lock.dart';
import 'pin_field.dart';

/// Đặt PIN 2 bước (nhập → nhập lại). Lệch nhau ⇒ không lưu, quay lại bước 1.
/// `onCompleted` chỉ được gọi khi 2 lần khớp và hợp lệ.
class PinSetupFlow extends StatefulWidget {
  const PinSetupFlow({
    super.key,
    required this.onCompleted,
    this.firstPrompt = 'Nhập mã PIN mới (6 số)',
  });

  final Future<void> Function(String pin) onCompleted;
  final String firstPrompt;

  @override
  State<PinSetupFlow> createState() => _PinSetupFlowState();
}

class _PinSetupFlowState extends State<PinSetupFlow> {
  final _controller = TextEditingController();
  String? _first;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onEntered(String pin) async {
    if (_busy) return;
    if (!isValidPin(pin)) return;
    if (_first == null) {
      _controller.clear();
      setState(() {
        _first = pin;
        _error = null;
      });
      return;
    }
    if (pin != _first) {
      _controller.clear();
      setState(() {
        _first = null;
        _error = 'Hai lần nhập không khớp. Vui lòng nhập lại từ đầu.';
      });
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onCompleted(pin);
    } catch (_) {
      if (!mounted) return;
      _controller.clear();
      setState(() {
        _first = null;
        _busy = false;
        _error = 'Không lưu được mã PIN. Vui lòng thử lại.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _first == null ? widget.firstPrompt : 'Nhập lại mã PIN để xác nhận',
          key: const Key('pin_setup_prompt'),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        // Khoá theo bước để ô luôn trống + lấy lại focus khi chuyển bước.
        PinField(
          key: ValueKey(_first == null),
          controller: _controller,
          enabled: !_busy,
          onCompleted: _onEntered,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            key: const Key('pin_setup_error'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: kPinErrorColor, fontSize: 13),
          ),
        ],
      ],
    );
  }
}

/// Màn hình đặt PIN (push từ Cài đặt). Đóng và trả PIN đã xác nhận, hoặc null nếu huỷ.
/// Việc ghi PIN do bên gọi làm (tránh giữ PIN lâu hơn cần thiết).
class PinSetupScreen extends StatelessWidget {
  const PinSetupScreen({super.key, required this.title, this.prompt});

  final String title;
  final String? prompt;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: PinSetupFlow(
            firstPrompt: prompt ?? 'Nhập mã PIN mới (6 số)',
            onCompleted: (pin) async => Navigator.of(context).pop(pin),
          ),
        ),
      ),
    );
  }
}
