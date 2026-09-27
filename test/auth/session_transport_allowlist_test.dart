import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/data/auth/session_transport.dart';
import 'package:vi_nha_minh/data/cloud/family_service.dart';

/// Transport thật chỉ gọi endpoint trong danh sách cho phép. Mọi endpoint mà app
/// dùng (kể cả Family P10) phải có trong đó VÀ phải tồn tại ở backend — lỗi thiếu
/// endpoint chỉ lộ ra trên máy thật (test khác dùng transport giả).
void main() {
  test('mọi callable app dùng đều nằm trong allowlist và có trong functions/index.js', () {
    final backend = File('functions/index.js').readAsStringSync();
    final exported = RegExp(r'exports\.(\w+) = onCall').allMatches(backend).map((m) => m.group(1)).toSet();
    final used = <String>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      for (final m in RegExp(r"""_(?:call|send)\(\s*'(\w+)'""").allMatches(f.readAsStringSync())) {
        used.add(m.group(1)!);
      }
    }
    expect(used, containsAll(FamilyServiceOps.all));
    for (final op in used) {
      expect(SessionTransportClient.operations, contains(op), reason: op);
      expect(exported, contains(op), reason: op);
    }
    for (final op in SessionTransportClient.operations) {
      expect(exported, contains(op), reason: op);
    }
  });
}
