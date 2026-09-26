import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db_encryption_status.dart';
import 'debug_db_benchmark_screen.dart';
import '../../../core/theme/app_colors.dart';
import '../security/security_settings_section.dart';
import '../fund/fund_list_screen.dart';
import '../savings/savings_screen.dart';
import 'account_settings_card.dart';
import 'debug_import_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Màn này được push thành route riêng từ avatar ở Trang chủ (không còn
    // nằm dưới `Scaffold` của `AppShell`), nên PHẢI tự có `Scaffold` — nếu
    // không `InkWell` của từng dòng ném "No Material widget found" (F23).
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          const AccountSettingsCard(),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.accentDark, AppColors.accent],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nâng cấp Premium',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Mở khoá nhiều sổ, báo cáo xu hướng nhiều tháng và sao lưu không giới hạn.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12.5,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                _SettingsRow(
                  label: 'Quỹ',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const FundListScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1, color: AppColors.divider),
                _SettingsRow(
                  label: 'Tiết kiệm',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SavingsScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1, color: AppColors.divider),
                const _SettingsRow(label: 'Ngân sách theo tháng'),
                const Divider(height: 1, color: AppColors.divider),
                const DbEncryptionStatusLine(),
                const SecuritySettingsSection(),
                // Công cụ dev tạm thời (V2-2C): CHỈ có trong bản debug, không
                // bao giờ xuất hiện ở release.
                if (kDebugMode) ...[
                  const Divider(height: 1, color: AppColors.divider),
                  _SettingsRow(
                    label: 'Nhập dữ liệu 2026 (debug)',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const DebugImportScreen(),
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.divider),
                  _SettingsRow(
                    label: 'Đo hiệu năng DB (debug)',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const DebugDbBenchmarkScreen(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
