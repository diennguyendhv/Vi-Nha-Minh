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
    this.isDefault = true,
    this.isActive = true,
  });

  final String id;
  final String name;
  final Color color;
  final TransactionType type;

  /// Các bước trạng thái do CHÍNH gia đình đặt ra cho hạng mục này, theo
  /// đúng thứ tự (`sortOrder`). Rỗng nghĩa là hạng mục này không theo dõi
  /// trạng thái. Không bao giờ ảnh hưởng balance.
  final List<Status> statuses;

  bool get hasStatus => statuses.isNotEmpty;

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
      isDefault: isDefault ?? this.isDefault,
      isActive: isActive ?? this.isActive,
    );
  }
}

const _unset = Object();
