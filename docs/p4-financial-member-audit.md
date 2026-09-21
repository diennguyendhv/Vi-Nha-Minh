# P4 — FinancialMember là dữ liệu: audit & kết quả

> Phạm vi: bỏ enum `FamilyMember` (Vợ/Chồng) khỏi runtime tài chính; nguồn thành viên duy nhất = `financial_member_rows` (schema v8, KHÔNG đổi schema). Không có Account/Auth/Membership.

## 1. Audit trước khi sửa (production `lib/`)
Phân loại: A runtime danh tính · B nhãn hiển thị · C tương thích di sản · D fixture test · E không liên quan.

| Nơi | Trước P4 | Loại | Sau P4 |
|---|---|---|---|
| `domain/entities/family_member.dart` (enum vo/chong + label) | nguồn danh tính | A+B | **xoá** |
| `domain/entities/wallet_member_resolver.dart` | cầu enum ↔ memberId | C | **xoá** (không còn enum để bắc cầu) |
| `pool_kind.dart` `savingsAssetRefId/parseSavingsAssetRefId` | kiểu `FamilyMember`, duyệt `values` | A | `String memberId`; không kiểm tra thành viên (ID mờ hợp lệ) |
| `compute_pool_balance`, `compute_member_financials`, `compute_savings_breakdown`, `compute_member_outflow_breakdown`, `compute_reportable_income` (`incomeRecipient`), `compute_grouped_totals` (`expenseSpender`, tham số `member`), `explore_transactions` (`TransactionFilter.member`, `involvesMember`, `computeMemberNetIncome`) | tham số/khoá `FamilyMember` | A | `String memberId` (`TransactionFilter.memberId`) |
| `compute_financial_summary` | `for (m in FamilyMember.values)` | A | tham số bắt buộc `members: List<FinancialMember>`; map khoá bằng `memberId` |
| `deletion_check` (số dư loại tiết kiệm) | duyệt enum | A | `computeSavingsAssetTypeBalance` (quét ledger, không cần danh sách thành viên) |
| `transaction_member_label` | nhãn từ enum | B | nhận `Iterable<FinancialMember>`; ID lạ → `null` |
| `local_savings_asset_type_repository.softDeleteAssetType` | duyệt enum | A | `computeSavingsAssetTypeBalance` |
| Home / Savings / Add / Edit(detail) / Summary (thẻ + chip) / Loans (tạo, tất toán, chi tiết) / danh sách giao dịch / hộp thoại chặn | `FamilyMember.values`, mặc định `.vo`, chip cứng `vo`/`chong` | A+B | lặp `memberDirectoryProvider.members`; mặc định = thành viên đầu theo `displayOrder`; "người nhận" = người khác người gửi suy từ dữ liệu |
| `data/local/app_database.dart` `_ensureWalletIdentity` | seed `vo`/`chong` | C | DB mới (`SeedProfile.fresh`) → **ID mờ**; nâng cấp v7→v8 và `SeedProfile.demo` giữ `vo`/`chong` |
| `data/import/legacy_import_guard.dart` | enum + `vo`/`chong` | C | hằng `'vo'`/`'chong'` cục bộ (importer debug đã gắn Excel Vợ/Chồng; đã tự khoá vì đòi schema v7) |
| Test | 261 chỗ dùng `FamilyMember.vo/chong` | D | chuỗi `'vo'`/`'chong'` (fixture Wallet di sản) + `test/support/legacy_members.dart` |

## 2. Mô hình runtime
- `FinancialMember{memberId,label,displayOrder}` (đã có từ P2) là danh tính runtime. Không thêm accountId/email/quyền.
- `MemberRepository` (`domain/repositories`) ← `LocalMemberRepository`: `watchMembers()`, `getMembers()`, `getMemberById()`, `createMember(label)` (ID mờ `OpaqueId`, `displayOrder` nối cuối). Sắp xếp `displayOrder`, hoà → `memberId`.
- `MemberDirectory` (`domain/entities`): ảnh chụp bất biến để UI/logic liệt kê, tra nhãn (`labelOf`), `defaultMemberId`, `resolveOrDefault`, `otherThan` (chỉ khi ĐÚNG 2 thành viên), `firstOtherThan`.
- `memberDirectoryProvider`/`membersStreamProvider` (`presentation/providers/member_providers.dart`) — UI không đọc bảng thô.
- `Transaction` không đổi; `sourceRefId/destinationRefId` vẫn là chuỗi `memberId`; pool tiết kiệm `assetTypeId|memberId`.

## 3. Bất biến giữ nguyên
Không đổi công thức tiền, không viết lại giao dịch, không đổi schema (v8), `vo`/`chong` của Wallet hiện tại nguyên vẹn. Quy tắc mặc định "Vợ trước" chỉ còn là thứ tự dữ liệu (`displayOrder`) — nợ tạm cho tới phase gắn Account.
