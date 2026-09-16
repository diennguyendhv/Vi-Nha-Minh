import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../features/add_transaction/add_transaction_sheet.dart';
import '../features/category/category_list_screen.dart';
import '../features/home/home_screen.dart';
import '../features/summary/summary_screen.dart';
import '../features/transactions/transaction_list_screen.dart';
import '../providers/app_state_providers.dart';

/// 5 ô ở bottom-nav đúng `docs/design.html` (Trang chủ / Giao dịch / [+] /
/// Danh mục / Tổng hợp) — [+] không phải 1 tab, mở thẳng "Thêm giao dịch".
/// "Cài đặt" chuyển vào avatar ở Trang chủ (`home_screen.dart`).
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(currentTabProvider);

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: tab.index,
          children: const [
            HomeScreen(),
            TransactionListScreen(),
            CategoryListScreen(),
            SummaryScreen(),
          ],
        ),
      ),
      bottomNavigationBar: _BottomBar(
        current: tab,
        onSelect: (t) => ref.read(currentTabProvider.notifier).state = t,
        onAdd: () => showAddTransactionSheet(context),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.current,
    required this.onSelect,
    required this.onAdd,
  });

  final AppTab current;
  final ValueChanged<AppTab> onSelect;
  final VoidCallback onAdd;

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
              icon: Icons.receipt_long_rounded,
              label: 'Giao dịch',
              selected: current == AppTab.transactions,
              onTap: () => onSelect(AppTab.transactions),
            ),
            _AddButton(onTap: onAdd),
            _BarItem(
              icon: Icons.category_rounded,
              label: 'Danh mục',
              selected: current == AppTab.categories,
              onTap: () => onSelect(AppTab.categories),
            ),
            _BarItem(
              icon: Icons.pie_chart_rounded,
              label: 'Tổng hợp',
              selected: current == AppTab.summary,
              onTap: () => onSelect(AppTab.summary),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 46,
        height: 46,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 21, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
