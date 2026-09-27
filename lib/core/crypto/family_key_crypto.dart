import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'backup_crypto.dart';

/// Mọi thứ 1 gói khoá Family được GẮN vào (AEAD context). Owner dựng nó từ lựa chọn
/// của CHÍNH mình (memberId) + dữ liệu người nhận đã đối chiếu vân tay; Member dựng lại
/// từ danh tính của chính mình. Sai 1 trường bất kỳ ⇒ mở gói thất bại.
class FamilyKeyContext {
  const FamilyKeyContext({
    required this.walletId,
    required this.ownerAccountId,
    required this.recipientAccountId,
    required this.recipientMemberId,
    required this.recipientInstallationId,
    required this.recipientPublicKey,
  });
  final String walletId;
  final String ownerAccountId;
  final String recipientAccountId;
  final String recipientMemberId;
  final String recipientInstallationId;

  /// X25519 public key (32 byte) của THIẾT BỊ người nhận.
  final Uint8List recipientPublicKey;

  String get _encoded => [
    FamilyKeyCrypto.version,
    walletId,
    ownerAccountId,
    recipientAccountId,
    recipientMemberId,
    recipientInstallationId,
    base64.encode(recipientPublicKey),
  ].join('|');
}

/// Khoá thiết bị Family (X25519). Private key chỉ nằm trong bộ nhớ khi dùng; lưu bền
/// qua Keystore ([FamilyDeviceKeyStore]). Redacted.
class FamilyDeviceKey {
  FamilyDeviceKey._(this._seed, this.publicKey);
  final Uint8List _seed;
  final Uint8List publicKey;

  static final _x25519 = DartX25519();

  static Future<FamilyDeviceKey> generate() =>
      fromSeed(BackupCrypto.randomBytes(32));

  static Future<FamilyDeviceKey> fromSeed(List<int> seed) async {
    if (seed.length != 32) throw const BackupKeyException();
    final pair = await _x25519.newKeyPairFromSeed(seed);
    final pub = await pair.extractPublicKey();
    return FamilyDeviceKey._(
      Uint8List.fromList(seed),
      Uint8List.fromList(pub.bytes),
    );
  }

  /// Chỉ để lưu vào Keystore. Không log/không hiển thị.
  Uint8List seedForStorage() => Uint8List.fromList(_seed);

  @override
  String toString() => 'FamilyDeviceKey(<redacted>)';
}

/// P10 — chia sẻ BMK zero-knowledge giữa Owner và Member (cryptoVersion 1).
///
/// Cấu trúc ECIES chuẩn (tương tự HPKE base mode, không tự chế nguyên thuỷ):
/// X25519 (khoá tạm của Owner × khoá thiết bị Member) → HKDF-SHA256 (salt = epk ‖
/// pkR, info = nhãn tách miền ‖ context) → AES-256-GCM(BMK, AAD = context). Máy chủ
/// chỉ thấy `{v, epk, n, c}` + public key: không có khoá nào mở được BMK. Context gắn
/// walletId, Owner, Account người nhận, memberId, installation và public key — máy chủ
/// không thể chuyển gói sang người nhận/thiết bị khác, cũng không đổi vai trò.
///
/// Chống máy chủ đánh tráo public key: Owner chỉ bọc SAU khi 2 người đối chiếu
/// [fingerprint] (máy Member tự tính từ khoá của chính nó). Chống đánh tráo BMK/ví:
/// [walletCode] (cam kết BMK) hiện trên cả 2 máy.
abstract final class FamilyKeyCrypto {
  static const version = 'vinhaminh-family-bmk-share-v1';
  static const _kekLabel = 'vinhaminh-family-bmk-kek-v1';
  static const _fingerprintLabel = 'vinhaminh-family-fingerprint-v1';
  static const _commitLabel = 'vinhaminh-family-bmk-commit-v1';
  static final _x25519 = DartX25519();
  static final _aes = DartAesGcm.with256bits();

  static Future<Uint8List> _kek(
    List<int> shared,
    List<int> epk,
    FamilyKeyContext ctx,
  ) async {
    // Khoá chung toàn 0 = public key bậc thấp (không đóng góp) ⇒ từ chối.
    if (shared.every((b) => b == 0)) throw const BackupKeyException();
    return BackupCrypto.hkdf(
      shared,
      salt: [...epk, ...ctx.recipientPublicKey],
      info: '$_kekLabel|${ctx._encoded}',
    );
  }

  /// Owner: bọc [bmk] cho đúng [ctx]. Khoá tạm mới mỗi lần, nonce sinh nội bộ.
  static Future<Map<String, Object>> wrapBmk(
    Uint8List bmk,
    FamilyKeyContext ctx,
  ) async {
    if (bmk.length != 32 || ctx.recipientPublicKey.length != 32) {
      throw ArgumentError('Invalid family key input');
    }
    final eph = await _x25519.newKeyPair();
    final epk = (await eph.extractPublicKey()).bytes;
    final shared = await (await _x25519.sharedSecretKey(
      keyPair: eph,
      remotePublicKey: SimplePublicKey(
        ctx.recipientPublicKey,
        type: KeyPairType.x25519,
      ),
    )).extractBytes();
    final box = await _aes.encrypt(
      bmk,
      secretKey: SecretKeyData(await _kek(shared, epk, ctx)),
      nonce: _aes.newNonce(),
      aad: utf8.encode(ctx._encoded),
    );
    return {
      'v': 1,
      'epk': base64.encode(epk),
      'n': base64.encode(box.nonce),
      'c': base64.encode([...box.cipherText, ...box.mac.bytes]),
    };
  }

  /// Member: mở gói bằng khoá thiết bị của chính mình. Sai khoá / sai context / bị sửa
  /// ⇒ [BackupKeyException] (không chi tiết).
  static Future<Uint8List> unwrapBmk(
    Map<String, Object?> wrapped,
    FamilyKeyContext ctx,
    FamilyDeviceKey device,
  ) async {
    try {
      if (wrapped['v'] != 1) throw const BackupKeyException();
      if (!_same(device.publicKey, ctx.recipientPublicKey)) {
        throw const BackupKeyException();
      }
      final epk = base64.decode(wrapped['epk']! as String);
      final nonce = base64.decode(wrapped['n']! as String);
      final c = base64.decode(wrapped['c']! as String);
      if (epk.length != 32 || nonce.length != 12 || c.length != 48) {
        throw const BackupKeyException();
      }
      final pair = await _x25519.newKeyPairFromSeed(device._seed);
      final shared = await (await _x25519.sharedSecretKey(
        keyPair: pair,
        remotePublicKey: SimplePublicKey(epk, type: KeyPairType.x25519),
      )).extractBytes();
      final clear = await _aes.decrypt(
        SecretBox(c.sublist(0, 32), nonce: nonce, mac: Mac(c.sublist(32))),
        secretKey: SecretKeyData(await _kek(shared, epk, ctx)),
        aad: utf8.encode(ctx._encoded),
      );
      return Uint8List.fromList(clear);
    } on BackupKeyException {
      rethrow;
    } on Object {
      throw const BackupKeyException();
    }
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static Future<String> _digits(List<int> input) async {
    final d = (await const DartSha256().hash(input)).bytes;
    // 48 bit ⇒ 12 chữ số thập phân (xác suất trùng ngẫu nhiên ≈ 1e-12).
    var v = BigInt.zero;
    for (final b in d.take(6)) {
      v = (v << 8) | BigInt.from(b);
    }
    final s = (v % BigInt.from(10).pow(12)).toString().padLeft(12, '0');
    return '${s.substring(0, 4)} ${s.substring(4, 8)} ${s.substring(8)}';
  }

  /// Vân tay người nhận: Owner tính từ dữ liệu máy chủ đưa, Member tính từ khoá CỦA
  /// CHÍNH MÌNH. 2 màn hình phải trùng thì Owner mới bọc khoá.
  static Future<String> fingerprint(FamilyKeyContext ctx) =>
      _digits(utf8.encode('$_fingerprintLabel|${ctx._encoded}'));

  /// Mã ví = cam kết BMK (HKDF 1 chiều, không lộ BMK/DEK). Trùng trên 2 máy ⇒ Member
  /// nhận đúng BMK của Owner (không phải khoá/ví do máy chủ dựng).
  static Future<String> walletCode(Uint8List bmk, String walletId) async =>
      _digits(await BackupCrypto.hkdf(bmk, info: '$_commitLabel|$walletId'));
}
