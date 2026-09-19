/// Phase 8.7 — chiều của 1 khoản vay (`Obligation`).
///
/// - [receivable]: NGƯỜI DÙNG cho người khác vay (Cho vay) — tiền là tài sản
///   (`PoolKind.receivable`), xem `docs/financial-core-v2.md` audit Phase
///   8.7 mục C.
/// - [payable]: NGƯỜI DÙNG đi vay người khác (Đi vay) — KHÔNG có PoolKind
///   riêng, tiền vay là 1 dòng INCOME thường + `Transaction.obligationId`,
///   outstanding tính DERIVED (mục D).
enum ObligationDirection { receivable, payable }
