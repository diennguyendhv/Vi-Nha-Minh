# Financial Core V2 — Audit & Thiết kế lại

**Trạng thái: CHƯA CODE.** Tài liệu này là kết quả Phase 1-5 (Đọc → Audit → Liệt kê vấn đề → Thiết kế V2 → Financial Core Spec) theo đúng yêu cầu review. Phase 6 (UI Flow V2) chưa làm — sẽ làm sau khi các quyết định ở mục 26 được chốt, vì không thiết kế UI dựa trên logic tài chính còn sai.

**Đã chốt toàn bộ 6 quyết định ở mục 26:** `MEMBER_AVAILABLE` không được âm (giống Fund/Savings) · nạp quỹ/tiết kiệm có category riêng để lên báo cáo · sửa/xoá giao dịch dùng **reversal ledger đầy đủ** (không dùng soft-delete đơn giản) · công thức tài chính dùng 3 tổng tách biệt · Status không ảnh hưởng balance · chuyển khoản giữa thành viên gộp thành 1 luồng chọn người nhận tự do (bỏ 2 category "Chồng đưa vợ"/"Vợ đưa chồng" cứng). Bước tiếp theo: đồng bộ `spec.md`/`CLAUDE.md`, rồi vẽ lại UI liên quan trong `docs/design.html`.

Tài liệu này **thay thế** phần mô hình tài chính trong `spec.md`/`CLAUDE.md`/`docs/design.html` hiện tại. Chưa sửa 3 file đó — đợi chốt xong mục 26 rồi mới đồng bộ ngược lại, tránh phải sửa 2 lần.

---

## 1. Executive Summary

Thiết kế V1 (`docs/design.html` hiện tại) dùng mô hình **"mọi danh mục chỉ là Thu hoặc Chi"** (`typeId: thu|chi` + cờ `isSaving` + cờ `transferToUid`). Mô hình này **sai về bản chất kế toán**: nó biến mọi khoản chuyển tiền nội bộ (vợ/chồng, nạp quỹ, nạp tiết kiệm) thành "Chi", làm phình Tổng chi và làm sai lệch mọi báo cáo dòng tiền — dù tài sản gia đình không hề giảm.

Thiết kế V2 thêm **loại giao dịch thứ 3: `TRANSFER`**, tách biệt hoàn toàn khỏi `INCOME`/`EXPENSE`. Mọi giao dịch giờ có dạng thống nhất: **`source → destination`**, trong đó một trong hai đầu có thể là `EXTERNAL` (bên ngoài hệ thống). Nhờ vậy:

- `EXPENSE` = destination là `EXTERNAL` → Tổng tài sản giảm.
- `INCOME` = source là `EXTERNAL` → Tổng tài sản tăng.
- `TRANSFER` = cả 2 đầu đều ở trong hệ thống → Tổng tài sản **không đổi**, chỉ đổi chỗ.

Một hàm Financial Engine duy nhất (`applyTransactionEffect`) xử lý cả 3 loại — không còn nhánh logic riêng cho quỹ, tiết kiệm, chuyển khoản như V1. Đây là thay đổi lớn nhất và quan trọng nhất của tài liệu này.

---

## 2. Bảng vấn đề (Audit)

| ID | Vấn đề | Mức độ | Vì sao sai / rủi ro | Đề xuất |
|---|---|---|---|---|
| F-01 | "Chồng đưa vợ/Vợ đưa chồng" được ghi là Chi (`typeId: chi`) | **CRITICAL** | Tài sản gia đình không giảm khi chuyển tiền nội bộ, nhưng Tổng chi vẫn +3.000.000 → sai báo cáo dòng tiền | Thêm `type: TRANSFER`, xem mục 7 |
| F-02 | Tiết kiệm là 1 category `isSaving` thuộc Chi | **CRITICAL** | Nạp tiết kiệm không phải chi tiêu — tiền vẫn thuộc gia đình. Trộn vào Tổng chi làm biến dạng tỷ lệ tiết kiệm thật (nó lại được cộng vào chính công thức tính tỷ lệ tiết kiệm — tự tham chiếu) | Tiết kiệm = `TRANSFER`, đích là `MEMBER_SAVINGS_CASH`/`MEMBER_SAVINGS_BANK`, xem mục 9 |
| F-03 | Nạp quỹ trừ số dư người nạp (Chi) **và** khi mua bằng quỹ tích tiếp lại trừ cả số dư người mua **lẫn** số dư quỹ | **CRITICAL** | **Trừ kép (double subtraction)** — 200.000đ bị trừ 2 lần khỏi tài sản gia đình dù chỉ 1 lượng tiền rời hệ thống. Test case 7 trong yêu cầu chứng minh rõ: chi từ quỹ chỉ được trừ quỹ, số dư thành viên phải giữ nguyên | Chi từ quỹ = `EXPENSE` với `source = FUND`, không đụng số dư thành viên. Xem mục 8 |
| F-04 | `CATEGORY` gánh cả vai trò `TransactionType` lẫn business rule (isSaving, transferToUid) | HIGH | Category lẽ ra chỉ là nhãn phân loại để báo cáo/lọc, không nên quyết định tiền chạy về đâu — khó mở rộng, khó test độc lập | Tách hẳn: `TRANSACTION.type` + `TRANSACTION.source/destination` quyết định dòng tiền; `CATEGORY` chỉ còn là nhãn + `type` để nhóm báo cáo. Xem mục 11 |
| F-05 | Công thức "Tổng thu = Tổng chi + Số tiền còn lại; Tổng chi = Chi phí + Tiết kiệm" | **CRITICAL** | Tự mâu thuẫn với F-02 — coi tiết kiệm vừa là "chi" vừa dùng để tính "còn lại". Nếu Transfer bị tính vào Chi (F-01) thì công thức càng sai thêm | Bỏ hẳn, thay bằng 3 tổng tách biệt: Income / External Expense / Transfer. Xem mục 17 |
| F-06 | `STATUS` không có state machine, không rõ đổi trạng thái có ảnh hưởng balance không | HIGH | Nếu sau này ai đó code "Pending thì chưa trừ tiền, Paid mới trừ" sẽ đá vào balance đã trừ sẵn lúc tạo — 2 nguồn sự thật | Chốt rõ: Status **không bao giờ** ảnh hưởng balance ở app này — đã xác nhận, xem mục 12 |
| F-07 | Không phân biệt `transactionDate` và `createdAt` | MEDIUM | Ghi hôm nay 1 khoản chi hôm qua sẽ bị tính nhầm sang tháng ghi sổ thay vì tháng phát sinh thật | Thêm `transactionDate` riêng, mọi rollup theo tháng dùng field này | 
| F-08 | Tiền lưu dạng số thực ngầm định (schema ghi `number amount`) | MEDIUM | Sai số dấu phẩy động khi cộng dồn hàng nghìn giao dịch (VD 0.1 + 0.2 ≠ 0.3 trong floating point) | Dùng `amountMinor` (số nguyên) + `currency`. Xem mục 6 |
| F-09 | Xoá Category/Status/Fund/Member không có cơ chế soft-delete | HIGH | Xoá "Sinh hoạt" sau khi đã có 500 giao dịch tham chiếu → giao dịch cũ mất nhãn, UI vỡ | Soft delete (`isActive`/`deletedAt`) cho mọi entity người dùng tự tạo. Xem mục 18 |
| F-10 | Không có cơ chế thống nhất sửa/xoá giao dịch qua Financial Engine | **CRITICAL** | Sửa thẳng `amount` trong DB mà quên cập nhật balance → số dư sai vĩnh viễn, rất khó phát hiện | `updateTransaction`/`deleteTransaction` bắt buộc qua Cloud Function tính lại pool. Xem mục 21 |
| F-11 | `FUND_ENTRY` lưu `linkedTxId` trỏ ngược về `TRANSACTION`, còn `TRANSACTION` lưu `fundId` trỏ tới `FUND` — 2 chiều, 2 nơi ghi | MEDIUM | Nguy cơ 2 bên lệch nhau nếu 1 trong 2 write thất bại giữa chừng (không atomic thật) | Bỏ hẳn `FUND_ENTRY` — Quỹ chỉ là 1 loại "pool", lịch sử quỹ = lọc từ chính bảng `TRANSACTION`. Xem mục 8, 14 |
| F-12 | Không có cơ chế chống double-submit (bấm Lưu 2 lần) | MEDIUM | Tạo 2 giao dịch giống hệt nhau, cộng dồn sai | Thêm `clientTxId` (idempotency key) sinh phía client, Cloud Function bỏ qua nếu trùng |
| F-13 | Không có validate categoryId/fundId/statusId thuộc đúng `familyId` khi ghi giao dịch | HIGH | Lỗ hổng bảo mật/toàn vẹn: 1 client có thể gửi categoryId của gia đình khác (nếu id đoán được) | Cloud Function phải kiểm tra mọi FK thuộc đúng family trước khi ghi |
| F-14 | Ngân sách (Budget) không nói rõ Transfer có tính vào "đã chi" không | MEDIUM | Nạp tiết kiệm 2 triệu có thể vô tình làm "Ngân sách ăn uống" báo vượt nếu code gộp nhầm | Chỉ `type = EXPENSE` mới trừ vào budget. Xem mục 13 |
| F-15 | Person-toggle ở màn Thêm giao dịch chỉ có 2 nút cứng (Vợ/Chồng) | LOW (đã biết, ghi trong spec cũ) | Không scale khi gia đình >2 người (đã có phase refactor `roleLabel` tự do ở Giai đoạn B) | Giữ nguyên lộ trình cũ, không cần sửa ngay |
| F-16 | Category "Nạp quỹ [tên quỹ]" chưa tồn tại trong danh sách seed nhưng được nhắc tới trong mô tả nạp quỹ | MEDIUM | Không rõ nạp quỹ dùng category nào để lên báo cáo | Ở V2 không cần category riêng cho từng quỹ nữa — nạp quỹ là `TRANSFER`, gắn 1 category chung "Nạp quỹ" hoặc không cần category (xem mục 8) |
| F-17 | Sơ đồ Use Case cũ lẫn UI action ("Xem biểu đồ theo hạng mục") vào chung nhóm với nghiệp vụ thật | LOW | Làm sơ đồ trông nhiều hơn thực chất, khó phân biệt cái gì cần Financial Engine | Gộp lại ở mục 15 |

---

## 3. Nguyên tắc tài chính mới

1. **Một transaction chỉ chạm tối đa 2 "pool" tiền** (nguồn và đích), không hơn.
2. **`TRANSFER` không bao giờ thay đổi Tổng tài sản.** `INCOME`/`EXPENSE` mới thay đổi.
3. **Category không quyết định tiền đi đâu — `type` + `source`/`destination` trên transaction mới quyết định.** Category chỉ để gắn nhãn/nhóm báo cáo.
4. **Status không bao giờ ảnh hưởng balance.** Balance được trừ/cộng ngay khi transaction được tạo, bất kể status là gì.
5. **Không lưu số âm trong `amountMinor`.** Chiều +/- suy ra từ vị trí source/destination.
6. **Mọi số liệu tổng hợp (balance, rollup tháng, báo cáo) phải build lại được 100% từ tập `TRANSACTION` gốc.** Cache chỉ để tăng tốc.
7. **Sửa/Xoá giao dịch bắt buộc qua Financial Engine**, không update thẳng field trong DB.

---

## 4. Financial Model — "Pool" tiền

Thay vì object rời rạc (`memberBalances`, `funds`, `savings` tách biệt như V1), V2 coi mọi nơi giữ tiền là một **pool**, xác định bằng `(kind, refId)`:

| kind | refId | Ý nghĩa |
|---|---|---|
| `MEMBER_AVAILABLE` | uid | Tiền có thể chi của 1 thành viên |
| `MEMBER_SAVINGS_CASH` | uid | Tiết kiệm hiện tại (chưa gửi NH) của 1 thành viên |
| `MEMBER_SAVINGS_BANK` | uid | Tiết kiệm đã gửi ngân hàng của 1 thành viên |
| `FUND` | fundId | 1 quỹ cụ thể (Quỹ tiền ăn, Quỹ sinh hoạt...) |
| `EXTERNAL` | — | Bên ngoài hệ thống (lương từ công ty, tiền trả cho người bán...) |

**Không tạo bảng `ACCOUNT` riêng cho MVP** (xem Phương án A/B ở mục 25) — các pool `MEMBER_*` vẫn cache trong `MEMBER_BALANCE`, `FUND` vẫn cache `balance` trên chính `funds/{fundId}`, giống V1. Điểm khác biệt là **cách 1 transaction tham chiếu tới các pool này được chuẩn hoá** (mục 6), nên Financial Engine xử lý bằng 1 hàm chung thay vì nhiều nhánh if/else theo category.

**Total Assets = tổng balance của mọi pool KHÔNG phải `EXTERNAL`.** Vì mỗi đồng tiền chỉ nằm trong đúng 1 pool tại 1 thời điểm, không có double count.

---

## 5. Asset Model

```
Available Money (1 gia đình)  = Σ MEMBER_AVAILABLE của mọi thành viên
Savings Assets (1 gia đình)   = Σ (MEMBER_SAVINGS_CASH + MEMBER_SAVINGS_BANK) của mọi thành viên
Fund Assets (1 gia đình)      = Σ FUND.balance của mọi quỹ

Total Assets = Available Money + Savings Assets + Fund Assets
```

Ví dụ mục 6 trong yêu cầu (Member A 5tr, Member B 3tr, Fund 2tr, Savings 4tr):

```
Available Money = 5 + 3 = 8 triệu
Reserved (Fund + Savings) = 2 + 4 = 6 triệu
Total Assets = 14 triệu
```

— khớp chính xác.

---

## 6. Transaction Model (entity trung tâm)

```
TRANSACTION
  txId                PK
  familyId             FK
  yearMonth            FK (derived tu transactionDate, giu phan trang theo thang nhu V1)
  type                 "INCOME" | "EXPENSE" | "TRANSFER"
  transferKind         nullable, chi khi type=TRANSFER:
                        "MEMBER_TO_MEMBER" | "SAVINGS_TOPUP" | "SAVINGS_WITHDRAW" |
                        "SAVINGS_TO_BANK" | "FUND_TOPUP"
  categoryId           FK (nhan, luon co - de bao cao/loc, KHONG quyet dinh dong tien)
  sourceKind           "MEMBER_AVAILABLE" | "MEMBER_SAVINGS_CASH" | "MEMBER_SAVINGS_BANK" | "FUND" | "EXTERNAL"
  sourceRefId          uid | fundId | null (null khi sourceKind = EXTERNAL, tuc INCOME)
  destinationKind      cung enum voi sourceKind
  destinationRefId     uid | fundId | null (null khi destinationKind = EXTERNAL, tuc EXPENSE)
  amountMinor          int, LUON DUONG
  currency             "VND" (mo rong duoc sau)
  note                 string
  statusId             FK, nullable — KHONG anh huong balance (xem muc 12)
  statusUpdatedAt       timestamp
  transactionDate       date — ngay nghiep vu, dung de rollup thang
  createdAt / createdBy
  reversalOfTxId        FK, nullable — transaction nay la ban hoan tac cua txId nao (xem muc 21)
  correctsTxId           FK, nullable — transaction nay la ban thay the/sua cho txId nao
  reversedByTxId         FK, nullable — transaction goc bi huy boi ban reversal nao (null = con hieu luc)
  clientTxId            string — idempotency key chong double-submit
  version               int — optimistic concurrency / sync (xem muc 22)
```

**Ví dụ áp dụng cho mọi nghiệp vụ hiện có:**

| Nghiệp vụ | type | source | destination |
|---|---|---|---|
| Lương tháng 9 | INCOME | EXTERNAL | MEMBER_AVAILABLE(Chồng) |
| Mua đồ ăn (ví thường) | EXPENSE | MEMBER_AVAILABLE(Vợ) | EXTERNAL |
| Mua đồ ăn (dùng Quỹ tiền ăn) | EXPENSE | FUND(quỹ tiền ăn) | EXTERNAL |
| Chồng đưa vợ 3 triệu | TRANSFER (MEMBER_TO_MEMBER) | MEMBER_AVAILABLE(Chồng) | MEMBER_AVAILABLE(Vợ) |
| Nạp quỹ tiền ăn 2 triệu | TRANSFER (FUND_TOPUP) | MEMBER_AVAILABLE(Vợ) | FUND(quỹ tiền ăn) |
| Nạp tiết kiệm 2 triệu | TRANSFER (SAVINGS_TOPUP) | MEMBER_AVAILABLE(X) | MEMBER_SAVINGS_CASH(X) |
| Rút tiết kiệm 500k về ví | TRANSFER (SAVINGS_WITHDRAW) | MEMBER_SAVINGS_CASH(X) | MEMBER_AVAILABLE(X) |
| Gửi tiết kiệm vào NH 10 triệu | TRANSFER (SAVINGS_TO_BANK) | MEMBER_SAVINGS_CASH(X) | MEMBER_SAVINGS_BANK(X) |

**Financial Engine — 1 hàm duy nhất xử lý mọi loại:**

```
function applyEffect(tx, sign) {              // sign = +1 khi apply, -1 khi reverse
  if (tx.sourceKind !== "EXTERNAL")
    incrementPool(tx.sourceKind, tx.sourceRefId, -sign * tx.amountMinor);
  if (tx.destinationKind !== "EXTERNAL")
    incrementPool(tx.destinationKind, tx.destinationRefId, +sign * tx.amountMinor);
}
```

Không còn nhánh riêng cho "quỹ", "tiết kiệm", "chuyển khoản" trong domain logic — tất cả chỉ là tham số `sourceKind/destinationKind` khác nhau. Đây chính là "Financial Engine" trung tâm mà bạn yêu cầu ở mục 1.

---

## 7. Transfer Model

`TRANSFER` là loại giao dịch mà **cả source và destination đều không phải `EXTERNAL`**. 5 `transferKind` hiện có (bảng trên) đều dùng chung 1 cơ chế `applyEffect`. Thêm `transferKind` mới sau này (vd chuyển giữa 2 quỹ) không cần đổi Financial Engine, chỉ cần cho phép `sourceKind/destinationKind = FUND` ở cả 2 đầu.

**Đang chờ chốt (xem giải thích chi tiết + ví dụ ở mục 26, câu hỏi #2):** giữ 2 category "Chồng đưa vợ"/"Vợ đưa chồng" cố định, hay gộp thành 1 luồng "Chuyển tiền cho thành viên khác" với người dùng tự chọn người nhận mỗi lần? Đề xuất chọn phương án 2 (tổng quát, đúng nguyên tắc `roleLabel` tự do đã có trong `CLAUDE.md`).

---

## 8. Fund Model (đã sửa lỗi trừ kép)

```
FUND
  fundId PK, familyId FK, name, color, isActive, balance (cached)
```

- **Nạp quỹ** = `TRANSFER(FUND_TOPUP)`, gắn category riêng **"Nạp quỹ"** (`type = TRANSFER`, seed mặc định, dùng chung cho mọi quỹ — không cần 1 category riêng cho từng quỹ, vì muốn xem theo từng quỹ cụ thể thì lọc theo `destinationRefId = fundId`, xem mục 14): `MEMBER_AVAILABLE(người nạp) -X`, `FUND +X`.
- **Chi tiêu dùng quỹ** = `EXPENSE`: `source = FUND`, `destination = EXTERNAL`. **Không đụng `MEMBER_AVAILABLE` của người mua.** Đây là điểm sửa quan trọng nhất so với V1 (F-03).
- **Chi tiêu không dùng quỹ** = `EXPENSE` bình thường: `source = MEMBER_AVAILABLE(người mua)`.
- **Không cần `FUND_ENTRY` riêng nữa** — lịch sử 1 quỹ = truy vấn `TRANSACTION` where `sourceRefId = fundId OR destinationRefId = fundId`.
- **Quỹ không được âm:** Cloud Function từ chối (rollback) nếu `applyEffect` sẽ làm `FUND.balance < 0` — kiểm tra trong cùng 1 Firestore transaction để tránh race condition 2 máy ghi đồng thời (đúng yêu cầu ban đầu, vẫn giữ).

Đối chiếu lại đúng Test 6/7/8 trong yêu cầu:

```
Test 6 — Top up: Member 5 → 3, Fund 0 → 2         (TRANSFER, cả 2 pool đổi, tổng không đổi)
Test 7 — Spend from Fund 500k: Member 3 → 3 (KHÔNG ĐỔI), Fund 2 → 1.5   (EXPENSE, chỉ Fund đổi)
Test 8 — Spend without Fund 500k: Member 3 → 2.5, Fund 2 → 2 (KHÔNG ĐỔI)  (EXPENSE, chỉ Member đổi)
```

---

## 9. Savings Model

```
MEMBER_BALANCE
  uid PK, availableBalance, savingsCash, savingsBank   (đổi tên cho rõ nghĩa so với V1)
```

Tiết kiệm **không còn là Category kiểu Chi** (sửa F-02). Toàn bộ thao tác tiết kiệm là `TRANSFER`, gắn 1 category riêng **"Tiết kiệm"** (`type = TRANSFER`, seed mặc định, dùng chung cho cả 3 `transferKind` bên dưới — phân biệt bằng `transferKind`, không cần 3 category riêng):

- **Nạp tiết kiệm:** `MEMBER_AVAILABLE -X` → `MEMBER_SAVINGS_CASH +X`.
- **Rút tiết kiệm về ví:** `MEMBER_SAVINGS_CASH -X` → `MEMBER_AVAILABLE +X`.
- **Gửi ngân hàng:** `MEMBER_SAVINGS_CASH -X` → `MEMBER_SAVINGS_BANK +X`.

Cả 3 đều KHÔNG đổi Total Assets, đúng ví dụ mục 5/8/9 trong yêu cầu. Màn hình "Tiết kiệm — Nhập giao dịch" (đã có ở `docs/design.html` màn 17) giữ nguyên UI, chỉ đổi bản chất transaction phía sau từ "category isSaving + savingsAction" sang "TRANSFER + transferKind".

---

## 10. Member Model

Không đổi so với V1 (uid, familyId, displayName, roleLabel tự do, isOwner). Bổ sung: khi 1 thành viên rời gia đình, **soft-delete** (`isActive=false`), không xoá cứng — transaction cũ vẫn cần hiển thị đúng tên người thực hiện. Đề xuất thêm `displayNameSnapshot` trên transaction (denormalize tên tại thời điểm ghi) để lịch sử không đổi ngay cả khi thành viên đổi tên hoặc rời đi sau này.

---

## 11. Category Model

```
CATEGORY
  categoryId PK, familyId FK, name, color,
  type ("INCOME" | "EXPENSE" | "TRANSFER"),
  isDefault, isActive (soft delete),
  statsEnabled (giu nguyen tu V1 — bat/tat hien o man Tong hop trang thai)
```

Bỏ hẳn `isSaving` và `transferToUid` khỏi Category (F-04) — 2 field này từng bắt Category "diễn" luôn vai trò của Transaction, sai nguyên tắc ở mục 14 trong yêu cầu. Category giờ **chỉ là nhãn + type để nhóm báo cáo**, không quyết định pool nào bị trừ/cộng.

`STATUS` (subcollection của Category) giữ nguyên như V1: `statusId, categoryId, name, sortOrder` — không đổi.

---

## 12. Status Model — quyết định rõ ràng

**Trả lời trực tiếp câu hỏi mục 15:** Status trong app này **không phải trạng thái thanh toán** (không giống Pending/Paid của hệ thống thanh toán thật). Nó là **nhãn tiến độ cam kết cá nhân** (Cho đi/Dâng hiến: đã chuẩn bị tới đâu). Vì vậy:

- Tiền bị trừ **ngay khi transaction được tạo**, bất kể status là gì.
- Đổi status (Chưa chuẩn bị → Đã chuẩn bị → Đã gửi) **không bao giờ** gọi tới Financial Engine, không tăng/giảm bất kỳ pool nào.
- Sửa `amount` của 1 transaction đã có status: vẫn đi qua `updateTransaction` bình thường (mục 21), không liên quan tới status.
- Không cần "hoàn tiền khi Cancelled" vì app không có khái niệm Cancelled — muốn huỷ thì dùng `deleteTransaction`/reversal (mục 21), tách biệt khỏi Status.

Đây là lựa chọn **cố tình đơn giản** (đúng nguyên tắc mục 38 — không over-engineering) vì đúng với nghiệp vụ gốc (sổ Google Sheets của gia đình chủ dự án ghi nhận tiền ngay, status chỉ để nhắc việc). Nếu sau này có nhu cầu "giao dịch chờ duyệt mới trừ tiền" thật sự (không phải nhu cầu hiện tại), đó sẽ là một field khác (`isPending`) tách biệt hoàn toàn khỏi `statusId`, không tái sử dụng cơ chế Status này.

---

## 13. Budget Model

```
BUDGET
  yearMonth PK, familyId FK, categoryLimits: { categoryId: amountMinor }
```

**Chỉ transaction có `type = EXPENSE`** mới cộng vào "đã chi" của 1 category trong Budget. `TRANSFER` (kể cả nạp tiết kiệm/quỹ) không bao giờ tính vào Budget — sửa đúng F-14.

---

## 14. Database Schema V2 (tổng hợp)

| Entity | Vai trò | Khoá | Soft delete | Ghi chú |
|---|---|---|---|---|
| `FAMILY` | Gia đình/sổ | familyId PK | không cần | không đổi so với V1 |
| `MEMBER` | Thành viên | uid PK, familyId FK | `isActive` | thêm `isActive` |
| `INVITE` | Lời mời | inviteId PK, familyId FK | tự hết hạn | không đổi |
| `CATEGORY` | Nhãn phân loại | categoryId PK, familyId FK | `isActive` | bỏ `isSaving`/`transferToUid`, thêm `type` (3 giá trị) |
| `STATUS` | Bước tiến độ (con của Category) | statusId PK, categoryId FK | `isActive` | không đổi |
| `FUND` | 1 pool tiền dạng quỹ | fundId PK, familyId FK | `isActive` | không đổi, bỏ subcollection `entries` |
| `TRANSACTION` | **Nguồn sự thật duy nhất** — mọi chuyển động tiền | txId PK, familyId FK | `deletedAt` | xem mục 6, thay thế cả `transactions` và `funds/{id}/entries` của V1 |
| `MEMBER_BALANCE` | Cache số dư 3 pool của 1 thành viên | uid PK | không cần (derived) | đổi tên field (mục 9) |
| `MONTH_SUMMARY` | Rollup tháng | yearMonth PK, familyId FK | không cần (derived) | xem mục 17 |
| `BUDGET` | Ngân sách | yearMonth PK, familyId FK | không cần | không đổi |

**Index cần có (Firestore composite):**
- `TRANSACTION`: `(familyId, yearMonth, deletedAt)` — liệt kê theo tháng, ẩn transaction đã xoá.
- `TRANSACTION`: `(familyId, sourceKind, sourceRefId)` và `(familyId, destinationKind, destinationRefId)` — tra lịch sử 1 pool (vd 1 quỹ, 1 tài khoản tiết kiệm) mà không phải quét toàn bộ.
- `TRANSACTION`: `(familyId, categoryId, statusId)` — cho màn "Trạng thái — Chi tiết".
- `TRANSACTION`: `clientTxId` unique per family — chặn double-submit (F-12).

**Validation bắt buộc ở Cloud Function** (không chỉ Security Rules — F-13): mọi `categoryId`/`fundId`/`statusId`/`sourceRefId`/`destinationRefId` gửi lên phải thuộc đúng `familyId` của người gọi.

---

## 15. Use Case V2 — điều chỉnh so với 35 use case cũ

Giữ nguyên phần lớn 9 nhóm. Thay đổi cụ thể:

- **Nhóm "Giao dịch":** đổi "Gắn trạng thái cho giao dịch" → tách rõ 2 use case: *"Chọn loại giao dịch (Thu/Chi/Chuyển)"* và *"Gắn trạng thái tiến độ (không ảnh hưởng số dư)"* — để không ai hiểu nhầm status quyết định tiền.
- Thêm use case **"Sửa giao dịch (tính lại số dư qua Financial Engine)"** và **"Huỷ giao dịch (reversal, không xoá lịch sử)"** — hiện chưa có use case rõ ràng cho việc này dù đã có phase sửa/xoá.
- **Nhóm "Quỹ, tạo được nhiều cái":** đổi "Nạp tiền vào quỹ, tự trừ chi phí người nạp" → *"Nạp tiền vào quỹ (chuyển nội bộ, không phải chi)"*.
- **Nhóm "Tiết kiệm":** thêm *"Xem lịch sử tiết kiệm (nạp/rút/chuyển ngân hàng)"*.
- Gộp "Xem biểu đồ theo hạng mục" vào chung "Xem tổng hợp theo tháng" — đây là 1 cách hiển thị, không phải use case nghiệp vụ riêng (đúng góp ý mục 30).
- Thêm ghi chú: "Import CSV" và "Backup/Restore" (đã có trong `spec.md` Giai đoạn F) cần chạy qua đúng Financial Engine khi tạo transaction hàng loạt, không insert thẳng vào DB — nếu không sẽ bỏ qua toàn bộ validate ở mục 14.

---

## 16. Business Rules (tóm tắt, tham chiếu Invariants ở mục 18)

- Balance của 1 pool **luôn** = tổng các `applyEffect` của mọi transaction chưa xoá chạm tới pool đó → luôn rebuild được (Invariant 10).
- Không transaction nào được tạo nếu thiếu `sourceKind`/`destinationKind` hợp lệ theo `type` (INCOME bắt buộc source=EXTERNAL, EXPENSE bắt buộc destination=EXTERNAL, TRANSFER cấm cả 2 đầu là EXTERNAL).
- Quỹ, Tiết kiệm, và `MEMBER_AVAILABLE` **không được âm** — mọi `EXPENSE`/`TRANSFER` làm 1 pool âm đều bị Cloud Function từ chối, kể cả chi tiêu trực tiếp từ số dư cá nhân.

---

## 17. Financial Formulas (thay thế hoàn toàn công thức cũ)

```
Total Income          = Σ amountMinor  (type = INCOME)
Total External Expense = Σ amountMinor  (type = EXPENSE)
Total Transfer Volume  = Σ amountMinor  (type = TRANSFER)   // chỉ để hiển thị, KHÔNG cộng vào Income/Expense

Total Assets (cuối kỳ) = Total Assets (đầu kỳ) + Total Income − Total External Expense
                          // Transfer không xuất hiện trong công thức này — tự cân bằng nội bộ

Available Money        = Σ MEMBER_AVAILABLE mọi thành viên
Savings Assets          = Σ (MEMBER_SAVINGS_CASH + MEMBER_SAVINGS_BANK)
Fund Assets             = Σ FUND.balance

Tỷ lệ tiết kiệm tháng   = (Total Income − Total External Expense) / Total Income
                          // giữ nguyên công thức hành vi tài chính cũ — vẫn đúng vì giờ
                          // "Total External Expense" đã KHÔNG còn lẫn tiết kiệm/chuyển khoản nữa
```

`MONTH_SUMMARY` lưu 3 số `totalIncome / totalExpense / totalTransfer` (thay cho `totalIncome/totalSpending/totalSaving` của V1), cộng `categoryTotals` (mọi type) và `statusTotals` (theo statusId).

---

## 18. Invariants bắt buộc

1. Mỗi transaction chạm tối đa 2 pool (source, destination).
2. `TRANSFER` không bao giờ đổi Total Assets.
3. `EXPENSE` làm Total Assets giảm đúng `amountMinor`.
4. `INCOME` làm Total Assets tăng đúng `amountMinor`.
5. Chi từ Quỹ (`source=FUND`) không đụng `MEMBER_AVAILABLE` của người mua.
6. Nạp Quỹ/Tiết kiệm trừ đúng 1 pool nguồn, cộng đúng 1 pool đích, cùng lúc, cùng giá trị.
7. Quỹ, Tiết kiệm, và `MEMBER_AVAILABLE` không bao giờ âm (kiểm tra cả client lẫn server, trong 1 Firestore transaction) — **đã chốt: không có ngoại lệ nào được phép âm.**
8. Sửa/xoá transaction bắt buộc qua Financial Engine (`updateTransaction`/`deleteTransaction`), không ghi thẳng field — **đã chốt: dùng reversal ledger (mục 21), transaction gốc không bao giờ bị mutate hay xoá cứng.**
9. Status không bao giờ kích hoạt `applyEffect`.
10. Mọi balance/rollup phải rebuild lại được 100% từ tập `TRANSACTION` gốc chưa xoá.
11. Category/Status/Fund/Member "xoá" chỉ soft-delete, transaction cũ vẫn hiển thị đúng.
12. `amountMinor` luôn dương; dấu suy ra từ `type` + vị trí source/destination.

---

## 19. Edge Cases

- Xoá 1 category đang có `statsEnabled=true` và đang được lọc ở màn Trạng thái — soft-delete, màn đó phải tự ẩn category đã inactive khỏi bộ lọc mới nhưng vẫn hiện đúng dữ liệu cũ khi xem lịch sử.
- Sửa transaction đổi hẳn `type` (vd từ EXPENSE sang TRANSFER) — Financial Engine phải: revert effect cũ theo `type` cũ, rồi apply effect mới theo `type` mới, trong cùng 1 Cloud Function transaction (mục 21).
- 2 thiết bị cùng sửa 1 transaction gần như đồng thời (đang ở Giai đoạn B trở đi) — dùng `version` (optimistic concurrency): ghi thất bại nếu `version` gửi lên không khớp bản mới nhất, client phải tải lại rồi thử lại.
- Family chuyển từ Cá nhân sang Gia đình (migrate local → cloud) — toàn bộ `TRANSACTION` local giữ nguyên shape (đã chuẩn hoá `type/source/destination` ngay từ Giai đoạn A local-first), nên migrate chỉ là copy nguyên văn, không cần transform.
- Rút tiết kiệm nhiều hơn số dư đang có — chặn như quỹ (Invariant 7), báo lỗi rõ ràng tương tự UI đã có ở màn 09.

---

## 20. Error Handling

- Mọi lỗi nghiệp vụ (quỹ âm, tiết kiệm âm, FK sai family, version conflict) phải trả về mã lỗi rõ ràng cho client hiển thị đúng thông điệp (không phải lỗi Firestore chung chung).
- Cloud Function ghi `applyEffect` phải chạy trong 1 Firestore Transaction (không phải batch write) để đảm bảo đọc-kiểm tra-ghi atomic, tránh race condition đã nêu ở Invariant 7.

---

## 21. Edit / Delete / Reversal — ĐÃ CHỐT: Phương án B (reversal ledger đầy đủ)

**`TRANSACTION` là append-only cho mọi field ảnh hưởng balance** (`type`, `amountMinor`, `sourceKind`/`sourceRefId`, `destinationKind`/`destinationRefId`) — không bao giờ `UPDATE` thẳng các field này lên 1 bản ghi đã tồn tại, và không dùng `deletedAt` để xoá transaction (khác với Category/Status/Fund/Member ở mục 18, vẫn soft-delete bình thường).

- **`reverseTransaction(txId)`** — Cloud Function tạo 1 transaction mới: `sourceKind`/`sourceRefId` và `destinationKind`/`destinationRefId` **đảo ngược** so với bản gốc, cùng `amountMinor`, `reversalOfTxId = txId`; đồng thời set `reversedByTxId` lên bản gốc. Bản gốc **không bị xoá**, vẫn nằm trong DB với nhãn "đã hoàn tác". `applyEffect` của bản reversal tự động triệt tiêu đúng hiệu ứng cũ vì source/destination đảo chiều.
- **`deleteTransaction(txId)`** (người dùng bấm "Xoá giao dịch") = gọi `reverseTransaction(txId)`. Không có xoá thật ở tầng dữ liệu.
- **`updateTransaction(txId, newFields)`** (sửa số tiền/loại giao dịch/nguồn-đích) = `reverseTransaction(txId)` **rồi** `createTransaction(newFields, correctsTxId: txId)`. 1 lần sửa tạo ra 3 bản ghi (gốc, hoàn tác, thay thế); UI chỉ hiện bản mới nhất theo mặc định (lọc `reversedByTxId IS NULL`), có thể bấm xem lịch sử sửa để thấy cả chuỗi.
- **Field không ảnh hưởng balance** (`note`, `categoryId` khi `type` giữ nguyên, `statusId`) được sửa trực tiếp, không cần qua reversal.

Đây là lựa chọn có chi phí cao hơn phương án soft-delete đơn giản (nhiều bản ghi hơn, mọi nơi hiển thị danh sách/rollup phải lọc `reversedByTxId IS NULL`) — đổi lại: không ai "sửa mất" lịch sử, đúng tinh thần app tài chính thật, và sẵn sàng cho multi-device/multi-user ở Giai đoạn B mà không phải thiết kế lại lần nữa.

---

## 22. Offline / Sync

Thêm sẵn từ Giai đoạn A (không cần dùng ngay, nhưng không muốn phải thêm field sau và migrate dữ liệu cũ):

```
updatedAt, updatedBy   — moi bang co the sua
deletedAt              — soft delete
version                — optimistic concurrency, tang moi lan update
clientTxId             — idempotency, chong double-submit / chong tao trung khi offline retry
```

Chưa cần logic merge conflict phức tạp ở Giai đoạn A/B (local-first, 1 thiết bị hoặc 2 thiết bị ít xung đột) — nhưng schema có sẵn `version` để Giai đoạn sau thêm conflict resolution (vd "last write wins theo version" hoặc hỏi người dùng) mà không phải đổi schema.

---

## 23. UI Flow V2 (sơ bộ — chưa thiết kế lại chi tiết)

Chưa vẽ lại `docs/design.html` ở bước này (đúng yêu cầu: Financial Core đúng trước, UI sau). Ảnh hưởng UI cần biết trước khi vẽ lại:

- Màn "Thêm giao dịch": thay vì chọn 1 "category" rồi suy luận income/expense/transfer, nên hỏi **loại giao dịch trước** (Thu / Chi / Chuyển), rồi mới hiện danh mục phù hợp với loại đó — khớp đúng nguyên tắc mục 29 ("UI đơn giản: Thu/Chi/Chuyển/Tiết kiệm").
- "Dùng quỹ" ở màn Thêm giao dịch thực chất là chọn **nguồn tiền** (`source`) khác thay vì `MEMBER_AVAILABLE` mặc định — đổi nhãn cho đúng bản chất, không phải "tích thêm 1 thứ phụ".
- Màn "Danh mục — Chỉnh sửa" cần thêm chọn `type` (Thu/Chi/Chuyển) thay cho segmented Thu/Chi hiện tại; bỏ toggle "Đánh dấu là Tiết kiệm" (không còn cần vì Tiết kiệm không phải Category nữa).
- Card công thức "Tổng thu = Tổng chi + Số tiền còn lại" ở phần Cơ sở dữ liệu cần gỡ bỏ, thay bằng công thức mục 17.

---

## 24. Test Cases (giữ nguyên 9 test đã cho, bổ sung thêm)

Test 1-9 trong yêu cầu giữ nguyên, đều PASS với model V2 (đã kiểm lại từng bước ở mục 6, 8, 9). Bổ sung:

- **Test 10 — Sửa giao dịch đổi amount:** Expense 500k → sửa 800k. Trước: Member X. Sau: Member X − 300k (chỉ phần chênh lệch bị trừ thêm, không trừ lại 800k từ đầu).
- **Test 11 — Sửa giao dịch đổi type:** Expense 500k (Member −500k) → sửa thành Transfer Member→Fund 500k. Sau khi sửa: Member phải cộng lại 500k (revert Expense) rồi trừ lại 500k (apply Transfer) → net Member không đổi, nhưng Fund +500k, Total Assets giảm 500k → tăng lại 500k (vì Expense revert) = không đổi ròng so với "trước khi có giao dịch gốc", đúng vì bản chất cuối cùng là 1 Transfer.
- **Test 12 — Double-submit:** Bấm Lưu 2 lần cùng `clientTxId` → chỉ 1 transaction được tạo.
- **Test 13 — Xoá giao dịch Income:** Income 10 triệu bị xoá → Member Available giảm đúng 10 triệu, Total Assets giảm đúng 10 triệu.
- **Test 14 — Ngân sách không bị Transfer ảnh hưởng:** Budget "Sinh hoạt" = 3 triệu, đã chi (Expense) 2 triệu, sau đó Nạp tiết kiệm (Transfer) 5 triệu → Budget "Sinh hoạt" vẫn báo đã dùng 2/3 triệu, không nhảy lên do Transfer.
- **Test 15 — Rebuild:** Xoá toàn bộ `MEMBER_BALANCE`/`FUND.balance` cache, chạy lại `applyEffect` cho mọi `TRANSACTION` chưa xoá theo đúng thứ tự thời gian → kết quả phải khớp 100% với cache trước khi xoá.

---

## 25. MVP Scope vs Future Scope

| Hạng mục | MVP (Giai đoạn A-D) | Để sau |
|---|---|---|
| 3 loại transaction (Income/Expense/Transfer) | ✅ bắt buộc ngay | — |
| Fund là pool riêng, không double-subtract | ✅ bắt buộc ngay | — |
| Savings là Transfer, không phải Category | ✅ bắt buộc ngay | — |
| Soft delete cho Category/Status/Fund/Member | ✅ | — |
| `amountMinor` + `currency` | ✅ | Hỗ trợ đa tiền tệ thật (USD/EUR) |
| Sửa/xoá qua Financial Engine — reversal ledger đầy đủ (Phương án B) | ✅ đã chốt dùng ngay từ Giai đoạn A | — |
| `version`/`clientTxId` field có sẵn trong schema | ✅ (chỉ thêm field) | Conflict resolution UI thật, offline queue |
| Bảng `ACCOUNT` tổng quát, double-entry ledger thật | ❌ không cần | Khi mở rộng đa loại tài sản/đa tiền tệ phức tạp hơn |
| Gộp 2 category chuyển khoản thành 1 luồng chọn người nhận tự do | Tuỳ chốt ở mục 26 | Nếu không chốt ngay, để khi refactor `roleLabel` tự do (Giai đoạn B) |

---

## 26. Quyết định — trạng thái chốt

| # | Câu hỏi | Trạng thái |
|---|---|---|
| 1 | `MEMBER_AVAILABLE` có được âm không? | ✅ **Đã chốt: không được âm**, giống Fund/Savings (mục 18, Invariant 7) |
| 2 | Chuyển khoản giữa thành viên: 2 category cố định hay 1 luồng chọn người nhận tự do? | ✅ **Đã chốt: Phương án B** — 1 category chung "Chuyển tiền cho thành viên khác" (`type=TRANSFER`), chọn người nhận từ danh sách thành viên mỗi lần ghi |
| 3 | Nạp quỹ/tiết kiệm có cần category riêng để báo cáo? | ✅ **Đã chốt: có** — seed 2 category `type=TRANSFER`: "Nạp quỹ" (dùng chung mọi quỹ) và "Tiết kiệm" (dùng chung mọi `transferKind` tiết kiệm), xem mục 8, 9 |
| 4 | Sửa/xoá giao dịch: soft-delete đơn giản hay reversal ledger đầy đủ? | ✅ **Đã chốt: reversal ledger đầy đủ** (Phương án B) — xem mục 21 |
| 5 | Bỏ công thức cũ, dùng 3 tổng tách biệt? | ✅ **Đã chốt** — xem mục 17 |
| 6 | Status không ảnh hưởng balance? | ✅ **Đã chốt** — xem mục 12 |

### Giải thích lại câu hỏi #2 (chuyển khoản giữa thành viên)

Hiện `docs/design.html` có sẵn 2 category cứng: **"Chồng đưa vợ"** và **"Vợ đưa chồng"**. Mỗi category này tự biết "tiền đi từ ai, đến ai" luôn (vd chọn category "Chồng đưa vợ" thì hệ thống ngầm hiểu người nhận luôn luôn là Vợ).

- **Phương án A — giữ như hiện tại (2 category cố định):** Đơn giản, không đổi UI. Nhưng **chỉ chạy đúng khi gia đình có đúng 2 người**. Nếu sau này gia đình mời thêm người thứ 3 (con đã lớn, ông bà...), muốn "Con chuyển tiền cho Mẹ" thì **phải tạo thêm category mới cho từng cặp người** — 3 người cần tối đa 6 category (Chồng→Vợ, Vợ→Chồng, Chồng→Con, Con→Chồng, Vợ→Con, Con→Vợ), 4 người cần tới 12 category. Không hợp lý.
- **Phương án B — 1 luồng chung "Chuyển tiền cho thành viên khác":** Chỉ có 1 category `type=TRANSFER` duy nhất. Khi tạo giao dịch, người dùng chọn **người nhận** từ danh sách thành viên hiện có trong gia đình (người gửi mặc định là chính người đang ghi giao dịch). Chạy đúng với bất kỳ số lượng thành viên nào, không cần tạo thêm category khi có người mới.

**Đã chốt: Phương án B.** Category "Chồng đưa vợ"/"Vợ đưa chồng" bị loại khỏi seed mặc định, thay bằng 1 category **"Chuyển tiền cho thành viên khác"** (`type=TRANSFER`). Màn Thêm giao dịch khi chọn category này sẽ hiện thêm 1 field chọn **người nhận** (danh sách thành viên hiện có trong gia đình, trừ người đang ghi); người gửi (`sourceRefId`) luôn là người đang thao tác. `transferKind = MEMBER_TO_MEMBER`.

---

**Toàn bộ 6 điểm ở mục 26 đã chốt xong.** Thứ tự tiếp theo: (a) đồng bộ lại `spec.md`/`CLAUDE.md` theo model V2 — đang làm ngay sau tài liệu này; (b) vẽ lại các màn liên quan trong `docs/design.html` (Thêm giao dịch, Danh mục, Quỹ, Tiết kiệm) theo đúng Financial Core mới; (c) mới bắt đầu code Giai đoạn A.
