# Scenario Walkthroughs — 12 kịch bản kiểm tra trước khi code

Tài liệu này mô phỏng tay từng kịch bản bạn liệt kê, đối chiếu với `docs/financial-core-v2.md` (Invariant, state machine §21.1, bảng edge case §27) và `docs/design-freeze.md`. Mục đích: cho bạn 1 bộ ledger trace cụ thể (số liệu thật, không trừu tượng) để tự tay đối chiếu/test trước khi bắt đầu code. **Vẫn chưa code** — đây là phân tích thiết kế.

Dùng chung bộ dữ liệu canonical đã chốt ở `docs/design-resolution-report.md`: Vợ/Chồng, Quỹ tiền ăn (số dư 1.850.000đ sau khi sửa demo data — xem mục "Sửa demo data phát sinh" ở cuối), Vợ có tiết kiệm Tiền mặt 1.200.000đ / Ngân hàng 8.000.000đ.

Ký hiệu: **ACTIVE**/**REVERSED** = state theo §21.1. `txN` = transaction thứ N tạo ra trong kịch bản (không phải id thật).

---

## 1. Bấm Lưu 2 lần (double save)

**Input:** Vợ mở màn Thêm giao dịch, nhập Expense "Đi chợ" 200.000đ (Sinh hoạt, nguồn ví). Form sinh đúng 1 `clientTxId = ctx-01` khi mở. Do lag UI, Vợ bấm nút Lưu 2 lần trước khi request đầu kịp phản hồi → 2 lệnh `addTransaction` gửi đi, **cùng** `clientTxId = ctx-01`, cùng nội dung.

**Expected:**
- Request 1: không tìm thấy transaction nào có `clientTxId=ctx-01` trong family → tạo `tx1` (ACTIVE, -200.000 Vợ).
- Request 2: tìm thấy `tx1` đã có `clientTxId=ctx-01` → **không tạo bản ghi mới**, coi như thành công, trả về `tx1`.
- Ledger cuối: đúng 1 transaction. Vợ giảm đúng **200.000đ** (không phải 400.000đ).

**Trạng thái nếu chạy NGAY BÂY GIỜ (trước khi code guard):** `LocalTransactionRepository.addTransaction` (hiện tại) không kiểm tra `clientTxId` trùng — request 2 SẼ tạo `tx2` riêng (id khác, cùng `clientTxId` nhưng không ai kiểm tra) → **Vợ bị trừ 400.000đ, sai thật.** Đây là bug tái hiện được nếu bạn test tay bằng cách bấm nhanh 2 lần trên UI hiện có.

**Việc cần làm:** `[IMPLEMENTATION BLOCKER]` — thêm unique index `clientTxId` (per family) ở `AppDatabase`, và `addTransaction` phải `SELECT ... WHERE clientTxId = ?` trước khi insert (hoặc bắt lỗi unique-constraint-violation và trả về bản ghi cũ).

---

## 2. Retry request (mất mạng, client tự gửi lại)

**Input:** Chồng ghi Income "Lương tháng 9" 16.000.000đ, `clientTxId = ctx-02`. Ở Giai đoạn B (Firestore), mạng rớt ngay sau khi request rời máy — client không biết server đã nhận hay chưa — app tự động gửi lại **đúng request đó** (cùng `clientTxId`) khi có mạng lại.

**Expected — 2 nhánh:**
- Nhánh A (server ĐÃ nhận lần đầu, chỉ response bị mất): lần retry phát hiện `clientTxId=ctx-02` đã tồn tại → không tạo thêm, coi như thành công.
- Nhánh B (server CHƯA nhận được gì lần đầu): lần retry là request đầu tiên thực sự tới server → tạo bình thường.
- Cả 2 nhánh: ledger cuối luôn đúng **1 transaction**, Chồng tăng đúng 16.000.000đ dù mạng chập chờn bao nhiêu lần retry.

**Khác biệt với kịch bản 1:** kịch bản 1 là 2 hành động CỦA NGƯỜI DÙNG (2 lần bấm); kịch bản 2 là 1 hành động của người dùng nhưng NHIỀU request ở tầng mạng — cùng 1 cơ chế phòng vệ (`clientTxId` idempotency) giải quyết cả 2, không cần thêm bất kỳ business rule nào riêng.

**Việc cần làm:** Cùng `[IMPLEMENTATION BLOCKER]` ở kịch bản 1, cộng thêm ở Giai đoạn B: Cloud Function phải tự enforce lại (không chỉ dựa vào Security Rules) — đúng nguyên tắc đã ghi ở `financial-core-v2.md` phần "Bảo mật cần siết chặt hơn khi lên quy mô lớn" (`spec.md`).

---

## 3. Reverse 2 lần

**Input:** Vợ ghi Expense "Ủng hộ quỹ lớp" 500.000đ (`tx1`, ACTIVE, Vợ -500.000). Vợ bấm "Xoá giao dịch" → `reverseTransaction(tx1)` tạo `tx2` (reversal, Vợ +500.000, `reversalOfTxId=tx1`); `tx1` → REVERSED. Vợ về lại đúng số dư trước khi ghi.

Sau đó (do double-tap nút Xoá, hoặc app hiển thị lại `tx1` từ cache/thông báo cũ), hệ thống gọi `reverseTransaction(tx1)` **LẦN THỨ 2**.

**Expected:** Bị từ chối ngay lập tức (Invariant 13, vì `tx1.reversedByTxId = tx2.id != null`). Không tạo `tx3`. Balance Vợ không đổi thêm.

**Nếu KHÔNG có guard (hiện trạng thật của code hôm nay):** `reverseTransaction` chạy bình thường lần 2, tạo `tx3` (Vợ +500.000 NỮA), và ghi đè `tx1.reversedByTxId = tx3.id` (mất dấu vết `tx2`). Vì `computeAllPoolBalances` cộng dồn **toàn bộ** transaction không lọc, cả `tx2` VÀ `tx3` đều được cộng vào balance → **Vợ bị cộng thừa 500.000đ vào số dư thật, sai tài chính, không chỉ sai UX.** Đây là mức độ nghiêm trọng nhất trong 12 kịch bản.

**Việc cần làm:** `[IMPLEMENTATION BLOCKER]` mức **CRITICAL** — bắt buộc có guard này trước khi coi màn Chi tiết giao dịch là hoàn chỉnh.

---

## 4. Edit transaction 5 lần

**Input:** Chồng ghi Expense "Tiền điện" 300.000đ (`t0`, ACTIVE, Chồng -300.000).

| Lần sửa | Thao tác trên | Thay đổi | Bản ghi mới | State sau |
|---|---|---|---|---|
| 1 | `t0` | 300.000 → 320.000 | `r1` (reversal `t0`), `c1` (=320.000, `correctsTxId=t0`) | `t0`→REVERSED, `c1` ACTIVE. Chồng: -320.000 |
| 2 | `c1` (bản mới nhất) | 320.000 → 350.000 | `r2`, `c2` (=350.000, `correctsTxId=c1`) | `c1`→REVERSED, `c2` ACTIVE. Chồng: -350.000 |
| 3 | `c2` | 350.000 → 280.000 | `r3`, `c3` (=280.000, `correctsTxId=c2`) | `c2`→REVERSED, `c3` ACTIVE. Chồng: -280.000 |
| 4 | `c3` | đổi "người tiêu": Chồng → Vợ (amount giữ 280.000) | `r4` (hoàn 280.000 cho Chồng), `c4` (source=Vợ, 280.000, `correctsTxId=c3`) | `c3`→REVERSED, `c4` ACTIVE. Chồng: 0 (về mốc trước `t0`), Vợ: -280.000 |
| 5 | `c4` | 280.000 → 300.000 | `r5`, `c5` (source=Vợ, 300.000, `correctsTxId=c4`) | `c4`→REVERSED, `c5` ACTIVE. Vợ: -300.000 |

**Ledger cuối:** 11 bản ghi (`t0, r1,c1, r2,c2, r3,c3, r4,c4, r5,c5`) — chỉ `c5` hiển thị mặc định (`reversedByTxId == null`). Balance cuối: **Vợ -300.000đ, Chồng 0đ** — khớp chính xác với "nếu từ đầu chỉ ghi 1 giao dịch Vợ -300.000đ" (Invariant 10, rebuild đúng dù sửa bao nhiêu lần).

**Điều kiện bắt buộc đúng ở MỌI bước:** thao tác luôn nhắm vào bản ACTIVE gần nhất, không bao giờ quay lại `t0`/`c1`/`c2`/`c3` (kể cả khi mở lại app từ 1 thông báo/deep-link cũ trỏ tới `t0`). Đây là Invariant 14 — `[IMPLEMENTATION BLOCKER]`, cần xác nhận `transaction_detail_screen.dart` tự resolve về bản mới nhất trước khi cho sửa, không tin thẳng `txId` được truyền vào route.

---

## 5. Delete sau khi reverse

**Input:** Nối tiếp kịch bản 4 — `t0` đã REVERSED từ lần sửa 1 (`r1` đã tạo). Do bug UI hoặc user quay lại từ lịch sử cũ, bấm "Xoá giao dịch" trên **`t0`** (không phải `c1`/bản mới nhất).

**Expected:** `deleteTransaction(t0)` = gọi thẳng `reverseTransaction(t0)` (theo định nghĩa mục 21) → bị Invariant 13 từ chối vì `t0.reversedByTxId != null`. **Đây không phải 1 rule riêng — nó là hệ quả tự động của Invariant 13 áp dụng lên path `deleteTransaction`**, vì "xoá" và "hoàn tác" dùng chung đúng 1 hàm (§21.1: không có state VOIDED tách biệt). Không cần code thêm logic riêng cho "xoá sau khi đã reverse" — cùng 1 guard ở kịch bản 3 tự động phủ luôn kịch bản này.

**Nếu bấm "Xoá" đúng trên `c1`** (bản đang ACTIVE, đúng luồng bình thường): hợp lệ, tạo `r2`, `c1`→REVERSED. Không có gì đặc biệt.

---

## 6. Chi quỹ (Expense, source = FUND)

**Input:** Quỹ tiền ăn đang có 1.850.000đ (canonical, xem mục cuối). Vợ ghi Expense "Đi chợ" 200.000đ, chọn **Nguồn tiền = Quỹ tiền ăn** thay vì ví.

**Ledger:** 1 transaction — `type=EXPENSE`, `sourceKind=FUND`, `sourceRefId=quy_tien_an`, `destinationKind=EXTERNAL`, `amountMinor=200000`.

**Expected balance:** Quỹ tiền ăn → **1.650.000đ**. `MEMBER_AVAILABLE(Vợ)` **không đổi** (đây chính là điểm F-03 đã sửa — không trừ kép). `totalExpense` tháng +200.000.

**Trường hợp không đủ quỹ:** nếu chọn "Quỹ sinh hoạt" (demo còn 100.000đ) và nhập 200.000đ → bị chặn bởi `InsufficientBalanceException` NGAY LÚC SUBMIT (Invariant 7), không tạo transaction. Đã có code + test (`wouldGoNegative`, group "Invariant 7" trong `financial_engine_test.dart`) — **kịch bản này KHÔNG phải blocker, đã hoạt động đúng.**

---

## 7. Nạp quỹ (Transfer, FUND_TOPUP)

**Input:** Vợ nạp 2.000.000đ vào Quỹ tiền ăn từ ví (đúng giao dịch "Nạp quỹ 01/09" trong canonical dataset).

**Ledger:** 1 transaction — `type=TRANSFER`, `transferKind=FUND_TOPUP`, `sourceKind=MEMBER_AVAILABLE`, `sourceRefId=vo`, `destinationKind=FUND`, `destinationRefId=quy_tien_an`, `amountMinor=2000000`.

**Expected balance:** Vợ giảm 2.000.000đ, Quỹ tăng 2.000.000đ. **Total Assets không đổi** (tự cân bằng nội bộ). `totalTransfer` +2.000.000; `totalIncome`/`totalExpense` **không đổi** — đây là điểm khác biệt cốt lõi so với model V1 (từng tính nhầm thành Chi).

---

## 8. Chuyển A → B (MEMBER_TO_MEMBER)

**Input:** Chồng chuyển 3.000.000đ cho Vợ (tiền chợ tháng).

**Ledger:** 1 transaction — `type=TRANSFER`, `transferKind=MEMBER_TO_MEMBER`, `sourceKind=MEMBER_AVAILABLE(Chồng)`, `destinationKind=MEMBER_AVAILABLE(Vợ)`.

**Expected balance:** Chồng -3.000.000, Vợ +3.000.000. Total Assets không đổi.

**Edge case đi kèm:** nếu chọn nhầm người nhận = người gửi (Chồng chuyển cho chính Chồng) → **REJECT** theo Invariant 15 — `[IMPLEMENTATION BLOCKER]`, chưa có validate này trong `add_transaction_sheet.dart`/repository.

---

## 9. Chuyển Savings Cash → Bank (SAVINGS_CONVERT)

**Input:** Vợ có Tiền mặt 1.200.000đ / Ngân hàng 8.000.000đ (canonical, khớp màn 08 và 16 sau Phase 1). Vợ chuyển toàn bộ 1.200.000đ từ Tiền mặt sang Ngân hàng.

**Ledger:** 1 transaction — `type=TRANSFER`, `transferKind=SAVINGS_CONVERT`, `sourceKind=MEMBER_SAVINGS_ASSET`, `sourceRefId="tien_mat|vo"`, `destinationKind=MEMBER_SAVINGS_ASSET`, `destinationRefId="ngan_hang|vo"`.

**Expected balance:** Vợ Tiền mặt → **0đ**, Ngân hàng → **9.200.000đ**. Tổng tiết kiệm Vợ vẫn **9.200.000đ** (không đổi — chỉ đổi chỗ). `MEMBER_AVAILABLE(Vợ)` không đổi.

---

## 10. Chuyển Savings Bank → Securities (loại tài sản MỚI, không có sẵn)

**Input:** Vợ tạo loại tài sản mới "Chứng khoán" (`SavingsAssetType` tự tạo qua nút "+ Thêm loại tài sản"). Vợ chuyển 5.000.000đ từ Ngân hàng sang Chứng khoán.

**Ledger:** 1 transaction — `sourceKind=MEMBER_SAVINGS_ASSET`, `sourceRefId="ngan_hang|vo"`, `destinationKind=MEMBER_SAVINGS_ASSET`, `destinationRefId="chung_khoan|vo"`.

**Expected balance:** Ngân hàng Vợ 9.200.000→4.200.000, Chứng khoán Vợ 0→5.000.000.

**Ý nghĩa của kịch bản này:** đây là bằng chứng cụ thể rằng model tổng quát hoá (`SavingsAssetType`) hoạt động đúng với **BẤT KỲ cặp loại tài sản nào**, kể cả loại vừa mới tạo, không cần thêm `transferKind` mới, không cần sửa `financial_engine.dart` — đúng thiết kế mục 7/9 ("thêm `transferKind` mới không cần đổi Engine", ở đây thậm chí không cần `transferKind` mới vì `SAVINGS_CONVERT` đã tổng quát). **Không có blocker nào ở kịch bản này** — nếu code hiện tại (`savings_screen.dart`, đã audit ở Phase 1) đúng như tài liệu, kịch bản này chạy được ngay.

---

## 11. App crash giữa lúc ghi transaction

**Input:** Vợ bấm Lưu 1 Expense 500.000đ. Ngay giữa lúc `LocalTransactionRepository.addTransaction` đang chạy (giữa bước kiểm tra `wouldGoNegative` và bước `insert`), app bị hệ điều hành kill (crash/hết pin/OS thu hồi).

**Expected:** Ghi phải **atomic** — hoặc toàn bộ xảy ra, hoặc không có gì xảy ra. Không có trạng thái "nửa vời".

**Vì sao thiết kế này an toàn:**
- Model **không lưu 1 field `balance` cache riêng ở tầng local** — balance luôn được tính động qua `computeAllPoolBalances(existing)` mỗi lần cần (đọc lại toàn bộ `TransactionRows`). Do đó không tồn tại nguy cơ kinh điển "đã ghi transaction nhưng quên cộng dồn vào balance cache" — không có cache nào để quên cập nhật.
- Nếu crash XẢY RA TRƯỚC khi câu lệnh `INSERT` của Drift hoàn tất → SQLite tự đảm bảo file DB không có bản ghi dở dang (write chưa commit không tồn tại sau khi mở lại) → mở lại app, giao dịch **không tồn tại**, y hệt như chưa từng bấm Lưu. An toàn, không cần code thêm.
- Với thao tác NHIỀU bước (`updateTransaction`/`reverseTransaction`, tạo 2-3 bản ghi cùng lúc): code hiện tại đã bọc đúng trong `_db.transaction(() async {...})` (Drift transaction) — nếu crash giữa chừng, toàn bộ 2-3 write đó bị rollback cùng nhau, không để lại trạng thái "có reversal mà chưa có bản thay thế".

**Việc cần làm:** không phải blocker mới — chỉ cần đảm bảo 3 guard mới (Invariant 13/14/15, sẽ code sau) khi implement **cũng phải nằm trong cùng khối `_db.transaction`** như các thao tác multi-write hiện có, không viết rời.

---

## 12. Hai thành viên thao tác gần như cùng lúc

**Ở Giai đoạn A (hiện tại, local-first):** Vợ và Chồng dùng 2 bản SQLite **RIÊNG BIỆT** trên 2 máy (chưa đồng bộ Firestore) → **không có race condition thật ở tầng dữ liệu**, vì không có tài nguyên nào bị 2 tiến trình ghi đồng thời. "Cùng lúc" chỉ có ý nghĩa ở Giai đoạn B trở đi.

**Ở Giai đoạn B (Firestore, sau khi mời người thứ 2):** ví dụ Vợ và Chồng cùng lúc chi từ Quỹ tiền ăn (giả sử đang còn 200.000đ) — Vợ ghi 150.000đ, Chồng ghi 100.000đ gần như đồng thời.

**Rủi ro nếu KHÔNG atomic:** cả 2 request đều đọc thấy "quỹ còn 200.000đ, đủ" trước khi bên kia kịp ghi → cả 2 đều được duyệt → Quỹ thành **-50.000đ**, vi phạm Invariant 7.

**Expected (đã đặc tả, chưa tới phase code):** Cloud Function `applyEffect` phải chạy trong **1 Firestore Transaction thật** (đọc-kiểm tra-ghi atomic trong cùng 1 khối), không phải batch write rời — request tới sau trong cùng transaction sẽ thấy balance đã bị request đầu trừ, phát hiện sẽ âm, và bị Firestore tự động retry/từ chối. Chỉ đúng 1 trong 2 được duyệt; người còn lại nhận lỗi rõ ràng ("Quỹ không đủ, ai đó vừa chi trước bạn"), không phải lỗi Firestore chung chung.

**Trạng thái:** đã đặc tả đầy đủ ở `financial-core-v2.md` §20 (Error Handling) + Invariant 7 — **không phải BLOCKER cho Giai đoạn A** (chưa cần vì chưa có 2 thiết bị chia sẻ dữ liệu), là yêu cầu bắt buộc phải làm đúng khi bắt đầu phase Cloud Function (`spec.md` phase 41).

---

## Sửa demo data phát sinh trong lúc dựng kịch bản 6/7

Khi dựng số liệu cho kịch bản 6/7, phát hiện thêm 1 **[DESIGN DATA INCONSISTENCY]** chưa bị bắt ở Phase 1/2: màn 15 (Quỹ tiền ăn — Chi tiết) hiển thị số dư **1.850.000đ** (khớp với dropdown ở màn 09: "Quỹ tiền ăn — còn 1.850.000đ"), nhưng cộng tay 4 dòng lịch sử hiển thị ngay bên dưới lại ra **1.555.000đ** (2.000.000 − 150.000 − 95.000 − 200.000), lệch 295.000đ.

**Đã sửa:** đổi 3 dòng chi tiêu từ quỹ (Đi chợ cuối tuần / Thịt bò, rau / Mua đồ ăn) thành **-60.000 / -50.000 / -40.000** — tổng chi 150.000đ, khớp đúng `2.000.000 − 150.000 = 1.850.000đ`, giờ cộng tay ra đúng số hiển thị trên `fund-balance` và khớp cả dropdown màn 09.

File đã sửa: `docs/design.html` (chỉ số liệu mockup, không đổi business logic).
