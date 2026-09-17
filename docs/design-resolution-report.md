# Design Resolution Report — Phase 2 (Resolve All Design/Architecture Conflicts)

Báo cáo này là kết quả PHASE 2, tiếp nối `docs/audit-pre-implementation.md` (Phase 1 — audit) và `docs/final-design-audit.md` (Phase 1 — fix + re-audit). **Không có file Dart/Flutter/repository/service/provider/migration nào được tạo hoặc sửa trong phase này** — toàn bộ thay đổi nằm ở `docs/financial-core-v2.md`, `spec.md`, `CLAUDE.md`, `docs/design.html`.

---

## 1. Issues found (bổ sung so với Phase 1)

Ngoài các BLOCKER/IMPORTANT đã liệt kê ở `docs/final-design-audit.md`, đợt rà soát sâu hơn (Phase 2) phát hiện thêm:

| # | Issue | Vị trí |
|---|---|---|
| P2-1 | Reversal ledger có Invariant nhưng **chưa có state machine chính thức** (ACTIVE/REVERSED, bảng transition hợp lệ/không hợp lệ) | `financial-core-v2.md` §21 |
| P2-2 | `SAVINGS_CONVERT` với source asset = destination asset được Invariant 15 chặn ở mức tổng quát, nhưng chưa có ví dụ nêu đích danh trường hợp này | `financial-core-v2.md` §18 |
| P2-3 | Fund→Fund / Savings(A)→Savings(B) được nói "chưa hỗ trợ" nhưng chưa gắn nhãn phân loại chính thức (SUPPORTED/NOT SUPPORTED/DEFERRED) | `financial-core-v2.md` §26 |
| P2-4 | Chưa có bảng edge-case quyết định tường minh theo format INPUT/EXPECTED/ACCEPT-REJECT/REASON cho toàn bộ danh sách edge case yêu cầu | `financial-core-v2.md` (mới — §27) |
| P2-5 | `financial-core-v2.md` §15 dùng wording "chuyển ngân hàng" (ám chỉ cố định) cho use case Tiết kiệm dù đã tổng quát hoá | `financial-core-v2.md` §15 |
| P2-6 | **[DESIGN DATA INCONSISTENCY]** Home (màn 08) tự nhận 3 giao dịch xảy ra "Hôm nay · 15/09" nhưng Transaction List (canonical, màn 10) không có giao dịch nào ngày 15/09; số tiền "Đi chợ" ở Home (180.000) khác số tiền "Đi chợ" ở Transaction List (275.000) cho cùng người/cùng category | `design.html` màn 08 |
| P2-7 | **[DESIGN DATA INCONSISTENCY]** Transaction Detail (màn 11) có cùng ngày/số tiền/người (10/09 · Vợ · 500.000) với dòng "Ủng hộ quỹ lớp" (CĐ) trong Transaction List, nhưng hiển thị category "DH" và note "Tháng 9" — trông như 2 giao dịch khác nhau dù caption nói đây là "bấm vào bất kỳ dòng nào cũng mở đúng màn này" | `design.html` màn 11 |
| P2-8 | Caption màn 09 vẫn nhắc nút "Rút về ví chính"/"Gửi ngân hàng" (màn 16) sau khi màn 16 đã đổi sang nút Nạp/Rút theo từng loại tài sản (do sửa BLOCKER B2/I8 ở Phase 1) | `design.html` màn 09 |

---

## 2. Issues fixed

| # | Fix |
|---|---|
| P2-1 | Thêm §21.1 "State machine chính thức" vào `financial-core-v2.md`: 2 state (ACTIVE/REVERSED, không có state VOIDED tách biệt — quyết định có chủ đích), bảng 6 dòng liệt kê transition hợp lệ/không hợp lệ, giải thích rõ REVERSED→REVERSED và REVERSED→CORRECTED đều INVALID |
| P2-2 | Bổ sung câu ví dụ cụ thể vào Invariant 15: "Tiền mặt → Tiền mặt" bị REJECT ngay lúc submit |
| P2-3 | Thêm §26.1 "Open Business Decisions — phân loại chính thức": bảng 6 dòng, mỗi dòng có nhãn SUPPORTED/NOT SUPPORTED + lý do business, nêu rõ Savings(A)→Savings(B) **khác** `MEMBER_TO_MEMBER` vì là 2 pool `MEMBER_SAVINGS_ASSET` khác `refId`, không phải cùng loại chuyển như ví |
| P2-4 | Thêm §27 "Bảng quyết định Edge Case" — 19 dòng, đúng format INPUT/EXPECTED/ACCEPT-REJECT/REASON, phủ toàn bộ danh sách edge case yêu cầu (amount=0/âm/lớn, duplicate, sửa lặp lại, hoàn tác lặp lại, xoá, clientTxId trùng, category xoá, member disabled, fund/savings archived, đổi ngày, offline retry, source=destination) |
| P2-5 | Sửa §15: liệt kê đúng 3 use case Tiết kiệm tổng quát hoá thay vì "chuyển ngân hàng"; thêm dòng "TOTAL USE CASES = 38" |
| P2-6 | Đổi label "Hôm nay · 15/09" → "Gần đây"; thay 3 dòng giao dịch bằng đúng 3 giao dịch gần nhất có thật trong Transaction List (14/09 Đi chợ -275.000, 14/09 Ăn sáng -45.000, 13/09 Lương +16.000.000), có ghi ngày trong subtitle |
| P2-7 | Đổi category dropdown màn 11 từ "DH" (selected) sang "CĐ" (selected), đổi ghi chú từ "Tháng 9" sang "Ủng hộ quỹ lớp" — giờ khớp 100% với dòng 10/09 trong Transaction List |
| P2-8 | Sửa caption màn 09: "nút Nạp/Rút trên từng loại tài sản (màn 16)" thay vì tên 2 nút cũ đã không còn tồn tại |

---

## 3. Business decisions made (bổ sung so với Phase 1)

1. Reversal ledger chỉ có 2 state (ACTIVE, REVERSED) — không có state "VOIDED" riêng; xoá và hoàn tác là cùng 1 operation.
2. `SAVINGS_CONVERT` cùng loại tài sản nguồn/đích → REJECT tường minh (không chỉ ngầm hiểu qua Invariant tổng quát).
3. Fund→Fund: `NOT SUPPORTED` (không phải `DEFERRED`) — không có nhu cầu business, có đường vòng.
4. Savings(A)→Savings(B): `NOT SUPPORTED` — khác biệt rõ với `MEMBER_TO_MEMBER` vì khác pool; có đường vòng 3 bước.
5. Demo data: "canonical" = nội dung hiển thị TRÙNG NHAU giữa các màn phải khớp chính xác (vd cùng 1 giao dịch mở từ 2 màn khác nhau phải ra cùng thông tin); các con số **tổng hợp/rollup** (Tổng chi tháng, tỷ lệ tiết kiệm %) được coi là số liệu minh hoạ độc lập, không bắt buộc suy ra được từ vài dòng ví dụ hiển thị trong danh sách giao dịch (một danh sách 3 dòng không có nghĩa là toàn bộ giao dịch trong tháng) — quyết định phạm vi này để tránh phải dựng cả 1 sổ cái giả hàng chục dòng chỉ để khớp số % hiển thị, không tương xứng với việc đây vẫn là bản mô phỏng tĩnh, chưa code.

---

## 4. Open decisions

Không còn open decision nào ở cấp độ business sau Phase 2 — cả 2 câu hỏi "chưa quyết" từ Phase 1 (Fund→Fund, Savings A→B) đã được phân loại chính thức ở mục 3.

---

## 5. Documentation files changed

- `docs/financial-core-v2.md` (thêm §21.1, §26.1, §27; sửa §15, §18)
- `docs/design.html` (sửa demo data màn 08, 11; sửa caption màn 09)
- (đồng bộ lại 3 tab "Tài liệu" nhúng trong `design.html` sau mỗi lần sửa `financial-core-v2.md`)

---

## 6. Old terminology removed / classified

Quét lại toàn bộ `spec.md`, `CLAUDE.md`, `docs/financial-core-v2.md`, và phần "native" của `docs/design.html` (loại trừ 3 khối nhúng, vốn chỉ là bản sao y nguyên của 3 file kia) cho `MEMBER_SAVINGS_CASH`, `MEMBER_SAVINGS_BANK`, `SAVINGS_TO_BANK`, và các cụm mô tả trừ kép ("trừ kép", "double subtraction", "tích quỹ"):

**Kết quả: 100% các lần xuất hiện còn lại đều là VALID HISTORICAL REFERENCE** — mỗi chỗ đều nằm trong 1 trong 3 khung cảnh:
1. Bảng audit lịch sử F-01/F-02/F-03 (mô tả đúng bug V1 đã biết, có link "xem mục 9/mục 8" trỏ sang định nghĩa đúng);
2. Câu so sánh "...của bản đầu"/"so với bản đầu" (đối chiếu rõ ràng với model cũ, không phải định nghĩa hiện hành);
3. Câu cấm đoán tường minh (`CLAUDE.md` dòng 80, `financial-core-v2.md` dòng 7: "Không dùng lại X — nếu thấy lại là dấu hiệu sai").

**Không tìm thấy OUTDATED DOCUMENTATION nào** (tức không còn chỗ nào coi 3 tên cũ là model đang áp dụng) sau đợt sửa Phase 1+2.

---

## 7. Financial invariants (tổng hợp, 15 invariant — `financial-core-v2.md` §18)

1. Mỗi transaction chạm tối đa 2 pool.
2. `TRANSFER` không đổi Total Assets.
3. `EXPENSE` giảm Total Assets đúng `amountMinor`.
4. `INCOME` tăng Total Assets đúng `amountMinor`.
5. Chi từ Quỹ không đụng `MEMBER_AVAILABLE` người mua.
6. Nạp Quỹ/Tiết kiệm: đúng 1 pool nguồn giảm, đúng 1 pool đích tăng, cùng giá trị.
7. Quỹ/Tiết kiệm/`MEMBER_AVAILABLE` không bao giờ âm.
8. Sửa/xoá bắt buộc qua Financial Engine, không ghi thẳng field.
9. Status không bao giờ kích hoạt `applyEffect`.
10. Balance/rollup rebuild được 100% từ `TRANSACTION` gốc.
11. Category/Status/Fund/Member "xoá" chỉ soft-delete.
12. `amountMinor` luôn dương.
13. **[MỚI]** Không hoàn tác 2 lần trên cùng 1 giao dịch.
14. **[MỚI]** Sửa nhiều lần luôn thao tác trên bản mới nhất.
15. **[MỚI]** `TRANSFER` cấm source = destination.

---

## 8. Implementation blockers (việc của code, KHÔNG phải tài liệu — đã gắn nhãn `[IMPLEMENTATION BLOCKER / TODO]` trong `financial-core-v2.md`)

1. Guard chặn hoàn tác 2 lần (Invariant 13) — chưa có trong `LocalTransactionRepository`.
2. Xác nhận `transaction_detail_screen.dart` luôn thao tác trên bản mới nhất (Invariant 14) — chưa audit code UI.
3. Unique constraint `clientTxId` trong `AppDatabase` (Drift) + kiểm tra trùng trước khi insert (mục 14) — chưa có.
4. Validate source ≠ destination cho mọi `TRANSFER` (Invariant 15) — chưa có ở repository/UI.
5. `amountMinor > 0` chỉ đang dựa vào `assert()` (bị strip ở release build) — cần validate tường minh ở tầng repository, không chỉ constructor.

Cả 5 mục đều đã có đặc tả rõ ràng (không còn là "chưa quyết định") — chỉ còn thiếu code, đúng phạm vi việc cho phiên implementation tiếp theo.

---

## 9. Remaining risks

- **Risk kỹ thuật (không phải thiết kế):** nếu phiên code tiếp theo bỏ sót 1 trong 5 implementation blocker ở mục 8, các Invariant 13/14/15 sẽ chỉ tồn tại trên giấy — cần đưa vào checklist review PR đầu tiên đụng tới `LocalTransactionRepository`.
- **Risk demo data:** các con số tổng hợp (%, tổng chi tháng) trong mockup vẫn là số độc lập, không suy ra được từ danh sách giao dịch hiển thị — nếu sau này có người dùng bản mockup này để "đối chiếu ngược" ra bộ dữ liệu test, họ sẽ không tìm thấy đủ giao dịch để giải thích các con số tổng — đã ghi rõ ở mục 3 để không ai hiểu nhầm đây là 1 sổ cái đầy đủ.
- **Risk tài liệu:** `docs/audit-pre-implementation.md` (Phase 1, bản audit gốc) vẫn còn nguyên các câu trích dẫn mô tả tình trạng LỖI ban đầu (đúng mục đích — biên bản lịch sử) — ai đọc file đó riêng lẻ mà không đọc `docs/final-design-audit.md`/report này tiếp theo có thể tưởng nhầm các lỗi đó vẫn còn tồn tại. Đã note rõ trong `CLAUDE.md` §11 rằng đây là tài liệu lịch sử.

---

## Kết luận Phase 2

Không còn BLOCKER hay CONFLICT nào ở cấp độ tài liệu. Tất cả OPEN DECISION quan trọng (Fund→Fund, Savings A→B) đã được chốt với nhãn phân loại rõ ràng.

**READY FOR FINAL DESIGN FREEZE**
