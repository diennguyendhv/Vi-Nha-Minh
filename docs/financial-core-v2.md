# Financial Core V2 — Audit & Thiết kế lại

**Trạng thái: ĐÃ CODE (Giai đoạn A, phase 1-17) + ĐÃ ĐỒNG BỘ TÀI LIỆU (2026-09-16).** Tài liệu này là kết quả Phase 1-5 (Đọc → Audit → Liệt kê vấn đề → Thiết kế V2 → Financial Core Spec) theo đúng yêu cầu review, và là **source of truth duy nhất** cho business logic tài chính — mọi mâu thuẫn giữa tài liệu này với `spec.md`/`CLAUDE.md`/`docs/design.html` đều được giải quyết bằng cách sửa 3 file kia theo đúng tài liệu này (không giữ song song 2 cách định nghĩa).

**Đã chốt toàn bộ 10 quyết định ở mục 26** (6 quyết định gốc + 4 quyết định bổ sung sau đợt audit trước-khi-code ngày 2026-09-16 — xem `docs/audit-pre-implementation.md`): `MEMBER_AVAILABLE` không được âm (giống Fund/Savings) · nạp quỹ/tiết kiệm có category riêng để lên báo cáo · sửa/xoá giao dịch dùng **reversal ledger đầy đủ** (không dùng soft-delete đơn giản) · công thức tài chính dùng 3 tổng tách biệt · Status không ảnh hưởng balance · chuyển khoản giữa thành viên gộp thành 1 luồng chọn người nhận tự do (bỏ 2 category "Chồng đưa vợ"/"Vợ đưa chồng" cứng) · Fund→Fund và Savings(A)→Savings(B) chưa hỗ trợ trong MVP · giao dịch Transfer cấm source=destination · sửa giao dịch nhiều lần liên tiếp luôn thao tác trên bản mới nhất · hoàn tác 2 lần trên cùng 1 giao dịch bị chặn.

Tài liệu này **thay thế hoàn toàn** phần mô hình tài chính trong `spec.md`/`CLAUDE.md`/`docs/design.html`. Savings model dùng **`SavingsAssetType`** (loại tài sản tự do do gia đình tạo, xem mục 9) làm mô hình chính duy nhất — không còn dùng `MEMBER_SAVINGS_CASH`/`MEMBER_SAVINGS_BANK`/`SAVINGS_TO_BANK` ở bất kỳ đâu trong bộ tài liệu (kể cả các mục khác trong chính file này — xem mục 6, đã sửa lại cho khớp mục 9).

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
| `MEMBER_SAVINGS_ASSET` | `assetTypeId|uid` (ghép chuỗi, xem mục 9) | Số dư của 1 thành viên trong 1 **loại tài sản tiết kiệm tự do do gia đình tạo** (`SavingsAssetType` — Tiền mặt, Ngân hàng, Chứng khoán...; KHÔNG còn 2 kind cố định `MEMBER_SAVINGS_CASH`/`MEMBER_SAVINGS_BANK`) |
| `FUND` | fundId | 1 quỹ cụ thể (Quỹ tiền ăn, Quỹ sinh hoạt...) |
| `EXTERNAL` | — | Bên ngoài hệ thống (lương từ công ty, tiền trả cho người bán...) |

**Không tạo bảng `ACCOUNT` riêng cho MVP** (xem Phương án A/B ở mục 25) — các pool `MEMBER_*` vẫn cache trong `MEMBER_BALANCE`, `FUND` vẫn cache `balance` trên chính `funds/{fundId}`, giống V1. Điểm khác biệt là **cách 1 transaction tham chiếu tới các pool này được chuẩn hoá** (mục 6), nên Financial Engine xử lý bằng 1 hàm chung thay vì nhiều nhánh if/else theo category.

**Total Assets = tổng balance của mọi pool KHÔNG phải `EXTERNAL`.** Vì mỗi đồng tiền chỉ nằm trong đúng 1 pool tại 1 thời điểm, không có double count.

---

## 5. Asset Model

```
Available Money (1 gia đình)  = Σ MEMBER_AVAILABLE của mọi thành viên
Savings Assets (1 gia đình)   = Σ MEMBER_SAVINGS_ASSET của MỌI loại tài sản, MỌI thành viên
                                 (không còn cố định 2 loại — cộng dồn bao nhiêu loại
                                 SavingsAssetType gia đình đã tạo cũng đúng, mục 9)
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
                        "SAVINGS_CONVERT" | "FUND_TOPUP" | "FUND_WITHDRAW"
                        (KHONG con "SAVINGS_TO_BANK" — xem muc 9, thay bang
                        SAVINGS_CONVERT tong quat giua BAT KY 2 loai tai san nao)
  categoryId           FK (nhan, luon co - de bao cao/loc, KHONG quyet dinh dong tien)
  sourceKind           "MEMBER_AVAILABLE" | "MEMBER_SAVINGS_ASSET" | "FUND" | "EXTERNAL"
                        (MEMBER_SAVINGS_ASSET = PoolKind.memberSavingsAsset, muc 9 —
                        1 pool RIÊNG cho tung (SavingsAssetType, thanh vien), KHONG con
                        2 kind co dinh MEMBER_SAVINGS_CASH/MEMBER_SAVINGS_BANK)
  sourceRefId          uid | fundId | "assetTypeId|member" | null (null khi
                        sourceKind = EXTERNAL, tuc INCOME — dinh dang ghep chuoi
                        cho MEMBER_SAVINGS_ASSET xem ham savingsAssetRefId muc 9)
  destinationKind      cung enum voi sourceKind
  destinationRefId     uid | fundId | "assetTypeId|member" | null (null khi
                        destinationKind = EXTERNAL, tuc EXPENSE)
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
| Rút hết quỹ về ví (trước khi xoá quỹ) | TRANSFER (FUND_WITHDRAW) | FUND(quỹ tiền ăn) | MEMBER_AVAILABLE(người nhận) |
| Nạp tiết kiệm 2 triệu (loại "Tiền mặt") | TRANSFER (SAVINGS_TOPUP) | MEMBER_AVAILABLE(X) | MEMBER_SAVINGS_ASSET(Tiền mặt, X) |
| Rút tiết kiệm 500k về ví | TRANSFER (SAVINGS_WITHDRAW) | MEMBER_SAVINGS_ASSET(Tiền mặt, X) | MEMBER_AVAILABLE(X) |
| Chuyển tiết kiệm sang loại khác (vd "Ngân hàng", hoặc bất kỳ loại nào X tự tạo) | TRANSFER (SAVINGS_CONVERT) | MEMBER_SAVINGS_ASSET(Tiền mặt, X) | MEMBER_SAVINGS_ASSET(Ngân hàng, X) |

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
- **Xoá quỹ chỉ được phép khi `balance = 0`.** Không tự ý "xoá và mất tiền" hay ngầm định chuyển tiền cho ai — người dùng phải chủ động **rút hết quỹ** trước bằng 1 giao dịch `TRANSFER(FUND_WITHDRAW)`: `source = FUND` → `destination = MEMBER_AVAILABLE(người nhận, tự chọn)`, y hệt cơ chế `FUND_TOPUP` nhưng đảo chiều. Khi `balance` đã về 0, `deleteFund` chỉ làm soft-delete (`isActive = false`) — không xoá cứng, lịch sử giao dịch cũ vẫn hiển thị đúng tên quỹ. Nút "Xoá quỹ" ở UI phải chặn và giải thích rõ lý do nếu `balance ≠ 0` (xem `docs/design.html` màn 15).

Đối chiếu lại đúng Test 6/7/8 trong yêu cầu:

```
Test 6 — Top up: Member 5 → 3, Fund 0 → 2         (TRANSFER, cả 2 pool đổi, tổng không đổi)
Test 7 — Spend from Fund 500k: Member 3 → 3 (KHÔNG ĐỔI), Fund 2 → 1.5   (EXPENSE, chỉ Fund đổi)
Test 8 — Spend without Fund 500k: Member 3 → 2.5, Fund 2 → 2 (KHÔNG ĐỔI)  (EXPENSE, chỉ Member đổi)
```

---

## 9. Savings Model — cập nhật: loại tài sản tự do, không còn cố định cash/bank

**Đã tổng quát hoá so với bản đầu** (từng cố định đúng 2 pool `MEMBER_SAVINGS_CASH`/`MEMBER_SAVINGS_BANK`) — thực tế gia đình có thể "tiết kiệm" dưới nhiều hình thức khác nhau: tiền mặt, gửi ngân hàng, mua chứng khoán, mua bất động sản... Không hardcode danh sách hình thức, đúng nguyên tắc "dữ liệu, không phải hằng số cứng" đã áp dụng cho Category/Fund.

```
SAVINGS_ASSET_TYPE
  assetTypeId PK, familyId FK, name, color, isActive (soft delete)
```

`SAVINGS_ASSET_TYPE` là dữ liệu gia đình tự tạo — y hệt `FUND` về hình dạng (chỉ id/tên/màu/isActive, không cache balance), khác `FUND` ở chỗ **mỗi loại tài sản là 1 pool RIÊNG cho TỪNG thành viên** (Fund thì dùng chung cả nhà). Pool kind mới `PoolKind.memberSavingsAsset` với `refId` là khoá ghép `"${assetTypeId}|${memberName}"` (hàm `savingsAssetRefId`/`parseSavingsAssetRefId`) — thay hẳn 2 kind cố định `MEMBER_SAVINGS_CASH`/`MEMBER_SAVINGS_BANK` của bản đầu. 2 loại seed mặc định "Tiền mặt"/"Ngân hàng" vẫn được tạo sẵn (giữ đúng trải nghiệm cũ), nhưng giờ chỉ là 2 hàng dữ liệu bình thường — xoá/thêm/sửa qua UI như bất kỳ loại nào khác, xoá được khi mọi thành viên đều về 0 ở loại đó (giống quy tắc Fund mục 8).

Toàn bộ thao tác tiết kiệm vẫn là `TRANSFER`, gắn 1 category riêng **"Tiết kiệm"** (`type = TRANSFER`, seed mặc định, dùng chung cho cả 3 `transferKind` bên dưới — phân biệt bằng `transferKind`, không cần 1 category riêng cho từng loại tài sản):

- **Nạp:** `MEMBER_AVAILABLE(X) -tiền` → `memberSavingsAsset(loại Y, X) +tiền` — `transferKind = SAVINGS_TOPUP`.
- **Rút về ví:** `memberSavingsAsset(loại Y, X) -tiền` → `MEMBER_AVAILABLE(X) +tiền` — `transferKind = SAVINGS_WITHDRAW`.
- **Chuyển đổi loại tài sản** (vd Tiền mặt → Ngân hàng, hoặc Ngân hàng → Chứng khoán): `memberSavingsAsset(loại Y, X) -tiền` → `memberSavingsAsset(loại Z, X) +tiền` — `transferKind = SAVINGS_CONVERT` (thay `SAVINGS_TO_BANK` cố định của bản đầu — giờ chuyển được giữa BẤT KỲ 2 loại nào, không riêng "sang ngân hàng").

Cả 3 đều KHÔNG đổi Total Assets (tiền chỉ đổi pool, không rời hệ thống). Không có màn nhập riêng cho tiết kiệm — cả 3 hành động đều mở lại chính màn Thêm giao dịch (`docs/design.html` màn 09, loại "Chuyển" → "Tiết kiệm", thêm bước chọn loại tài sản), tránh 2 luồng code trùng nhau cho cùng 1 việc. Màn "Tiết kiệm" riêng (Cài đặt → Tiết kiệm) chỉ để xem số dư từng loại theo từng thành viên + tạo/xoá loại tài sản, không nhập giao dịch trực tiếp — giống hệt nguyên tắc màn Quỹ.

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
  statsEnabled (giu nguyen tu V1 — bat/tat hien o man Tong hop trang thai),
  excludeFromTotals (bool, mac dinh false — bo qua khi tinh totalIncome/totalExpense o rollup,
                      van cong/tru availableBalance binh thuong qua applyEffect)
  linkedExpenseCategoryId (categoryId?, chi hop le khi type = INCOME, mac dinh null —
                            tro toi 1 CATEGORY khac co type = EXPENSE, thuan tuy de tinh
                            "Thu nhap rong" hien thi (muc 17), KHONG doi applyEffect/
                            Total Income/Total External Expense)
```

Bỏ hẳn `isSaving` và `transferToUid` khỏi Category (F-04) — 2 field này từng bắt Category "diễn" luôn vai trò của Transaction, sai nguyên tắc ở mục 14 trong yêu cầu. Category giờ **chỉ là nhãn + type để nhóm báo cáo**, không quyết định pool nào bị trừ/cộng.

**`excludeFromTotals` — ví dụ dùng: category seed "Số dư ban đầu"** (`type=INCOME`). Khi mới dùng app, tiền đang có sẵn (không phải kiếm được trong kỳ) vẫn cần 1 giao dịch `INCOME` thật để cộng vào `availableBalance` — nhưng không nên tính vào `totalIncome` hàng tháng vì sẽ làm sai lệch báo cáo thu nhập thật. Cờ này là thuộc tính chung của mọi `CATEGORY` (đúng nguyên tắc "category là dữ liệu"), không hardcode riêng cho "Số dư ban đầu" — gia đình nào cũng tự đánh dấu được cho category tự tạo.

**`linkedExpenseCategoryId` — ví dụ dùng: "Doanh thu" (Thu) liên kết "Chi phí vận hành" (Chi).** Đây là câu trả lời cho mẫu "thu hộ — phải trả lại" (thu tiền về nhưng phải trả 1 phần chi phí thuê ngoài): **vẫn ghi 2 giao dịch riêng biệt** (1 `INCOME` "Doanh thu" + 1 `EXPENSE` "Chi phí vận hành" có `statuses` Chưa gửi/Đã gửi để theo dõi tiến độ trả) — **không dùng số âm trên Income** (vi phạm Invariant 12), và **không gộp Chi vào trong Thu** thành 1 giao dịch (sẽ phá nguyên tắc 1 giao dịch chỉ có 1 `type`/1 cặp source-destination). Field này chỉ làm đúng 1 việc: đánh dấu category Thu "Doanh thu" biết category Chi nào là khoản nó phải trả lại, để UI tính và hiển thị thêm chỉ số **"Thu nhập ròng" = Doanh thu − Chi phí vận hành** (mục 17) — hoàn toàn không đụng tới `applyEffect`, không đổi `Total Income`/`Total External Expense`/`Total Assets`. Optional — chỉ set khi gia đình cần loại báo cáo "thu hộ" này, phần lớn category Thu (Lương, Thu nhập khác...) để `null`.

`STATUS` (subcollection của Category) giữ nguyên như V1: `statusId, categoryId, name, sortOrder` — không đổi.

**Category đã soft-delete (`isActive=false`) vẫn phải chọn được khi SỬA 1 giao dịch cũ đang tham chiếu chính category đó** — chỉ ẩn khỏi danh sách khi TẠO MỚI giao dịch. Nếu không, mở màn "Chi tiết giao dịch" (mục 21) để sửa `note`/`transactionDate`/`statusId` của 1 giao dịch thuộc category đã xoá sẽ không hiển thị đúng lựa chọn `categoryId` hiện tại trong dropdown — không phải lỗi tài chính (không ảnh hưởng balance) nhưng là lỗi UI có thể khiến người dùng vô tình đổi nhầm category khi chỉ định sửa ghi chú. UI phải tự thêm category hiện tại của giao dịch vào danh sách chọn nếu nó không còn `isActive`, đánh dấu rõ "(đã ẩn)".

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
| `SAVINGS_ASSET_TYPE` | 1 "loại" tài sản tiết kiệm gia đình tự đặt (Tiền mặt, Ngân hàng, Chứng khoán...) | assetTypeId PK, familyId FK | `isActive` | xem mục 9 — mỗi loại là 1 pool RIÊNG cho TỪNG thành viên (`PoolKind.memberSavingsAsset`, refId ghép `assetTypeId|member`), khác `FUND` (dùng chung cả nhà). **Đây là mô hình Savings chính thức duy nhất — không còn field `savingsCash`/`savingsBank` cố định ở bất kỳ entity nào.** |
| `TRANSACTION` | **Nguồn sự thật duy nhất** — mọi chuyển động tiền | txId PK, familyId FK | `deletedAt` | xem mục 6, thay thế cả `transactions` và `funds/{id}/entries` của V1 |
| `MEMBER_BALANCE` | Cache số dư `MEMBER_AVAILABLE` của 1 thành viên + map số dư theo từng `SavingsAssetType` | uid PK | không cần (derived) | `availableBalance` (1 field cố định) + `savingsByAssetType: { assetTypeId: amountMinor }` (map động theo số loại tài sản gia đình đã tạo — KHÔNG còn 2 field cố định `savingsCash`/`savingsBank`, xem mục 9) |
| `MONTH_SUMMARY` | Rollup tháng | yearMonth PK, familyId FK | không cần (derived) | xem mục 17 |
| `BUDGET` | Ngân sách | yearMonth PK, familyId FK | không cần | không đổi |

**Index cần có (Firestore composite):**
- `TRANSACTION`: `(familyId, yearMonth, deletedAt)` — liệt kê theo tháng, ẩn transaction đã xoá.
- `TRANSACTION`: `(familyId, sourceKind, sourceRefId)` và `(familyId, destinationKind, destinationRefId)` — tra lịch sử 1 pool (vd 1 quỹ, 1 tài khoản tiết kiệm) mà không phải quét toàn bộ.
- `TRANSACTION`: `(familyId, categoryId, statusId)` — cho màn "Trạng thái — Chi tiết".
- `TRANSACTION`: `clientTxId` unique per family — chặn double-submit (F-12). **Bắt buộc enforce ngay ở tầng local (Giai đoạn A, SQLite/Drift) chứ không đợi tới Firestore/Cloud Function ở Giai đoạn B** — double-submit (bấm Lưu 2 lần) có thể xảy ra ở 1 thiết bị offline y hệt như ở nhiều thiết bị, nên đây là 1 unique constraint DB, không phải business rule riêng của cloud. **Idempotency semantics bắt buộc:** request đầu tiên với 1 `clientTxId` → tạo transaction; request lặp lại **cùng** `clientTxId` → KHÔNG tạo bản ghi mới, trả về/dùng lại đúng transaction đã tạo ở request đầu; 2 giao dịch khác nhau bắt buộc phải có `clientTxId` khác nhau (sinh mới mỗi lần mở form Thêm giao dịch). **[IMPLEMENTATION BLOCKER / TODO]** — `AppDatabase` (Drift) hiện chưa có unique constraint trên cột này, và `LocalTransactionRepository.addTransaction` chưa kiểm tra trùng `clientTxId` trước khi insert; chỉ dựa vào việc UI disable nút Lưu sau khi bấm là KHÔNG đủ (không chặn được double-submit thực sự nếu 2 request race nhau, vd double-tap nhanh hoặc retry sau lỗi mạng ở Giai đoạn B).

**Validation bắt buộc ở Cloud Function** (không chỉ Security Rules — F-13): mọi `categoryId`/`fundId`/`statusId`/`sourceRefId`/`destinationRefId` gửi lên phải thuộc đúng `familyId` của người gọi.

---

## 15. Use Case V2 — điều chỉnh so với 35 use case cũ

**TOTAL USE CASES = 38** (đánh số liên tục U01-U38 trong sơ đồ Mermaid ở `docs/design.html` #usecase, 9 nhóm — xem đối chiếu số đếm ở `docs/final-design-audit.md` mục 5: header từng ghi nhầm "37", đã sửa; đánh số từng có hậu tố chữ cái không theo thứ tự (U16b, U20b, U20c, U23a/b/c) đã đánh số lại tuần tự).

Giữ nguyên phần lớn 9 nhóm. Thay đổi cụ thể:

- **Nhóm "Giao dịch":** đổi "Gắn trạng thái cho giao dịch" → tách rõ 2 use case: *"Chọn loại giao dịch (Thu/Chi/Chuyển)"* và *"Gắn trạng thái tiến độ (không ảnh hưởng số dư)"* — để không ai hiểu nhầm status quyết định tiền.
- Thêm use case **"Sửa giao dịch (tính lại số dư qua Financial Engine)"** và **"Huỷ giao dịch (reversal, không xoá lịch sử)"** — hiện chưa có use case rõ ràng cho việc này dù đã có phase sửa/xoá.
- **Nhóm "Quỹ, tạo được nhiều cái":** đổi "Nạp tiền vào quỹ, tự trừ chi phí người nạp" → *"Nạp tiền vào quỹ (chuyển nội bộ, không phải chi)"*.
- **Nhóm "Tiết kiệm":** thêm *"Tạo loại tài sản tiết kiệm mới"*, *"Nạp/Rút tiết kiệm theo loại tài sản"*, *"Chuyển đổi giữa 2 loại tài sản tiết kiệm"* (KHÔNG còn "chuyển ngân hàng" cố định — bất kỳ 2 loại nào cũng chuyển đổi được, mục 9).
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
Total Income          = Σ amountMinor  (type = INCOME, bo qua category.excludeFromTotals = true)
Total External Expense = Σ amountMinor  (type = EXPENSE)
Total Transfer Volume  = Σ amountMinor  (type = TRANSFER)   // chỉ để hiển thị, KHÔNG cộng vào Income/Expense

Total Assets (cuối kỳ) = Total Assets (đầu kỳ) + Total Income − Total External Expense
                          // Transfer không xuất hiện trong công thức này — tự cân bằng nội bộ

Available Money        = Σ MEMBER_AVAILABLE mọi thành viên
Savings Assets          = Σ memberSavingsAsset mọi loại, mọi thành viên (mục 9 — không còn
                          cố định cash+bank, cộng dồn BẤT KỲ loại tài sản nào đã tạo)
Fund Assets             = Σ FUND.balance

Tỷ lệ tiết kiệm tháng   = (Total Income − Total External Expense) / Total Income
                          // giữ nguyên công thức hành vi tài chính cũ — vẫn đúng vì giờ
                          // "Total External Expense" đã KHÔNG còn lẫn tiết kiệm/chuyển khoản nữa

Thu nhập ròng (1 danh mục Thu có linkedExpenseCategoryId, theo kỳ)
                        = Σ amountMinor (category = danh mục Thu đó)
                          − Σ amountMinor (category = linkedExpenseCategoryId, MỌI status)
                          // trừ luôn cả status "Chưa gửi" vì tiền đã bị trừ khỏi
                          // availableBalance ngay lúc tạo transaction (mục 12) —
                          // status chỉ là nhãn tiến độ, không phải mốc "tiền đã thật sự rời đi"
                          // Chỉ số hiển thị (report-only) — KHÔNG thay Total Income/Total
                          // External Expense/Total Assets ở trên, không cộng dồn liên tháng
                          // Truyền `month` để xem theo từng tháng (vd "doanh thu hàng
                          // tháng"), bỏ trống để tính suốt lịch sử.

Tổng "tiền ra" của 1 thành viên theo hạng mục (`computeMemberOutflowBreakdown`, theo kỳ)
                        = gộp mọi EXPENSE và TRANSFER mà thành viên đó là nguồn
                          (sourceKind=MEMBER_AVAILABLE, sourceRefId=thành viên),
                          nhóm theo categoryId — 1 bảng duy nhất cho Đầu tư/Tự
                          thưởng/CĐ/DH/Tiết kiệm/Nạp quỹ/Chuyển tiền cho thành
                          viên khác, đúng cách sheet gốc liệt kê chung. Không gộp
                          INCOME — dùng riêng `computeMemberIncomeTotal` (Σ INCOME
                          có destinationRefId = thành viên đó).
```

`MONTH_SUMMARY` lưu 3 số `totalIncome / totalExpense / totalTransfer` (thay cho `totalIncome/totalSpending/totalSaving` của V1), cộng `categoryTotals` (mọi type) và `statusTotals` (theo statusId).

**Số dư còn lại (`availableBalance`) là 1 chuỗi liên tục, không có khái niệm "số dư ban đầu của tháng" lưu riêng.** Công thức tương đương tính tay hàng tháng ("số dư ban đầu + doanh thu − chi phí vận hành − chi tiêu − tiết kiệm = số dư hiện tại") **đúng tự động** nhờ cách balance luôn = tổng cộng dồn mọi transaction từ đầu tới nay (Invariant 10) — không cần field `openingBalance` riêng cho mỗi tháng, vì "số dư cuối tháng trước" chính là điểm mà tổng cộng dồn đang dừng ở đó, tự động trở thành điểm bắt đầu của tháng sau khi cộng thêm giao dịch mới. Đây là lý do tách biệt `availableBalance` (không reset) khỏi `MONTH_SUMMARY.totalIncome/totalExpense` (reset mỗi tháng, chỉ để báo cáo).

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
11. Category/Status/Fund/Member "xoá" chỉ soft-delete, transaction cũ vẫn hiển thị đúng — kể cả khi đang SỬA giao dịch cũ đó (mục 11).
12. `amountMinor` luôn dương; dấu suy ra từ `type` + vị trí source/destination.
13. **`reverseTransaction`/`deleteTransaction` phải từ chối nếu giao dịch gốc đã có `reversedByTxId != null`** (đã bị hoàn tác/thay thế trước đó) — chống hoàn tác 2 lần trên cùng 1 giao dịch, vốn sẽ áp dụng hiệu ứng đảo ngược 2 lần vào balance (vì `computeAllPoolBalances` cộng dồn TOÀN BỘ transaction, không lọc). Ném lỗi rõ ràng (`AlreadyReversedException` hoặc tương đương) thay vì âm thầm tạo thêm 1 bản reversal chồng chéo. **[IMPLEMENTATION BLOCKER / TODO]** — chưa có guard này trong `LocalTransactionRepository` hiện tại; bắt buộc thêm trước khi PR tiếp theo đụng tới `reverseTransaction`/`deleteTransaction` được coi là hoàn chỉnh.
14. **Sửa giao dịch (`updateTransaction`) luôn phải thao tác trên bản ghi mới nhất của 1 chuỗi sửa** (`reversedByTxId == null`) — UI không bao giờ được hiển thị nút "Sửa"/"Xoá" trên 1 bản ghi đã có `reversedByTxId != null`, kể cả khi đó là bản gốc của 1 giao dịch đã từng sửa 1 lần. Sửa lần thứ N luôn tạo `correctsTxId` trỏ tới bản thay thế gần nhất (lần N-1), không trỏ ngược về bản gốc ban đầu. **[IMPLEMENTATION BLOCKER / TODO]** — cần xác nhận `transaction_detail_screen.dart` luôn điều hướng theo `txId` mới nhất, chưa audit code UI này.
15. **`TRANSFER` không được có source và destination là cùng 1 pool** (cùng `kind` và cùng `refId`) — chặn ở cả UI (không cho chọn người nhận = người gửi, loại tài sản đích = loại tài sản nguồn) lẫn tầng ghi dữ liệu, để không tạo ra giao dịch "rỗng" vô nghĩa trong lịch sử. **Ví dụ cụ thể cho `SAVINGS_CONVERT`:** nếu loại tài sản nguồn = loại tài sản đích (cùng `assetTypeId`, cùng thành viên) — vd chọn "Tiền mặt → Tiền mặt" — **giao dịch phải bị REJECT ngay lúc submit**, không tạo transaction "chuyển đổi cùng loại" (vô nghĩa về nghiệp vụ, dù không gây sai balance vì tự triệt tiêu). **[IMPLEMENTATION BLOCKER / TODO]** — chưa có validate này trong `LocalTransactionRepository`/UI `add_transaction_sheet.dart`.

---

## 19. Edge Cases

- Xoá 1 category đang có `statsEnabled=true` và đang được lọc ở màn Trạng thái — soft-delete, màn đó phải tự ẩn category đã inactive khỏi bộ lọc mới nhưng vẫn hiện đúng dữ liệu cũ khi xem lịch sử.
- **Sửa transaction đổi hẳn `type` (vd từ EXPENSE sang TRANSFER) — KHÔNG hỗ trợ, đã chốt ở mục 21 và mục 26 quyết định #7.** Đây không phải "chưa làm" mà là **cố tình không cho phép** qua UI: `type`/`transferKind`/`sourceKind`/`destinationKind` là append-only tuyệt đối, `buildCorrection()` không nhận tham số nào để đổi 3 field này. Nhập sai loại giao dịch → xoá (`reverseTransaction`) và ghi lại từ đầu qua màn Thêm giao dịch, không "sửa" nó thành loại khác. (Test 11 ở mục 24 — bản trước của tài liệu này từng mô tả khả năng đổi `type` khi sửa; đã rút khỏi danh sách test bắt buộc vì mâu thuẫn với quyết định này.)
- **Sửa giao dịch đã từng sửa 1 lần (sửa lần thứ 2 trở lên)** — UI/repository phải tìm đúng bản mới nhất (`reversedByTxId == null`) của chuỗi sửa để thao tác tiếp, không thao tác nhầm lên bản gốc đã bị đánh dấu `reversedByTxId` từ lần sửa trước (Invariant 14).
- **Gọi hoàn tác (`reverseTransaction`/`deleteTransaction`) trên 1 giao dịch đã bị hoàn tác/thay thế trước đó** — từ chối theo Invariant 13, không tạo thêm bản reversal chồng chéo.
- **Giao dịch Transfer với source = destination** (vd chọn nhầm người nhận = người gửi, hoặc chuyển đổi loại tài sản tiết kiệm sang chính loại đang có) — chặn theo Invariant 15, không lưu giao dịch rỗng.
- **Fund → Fund** (chuyển thẳng giữa 2 quỹ) và **Savings của thành viên A → Savings của thành viên B** — **chưa hỗ trợ trong MVP** (mục 26 quyết định #7, #8). Muốn làm tương đương thì đi qua các bước đã có sẵn (vd rút quỹ A về ví → nạp vào quỹ B; hoặc rút tiết kiệm A về ví → chuyển cho B → B tự nạp lại tiết kiệm) — không phải bug, là giới hạn phạm vi đã ghi nhận rõ.
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

**Phân biệt rõ 2 loại "xoá" trong app, kẻo nhầm — đây là điểm dễ gây hiểu lầm nhất:**

- **Xoá dữ liệu tham chiếu** (Category, Status, Fund khi `balance=0`, Member) = soft-delete (`isActive=false`) **và không đổi bất kỳ số dư nào**, vì đây chỉ là nhãn/thực thể, không phải bản thân 1 chuyển động tiền.
- **Xoá 1 giao dịch** = **CÓ đổi số dư thật** — đúng mục đích của việc xoá là hoàn tác chính xác hiệu ứng tiền của giao dịch đó (`reverseTransaction`, mục dưới). "Xoá mềm" ở đây chỉ có nghĩa **không xoá mất bản ghi/lịch sử**, không có nghĩa "không đổi số dư". Balance luôn = tổng tất cả giao dịch còn hiệu lực (`reversedByTxId IS NULL`) tính từ đầu tới nay (Invariant 10) — nên xoá 1 giao dịch ở bất kỳ vị trí nào trong chuỗi lịch sử (kể cả giao dịch từ nhiều tháng trước) đều tự động tính lại đúng số dư hiện tại, không cần biết nó nằm ở đâu trong chuỗi.

**Quyết định phạm vi UI — cập nhật, mở lại so với bản thu hẹp trước đó:** màn "Chi tiết giao dịch" cho sửa **toàn bộ**: `categoryId` (chỉ chọn trong cùng `type` Thu/Chi/Chuyển của giao dịch gốc — không đổi `type`), `amountMinor`, `note`, "người tiêu" (`sourceRefId` khi EXPENSE nguồn ví, hoặc `destinationRefId` khi INCOME), `transactionDate`, `statusId`. Vẫn **không sửa được `type`/`transferKind`/`sourceKind`/`destinationKind`** (vd không đổi từ Expense sang Transfer, không đổi nguồn từ Ví sang Quỹ) và với `TRANSFER` thì không sửa được category/người tiêu (2 phía cùng lúc, mơ hồ) — nhập sai loại giao dịch hoặc sai loại chuyển thì vẫn phải **xoá và ghi lại** qua màn Thêm giao dịch. `amountMinor` và "người tiêu" là 2 field ẢNH HƯỞNG BALANCE nên đổi 1 trong 2 sẽ tự động đi qua reversal ledger; `categoryId`/`note`/`transactionDate`/`statusId` không ảnh hưởng balance nên update thẳng, không tạo bản ghi mới — `TransactionRepository.updateTransaction` tự quyết định nhánh nào theo field nào thực sự đổi.

- **`reverseTransaction(txId)`** — Cloud Function tạo 1 transaction mới: `sourceKind`/`sourceRefId` và `destinationKind`/`destinationRefId` **đảo ngược** so với bản gốc, cùng `amountMinor`, `reversalOfTxId = txId`; đồng thời set `reversedByTxId` lên bản gốc. Bản gốc **không bị xoá**, vẫn nằm trong DB với nhãn "đã hoàn tác". `applyEffect` của bản reversal tự động triệt tiêu đúng hiệu ứng cũ vì source/destination đảo chiều. **Bắt buộc từ chối ngay từ đầu nếu `txId` được truyền vào đã có `reversedByTxId != null`** (Invariant 13) — trả lỗi rõ ràng cho UI thay vì tạo thêm 1 bản reversal chồng lên bản reversal cũ.
- **`deleteTransaction(txId)`** (người dùng bấm "Xoá giao dịch") = gọi `reverseTransaction(txId)`. Không có xoá thật ở tầng dữ liệu.
- **`updateTransaction(txId, newFields)`** — nếu `amountMinor`/người tiêu đổi: = `reverseTransaction(txId)` **rồi** `createTransaction(newFields, correctsTxId: txId)`, mang theo luôn mọi field khác cũng đổi cùng lúc (category/note/ngày/status). 1 lần sửa kiểu này tạo ra 3 bản ghi (gốc, hoàn tác, thay thế); UI chỉ hiện bản mới nhất theo mặc định (lọc `reversedByTxId IS NULL`), có thể bấm xem lịch sử sửa để thấy cả chuỗi. **`txId` truyền vào phải luôn là bản mới nhất còn hiệu lực của giao dịch đang sửa** (Invariant 14) — nếu người dùng mở lại 1 giao dịch đã từng sửa trước đó, UI phải điều hướng/thao tác trên bản thay thế mới nhất (`correctsTxId` gần nhất, `reversedByTxId == null`), không bao giờ trên bản gốc ban đầu; sửa lần thứ N tạo `correctsTxId` trỏ tới bản của lần N-1, không trỏ ngược về bản gốc.
- **Field không ảnh hưởng balance** (`note`, `categoryId` khi `type` giữ nguyên, `transactionDate`, `statusId`) được sửa trực tiếp, không cần qua reversal, khi đó không có field nào ảnh hưởng balance đổi.

Đây là lựa chọn có chi phí cao hơn phương án soft-delete đơn giản (nhiều bản ghi hơn, mọi nơi hiển thị danh sách/rollup phải lọc `reversedByTxId IS NULL`) — đổi lại: không ai "sửa mất" lịch sử, đúng tinh thần app tài chính thật, và sẵn sàng cho multi-device/multi-user ở Giai đoạn B mà không phải thiết kế lại lần nữa.

### 21.1 State machine chính thức (hard invariant)

Model này chỉ có **đúng 2 state** cho 1 transaction — **không có state "VOIDED" tách biệt khỏi "REVERSED"**: "xoá" (`deleteTransaction`) và "hoàn tác" (`reverseTransaction`) là **cùng một operation**, dẫn tới cùng một state đích. Đây là quyết định thiết kế có chủ đích (đơn giản hoá, đúng nguyên tắc mục 38 không over-engineering), không phải thiếu sót — nếu sau này cần phân biệt "huỷ vì nhập sai" và "huỷ vì hoàn tiền thật", đó sẽ là 1 field độc lập (vd `voidReason`), không phải 1 state machine mới.

```
ACTIVE    — reversedByTxId == null. Giao dịch đang có hiệu lực, được tính vào
             balance/rollup, hiển thị mặc định trong mọi danh sách.
REVERSED  — reversedByTxId != null. Đã bị hoàn tác/thay thế bởi đúng 1 transaction
             khác. VẪN nằm trong DB (không xoá cứng), vẫn được cộng vào
             computeAllPoolBalances (Invariant 10) — hiệu ứng của nó bị bản
             reversal triệt tiêu, không phải bị loại bỏ khỏi phép tính.
```

**Bảng chuyển trạng thái hợp lệ/không hợp lệ:**

| Từ | Hành động | Đến | Hợp lệ? |
|---|---|---|---|
| ACTIVE | `reverseTransaction` / `deleteTransaction` | REVERSED (bản gốc) + tạo mới 1 bản reversal ở trạng thái ACTIVE | ✅ Hợp lệ — đúng 1 lần |
| ACTIVE | `updateTransaction` (đổi `amountMinor`/người tiêu) | REVERSED (bản gốc) + tạo mới 1 bản reversal (ACTIVE, nội bộ) + 1 bản thay thế (ACTIVE, `correctsTxId`) | ✅ Hợp lệ — đúng 1 lần cho mỗi lần sửa |
| ACTIVE | `updateTransaction` (chỉ đổi field không ảnh hưởng balance: `note`/`categoryId` cùng type/`transactionDate`/`statusId`) | ACTIVE (update thẳng tại chỗ, không sinh bản ghi mới) | ✅ Hợp lệ |
| **REVERSED** | `reverseTransaction` / `deleteTransaction` **lần thứ 2** | — | ❌ **INVALID — bị Invariant 13 từ chối.** Không có "REVERSED → REVERSED". |
| **REVERSED** | `updateTransaction` (sửa amount/người tiêu trên chính bản đã bị đánh dấu `reversedByTxId`) | — | ❌ **INVALID — bị Invariant 14 từ chối.** Phải thao tác trên bản thay thế mới nhất (`correctsTxId` gần nhất, còn ACTIVE), không phải bản gốc. |
| ACTIVE | `UPDATE` trực tiếp `type`/`amountMinor`/`sourceKind`/`destinationKind` không qua `reverseTransaction`/`buildCorrection` | — | ❌ **INVALID — vi phạm Invariant 8 (append-only).** Đây là lỗi nghiêm trọng nhất (F-10) nếu code vô tình mutate thẳng field ảnh hưởng balance. |

Không có transition nào dẫn NGƯỢC từ REVERSED về ACTIVE (không có "un-reverse" / "khôi phục giao dịch đã xoá") — muốn có lại đúng hiệu ứng đó thì tạo 1 giao dịch ACTIVE mới (ghi lại từ đầu qua màn Thêm giao dịch), không phải đảo ngược state của bản REVERSED.

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
- **Test 11 — RÚT KHỎI danh sách bắt buộc (đã chốt lại ở mục 21, quyết định #7 mục 26):** kịch bản "sửa giao dịch đổi hẳn `type`" (vd Expense → Transfer) không còn là 1 use case hợp lệ — `updateTransaction`/`buildCorrection` không nhận tham số đổi `type`/`sourceKind`/`destinationKind`. Không cần Financial Engine hỗ trợ nhánh này; nhập sai loại giao dịch thì hoàn tác (`reverseTransaction`) rồi ghi lại giao dịch mới, tương đương về mặt số học (2 bước hoàn tác + tạo mới cũng cho cùng kết quả) nhưng không đi qua `correctsTxId`.
- **Test 12 — Double-submit:** Bấm Lưu 2 lần cùng `clientTxId` → chỉ 1 transaction được tạo.
- **Test 13 — Xoá giao dịch Income:** Income 10 triệu bị xoá → Member Available giảm đúng 10 triệu, Total Assets giảm đúng 10 triệu.
- **Test 14 — Ngân sách không bị Transfer ảnh hưởng:** Budget "Sinh hoạt" = 3 triệu, đã chi (Expense) 2 triệu, sau đó Nạp tiết kiệm (Transfer) 5 triệu → Budget "Sinh hoạt" vẫn báo đã dùng 2/3 triệu, không nhảy lên do Transfer.
- **Test 15 — Rebuild:** Xoá toàn bộ `MEMBER_BALANCE`/`FUND.balance` cache, chạy lại `applyEffect` cho mọi `TRANSACTION` chưa xoá theo đúng thứ tự thời gian → kết quả phải khớp 100% với cache trước khi xoá.
- **Test 16 — `excludeFromTotals`:** Ghi `INCOME` "Số dư ban đầu" 5.000.000đ (category `excludeFromTotals=true`), rồi ghi `INCOME` "Lương" 10.000.000đ (category thường). `availableBalance` phải tăng đúng 15.000.000đ (cả 2 đều qua `applyEffect`); `months/{yearMonth}.totalIncome` chỉ được tính 10.000.000đ (bỏ qua dòng "Số dư ban đầu").
- **Test 17 — "Thu hộ, phải trả lại":** Ghi `INCOME` "Doanh thu" +2.000.000đ và `EXPENSE` "Chi phí vận hành" (category có `statuses`) −1.000.000đ, status ban đầu "Chưa gửi". `availableBalance` tăng đúng 1.000.000đ ròng; `totalIncome` vẫn ghi nhận đủ 2.000.000đ và `totalExpense` ghi nhận đủ 1.000.000đ (không gộp tắt thành số net); sau khi đổi status sang "Đã gửi", balance không đổi thêm (đúng Invariant 9 — status không đụng Financial Engine).
- **Test 18 — "Thu nhập ròng" (`linkedExpenseCategoryId`):** Category "Doanh thu" (`type=INCOME`) có `linkedExpenseCategoryId` trỏ tới "Chi phí vận hành" (`type=EXPENSE`, `statuses`: Chưa gửi/Đã gửi). Trong tháng ghi: `INCOME` "Doanh thu" 5.000.000đ; `EXPENSE` "Chi phí vận hành" 2.000.000đ status "Chưa gửi" + 1.000.000đ status "Đã gửi". "Thu nhập ròng" hiển thị = 5.000.000 − (2.000.000 + 1.000.000) = 2.000.000đ (cộng cả 2 status, vì tiền đã trừ khỏi `availableBalance` ngay lúc tạo bất kể status). `totalIncome` tháng đó vẫn ghi đủ 5.000.000đ, `totalExpense` vẫn ghi đủ 3.000.000đ — "Thu nhập ròng" chỉ là số hiển thị thêm, không thay 2 tổng này lẫn `Total Assets`.
- **Test 19 — Chặn hoàn tác 2 lần (Invariant 13):** Expense 500k đã bị `reverseTransaction` 1 lần (`reversedByTxId` đã set). Gọi `reverseTransaction` lần thứ 2 trên cùng `txId` gốc → phải bị từ chối (lỗi rõ ràng), không tạo thêm bản reversal thứ 2, balance không đổi thêm.
- **Test 20 — Sửa 2 lần liên tiếp luôn trên bản mới nhất (Invariant 14):** Expense 500k → sửa lần 1 thành 800k (tạo bản thay thế R1, `correctsTxId` trỏ tới bản gốc) → sửa lần 2 thành 900k phải thao tác trên R1 (không phải bản gốc): kết quả `correctsTxId` của bản thay thế R2 = id của R1 (không phải id bản gốc), và balance cuối = -900.000 (không phải tính nhầm từ 500k gốc).
- **Test 21 — Chặn Transfer source = destination (Invariant 15):** Tạo `TRANSFER(SAVINGS_CONVERT)` với loại tài sản nguồn = loại tài sản đích (cùng `assetTypeId`, cùng thành viên) → bị từ chối trước khi ghi; tương tự `MEMBER_TO_MEMBER` với người nhận = người gửi.

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
| `SavingsAssetType` tổng quát hoá (không cố định cash/bank) | ✅ bắt buộc ngay (đã code từ phase 15) | — |
| Chặn hoàn tác 2 lần / sửa nhiều lần luôn trên bản mới nhất (Invariant 13, 14) | ✅ bắt buộc ngay | — |
| Chặn Transfer source=destination (Invariant 15) | ✅ bắt buộc ngay | — |
| Fund → Fund (chuyển thẳng giữa 2 quỹ) | ❌ không cần | Nếu có nhu cầu thật, thêm 1 `transferKind` mới — engine không cần đổi (mục 7) |
| Savings của thành viên A → Savings của thành viên B trực tiếp | ❌ không cần | Đi qua rút + chuyển member-to-member + nạp lại (3 bước) là đủ cho MVP |

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
| 7 | Fund → Fund và Savings(A) → Savings(B) trực tiếp có cần trong MVP không? | ✅ **Đã chốt — phân loại chính thức: `NOT SUPPORTED` (không phải `DEFERRED`)** cho cả 2, xem mục 26.1 dưới đây để phân biệt lý do và cách đi vòng. |
| 8 | Giao dịch Transfer có được phép source = destination không? | ✅ **Đã chốt: không** — chặn ở cả UI lẫn tầng ghi dữ liệu (Invariant 15). |
| 9 | Sửa 1 giao dịch đã từng sửa trước đó (sửa lần 2 trở lên) thao tác trên bản nào? | ✅ **Đã chốt: luôn trên bản mới nhất còn hiệu lực** (`reversedByTxId == null`), không bao giờ trên bản gốc ban đầu (Invariant 14). |
| 10 | Có cho phép hoàn tác (`reverseTransaction`) 2 lần trên cùng 1 giao dịch không? | ✅ **Đã chốt: không** — từ chối nếu đã có `reversedByTxId != null` (Invariant 13). |

### Giải thích lại câu hỏi #2 (chuyển khoản giữa thành viên)

Hiện `docs/design.html` có sẵn 2 category cứng: **"Chồng đưa vợ"** và **"Vợ đưa chồng"**. Mỗi category này tự biết "tiền đi từ ai, đến ai" luôn (vd chọn category "Chồng đưa vợ" thì hệ thống ngầm hiểu người nhận luôn luôn là Vợ).

- **Phương án A — giữ như hiện tại (2 category cố định):** Đơn giản, không đổi UI. Nhưng **chỉ chạy đúng khi gia đình có đúng 2 người**. Nếu sau này gia đình mời thêm người thứ 3 (con đã lớn, ông bà...), muốn "Con chuyển tiền cho Mẹ" thì **phải tạo thêm category mới cho từng cặp người** — 3 người cần tối đa 6 category (Chồng→Vợ, Vợ→Chồng, Chồng→Con, Con→Chồng, Vợ→Con, Con→Vợ), 4 người cần tới 12 category. Không hợp lý.
- **Phương án B — 1 luồng chung "Chuyển tiền cho thành viên khác":** Chỉ có 1 category `type=TRANSFER` duy nhất. Khi tạo giao dịch, người dùng chọn **người nhận** từ danh sách thành viên hiện có trong gia đình (người gửi mặc định là chính người đang ghi giao dịch). Chạy đúng với bất kỳ số lượng thành viên nào, không cần tạo thêm category khi có người mới.

**Đã chốt: Phương án B.** Category "Chồng đưa vợ"/"Vợ đưa chồng" bị loại khỏi seed mặc định, thay bằng 1 category **"Chuyển tiền cho thành viên khác"** (`type=TRANSFER`). Màn Thêm giao dịch khi chọn category này sẽ hiện thêm 1 field chọn **người nhận** (danh sách thành viên hiện có trong gia đình, trừ người đang ghi); người gửi (`sourceRefId`) luôn là người đang thao tác. `transferKind = MEMBER_TO_MEMBER`.

### 26.1 Open Business Decisions — phân loại chính thức

Mỗi quyết định phạm vi dưới đây dùng đúng 1 trong 3 nhãn: **`SUPPORTED`** (có trong MVP), **`NOT SUPPORTED`** (cố tình không làm, không có kế hoạch trừ khi có lý do business mới), **`DEFERRED`** (sẽ làm, chỉ chưa phải bây giờ).

| Kịch bản | Phân loại | Lý do business |
|---|---|---|
| `MEMBER_TO_MEMBER` — chuyển `MEMBER_AVAILABLE` giữa 2 thành viên | `SUPPORTED` | Nhu cầu gốc từ sheet thật (Chồng đưa vợ tiền chợ), dùng hàng ngày — xem mục 7, quyết định #2. |
| `FUND_TOPUP`/`FUND_WITHDRAW` — nạp/rút 1 quỹ | `SUPPORTED` | Envelope budgeting là tính năng lõi — mục 8. |
| `SAVINGS_TOPUP`/`SAVINGS_WITHDRAW`/`SAVINGS_CONVERT` — trong phạm vi tài sản của **CÙNG 1 thành viên** | `SUPPORTED` | Mục 9 — nhu cầu gốc "tiết kiệm hiện tại"/"gửi ngân hàng" của sheet thật, tổng quát hoá thêm loại tài sản. |
| **Fund → Fund** (chuyển thẳng số dư giữa 2 quỹ, không qua ví thành viên) | `NOT SUPPORTED` | Không có nhu cầu thật nào trong sheet gốc; đi qua `FUND_WITHDRAW` (Fund → ví) rồi `FUND_TOPUP` (ví → Fund khác) cho đúng kết quả, chỉ tốn thêm 1 bước UI. Thêm thẳng sẽ cần 1 `transferKind` mới (`FUND_TO_FUND`) — không phức tạp về engine (mục 7) nhưng chưa có lý do business để ưu tiên. |
| **Savings(thành viên A) → Savings(thành viên B)** — chuyển trực tiếp tài sản tiết kiệm của người này sang người kia, KHÔNG qua `MEMBER_AVAILABLE` | `NOT SUPPORTED` | **Khác hẳn `MEMBER_TO_MEMBER`** — đây là 2 pool `MEMBER_SAVINGS_ASSET` của 2 `refId` khác nhau (khoá ghép `assetTypeId|A` và `assetTypeId|B`), không phải cùng 1 loại chuyển như tiền ví. Không có nhu cầu thật (sheet gốc tính tiết kiệm riêng biệt theo từng người, không có khái niệm "cho tiết kiệm"); đi qua đường vòng đã có: A rút tiết kiệm về ví (`SAVINGS_WITHDRAW`) → A chuyển ví cho B (`MEMBER_TO_MEMBER`) → B tự nạp lại tiết kiệm (`SAVINGS_TOPUP`) — 3 giao dịch riêng biệt, đúng minh bạch dòng tiền hơn 1 giao dịch "ẩn" gộp 3 bước làm 1. |
| `SAVINGS_CONVERT` với loại tài sản nguồn = loại tài sản đích | `NOT SUPPORTED` (reject) | Vô nghĩa về nghiệp vụ — Invariant 15. |

---

**Toàn bộ 10 điểm ở mục 26 đã chốt xong.** `spec.md`, `CLAUDE.md`, `docs/design.html` (ERD + sơ đồ use case + caption màn hình) đã được đồng bộ lại theo đúng tài liệu này ở đợt sửa ngày 2026-09-16 (xem `docs/audit-pre-implementation.md` cho danh sách đầy đủ các mâu thuẫn đã tìm thấy và sửa). Việc còn lại (thuộc phạm vi CODE, không phải tài liệu — chưa làm trong đợt sửa này): thêm unique constraint `clientTxId` ở `AppDatabase` (Drift), thêm guard chặn hoàn tác 2 lần (Invariant 13) và validate source≠destination (Invariant 15) vào `LocalTransactionRepository`, xác nhận `transaction_detail_screen.dart` luôn thao tác trên bản mới nhất (Invariant 14).

---

## 27. Bảng quyết định Edge Case (INPUT / EXPECTED / ACCEPT-REJECT / REASON)

| Edge case | Input | Expected behavior | Accept/Reject | Reason |
|---|---|---|---|---|
| `amount = 0` | `amountMinor = 0` | Không tạo transaction | **REJECT** | Invariant 12 (`amountMinor > 0`) — hiện chỉ enforce qua `assert()` (bị strip ở release build) + UI guard (`_buildTransaction` trả null); **chưa có validate ở tầng repository — GAP, không phải OPEN DECISION** (quyết định đã rõ, chỉ thiếu chỗ enforce). |
| `amount` âm | `amountMinor = -50000` | Không tạo transaction | **REJECT** | Cùng Invariant 12. Không có khái niệm "expense âm nghĩa là hoàn tiền" — muốn hoàn tiền thì dùng `reverseTransaction`. |
| `amount` rất lớn | `amountMinor = 999999999999` | Tạo bình thường nếu không làm pool nguồn âm | **ACCEPT** | Không có trần nghiệp vụ; giới hạn kỹ thuật duy nhất là kiểu dữ liệu (Dart `int` 64-bit, dư sức). |
| Transaction duplicate (double submit) | 2 request cùng `clientTxId` | Chỉ 1 transaction tồn tại | **REJECT** (request thứ 2) | Invariant mới ở mục 14 (idempotency) — `[IMPLEMENTATION BLOCKER / TODO]`, xem mục 14. |
| Sửa giao dịch (lần 1) | `updateTransaction(txId=A, amount mới)` | Tạo reversal + replacement, A chuyển REVERSED | **ACCEPT** | Mục 21, đã có test (Test 10). |
| Sửa giao dịch lặp lại (lần 2 trên bản gốc A, không phải bản thay thế) | `updateTransaction(txId=A, ...)` khi A đã REVERSED | Từ chối, yêu cầu thao tác trên bản thay thế mới nhất | **REJECT** | Invariant 14 — `[IMPLEMENTATION BLOCKER / TODO]`. |
| Hoàn tác lặp lại (`reverseTransaction` lần 2 trên cùng txId) | `reverseTransaction(txId=A)` khi A đã REVERSED | Từ chối | **REJECT** | Invariant 13 — `[IMPLEMENTATION BLOCKER / TODO]`. |
| Xoá giao dịch (`deleteTransaction`) | `deleteTransaction(txId=A)`, A đang ACTIVE | = `reverseTransaction(A)` | **ACCEPT** | Mục 21. |
| `clientTxId` trùng cho 2 giao dịch KHÁC NHAU (lỗi client sinh id không đúng) | 2 giao dịch nội dung khác, cùng `clientTxId` | Giao dịch thứ 2 bị coi là "lặp lại của thứ nhất", KHÔNG được tạo | **REJECT** (giao dịch thứ 2, đúng theo thiết kế idempotency) | Đây là lỗi ở phía sinh `clientTxId` (phải là ngẫu nhiên/UUID mỗi lần mở form), không phải lỗi hệ thống — ghi rõ để dev không nhầm là "bug mất giao dịch". |
| Cùng 1 giao dịch bấm Lưu 2 lần liên tiếp (double-tap) | Cùng nội dung, cùng `clientTxId` (sinh 1 lần khi mở form) | Chỉ 1 transaction | **ACCEPT** (idempotent — coi là 1 request) | Mục 14. |
| Category bị xoá sau khi đã có giao dịch tham chiếu | `categoryId` của giao dịch cũ có `isActive=false` | Giao dịch cũ vẫn hiển thị đúng tên/màu category; dropdown sửa giao dịch vẫn chọn được category đó (đánh dấu "đã ẩn") | **ACCEPT** | Mục 11, Invariant 11. |
| Thành viên bị "disable" | — | Chưa có khái niệm này ở Giai đoạn A (chỉ 2 thành viên cố định `vo`/`chong`) | **N/A — ngoài phạm vi Giai đoạn A** | Chờ refactor `roleLabel` tự do + `isActive` trên Member ở Giai đoạn B (`spec.md` phase 24). |
| Fund bị archive (soft-delete) khi `balance ≠ 0` | Bấm "Xoá quỹ" khi còn số dư | Chặn, yêu cầu rút hết trước | **REJECT** | Mục 8. |
| Fund bị archive khi `balance = 0` | Bấm "Xoá quỹ" khi số dư = 0 | Soft-delete (`isActive=false`) | **ACCEPT** | Mục 8. |
| Savings asset type bị archive khi còn số dư ở bất kỳ thành viên nào | Bấm xoá loại tài sản | Chặn | **REJECT** | Mục 9, cùng nguyên tắc Fund. |
| Savings asset type bị archive khi mọi thành viên = 0 | Bấm xoá loại tài sản | Soft-delete | **ACCEPT** | Mục 9. |
| Đổi `transactionDate` của giao dịch cũ | `updateTransaction(txId, transactionDate mới)` | Update thẳng, không qua reversal, giao dịch chuyển sang rollup tháng khác | **ACCEPT** | Mục 21 — field này không ảnh hưởng balance. |
| Offline retry (Giai đoạn B, mất mạng giữa lúc gửi) | Client gửi lại đúng request cũ (cùng `clientTxId`) khi có mạng lại | Không tạo trùng | **ACCEPT** (idempotent) | Mục 14, mục 22. |
| Transfer source = destination (mọi loại) | `MEMBER_TO_MEMBER` người nhận = người gửi, hoặc `SAVINGS_CONVERT` cùng loại tài sản | Từ chối | **REJECT** | Invariant 15 — `[IMPLEMENTATION BLOCKER / TODO]`. |
