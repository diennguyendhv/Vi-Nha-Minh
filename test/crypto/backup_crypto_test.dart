import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/crypto/backup_crypto.dart';
import 'package:vi_nha_minh/core/crypto/envelope_cipher.dart';

List<int> hex(String s) => [
  for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16),
];
String toHex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// Test-only cheap parameters (production uses [KdfParams.v1]).
const fast = KdfParams(memoryKib: 19456, iterations: 2, parallelism: 1);
const walletId = 'fixture-0123456789';

void main() {
  group('official vectors', () {
    test('Argon2id RFC 9106 §5.3', () async {
      final tag = await BackupCrypto.argon2id(
        List.filled(32, 1),
        List.filled(16, 2),
        const KdfParams(memoryKib: 32, iterations: 3, parallelism: 4),
        secret: List.filled(8, 3),
        associatedData: List.filled(12, 4),
      );
      expect(
        toHex(tag),
        '0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659',
      );
    });
    test('HKDF-SHA256 RFC 5869 test case 1', () async {
      final okm = await DartHkdf(hmac: DartHmac.sha256(), outputLength: 42)
          .deriveKey(
            secretKey: SecretKeyData(List.filled(22, 0x0b)),
            nonce: hex('000102030405060708090a0b0c'),
            info: hex('f0f1f2f3f4f5f6f7f8f9'),
          );
      expect(
        toHex(await okm.extractBytes()),
        '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf'
        '34007208d5b887185865',
      );
    });
    test('AES-256-GCM (McGrew–Viega GCM spec test case 16)', () async {
      final box = await DartAesGcm.with256bits().encrypt(
        hex(
          'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72'
          '1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39',
        ),
        secretKey: SecretKeyData(
          hex(
            'feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308',
          ),
        ),
        nonce: hex('cafebabefacedbaddecaf888'),
        aad: hex('feedfacedeadbeeffeedfacedeadbeefabaddad2'),
      );
      expect(
        toHex(box.cipherText),
        '522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa'
        '8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662',
      );
      expect(toHex(box.mac.bytes), '76fc6ece0f4e1768cddf8853bb2d551b');
    });
  });

  group('key hierarchy', () {
    test('BMK is 256-bit secure random and never repeats', () {
      final keys = {for (var i = 0; i < 64; i++) toHex(BackupCrypto.newBmk())};
      expect(keys.length, 64);
      expect(keys.every((k) => k.length == 64), isTrue);
    });

    test('password derivation deterministic for same salt/settings', () async {
      final salt = List.filled(16, 7);
      final a = await BackupCrypto.fromPassword('mật khẩu đúng', salt, fast);
      final b = await BackupCrypto.fromPassword('mật khẩu đúng', salt, fast);
      final c = await BackupCrypto.fromPassword(
        'mật khẩu đúng',
        List.filled(16, 8),
        fast,
      );
      expect(a.proof, b.proof);
      expect(a.proof, isNot(c.proof));
      expect(a.proof.length, 43);
      expect(a.toString(), isNot(contains(a.proof)));
    });

    Future<({Uint8List bmk, WrappedKeySlot pw, WrappedKeySlot rc, RecoveryKey rk})>
    setup(String password) async {
      final bmk = BackupCrypto.newBmk();
      final pwSalt = BackupCrypto.randomBytes(16);
      final rcSalt = BackupCrypto.randomBytes(32);
      final rk = RecoveryKey.generate();
      final pw = await BackupCrypto.wrap(
        bmk: bmk,
        secrets: await BackupCrypto.fromPassword(password, pwSalt, fast),
        salt: pwSalt,
        kdf: fast.toJson(),
        walletId: walletId,
        slot: 'password',
      );
      final rc = await BackupCrypto.wrap(
        bmk: bmk,
        secrets: await BackupCrypto.fromRecoveryKey(rk, rcSalt),
        salt: rcSalt,
        kdf: {'alg': 'hkdf-sha256'},
        walletId: walletId,
        slot: 'recovery',
      );
      return (bmk: bmk, pw: pw, rc: rc, rk: rk);
    }

    Future<Uint8List> unwrapPw(WrappedKeySlot s, String password) async =>
        BackupCrypto.unwrap(
          slot: s,
          secrets: await BackupCrypto.fromPassword(
            password,
            s.salt,
            KdfParams.fromJson(s.kdf),
          ),
          walletId: walletId,
          slotName: 'password',
        );

    test('right password unwraps; wrong password cannot', () async {
      final k = await setup('correct horse');
      expect(await unwrapPw(k.pw, 'correct horse'), k.bmk);
      await expectLater(
        unwrapPw(k.pw, 'correct hors3'),
        throwsA(isA<BackupKeyException>()),
      );
      // Slot bound to wallet + slot name via AAD.
      await expectLater(
        BackupCrypto.unwrap(
          slot: k.pw,
          secrets: await BackupCrypto.fromPassword(
            'correct horse',
            k.pw.salt,
            fast,
          ),
          walletId: 'fixture-other-wallet',
          slotName: 'password',
        ),
        throwsA(isA<BackupKeyException>()),
      );
    });

    test('Recovery Key unwraps the same BMK; wrong key cannot', () async {
      final k = await setup('pw');
      final display = await k.rk.display();
      expect(display, matches(RegExp(r'^HW1(-[0-9A-HJKMNP-TV-Z]{4}){14}$')));
      final parsed = await RecoveryKey.parse(
        display.toLowerCase().replaceAll('-', ' '),
      );
      Future<Uint8List> open(RecoveryKey key) async => BackupCrypto.unwrap(
        slot: k.rc,
        secrets: await BackupCrypto.fromRecoveryKey(key, k.rc.salt),
        walletId: walletId,
        slotName: 'recovery',
      );
      expect(await open(parsed), k.bmk);
      await expectLater(
        open(RecoveryKey.generate()),
        throwsA(isA<BackupKeyException>()),
      );
      // A one-character typo is caught by the checksum before any unwrap.
      final typo = display.replaceRange(
        5,
        6,
        display[5] == 'A' ? 'B' : 'A',
      );
      await expectLater(
        RecoveryKey.parse(typo),
        throwsA(isA<FormatException>()),
      );
      expect(k.rk.toString(), isNot(contains(display.substring(4, 8))));
    });

    test('password change re-wraps the SAME BMK; recovery slot untouched', () async {
      final k = await setup('old password');
      final bmk = await unwrapPw(k.pw, 'old password');
      final newSalt = BackupCrypto.randomBytes(16);
      final rewrapped = await BackupCrypto.wrap(
        bmk: bmk,
        secrets: await BackupCrypto.fromPassword('new password', newSalt, fast),
        salt: newSalt,
        kdf: fast.toJson(),
        walletId: walletId,
        slot: 'password',
      );
      expect(await unwrapPw(rewrapped, 'new password'), k.bmk);
      await expectLater(
        unwrapPw(rewrapped, 'old password'),
        throwsA(isA<BackupKeyException>()),
      );
    });

    test('NFC: composed/decomposed Vietnamese derive the same keys', () async {
      final salt = List.filled(16, 5);
      // "Mật khẩu Tiệm" precomposed vs fully decomposed (base + combining marks).
      const composed = 'Mật khẩu Tiệm';
      const decomposed = 'Mật khẩu Tiệm';
      expect(composed == decomposed, isFalse);
      expect(utf8.encode(composed), isNot(utf8.encode(decomposed)));
      final a = await BackupCrypto.fromPassword(composed, salt, fast);
      final b = await BackupCrypto.fromPassword(decomposed, salt, fast);
      expect(a.proof, b.proof);
      // Wrapped with one form, unwrapped with the other.
      final bmk = BackupCrypto.newBmk();
      final slot = await BackupCrypto.wrap(bmk: bmk, secrets: a, salt: salt,
          kdf: fast.toJson(), walletId: walletId, slot: 'password');
      expect(await BackupCrypto.unwrap(slot: slot, secrets: b, walletId: walletId,
          slotName: 'password'), bmk);
      expect(fast.toJson()['norm'], 'NFC');
    });

    test('case and whitespace stay significant (no trim, no case fold, no NFKC)', () async {
      final salt = List.filled(16, 6);
      final base = (await BackupCrypto.fromPassword('Mật khẩu 1', salt, fast)).proof;
      for (final variant in ['mật khẩu 1', 'MẬT KHẨU 1', ' Mật khẩu 1', 'Mật khẩu 1 ',
          'Mật  khẩu 1', 'Mật khẩu １']) {
        expect((await BackupCrypto.fromPassword(variant, salt, fast)).proof,
            isNot(base), reason: variant);
      }
    });

    test('password takeover credential = HKDF(Argon2id(NFC(pw))), never a fast hash', () async {
      final salt = List.filled(16, 3);
      const pw = 'Tiện chợ 2026';
      final got = (await BackupCrypto.fromPassword(pw, salt, fast)).proof;
      final root = await BackupCrypto.argon2id(
        utf8.encode('Tiện chợ 2026'), salt, fast);
      final expected = base64Url.encode(await BackupCrypto.hkdf(root,
          info: BackupCrypto.passwordTakeoverLabel)).replaceAll('=', '');
      expect(got, expected);
      final fastHash = base64Url.encode(await BackupCrypto.hkdf(
          BackupCrypto.passwordBytes(pw), salt: salt,
          info: BackupCrypto.passwordTakeoverLabel)).replaceAll('=', '');
      expect(got, isNot(fastHash));
      final kek = await BackupCrypto.hkdf(root, info: BackupCrypto.passwordKekLabel);
      expect(got, isNot(base64Url.encode(kek).replaceAll('=', '')));
    });

    test('KDF metadata without NFC version is refused', () {
      expect(() => KdfParams.fromJson({'alg': 'argon2id', 'v': 19, 'm': 65536, 't': 3, 'p': 4}),
          throwsA(isA<BackupKeyException>()));
    });

    test('downgraded KDF params from server are refused', () {
      expect(
        () => KdfParams.fromJson({'alg': 'argon2id', 'v': 19, 'm': 8, 't': 1, 'p': 1}),
        throwsA(isA<BackupKeyException>()),
      );
    });
  });

  group('envelope', () {
    final body = {'amount': 1234567, 'note': 'Tiền chợ bí mật', 'category': 'Ăn uống'};

    test('round trip, opaque id, fresh nonce each seal', () async {
      final cipher = await EnvelopeCipher.create(BackupCrypto.newBmk(), walletId);
      final a = await cipher.seal(kind: 'transaction', localId: 'tx-1', rev: 1, body: body);
      final b = await cipher.seal(kind: 'transaction', localId: 'tx-1', rev: 1, body: body);
      expect(a.id, b.id);
      expect(a.id, isNot(contains('tx-1')));
      expect(a.nonce, isNot(b.nonce));
      expect(a.ciphertext, isNot(b.ciphertext));
      final opened = await cipher.open(Envelope.fromJson(a.toJson()));
      expect([opened.kind, opened.localId, opened.rev], ['transaction', 'tx-1', 1]);
      expect(opened.body, body);
      final json = jsonEncode(a.toJson());
      for (final plain in ['1234567', 'Tiền', 'chợ', 'Ăn uống', 'amount', 'note', 'tx-1', 'transaction', 'kind']) {
        expect(json.contains(plain), isFalse, reason: plain);
      }
      expect(a.toJson().keys.toSet(), {'v', 'id', 'rev', 'n', 'c', 'aad'});
    });

    test('tampered ciphertext / nonce / AAD metadata rejected', () async {
      final bmk = BackupCrypto.newBmk();
      final cipher = await EnvelopeCipher.create(bmk, walletId);
      final e = await cipher.seal(kind: 'transaction', localId: 'tx-1', rev: 3, body: body);
      final other = await cipher.seal(kind: 'transaction', localId: 'tx-2', rev: 3, body: body);
      final bytes = base64.decode(e.ciphertext);
      bytes[0] ^= 1;
      final variants = [
        Envelope(id: e.id, rev: e.rev, nonce: e.nonce, ciphertext: base64.encode(bytes)),
        Envelope(id: e.id, rev: 4, nonce: e.nonce, ciphertext: e.ciphertext),
        Envelope(id: other.id, rev: e.rev, nonce: e.nonce, ciphertext: e.ciphertext),
        Envelope(id: 'A' * 43, rev: e.rev, nonce: e.nonce, ciphertext: e.ciphertext),
        Envelope(id: e.id, rev: e.rev, nonce: base64.encode(List.filled(12, 0)), ciphertext: e.ciphertext),
      ];
      for (final v in variants) {
        await expectLater(cipher.open(v), throwsA(isA<BackupKeyException>()));
      }
      // Same BMK, different wallet: moving ciphertext across wallets fails.
      final otherWallet = await EnvelopeCipher.create(bmk, 'fixture-other-wallet');
      await expectLater(otherWallet.open(e), throwsA(isA<BackupKeyException>()));
      expect(cipher.toString(), 'EnvelopeCipher(<redacted>)');
    });
  });

  test('key separation: BMK never encrypts directly; labels independent', () async {
    final bmk = BackupCrypto.newBmk();
    final cipher = await EnvelopeCipher.create(bmk, walletId);
    final e = await cipher.seal(kind: 'fund', localId: 'f1', rev: 1, body: {'x': 1});
    final raw = base64.decode(e.ciphertext);
    await expectLater(
      DartAesGcm.with256bits().decrypt(
        SecretBox(raw.sublist(0, raw.length - 16), nonce: base64.decode(e.nonce), mac: Mac(raw.sublist(raw.length - 16))),
        secretKey: SecretKeyData(bmk),
        aad: utf8.encode('vinhaminh-env|v1|s1|$walletId|${e.id}'),
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    final labels = [
      EnvelopeCipher.dekLabel,
      EnvelopeCipher.idkLabel,
      BackupCrypto.passwordKekLabel,
      BackupCrypto.passwordTakeoverLabel,
      BackupCrypto.recoveryKekLabel,
      BackupCrypto.recoveryTakeoverLabel,
    ];
    expect(labels.toSet().length, labels.length);
    final derived = {for (final l in labels) toHex(await BackupCrypto.hkdf(bmk, info: l))};
    expect(derived.length, labels.length);
    expect(derived.contains(toHex(bmk)), isFalse);
  });

  test('Recovery Key: takeover credential independent of Recovery KEK', () async {
    final rk = RecoveryKey.generate();
    final salt = BackupCrypto.randomBytes(32);
    final a = await BackupCrypto.fromRecoveryKey(rk, salt);
    final display = await rk.display();
    // The credential sent to the server is neither the key nor anything
    // resembling it, and differs from the password-slot credential.
    final body = display.replaceAll('-', '').substring(3);
    expect(a.proof.contains(body.substring(0, 8)), isFalse);
    final pw = await BackupCrypto.fromPassword('pw-x', salt.sublist(0, 16), fast);
    expect(a.proof, isNot(pw.proof));
    // A slot wrapped under the takeover credential's bytes cannot be opened with
    // the KEK and vice versa is implied by HKDF label separation (tested above).
    expect(a.proof, (await BackupCrypto.fromRecoveryKey(rk, salt)).proof);
    expect(a.proof, isNot((await BackupCrypto.fromRecoveryKey(rk, BackupCrypto.randomBytes(32))).proof));
  });

  test('production KDF cost (informational timing)', () async {
    final sw = Stopwatch()..start();
    await BackupCrypto.fromPassword('timing only', List.filled(16, 1), KdfParams.v1);
    // ignore: avoid_print
    print('Argon2id v1 (64 MiB, t=3, p=4) host: ${sw.elapsedMilliseconds} ms');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
