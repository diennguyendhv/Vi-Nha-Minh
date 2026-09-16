/// Financial Core V2 (`docs/financial-core-v2.md` mục 6): mọi giao dịch chỉ
/// có đúng 1 trong 3 loại này — `type` cùng `sourceKind`/`destinationKind`
/// trên [Transaction] quyết định dòng tiền, `Category` chỉ còn là nhãn.
///
/// - [income]: `sourceKind == PoolKind.external` — tiền từ bên ngoài vào.
/// - [expense]: `destinationKind == PoolKind.external` — tiền rời hệ thống.
/// - [transfer]: cả 2 đầu đều không phải external — tiền chỉ đổi chỗ, không
///   đổi Tổng tài sản.
enum TransactionType { income, expense, transfer }
