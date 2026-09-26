import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'backup_crypto.dart';

/// Entity kinds known to the client. They live INSIDE the ciphertext; the
/// server never learns whether an object is a transaction, fund, savings…
const envelopeKinds = {
  'transaction',
  'category',
  'status',
  'fund',
  'savingsAsset',
  'member',
  'walletMeta',
  'counterparty',
  'obligation',
  // P8.3: real Wallet tables (`syncCapturedTables`) + the encrypted manifest.
  'savingsAssetType',
  'financialMember',
  'walletSetting',
  'manifest',
};

/// Generic encrypted object, cryptoVersion 1 / payload schema 1.
/// Visible: opaque id, rev, nonce, ciphertext (+tag), version numbers.
/// AAD = `vinhaminh-env|v1|s1|walletId|id` — only stable context the client
/// knows at encryption time. Moving ciphertext to another wallet or entity
/// fails authentication; the client-allocated rev is also sealed INSIDE the
/// plaintext and checked on open, so a replayed older revision is detected.
class Envelope {
  const Envelope({
    required this.id,
    required this.rev,
    required this.nonce,
    required this.ciphertext,
  });
  final String id;
  final int rev;
  final String nonce;
  final String ciphertext;

  Map<String, Object> toJson() => {
    'v': BackupCrypto.cryptoVersion,
    'id': id,
    'rev': rev,
    'n': nonce,
    'c': ciphertext,
    'aad': 1,
  };

  static Envelope fromJson(Map<String, Object?> json) {
    if (json['v'] != 1 || json['aad'] != 1) throw const BackupKeyException();
    return Envelope(
      id: json['id']! as String,
      rev: json['rev']! as int,
      nonce: json['n']! as String,
      ciphertext: json['c']! as String,
    );
  }
}

class OpenedEntity {
  const OpenedEntity(this.kind, this.localId, this.rev, this.body);
  final String kind;
  final String localId;
  final int rev;
  final Map<String, Object?> body;
}

/// Seals/opens envelopes for one Wallet. There is deliberately NO nonce
/// parameter: every [seal] draws a fresh random 96-bit nonce internally.
class EnvelopeCipher {
  EnvelopeCipher._(this.walletId, this._dek, this._idk);
  final String walletId;
  final Uint8List _dek;
  final Uint8List _idk;
  static const dekLabel = 'vinhaminh-wallet-data-v1';
  static const idkLabel = 'vinhaminh-wallet-id-v1';
  static final _aes = DartAesGcm.with256bits();
  static final _walletId = RegExp(r'^[A-Za-z0-9_-]{8,64}$');

  /// BMK is a root key only: DEK and IDK are independent HKDF sub-keys.
  static Future<EnvelopeCipher> create(Uint8List bmk, String walletId) async {
    if (bmk.length != 32 || !_walletId.hasMatch(walletId)) {
      throw ArgumentError('Invalid backup key context');
    }
    return EnvelopeCipher._(
      walletId,
      await BackupCrypto.hkdf(bmk, info: dekLabel),
      await BackupCrypto.hkdf(bmk, info: idkLabel),
    );
  }

  /// Opaque, stable cloud id: HMAC-SHA256(IDK, kind ‖ localId). Neither the
  /// kind nor local ids such as legacy `vo`/`chong` reach the server.
  Future<String> opaqueId(String kind, String localId) async {
    final mac = await DartHmac.sha256().calculateMac(
      utf8.encode('$kind\u0000$localId'),
      secretKey: SecretKeyData(_idk),
    );
    return base64Url.encode(mac.bytes).replaceAll('=', '');
  }

  List<int> _aad(String id) => utf8.encode('vinhaminh-env|v1|s1|$walletId|$id');

  Future<Envelope> seal({
    required String kind,
    required String localId,
    required int rev,
    required Map<String, Object?> body,
  }) async {
    if (!envelopeKinds.contains(kind) || rev < 1) {
      throw ArgumentError('Invalid envelope metadata');
    }
    final id = await opaqueId(kind, localId);
    final box = await _aes.encrypt(
      utf8.encode(
        jsonEncode({'kind': kind, 'localId': localId, 'rev': rev, 'body': body}),
      ),
      secretKey: SecretKeyData(_dek),
      nonce: _aes.newNonce(),
      aad: _aad(id),
    );
    return Envelope(
      id: id,
      rev: rev,
      nonce: base64.encode(box.nonce),
      ciphertext: base64.encode([...box.cipherText, ...box.mac.bytes]),
    );
  }

  /// Throws [BackupKeyException] if ciphertext, nonce, wallet, id or rev were
  /// altered/swapped.
  Future<OpenedEntity> open(Envelope envelope) async {
    try {
      final bytes = base64.decode(envelope.ciphertext);
      if (bytes.length < 17) throw const BackupKeyException();
      final clear = await _aes.decrypt(
        SecretBox(
          bytes.sublist(0, bytes.length - 16),
          nonce: base64.decode(envelope.nonce),
          mac: Mac(bytes.sublist(bytes.length - 16)),
        ),
        secretKey: SecretKeyData(_dek),
        aad: _aad(envelope.id),
      );
      final inner = jsonDecode(utf8.decode(clear)) as Map<String, Object?>;
      final kind = inner['kind']! as String;
      final localId = inner['localId']! as String;
      if (inner['rev'] != envelope.rev ||
          await opaqueId(kind, localId) != envelope.id) {
        throw const BackupKeyException();
      }
      return OpenedEntity(
        kind,
        localId,
        envelope.rev,
        Map<String, Object?>.from(inner['body']! as Map),
      );
    } on BackupKeyException {
      rethrow;
    } on Object {
      throw const BackupKeyException();
    }
  }

  @override
  String toString() => 'EnvelopeCipher(<redacted>)';
}
