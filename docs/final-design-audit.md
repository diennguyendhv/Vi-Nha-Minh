# FINAL DESIGN AUDIT & CHECKLIST — sau đợt sửa tài liệu 2026-09-16

Tài liệu này là kết quả của đợt sửa **chỉ tài liệu/thiết kế, không đụng code ứng dụng** thực hiện ngay sau `docs/audit-pre-implementation.md`. Mục tiêu: loại bỏ toàn bộ BLOCKER và IMPORTANT issue đã phát hiện, đưa `spec.md` / `CLAUDE.md` / `docs/financial-core-v2.md` / `docs/design.html` (ERD + sơ đồ use case + demo data) về **cùng một business logic**.

**Không có file Dart/Flutter/repository/service/provider/database migration nào bị tạo hoặc sửa trong đợt này.**

---

## 1. Danh sách file đã sửa

| File | Loại thay đổi |
|---|---|
| `docs/financial-core-v2.md` | Sửa nội bộ (mục 6, 14 khớp lại mục 9 — savings tổng quát hoá); thêm Invariant 13-15; thêm Test 19-21; sửa/rút Test 11; thêm rule category-soft-delete-vẫn-chọn-được; cập nhật bảng MVP scope + bảng quyết định mục 26 (10 quyết định); cập nhật trạng thái đầu file (không còn "CHƯA CODE") |
| `spec.md` | Sửa schema Firestore (`transferKind`, `sourceKind`/`destinationKind`, `memberBalances` → `savingsByAssetType`, thêm collection `savingsAssetTypes`); sửa "18 màn hình" → "17 màn hình"; sửa mô tả tiết kiệm/quỹ dùng wording tổng quát; sửa phase 46/47 |
| `CLAUDE.md` | Sửa §9 (bỏ `MEMBER_SAVINGS_CASH`/`MEMBER_SAVINGS_BANK`, thêm đoạn `SavingsAssetType` là mô hình duy nhất + 3 invariant mới + quyết định Fund→Fund/Savings A→B); cập nhật §11 (đếm invariant/test case, trạng thái `docs/design.html`, thêm mục trỏ tới `docs/audit-pre-implementation.md`) |
| `docs/design.html` | Thêm `<meta charset="utf-8">` (sửa lỗi hiển thị sai tiếng Việt khi mở ngoài Artifact); sửa dòng giới thiệu nhóm màn "Ghi chép hằng ngày" (bỏ mô tả trừ kép Quỹ); sửa ERD (`MEMBER_BALANCE`, thêm entity `SAVINGS_ASSET_TYPE`, sửa comment `TRANSACTION`); đánh số lại toàn bộ sơ đồ use case U01-U38 liên tục (bỏ hậu tố chữ cái); sửa số đếm "37 use case" → "38", "10 bảng" → "11 bảng"; sửa demo data màn 08 (Trang chủ) và màn 16 (Tiết kiệm) cho khớp nhau; thêm chọn loại tài sản vào panel Chuyển→Tiết kiệm ở màn 09; sửa mảng `statusMap` trong JS (bỏ `chong_dua_vo`/`vo_dua_chong` đã lỗi thời); sửa khối "Trạng thái hiện tại" và footer (không còn nói "chưa code"); đồng bộ lại 3 tab "Tài liệu" nhúng theo nội dung mới của `financial-core-v2.md`/`spec.md`/`CLAUDE.md` |
| `docs/final-design-audit.md` | **File mới** — chính tài liệu này |

`docs/audit-pre-implementation.md` (audit gốc) **giữ nguyên, không sửa** — đây là biên bản lịch sử ghi lại các vấn đề tại thời điểm phát hiện; tài liệu hiện tại là bản đối chiếu lại SAU khi sửa.

---

## 2. BLOCKER đã xử lý

| # | BLOCKER (từ audit gốc) | Đã xử lý bằng cách |
|---|---|---|
| B1 | `docs/design.html` dòng 1000 mô tả lại đúng lỗi trừ kép Quỹ (F-03) | Viết lại đoạn giới thiệu nhóm màn, mô tả đúng model V2 ("chọn Quỹ làm nguồn tiền... chỉ trừ đúng quỹ đó") |
| B2 | Mô hình Tiết kiệm tồn tại song song 2 phiên bản (tổng quát hoá vs cố định 2 loại) trên 4 vị trí khác nhau | Sửa cả 4: `financial-core-v2.md` §6/§14 (tự mâu thuẫn nội bộ), `CLAUDE.md` §9, `spec.md` (schema + wording), ERD trong `design.html` — tất cả giờ dùng `SavingsAssetType`/`MEMBER_SAVINGS_ASSET`/`SAVINGS_CONVERT` |
| B3 | Đếm sai: "37 use case" (thực tế 38, đánh số lộn xộn bằng hậu tố chữ cái) | Đánh số lại toàn bộ sơ đồ Mermaid U01-U38 tuần tự theo đúng thứ tự xuất hiện, sửa header thành "38 use case" |
| B4 | Đếm sai: "18 màn hình mô phỏng" ở `spec.md`/tham chiếu trong khi thực tế là 17 | Sửa `spec.md` dòng liên quan thành "17 màn hình mô phỏng" (`design.html` vốn đã đúng 17, không cần sửa) |
| B5 | [DESIGN DATA INCONSISTENCY] Số liệu demo Tiết kiệm giữa màn 08 và màn 16 không khớp nhau | Thống nhất 1 bộ số liệu: Vợ = Tiền mặt 1.200.000 + Ngân hàng 8.000.000 = 9.200.000đ (khớp cả 2 màn); Chồng = 6.000.000đ ở màn 08 (màn 16 minh hoạ theo Vợ, có segmented chọn thành viên khớp code thật) |
| B6 | 2 kịch bản Transfer chưa có quyết định (Fund→Fund, Savings người A→người B) | Chốt rõ trong `financial-core-v2.md` mục 26 quyết định #7: **không hỗ trợ trong MVP**, đi qua các bước có sẵn |
| B7 | Ambiguity trong reversal ledger: sửa nhiều lần liên tiếp thao tác trên bản nào; hoàn tác 2 lần trên cùng giao dịch có bị chặn không; Transfer source=destination có hợp lệ không | Thêm Invariant 13, 14, 15 + Test 19, 20, 21 vào `financial-core-v2.md`, chốt rõ trong bảng quyết định mục 26 (#8, #9, #10) |

**Không còn BLOCKER nào ở cấp độ tài liệu/thiết kế sau đợt sửa này.**

---

## 3. IMPORTANT issue đã xử lý

| # | Vấn đề | Đã xử lý bằng cách |
|---|---|---|
| I1 | `financial-core-v2.md` §14 (bảng schema tổng hợp) thiếu entity `SAVINGS_ASSET_TYPE` dù §9 đã định nghĩa | Thêm dòng `SAVINGS_ASSET_TYPE` vào bảng, sửa dòng `MEMBER_BALANCE` (map `savingsByAssetType` thay 2 field cứng) |
| I2 | Test 11 (`sửa giao dịch đổi type`) mâu thuẫn với quyết định mục 21 (cấm đổi `type` qua UI) và không khớp chữ ký hàm `buildCorrection()` trong code | Rút Test 11 khỏi danh sách bắt buộc, ghi rõ lý do (đã cấm ở tầng UI, không cần Financial Engine hỗ trợ) |
| I3 | Category đã soft-delete không rõ có hiện được trong dropdown khi sửa giao dịch cũ hay không | Thêm rule tường minh vào `financial-core-v2.md` mục 11: hiện, đánh dấu "(đã ẩn)", chỉ ẩn khi TẠO MỚI |
| I4 | Chưa có ràng buộc rõ cho double-submit (`clientTxId`) ở tầng local, dễ hiểu nhầm là chỉ cần cho cloud | Ghi rõ trong `financial-core-v2.md` mục 14: bắt buộc enforce ngay ở tầng local (Drift), không đợi Firestore |
| I5 | `docs/design.html` không tự khai báo charset, phụ thuộc hoàn toàn vào server/host để hiển thị đúng tiếng Việt | Thêm `<meta charset="utf-8">` làm dòng đầu tiên của file |
| I6 | JS mockup (`statusMap`) trong `design.html` vẫn tham chiếu 2 category đã bị loại bỏ (`chong_dua_vo`/`vo_dua_chong`) | Thay bằng `chuyen_tien_thanh_vien`/`nap_quy` (đúng id category hiện hành) |
| I7 | Khối "Trạng thái hiện tại" + footer trong `design.html` vẫn nói "chưa code"/"bản nháp thiết kế, chưa code" dù Giai đoạn A đã code xong phase 1-17 | Cập nhật cả 2 chỗ, trỏ sang tài liệu audit |
| I8 | Panel "Chuyển → Tiết kiệm" ở màn 09 (mockup) thiếu bước chọn loại tài sản, không khớp model tổng quát hoá | Thêm dropdown "Loại tài sản" vào panel |
| I9 | Card giới thiệu "02 — dữ liệu" nói "10 bảng" nhưng ERD thực tế có 11 entity (sau khi thêm SAVINGS_ASSET_TYPE) | Sửa thành "11 bảng" |

---

## 4. Quyết định business đã chốt (bổ sung, ngoài 6 quyết định gốc)

1. **Fund → Fund** (chuyển thẳng giữa 2 quỹ): **không hỗ trợ trong MVP.** Cần thì đi qua rút quỹ A về ví → nạp vào quỹ B.
2. **Savings người A → Savings người B** (chuyển tiết kiệm trực tiếp giữa 2 thành viên): **không hỗ trợ trong MVP.** Đi qua rút về ví → chuyển thành viên → nạp lại (3 bước).
3. **Giao dịch Transfer với source = destination** (cùng kind, cùng refId): **bị cấm** — Invariant 15 mới, chặn cả UI lẫn tầng ghi dữ liệu.
4. **Sửa giao dịch nhiều lần liên tiếp**: luôn thao tác trên bản mới nhất còn hiệu lực (`reversedByTxId == null`), không bao giờ trên bản gốc ban đầu — Invariant 14 mới.
5. **Hoàn tác 2 lần trên cùng 1 giao dịch**: bị từ chối — Invariant 13 mới.
6. **Category đã soft-delete**: vẫn chọn được khi sửa giao dịch cũ đang tham chiếu nó (đánh dấu "đã ẩn"), chỉ ẩn khỏi danh sách khi tạo giao dịch mới.
7. **Test 11 (đổi `type` khi sửa giao dịch)**: chính thức loại khỏi phạm vi MVP — không mâu thuẫn với quyết định "type là append-only" nữa.
8. **`clientTxId` unique constraint**: bắt buộc ở tầng local (SQLite/Drift) ngay từ Giai đoạn A, không đợi Firestore.

---

## 5. FINAL DESIGN AUDIT (chạy lại sau khi sửa)

Đối chiếu lại đúng các hạng mục đã gắn cờ trong `docs/audit-pre-implementation.md`:

- **Savings model**: `financial-core-v2.md` (toàn bộ mục 4-9), `spec.md`, `CLAUDE.md`, ERD `design.html` — **khớp nhau 100%**, đều dùng `SavingsAssetType`/`MEMBER_SAVINGS_ASSET`/`SAVINGS_CONVERT`. Không còn `MEMBER_SAVINGS_CASH`/`MEMBER_SAVINGS_BANK`/`SAVINGS_TO_BANK` ở bất kỳ định nghĩa model nào (các chỗ còn giữ 3 tên này là bảng audit lịch sử F-02, có framing rõ "so với bản đầu" — không phải định nghĩa hiện hành).
- **Fund double-subtraction**: không còn câu/đoạn nào trong `design.html` mô tả sai; code (đã audit ở vòng trước) vốn đã đúng.
- **Use case**: đếm lại = 38, đúng bằng số node trong Mermaid, đánh số liên tục U01-U38, không trùng, không thiếu.
- **Số màn hình**: 17 ở cả `design.html` (thực tế + text) và `spec.md` (đã sửa).
- **Reversal ledger**: 3 case còn mơ hồ (sửa nhiều lần, hoàn tác 2 lần, source=destination) nay đều có Invariant + Test case tường minh.
- **Category System vs User**: đã đúng từ trước (không có gì phải sửa) — UI (màn 06) vẫn nhóm Chuyển riêng, có nhãn "hệ thống, không tự tạo/xoá được"; JS mockup đã hết tham chiếu category cũ.
- **Demo data**: điểm sai duy nhất được xác nhận (Home vs Savings) đã thống nhất; không phát hiện thêm điểm sai số liệu nào khác khi rà lại các màn 08, 09, 10, 12, 13, 14, 15, 16 (không sửa business logic, chỉ đổi số liệu mockup theo đúng yêu cầu).
- **Mermaid/encoding**: thêm `meta charset` — loại bỏ rủi ro hiển thị sai khi mở file ngoài môi trường có header HTTP đúng.

**Không phát hiện BLOCKER hay IMPORTANT issue mới phát sinh từ chính các thay đổi vừa thực hiện** (đối chiếu chéo lại toàn bộ số liệu/ID sau khi sửa bằng grep + đếm node Mermaid).

---

## 6. FINAL DESIGN CHECKLIST

- [x] Financial Core V2 là source of truth duy nhất, không còn mô hình song song (Income/Expense/Transfer, Fund, Savings)
- [x] Fund: Expense từ ví → chỉ trừ ví; Expense từ Fund → chỉ trừ Fund; không còn câu/diagram nào mô tả trừ kép
- [x] Savings: chỉ dùng `SavingsAssetType` + `SAVINGS_TOPUP`/`SAVINGS_WITHDRAW`/`SAVINGS_CONVERT`; không còn `MEMBER_SAVINGS_CASH`/`MEMBER_SAVINGS_BANK`/`SAVINGS_TO_BANK` trong bất kỳ định nghĩa model nào
- [x] Reversal: Original → Reversal → Correction được chuẩn hoá đầy đủ, có invariant chặn hoàn tác 2 lần và chặn sửa nhầm bản cũ
- [x] Category: System category (Transfer, cố định) và User category (Income/Expense, CRUD tự do) phân biệt rõ, UI phản ánh đúng domain model
- [x] Use case: đếm lại đúng, không trùng, không thiếu, đánh số liên tục, diagram khớp danh sách
- [x] Demo data: 1 bộ dữ liệu thống nhất giữa các màn liên quan đến Tiết kiệm; không có business logic nào bị sửa chỉ để khớp mockup
- [x] `spec.md`, `CLAUDE.md`, `docs/financial-core-v2.md`, `docs/design.html` (ERD + ba tab "Tài liệu" nhúng) mô tả cùng 1 business logic
- [ ] *(Ngoài phạm vi đợt sửa này — việc của lập trình, không phải tài liệu)* Guard chặn hoàn tác 2 lần (Invariant 13), unique constraint `clientTxId` (F-12), validate source≠destination (Invariant 15) **chưa được implement trong code** — đã ghi rõ thành yêu cầu bắt buộc trong `financial-core-v2.md`, cần làm khi động tới `LocalTransactionRepository`/`AppDatabase` ở phiên code tiếp theo.

---

## Kết luận

**READY FOR IMPLEMENTATION**

Toàn bộ BLOCKER và IMPORTANT issue phát hiện ở `docs/audit-pre-implementation.md` đã được xử lý ở cấp độ tài liệu/thiết kế. `spec.md`, `CLAUDE.md`, `docs/financial-core-v2.md`, và `docs/design.html` (ERD, sơ đồ use case, demo data, 3 tab "Tài liệu" nhúng) hiện mô tả **cùng một business logic**, không còn định nghĩa song song hay số liệu mâu thuẫn.

Mục cuối trong FINAL DESIGN CHECKLIST (guard chặn hoàn tác 2 lần, unique constraint `clientTxId`, validate source≠destination) là **việc lập trình cho phiên code tiếp theo**, không phải mâu thuẫn thiết kế — 3 yêu cầu này giờ đã được đặc tả rõ ràng (Invariant 13/14/15) nên không còn là điều "chưa quyết định", chỉ còn là "chưa viết code", đúng như phạm vi đợt này chỉ giới hạn ở tài liệu.
