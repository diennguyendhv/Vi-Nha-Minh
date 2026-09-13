import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../features/add_transaction/add_transaction_sheet.dart';
import '../features/home/home_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/summary/summary_screen.dart';
import '../providers/app_state_providers.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(currentTabProvider);

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: tab.index,
          children: const [HomeScreen(), SummaryScreen(), SettingsScreen()],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        onPressed: () => showAddTransactionSheet(context),
        shape: const CircleBorder(),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
      ),
      bottomNavigationBar: _BottomBar(
        current: tab,
        onSelect: (t) => ref.read(currentTabProvider.notifier).state = t,
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.current, required this.onSelect});

  final AppTab current;
  final ValueChanged<AppTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: Color(0xFFECEAE4))),
      ),
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _BarItem(
              icon: Icons.home_rounded,
              label: 'Trang chủ',
              selected: current == AppTab.home,
              onTap: () => onSelect(AppTab.home),
            ),
            _BarItem(
              icon: Icons.pie_chart_rounded,
              label: 'Tổng hợp',
              selected: current == AppTab.summary,
              onTap: () => onSelect(AppTab.summary),
            ),
            _BarItem(
              icon: Icons.settings_rounded,
              label: 'Cài đặt',
              selected: current == AppTab.settings,
              onTap: () => onSelect(AppTab.settings),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.textMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 21, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
