import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3_pkg;
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/seed_defaults.dart';
import 'package:vi_nha_minh/data/repositories/local_wallet_identity_repository.dart';
import 'package:vi_nha_minh/core/utils/opaque_id.dart';
import 'package:vi_nha_minh/domain/entities/wallet_identity.dart';
import 'package:vi_nha_minh/data/repositories/local_member_repository.dart';

/// P2 — schema v7 → v8: thêm `wallet_meta` (singleton) + `financial_member_rows`
/// (`vo`, `chong`) và KHÔNG đổi bất kỳ dòng cũ nào. Fixture "v7 thật": dựng DB hiện
/// tại (demo: có danh mục/trạng thái/quỹ/tiết kiệm), thêm giao dịch của CẢ Vợ và
/// Chồng (trạng thái null lẫn có, tiết kiệm, quỹ, hoàn tác), rồi BỎ 2 bảng mới và hạ
/// `user_version` về 7 — đúng shape v7 — và mở lại bằng AppDatabase để chạy nâng cấp thật.
void main() {
  TransactionRowsCompanion tx(
    String id,
    String type,
    String category,
    int amount, {
    String source = 'memberAvailable',
    String? sourceRef = 'vo',
    String destination = 'external',
    String? destinationRef,
    String? statusId,
    String? note,
    String? reversalOf,
    String? reversedBy,
    DateTime? date,
  }) => TransactionRowsCompanion.insert(
    id: id,
    type: type,
    categoryId: category,
    sourceKind: source,
    sourceRefId: Value(sourceRef),
    destinationKind: destination,
    destinationRefId: Value(destinationRef),
    amountMinor: amount,
    statusId: Value(statusId),
    note: Value(note ?? ''),
    transactionDate: date ?? DateTime(2026, 9, 5, 8, 30, 15),
    createdAt: DateTime(2026, 9, 5, 8, 31),
    clientTxId: 'client-$id',
    reversalOfTxId: Value(reversalOf),
    reversedByTxId: Value(reversedBy),
  );

  const oldTables = [
    'transaction_rows',
    'category_rows',
    'status_rows',
    'fund_rows',
    'savings_asset_type_rows',
    'counterparty_rows',
    'obligation_rows',
  ];

  /// Toàn bộ dòng của các bảng CŨ, để so sánh từng trường trước/sau.
  Future<Map<String, List<Map<String, Object?>>>> dumpOld(AppDatabase db) async {
    final out = <String, List<Map<String, Object?>>>{};
    for (final t in oldTables) {
      final rows = await db.customSelect('SELECT * FROM $t ORDER BY 1').get();
      out[t] = [for (final r in rows) Map<String, Object?>.of(r.data)];
    }
    return out;
  }

  Future<File> buildV7Fixture(Directory dir) async {
    final file = File('${dir.path}/v7.sqlite');
    final seed = AppDatabase.forTesting(NativeDatabase(file), seed: SeedProfile.demo);
    final t = seed.into(seed.transactionRows);
    // Cả Vợ và Chồng; có/không trạng thái; tiết kiệm; quỹ; cặp hoàn tác.
    await t.insert(tx('open-vo', 'income', 'thu_nhap', 10000000,
        source: 'external', sourceRef: null, destination: 'memberAvailable', destinationRef: 'vo'));
    await t.insert(tx('open-chong', 'income', 'thu_nhap', 6000000,
        source: 'external', sourceRef: null, destination: 'memberAvailable', destinationRef: 'chong'));
    await t.insert(tx('gift-vo', 'expense', 'cho_di', 250000,
        sourceRef: 'vo', statusId: 'cho_di_da_chuan_bi', note: 'quà'));
    await t.insert(tx('gift-chong', 'expense', 'cho_di', 120000, sourceRef: 'chong'));
    await t.insert(tx('save-chong', 'transfer', 'tiet_kiem', 2000000,
        sourceRef: 'chong', destination: 'memberSavingsAsset', destinationRef: 'savings_unallocated|chong'));
    await t.insert(tx('fund-vo', 'transfer', 'nap_quy', 500000,
        sourceRef: 'vo', destination: 'fund', destinationRef: 'an_uong'));
    await t.insert(tx('rev-orig', 'expense', 'sinh_hoat', 300000, reversedBy: 'rev-back'));
    await t.insert(tx('rev-back', 'income', 'sinh_hoat', 300000,
        source: 'external', sourceRef: null, destination: 'memberAvailable', destinationRef: 'vo',
        reversalOf: 'rev-orig'));
    await seed.close();

    // Hạ về shape v7: bỏ 2 bảng mới + user_version = 7.
    final raw = sqlite3_pkg.sqlite3.open(file.path);
    raw.execute('DROP TABLE wallet_meta');
    raw.execute('DROP TABLE financial_member_rows');
    raw.execute('PRAGMA user_version = 7;');
    raw.close();
    return file;
  }

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vnm_migration_v8_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('v7 → v8: mọi dòng CŨ giữ nguyên từng trường; đúng 1 Wallet; đúng 2 FinancialMember di sản', () async {
    final file = await buildV7Fixture(dir);

    // Ảnh chụp các bảng cũ ở shape v7 (đọc bằng sqlite thô, chưa qua nâng cấp).
    final rawBefore = sqlite3_pkg.sqlite3.open(file.path);
    expect(rawBefore.select('PRAGMA user_version').single.values.single, 7);
    final before = <String, List<Map<String, Object?>>>{
      for (final t in oldTables)
        t: [
          for (final r in rawBefore.select('SELECT * FROM $t ORDER BY 1')) Map<String, Object?>.of(r),
        ],
    };
    rawBefore.close();
    expect(before['transaction_rows'], hasLength(8));
    expect(before['category_rows']!.isNotEmpty && before['status_rows']!.isNotEmpty, isTrue);

    final db = AppDatabase.forTesting(NativeDatabase(file));
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 11);

    // 1) Dữ liệu cũ y hệt, từng trường của từng dòng.
    final after = await dumpOld(db);
    for (final t in oldTables) {
      expect(after[t], before[t], reason: 'bảng $t không được đổi một trường nào');
    }

    // 2) Đúng 1 Wallet.
    final meta = await db.select(db.walletMeta).get();
    expect(meta, hasLength(1));
    expect(OpaqueId.isValid(meta.single.walletId), isTrue, reason: 'walletId là UUID mờ');
    expect(meta.single.kind, 'local');
    expect(meta.single.singleton, 1);

    // 3) Đúng 2 FinancialMember di sản, giữ nguyên token vo/chong.
    final members = await db.select(db.financialMemberRows).get();
    expect({for (final m in members) m.memberId}, {'vo', 'chong'});
    expect(members.firstWhere((m) => m.memberId == 'vo').label, 'Vợ');
    expect(members.firstWhere((m) => m.memberId == 'chong').label, 'Chồng');

    // 4) Mọi ref thành viên trong giao dịch trỏ tới thành viên có thật.
    final refs = await db.customSelect(
      "SELECT DISTINCT source_ref_id r FROM transaction_rows WHERE source_kind='memberAvailable' "
      "UNION SELECT DISTINCT destination_ref_id FROM transaction_rows WHERE destination_kind='memberAvailable'",
    ).get();
    for (final r in refs) {
      expect({'vo', 'chong'}, contains(r.read<String>('r')));
    }

    // 5) Toàn vẹn.
    expect((await db.customSelect('PRAGMA integrity_check').getSingle()).data.values.single, 'ok');
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    await db.close();
  });

  test('walletId sinh 1 lần rồi BỀN: mở lại nhiều lần không đổi, không tạo dòng thứ hai', () async {
    final file = await buildV7Fixture(dir);
    var db = AppDatabase.forTesting(NativeDatabase(file));
    final id1 = (await db.select(db.walletMeta).getSingle()).walletId;
    await db.close();
    for (var i = 0; i < 3; i++) {
      db = AppDatabase.forTesting(NativeDatabase(file));
      expect((await db.select(db.walletMeta).getSingle()).walletId, id1);
      expect(await db.select(db.financialMemberRows).get(), hasLength(2));
      await db.close();
    }
  });

  test('singleton: KHÔNG thể chèn Wallet thứ hai (khóa chính + CHECK), kể cả cố ý', () async {
    final file = await buildV7Fixture(dir);
    final db = AppDatabase.forTesting(NativeDatabase(file));
    await expectLater(
      db.into(db.walletMeta).insert(
        WalletMetaCompanion.insert(walletId: OpaqueId.generate(), kind: 'local', createdAt: DateTime.now()),
      ),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement("INSERT INTO wallet_meta (singleton, wallet_id, kind, created_at) VALUES (2, 'x', 'local', 0)"),
      throwsA(anything),
      reason: 'CHECK (singleton = 1)',
    );
    expect(await db.select(db.walletMeta).get(), hasLength(1));
    await db.close();
  });

  test('ATOMIC: lỗi giữa chừng ⇒ ROLLBACK, DB vẫn là v7 hợp lệ, không có Wallet nửa vời, dữ liệu nguyên vẹn', () async {
    final file = await buildV7Fixture(dir);
    final raw = sqlite3_pkg.sqlite3.open(file.path);
    // Bảng trùng tên nhưng khác shape ⇒ createTable(financial_member_rows) sẽ lỗi SAU khi
    // wallet_meta đã được tạo trong cùng transaction.
    raw.execute('CREATE TABLE financial_member_rows (blocker TEXT)');
    final before = <String, List<Object?>>{
      for (final t in oldTables) t: [for (final r in raw.select('SELECT * FROM $t ORDER BY 1')) r.values],
    };
    raw.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    await expectLater(db.select(db.transactionRows).get(), throwsA(anything));
    await db.close();

    final check = sqlite3_pkg.sqlite3.open(file.path);
    expect(check.select('PRAGMA user_version').single.values.single, 7, reason: 'vẫn v7');
    final names = [for (final r in check.select("SELECT name FROM sqlite_master WHERE type='table'")) r['name']];
    expect(names, isNot(contains('wallet_meta')), reason: 'không có Wallet nửa vời');
    for (final t in oldTables) {
      expect([for (final r in check.select('SELECT * FROM $t ORDER BY 1')) r.values], before[t], reason: t);
    }
    expect(check.select('PRAGMA integrity_check').single.values.single, 'ok');
    check.close();
  });

  test('DB MỚI: fresh = 2 thành viên ID mờ; demo (di sản) = vo/chong; đều đúng 1 Wallet', () async {
    for (final profile in [SeedProfile.fresh, SeedProfile.demo]) {
      final db = AppDatabase.forTesting(NativeDatabase.memory(), seed: profile);
      expect(await db.select(db.walletMeta).get(), hasLength(1), reason: '$profile');
      final members = await LocalMemberRepository(db).getMembers();
      expect(members.map((m) => m.label), ['Vợ', 'Chồng'], reason: '$profile: theo displayOrder');
      if (profile == SeedProfile.demo) {
        expect(members.map((m) => m.memberId), ['vo', 'chong']);
      } else {
        expect(members.every((m) => OpaqueId.isValid(m.memberId)), isTrue, reason: 'Wallet mới dùng ID mờ');
      }
      await db.close();
    }
  });

  test('LocalWalletIdentityRepository trả thành viên theo displayOrder', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final identity = await LocalWalletIdentityRepository(db).read();
    expect(identity.kind, WalletKind.local);
    expect(identity.members.map((m) => m.memberId), ['vo', 'chong'], reason: 'theo displayOrder');
    expect(identity.memberById('vo')!.label, 'Vợ');
    await db.close();
  });

  test('OpaqueId: UUID v4 hợp lệ, không trùng, KHÔNG phải vo/chong (chiến lược ID cho Wallet/thành viên MỚI)', () {
    final ids = {for (var i = 0; i < 2000; i++) OpaqueId.generate()};
    expect(ids, hasLength(2000));
    for (final id in ids.take(50)) {
      expect(OpaqueId.isValid(id), isTrue);
      expect(id, isNot(anyOf('vo', 'chong')));
    }
    expect(OpaqueId.isValid('vo'), isFalse);
  });

  test('Bất biến kiến trúc (chỉ kiểm mô hình, chưa triển khai mời): người còn lại sẽ gắn vào memberId ĐÃ CÓ, không tạo thành viên mới', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final before = (await LocalWalletIdentityRepository(db).read()).members;
    // Kịch bản tương lai: Owner claim 'chong' → 'vo' vẫn là slot chưa gắn. Ở P2 không có
    // thao tác nào được phép thêm thành viên: số thành viên cố định = 2 và ID không đổi.
    final after = (await LocalWalletIdentityRepository(db).read()).members;
    expect(after, before);
    expect(after.map((m) => m.memberId).toSet(), {'vo', 'chong'});
    await db.close();
  });
}
