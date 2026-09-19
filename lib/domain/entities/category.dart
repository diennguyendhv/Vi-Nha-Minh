import 'package:flutter/material.dart';

import 'status.dart';
import 'transaction_type.dart';

/// Hạng mục là DỮ LIỆU do từng gia đình tự định nghĩa (đúng như
/// `families/{familyId}/categories/{categoryId}` trong spec.md).
///
/// Financial Core V2 (`docs/financial-core-v2.md` mục 11, F-04): Category
/// giờ CHỈ là nhãn + [type] để nhóm báo cáo — KHÔNG quyết định tiền chạy đi
/// đâu (việc đó do `Transaction.sourceKind`/`destinationKind` quyết định).
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.color,
    required this.type,
    this.statuses = const [],
    this.statsEnabled = false,
    this.excludeFromTotals = false,
    this.linkedExpenseCategoryId,
    this.groupKey,
    this.isDefault = true,
    this.isActive = true,
  });

  final String id;
  final String name;
  final Color color;
  final TransactionType type;

  /// TẤT CẢ các bước trạng thái do CHÍNH gia đình đặt ra cho hạng mục này
  /// (kể cả bước đã ẩn `isActive == false`), theo đúng thứ tự (`sortOrder`).
  /// Giữ cả bước đã ẩn để giao dịch lịch sử vẫn resolve được tên và để màn
  /// quản lý cho phép "Sử dụng lại". Không bao giờ ảnh hưởng balance.
  ///
  /// Khi TẠO giao dịch mới hoặc chọn bước cho giao dịch, dùng
  /// [activeStatuses] — KHÔNG dùng danh sách này.
  final List<Status> statuses;

  /// Các bước đang dùng — chỉ những bước này được chọn cho giao dịch mới.
  List<Status> get activeStatuses => statuses.where((s) => s.isActive).toList();

  /// Hạng mục có workflow dùng được cho giao dịch mới (còn ít nhất 1 bước
  /// đang dùng). Rỗng/toàn bộ bước đã ẩn nghĩa là giao dịch mới không có
  /// trạng thái; giao dịch cũ vẫn giữ `statusId` của nó.
  bool get hasStatus => statuses.any((s) => s.isActive);

  /// Tra bước trạng thái theo id trong TẤT CẢ các bước (kể cả đã ẩn) — để
  /// hiển thị tên cho giao dịch lịch sử.
  Status? statusById(String? id) {
    if (id == null) return null;
    for (final s in statuses) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Bật/tắt việc danh mục này có hiện ở màn Tổng hợp trạng thái hay không.
  final bool statsEnabled;

  /// Bỏ qua khi tính `totalIncome`/`totalExpense` ở rollup tháng, nhưng vẫn
  /// cộng/trừ `availableBalance` bình thường qua Financial Engine (vd "Số dư
  /// ban đầu"). Xem `docs/financial-core-v2.md` mục 11.
  final bool excludeFromTotals;

  /// Chỉ hợp lệ khi `type == TransactionType.income`. Trỏ tới 1 category
  /// `type == expense` khác để tính "Thu nhập ròng" hiển thị — KHÔNG đổi
  /// applyEffect/Total Income/Total External Expense. Xem mục 11, 17.
  final String? linkedExpenseCategoryId;

  /// Phân loại BÁO CÁO cho danh mục Chi (schema v7): `null` = Chi tiêu,
  /// [CategoryGroupKey.businessExpense] = Chi phí kinh doanh. Chỉ có nghĩa
  /// với `type == expense`; KHÔNG ảnh hưởng số dư/ledger, không bao giờ suy
  /// từ tên hay Ghi chú. Nhóm của danh mục Thu lấy từ [excludeFromTotals]
  /// (false = Doanh thu, true = Khoản thu khác) — không có cột thứ hai.
  final String? groupKey;

  /// Chi phí kinh doanh (Chi + [groupKey] == business_expense).
  bool get isBusinessExpense =>
      type == TransactionType.expense &&
      groupKey == CategoryGroupKey.businessExpense;

  /// Danh mục hệ thống seed sẵn (9-10 hạng mục mặc định). Danh mục `type ==
  /// transfer` luôn `isDefault == true` và không cho tự tạo/xoá qua UI.
  final bool isDefault;

  /// Soft delete — giao dịch cũ vẫn hiển thị đúng tên/màu khi `isActive ==
  /// false`, chỉ ẩn khỏi các bộ chọn tạo giao dịch mới.
  final bool isActive;

  String get initial => name.isEmpty ? '' : name.substring(0, 1).toUpperCase();

  Category copyWith({
    String? name,
    Color? color,
    TransactionType? type,
    List<Status>? statuses,
    bool? statsEnabled,
    bool? excludeFromTotals,
    Object? linkedExpenseCategoryId = _unset,
    Object? groupKey = _unset,
    bool? isDefault,
    bool? isActive,
  }) {
    return Category(
      id: id,
      name: name ?? this.name,
      color: color ?? this.color,
      type: type ?? this.type,
      statuses: statuses ?? this.statuses,
      statsEnabled: statsEnabled ?? this.statsEnabled,
      excludeFromTotals: excludeFromTotals ?? this.excludeFromTotals,
      linkedExpenseCategoryId: identical(linkedExpenseCategoryId, _unset)
          ? this.linkedExpenseCategoryId
          : linkedExpenseCategoryId as String?,
      groupKey: identical(groupKey, _unset) ? this.groupKey : groupKey as String?,
      isDefault: isDefault ?? this.isDefault,
      isActive: isActive ?? this.isActive,
    );
  }
}

/// Giá trị hợp lệ của [Category.groupKey] (schema v7).
class CategoryGroupKey {
  CategoryGroupKey._();

  static const businessExpense = 'business_expense';
}

const _unset = Object();
