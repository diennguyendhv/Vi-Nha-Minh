import 'package:flutter/material.dart';

import '../../domain/entities/category.dart';
import '../../domain/entities/status.dart';
import '../../domain/entities/transaction_type.dart';

/// Đúng bảng hạng mục seed trong `spec.md` (Financial Core V2) — chỉ dùng
/// để SEED database rỗng lúc khởi tạo (`data/local/seed_defaults.dart`).
/// Đây KHÔNG còn là nguồn sự thật cho UI (khác V1) — UI đọc danh mục qua
/// `CategoryRepository`/`categoriesStreamProvider`, vì danh mục giờ là dữ
/// liệu người dùng CRUD được, không phải hằng số cứng.
class DefaultCategories {
  DefaultCategories._();

  static const soDuBanDau = Category(
    id: 'so_du_ban_dau',
    name: 'Số dư ban đầu',
    color: Color(0xFF2F8F4F),
    type: TransactionType.income,
    excludeFromTotals: true,
  );
  static const thuNhap = Category(
    id: 'thu_nhap',
    name: 'Thu nhập',
    color: Color(0xFF12805C),
    type: TransactionType.income,
  );
  static const sinhHoat = Category(
    id: 'sinh_hoat',
    name: 'Sinh hoạt',
    color: Color(0xFF3E6FB0),
    type: TransactionType.expense,
  );
  static const dauTu = Category(
    id: 'dau_tu',
    name: 'Đầu tư',
    color: Color(0xFFC9A23E),
    type: TransactionType.expense,
  );
  static const tuThuong = Category(
    id: 'tu_thuong',
    name: 'Tự thưởng',
    color: Color(0xFFC14F7A),
    type: TransactionType.expense,
  );
  /// Tên hiển thị viết tắt (mã hoá) — "Cho đi" nguyên bản nhạy cảm, dùng
  /// "CĐ" để người ngoài nhìn màn hình không đoán ra ngay. Id nội bộ
  /// (`cho_di`) giữ nguyên, không đổi — chỉ đổi `name` hiển thị.
  static const choDi = Category(
    id: 'cho_di',
    name: 'CĐ',
    color: Color(0xFF8A4FB0),
    type: TransactionType.expense,
    statsEnabled: true,
    statuses: [
      Status(
        id: 'cho_di_chua_chuan_bi',
        categoryId: 'cho_di',
        name: 'CCB',
        sortOrder: 0,
      ),
      Status(
        id: 'cho_di_da_chuan_bi',
        categoryId: 'cho_di',
        name: 'ĐCB',
        sortOrder: 1,
      ),
      Status(
        id: 'cho_di_da_gui',
        categoryId: 'cho_di',
        name: 'ĐG',
        sortOrder: 2,
      ),
    ],
  );

  /// Tương tự `choDi` — "Dâng hiến" viết tắt "DH", id nội bộ giữ nguyên.
  static const dangHien = Category(
    id: 'dang_hien',
    name: 'DH',
    color: Color(0xFF3E86B0),
    type: TransactionType.expense,
    statsEnabled: true,
    statuses: [
      Status(
        id: 'dang_hien_chua_chuan_bi',
        categoryId: 'dang_hien',
        name: 'CCB',
        sortOrder: 0,
      ),
      Status(
        id: 'dang_hien_da_chuan_bi',
        categoryId: 'dang_hien',
        name: 'ĐCB',
        sortOrder: 1,
      ),
      Status(
        id: 'dang_hien_da_dang',
        categoryId: 'dang_hien',
        name: 'ĐD',
        sortOrder: 2,
      ),
    ],
  );

  /// 3 danh mục `type == transfer` — hệ thống quản lý, không tự tạo/xoá qua
  /// UI (`spec.md` bảng seed).
  static const chuyenTienThanhVien = Category(
    id: 'chuyen_tien_thanh_vien',
    name: 'Chuyển tiền cho thành viên khác',
    color: Color(0xFF6FA8D8),
    type: TransactionType.transfer,
  );
  static const napQuy = Category(
    id: 'nap_quy',
    name: 'Nạp quỹ',
    color: Color(0xFFD8836F),
    type: TransactionType.transfer,
  );
  static const tietKiem = Category(
    id: 'tiet_kiem',
    name: 'Tiết kiệm',
    color: Color(0xFF8FA3B3),
    type: TransactionType.transfer,
  );

  /// Phase 8.6 — category cho khoản THU HỒI/HOÀN TIỀN gắn với 1 giao dịch
  /// Chi trước đó (bán lại đồ, hoàn tiền một phần, người khác trả nợ đã
  /// ứng...). Về mặt kỹ thuật vẫn là `TransactionType.income` (tiền từ
  /// ngoài hệ thống vào — `typeFromEndpoints`), nhưng `excludeFromTotals =
  /// true` để KHÔNG tính vào Total Income/monthlyIncome báo cáo — chỉ tăng
  /// `availableBalance`/Total Assets. Dùng lại ĐÚNG cơ chế `excludeFromTotals`
  /// đã có từ Phase 1 (giống "Số dư ban đầu"), không phải type/field tài
  /// chính mới. Generic cho MỌI gia đình — không gắn với bất kỳ workflow
  /// riêng nào (CLAUDE.md mục 9).
  static const hoanTienThuHoi = Category(
    id: 'hoan_tien_thu_hoi',
    name: 'Hoàn tiền / Thu hồi',
    color: Color(0xFF5FA88A),
    type: TransactionType.income,
    excludeFromTotals: true,
  );

  static const all = <Category>[
    soDuBanDau,
    thuNhap,
    sinhHoat,
    dauTu,
    tuThuong,
    choDi,
    dangHien,
    chuyenTienThanhVien,
    napQuy,
    tietKiem,
    hoanTienThuHoi,
  ];

  static const quickNotes = <String>[
    'Chợ',
    'Xăng xe',
    'Cà phê',
    'Hoá đơn',
    'Khác',
  ];
}
