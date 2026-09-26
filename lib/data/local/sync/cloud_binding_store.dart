import 'package:drift/drift.dart';

import '../../../domain/entities/cloud_binding.dart';
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
/// Không có API nào gắn ví chỉ từ phiên Firebase. P8.1 chưa có đường production nào
/// gọi các hàm ghi — luồng claim/backend thuộc P8.2.
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
  Future<void> activate({
    required String claimRequestId,
    int? cryptoVersion,
    int? keyringRev,
  }) => _db.transaction(() async {
    final current = await read();
    if (current == null ||
        current.state != CloudBindingState.claiming ||
        current.claimRequestId != claimRequestId) {
      throw const CloudBindingException('not-claiming');
    }
    await _db.update(_db.cloudBinding).write(
      CloudBindingCompanion(
        state: const Value('ACTIVE'),
        cryptoVersion: Value(cryptoVersion),
        keyringRev: Value(keyringRev),
        updatedAt: Value(DateTime.now()),
      ),
    );
  });

  /// Huỷ claim đang dở (CLAIMING → NONE). Không đụng ví ACTIVE.
  Future<void> abandonClaim() => _db.transaction(() async {
    if ((await state()) != CloudBindingState.claiming) {
      throw const CloudBindingException('not-claiming');
    }
    await _db.delete(_db.cloudBinding).go();
  });
}
