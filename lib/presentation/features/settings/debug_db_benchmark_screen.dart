import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../data/local/wallet_descriptor.dart';

import '../../../data/local/db_encryption/debug_db_benchmark.dart';

/// Debug-only (never in release): plaintext vs SQLCipher timings on synthetic
/// temp data. Never touches the real Wallet or the Keystore.
class DebugDbBenchmarkScreen extends StatefulWidget {
  const DebugDbBenchmarkScreen({super.key});
  @override
  State<DebugDbBenchmarkScreen> createState() => _DebugDbBenchmarkScreenState();
}

class _DebugDbBenchmarkScreenState extends State<DebugDbBenchmarkScreen> {
  String _out = 'Chưa chạy';
  bool _busy = false;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _out = 'Đang đo…';
    });
    try {
      final r = await runDebugDbBenchmark();
      _out = [
        'median ms (plain → SQLCipher), 2000 tx, 5 rounds',
        for (final e in r.entries) '${e.key}: ${e.value.plain} → ${e.value.encrypted}',
      ].join('\n');
      if (kDebugMode) debugPrint('[db-bench] ${_out.replaceAll('\n', ' | ')}');
    } on Object catch (e) {
      _out = 'Lỗi: ${e.runtimeType}';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _report() async {
    setState(() => _busy = true);
    try {
      final r = await debugWalletIntegrityReport(
        WalletDescriptor.legacyLocal.dbFileName,
      );
      _out = const JsonEncoder.withIndent(' ').convert(r);
      // Debug-only; counts/digests/ids, never row contents or keys.
      if (kDebugMode) debugPrint('[db-report] ${jsonEncode(r)}');
    } on Object catch (e) {
      _out = 'Lỗi: ${e.runtimeType}';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('DB benchmark (debug)')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton(
            key: const Key('run_db_benchmark'),
            onPressed: _busy ? null : _run,
            child: const Text('Chạy'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('run_integrity_report'),
            onPressed: _busy ? null : _report,
            child: const Text('Báo cáo toàn vẹn ví (chỉ đọc)'),
          ),
          const SizedBox(height: 16),
          SelectableText(_out, key: const Key('db_benchmark_result')),
        ],
      ),
    ),
  );
}
