import 'package:flutter/material.dart';

import '../../domain/entities/category.dart';
import '../../domain/entities/category_kind.dart';
import '../../domain/entities/family_member.dart';

/// Đúng 9 hạng mục thật trong sheet "Quản lý tài chính 2026" (trang Ghi
/// chép) — không phải danh sách Ăn uống/Di chuyển đã đoán ở bản nháp đầu.
class DefaultCategories {
  DefaultCategories._();

  static const thuNhap = Category(
    id: 'thu_nhap',
    name: 'Thu nhập',
    color: Color(0xFF2F8F4F),
    kind: CategoryKind.income,
  );
  static const sinhHoat = Category(
    id: 'sinh_hoat',
    name: 'Sinh hoạt',
    color: Color(0xFF3E6FB0),
    kind: CategoryKind.expense,
  );
  static const dauTu = Category(
    id: 'dau_tu',
    name: 'Đầu tư',
    color: Color(0xFFC9A23E),
    kind: CategoryKind.expense,
  );
  static const tuThuong = Category(
    id: 'tu_thuong',
    name: 'Tự thưởng',
    color: Color(0xFFC14F7A),
    kind: CategoryKind.expense,
  );
  static const choDi = Category(
    id: 'cho_di',
    name: 'Cho đi',
    color: Color(0xFF8A4FB0),
    kind: CategoryKind.expense,
    statuses: ['Chưa chuẩn bị', 'Đã chuẩn bị', 'Đã gửi'],
  );
  static const tietKiem = Category(
    id: 'tiet_kiem',
    name: 'Tiết kiệm',
    color: Color(0xFF12805C),
    kind: CategoryKind.savings,
  );
  static const dangHien = Category(
    id: 'dang_hien',
    name: 'Dâng hiến',
    color: Color(0xFF3E86B0),
    kind: CategoryKind.expense,
    statuses: ['Chưa chuẩn bị', 'Đã chuẩn bị', 'Đã dâng'],
  );
  static const chongDuaVo = Category(
    id: 'chong_dua_vo',
    name: 'Chồng đưa vợ',
    color: Color(0xFF6FA8D8),
    kind: CategoryKind.transfer,
    transferFrom: FamilyMember.chong,
    transferTo: FamilyMember.vo,
  );
  static const voDuaChong = Category(
    id: 'vo_dua_chong',
    name: 'Vợ đưa chồng',
    color: Color(0xFFD8836F),
    kind: CategoryKind.transfer,
    transferFrom: FamilyMember.vo,
    transferTo: FamilyMember.chong,
  );

  static const all = <Category>[
    thuNhap,
    sinhHoat,
    dauTu,
    tuThuong,
    choDi,
    tietKiem,
    dangHien,
    chongDuaVo,
    voDuaChong,
  ];

  static const expense = <Category>[sinhHoat, dauTu, tuThuong, choDi, dangHien];

  static const quickNotes = <String>['Chợ', 'Xăng xe', 'Cà phê', 'Hoá đơn', 'Khác'];

  static Category byId(String id) {
    return all.firstWhere(
      (c) => c.id == id,
      orElse: () => const Category(
        id: '',
        name: '',
        color: Color(0xFF9A9D97),
        kind: CategoryKind.expense,
      ),
    );
  }
}
