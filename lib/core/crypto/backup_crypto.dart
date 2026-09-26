import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// P8 zero-knowledge backup primitives (cryptoVersion 1).
///
/// Key hierarchy: a random 256-bit Wallet Backup Master Key (BMK) is a ROOT key
/// only — never used directly to encrypt; HKDF derives the DEK/IDK. The Backup
/// Password (Argon2id) and the Recovery Key (HKDF) each derive an independent
/// KEK + device-takeover credential. Both KEKs wrap the SAME BMK. Nothing here ever logs or stringifies
/// secret material; [toString] of every secret-holding type is redacted.
abstract final class BackupCrypto {
  static const cryptoVersion = 1;
  static final _random = Random.secure();
  static final _aes = DartAesGcm.with256bits();
  static final _hkdf = DartHkdf(hmac: DartHmac.sha256(), outputLength: 32);

  static Uint8List randomBytes(int length) =>
      Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

  /// Secure-random 256-bit BMK.
  static Uint8List newBmk() => randomBytes(32);

  static Future<Uint8List> hkdf(
    List<int> ikm, {
    List<int> salt = const [],
    required String info,
  }) async {
    final key = await _hkdf.deriveKey(
      secretKey: SecretKeyData(ikm),
      nonce: salt,
      info: utf8.encode(info),
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  static Future<Uint8List> argon2id(
    List<int> password,
    List<int> salt,
    KdfParams params, {
    List<int> secret = const [],
    List<int> associatedData = const [],
    int hashLength = 32,
  }) async {
    final key = await DartArgon2id(
      parallelism: params.parallelism,
      memory: params.memoryKib,
      iterations: params.iterations,
      hashLength: hashLength,
    ).deriveKey(
      secretKey: SecretKeyData(password),
      nonce: salt,
      optionalSecret: secret,
      associatedData: associatedData,
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  // Domain-separated labels. One key never serves two purposes: KEKs only
  // wrap the BMK; takeover credentials only authenticate lost-device recovery;
  // DEK/IDK (envelope_cipher.dart) only encrypt data / derive opaque ids.
  static const passwordKekLabel = 'vinhaminh-backup-password-kek-v1';
  static const passwordTakeoverLabel = 'vinhaminh-device-takeover-password-v1';
  static const recoveryKekLabel = 'vinhaminh-backup-recovery-v1';
  static const recoveryTakeoverLabel = 'vinhaminh-device-takeover-v1';

  static String _token(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  /// Password pre-processing, versioned in KDF metadata (`norm: 'NFC'`):
  /// Unicode NFC only — no trim, no case folding, no NFKC. Composed and
  /// decomposed Vietnamese input (e.g. "ệ" vs "e"+U+0323+U+0302) are equal.
  static List<int> passwordBytes(String password) =>
      utf8.encode(unorm.nfc(password));

  /// Backup Password → NFC → UTF-8 → Argon2id root (salted, versioned params)
  /// → domain-separated HKDF into an independent KEK and an independent
  /// takeover credential. The takeover credential is NEVER derived from the
  /// raw password by a fast hash — only from the Argon2id root.
  static Future<KeySlotSecrets> fromPassword(
    String password,
    List<int> salt,
    KdfParams params,
  ) async {
    final root = await argon2id(passwordBytes(password), salt, params);
    return KeySlotSecrets._(
      await hkdf(root, info: passwordKekLabel),
      _token(await hkdf(root, info: passwordTakeoverLabel)),
    );
  }

  /// Recovery Secret (256 random bits) → HKDF (slow KDF unnecessary). The
  /// Recovery Key itself is never sent anywhere; the server only ever sees
  /// the takeover credential (and stores SHA-256 of it), from which neither
  /// the Recovery Secret, the Recovery KEK, the BMK nor the DEK can be derived.
  static Future<KeySlotSecrets> fromRecoveryKey(
    RecoveryKey key,
    List<int> salt,
  ) async => KeySlotSecrets._(
    await hkdf(key._bytes, salt: salt, info: recoveryKekLabel),
    _token(await hkdf(key._bytes, salt: salt, info: recoveryTakeoverLabel)),
  );

  static List<int> _wrapAad(String walletId, String slot) =>
      utf8.encode('vinhaminh-bmk-wrap|v1|$walletId|$slot');

  /// Wraps [bmk] with AES-256-GCM under a fresh random nonce.
  static Future<WrappedKeySlot> wrap({
    required Uint8List bmk,
    required KeySlotSecrets secrets,
    required List<int> salt,
    required Map<String, Object> kdf,
    required String walletId,
    required String slot,
  }) async {
    final box = await _aes.encrypt(
      bmk,
      secretKey: SecretKeyData(secrets._wrapKey),
      nonce: _aes.newNonce(),
      aad: _wrapAad(walletId, slot),
    );
    return WrappedKeySlot(
      salt: Uint8List.fromList(salt),
      kdf: kdf,
      nonce: Uint8List.fromList(box.nonce),
      wrapped: Uint8List.fromList([...box.cipherText, ...box.mac.bytes]),
    );
  }

  /// Throws [BackupKeyException] on a wrong password/Recovery Key or tampering.
  static Future<Uint8List> unwrap({
    required WrappedKeySlot slot,
    required KeySlotSecrets secrets,
    required String walletId,
    required String slotName,
  }) async {
    if (slot.wrapped.length != 48) throw const BackupKeyException();
    try {
      final clear = await _aes.decrypt(
        SecretBox(
          slot.wrapped.sublist(0, 32),
          nonce: slot.nonce,
          mac: Mac(slot.wrapped.sublist(32)),
        ),
        secretKey: SecretKeyData(secrets._wrapKey),
        aad: _wrapAad(walletId, slotName),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const BackupKeyException();
    }
  }
}

/// Wrong password / Recovery Key / tampered material. Carries no detail.
class BackupKeyException implements Exception {
  const BackupKeyException();
  @override
  String toString() => 'BackupKeyException';
}

/// Versioned Argon2id parameters (stored beside each wrapped slot).
class KdfParams {
  const KdfParams({
    required this.memoryKib,
    required this.iterations,
    required this.parallelism,
  });

  /// RFC 9106 §4 second recommendation (64 MiB, t=3, p=4).
  static const v1 = KdfParams(memoryKib: 65536, iterations: 3, parallelism: 4);
  final int memoryKib;
  final int iterations;
  final int parallelism;

  Map<String, Object> toJson() => {
    'alg': 'argon2id',
    'v': 19,
    'm': memoryKib,
    't': iterations,
    'p': parallelism,
    'norm': passwordNormalization,
  };

  /// Only supported password pre-processing (versioned with the slot).
  static const passwordNormalization = 'NFC';

  static KdfParams fromJson(Map<String, Object?> json) {
    if (json['alg'] != 'argon2id' ||
        json['v'] != 19 ||
        json['norm'] != passwordNormalization) {
      throw const BackupKeyException();
    }
    final m = json['m'], t = json['t'], p = json['p'];
    if (m is! int || t is! int || p is! int) throw const BackupKeyException();
    final params = KdfParams(memoryKib: m, iterations: t, parallelism: p);
    // Refuse downgraded parameters served by a malicious backend.
    if (params.memoryKib < 19456 || params.iterations < 2 || params.parallelism < 1) {
      throw const BackupKeyException();
    }
    return params;
  }
}

/// Derived wrapping key + session recovery proof for one slot. Redacted.
class KeySlotSecrets {
  KeySlotSecrets._(this._wrapKey, this.proof);
  final Uint8List _wrapKey;

  /// base64url(43) proof for P7.1 lost-device recovery. The server stores only
  /// SHA-256(proof); it is HKDF-independent of the wrapping key.
  final String proof;
  @override
  String toString() => 'KeySlotSecrets(<redacted>)';
}

class WrappedKeySlot {
  const WrappedKeySlot({
    required this.salt,
    required this.kdf,
    required this.nonce,
    required this.wrapped,
  });
  final Uint8List salt;
  final Map<String, Object> kdf;
  final Uint8List nonce;
  final Uint8List wrapped;

  Map<String, Object> toJson() => {
    'salt': base64.encode(salt),
    'kdf': kdf,
    'nonce': base64.encode(nonce),
    'wrapped': base64.encode(wrapped),
  };

  static WrappedKeySlot fromJson(Map<String, Object?> json) => WrappedKeySlot(
    salt: base64.decode(json['salt']! as String),
    kdf: Map<String, Object>.from(json['kdf']! as Map),
    nonce: base64.decode(json['nonce']! as String),
    wrapped: base64.decode(json['wrapped']! as String),
  );
}

/// 256-bit Recovery Key, shown once as `HW1-XXXX-…` (Crockford base32 + a
/// 20-bit SHA-256 checksum group to catch typos). Never logged or uploaded.
class RecoveryKey {
  RecoveryKey._(this._bytes);
  final Uint8List _bytes;
  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  static RecoveryKey generate() => RecoveryKey._(BackupCrypto.randomBytes(32));

  static String _base32(List<int> bytes, int chars) {
    var bits = BigInt.zero;
    for (final b in bytes) {
      bits = (bits << 8) | BigInt.from(b);
    }
    final totalBits = chars * 5;
    bits <<= totalBits - bytes.length * 8;
    final out = StringBuffer();
    for (var i = chars - 1; i >= 0; i--) {
      out.write(_alphabet[((bits >> (i * 5)) & BigInt.from(31)).toInt()]);
    }
    return out.toString();
  }

  static Future<String> _checksum(List<int> bytes) async {
    final d = (await const DartSha256().hash(bytes)).bytes;
    final value = (d[0] << 12) | (d[1] << 4) | (d[2] >> 4);
    return [for (var i = 3; i >= 0; i--) _alphabet[(value >> (i * 5)) & 31]].join();
  }

  /// Human format. Call once for the one-time display; never persist.
  Future<String> display() async {
    final body = _base32(_bytes, 52) + await _checksum(_bytes);
    final groups = [
      for (var i = 0; i < body.length; i += 4) body.substring(i, i + 4),
    ];
    return 'HW1-${groups.join('-')}';
  }

  /// Accepts spaces/hyphens/lowercase and Crockford aliases (O→0, I/L→1).
  static Future<RecoveryKey> parse(String input) async {
    var text = input.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (text.startsWith('HW1')) text = text.substring(3);
    text = text.replaceAll('O', '0').replaceAll(RegExp('[IL]'), '1');
    if (text.length != 56 || text.split('').any((c) => !_alphabet.contains(c))) {
      throw const FormatException('recovery-key-format');
    }
    var bits = BigInt.zero;
    for (final c in text.substring(0, 52).split('')) {
      bits = (bits << 5) | BigInt.from(_alphabet.indexOf(c));
    }
    if ((bits & BigInt.from(15)) != BigInt.zero) {
      throw const FormatException('recovery-key-format');
    }
    bits >>= 4;
    final bytes = Uint8List(32);
    for (var i = 31; i >= 0; i--) {
      bytes[i] = (bits & BigInt.from(255)).toInt();
      bits >>= 8;
    }
    if (await _checksum(bytes) != text.substring(52)) {
      throw const FormatException('recovery-key-checksum');
    }
    return RecoveryKey._(bytes);
  }

  @override
  String toString() => 'RecoveryKey(<redacted>)';
}
