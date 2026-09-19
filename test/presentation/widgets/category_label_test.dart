import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/constants/default_categories.dart';
import 'package:vi_nha_minh/domain/entities/category.dart';
import 'package:vi_nha_minh/domain/entities/transaction_type.dart';
import 'package:vi_nha_minh/presentation/widgets/category_label.dart';

Category _c(String name, TransactionType type, {bool exclude = false, String? group}) =>
    Category(id: 'x_$name', name: name, color: Colors.grey, type: type, excludeFromTotals: exclude, groupKey: group);

void main() {
  test('nhãn "Nhóm · Danh mục" theo cờ phân loại, không theo tên', () {
    expect(categoryDisplayLabel(_c('Học phí', TransactionType.income)), 'Doanh thu · Học phí');
    expect(categoryDisplayLabel(_c('Bán lại', TransactionType.income, exclude: true)), 'Khoản thu khác · Bán lại');
    expect(categoryDisplayLabel(_c('Sinh hoạt', TransactionType.expense)), 'Chi tiêu · Sinh hoạt');
    expect(
      categoryDisplayLabel(_c('Lương nhân viên', TransactionType.expense, group: CategoryGroupKey.businessExpense)),
      'Chi phí kinh doanh · Lương nhân viên',
    );
  });

  test('tên trùng tên nhóm không bị lặp; danh mục đã xoá có nhãn riêng', () {
    expect(categoryDisplayLabel(DefaultCategories.chiPhiKinhDoanh), 'Chi phí kinh doanh');
    expect(categoryDisplayLabel(null), 'Đã xoá danh mục');
  });

  test('Chuyển và danh mục nâng cao (lịch sử cũ) giữ tên gốc, không gán nhóm', () {
    expect(categoryDisplayLabel(DefaultCategories.tietKiem), 'Tiết kiệm');
    expect(categoryDisplayLabel(DefaultCategories.choVay), 'Cho vay');
    expect(categoryDisplayLabel(DefaultCategories.vayNo), 'Đi vay');
    expect(categoryDisplayLabel(DefaultCategories.traNo), 'Trả nợ');
    expect(categoryDisplayLabel(DefaultCategories.laiChoVay), 'Lãi cho vay');
    expect(categoryDisplayLabel(DefaultCategories.hoanTienThuHoi), 'Hoàn tiền / Thu hồi');
  });
}
