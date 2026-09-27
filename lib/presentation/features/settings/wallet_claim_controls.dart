import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/cloud/wallet_claim_service.dart';
import '../../../domain/auth/cloud_session.dart';
import '../../../domain/entities/cloud_binding.dart';
import '../../../l10n/session_localizations.dart';

/// P8.2 "Sao lưu ví này": claim TƯỜNG MINH (đăng nhập không bao giờ tự claim).
/// Luồng: phiên P7.1 hợp lệ → "Bạn là ai trong ví này?" (không mặc định) → màn xác
/// nhận nói rõ hệ quả → step-up → claim. Bước này chỉ gửi metadata sở hữu.
class WalletClaimControls extends StatefulWidget {
  const WalletClaimControls({
    super.key,
    required this.service,
    required this.accountLabel,
    this.stepUp,
  });
  final WalletClaimService service;

  /// Email/tên hiển thị của Account đang đăng nhập (chỉ để hiện ở màn xác nhận).
  final String accountLabel;
  final StepUp? stepUp;

  @override
  State<WalletClaimControls> createState() => _WalletClaimControlsState();
}

class _WalletClaimControlsState extends State<WalletClaimControls> {
  bool _busy = false;
  CloudBindingInfo? _binding;
  bool _loaded = false;
  String? _message;
  Map<String, String> _labels = const {};

  SessionLocalizations get _text => SessionLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    // Khởi động lại khi còn CLAIMING ⇒ gửi lại ĐÚNG claimRequestId đã lưu.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _guard(() async {
        await _reload();
        if (_binding?.state == CloudBindingState.claiming) {
          await widget.service.resume();
        }
      }, silentFailure: true),
    );
  }

  Future<void> _reload() async {
    final binding = await widget.service.binding();
    final candidates = await widget.service.candidates();
    if (!mounted) return;
    setState(() {
      _binding = binding;
      _labels = {for (final c in candidates) c.memberId: c.label};
      _loaded = true;
    });
  }

  Future<void> _guard(
    Future<void> Function() action, {
    bool silentFailure = false,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on WalletClaimException catch (e) {
      if (mounted) {
        setState(
          () => _message = switch (e.reason) {
            'ALREADY_CLAIMED' => _text.claimAlreadyClaimed,
            'ACCOUNT_HAS_WALLET' => _text.claimAccountHasWallet,
            'SELF_MEMBER_MISMATCH' => _text.claimSelfMismatch,
            'BACKUP_STARTED' => _text.claimBackupStarted,
            _ => _text.claimFailed,
          },
        );
      }
    } on SessionFailure catch (e) {
      if (mounted && !silentFailure) {
        setState(
          () => _message = switch (e.reason) {
            'RECENT_LOGIN_REQUIRED' => _text.recentLoginRequired,
            'DEVICE_REVOKED' || 'RECOVERY_REQUIRED' => _text.deviceRevoked,
            _ => e.denied ? _text.claimNeedSession : _text.claimFailed,
          },
        );
      }
    } on Object {
      if (mounted && !silentFailure)
        setState(() => _message = _text.claimFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
      try {
        await _reload();
      } on Object {
        /* Hiển thị lại ở lần sau; không làm hỏng màn Cài đặt. */
      }
    }
  }

  Future<bool> _stepUp() async {
    final ok = await (widget.stepUp?.call() ?? Future.value(true));
    if (!ok && mounted) setState(() => _message = _text.stepUpFailed);
    return ok;
  }

  String _summary(ClaimCandidate c) {
    if (c.transactionCount == 0) return _text.claimMemberEmpty;
    final f = DateFormat('MM/yyyy');
    final range = c.firstDate == null
        ? ''
        : '${f.format(c.firstDate!)} – ${f.format(c.lastDate!)}';
    return _text.claimMemberSummary(c.transactionCount, range);
  }

  Future<void> _start() => _guard(() async {
    setState(() => _message = null);
    // Bước 2 trước bước 3: không có phiên P7.1 hiện hành ⇒ dừng, chưa hỏi gì.
    await widget.service.session.credential();
    final candidates = await widget.service.candidates();
    if (!mounted) return;
    final chosen = await showDialog<ClaimCandidate>(
      context: context,
      builder: (_) => _WhoAreYouDialog(
        text: _text,
        candidates: candidates,
        summary: _summary,
      ),
    );
    if (chosen == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_text.claimConfirmTitle),
        content: SingleChildScrollView(
          child: Text(
            _text.claimConfirmBody(widget.accountLabel, chosen.label),
            key: const Key('claim_confirm_body'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_text.cancelSession),
          ),
          FilledButton(
            key: const Key('claim_confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_text.claimConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (!await _stepUp()) return;
    await widget.service.claim(chosen.memberId);
  });

  Future<void> _retry() => _guard(() async {
    setState(() => _message = null);
    await widget.service.resume();
  });

  Future<void> _check() => _guard(() async {
    final status = await widget.service.serverStatus();
    if (!mounted) return;
    setState(
      () => _message = status.claimed && status.ownedByYou
          ? _text.claimServerOk
          : status.claimed
          ? _text.claimOtherAccount
          : _text.claimServerMissing,
    );
  });

  Future<void> _abandon() => _guard(() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_text.claimAbandon),
        content: Text(_text.claimAbandonBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_text.cancelSession),
          ),
          FilledButton(
            key: const Key('claim_abandon_confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_text.claimAbandon),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (!await _stepUp()) return;
    await widget.service.abandon();
    if (mounted) setState(() => _message = _text.claimAbandoned);
  });

  @override
  Widget build(BuildContext context) {
    final text = _text;
    final binding = _binding;
    final uid = widget.service.session.accountId();
    final mine = binding != null && binding.accountId == uid;
    final String status;
    final actions = <Widget>[];
    if (!_loaded) {
      status = '';
    } else if (binding == null) {
      status = text.claimNone;
      actions.add(
        FilledButton(
          key: const Key('claim_start'),
          onPressed: _busy ? null : _start,
          child: Text(text.claimStart),
        ),
      );
    } else if (!mine) {
      status = text.claimOtherAccount;
    } else if (binding.state == CloudBindingState.claiming) {
      status = text.claimPending;
      actions.addAll([
        FilledButton(
          key: const Key('claim_retry'),
          onPressed: _busy ? null : _retry,
          child: Text(text.claimRetry),
        ),
        TextButton(
          key: const Key('claim_abandon'),
          onPressed: _busy ? null : _abandon,
          child: Text(text.claimAbandon),
        ),
      ]);
    } else {
      status = text.claimActive(
        _labels[binding.selfMemberId] ?? binding.selfMemberId,
      );
      actions.addAll([
        TextButton(
          key: const Key('claim_check'),
          onPressed: _busy ? null : _check,
          child: Text(text.claimCheck),
        ),
        TextButton(
          key: const Key('claim_abandon'),
          onPressed: _busy ? null : _abandon,
          child: Text(text.claimAbandon),
        ),
      ]);
    }
    return Column(
      key: const Key('wallet_claim_controls'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text.claimTitle,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(status, key: const Key('claim_status')),
        if (_message != null) ...[
          const SizedBox(height: 4),
          Text(_message!, key: const Key('claim_message')),
        ],
        Wrap(spacing: 8, children: actions),
      ],
    );
  }
}

/// Không có lựa chọn mặc định: nút Tiếp tục chỉ bật sau khi người dùng TỰ chọn.
class _WhoAreYouDialog extends StatefulWidget {
  const _WhoAreYouDialog({
    required this.text,
    required this.candidates,
    required this.summary,
  });
  final SessionLocalizations text;
  final List<ClaimCandidate> candidates;
  final String Function(ClaimCandidate) summary;

  @override
  State<_WhoAreYouDialog> createState() => _WhoAreYouDialogState();
}

class _WhoAreYouDialogState extends State<_WhoAreYouDialog> {
  ClaimCandidate? _chosen;

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    return AlertDialog(
      title: Text(text.claimWhoTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text.claimWhoBody),
            const SizedBox(height: 8),
            for (final c in widget.candidates)
              ListTile(
                key: Key('claim_member_${c.memberId}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _chosen?.memberId == c.memberId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(c.label),
                subtitle: Text(widget.summary(c)),
                onTap: () => setState(() => _chosen = c),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(text.cancelSession),
        ),
        FilledButton(
          key: const Key('claim_member_next'),
          onPressed: _chosen == null
              ? null
              : () => Navigator.pop(context, _chosen),
          child: Text(text.claimNext),
        ),
      ],
    );
  }
}
