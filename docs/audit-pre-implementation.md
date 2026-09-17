# Audit toàn bộ thiết kế & đặc tả — trước khi code Giai đoạn A trở đi

**Ngày:** 2026-09-16 · **Phạm vi:** `spec.md`, `CLAUDE.md`, `docs/financial-core-v2.md`, `docs/design.html` (ERD + sơ đồ use case + 17 màn mockup + 3 tab "Tài liệu" nhúng), và toàn bộ `lib/` + `test/` hiện có (chỉ đọc để phát hiện xung đột, **không sửa code**).

**Không có dòng code ứng dụng nào bị thay đổi trong audit này** — đây thuần là tài liệu đối chiếu. Mọi đề xuất bên dưới là việc cần làm ở bước tiếp theo (sửa tài liệu trước, sau đó mới chạm code nếu cần).

**Phương pháp:** đọc toàn văn `spec.md` (354 dòng), `docs/financial-core-v2.md` (495 dòng), `CLAUDE.md` (94 dòng); đọc toàn bộ ERD + sơ đồ use case + tất cả 17 caption màn hình trong `docs/design.html` (2883 dòng) và đọc chi tiết nội dung 6 màn hình (06, 07, 08, 09, 11, 12, 13, 15, 16); đọc trực tiếp toàn bộ entity/engine/repository cốt lõi trong `lib/domain/` + `lib/data/repositories/local_transaction_repository.dart` + 3 màn hình Flutter (`home_screen.dart`, `savings_screen.dart`, `fund_detail_screen.dart`) + `add_transaction_sheet.dart`/`category_edit_screen.dart` (grep có mục tiêu); đọc toàn bộ 3 file test hiện có. Các màn hình Flutter còn lại (`category_list_screen.dart`, `transaction_list_screen.dart`, `transaction_detail_screen.dart`, `summary_screen.dart`, `fund_list_screen.dart`, `settings_screen.dart`) **chưa đọc toàn văn** — chỉ đối chiếu gián tiếp qua provider/domain layer chúng dùng; nếu cần audit sâu hơn các màn này, nên làm 1 lượt riêng.

---

## Tóm tắt điều hành (đọc trước nếu vội)

| # | Mức độ | Phát hiện |
|---|---|---|
| 1 | **[BLOCKER — text tài liệu, không phải code]** | `docs/design.html` dòng 1000 mô tả lại đúng lỗi trừ kép Quỹ (F-03) mà Financial Core V2 đã sửa — xem mục A bên dưới. |
| 2 | **[CONFLICT]** | Mô hình Tiết kiệm: code + `financial-core-v2.md` §9 đã tổng quát hoá (`SavingsAssetType` tự do) nhưng `CLAUDE.md` §9, `spec.md` (khối schema + bảng seed), ERD trong `design.html`, và **chính `financial-core-v2.md` §6/§14** vẫn mô tả model cũ cố định `MEMBER_SAVINGS_CASH`/`MEMBER_SAVINGS_BANK`. |
| 3 | **[DESIGN DATA INCONSISTENCY]** | Số liệu demo Tiết kiệm ở màn 08 (Trang chủ) và màn 16 (Tiết kiệm — Quản lý) không khớp nhau. |
| 4 | **[CONFLICT — đếm sai]** | Sơ đồ use case: header ghi "37 use case", đếm thực tế trong Mermaid là **38** (32 mã U01-U32 + 6 mã chữ cái không theo thứ tự: U16b, U20b, U20c, U23a/b/c). |
| 5 | **[CONFLICT — đếm sai]** | `spec.md` dòng 28 và `CLAUDE.md` dòng 94 vẫn ghi "18 màn hình mô phỏng"; `docs/design.html` (nguồn thật) đã tự sửa còn **17** và hiển thị đúng 17. |
| 6 | **[GAP — chưa implement, không phải conflict tài liệu]** | Chống double-submit (`clientTxId`) được tài liệu hoá là bắt buộc (F-12, Invariant, index ở FC-V2 §14) nhưng **chưa có ràng buộc unique nào** trong `AppDatabase` (Drift) lẫn logic `LocalTransactionRepository.addTransaction` — 2 lần bấm Lưu với cùng `clientTxId` vẫn tạo 2 giao dịch. |
| 7 | **[CONFLICT nội bộ trong `financial-core-v2.md`]** | §14 (bảng Database Schema V2) không liệt kê entity `SAVINGS_ASSET_TYPE` dù §9 định nghĩa chi tiết — bảng schema tổng hợp bị bỏ sót. |
| 8 | **[CONFLICT nội bộ trong `financial-core-v2.md`]** | Test 11 (§24) và edge case "đổi hẳn `type`" (§19) mô tả 1 khả năng mà §21 (quyết định phạm vi UI, viết sau) đã minh thị cấm ("không sửa được `type`") và `buildCorrection()`/`TransactionRepository.updateTransaction()` trong code không có tham số nào cho phép đổi `type`/`sourceKind`/`destinationKind` — test case này hiện không thể tự động hoá được với chữ ký hàm hiện tại. |
| 9 | **[GAP phòng vệ, mức thấp]** | `amountMinor > 0` (Invariant 12) chỉ được ép ở `assert()` trong constructor `Transaction` — bị Dart **loại bỏ hoàn toàn ở bản release** (`flutter build --release` tắt `assert`). Có UI-layer guard (`_buildTransaction` trả `null` nếu `_amount <= 0`) nên rủi ro thực tế thấp ở Giai đoạn A, nhưng không có phòng vệ ở tầng repository/DB — cùng nguyên tắc "không chỉ tin client" mà chính tài liệu yêu cầu cho Cloud Function sau này. |

Không phát hiện lỗi trừ kép nào **trong code thật** (`local_transaction_repository.dart`, `financial_engine.dart`) — F-03 đã được sửa đúng và có test (Test 6/7/8). Không phát hiện hardcode `if (categoryId == 'cho_di')`/`'dang_hien'` nào trong `domain/`/`presentation/` — nguyên tắc CLAUDE.md §9 được tôn trọng trong code hiện tại.

---

## Phần 1-2 — Bản đồ hệ thống & xác định Source of Truth

**Thứ tự ưu tiên nguồn sự thật đã xác định được qua đối chiếu (không phải mặc định — suy ra từ việc code thật đã implement đúng cái nào):**

1. **Code hiện có trong `lib/`** (đã qua phase 1-17, xem `spec.md` Giai đoạn A) — đây là bằng chứng "đã chạy được", nặng ký nhất khi có mâu thuẫn về **model tài chính**.
2. **`docs/financial-core-v2.md`** — đúng với code ở hầu hết các mục, nhưng **tự mâu thuẫn nội bộ** ở 2 chỗ (savings model §6/§9, và Test 11 §19/§21/§24) vì tài liệu được viết dần qua nhiều lượt mà không rà lại các mục cũ mỗi khi có quyết định mới.
3. **`spec.md`** — bản tóm tắt kỹ thuật, nhưng phần "Tài khoản theo từng thành viên"/schema Firestore chưa đồng bộ theo savings model tổng quát hoá (viết trước khi phase 15 tổng quát hoá savings, và không được cập nhật lại).
4. **`CLAUDE.md`** — đúng nguyên tắc lớn ("category là dữ liệu", Financial Engine 1 hàm duy nhất...) nhưng ví dụ cụ thể trong §9 (liệt kê `MEMBER_SAVINGS_CASH`/`MEMBER_SAVINGS_BANK`) đã lỗi thời.
5. **`docs/design.html`** — hỗn hợp: ERD + 1 đoạn caption đã lỗi thời (model cũ), nhưng phần lớn caption màn hình (đặc biệt màn 09, 15, 16) đã cập nhật đúng V2, thậm chí **đúng hơn** ERD trong cùng file.

**Bản đồ nhanh 18 mục yêu cầu (Phần 1) — nơi mỗi mục thực sự được định nghĩa:**

| Mục | Định nghĩa ở đâu (nguồn đúng nhất) |
|---|---|
| Business rules | `docs/financial-core-v2.md` §3, §16, §18 (Invariants) |
| Financial model | `docs/financial-core-v2.md` §4-§9 + `lib/domain/engine/financial_engine.dart` |
| Entity/model | `lib/domain/entities/*.dart` (code) khớp `financial-core-v2.md` §6, §11, §14 (trừ savings, xem CONFLICT #2) |
| Transaction model | `lib/domain/entities/transaction.dart` — khớp đúng §6 |
| Balance calculation | `lib/domain/engine/financial_engine.dart` (`computeAllPoolBalances`) — xem bảng Phần 10 bên dưới |
| Fund/Pool | `lib/domain/entities/pool_kind.dart` + `lib/domain/usecases/compute_pool_balance.dart` |
| Savings | Code + FC-V2 §9 (tổng quát hoá) — **nhưng 4 tài liệu khác chưa đồng bộ**, xem CONFLICT #2 |
| Category | `lib/domain/entities/category.dart` — khớp FC-V2 §11 |
| Status | `lib/domain/entities/status.dart` — khớp FC-V2 §12 |
| Member | `lib/domain/entities/family_member.dart` — **vẫn enum cố định `{vo, chong}`**, đúng như đã ghi nhận là cố ý hoãn tới Giai đoạn B phase 24 (`spec.md` dòng 239) |
| Family | `spec.md` khối schema `families/{familyId}` — chưa có code thật (Giai đoạn A local-first, chưa tới Giai đoạn B) |
| UI flow | `docs/design.html` 17 màn — xem Phần 11 |
| Navigation | `lib/presentation/shell/app_shell.dart` + `lib/core/router/app_router.dart` (chưa đọc toàn văn — khuyến nghị audit riêng nếu cần) |
| Local database | `lib/data/local/app_database.dart` (Drift/SQLite) |
| Sharing/sync | `spec.md` Giai đoạn B (chưa code — đúng kế hoạch, chưa tới phase) |
| Reversal/Edit/Delete | `lib/domain/engine/financial_engine.dart` (`buildReversal`/`buildCorrection`) + `lib/data/repositories/local_transaction_repository.dart` — khớp đúng FC-V2 §21, xem Phần 6 |
| Validation | Rải rác — xem GAP #6, #9 ở trên |
| Edge cases | Xem Phần 14 bên dưới |

---

## A. [BLOCKER] Text mô tả lỗi trừ kép Quỹ còn sót lại trong `docs/design.html`

**Vị trí:** `docs/design.html` dòng 1000 — đoạn giới thiệu nhóm màn "Ghi chép hằng ngày" (ngay phía trên màn 08/09):

> "Thêm giao dịch giờ có ô tích 'Quỹ tiền ăn' — **tích thì vừa trừ số dư người ghi vừa trừ số dư quỹ**, không tích thì chỉ trừ số dư như bình thường."

Đây **chính xác là mô tả lỗi F-03 (trừ kép)** mà `docs/financial-core-v2.md` liệt kê là **CRITICAL** và đã sửa: "Nạp quỹ trừ số dư người nạp (Chi) **và** khi mua bằng quỹ tích tiếp lại trừ cả số dư người mua **lẫn** số dư quỹ". Đoạn text này là tàn dư từ bản V1, không được xoá khi màn 09 được vẽ lại theo V2.

**Bằng chứng nó đã lỗi thời:** ngay caption của chính màn 09 (dòng 1168, cách đó 168 dòng) lại mô tả **đúng** hành vi V2: "không trừ số dư Vợ, chỉ quỹ mới bị chặn (đúng model V2, không trừ kép)". Code thật (`local_transaction_repository.dart`, `financial_engine.dart`, test Test 7/8) cũng làm đúng — **chỉ đoạn text giới thiệu nhóm màn ở dòng 1000 là sai/lỗi thời**, tự mâu thuẫn với chính màn ngay bên dưới nó.

**Ảnh hưởng:** người đọc lướt (developer mới, hoặc chính chủ dự án xem lại sau nhiều tháng) rất dễ hiểu nhầm ngay từ câu giới thiệu, trước khi đọc tới caption chi tiết đúng hơn.

**Đề xuất:** sửa dòng 1000 thành mô tả đúng V2, ví dụ: *"Thêm giao dịch giờ chọn được 'Nguồn tiền' là Quỹ thay vì ví chính — chọn Quỹ thì chỉ trừ đúng quỹ đó, không đụng số dư người ghi (đúng model V2, không trừ kép)."*

---

## B. [CONFLICT] Mô hình Tiết kiệm — 2 phiên bản đang tồn tại song song trong tài liệu

**File/vị trí giữ model MỚI (đúng, tổng quát hoá — khớp code):**
- `docs/financial-core-v2.md` §9 (dòng 192-209): `SAVINGS_ASSET_TYPE` do gia đình tự tạo, `PoolKind.memberSavingsAsset`, `TransferKind.savingsConvert` thay `SAVINGS_TO_BANK`.
- Code: `lib/domain/entities/pool_kind.dart` (`memberSavingsAsset`, `savingsAssetRefId`), `lib/domain/entities/transfer_kind.dart` (`savingsConvert`), `lib/domain/entities/savings_asset_type.dart`, `lib/presentation/features/savings/savings_screen.dart` (CRUD loại tài sản đầy đủ, `+ Thêm loại tài sản`).
- `docs/design.html` caption màn 16 (dòng 1389): tự ghi chú rõ "Đã tổng quát hoá... Hiện tại/Ngân hàng ở mockup này chỉ là 2 ví dụ minh hoạ".

**File/vị trí vẫn giữ model CŨ (2 pool cố định — lỗi thời):**
- `docs/financial-core-v2.md` **chính nó**, ở 2 mục khác: §6 bảng Transaction Model (dòng 109-116, liệt kê `transferKind` gồm `SAVINGS_TOPUP | SAVINGS_WITHDRAW | SAVINGS_TO_BANK`, và `sourceKind` gồm `MEMBER_SAVINGS_CASH | MEMBER_SAVINGS_BANK`); §14 bảng Database Schema V2 không có dòng nào cho `SAVINGS_ASSET_TYPE`.
- `CLAUDE.md` §9 (đoạn "Dòng tiền thật nằm trên `Transaction`..."): liệt kê `MEMBER_SAVINGS_CASH`, `MEMBER_SAVINGS_BANK` như 2 giá trị cố định của `sourceKind`.
- `spec.md`: khối schema Firestore (`transferKind` liệt kê `SAVINGS_TO_BANK`; `sourceKind`/`destinationKind` liệt kê `MEMBER_SAVINGS_CASH`/`MEMBER_SAVINGS_BANK` cố định; `memberBalances/{uid}` có field cứng `savingsCash`/`savingsBank` thay vì 1 cấu trúc theo `assetTypeId`).
- `docs/design.html` ERD (native, không phải bản nhúng) dòng 715-744: `TRANSACTION.sourceKind` comment "MEMBER_AVAILABLE/SAVINGS_CASH/SAVINGS_BANK/FUND/EXTERNAL", entity `MEMBER_BALANCE` có field cứng `savingsCash`/`savingsBank` — **không hề nhắc tới `SAVINGS_ASSET_TYPE`**.
- `docs/design.html` màn 08 (Trang chủ) mockup (dòng 1010-1022): mỗi thẻ thành viên có đúng 2 dòng cố định "TK hiện tại"/"Đã gửi NH" — **không có caveat như màn 16**, và thực tế đã lỗi thời so với code thật (`home_screen.dart` hiện chỉ hiện 1 con số "Tiết kiệm" gộp + dòng chữ "Xem theo từng loại tài sản ở Cài đặt › Tiết kiệm", đúng nguyên tắc tổng quát hoá).

**Vì sao sai / rủi ro:** một developer đọc `spec.md` hoặc `CLAUDE.md` (2 tài liệu được liệt là "canonical") trước khi đọc kỹ `financial-core-v2.md` §9 sẽ dựng nhầm lại đúng model cứng 2-loại mà dự án đã chủ động từ bỏ — tốn công viết lại, và nếu đã có dữ liệu thật theo model tự do thì migrate ngược sẽ mất thông tin (không map được 1-1 nếu gia đình đã tạo loại tài sản thứ 3 trở lên).

**Đề xuất thống nhất:** `docs/financial-core-v2.md` §9 (+ code) là **source of truth** — đây là bản đã audit kỹ nhất, có lý do rõ ràng ("nguyên tắc dữ liệu không phải hằng số cứng"), và **code đã chạy đúng theo nó**. Cần cập nhật đồng bộ ngược lại:
1. `financial-core-v2.md` §6 và §14 (tự sửa lỗi nội bộ trước).
2. `spec.md` — sửa khối schema Firestore, bảng `memberBalances` (đổi từ field cứng sang cấu trúc theo asset type), bảng liệt kê `transferKind`/`sourceKind`.
3. `CLAUDE.md` §9 — sửa đoạn ví dụ liệt kê `MEMBER_SAVINGS_CASH`/`MEMBER_SAVINGS_BANK`.
4. `docs/design.html` — sửa ERD (entity `MEMBER_BALANCE`, comment trên `TRANSACTION`), và vẽ lại màn 08 để không hiện cứng 2 dòng "TK hiện tại"/"Đã gửi NH" (nên hiện tổng tiết kiệm gộp, khớp đúng những gì `home_screen.dart` thật đang làm).

---

## C. [DESIGN DATA INCONSISTENCY] Số liệu demo Tiết kiệm giữa màn 08 và màn 16

- **Màn 08 (Trang chủ):** Vợ — "TK hiện tại" 1.200.000đ + "Đã gửi NH" 8.000.000đ = 9.200.000đ. Chồng — "TK hiện tại" 500.000đ + "Đã gửi NH" 5.500.000đ = 6.000.000đ.
- **Màn 16 (Tiết kiệm — Quản lý):** "Tổng tiết kiệm" 10.500.000đ, chia "Hiện tại" 500.000đ / "Đã gửi NH" 10.000.000đ.

**Khác nhau:** không có tổ hợp nào của (Vợ, Chồng, Vợ+Chồng) từ màn 08 cộng ra đúng 10.500.000đ hay khớp cặp (500.000/10.000.000) của màn 16. Màn 16 không ghi rõ đang xem của ai (mockup tĩnh, không có toggle thành viên thật — dù code thật `savings_screen.dart` có `SegmentedButton<FamilyMember>`), nên không đối chiếu được.

**Nguyên nhân:** 2 màn được vẽ ở 2 thời điểm khác nhau (màn 16 vẽ lại sau khi tổng quát hoá savings ở phase 15, màn 08 không được cập nhật số liệu demo theo).

**Đề xuất:** chọn 1 bộ số liệu demo duy nhất dùng xuyên suốt (xem đề xuất DEMO DATA SOURCE ở Phần 12 bên dưới), rồi rà lại toàn bộ số tiền hiển thị ở màn 08, 09, 10, 12, 13, 14, 15, 16 theo đúng 1 nguồn.

---

## D. Financial Core — đối chiếu 8 kịch bản Transfer (Phần 3 yêu cầu)

Đối chiếu trực tiếp với `applyEffect()` (`lib/domain/engine/financial_engine.dart` dòng 16-25) — hàm duy nhất, không nhánh rẽ theo loại, nên **về mặt thiết kế không thể có lỗi khác nhau giữa các trường hợp** miễn `sourceKind`/`destinationKind` được truyền đúng. Bảng dưới xác nhận từng trường hợp có được 1 `transferKind`/luồng UI hợp lệ hay không:

| # | Kịch bản | Source giảm | Destination tăng | Income đổi? | Expense đổi? | Available đổi? | Net worth đổi? | Đã có luồng UI/transferKind? |
|---|---|---|---|---|---|---|---|---|
| 1 | Member → Member | `MEMBER_AVAILABLE(A)` | `MEMBER_AVAILABLE(B)` | Không | Không | Có (A giảm, B tăng, tổng 2 người không đổi) | Không | Có — `MEMBER_TO_MEMBER` |
| 2 | Member → Fund | `MEMBER_AVAILABLE` | `FUND` | Không | Không | Người nạp giảm | Không | Có — `FUND_TOPUP` |
| 3 | Fund → Member | `FUND` | `MEMBER_AVAILABLE` | Không | Không | Người nhận tăng | Không | Có — `FUND_WITHDRAW` (chỉ dùng khi rút hết quỹ trước khi xoá, FC-V2 §8) |
| 4 | Member → Savings (asset bất kỳ) | `MEMBER_AVAILABLE` | `memberSavingsAsset` | Không | Không | Giảm | Không | Có — `SAVINGS_TOPUP` |
| 5 | Savings → Member | `memberSavingsAsset` | `MEMBER_AVAILABLE` | Không | Không | Tăng | Không | Có — `SAVINGS_WITHDRAW` |
| 6 | Savings Asset → Savings Asset **(cùng 1 người)** | `memberSavingsAsset(loại Y, X)` | `memberSavingsAsset(loại Z, X)` | Không | Không | Không đổi | Không | Có — `SAVINGS_CONVERT` |
| 7 | Fund → Fund | — | — | — | — | — | — | **[DECISION REQUIRED]** — Chưa có `transferKind` nào cho việc này. FC-V2 §7 nói "thêm `transferKind` mới sau này (vd chuyển giữa 2 quỹ) không cần đổi Financial Engine" — đúng về mặt kỹ thuật (engine không cần đổi, chỉ cần cho phép `sourceKind=destinationKind=FUND`), nhưng **chưa có quyết định** nào ghi nhận có cần use case này ở Giai đoạn A hay không. Đề xuất: ghi rõ "để sau, không cần trong Giai đoạn A" nếu đúng vậy, thay vì để ngỏ. |
| 8 | Savings Asset của người A → Savings Asset của người B | — | — | — | — | — | — | **[DECISION REQUIRED]** — Không có luồng nào (transferKind hiện có `savingsConvert` chỉ đổi loại tài sản, không đổi người sở hữu). Nếu gia đình muốn "chuyển tiết kiệm cho nhau" thì phải rút về ví rồi mới chuyển member-to-member rồi mới nạp lại — 3 bước, không rõ có đúng ý định thiết kế hay là 1 lỗ hổng chưa nghĩ tới. Đề xuất: ghi chú tường minh trong `financial-core-v2.md` (không cần code ngay, chỉ cần 1 câu quyết định). |

Không phát hiện trường hợp nào Transfer vô tình bị tính vào Income/Expense trong code (`computeThreeTotals` switch theo đúng `t.type`, Transfer luôn cộng riêng vào `totalTransfer`).

---

## E. Fund/Pool — xác nhận không còn trừ kép trong code

Đối chiếu `local_transaction_repository.dart` + `financial_engine_test.dart`:
- **Nạp quỹ** = 1 transaction `TRANSFER(FUND_TOPUP)`, `applyEffect` trừ đúng 1 pool nguồn (`MEMBER_AVAILABLE`) và cộng đúng 1 pool đích (`FUND`) — test "Test 6" xác nhận.
- **Chi từ quỹ** = 1 transaction `EXPENSE` với `source = FUND` — chỉ pool `FUND` bị trừ, `MEMBER_AVAILABLE` người mua **không được `applyEffect` chạm tới** vì nó không xuất hiện ở `sourceKind`/`destinationKind` của giao dịch đó — test "Test 7" xác nhận rõ ràng bằng assertion "MEMBER_AVAILABLE người mua giữ nguyên".
- **Chi không dùng quỹ** = `EXPENSE` với `source = MEMBER_AVAILABLE` — Fund không đổi — "Test 8" xác nhận.
- **Quỹ không âm:** `_assertWontGoNegative` (dòng 82-96) gọi trước mọi `addTransaction`/`updateTransaction`, ném `InsufficientBalanceException` — có test riêng cho `wouldGoNegative`.
- **Xoá quỹ khi `balance≠0`:** chưa đọc trực tiếp code chặn nút xoá trong `fund_list_screen.dart`/`fund_detail_screen.dart` (chỉ đọc 60 dòng đầu `fund_detail_screen.dart`) — khuyến nghị xác nhận riêng nếu cần chắc chắn 100%, nhưng theo caption màn 15 thì cơ chế này đã được thiết kế đúng.

**Kết luận Phần 4:** không có [BLOCKER — FUND DOUBLE SUBTRACTION] nào trong **code**. Chỉ có 1 chỗ trong **văn bản** (`docs/design.html` dòng 1000, mục A ở trên).

---

## F. Reversal Ledger — mô phỏng 4 case theo yêu cầu

Dựa trên `buildReversal`/`buildCorrection` (`financial_engine.dart`) + `LocalTransactionRepository.updateTransaction`/`reverseTransaction`, đã có unit test cho Case A. Case B/C/D suy luận từ đọc code (chưa có test tự động riêng cho C/D — xem GAP bên dưới).

**Case A — Expense 1.000.000 → sửa thành 800.000 (nhỏ hơn số ví dụ gốc dùng 500k→800k, nhưng cùng cơ chế):**
Ledger cuối: 3 bản ghi — (1) bản gốc 1.000.000, `reversedByTxId` trỏ tới (2); (2) bản reversal (nguồn/đích đảo ngược 1.000.000, `reversalOfTxId` = (1)); (3) bản thay thế 800.000, `correctsTxId` = (1). Balance cuối = -1.000.000 (gốc) +1.000.000 (reversal, hoàn lại) -800.000 (thay thế) = **-800.000**, đúng. Danh sách hiển thị (`isVisible`) chỉ còn (3). Đã có test tương đương (Test 10, 500k→800k) — **PASS theo code đọc được**.

**Case B — Payer A → đổi thành Payer B:**
Đây chính là nhánh `memberChanged` trong `updateTransaction` (dòng 171-181): với `EXPENSE` nguồn `memberAvailable`, đổi "người tiêu" nghĩa là đổi `sourceRefId`. Cũng đi qua `buildCorrection` giống Case A (amount giữ nguyên, chỉ `newSourceRefId` khác) → cùng cơ chế 3 bản ghi, source A được hoàn lại đúng số tiền, source B (bản thay thế) bị trừ đúng số tiền. **Chưa có test tự động riêng cho trường hợp NÀY** (chỉ đổi người, không đổi amount) — khuyến nghị thêm 1 test case tương tự Test 10 nhưng đổi `sourceRefId` thay vì `amountMinor`.

**Case C — Transaction đã sửa 1 lần → sửa lần thứ hai:**
Vì `updateTransaction` luôn thao tác trên `transactionId` được truyền vào (không phải luôn "bản mới nhất"), cần xác nhận UI (`transaction_detail_screen.dart`, chưa đọc toàn văn) luôn mở **bản thay thế mới nhất** (id của bản (3) ở Case A) khi người dùng bấm sửa lần 2, chứ không phải bản gốc (1) đã bị đánh dấu `reversedByTxId`. Nếu UI vô tình giữ id gốc (1) và gọi sửa lần 2 trên id đó, `existing.firstWhere((t) => t.id == transactionId)` trong code (dòng 166) vẫn tìm thấy bản gốc (đã reversed) và tính lại `buildCorrection` dựa trên **giá trị gốc thay vì giá trị đã sửa lần 1** — balance cuối vẫn đúng về mặt số học (vì đều dựa trên cùng chuỗi cộng dồn toàn bộ), nhưng **lịch sử hiển thị** ("sửa lần thứ 2 dựa trên lần 1") sẽ bị rối nếu `correctsTxId` của bản (5) trỏ nhầm về (1) thay vì (3). **[DECISION REQUIRED — cần xác nhận UI luôn truyền id bản mới nhất]**, không phải lỗi số dư mà là lỗi khả năng truy vết lịch sử sửa.

**Case D — Transaction đã sửa → void/delete:**
`deleteTransaction` = gọi `reverseTransaction(txId)` (FC-V2 §21). Nếu gọi trên id bản gốc (1) đã bị reversed, `reverseTransaction` (dòng 115-134) vẫn chạy được (nó không kiểm tra `original.isReversed` trước khi tạo reversal!) — **có thể tạo reversal thứ 2 cho cùng 1 bản gốc đã bị reversal trước đó**, dẫn tới `reversedByTxId` của bản gốc bị ghi đè bởi reversal mới nhất trong khi reversal cũ vẫn còn hiệu lực trong bảng balance (`computeAllPoolBalances` cộng TOÀN BỘ, không lọc) → tổng hiệu ứng bị áp dụng **2 lần hoàn tác** cho cùng 1 giao dịch, sai balance thật sự. **[BLOCKER tiềm ẩn — cần xác nhận UI không bao giờ cho phép gọi `reverseTransaction`/`deleteTransaction` trên 1 giao dịch đã `isReversed`]** — code hiện tại (`local_transaction_repository.dart`) không tự chặn ở tầng repository, chỉ dựa vào UI ẩn nút "Xoá" cho giao dịch cũ (chưa xác nhận `transaction_detail_screen.dart` có làm vậy không, vì chưa đọc toàn văn file này).

**Đề xuất:** thêm 1 guard ở đầu `reverseTransaction`/`updateTransaction`: nếu `original.reversedByTxId != null`, ném lỗi rõ ràng thay vì âm thầm tạo hiệu ứng chồng chéo. Đây là gap ở tầng repository, không phải ở tài liệu — nên coi là việc cần làm khi bắt đầu code tiếp (không sửa ngay trong audit này).

---

## G. Status — xác nhận không đụng balance

Đọc `status.dart`, `financial_engine.dart` (không có hàm nào nhận `Status`/`statusId` làm input để tính pool), và `updateTransaction` (nhánh đổi `statusId` luôn đi vào "update thẳng tại chỗ", không bao giờ gọi `buildCorrection`/`applyEffect`). **Khớp hoàn toàn Invariant 9.** Không phát hiện xung đột.

---

## H. Category — SYSTEM vs USER

- **SYSTEM category** (`type = TRANSFER`): `chuyen_tien_thanh_vien`, `nap_quy`, `tiet_kiem` — `isDefault = true`, theo docstring `category.dart` dòng 51-52 "Danh mục `type == transfer` luôn `isDefault == true` và không cho tự tạo/xoá qua UI". `category_edit_screen.dart` xác nhận segmented chọn loại chỉ có "Thu"/"Chi" (không có option Transfer) — khớp đúng, không tìm thấy đường nào trong UI để user tạo category `type=TRANSFER` mới.
- **USER category** (`type = INCOME | EXPENSE`): CRUD đầy đủ qua `category_edit_screen.dart`, đúng CLAUDE.md §9 ("CRUD danh mục là tính năng Phase 1, không đợi Premium").
- **UI hiển thị Thu | Chi | Chuyển đúng cách không phá model:** màn 06 (Danh mục — Danh sách) nhóm theo 3 khối "Thu"/"Chi"/"Chuyển· hệ thống, không tự tạo/xoá được" — đây chính là câu trả lời cho yêu cầu "đề xuất cách UI xử lý Transfer mà không làm hỏng domain model": nhóm Transfer hiển thị NHƯ MỘT NHÓM RIÊNG, đã có nhãn phụ giải thích rõ là hệ thống quản lý. Không cần đề xuất thêm — đã làm đúng.
- **Category đã bị xoá vẫn được giao dịch cũ tham chiếu đúng:** xác nhận qua `home_screen.dart` dòng 296-298 (`category?.name ?? 'Đã xoá danh mục'`) — có xử lý fallback khi category null.

Không phát hiện xung đột ở phần Category.

---

## I. Data Model — bảng entity tổng hợp (Phần 9)

| Entity | PK | FK | Bắt buộc | Tuỳ chọn | Enum | Sửa/Xoá | Ghi chú |
|---|---|---|---|---|---|---|---|
| `Family` | `familyId` | — | `name`, `accountType`, `syncMode`, `ownerUid` | — | `accountType`{personal,family}, `syncMode`{local,cloud} | Không xoá (chỉ tồn tại khi có Firestore) | Chưa có code (Giai đoạn B) |
| `Member` | `uid` | `familyId` | `displayName`, `roleLabel` | — | — | Soft delete (`isActive`) | Code hiện tại: enum cứng `FamilyMember{vo,chong}`, cố ý hoãn refactor |
| `Category` | `categoryId` | `familyId` | `name`, `color`, `type` | `linkedExpenseCategoryId` | `type`{INCOME,EXPENSE,TRANSFER} | Soft delete; `type=TRANSFER` không cho tạo/xoá qua UI | Khớp code 100% |
| `Status` | `statusId` | `categoryId` | `name`, `sortOrder` | — | — | Soft delete; CRUD tự do, không giới hạn số bước | Khớp code 100% |
| `Fund` | `fundId` | `familyId` | `name` | `color` | — | Soft delete, chỉ khi `balance=0` | Khớp code (`fund.dart`, chưa đọc guard UI xoá) |
| `SavingsAssetType` | `assetTypeId` | `familyId` | `name` | `color` | — | Soft delete, khi mọi thành viên = 0 ở loại đó | **Thiếu trong `financial-core-v2.md` §14 và mọi ERD** — chỉ có ở §9 và code |
| `Transaction` | `txId` | `familyId`, `categoryId`, `statusId?` | `type`, `sourceKind`, `destinationKind`, `amountMinor`, `transactionDate`, `clientTxId` | `transferKind`, `note`, `statusId`, `reversalOfTxId`, `correctsTxId`, `reversedByTxId` | `type`{INCOME,EXPENSE,TRANSFER}, `transferKind`{6 giá trị}, `sourceKind`/`destinationKind`{5 giá trị `PoolKind`} | **Append-only** — không update/xoá field ảnh hưởng balance | `clientTxId` cần unique constraint (xem GAP #6) |
| `MemberBalance`/pool cache | theo `(kind, refId)` | — | — | — | — | Derived, luôn rebuild được từ `Transaction` (Invariant 10) | Field cứng `savingsCash`/`savingsBank` trong tài liệu cũ nay phải là map theo `assetTypeId` |
| `Budget` | `yearMonth` | `familyId` | `categoryLimits` | — | — | — | Chưa code (Giai đoạn E), model đơn giản, ổn |

**Index cần có** — đã liệt kê đủ ở `financial-core-v2.md` §14, chỉ thiếu 1 dòng: **unique index/constraint trên `clientTxId` chưa được thực thi ở tầng local (Drift)** dù đã ghi nhận là cần cho Firestore. Nên thêm ngay ở local trước (dùng `UniqueKey()`/`@TableIndex` của Drift) vì double-submit có thể xảy ra ở cả local, không riêng cloud.

---

## J. Balance — bảng Metric/Source of Truth/Formula/Used by screen (Phần 10)

| Metric | Source of Truth | Formula | Dùng ở màn |
|---|---|---|---|
| `availableBalance` (1 thành viên) | `computeMemberFinancials` (đọc toàn bộ transaction, cộng dồn `applyEffect` cho pool `memberAvailable`) | Σ `applyEffect` mọi transaction (không lọc theo tháng) | 08 (Trang chủ), 12 (Tổng hợp) |
| `savingsTotal` (1 thành viên, mọi loại tài sản) | `computeMemberSavingsByAssetType` cộng dồn theo từng `assetTypeId` rồi tổng | Σ pool `memberSavingsAsset(*, member)` | 08, 16 |
| `Fund.balance` | `computeFundBalance` | Σ `applyEffect` pool `(fund, fundId)` | 14, 15, màn Thêm giao dịch (chọn nguồn) |
| `ThreeTotals` (Income/Expense/Transfer) | `computeThreeTotals` | Xem công thức FC-V2 §17, tôn trọng `excludeFromTotals`, lọc `isVisible` | 12 (Tổng hợp), sẽ dùng cho `MONTH_SUMMARY` khi lên Cloud |
| Tỷ lệ tiết kiệm | `ThreeTotals.savingsRatePercent` | (Income − Expense)/Income | 08, 12 |
| Thu nhập ròng | `computeNetIncome` | Σ INCOME (category liên kết) − Σ EXPENSE (category `linkedExpenseCategoryId`, mọi status) | 06, 07, 13 |
| Tổng "tiền ra" theo hạng mục của 1 thành viên | `compute_member_outflow_breakdown.dart` (chưa đọc toàn văn, chỉ xác nhận tồn tại) | EXPENSE + TRANSFER có thành viên đó là nguồn, nhóm theo `categoryId` | 12 (có thể) |

**Không phát hiện 2 công thức khác nhau cho cùng 1 metric giữa các màn** — tất cả đều gọi chung 1 use case trong `domain/usecases/`, đúng nguyên tắc kiến trúc CLAUDE.md §3 (domain không phụ thuộc UI). Đây là điểm mạnh của thiết kế hiện tại, đáng ghi nhận.

---

## K. UI/UX Flow — 17 màn hình (Phần 11), tổng hợp nhanh

Đã đọc toàn văn caption + tương tác của cả 17 màn. Không lặp lại toàn bộ 18 tiêu chí (Mục đích/Input/Output/...) cho từng màn ở đây vì phần lớn khớp đúng thiết kế và đã có caption tự giải thích khá đầy đủ trong chính `design.html`. Chỉ liệt kê các điểm lệch phát hiện được:

| Màn | Vấn đề |
|---|---|
| 08 · Trang chủ | Số liệu Tiết kiệm hiển thị cứng 2 dòng "TK hiện tại"/"Đã gửi NH" — lỗi thời so với model tổng quát hoá (xem mục B, C) và so với code thật (`home_screen.dart` chỉ hiện 1 số gộp) |
| 09 · Thêm giao dịch | Đúng model V2 ở phần Quỹ, nhưng panel "Chuyển → Tiết kiệm" (dòng 1157-1160) chỉ có 3 nút cố định "Nạp/Rút về ví/Gửi NH", **thiếu bước chọn loại tài sản** (asset type) mà model tổng quát hoá yêu cầu — mockup tĩnh chưa vẽ lại phần này dù caption màn 16 đã nói rõ tổng quát hoá. Code thật (`savings_screen.dart`) đã có `initialSavingsAssetTypeId` khi mở sheet, nên có thể đây chỉ là mockup HTML tĩnh chưa cập nhật theo kịp code, không phải code sai. |
| 11 · Chi tiết giao dịch | Không phát hiện lệch — caption mô tả đúng khớp code (`updateTransaction` reversal logic) |
| 12 · Tổng hợp | Không phát hiện lệch |
| 13 · Trạng thái — Chi tiết | Không phát hiện lệch — đúng nguyên tắc lặp qua `category.statuses`, không hardcode số bước |
| Nhóm giới thiệu trước 08/09 (dòng 1000) | Xem mục A — [BLOCKER] |
| 16 · Tiết kiệm — Quản lý | Tự có caveat đúng, chỉ số liệu demo lệch với 08 (mục C) |

**Không phát hiện UI chứa business logic riêng khác Financial Core** trong các file đã đọc — mọi màn đều gọi qua `domain/usecases`/`financial_engine.dart`, không tính toán số dư trực tiếp trong widget.

---

## L. Use Case — đếm lại toàn bộ (Phần 13)

**Total actual use cases: 38** (không phải 37 như header dòng 496 ghi).

Đếm: `U01`...`U32` (32 mã số liên tục) + 6 mã có hậu tố chữ cái chèn không theo thứ tự: `U16b` (sau U16), `U20c` rồi `U20b` (chèn sau U20, **thứ tự xuất hiện trong file bị đảo — U20c đứng trước U20b**), `U23a`, `U23b`, `U23c` (sau U23).

**Duplicate:** không phát hiện use case trùng nội dung.

**Incorrect numbering:** đánh số bằng hậu tố chữ cái không nhất quán thứ tự xuất hiện (U20c trước U20b) — dễ gây nhầm khi ai đó tham chiếu "U20b" mà không mở file ra xem thứ tự thật.

**Uncovered business flow đã tìm thấy khi đối chiếu với `financial-core-v2.md` §15** (tài liệu này tự đề xuất 5 thay đổi use case) — kiểm tra từng cái:
- ✅ "Chọn loại giao dịch (Thu/Chi/Chuyển)" — đã có U17.
- ✅ "Gắn trạng thái tiến độ, không ảnh hưởng số dư" — đã có U20 (tên khác nhưng đúng ý).
- ✅ "Sửa giao dịch qua Financial Engine" + "Huỷ giao dịch (reversal)" — đã gộp vào U18.
- ✅ "Nạp tiền vào quỹ (chuyển nội bộ, không phải chi)" — đã có U21 (tên đã đổi đúng ý).
- ✅ "Xem lịch sử tiết kiệm" — nằm trong U23a/b/c (ngầm định, không có use case riêng "xem lịch sử" nhưng chấp nhận được vì U23 nhóm Quỹ có "Xem số dư và lịch sử", nhóm Tiết kiệm thiếu use case tương đương tường minh — **có thể bổ sung `U23d: Xem lịch sử tiết kiệm` cho đủ, hiện đang ẩn trong U23a/b/c**).

**Đề xuất danh sách use case chuẩn:** đánh số lại tuần tự U01-U38 (bỏ hậu tố chữ cái), theo đúng thứ tự xuất hiện thật trong file (tức là đổi chỗ U20b/U20c hiện tại thành U20b→"Chuyển tiền cho thành viên khác" trước, U20c→"Tạo quỹ mới" sau, theo đúng thứ tự dòng 560/565 hiện có — hoặc đơn giản hơn: đánh số lại toàn bộ 01-38 liên tục theo đúng thứ tự đọc từ trên xuống), và sửa header "37 use case" → "38 use case".

---

## M. Edge Cases (Phần 14) — rà theo danh sách yêu cầu

| Edge case | Trạng thái |
|---|---|
| `amount = 0` | Chặn ở UI (`_buildTransaction` trả `null`); **không chặn ở tầng domain/DB ngoài `assert()`** — xem GAP #9 |
| `amount` âm | `Transaction` constructor có `assert(amountMinor > 0)` — cùng rủi ro bị strip ở release build như trên |
| `amount` rất lớn | Không có giới hạn trên nào được tài liệu hoá — có thể chấp nhận được (không phải rủi ro tài chính), nhưng chưa thấy validate tràn số (Dart `int` là 64-bit trên native nên thực tế an toàn) |
| Transaction duplicate / double submit | **[GAP đã nêu ở #6]** — `clientTxId` tồn tại trong schema nhưng chưa được enforce |
| Edit transaction | Đã audit kỹ ở mục F (Case A) — đúng |
| Edit nhiều lần | **[DECISION REQUIRED — Case C ở mục F]** — cần xác nhận UI luôn thao tác trên bản mới nhất |
| Delete transaction | Đã audit ở mục F (Case D) — **[BLOCKER tiềm ẩn]** nếu gọi `reverseTransaction` trên giao dịch đã bị reverse trước đó, không có guard |
| Reverse transaction | Cùng vấn đề Case D |
| Transfer source = destination | **Không tìm thấy validate nào chặn trường hợp này** (vd chọn "Chuyển tiền cho thành viên khác" nhưng người gửi = người nhận, hoặc `SAVINGS_CONVERT` với loại nguồn = loại đích) — `applyEffect` với `source == destination` (cùng kind, cùng refId) sẽ tự triệt tiêu về mặt số học (trừ rồi cộng lại đúng ) nên **không gây sai balance**, nhưng tạo ra 1 giao dịch "rỗng" vô nghĩa vẫn được lưu vào lịch sử — **[DECISION REQUIRED]**: có nên chặn ở UI không (UX, không phải tài chính) |
| Fund không đủ tiền | Đã có `InsufficientBalanceException`, test đầy đủ |
| Savings không đủ tiền | Cùng cơ chế `wouldGoNegative`, có test riêng (group "Savings Model") |
| Member không đủ tiền | Cùng cơ chế, `MEMBER_AVAILABLE` cũng qua `wouldGoNegative` |
| Giao dịch liên quan category đã bị xoá | Có fallback hiển thị "Đã xoá danh mục" (`home_screen.dart`) — ổn cho hiển thị, nhưng **chưa rõ** category bị soft-delete có còn chọn được trong dropdown "Hạng mục" ở màn Chi tiết giao dịch (11) khi sửa hay không — nếu dropdown chỉ load category `isActive=true` thì sửa 1 giao dịch cũ thuộc category đã xoá sẽ không hiện đúng lựa chọn hiện tại trong dropdown. **[DECISION REQUIRED — cần audit `transaction_detail_screen.dart` khi code tiếp]** |
| Member bị disable | Chưa áp dụng (Giai đoạn A chỉ có 2 member cố định, không có "disable") — đúng kế hoạch, chưa tới phase |
| Fund bị archive | Đã có (soft delete khi `balance=0`) |
| Savings asset bị archive | Đã có, đúng cơ chế Fund (`savings_screen.dart` `_delete`) |
| Date thay đổi (`transactionDate`) | Có, update trực tiếp (không ảnh hưởng balance) — đúng thiết kế |
| Timezone | Không thấy xử lý riêng — `DateTime.now()` dùng giờ máy cục bộ, chưa có chuẩn hoá UTC. Với app 1 gia đình dùng chung múi giờ VN, rủi ro thấp ở Giai đoạn A; **cần quyết định trước Giai đoạn B** (2 máy khác múi giờ nếu có thành viên ở nước ngoài) |
| Offline | Đúng kế hoạch — Giai đoạn A vốn hoàn toàn offline (SQLite), chưa cần xử lý gì thêm |
| App crash giữa transaction | `_db.transaction(() async {...})` được dùng trong `reverseTransaction`/`updateTransaction` (Drift transaction, atomic) — an toàn cho các thao tác nhiều bước. `addTransaction` chỉ có 1 write nên không cần transaction wrapper. Ổn. |
| App bị đóng khi đang save | Cùng lý do trên — Drift transaction đảm bảo atomic, không có write dở dang |
| Concurrent write | Chưa áp dụng được ở Giai đoạn A (1 thiết bị) — `version` field có sẵn cho Giai đoạn B, đúng kế hoạch |
| Sync conflict tương lai | Đã có `version` cho optimistic concurrency, đúng kế hoạch FC-V2 §22 |

---

## N. Local-first / Future Sync (Phần 15)

- **Transaction ID:** `IdGenerator.generate()` — chưa đọc thuật toán sinh id (chỉ thấy test file `id_generator_test.dart` tồn tại, chưa đọc nội dung) — khuyến nghị xác nhận id đủ ngẫu nhiên để không đụng độ khi 2 thiết bị sinh id cùng lúc trước khi migrate lên Firestore.
- **Idempotency:** `clientTxId` có field nhưng chưa enforce — xem GAP #6.
- **Timestamps:** `transactionDate` (ngày nghiệp vụ) tách biệt `createdAt` (thời điểm ghi) — đúng thiết kế F-07.
- **Sync state:** `syncMode` chưa gắn field lưu cục bộ nào (đúng như spec.md ghi nhận phase 14 dời sang phiên sau — không phải audit issue, là việc chưa tới phase).
- **Soft delete:** đã dùng nhất quán cho Category/Status/Fund/SavingsAssetType (`isActive`), và append-only cho Transaction (`reversedByTxId`) — đúng 2 cơ chế xoá tách biệt theo đúng FC-V2 §21.
- **Revision/version:** có sẵn field `version` trên `Transaction`, mặc định `1`, chưa dùng logic thật — đúng kế hoạch.

**Domain không phụ thuộc Firebase:** xác nhận qua `import` ở toàn bộ `lib/domain/*.dart` đã đọc — không file nào import `cloud_firestore`/`firebase_*`. Đúng nguyên tắc CLAUDE.md §3.

---

## O. Mermaid / Documentation (Phần 16)

- Sơ đồ use case (erDiagram + graph) trong `design.html` **có Mermaid runtime thật** (kiểm tra qua đã thấy `<pre class="mermaid">` render được ở lần xem trước đó trong project — không kiểm tra lại lần này, giả định vẫn đúng vì không có thay đổi liên quan tới thư viện). Nếu muốn chắc chắn 100%, nên mở `design.html` bằng trình duyệt và xác nhận cả ERD lẫn use case diagram render ra hình chứ không phải text thô.
- ERD dùng tên entity/transaction **có 1 chỗ cũ** (mục B ở trên — `MEMBER_BALANCE.savingsCash/savingsBank`).
- Không phát hiện thiếu flow nghiêm trọng nào khác ngoài đã liệt kê ở mục D (Fund→Fund, Savings A→Savings B).

---

## Việc cần làm tiếp theo (không làm trong audit này)

Theo đúng yêu cầu "chỉ audit, không code" — liệt kê thứ tự đề xuất khi bắt đầu phiên sửa tài liệu (không phải sửa code):

1. Sửa `docs/design.html` dòng 1000 (mục A) — ưu tiên cao nhất, dễ hiểu nhầm nhất.
2. Thống nhất model Tiết kiệm ở cả 4 nơi còn lại theo `financial-core-v2.md` §9 + code (mục B).
3. Sửa số đếm: "37 use case" → 38 (và đánh số lại U01-U38 liên tục), "18 màn hình" → 17, ở cả `spec.md` và `CLAUDE.md`.
4. Ghi quyết định rõ ràng cho 2 khoảng trống ở mục D (Fund→Fund, Savings A→Savings B) — dù chỉ là 1 câu "để sau, ngoài phạm vi Giai đoạn A" cũng đủ để không còn là BLOCKER.
5. Khi quay lại code (không phải bây giờ): thêm guard chặn `reverseTransaction` gọi 2 lần trên cùng 1 giao dịch (mục F Case D), thêm unique constraint cho `clientTxId` (GAP #6), xác nhận `transaction_detail_screen.dart` luôn sửa trên bản mới nhất (mục F Case C).
