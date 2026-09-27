import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/sync/remote_signal.dart';
import '../../../data/cloud/family_service.dart';
import '../../../data/local/sync/cloud_binding_store.dart';
import '../../../domain/auth/cloud_session.dart';
import '../../../domain/entities/cloud_binding.dart';
import '../../../domain/entities/wallet_identity.dart';
import '../../../l10n/session_localizations.dart';
import '../../providers/database_provider.dart';
import '../../providers/sync_provider.dart';

/// Tình trạng CỤC BỘ của ví đang mở (đọc SQLite + registry, 0 lời gọi mạng).
class _LocalWallet {
  const _LocalWallet({
    required this.kind,
    required this.binding,
    required this.backupOn,
    required this.familyMember,
    required this.selfMemberId,
    required this.selfLabel,
  });
  final String kind;
  final CloudBindingInfo? binding;
  final bool backupOn;
  final bool familyMember;
  final String? selfMemberId;
  final String? selfLabel;
  bool get claimed => binding?.state == CloudBindingState.active;
}

/// P10 (DEV) — màn Gia đình. Owner: "Chia sẻ với gia đình" (nâng ví tại chỗ), "Chia sẻ
/// với vợ/chồng" (mời Account làm FinancialMember ĐÃ CÓ, không chọn sẵn), đối chiếu mã
/// bảo mật rồi mới chia sẻ khoá ví, thu hồi. Member: nhập mã mời → chấp nhận → đọc mã
/// bảo mật cho Owner → tải ví. Mọi lời gọi mạng chỉ khi người dùng bấm/mở màn này.
class FamilyScreen extends ConsumerStatefulWidget {
  const FamilyScreen({super.key, required this.stepUp});
  final StepUp stepUp;
  @override
  ConsumerState<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends ConsumerState<FamilyScreen> {
  _LocalWallet? _local;
  FamilyStatus? _status;
  String? _walletCode;
  String? _message;
  bool _busy = false;
  ({String token, DateTime expiresAt})? _invite;

  // Member side.
  final _code = TextEditingController();
  FamilyInvitePreview? _preview;
  String? _fingerprint;

  SessionLocalizations get _t => SessionLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<_LocalWallet?> _readLocal() async {
    if (ref.read(walletAccessDeniedProvider)) return null;
    final db = ref.read(appDatabaseProvider);
    final meta = await db.select(db.walletMeta).getSingle();
    final binding = await CloudBindingStore(db).read();
    final state = await db.select(db.syncState).getSingleOrNull();
    final entry = ref.read(walletRegistryProvider).byWalletId(meta.walletId);
    String? label;
    if (binding != null) {
      final m =
          await (db.select(db.financialMemberRows)
                ..where((m) => m.memberId.equals(binding.selfMemberId)))
              .getSingleOrNull();
      label = m?.label;
    }
    return _LocalWallet(
      kind: meta.kind,
      binding: binding,
      backupOn: state?.backupState != null,
      familyMember: entry?.familyMember ?? false,
      selfMemberId: binding?.selfMemberId,
      selfLabel: label,
    );
  }

  Future<void> _load() async {
    final service = ref.read(familyServiceProvider);
    final local = await _readLocal();
    if (!mounted) return;
    setState(() => _local = local);
    if (service == null || local == null || !local.claimed) return;
    await _run(() async {
      _walletCode = await service.walletCode();
      if (local.kind == WalletKind.family.name && !local.familyMember) {
        _status = await service.status();
      }
    });
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      if (done != null) _message = done;
    } on FamilyException catch (e) {
      if (kDebugMode) debugPrint('[family] failed $e');
      _message = e.reason == 'member-mismatch'
          ? _t.familyMemberMismatch
          : _t.familyFailed;
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[family] failed ${e.runtimeType} $e');
      _message = _t.familyFailed;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body, String ok) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_t.cancelSession),
            ),
            FilledButton(
              key: const Key('family_confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ok),
            ),
          ],
        ),
      ) ==
      true;

  void _bumpRegistry() =>
      ref.read(walletRegistryRevisionProvider.notifier).state++;

  // ---------------------------------------------------------------- Owner
  Future<void> _promote(FamilyService s) async {
    if (!await _confirm(
      _t.familyPromote,
      _t.familyPromoteBody,
      _t.familyPromote,
    )) {
      return;
    }
    if (!await widget.stepUp()) return;
    await _run(() async {
      await s.promote();
      _bumpRegistry();
    }, done: _t.familyPromoted);
    await _load();
  }

  Future<void> _startInvite(FamilyService s) async {
    final local = _local!;
    final choices = await s.inviteChoices(local.selfMemberId!);
    if (!mounted) return;
    final picked =
        await showDialog<({FamilyMemberChoice member, String email})>(
          context: context,
          builder: (_) => _InviteDialog(choices: choices, text: _t),
        );
    if (picked == null || !mounted) return;
    if (!await _confirm(
      _t.familyInviteConfirmTitle,
      _t.familyInviteConfirmBody(picked.email, picked.member.label),
      _t.familyInvite,
    )) {
      return;
    }
    if (!await widget.stepUp()) return;
    await _run(() async {
      _invite = await s.invite(
        memberId: picked.member.memberId,
        email: picked.email,
      );
    });
  }

  Future<void> _share(FamilyService s, FamilyAccountView m) async {
    if (!await widget.stepUp()) return;
    await _run(() => s.shareKey(m), done: _t.familyKeyShared);
    await _load();
  }

  Future<void> _revoke(FamilyService s, FamilyAccountView m) async {
    if (!await _confirm(
      _t.familyRevoke,
      _t.familyRevokeBody,
      _t.familyRevoke,
    )) {
      return;
    }
    if (!await widget.stepUp()) return;
    await _run(() => s.revoke(m));
    await _load();
  }

  // --------------------------------------------------------------- Member
  Future<void> _previewInvite(FamilyService s) =>
      _run(() async => _preview = await s.preview(_code.text));

  Future<void> _accept(FamilyService s) async {
    if (!await widget.stepUp()) return;
    await _run(() async {
      final r = await s.accept(_code.text);
      _fingerprint = r.fingerprint;
      _preview = null;
    });
  }

  Future<void> _checkAndJoin(FamilyService s) async {
    await _run(() async {
      final mine = await s.myFamily();
      _fingerprint = mine.fingerprint ?? _fingerprint;
      if (!mine.member) throw const FamilyException('not-member');
      if (!mine.hasKey) {
        _message = _t.familyJoinWaiting;
        return;
      }
      final r = await s.join();
      // Tham gia (lại): token FCM cũ đã bị máy chủ xoá khi thu hồi ⇒ đăng ký lại.
      final uid = s.session.accountId();
      if (uid != null) await RemoteSignalRegistrar.forget(uid, r.walletId);
      ref.read(selectedWalletIdProvider.notifier).state = r.walletId;
      _bumpRegistry();
      _message = _t.familyJoined;
    });
  }

  String _time(DateTime t) =>
      '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  List<Widget> _ownerSection(FamilyService s, _LocalWallet local) {
    final t = _t;
    // Ví chưa đăng ký cloud (vd ví cục bộ lúc cài): chỉ phần "Tham gia" có nghĩa.
    if (!local.claimed) return const [];
    if (!local.backupOn) return [Text(t.familyNeedsBackup)];
    if (local.kind != WalletKind.family.name) {
      return [
        Text(t.familyPromoteBody),
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('family_promote'),
          onPressed: _busy ? null : () => _promote(s),
          child: Text(t.familyPromote),
        ),
      ];
    }
    final status = _status;
    return [
      if (_walletCode != null)
        Text(
          t.familyWalletCode(_walletCode!),
          key: const Key('family_wallet_code'),
        ),
      if (status != null)
        for (final a in status.accounts)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${a.label ?? '…'} · '
                    '${a.role == 'OWNER' ? t.familyOwner : t.familyMember}'
                    '${a.status == 'REVOKED' ? ' · ${t.familyRevoked}' : ''}'
                    '${a.role == 'OWNER' ? ' ${t.familyYou}' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (a.awaitingKey) ...[
                    const SizedBox(height: 6),
                    Text(t.familyAwaitingKey),
                    SelectableText(
                      a.fingerprint!,
                      key: const Key('family_owner_fingerprint'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                    FilledButton(
                      key: const Key('family_share_key'),
                      onPressed: _busy ? null : () => _share(s, a),
                      child: Text(t.familyShareKey),
                    ),
                  ],
                  if (a.isActiveMember)
                    TextButton(
                      key: const Key('family_revoke'),
                      onPressed: _busy ? null : () => _revoke(s, a),
                      child: Text(t.familyRevoke),
                    ),
                ],
              ),
            ),
          ),
      if (status != null && status.activeMember == null) ...[
        FilledButton(
          key: const Key('family_invite'),
          onPressed: _busy ? null : () => _startInvite(s),
          child: Text(t.familyInvite),
        ),
        if (_invite != null) ...[
          const SizedBox(height: 8),
          Text(t.familyInviteCode(_time(_invite!.expiresAt))),
          SelectableText(_invite!.token, key: const Key('family_invite_token')),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _invite!.token));
                  if (mounted) setState(() => _message = t.familyCopied);
                },
                child: Text(t.familyCopy),
              ),
              TextButton(
                key: const Key('family_invite_cancel'),
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await s.cancelInvite();
                        _invite = null;
                      }),
                child: Text(t.familyInviteCancel),
              ),
            ],
          ),
        ],
      ],
      TextButton(onPressed: _busy ? null : _load, child: Text(t.familyRefresh)),
    ];
  }

  List<Widget> _memberJoinSection(FamilyService s) {
    final t = _t;
    return [
      Text(
        t.familyJoinTitle,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
      TextField(
        key: const Key('family_join_code'),
        controller: _code,
        decoration: InputDecoration(labelText: t.familyJoinCode),
        autocorrect: false,
        enableSuggestions: false,
      ),
      Wrap(
        spacing: 8,
        children: [
          TextButton(
            key: const Key('family_join_preview'),
            onPressed: _busy ? null : () => _previewInvite(s),
            child: Text(t.familyJoinPreview),
          ),
          TextButton(
            key: const Key('family_join_check'),
            onPressed: _busy ? null : () => _checkAndJoin(s),
            child: Text(t.familyJoinCheck),
          ),
        ],
      ),
      if (_preview != null) ...[
        Text(t.familyJoinInvite(_time(_preview!.expiresAt))),
        FilledButton(
          key: const Key('family_join_accept'),
          onPressed: _busy ? null : () => _accept(s),
          child: Text(t.familyJoinAccept),
        ),
      ],
      if (_fingerprint != null)
        Text(
          t.familyJoinFingerprint(_fingerprint!),
          key: const Key('family_member_fingerprint'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(familyServiceProvider);
    final local = _local;
    final t = _t;
    return Scaffold(
      appBar: AppBar(title: Text(t.familyTitle)),
      body: s == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_message!, key: const Key('family_message')),
                  ),
                if (local != null && local.familyMember) ...[
                  Text(
                    t.familyYouAre(local.selfLabel ?? '…'),
                    key: const Key('family_you_are'),
                  ),
                  if (_walletCode != null)
                    Text(
                      t.familyWalletCode(_walletCode!),
                      key: const Key('family_wallet_code'),
                    ),
                ] else if (local != null)
                  ..._ownerSection(s, local),
                const Divider(height: 32),
                ..._memberJoinSection(s),
              ],
            ),
    );
  }
}

class _InviteDialog extends StatefulWidget {
  const _InviteDialog({required this.choices, required this.text});
  final List<FamilyMemberChoice> choices;
  final SessionLocalizations text;
  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  // Không chọn sẵn: người dùng PHẢI chọn tường minh.
  FamilyMemberChoice? _member;
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.text;
    final ok = _member != null && _email.text.contains('@');
    return AlertDialog(
      title: Text(t.familyInvite),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.familyInviteWho),
            for (final c in widget.choices)
              ListTile(
                key: Key('family_invite_member_${c.memberId}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _member?.memberId == c.memberId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(c.label),
                onTap: () => setState(() => _member = c),
              ),
            TextField(
              key: const Key('family_invite_email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: InputDecoration(labelText: t.familyInviteEmail),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancelSession),
        ),
        FilledButton(
          key: const Key('family_invite_next'),
          onPressed: ok
              ? () => Navigator.pop(context, (
                  member: _member!,
                  email: _email.text.trim(),
                ))
              : null,
          child: Text(t.done),
        ),
      ],
    );
  }
}
