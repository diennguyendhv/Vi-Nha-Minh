import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/sync_mode.dart';

/// Mặc định "local" cho mọi gia đình mới. Giai đoạn B sẽ đọc/ghi giá trị
/// này từ nơi lưu bền vững thật (vd shared_preferences hoặc chính local DB)
/// và đổi sang "cloud" ngay sau khi migrate dữ liệu thành công — hiện tại
/// (Giai đoạn A) chưa có ai đọc/ghi provider này ngoài giá trị mặc định.
final syncModeProvider = StateProvider<SyncMode>((ref) => SyncMode.local);
