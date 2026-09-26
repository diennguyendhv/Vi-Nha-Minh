import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import '../../providers/database_provider.dart';

/// Cổng quyền truy cập Wallet theo Account (đặt dưới `LockGate`).
///
/// Ví Family (và Personal đã claim) gắn với Account. Đăng nhập Account khác trên cùng
/// máy ⇒ ví bị ẨN: `child` (Navigator + mọi màn tài chính) KHÔNG được dựng, không DB
/// nào được mở. File SQLCipher, khoá, binding giữ nguyên — không xoá, không chuyển
/// quyền, không claim cho Account mới. Đăng nhập lại đúng Account ⇒ cùng ví quay lại.
class WalletAccessGate extends ConsumerWidget {
  const WalletAccessGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Đang nạp trạng thái đăng nhập: chưa quyết định ⇒ không lộ gì, không báo nhầm.
    if (ref.watch(accountProvider).isLoading) {
      return const Material(child: SizedBox.expand());
    }
    if (!ref.watch(walletAccessDeniedProvider)) return child;
    final busy = ref.watch(authActionProvider).busy;
    return Material(
      key: const Key('wallet_access_denied'),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_person_outlined, size: 56),
              const SizedBox(height: 16),
              const Text(
                'Ví trên máy này thuộc một tài khoản khác',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              const Text(
                'Tài khoản đang đăng nhập không có quyền mở ví này. Dữ liệu vẫn được '
                'giữ nguyên và mã hoá trên máy. Đăng nhập đúng tài khoản để mở lại.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('wallet_access_sign_out'),
                onPressed: busy
                    ? null
                    : () => ref.read(authActionProvider.notifier).signOut(),
                child: const Text('Đăng xuất tài khoản này'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
