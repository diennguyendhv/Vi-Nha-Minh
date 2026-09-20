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

  /// "Khác" thuộc nhóm Khoản thu khác (tiền vào không phải doanh thu, vd bán
  /// lại đồ, người khác trả lại). Chỉ seed cho DB MỚI — DB cũ không đổi.
  static const thuKhac = Category(
    id: 'thu_khac',
    name: 'Khác',
    color: Color(0xFF6FA88A),
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
      // Bộ 4 trạng thái đang dùng thật (đọc từ DB Pixel): CĐ có ĐD SAU ĐG.
      Status(
        id: 'cho_di_da_dang',
        categoryId: 'cho_di',
        name: 'ĐD',
        sortOrder: 3,
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
      // Bộ 4 trạng thái đang dùng thật: DH có ĐG SAU ĐD (khác thứ tự của CĐ).
      Status(
        id: 'dang_hien_da_gui',
        categoryId: 'dang_hien',
        name: 'ĐG',
        sortOrder: 3,
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

  /// Phase 8.7 — Receivable (cho vay): TẠO khoản vay + trả gốc đều là
  /// `TransactionType.transfer` (`memberAvailable ↔ receivable`), dùng
  /// chung 1 category giống `napQuy`/`chuyenTienThanhVien` (đều là các
  /// category `type == transfer` hệ thống).
  static const choVay = Category(
    id: 'cho_vay',
    name: 'Cho vay',
    color: Color(0xFF4F8AB0),
    type: TransactionType.transfer,
  );

  /// Phase 8.7 — phần LÃI của 1 lần thu hồi Receivable (leg riêng, income
  /// thật, KHÔNG `excludeFromTotals` — báo cáo bình thường vào Tổng thu).
  static const laiChoVay = Category(
    id: 'lai_cho_vay',
    name: 'Lãi cho vay',
    color: Color(0xFF6FB08A),
    type: TransactionType.income,
  );

  /// Phase 8.7 — Payable (đi vay): giao dịch TẠO khoản vay (nhận tiền vay).
  static const vayNo = Category(
    id: 'vay_no',
    name: 'Đi vay',
    color: Color(0xFFB0834F),
    type: TransactionType.income,
  );

  /// Phase 8.7 — Payable: giao dịch TẤT TOÁN (trả nợ, gồm cả gốc lẫn lãi
  /// gộp trong 1 dòng — xem `buildObligationSettlementLegs`).
  static const traNo = Category(
    id: 'tra_no',
    name: 'Trả nợ',
    color: Color(0xFFB0574F),
    type: TransactionType.expense,
  );

  /// Hạng mục Chi BÌNH THƯỜNG cho chi phí vận hành công việc/kinh doanh (lương,
  /// quảng cáo, bảo hành...). Chi tiết từng khoản ghi trong Ghi chú — Category
  /// chỉ là nhóm để thống kê, KHÔNG có ngữ nghĩa báo cáo đặc biệt nào (không
  /// liên kết với hạng mục Thu, không tính lợi nhuận). Chỉ được seed khi tạo
  /// DB mới (như mọi hạng mục mặc định) — DB đã có từ trước không bị đổi.
  static const chiPhiKinhDoanh = Category(
    id: 'chi_phi_kinh_doanh',
    name: 'Chi phí kinh doanh',
    color: Color(0xFF5B7083),
    type: TransactionType.expense,
    groupKey: CategoryGroupKey.businessExpense,
  );

  /// Seed cho NGƯỜI DÙNG MỚI (`SeedProfile.fresh`): chỉ các danh mục HỆ THỐNG mà
  /// app cần để chạy (Chuyển tiền, Nạp quỹ, Tiết kiệm + 5 danh mục của tính năng
  /// nâng cao — ẩn mặc định). KHÔNG có danh mục con nào: 4 nhóm Thu/Chi là ngữ
  /// nghĩa hệ thống, danh mục con do gia đình tự tạo (không seed cấu trúc riêng
  /// của 1 hộ), và không có trạng thái nào.
  static const freshSystem = <Category>[
    chuyenTienThanhVien,
    napQuy,
    tietKiem,
    hoanTienThuHoi,
    choVay,
    laiChoVay,
    vayNo,
    traNo,
  ];

  /// Seed đầy đủ của hộ chủ dự án (`SeedProfile.demo`) — dùng cho test/golden.
  static const all = <Category>[
    soDuBanDau,
    thuKhac,
    thuNhap,
    sinhHoat,
    dauTu,
    tuThuong,
    choDi,
    dangHien,
    chiPhiKinhDoanh,
    chuyenTienThanhVien,
    napQuy,
    tietKiem,
    hoanTienThuHoi,
    choVay,
    laiChoVay,
    vayNo,
    traNo,
  ];
}
