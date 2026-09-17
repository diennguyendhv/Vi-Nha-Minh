# FINAL DESIGN FREEZE

Kiểm tra cuối cùng trước khi implementation. **Chưa code** — tài liệu này chỉ tổng hợp/đối chiếu lại nội dung đã có trong `docs/financial-core-v2.md`, `spec.md`, `CLAUDE.md`, `docs/design.html` thành 1 bản "đóng băng" tham chiếu nhanh cho phiên code tiếp theo.

---

## 1. Source of Truth

**SOURCE OF TRUTH = `docs/financial-core-v2.md` (business logic tài chính) + `spec.md` (schema/lộ trình) + `CLAUDE.md` (quy ước code) + `docs/design.html` (UI/ERD/use case), theo đúng thứ tự ưu tiên khi có mâu thuẫn: `financial-core-v2.md` > 3 file còn lại.**

Đã kiểm tra tính nhất quán (Phase 1 + Phase 2, xem `docs/audit-pre-implementation.md`, `docs/final-design-audit.md`, `docs/design-resolution-report.md`):

| Hạng mục | Nhất quán? |
|---|---|
| 3 loại giao dịch (Income/Expense/Transfer) | ✅ |
| Fund model (không trừ kép) | ✅ |
| Savings model (`SavingsAssetType` tổng quát) | ✅ (đã sửa xung đột nội bộ trong chính `financial-core-v2.md`) |
| Category (System vs User) | ✅ |
| Reversal ledger + state machine | ✅ |
| Công thức tài chính (3 tổng tách biệt) | ✅ |
| Use case count (38) | ✅ |
| Screen count (17) | ✅ |
| Demo data (các số liệu trùng lặp giữa màn hình) | ✅ |
| `clientTxId` idempotency (đặc tả) | ✅ — nhưng CODE chưa implement, xem mục 6 |

**Kết luận mục 1: NHẤT QUÁN — không có 2 định nghĩa song song cho cùng 1 nghiệp vụ ở bất kỳ đâu trong 4 tài liệu.**

---

## 2. FINAL BUSINESS RULES

| Rule | Định nghĩa duy nhất |
|---|---|
| **Transaction types** | Đúng 3 giá trị: `INCOME`, `EXPENSE`, `TRANSFER`. Suy từ vị trí `sourceKind`/`destinationKind`: `sourceKind=EXTERNAL` → INCOME; `destinationKind=EXTERNAL` → EXPENSE; cả 2 đều không phải EXTERNAL → TRANSFER. |
| **Income** | `source=EXTERNAL` → `destination` (MEMBER_AVAILABLE) tăng đúng `amountMinor`. Tăng `Total Assets`. |
| **Expense** | `destination=EXTERNAL`. Nếu `source=MEMBER_AVAILABLE` → ví thành viên giảm; nếu `source=FUND` → **chỉ** quỹ giảm, ví thành viên KHÔNG đổi. Giảm `Total Assets`. |
| **Transfer** | Cả 2 đầu không phải EXTERNAL. Không bao giờ đổi `Total Assets`. 5 `transferKind`: `MEMBER_TO_MEMBER`, `FUND_TOPUP`, `FUND_WITHDRAW`, `SAVINGS_TOPUP`, `SAVINGS_WITHDRAW`, `SAVINGS_CONVERT`. Cấm source = destination (Invariant 15). |
| **Member balance** | `MEMBER_AVAILABLE(uid)` — derived, = Σ `applyEffect` toàn bộ transaction chạm pool này. Không bao giờ âm. Không reset theo tháng (cộng dồn từ đầu). |
| **Fund** | 1 pool dùng chung cả gia đình (`FUND(fundId)`). Nạp = `TRANSFER(FUND_TOPUP)`. Chi dùng quỹ = `EXPENSE` với `source=FUND`. Không bao giờ âm. Xoá chỉ khi `balance=0` (soft-delete). Không có subcollection lịch sử riêng — lịch sử = lọc `TRANSACTION`. |
| **Savings** | KHÔNG phải Category kiểu Chi — luôn là `TRANSFER`, category "Tiết kiệm" cố định. 3 `transferKind`: `SAVINGS_TOPUP`/`SAVINGS_WITHDRAW`/`SAVINGS_CONVERT`. |
| **SavingsAssetType** | Entity gia đình tự tạo (id/tên/màu/isActive), không giới hạn số lượng. Mỗi loại = 1 pool RIÊNG cho TỪNG thành viên (`PoolKind.memberSavingsAsset`, `refId = assetTypeId|uid`). Đây là **mô hình Savings duy nhất** — không có model cố định cash/bank song song. |
| **Category** | Nhãn phân loại + `type` (3 giá trị) để nhóm báo cáo — KHÔNG quyết định dòng tiền. 2 loại: **System category** (`type=TRANSFER`, `isDefault=true`, không tự tạo/xoá qua UI — "Chuyển tiền cho thành viên khác", "Nạp quỹ", "Tiết kiệm") và **User category** (`type=INCOME`/`EXPENSE`, CRUD tự do). |
| **Status** | Subcollection của Category, tự đặt tên/thứ tự, không giới hạn số bước. KHÔNG BAO GIỜ ảnh hưởng balance (Invariant 9). |
| **Reversal** | `TRANSACTION` append-only cho field ảnh hưởng balance. Sửa/xoá = tạo bản ghi mới (`reversalOfTxId`/`correctsTxId`), đánh dấu `reversedByTxId` lên bản gốc. Không hoàn tác 2 lần trên cùng giao dịch (Invariant 13). Xem state machine §21.1. |
| **Edit** | Field ảnh hưởng balance (`amountMinor`, "người tiêu") → qua reversal ledger (reverse + tạo bản thay thế). Field không ảnh hưởng balance (`note`/`categoryId` cùng type/`transactionDate`/`statusId`) → update thẳng. Không bao giờ đổi `type`/`transferKind`/`sourceKind`/`destinationKind`. Luôn thao tác trên bản mới nhất (Invariant 14). |
| **Delete/Void** | `deleteTransaction` = `reverseTransaction`. KHÔNG có state "voided" tách biệt — chỉ có ACTIVE/REVERSED (§21.1). Category/Status/Fund/Member "xoá" = soft-delete riêng, không đụng balance. |
| **Summary (Month Rollup)** | `totalIncome`/`totalExpense`/`totalTransfer` tách biệt hoàn toàn theo `type`, bỏ qua `excludeFromTotals`. Transfer không bao giờ cộng vào Income/Expense. |
| **Net income** | Chỉ áp dụng cho category Income có `linkedExpenseCategoryId`: = Σ Income đó − Σ Expense liên kết (mọi status). Report-only, không đổi `Total Income`/`Total Expense`/`Total Assets`. |
| **Total assets** | `= Available Money (Σ MEMBER_AVAILABLE) + Savings Assets (Σ MEMBER_SAVINGS_ASSET mọi loại, mọi thành viên) + Fund Assets (Σ FUND.balance)`. Cuối kỳ = đầu kỳ + Total Income − Total External Expense (Transfer tự cân bằng, không xuất hiện trong công thức). |

---

## 3. FINAL ENTITY MODEL

| Entity | Fields chính | PK | FK | Enum | Relationships | Nullable | Validation | Delete behavior |
|---|---|---|---|---|---|---|---|---|
| `FAMILY` | name, accountType, syncMode, ownerUid, createdAt, memberIds | familyId | — | accountType{personal,family}; syncMode{local,cloud} | 1—N mọi entity con | — | — | Không xoá |
| `MEMBER` | displayName, roleLabel, joinedAt, isOwner, isActive | uid | familyId | — (Giai đoạn A: `FamilyMember{vo,chong}` cố định, cố ý chưa tổng quát) | N—N Transaction (source/destination) | roleLabel tự do | — | Soft delete (`isActive`) |
| `INVITE` | code, suggestedRoleLabel, createdBy, createdAt, expiresAt, maxUses, usedCount | inviteId | familyId | — | — | — | code 6-8 ký tự ngẫu nhiên | Tự hết hạn |
| `CATEGORY` | name, color, type, statsEnabled, excludeFromTotals, linkedExpenseCategoryId, isDefault, isActive | categoryId | familyId | type{INCOME,EXPENSE,TRANSFER} | 1—N Status; 1—N Transaction; self-ref qua linkedExpenseCategoryId | linkedExpenseCategoryId (chỉ hợp lệ khi type=INCOME) | type=TRANSFER bắt buộc isDefault=true | Soft delete (`isActive`), vẫn chọn được khi sửa giao dịch cũ tham chiếu nó |
| `STATUS` | name, sortOrder, isActive | statusId | categoryId | — | N—1 Category; 1—N Transaction | — | Không giới hạn số bước | Soft delete |
| `FUND` | name, color, isActive, balance(derived) | fundId | familyId | — | 1—N Transaction (source/destination) | — | balance không âm | Soft delete chỉ khi balance=0 |
| `SAVINGS_ASSET_TYPE` | name, color, isActive | assetTypeId | familyId | — | 1—N Transaction (qua refId ghép); N—N Member (qua pool) | — | balance mọi thành viên không âm | Soft delete chỉ khi MỌI thành viên = 0 ở loại này |
| `TRANSACTION` | type, transferKind, categoryId, sourceKind/sourceRefId, destinationKind/destinationRefId, amountMinor, currency, note, statusId, statusUpdatedAt, transactionDate, createdAt, createdBy, clientTxId, version, reversalOfTxId, correctsTxId, reversedByTxId | txId | familyId, categoryId, statusId?, (sourceRefId/destinationRefId trỏ Member/Fund/SavingsAssetType tuỳ kind) | type{INCOME,EXPENSE,TRANSFER}; transferKind{6 giá trị}; sourceKind/destinationKind{MEMBER_AVAILABLE, MEMBER_SAVINGS_ASSET, FUND, EXTERNAL} | N—1 Category; N—1 Status; N—1 Member/Fund/SavingsAssetType (qua source/destination) | sourceRefId/destinationRefId null khi kind=EXTERNAL; transferKind null trừ khi type=TRANSFER; statusId null nếu category không có statuses | amountMinor luôn dương (Invariant 12); source≠destination (Invariant 15); clientTxId unique per family | **Append-only** — không update/xoá field ảnh hưởng balance; "xoá" = reverse (state machine §21.1) |
| `MEMBER_BALANCE` | availableBalance, savingsByAssetType (map) | uid | — | — | 1—1 Member | — | Mọi giá trị không âm | Derived, không cần xoá — rebuild từ TRANSACTION |
| `MONTH_SUMMARY` | totalIncome, totalExpense, totalTransfer, categoryTotals, statusTotals, memberTotals | yearMonth | familyId | — | 1—N Transaction (con) | — | totalTransfer không cộng vào totalIncome/totalExpense | Derived |
| `BUDGET` | categoryLimits (map) | yearMonth | familyId | — | N—1 Category (qua map key) | — | Chỉ cộng dồn type=EXPENSE | Không xoá |

**Không có entity nào "hiểu theo nhiều cách"** — mỗi entity chỉ có đúng 1 định nghĩa field/enum trong toàn bộ 4 tài liệu (đã đối chiếu ở Phase 1/2).

---

## 4. FINANCIAL INVARIANTS (15, bắt buộc đúng — `financial-core-v2.md` §18)

1. Mỗi transaction chạm tối đa 2 pool.
2. `TRANSFER` không làm thay đổi Income/Expense/Total Assets.
3. `EXPENSE` giảm Total Assets đúng `amountMinor`.
4. `INCOME` tăng Total Assets đúng `amountMinor`.
5. `EXPENSE` với `source=FUND` không làm giảm `MEMBER_AVAILABLE` lần nữa (không trừ kép).
6. Nạp Quỹ/Tiết kiệm: đúng 1 pool nguồn giảm + đúng 1 pool đích tăng, cùng lúc, cùng giá trị.
7. Quỹ/Tiết kiệm/`MEMBER_AVAILABLE` không bao giờ âm.
8. Sửa/xoá bắt buộc qua Financial Engine — reversal phải hoàn nguyên đúng hiệu ứng gốc; correction sau reversal phải tạo hiệu ứng mới chính xác.
9. Status change không bao giờ làm thay đổi balance.
10. Balance/rollup luôn rebuild được 100% từ `TRANSACTION` gốc.
11. Category/Status/Fund/Member "xoá" chỉ soft-delete.
12. `amountMinor` luôn dương.
13. Không hoàn tác 2 lần trên cùng 1 giao dịch.
14. Sửa nhiều lần liên tiếp luôn thao tác trên bản mới nhất.
15. `TRANSFER` cấm source = destination (Savings conversion không được "chuyển đổi" cùng 1 loại — không tạo/mất tiền ngoài đúng 2 pool source/destination).

Tất cả 15 invariant đều phát biểu được rõ ràng, không có invariant nào mơ hồ → **không rơi vào điều kiện NOT READY của mục này.**

---

## 5. TEST MATRIX (Financial Engine — 20 test case, `financial-core-v2.md` §24)

| ID | Scenario | Initial state | Action | Expected ledger | Expected balance | Expected income/expense | Result |
|---|---|---|---|---|---|---|---|
| 1-5 | Income/Expense/Transfer cơ bản + không lẫn nhau | Pools = 0 | Tạo từng loại | 1 transaction/loại | Đúng dấu theo type | Income/Expense tách biệt, Transfer không cộng vào cả 2 | PASS (đã test) |
| 6 | Nạp quỹ | Member 5tr, Fund 0 | `TRANSFER(FUND_TOPUP)` 2tr | 1 transaction | Member 3tr, Fund 2tr | Không đổi | PASS |
| 7 | Chi từ quỹ | Member 3tr, Fund 2tr | `EXPENSE(source=FUND)` 500k | 1 transaction | Member 3tr (KHÔNG đổi), Fund 1.5tr | Expense +500k | PASS |
| 8 | Chi không dùng quỹ | Member 3tr, Fund 2tr | `EXPENSE(source=MEMBER_AVAILABLE)` 500k | 1 transaction | Member 2.5tr, Fund 2tr (không đổi) | Expense +500k | PASS |
| 9 | (giữ nguyên theo yêu cầu gốc) | — | — | — | — | — | PASS |
| 10 | Sửa Expense 500k→800k | Member -500k | `updateTransaction(amount=800k)` | gốc REVERSED, +2 bản mới (reversal, replacement) | Member -800k (chỉ phần chênh -300k bị trừ thêm) | Expense hiệu lực = 800k | PASS (test thật đã có) |
| 11 | **RÚT KHỎI ma trận bắt buộc** | — | Sửa đổi hẳn `type` | — | — | — | N/A — cấm ở §21, không cần Engine hỗ trợ |
| 12 | Double-submit | — | 2 request cùng `clientTxId` | Chỉ 1 transaction | Không đổi thêm | Không đổi thêm | **[IMPLEMENTATION BLOCKER]** — chưa test được vì chưa code guard |
| 13 | Xoá Income | Member +10tr (từ 1 Income) | `deleteTransaction` | Bản gốc REVERSED + 1 reversal | Member -10tr (về lại mốc trước Income) | Total Assets -10tr | PASS (logic), chưa có test tự động riêng |
| 14 | Budget không bị Transfer ảnh hưởng | Budget Sinh hoạt 3tr, đã chi 2tr | Nạp tiết kiệm (Transfer) 5tr | — | — | Budget vẫn báo 2/3tr | PASS (logic, Budget chưa code — Giai đoạn E) |
| 15 | Rebuild từ đầu | Cache đã xoá | Chạy lại `applyEffect` mọi transaction | — | Khớp 100% cache cũ | Khớp 100% | PASS (logic, `computeAllPoolBalances` design đúng) |
| 16 | `excludeFromTotals` | — | Income "Số dư ban đầu" 5tr + Income "Lương" 10tr | 2 transaction | availableBalance +15tr | totalIncome chỉ +10tr | PASS (test thật đã có) |
| 17 | "Thu hộ, phải trả lại" | — | Income 2tr + Expense (status) 1tr | 2 transaction riêng | +1tr ròng | totalIncome +2tr, totalExpense +1tr (không gộp net) | PASS (logic) |
| 18 | "Thu nhập ròng" | — | Income 5tr (linked) + Expense 2tr(status1)+1tr(status2) | 3 transaction | Không đổi thêm (report-only) | Net income = 2tr hiển thị thêm | PASS (test thật đã có) |
| 19 | Chặn hoàn tác 2 lần | Tx đã REVERSED 1 lần | `reverseTransaction` lần 2 | Bị từ chối | Không đổi | Không đổi | **[IMPLEMENTATION BLOCKER]** — Invariant 13 chưa code |
| 20 | Sửa 2 lần liên tiếp | Tx đã sửa 1 lần (R1) | Sửa lần 2 trên R1 | `correctsTxId` của R2 trỏ R1 (không phải bản gốc) | Đúng giá trị lần sửa cuối | — | **[IMPLEMENTATION BLOCKER]** — Invariant 14 chưa audit UI |
| 21 | Chặn source=destination | — | `SAVINGS_CONVERT` cùng loại tài sản | Bị từ chối | Không đổi | Không đổi | **[IMPLEMENTATION BLOCKER]** — Invariant 15 chưa code |

**Edge case bổ sung** (amount=0/âm/lớn, category xoá, fund/savings archived, offline retry...) — xem bảng đầy đủ ở `financial-core-v2.md` §27.

---

## 6. IMPLEMENTATION BOUNDARY

| Layer | Trách nhiệm |
|---|---|
| **UI** (`presentation/`) | Thu thập input, hiển thị dữ liệu đã tính sẵn từ domain/usecases, gọi đúng use case/repository method. **KHÔNG được tự tính balance/tổng/tỷ lệ** — mọi phép tính tài chính đi qua `domain/usecases/*` hoặc `domain/engine/financial_engine.dart`. |
| **Application/Use case layer** (`domain/usecases/`) | Điều phối nghiệp vụ cấp cao (`computeThreeTotals`, `computeMemberFinancials`, `computeNetIncome`...) — gọi Financial Engine, không tự ý cộng/trừ pool trực tiếp. |
| **Domain/Financial Engine** (`domain/engine/financial_engine.dart`) | **Nguồn sự thật duy nhất cho "tiền chạy đi đâu"** — `applyEffect`, `buildReversal`, `buildCorrection`, `computeAllPoolBalances`, `wouldGoNegative`. Không phụ thuộc Firebase/UI. Đây là nơi bắt buộc thêm 3 guard còn thiếu (Invariant 13/14/15). |
| **Repository** (`data/repositories/`) | Implement interface domain (`TransactionRepository`...), map domain entity ↔ DB row, gọi Financial Engine để validate trước khi ghi (`_assertWontGoNegative`), enforce `clientTxId` unique. Không chứa business logic tài chính riêng ngoài validate + gọi Engine. |
| **Database** (`data/local/app_database.dart`, Drift/SQLite) | Lưu trữ persistent, cung cấp transaction/atomic write (`_db.transaction`). Cần thêm unique index cho `clientTxId`. |
| **Sync tương lai** (Giai đoạn B, Firestore) | Thay implementation của `TransactionRepository`/`CategoryRepository`/... bằng `Firestore*Repository`, chọn theo `syncMode` lúc runtime. Cloud Function thực hiện lại đúng `applyEffect` (không có logic tài chính khác ở Cloud Function so với `financial_engine.dart`) + validate FK thuộc đúng family (F-13) + Security Rules là lớp phòng thủ thứ 2, không phải duy nhất. |

**Xác nhận: UI không tự tính financial balance ở bất kỳ file nào đã audit** (`home_screen.dart`, `savings_screen.dart`, `fund_detail_screen.dart` đều gọi `compute*`/`financial_engine` functions, không tính tay).

---

## 7. DESIGN FREEZE RULE (áp dụng từ thời điểm này)

- Không tự ý thay đổi business rule khi đang code Giai đoạn A tiếp theo.
- Nếu implementation phát hiện xung đột với tài liệu (vd 1 Invariant không khả thi kỹ thuật) → **DỪNG, báo cáo, không tự workaround bằng cách đổi domain logic ngầm.**
- Mọi thay đổi business rule phải được cập nhật vào `docs/financial-core-v2.md` (+ đồng bộ 3 file còn lại) **trước khi** code tiếp tục dựa trên thay đổi đó.

---

## FINAL OUTPUT

**DESIGN FREEZE = READY**

Chưa code. Toàn bộ business rule, entity model, invariant, và ranh giới layer đã được đặc tả rõ ràng, nhất quán giữa `financial-core-v2.md`/`spec.md`/`CLAUDE.md`/`design.html`. 5 mục ở bảng Test Matrix/Invariant được đánh dấu `[IMPLEMENTATION BLOCKER]` không phải điều "chưa xác định" — chúng là các validate/guard đã có đặc tả đầy đủ (Invariant 13/14/15, unique `clientTxId`, `amountMinor>0` ở tầng repository) nhưng chưa được viết code, đúng như phạm vi mọi phase audit/thiết kế trước khi implementation. Dự án sẵn sàng bước vào implementation, với điều kiện: PR đầu tiên đụng tới `LocalTransactionRepository`/`AppDatabase` phải giải quyết 5 mục blocker này trước khi coi Financial Engine là hoàn chỉnh.
