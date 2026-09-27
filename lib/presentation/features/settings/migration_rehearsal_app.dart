import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../../data/local/db_encryption/db_key_store.dart';
import '../../../data/local/db_encryption/migration_rehearsal.dart';

/// Bản build CHẨN ĐOÁN (`--dart-define=DB_REHEARSAL=true`, chỉ debug): KHÔNG chạy
/// preflight/Auth/registry, KHÔNG mở ví bằng `AppDatabase` ⇒ file ví thật không bao giờ
/// bị di trú ở chế độ này. Chỉ đọc khoá DB (Keystore) rồi chạy
/// [rehearseWalletMigration] trên bản sao tạm. Chuỗi hiển thị cố ý không qua l10n: công
/// cụ nội bộ, bị gỡ trước Play (CLAUDE.md mục 19).
class MigrationRehearsalApp extends StatelessWidget {
  const MigrationRehearsalApp({super.key});
  static const enabled = kDebugMode && bool.fromEnvironment('DB_REHEARSAL');

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: _RehearsalScreen());
}

class _RehearsalScreen extends StatefulWidget {
  const _RehearsalScreen();
  @override
  State<_RehearsalScreen> createState() => _RehearsalScreenState();
}

class _RehearsalScreenState extends State<_RehearsalScreen> {
  List<File> _files = const [];
  String _out = 'Chưa chạy';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _list();
  }

  Future<Directory> _scratch() async =>
      Directory('${(await getTemporaryDirectory()).path}/migration_rehearsal');

  Future<void> _list() async {
    // Dọn bản sao sót lại từ lần chạy bị ngắt (chỉ trong thư mục tạm riêng).
    final scratch = await _scratch();
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
    final docs = await getApplicationDocumentsDirectory();
    final files =
        docs
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.sqlite'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    if (mounted) setState(() => _files = files);
  }

  Future<void> _run(File live) async {
    setState(() {
      _busy = true;
      _out = 'Đang chạy…';
    });
    final name = live.uri.pathSegments.last;
    Map<String, Object?> report;
    try {
      final entry = await const KeystoreDbKeyStore().load(name);
      if (entry == null) {
        report = {
          'file': name,
          'pass': false,
          'mismatches': ['key-missing'],
        };
      } else {
        final r = await rehearseWalletMigration(
          live: live,
          liveKey: entry.key,
          scratch: await _scratch(),
        );
        report = {'file': name, ...r.report};
      }
    } on Object catch (e) {
      report = {
        'file': name,
        'pass': false,
        'mismatches': ['error:${e.runtimeType}'],
      };
    }
    // logcat cắt ~1 KB/dòng ⇒ in từng khoá 1 dòng.
    for (final e in report.entries) {
      debugPrint('[rehearsal] ${e.key}=${jsonEncode(e.value)}');
    }
    debugPrint('[rehearsal] END pass=${report['pass']}');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _out = const JsonEncoder.withIndent(' ').convert(report);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Diễn tập di trú DB (chẩn đoán)')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Chỉ đọc ví thật. Bản sao mã hoá tạm được di trú, so sánh rồi xoá. '
          'Chế độ này không mở ví.',
        ),
        const SizedBox(height: 12),
        for (final f in _files)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FilledButton(
              onPressed: _busy ? null : () => _run(f),
              child: Text('Diễn tập: ${f.uri.pathSegments.last}'),
            ),
          ),
        const SizedBox(height: 12),
        SelectableText(_out),
      ],
    ),
  );
}
