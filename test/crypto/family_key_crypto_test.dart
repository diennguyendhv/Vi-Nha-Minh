import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/crypto/backup_crypto.dart';
import 'package:vi_nha_minh/core/crypto/family_key_crypto.dart';

/// P10 — chia sẻ BMK zero-knowledge Owner → thiết bị Member.
void main() {
  late FamilyDeviceKey member;
  late Uint8List bmk;
  FamilyKeyContext ctx({
    String walletId = 'wallet-1234',
    String owner = 'uid-owner',
    String recipient = 'uid-member',
    String memberId = 'vo',
    String installation = '11111111-1111-4111-8111-111111111111',
    Uint8List? pub,
  }) => FamilyKeyContext(
    walletId: walletId,
    ownerAccountId: owner,
    recipientAccountId: recipient,
    recipientMemberId: memberId,
    recipientInstallationId: installation,
    recipientPublicKey: pub ?? member.publicKey,
  );

  setUp(() async {
    member = await FamilyDeviceKey.generate();
    bmk = BackupCrypto.newBmk();
  });

  test('Owner bọc → đúng thiết bị Member mở ra đúng BMK; gói chỉ có {v,epk,n,c}', () async {
    final wrapped = await FamilyKeyCrypto.wrapBmk(bmk, ctx());
    expect(wrapped.keys.toSet(), {'v', 'epk', 'n', 'c'});
    expect(base64.decode(wrapped['c']! as String).length, 48);
    // Không byte BMK nào nằm nguyên văn trong gói (cái máy chủ lưu).
    final visible = jsonEncode(wrapped);
    expect(visible.contains(base64.encode(bmk)), isFalse);
    expect(await FamilyKeyCrypto.unwrapBmk(wrapped, ctx(), member), bmk);
    // Khoá tạm mới mỗi lần ⇒ 2 gói khác nhau, cùng mở ra BMK.
    final again = await FamilyKeyCrypto.wrapBmk(bmk, ctx());
    expect(again['epk'], isNot(wrapped['epk']));
    expect(await FamilyKeyCrypto.unwrapBmk(again, ctx(), member), bmk);
  });

  test('máy chủ (có mọi thứ nó lưu) / khoá khác / thiết bị khác KHÔNG mở được', () async {
    final wrapped = await FamilyKeyCrypto.wrapBmk(bmk, ctx());
    final attacker = await FamilyDeviceKey.generate();
    // Khoá riêng sai (vd máy chủ tự sinh khoá): thất bại dù dùng đúng context.
    await expectLater(
      FamilyKeyCrypto.unwrapBmk(wrapped, ctx(), attacker),
      throwsA(isA<BackupKeyException>()),
    );
    await expectLater(
      FamilyKeyCrypto.unwrapBmk(wrapped, ctx(pub: attacker.publicKey), attacker),
      throwsA(isA<BackupKeyException>()),
    );
  });

  test('gói gắn walletId/Owner/người nhận/memberId/installation — đổi 1 trường là hỏng', () async {
    final wrapped = await FamilyKeyCrypto.wrapBmk(bmk, ctx());
    for (final wrong in [
      ctx(walletId: 'wallet-9999'),
      ctx(owner: 'uid-attacker'),
      ctx(recipient: 'uid-other'),
      ctx(memberId: 'chong'),
      ctx(installation: '22222222-2222-4222-8222-222222222222'),
    ]) {
      await expectLater(
        FamilyKeyCrypto.unwrapBmk(wrapped, wrong, member),
        throwsA(isA<BackupKeyException>()),
      );
    }
    // Sửa ciphertext / nonce / epk.
    for (final field in ['c', 'n', 'epk']) {
      final bytes = base64.decode(wrapped[field]! as String)..[0] ^= 1;
      await expectLater(
        FamilyKeyCrypto.unwrapBmk(
          {...wrapped, field: base64.encode(bytes)},
          ctx(),
          member,
        ),
        throwsA(isA<BackupKeyException>()),
      );
    }
  });

  test('public key bậc thấp (toàn 0) bị từ chối khi bọc', () async {
    await expectLater(
      FamilyKeyCrypto.wrapBmk(bmk, ctx(pub: Uint8List(32))),
      throwsA(anything),
    );
  });

  test('vân tay: 2 máy tính ra cùng mã; máy chủ đổi public key/người nhận ⇒ mã khác', () async {
    final a = await FamilyKeyCrypto.fingerprint(ctx());
    expect(a, matches(RegExp(r'^\d{4} \d{4} \d{4}$')));
    expect(await FamilyKeyCrypto.fingerprint(ctx()), a);
    final swapped = await FamilyDeviceKey.generate();
    expect(await FamilyKeyCrypto.fingerprint(ctx(pub: swapped.publicKey)), isNot(a));
    expect(await FamilyKeyCrypto.fingerprint(ctx(recipient: 'uid-x')), isNot(a));
    expect(await FamilyKeyCrypto.fingerprint(ctx(memberId: 'chong')), isNot(a));
    expect(
      await FamilyKeyCrypto.fingerprint(
        ctx(installation: '33333333-3333-4333-8333-333333333333'),
      ),
      isNot(a),
    );
  });

  test('mã ví = cam kết BMK: trùng khi cùng BMK, khác khi BMK/ví khác, không lộ BMK', () async {
    final code = await FamilyKeyCrypto.walletCode(bmk, 'wallet-1234');
    expect(await FamilyKeyCrypto.walletCode(Uint8List.fromList(bmk), 'wallet-1234'), code);
    expect(await FamilyKeyCrypto.walletCode(BackupCrypto.newBmk(), 'wallet-1234'), isNot(code));
    expect(await FamilyKeyCrypto.walletCode(bmk, 'wallet-5678'), isNot(code));
  });

  test('khoá thiết bị khôi phục từ seed (Keystore) ra đúng public key; toString không lộ', () async {
    final again = await FamilyDeviceKey.fromSeed(member.seedForStorage());
    expect(again.publicKey, member.publicKey);
    expect(member.toString(), 'FamilyDeviceKey(<redacted>)');
    final wrapped = await FamilyKeyCrypto.wrapBmk(bmk, ctx());
    expect(await FamilyKeyCrypto.unwrapBmk(wrapped, ctx(), again), bmk);
  });
}
