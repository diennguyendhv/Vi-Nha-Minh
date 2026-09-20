import 'package:drift/native.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/constants/advanced_system_categories.dart';
import 'package:vi_nha_minh/data/local/app_database.dart';
import 'package:vi_nha_minh/data/local/seed_defaults.dart';
import 'package:vi_nha_minh/data/repositories/local_category_repository.dart';
import 'package:vi_nha_minh/data/repositories/local_fund_repository.dart';
import 'package:vi_nha_minh/data/repositories/local_savings_asset_type_repository.dart';
import 'package:vi_nha_minh/data/repositories/local_transaction_repository.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/family_member.dart';
import 'package:vi_nha_minh/domain/entities/fund.dart';
import 'package:vi_nha_minh/domain/entities/pool_kind.dart';
import 'package:vi_nha_minh/domain/entities/savings_asset_type.dart';
import 'package:vi_nha_minh/domain/entities/transaction.dart' as domain;
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/entities/transfer_kind.dart';
import 'package:vi_nha_minh/domain/errors/domain_exceptions.dart';

/// Người dùng MỚI: seed tối giản (không danh mục con, không trạng thái, chỉ Quỹ
/// tiền ăn + Gửi ngân hàng), và vòng đời Quỹ (ngừng / dùng lại / xóa hẳn).
void main() {
  group('Seed người dùng mới', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory(), seed: SeedProfile.fresh));
    tearDown(() async => db.close());

    test('Chỉ danh mục HỆ THỐNG (Chuyển + nâng cao ẩn); KHÔNG danh mục con Thu/Chi nào, KHÔNG trạng thái', () async {
      final cats = await LocalCategoryRepository(db).watchCategories().first;
      // Không có danh mục Thu/Chi "thường" nào (mọi danh mục Thu/Chi đều thuộc tính năng nâng cao ẩn).
      final visibleChildren = [
        for (final c in cats)
          if (c.type != TransactionType.transfer && !AdvancedSystemCategories.contains(c.id)) c,
      ];
      expect(visibleChildren, isEmpty, reason: 'danh mục con do gia đình tự tạo');
      expect(cats.map((c) => c.id).toSet(), {
        'chuyen_tien_thanh_vien', 'nap_quy', 'tiet_kiem',
        'hoan_tien_thu_hoi', 'cho_vay', 'lai_cho_vay', 'vay_no', 'tra_no',
      });
      expect(cats.every((c) => c.statuses.isEmpty), isTrue);
      expect((await db.select(db.statusRows).get()), isEmpty);
    });

    test('Quỹ: chỉ "Quỹ tiền ăn"; Tiết kiệm: chỉ "Gửi ngân hàng" (+ "Chưa phân bổ" là hạ tầng ảo, không có row)', () async {
      final funds = await LocalFundRepository(db, LocalTransactionRepository(db)).watchFunds().first;
      expect(funds.map((f) => f.name), ['Quỹ tiền ăn']);
      final assets = await LocalSavingsAssetTypeRepository(db, LocalTransactionRepository(db)).watchAssetTypes().first;
      expect(assets.map((a) => a.name), ['Gửi ngân hàng']);
      expect(assets.any((a) => a.id == SystemSavingsAssets.unallocatedId), isFalse);
    });

    test('Không có giao dịch, khoản vay hay đối tác nào', () async {
      expect(await db.select(db.transactionRows).get(), isEmpty);
      expect(await db.select(db.obligationRows).get(), isEmpty);
      expect(await db.select(db.counterpartyRows).get(), isEmpty);
    });

    test('Bộ seed "demo" (test/golden) vẫn đầy đủ như trước', () async {
      final demo = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(demo.close);
      expect((await demo.select(demo.categoryRows).get()).length, 17);
      expect((await demo.select(demo.savingsAssetTypeRows).get()).length, 4);
    });
  });

  group('Vòng đời Quỹ', () {
    late AppDatabase db;
    late LocalTransactionRepository txRepo;
    late LocalFundRepository funds;

    domain.Transaction income(String id, int amount) => domain.Transaction(
      id: id,
      type: TransactionType.income,
      categoryId: 'thu_test',
      sourceKind: PoolKind.external,
      destinationKind: PoolKind.memberAvailable,
      destinationRefId: FamilyMember.vo.name,
      amountMinor: amount,
      transactionDate: DateTime(2026, 9, 1),
      createdAt: DateTime(2026, 9, 1),
      clientTxId: 'c-$id',
    );

    domain.Transaction topup(String id, String fund, int amount) => domain.Transaction(
      id: id,
      type: TransactionType.transfer,
      transferKind: TransferKind.fundTopup,
      categoryId: 'nap_quy',
      sourceKind: PoolKind.memberAvailable,
      sourceRefId: FamilyMember.vo.name,
      destinationKind: PoolKind.fund,
      destinationRefId: fund,
      amountMinor: amount,
      transactionDate: DateTime(2026, 9, 2),
      createdAt: DateTime(2026, 9, 2),
      clientTxId: 'c-$id',
    );

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory(), seed: SeedProfile.fresh);
      txRepo = LocalTransactionRepository(db);
      funds = LocalFundRepository(db, txRepo);
      // Danh mục Thu để có tiền vào ví (do gia đình tự tạo).
      await LocalCategoryRepository(db).addCategory(
        Category(id: 'thu_test', name: 'Thu test', color: const Color(0xFF12805C), type: TransactionType.income, isDefault: false),
      );
      await txRepo.addTransaction(income('i1', 1000000));
    });
    tearDown(() async => db.close());

    Future<bool> exists(String id) async =>
        (await db.select(db.fundRows).get()).any((r) => r.id == id);

    test('Tạo quỹ mới, đổi tên, ngừng, dùng lại (giữ NGUYÊN id), xóa hẳn khi sạch', () async {
      await funds.addFund(const Fund(id: 'qhoc', name: 'Quỹ học', color: Color(0xFF3E6FB0)));
      await funds.updateFund(const Fund(id: 'qhoc', name: 'Quỹ học phí', color: Color(0xFF3E6FB0)));
      expect((await funds.watchFunds().first).firstWhere((f) => f.id == 'qhoc').name, 'Quỹ học phí');

      await funds.softDeleteFund('qhoc');
      expect((await funds.watchFunds().first).firstWhere((f) => f.id == 'qhoc').isActive, isFalse);
      await funds.reactivateFund('qhoc');
      expect((await funds.watchFunds().first).firstWhere((f) => f.id == 'qhoc').isActive, isTrue);

      // Đang hoạt động → chưa xóa hẳn được.
      await expectLater(funds.deleteFundPermanently('qhoc'), throwsA(isA<FundNotDeletableException>()));
      await funds.softDeleteFund('qhoc');
      await funds.deleteFundPermanently('qhoc');
      expect(await exists('qhoc'), isFalse);
    });

    test('Quỹ tiền ăn mặc định KHÔNG bị bảo vệ đặc biệt: ngừng rồi xóa hẳn được khi sạch', () async {
      await funds.softDeleteFund('an_uong');
      await funds.deleteFundPermanently('an_uong');
      expect(await exists('an_uong'), isFalse);
      // Không tự tạo lại.
      expect((await funds.watchFunds().first).any((f) => f.id == 'an_uong'), isFalse);
    });

    test('Quỹ còn tiền: không ngừng được (còn X đ); còn giao dịch: không xóa hẳn được; xóa giao dịch → xóa được', () async {
      await txRepo.addTransaction(topup('nap1', 'an_uong', 100000));
      await expectLater(funds.softDeleteFund('an_uong'), throwsA(isA<FundNotEmptyException>()));

      // Rút hết bằng cách xóa lần nạp → quỹ về 0, sạch dấu vết.
      await txRepo.deleteTransaction('nap1');
      await funds.softDeleteFund('an_uong');
      await funds.deleteFundPermanently('an_uong');
      expect(await exists('an_uong'), isFalse);
    });

    test('Quỹ ngừng nhưng còn giao dịch tham chiếu (số dư 0) → xóa hẳn bị chặn cho tới khi hết giao dịch', () async {
      await funds.addFund(const Fund(id: 'qx', name: 'Quỹ X', color: Color(0xFF8FA3B3)));
      await txRepo.addTransaction(topup('nx', 'qx', 50000));
      // Rút lại về 0 bằng 1 giao dịch chi từ quỹ.
      await txRepo.addTransaction(
        domain.Transaction(
          id: 'sx',
          type: TransactionType.expense,
          categoryId: 'thu_test',
          sourceKind: PoolKind.fund,
          sourceRefId: 'qx',
          destinationKind: PoolKind.external,
          amountMinor: 50000,
          transactionDate: DateTime(2026, 9, 3),
          createdAt: DateTime(2026, 9, 3),
          clientTxId: 'c-sx',
        ),
      );
      await funds.softDeleteFund('qx');
      await expectLater(funds.deleteFundPermanently('qx'), throwsA(isA<FundNotDeletableException>()));

      await txRepo.deleteTransaction('sx');
      await expectLater(funds.deleteFundPermanently('qx'), throwsA(isA<FundNotDeletableException>()), reason: 'còn giao dịch nạp');
      await expectLater(txRepo.deleteTransaction('nx'), completes);
      await funds.deleteFundPermanently('qx');
      expect(await exists('qx'), isFalse);
    });
  });
}
