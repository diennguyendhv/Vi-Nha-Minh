import 'package:drift/drift.dart';

import '../../../domain/entities/cloud_binding.dart';
import '../../../domain/entities/wallet_identity.dart';
import '../app_database.dart';

/// Lỗi chuyển trạng thái claim không hợp lệ (không ghi gì).
class CloudBindingException implements Exception {
  const CloudBindingException(this.reason);
  final String reason;
  @override
  String toString() => 'CloudBindingException($reason)';
}

/// Đọc/ghi `cloud_binding` (P8.1). Chỉ có các chuyển trạng thái TƯỜNG MINH:
/// NONE → CLAIMING ([beginClaim]) → ACTIVE ([activate]); CLAIMING → NONE ([abandonClaim]).
/// Không có API nào gắn ví chỉ từ phiên Firebase. Chỉ `WalletClaimService` (P8.2,
/// sau khi người dùng xác nhận + máy chủ trả lời) gọi các hàm ghi.
class CloudBindingStore {
  CloudBindingStore(this._db);
  final AppDatabase _db;

  static const _states = {
    'NONE': CloudBindingState.none,
    'CLAIMING': CloudBindingState.claiming,
    'ACTIVE': CloudBindingState.active,
  };

  /// `null` = chưa có dòng = [CloudBindingState.none].
  Future<CloudBindingInfo?> read() async {
    final r = await _db.select(_db.cloudBinding).getSingleOrNull();
    if (r == null) return null;
    return CloudBindingInfo(
      walletId: r.walletId,
      accountId: r.accountId,
      selfMemberId: r.selfMemberId,
      environment: r.environment,
      state: _states[r.state]!,
      claimRequestId: r.claimRequestId,
      cryptoVersion: r.cryptoVersion,
      keyringRev: r.keyringRev,
    );
  }

  Future<CloudBindingState> state() async =>
      (await read())?.state ?? CloudBindingState.none;

  /// Bắt đầu claim: người dùng đã chọn rõ [selfMemberId] (phải là FinancialMember
  /// ĐÃ CÓ của ví này). Chỉ từ NONE; walletId lấy từ `wallet_meta` (không nhận từ ngoài).
  Future<void> beginClaim({
    required String accountId,
    required String selfMemberId,
    required String environment,
    required String claimRequestId,
  }) => _db.transaction(() async {
    if (accountId.isEmpty || claimRequestId.isEmpty || environment.isEmpty) {
      throw const CloudBindingException('invalid-argument');
    }
    if ((await state()) != CloudBindingState.none) {
      throw const CloudBindingException('already-bound');
    }
    final meta = await _db.select(_db.walletMeta).getSingleOrNull();
    if (meta == null) throw const CloudBindingException('no-wallet');
    final member = await (_db.select(_db.financialMemberRows)
          ..where((m) => m.memberId.equals(selfMemberId)))
        .getSingleOrNull();
    if (member == null) throw const CloudBindingException('unknown-member');
    await _db.into(_db.cloudBinding).insert(
      CloudBindingCompanion.insert(
        walletId: meta.walletId,
        accountId: accountId,
        selfMemberId: selfMemberId,
        environment: environment,
        state: 'CLAIMING',
        claimRequestId: Value(claimRequestId),
        updatedAt: DateTime.now(),
      ),
      mode: InsertMode.insertOrReplace,
    );
  });

  /// Máy chủ đã xác nhận claim [claimRequestId] ⇒ ACTIVE. Từ thời điểm này mọi ghi
  /// dữ liệu Wallet đều được trigger đưa vào outbox.
  ///
  /// P8.2: khi có câu trả lời máy chủ, TRONG CÙNG 1 DB transaction kiểm lại
  /// [serverWalletId] == `wallet_meta.wallet_id`, [serverSelfMemberId] == thành viên đã
  /// chọn VÀ thành viên đó vẫn còn; lưu [serverClaimRequestId] (id claim gốc máy chủ
  /// giữ — có thể khác id cục bộ khi claim tương thích được thử lại); `wallet_meta.kind`
  /// local → personal. Sai bất kỳ điều gì ⇒ không ghi gì, vẫn CLAIMING.
  Future<void> activate({
    required String claimRequestId,
    int? cryptoVersion,
    int? keyringRev,
    String? serverWalletId,
    String? serverSelfMemberId,
    String? serverClaimRequestId,
  }) => _db.transaction(() async {
    final current = await read();
    if (current == null ||
        current.state != CloudBindingState.claiming ||
        current.claimRequestId != claimRequestId) {
      throw const CloudBindingException('not-claiming');
    }
    final meta = await _db.select(_db.walletMeta).getSingleOrNull();
    if (meta == null ||
        meta.walletId != current.walletId ||
        (serverWalletId != null && serverWalletId != meta.walletId)) {
      throw const CloudBindingException('wallet-mismatch');
    }
    if (serverSelfMemberId != null &&
        serverSelfMemberId != current.selfMemberId) {
      throw const CloudBindingException('self-member-mismatch');
    }
    final member = await (_db.select(_db.financialMemberRows)
          ..where((m) => m.memberId.equals(current.selfMemberId)))
        .getSingleOrNull();
    if (member == null) throw const CloudBindingException('unknown-member');
    await _db.update(_db.cloudBinding).write(
      CloudBindingCompanion(
        state: const Value('ACTIVE'),
        claimRequestId: Value(serverClaimRequestId ?? claimRequestId),
        cryptoVersion: Value(cryptoVersion),
        keyringRev: Value(keyringRev),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _db.update(_db.walletMeta).write(
      WalletMetaCompanion(kind: Value(WalletKind.personal.name)),
    );
  });

  /// Huỷ claim đang dở (CLAIMING → NONE). Không đụng ví ACTIVE.
  Future<void> abandonClaim() => _db.transaction(() async {
    if ((await state()) != CloudBindingState.claiming) {
      throw const CloudBindingException('not-claiming');
    }
    await _db.delete(_db.cloudBinding).go();
  });

  /// P8.2: máy chủ đã xác nhận KHÔNG còn giữ claim nào của ví này (huỷ claim thành
  /// công, hoặc claim bị từ chối dứt khoát) ⇒ CLAIMING/ACTIVE → NONE trong 1 DB
  /// transaction: xoá binding, `wallet_meta.kind` → local, bỏ outbox/sync_state (chỉ
  /// là ý định đồng bộ, không phải dữ liệu tài chính). Không dòng tài chính nào bị đụng.
  Future<void> release() => _db.transaction(() async {
    if ((await state()) == CloudBindingState.none) return;
    await _db.delete(_db.cloudBinding).go();
    await _db.delete(_db.syncOutbox).go();
    await _db.delete(_db.syncState).go();
    await _db.update(_db.walletMeta).write(
      WalletMetaCompanion(kind: Value(WalletKind.local.name)),
    );
  });
}
