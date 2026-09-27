import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/import/legacy_import_guard.dart';
import '../../../data/import/legacy_import_plan.dart';
import '../../../data/import/legacy_ledger_importer.dart';
import '../../providers/database_provider.dart';

/// CÔNG CỤ DEV TẠM THỜI (V2-2C) — chỉ truy cập được trong bản debug
/// (`kDebugMode`, xem `SettingsScreen`). Đọc `import_plan.json` +
/// `import_manifest.json` do adb đẩy vào thư mục file riêng của app (không cần
/// quyền lưu trữ), hiện bản xem trước, rồi CHỈ nhập khi người dùng bấm xác nhận.
/// Chạy đúng importer đã qua staging (repository + Financial Core, 1 transaction
/// nguyên tử — kèm kiểm tra số liệu sau nhập BÊN TRONG transaction: sai ⇒ rollback).
class DebugImportScreen extends ConsumerStatefulWidget {
  const DebugImportScreen({super.key});

  @override
  ConsumerState<DebugImportScreen> createState() => _DebugImportScreenState();
}

class _DebugImportScreenState extends ConsumerState<DebugImportScreen> {
  ImportPlan? _plan;
  LegacyImportManifest? _manifest;
  LegacyBaseline? _baseline;
  LegacyLedgerMeasure? _current;
  String? _error;
  bool _busy = true;
  LegacyLedgerMeasure? _done;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) throw 'Không có thư mục file riêng của app.';
      final planFile = File('${dir.path}/import_plan.json');
      final manFile = File('${dir.path}/import_manifest.json');
      if (!planFile.existsSync() || !manFile.existsSync()) {
        throw 'Chưa có import_plan.json / import_manifest.json trong\n${dir.path}';
      }
      final plan = ImportPlan.fromJson(
        jsonDecode(await planFile.readAsString()) as Map<String, dynamic>,
      );
      final manifest = LegacyImportManifest.fromJson(
        jsonDecode(await manFile.readAsString()) as Map<String, dynamic>,
      );
      LegacyImportGuard.validatePlan(plan, manifest);
      final db = ref.read(appDatabaseProvider);
      final baseline = await LegacyImportGuard.checkBaseline(db, plan);
      final current = await LegacyImportGuard.measure(db);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _manifest = manifest;
        _baseline = baseline;
        _current = current;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  Future<void> _import() async {
    final plan = _plan!, manifest = _manifest!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final db = ref.read(appDatabaseProvider);
      // Nhập + xác minh trong CÙNG 1 transaction: sai lệch ⇒ ném ⇒ rollback toàn bộ.
      final measured = await db.transaction(() async {
        final base = await LegacyImportGuard.checkBaseline(db, plan);
        if (!base.clean) throw LegacyImportRejectedException(base.problems);
        final r = await LegacyLedgerImporter(db).run(plan);
        final problems = <String>[
          if (r.transactionsCreated != manifest.finalTransactions)
            'Đã tạo ${r.transactionsCreated} ≠ ${manifest.finalTransactions} giao dịch',
          if (r.transactionsExisting != 0) 'Có giao dịch đã tồn tại',
        ];
        final n =
            (await db
                    .customSelect('SELECT COUNT(*) c FROM transaction_rows')
                    .getSingle())
                .read<int>('c');
        if (n != manifest.finalTransactions) {
          problems.add('Đếm DB $n ≠ ${manifest.finalTransactions}');
        }
        final m = await LegacyImportGuard.measure(db);
        problems.addAll(LegacyImportGuard.diff(m, manifest));
        if (problems.isNotEmpty) throw LegacyImportRejectedException(problems);
        return m;
      });
      if (!mounted) return;
      setState(() {
        _done = measured;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'NHẬP THẤT BẠI — đã hoàn tác toàn bộ.\n$e';
        _busy = false;
      });
    }
  }

  static String _fmt(int v) {
    final s = v.abs().toString();
    final b = StringBuffer(v < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }

  Widget _row(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: Text(k)),
        Text(v),
      ],
    ),
  );

  Widget _balances(Map<String, int> b) => Column(
    children: [
      _row('Vợ Khả dụng', _fmt(b['availableVo']!)),
      _row('Chồng Khả dụng', _fmt(b['availableChong']!)),
      _row('Vợ Tiết kiệm', _fmt(b['savingsVo']!)),
      _row('Chồng Tiết kiệm', _fmt(b['savingsChong']!)),
      _row('Tổng tài sản', _fmt(b['totalAssets']!)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final plan = _plan, manifest = _manifest, baseline = _baseline;
    final children = <Widget>[];
    if (_busy) {
      children.add(const Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      children.add(
        Text(_error!, style: const TextStyle(color: Colors.red, height: 1.4)),
      );
    }
    if (_done != null && manifest != null) {
      children
        ..add(
          const Text(
            'Nhập dữ liệu hoàn tất',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        )
        ..add(const SizedBox(height: 8))
        ..add(_row('Giao dịch', _fmt(manifest.finalTransactions)))
        ..add(_balances(_done!.balances));
    } else if (plan != null && manifest != null && baseline != null) {
      children
        ..add(_row('Nguồn', 'Quản lý tài chính 2026'))
        ..add(_row('Workbook hash', '${plan.workbookSha256.substring(0, 8)}…'))
        ..add(_row('Giao dịch nguồn', _fmt(manifest.sourceTransactions)))
        ..add(_row('Số dư đầu kỳ', _fmt(manifest.openingTransactions)))
        ..add(_row('Phân bổ tiết kiệm', _fmt(manifest.allocationTransactions)))
        ..add(_row('Tổng sẽ nhập', _fmt(manifest.finalTransactions)))
        ..add(const Divider())
        ..add(const Text('Kỳ vọng sau nhập:'))
        ..add(_balances(manifest.balances))
        ..add(const Divider());
      if (baseline.alreadyImported) {
        children.add(
          const Text(
            'Dữ liệu này đã được nhập',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        );
        if (_current != null) children.add(_balances(_current!.balances));
      } else if (!baseline.clean) {
        children.add(
          Text(
            'BỊ CHẶN — DB không ở trạng thái sạch:\n${baseline.problems.join('\n')}',
            style: const TextStyle(color: Colors.red, height: 1.4),
          ),
        );
      } else {
        children.add(
          FilledButton(
            onPressed: _busy ? null : _import,
            child: Text('NHẬP ${_fmt(manifest.finalTransactions)} GIAO DỊCH'),
          ),
        );
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Nhập dữ liệu 2026 (debug)')),
      backgroundColor: AppColors.background,
      body: ListView(padding: const EdgeInsets.all(20), children: children),
    );
  }
}
