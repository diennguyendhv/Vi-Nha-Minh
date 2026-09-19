import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Chống "tap xuyên" sau khi một bottom sheet tài chính LƯU THÀNH CÔNG rồi đóng.
///
/// Nguyên nhân (Pixel 7a, R5): khi route bottom sheet đang đóng, Flutter bọc
/// nó trong `IgnorePointer`, và ngay sau khi route bị gỡ thì các tap kế tiếp
/// của người dùng (bấm Lưu 2–3 lần liên tiếp) rơi xuống trang bên dưới — tại
/// đúng vị trí nút Lưu đang nằm nút "+" của Home, nên mở ra sheet mới.
///
/// Cách xử lý: ngay trước khi pop sau khi lưu xong, [TapGuardNotifier.arm]
/// bật cờ; [TapGuardScope] (đặt trên cùng cây app) nuốt mọi pointer trong
/// [kTapGuardWindow] rồi tự tắt. Chỉ kích hoạt ở nhánh THÀNH CÔNG — đóng
/// bằng nút X / Back không bị ảnh hưởng.
const kTapGuardWindow = Duration(milliseconds: 600);

class TapGuardNotifier extends Notifier<bool> {
  Timer? _timer;

  @override
  bool build() {
    ref.onDispose(() => _timer?.cancel());
    return false;
  }

  void arm() {
    _timer?.cancel();
    state = true;
    _timer = Timer(kTapGuardWindow, () => state = false);
  }
}

final tapGuardProvider = NotifierProvider<TapGuardNotifier, bool>(
  TapGuardNotifier.new,
);

/// Đặt ngay dưới `MaterialApp` (qua `builder`) để phủ cả Navigator/overlay.
class TapGuardScope extends ConsumerWidget {
  const TapGuardScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AbsorbPointer(absorbing: ref.watch(tapGuardProvider), child: child);
  }
}

/// Đóng sheet sau khi lưu thành công: bật chống tap-xuyên rồi pop đúng 1 lần.
void closeSheetAfterSave(BuildContext context, WidgetRef ref) {
  ref.read(tapGuardProvider.notifier).arm();
  Navigator.of(context).pop();
}
