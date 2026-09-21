import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/constants/default_categories.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/domain/usecases/selectable_categories.dart';

Category _c(String id, TransactionType t, {bool active = true}) => Category(
  id: id,
  name: 'Tên khác $id',
  color: Colors.teal,
  type: t,
  isActive: active,
  isDefault: false,
);

void main() {
  final all = DefaultCategories.all;

  test('Chi thường: chỉ danh mục thường — KHÔNG Trả nợ / Cho vay / Chuyển / Nạp quỹ / Tiết kiệm', () {
    final ids = selectableCategories(all, type: TransactionType.expense).map((c) => c.id).toSet();
    for (final id in ['tra_no', 'cho_vay', 'chuyen_tien_thanh_vien', 'nap_quy', 'tiet_kiem']) {
      expect(ids, isNot(contains(id)), reason: id);
    }
    expect(ids, containsAll(['sinh_hoat', 'cho_di', 'dang_hien', 'dau_tu']));
  });

  test('Thu thường: KHÔNG Vay nợ / Lãi cho vay / Hoàn tiền-Thu hồi; vẫn có Thu nhập', () {
    final ids = selectableCategories(all, type: TransactionType.income).map((c) => c.id).toSet();
    for (final id in ['vay_no', 'lai_cho_vay', 'hoan_tien_thu_hoi']) {
      expect(ids, isNot(contains(id)), reason: id);
    }
    expect(ids, contains('thu_nhap'));
  });

  test('Nhận diện theo ID/loại, KHÔNG theo tên: đổi tên danh mục hệ thống vẫn ẩn; danh mục thường tên "Trả nợ" vẫn hiện', () {
    final renamedSystem = DefaultCategories.traNo.copyWith(name: 'Hoàn toàn tên khác');
    final ordinaryNamedTraNo = Category(
      id: 'user_x',
      name: 'Trả nợ',
      color: Colors.teal,
      type: TransactionType.expense,
      isDefault: false,
    );
    final ids = selectableCategories([renamedSystem, ordinaryNamedTraNo], type: TransactionType.expense).map((c) => c.id);
    expect(ids, ['user_x']);
  });

  test('Đã ngừng không được đề nghị; danh mục HIỆN TẠI của giao dịch cũ (ngừng hoặc hệ thống) vẫn được giữ để hiển thị', () {
    final list = [_c('a', TransactionType.expense), _c('b', TransactionType.expense, active: false)];
    expect(selectableCategories(list, type: TransactionType.expense).map((c) => c.id), ['a']);
    expect(selectableCategories(list, type: TransactionType.expense, currentCategoryId: 'b').map((c) => c.id), ['a', 'b']);
    final withSystem = [...list, DefaultCategories.traNo, DefaultCategories.vayNo];
    expect(
      selectableCategories(withSystem, type: TransactionType.expense, currentCategoryId: 'tra_no').map((c) => c.id),
      ['a', 'tra_no'],
      reason: 'chỉ danh mục hiện tại; Vay nợ (khác loại) và hệ thống khác không được đề nghị',
    );
  });

  test('isSystemInfrastructureCategory: Chuyển/Nạp quỹ/Tiết kiệm + 5 danh mục nâng cao; danh mục thường thì không', () {
    for (final c in [
      DefaultCategories.chuyenTienThanhVien,
      DefaultCategories.napQuy,
      DefaultCategories.tietKiem,
      DefaultCategories.choVay,
      DefaultCategories.laiChoVay,
      DefaultCategories.vayNo,
      DefaultCategories.traNo,
      DefaultCategories.hoanTienThuHoi,
    ]) {
      expect(isSystemInfrastructureCategory(c), isTrue, reason: c.id);
    }
    expect(isSystemInfrastructureCategory(DefaultCategories.sinhHoat), isFalse);
    expect(
      isSystemInfrastructureCategory(DefaultCategories.chiPhiKinhDoanh),
      isFalse,
      reason: 'là danh mục con thường thuộc nhóm Chi phí kinh doanh, không phải hạ tầng',
    );
  });
}
