# Đặc tả sản phẩm & Lộ trình phát triển
## Ứng dụng Quản lý Chi tiêu Cá nhân/Gia đình — phát hành trên CH Play (Google Play)

Tài liệu này được viết với hai vai trò: **chuyên gia tài chính cá nhân** (thiết kế mô hình dữ liệu và chỉ số sao cho app thực sự giúp kiểm soát dòng tiền, không chỉ ghi chép) và **chuyên gia lập trình Android/Flutter** (thiết kế kiến trúc, kế hoạch kỹ thuật và phát hành sao cho khả thi, bảo trì được lâu dài).

Nguồn gốc: file Google Sheets "Quản lý tài chính 2026" hiện tại, gồm trang **Ghi chép** (nhật ký giao dịch: STT, Hạng mục, Thành tiền, Chi tiết, Người tiêu, Ngày tháng, Trạng thái) và trang **Tổng hợp**. Quyết định kỹ thuật đã chốt: **Flutter**, **Firebase (đồng bộ realtime)**, mô hình **Freemium**, triển khai theo **MVP gọn nhẹ trước, mở rộng dần**.

---

## Nhận định của chuyên gia tài chính trước khi thiết kế

Sổ hiện tại của bạn ghi rất tốt phần **chi tiêu** (Sinh hoạt, Dâng hiến, Cho đi, Tự thưởng...), nhưng để app thực sự là công cụ *quản lý tài chính* chứ không chỉ sổ chép tay số hoá, cần bổ sung ba điều mà một sổ chi tiêu đơn thuần thường thiếu:

1. **Ghi nhận cả thu nhập** (lương, thu nhập freelance, thu nhập khác...), không chỉ chi tiêu — nếu không có vế thu, app không thể tính được số dư thực tế hay tỷ lệ tiết kiệm, chỉ có thể cộng dồn chi tiêu như sheet hiện tại đang làm.
2. **Tỷ lệ theo thu nhập, không chỉ số tuyệt đối** — ví dụ tỷ lệ Dâng hiến/Cho đi trên tổng thu, tỷ lệ tiết kiệm (Thu − Chi)/Thu mỗi tháng. Đây là chỉ số có ý nghĩa hành vi hơn nhiều so với việc chỉ nhìn tổng số tiền đã tiêu.
3. **Ngân sách theo hạng mục** (bạn định chi bao nhiêu cho Sinh hoạt/tháng) đối chiếu với thực chi, để phát hiện lệch sớm thay vì cuối tháng mới biết đã vượt.

Ba điểm này được đưa vào làm một phần bắt buộc trong thiết kế mô hình dữ liệu ngay từ Phase 1, để không phải làm lại (migration dữ liệu) khi thêm sau này.

---

## Kiến trúc kỹ thuật tổng thể

**Frontend:** Flutter/Dart, Riverpod cho state management, `go_router` cho điều hướng, kiến trúc 3 lớp `presentation / domain / data` (chi tiết xem `CLAUDE.md`).

**Backend:** Firebase Authentication, Cloud Firestore, Cloud Functions, Cloud Messaging, Firebase Storage.

**Mô hình dữ liệu Firestore (đối chiếu trực tiếp với sheet "Quản lý tài chính 2026" thật — trang Ghi chép + Tổng hợp). Bản vẽ đầy đủ (sơ đồ use case, ERD, 18 màn hình mô phỏng) đã chốt tại [`docs/design.html`](docs/design.html) — phần dưới đây là bản tóm tắt kỹ thuật khớp với file đó, mọi thay đổi schema về sau phải cập nhật đồng thời cả hai nơi.**

**Mô hình tài chính V2 (thay thế hoàn toàn bản nháp Thu/Chi ban đầu) — chi tiết đầy đủ + lý do + test case ở [`docs/financial-core-v2.md`](docs/financial-core-v2.md), đọc file đó trước khi code Financial Engine.**

**3 loại giao dịch, không phải 2:** `INCOME` (tiền từ bên ngoài vào), `EXPENSE` (tiền rời khỏi gia đình thật sự), `TRANSFER` (tiền chỉ đổi chỗ giữa 2 "pool" trong cùng hệ thống — không làm Tổng tài sản đổi). Bản nháp đầu từng gộp Tiết kiệm/Quỹ/Chuyển khoản nội bộ vào chung "Chi" — **sai**, vì tài sản gia đình không hề giảm khi vợ chồng chuyển tiền cho nhau hay nạp tiền vào quỹ/tiết kiệm; gộp vào Chi làm phình Tổng chi giả tạo. Mỗi giao dịch có `sourceKind`/`sourceRefId` (tiền lấy từ đâu) và `destinationKind`/`destinationRefId` (tiền tới đâu) — 1 trong 2 đầu là `EXTERNAL` thì đó là Thu hoặc Chi; cả 2 đầu đều ở trong hệ thống thì đó là Transfer. `Category` chỉ còn là **nhãn để nhóm báo cáo**, không quyết định tiền chạy đi đâu.

Danh sách hạng mục seed mặc định (Phase 1, đúng theo dropdown thật trong sheet, đã bỏ 2 hạng mục "Chồng đưa vợ"/"Vợ đưa chồng" cứng — xem lý do ở `docs/financial-core-v2.md` mục 26):

| id | Tên hiển thị | `type` | Có `statuses`? |
|---|---|---|---|
| `thu_nhap` | Thu nhập | INCOME | không |
| `sinh_hoat` | Sinh hoạt | EXPENSE | tự thêm được (không mặc định) |
| `dau_tu` | Đầu tư | EXPENSE | không |
| `tu_thuong` | Tự thưởng | EXPENSE | không |
| `cho_di` | Cho đi | EXPENSE | **có, 3 bước mặc định** |
| `dang_hien` | Dâng hiến | EXPENSE | **có, 3 bước mặc định** |
| `chuyen_tien_thanh_vien` | Chuyển tiền cho thành viên khác | TRANSFER | không — khi chọn, UI hỏi thêm **người nhận** (danh sách thành viên), chạy đúng với bất kỳ số thành viên nào, không cần 1 category riêng cho từng cặp người |
| `nap_quy` | Nạp quỹ | TRANSFER | không — dùng chung cho mọi quỹ, xem `fund` bên dưới |
| `tiet_kiem` | Tiết kiệm | TRANSFER | không — dùng chung cho cả nạp/rút/gửi ngân hàng, phân biệt bằng `transferKind` |

Cách 1 giao dịch ảnh hưởng số dư — **1 hàm Financial Engine duy nhất cho mọi loại**: nếu `sourceKind ≠ EXTERNAL` thì trừ `amountMinor` khỏi pool nguồn; nếu `destinationKind ≠ EXTERNAL` thì cộng `amountMinor` vào pool đích. Không có nhánh if/else riêng theo category — xem code mẫu ở `docs/financial-core-v2.md` mục 6.

**Trạng thái (`statuses`) là bảng con CRUD được, áp dụng cho mọi danh mục, không riêng Cho đi/Dâng hiến:** `families/{familyId}/categories/{categoryId}/statuses/{statusId}` gồm `name` (tự đặt) và `sortOrder` (tự sắp xếp) — thay cho mảng cứng `statuses: string[]` ở bản nháp đầu, để người dùng xem/thêm/sửa/xoá/sắp xếp từng bước qua UI (màn "Danh mục — Chỉnh sửa"). Giao dịch tham chiếu `statusId` (không phải chuỗi tự do), sửa được sau khi tạo (`statusUpdatedAt` ghi lại lần đổi gần nhất) — ví dụ Dâng hiến hôm nay "Chưa chuẩn bị", mai đổi "Đã chuẩn bị", không cố định lúc ghi.

**`statsEnabled` (bool) trên từng `category`:** bật/tắt việc danh mục đó có hiện ở màn Tổng hợp trạng thái hay không. Nhiều danh mục có `statuses` nhưng người dùng chỉ cần xem tổng hợp 1-2 lần/tháng cho một số danh mục nhất định (vd Cho đi, Dâng hiến) — tắt cho danh mục không cần theo dõi thường xuyên để đỡ rối màn Tổng hợp.

**Tài khoản theo từng thành viên (riêng biệt, không gộp chung)** — đây là điểm khác biệt lớn nhất so với mô hình "một quỹ chung" ban đầu: sheet thật tính **Số dư** và **Tiết kiệm** riêng cho Vợ và cho Chồng (cột `K`/`N` "Tổng hợp"), dựa vào cột "Người tiêu" của từng giao dịch. App giữ đúng cơ chế này cho MỌI thành viên, không riêng Vợ/Chồng.

**Tiết kiệm chia 2 loại con (yêu cầu mới, sheet hiện chưa có — cần bổ sung khi lên app):** mỗi tài khoản tiết kiệm tách thành **tiết kiệm hiện tại** (tiền mặt/chưa gửi) và **tiết kiệm đã gửi ngân hàng**, để biết chính xác bao nhiêu đang nằm ở đâu.

**Cá nhân hay Gia đình — không phải hai schema khác nhau, mà là cùng một mô hình.** "Cá nhân" thực chất là một `families/{familyId}` chỉ có 1 thành viên (`accountType: "personal"`); mời thêm người vào là chuyển tự nhiên sang gia đình, không cần màn hình "nâng cấp" riêng. **Vai trò (`roleLabel`) là chuỗi tự do do chính gia đình đặt** (Vợ/Chồng/Bố/Mẹ/Con/bất kỳ) — đúng nguyên tắc "dữ liệu, không hardcode" đã áp dụng cho hạng mục và trạng thái (xem `CLAUDE.md` mục 9); code Flutter hiện tại (Phase 1, dựng cho vợ chồng chủ dự án) đang dùng enum cứng `FamilyMember{vo, chong}` — việc thay bằng model vai trò tự do là một đợt refactor riêng, đã đưa vào Giai đoạn B bên dưới (làm cùng lúc với phần mời/tham gia thật), **chưa làm ngay** để tránh phá vỡ bản demo hiện tại.

**Mời qua mã hoặc đường link:** mỗi lời mời có mã ngẫu nhiên 6-8 ký tự (đủ khó đoán để không ai lẻn vào gia đình người khác), **có hạn dùng** (mặc định 7 ngày) và giới hạn số lần dùng. Link mời dùng **Android App Links** — không dùng Firebase Dynamic Links vì Google đã thông báo ngừng dịch vụ này, thiết kế đúng từ đầu để khỏi phải làm lại.

**Local-first: mặc định lưu trên máy, chỉ lên Firestore khi thật sự có người thứ 2 tham gia.** Firestore chỉ thật sự cần thiết để đồng bộ realtime giữa nhiều thiết bị — nếu chỉ 1 người dùng (kể cả đã chọn "Gia đình" lúc onboarding nhưng chưa mời ai), không có lý do gì phải trả phí/độ trễ mạng cho việc đó. Vì vậy:

- Mọi tài khoản mới **luôn bắt đầu ở `syncMode: "local"`** — dữ liệu lưu bằng database cục bộ trên máy (SQLite/Hive qua `drift`/`hive`), không cần đăng nhập, không cần mạng, không đụng tới Firebase.
- `families/{familyId}` trên Firestore **chỉ thật sự được tạo tại thời điểm lời mời đầu tiên được người khác chấp nhận.** Trước đó, "gia đình" chỉ tồn tại cục bộ trên máy người tạo.
- Khi người thứ 2 chấp nhận lời mời: toàn bộ dữ liệu local (giao dịch, Quỹ) được **migrate lên Firestore** đúng schema bên dưới, `syncMode` đổi thành `"cloud"`, và từ đó app dùng `FirestoreTransactionRepository` thay vì repository local — cả 2 máy đọc chung 1 nguồn.
- `TransactionRepository`/`FundRepository` là interface trừu tượng (đã thiết kế theo Clean Architecture ngay từ đầu) nên việc có 2 cách triển khai song song (local/cloud) không phá vỡ `domain/` hay `presentation/` — chỉ đổi implementation nào được inject lúc runtime dựa vào `syncMode`.

```
families/{familyId}
  name, accountType ("personal" | "family"), syncMode ("local" | "cloud"),
  ownerUid, createdAt, memberIds: [uid1, uid2, ...]

families/{familyId}/members/{uid}
  displayName, roleLabel (chuỗi tự do, gia đình tự đặt), joinedAt, isOwner, isActive (soft delete)

families/{familyId}/invites/{inviteId}
  code (6-8 ký tự ngẫu nhiên), suggestedRoleLabel,
  createdBy, createdAt, expiresAt, maxUses, usedCount

families/{familyId}/categories/{categoryId}
  name, color, type ("INCOME" | "EXPENSE" | "TRANSFER"),
  statsEnabled (bool, hien o Tong hop trang thai),
  isDefault, isActive (soft delete)

families/{familyId}/categories/{categoryId}/statuses/{statusId}
  name (tu dat), sortOrder (int), isActive (soft delete)

families/{familyId}/funds/{fundId}
  name, color, isActive (soft delete),
  balance   // derived, cache boi Cloud Function

families/{familyId}/transactions/{txId}
  type ("INCOME" | "EXPENSE" | "TRANSFER")
  transferKind (null tru khi type=TRANSFER: "MEMBER_TO_MEMBER" | "FUND_TOPUP" |
                "SAVINGS_TOPUP" | "SAVINGS_WITHDRAW" | "SAVINGS_TO_BANK")
  categoryId, statusId (FK, null neu danh muc khong co statuses), statusUpdatedAt,
  sourceKind / sourceRefId          ("MEMBER_AVAILABLE"|"MEMBER_SAVINGS_CASH"|
                                      "MEMBER_SAVINGS_BANK"|"FUND"|"EXTERNAL", + uid/fundId)
  destinationKind / destinationRefId (cung enum voi sourceKind)
  amountMinor (int, luon duong), currency ("VND"),
  note, transactionDate (ngay nghiep vu), spenderUid,
  createdAt, createdBy, clientTxId (chong double-submit), version,
  reversalOfTxId / correctsTxId / reversedByTxId (null neu con hieu luc — xem Financial Engine)

families/{familyId}/memberBalances/{uid}
  availableBalance,      // Tien co the chi cua nguoi nay (khong duoc am)
  savingsCash,           // Tiet kiem hien tai, chua gui ngan hang (khong duoc am)
  savingsBank            // Tiet kiem da gui ngan hang (khong duoc am)

families/{familyId}/budgets/{yearMonth}
  categoryLimits: { categoryId: amountMinor }   // chi cong don giao dich type=EXPENSE
```

`memberBalances`/`funds/{id}.balance` là số liệu dẫn xuất (derived) — tính lại từ toàn bộ `transactions` chưa bị `reversedByTxId`; cache bằng Cloud Function cập nhật mỗi khi có giao dịch mới, phải luôn rebuild lại được 100% từ `transactions` gốc (tham khảo số dòng thật trong sheet: hơn 1700 dòng chỉ riêng 8 tháng đầu năm).

**Công thức tài chính (3 tổng tách biệt — thay hẳn công thức "Tổng thu = Tổng chi + Tiết kiệm" ở bản nháp đầu, vốn tự mâu thuẫn vì gộp cả Transfer vào Chi):**

```
Total Income          = Σ amountMinor (type = INCOME)
Total External Expense = Σ amountMinor (type = EXPENSE)
Total Transfer Volume  = Σ amountMinor (type = TRANSFER)   // chỉ để hiển thị dòng tiền, KHÔNG cộng vào Thu/Chi

Tổng tài sản (cuối kỳ) = Tổng tài sản (đầu kỳ) + Total Income − Total External Expense
                          // Transfer tự cân bằng nội bộ, không xuất hiện trong công thức này

Tỷ lệ tiết kiệm tháng = (Total Income − Total External Expense) / Total Income
```

Vì `Total External Expense` giờ không còn lẫn Tiết kiệm/Quỹ/chuyển khoản nội bộ, công thức luôn đúng bằng cộng dồn số học đơn giản — không cần nhánh logic riêng cho tiết kiệm ở bất kỳ use case tổng hợp nào trong `domain/`.

**Chia dữ liệu theo tháng + bảng tổng hợp tính sẵn — quyết định kiến trúc quan trọng cho việc mở rộng nhiều người dùng, nhiều năm:**

Một collection `transactions` phẳng, cộng dồn mãi mãi, có hai vấn đề khi scale: (1) mỗi lần mở app phải nghe realtime toàn bộ lịch sử để tính lại số dư/báo cáo — càng dùng lâu càng chậm và càng tốn phí đọc; (2) không có ranh giới tự nhiên để phân trang theo tháng/năm như cách người dùng thực sự xem dữ liệu (sheet thật cũng tự chia theo "Tháng 1"…"Tháng 9"). Giải pháp:

```
families/{familyId}/months/{yearMonth}              // yearMonth dạng "2026-09"
  totalIncome,           // Sigma type=INCOME
  totalExpense,          // Sigma type=EXPENSE (KHONG con lan Tiet kiem/Quy/chuyen khoan)
  totalTransfer,         // Sigma type=TRANSFER, chi de hien thi dong tien, khong cong vao Thu/Chi
  categoryTotals: { categoryId: amount },
  memberTotals: { uid: { income, expense } },
  statusTotals: { statusId: amount, ... }   // khoa theo statusId thuc te cua tung category, khong hardcode ten buoc

families/{familyId}/months/{yearMonth}/transactions/{txId}
  // giong het shape families/{familyId}/transactions/{txId} o tren, chi khac vi tri luu
  // (phan trang theo thang de realtime listener luon nho, xem giai thich ben duoi)
```

- **Realtime listener chỉ mở cho tháng đang xem** (`months/{currentYearMonth}/transactions`) — dữ liệu luôn nhỏ và nhanh dù sổ đã dùng 5 năm, vì tháng cũ không còn bị "nghe" nữa.
- **`months/{yearMonth}` là document tổng hợp tính sẵn** (giống hệt các con số trong sheet Tổng hợp — Thu nhập, Sinh hoạt, Đầu tư... theo %, và khối Chưa chuẩn bị/Đã chuẩn bị/Đã dâng/Đã gửi), cập nhật bằng Cloud Function `onWrite` trên `transactions` dùng `FieldValue.increment()`. Mở màn hình Tổng hợp chỉ cần đọc **1 document** thay vì cộng hàng trăm/nghìn giao dịch ở client.
- **Xem theo năm** = cộng 12 document `months/{yearMonth}` (12 lần đọc, rẻ) thay vì đọc lại toàn bộ giao dịch trong năm.
- `memberBalances/{uid}` (số dư/tiết kiệm trọn đời) cũng được Cloud Function này cập nhật cùng lúc, cùng cơ chế increment.
- Cấu trúc này scale tốt cho nhiều gia đình cùng lúc vì `familyId` đã là ranh giới tenant tự nhiên — chi phí/tốc độ của gia đình A không phụ thuộc gia đình B dùng bao lâu hay bao nhiêu dữ liệu.

**Quỹ (envelope budgeting) — tạo được nhiều cái, không còn cố định 1 "Quỹ tiền ăn" duy nhất.** Gia đình tự đặt tên tuỳ ý (Quỹ tiền ăn, Quỹ sinh hoạt, quỹ du lịch...), không giới hạn số lượng. Quỹ là 1 "pool" tiền như bất kỳ pool nào khác (`sourceKind`/`destinationKind = FUND`) — **không có subcollection `entries` riêng nữa**: lịch sử 1 quỹ = truy vấn `transactions` where `sourceRefId = fundId OR destinationRefId = fundId` (xem index cần tạo ở `docs/financial-core-v2.md` mục 14).

- **Nạp quỹ** = `TRANSFER(FUND_TOPUP)`, category "Nạp quỹ": `source = MEMBER_AVAILABLE(người nạp)`, `destination = FUND(quỹ)`.
- **Chi tiêu dùng quỹ** = `EXPENSE` bình thường (vd category Sinh hoạt) nhưng `source = FUND(quỹ)` thay vì `MEMBER_AVAILABLE` — **chỉ trừ đúng 1 pool là quỹ, không đụng số dư người mua.** Đây là điểm sửa quan trọng nhất so với bản nháp đầu (bản đầu từng trừ **cả** số dư người mua **lẫn** số dư quỹ cho cùng 1 khoản chi — lỗi trừ kép, xem `docs/financial-core-v2.md` mục F-03).
- **Chi tiêu không dùng quỹ** = `EXPENSE` bình thường, `source = MEMBER_AVAILABLE(người mua)`.
- **Quỹ không được phép âm** (giống `MEMBER_AVAILABLE`): UI đọc `balance` quỹ trước khi cho chọn, khoá lựa chọn nếu `amountMinor` > `balance`; Cloud Function kiểm tra lại trong 1 Firestore Transaction trước khi ghi, từ chối nếu sẽ làm âm (tránh race condition 2 thiết bị ghi cùng lúc).
- **Xoá quỹ chỉ được phép khi `balance = 0`.** Phải rút hết quỹ trước bằng giao dịch `TRANSFER(FUND_WITHDRAW)` (`source = FUND` → `destination = MEMBER_AVAILABLE`, đảo chiều của `FUND_TOPUP`), sau đó mới soft-delete (`isActive = false`) — không xoá cứng, không tự ý quy tiền còn lại cho ai. Màn Quỹ — Chi tiết (`docs/design.html` màn 15) chặn nút "Xoá quỹ" và giải thích rõ nếu `balance ≠ 0`.
- **Màn Quỹ/Tiết kiệm chỉ để xem số dư + lịch sử, không nhập giao dịch trực tiếp.** Các nút "Nạp quỹ"/"Ghi khoản mua"/"Rút về ví chính"/"Gửi ngân hàng" đều mở màn Thêm giao dịch (`docs/design.html` màn 09) điền sẵn loại giao dịch/nguồn-đích tương ứng — chỉ có 1 nơi tạo giao dịch duy nhất trong app, tránh 2 luồng code trùng nhau cho cùng 1 việc.

**Tiết kiệm — màn quản lý riêng, tách hẳn khỏi Quỹ, và không còn là Category kiểu Chi.** Toàn bộ thao tác tiết kiệm là `TRANSFER`, category "Tiết kiệm", phân biệt bằng `transferKind`:

- `SAVINGS_TOPUP` — nạp tiết kiệm: `source = MEMBER_AVAILABLE` → `destination = MEMBER_SAVINGS_CASH`.
- `SAVINGS_WITHDRAW` — rút về ví chính (mở qua màn Thêm giao dịch, loại "Chuyển"): `source = MEMBER_SAVINGS_CASH` → `destination = MEMBER_AVAILABLE`.
- `SAVINGS_TO_BANK` — gửi ngân hàng: `source = MEMBER_SAVINGS_CASH` → `destination = MEMBER_SAVINGS_BANK`.

Cả 3 đều **không đổi Tổng tài sản**, chỉ đổi chỗ tiền đang nằm — qua **chính màn Thêm giao dịch** (loại "Chuyển" → "Tiết kiệm"), không phải 1 form/màn hình riêng: chọn loại hình, nhập số tiền + ghi chú, `transactionDate`/`createdAt` hệ thống tự gán.

**Chuyển tiền cho thành viên khác** (thay 2 category cứng "Chồng đưa vợ"/"Vợ đưa chồng" ở bản nháp đầu) = `TRANSFER(MEMBER_TO_MEMBER)`, category "Chuyển tiền cho thành viên khác": `source = MEMBER_AVAILABLE(người gửi, mặc định là người đang thao tác)` → `destination = MEMBER_AVAILABLE(người nhận, chọn từ danh sách thành viên)`. Chạy đúng với bất kỳ số lượng thành viên nào ngay từ Giai đoạn A, không cần refactor lại khi gia đình mời thêm người thứ 3.

**Sửa/xoá giao dịch dùng reversal ledger, không sửa/xoá cứng:** `transactions` là append-only cho mọi field ảnh hưởng số dư — sửa hoặc xoá đều tạo thêm bản ghi mới (`reversalOfTxId`/`correctsTxId`), bản gốc chỉ được đánh dấu `reversedByTxId`, không bao giờ bị mutate hay xoá thật. Chi tiết cơ chế + lý do ở `docs/financial-core-v2.md` mục 21.

**Quy tắc bảo mật Firestore (rút gọn):**

```
match /families/{familyId}/{document=**} {
  allow read, write: if request.auth.uid in get(/databases/$(database)/documents/families/$(familyId)).data.memberIds;
}
```

---

## Lộ trình chi tiết theo mô hình thác nước

Mỗi phase dưới đây là **một đơn vị việc làm trọn vẹn theo đúng quy trình thác nước**: viết code xong → chạy thử thật (trên máy/thiết bị/emulator) → kiểm thử đạt tiêu chí → mới chuyển sang phase kế tiếp. Không phase nào bắt đầu khi phase trước chưa qua được bước Test. Phase đã có dấu ✅ là đã hoàn thành trong phiên làm việc dựng nền tảng ban đầu.

### Giai đoạn A — Nền tảng & lưu trữ local-first (18 phase, đánh số 1-18)

Toàn bộ tính năng ghi chép cá nhân (giao dịch + Quỹ tiền ăn) chạy đầy đủ ở giai đoạn này **mà chưa cần đụng tới Firebase** — chỉ khi thật sự có người thứ 2 tham gia (Giai đoạn B) mới cần lên mạng.

1. ✅ **Khởi tạo Flutter project + kiến trúc 3 lớp** — Code: `flutter create`, dựng `presentation/domain/data/core`. Chạy: `flutter run` trên điện thoại thật. Test: app mở được, không crash.
2. ✅ **Cấu hình lint chuẩn** — Code: bật `flutter_lints` trong `analysis_options.yaml`. Chạy: `dart analyze`. Test: 0 lỗi/cảnh báo.
3. **CI cơ bản trên GitHub Actions** — Code: workflow chạy `flutter analyze` + `flutter test` mỗi lần push. Chạy: push thử 1 commit. Test: Action chạy xanh.
4. ✅ **Đẩy code lên GitHub** — Code: `git init`, `git remote add`, push. Chạy: mở repo trên github.com. Test: đủ file, không lộ secret/API key.
5. ✅ **Domain entities & mock repository** — đã code/chạy/test qua `MockTransactionRepository` để dựng UI trước; sẽ thay bằng repository local ở phase kế mà không đổi domain.
6. **`LocalTransactionRepository` (lưu cục bộ trên máy)** — Code: implement `TransactionRepository` bằng SQLite/Hive, không phụ thuộc Firebase. Chạy: `flutter run` khi chưa cấu hình Firebase gì cả, thêm thử giao dịch. Test: lưu/đọc đúng, dữ liệu còn nguyên sau khi đóng/mở lại app.
7. **Luồng khởi động Local, không bắt đăng nhập** — Code: 3 màn theo đúng `docs/design.html` (Chào mừng → Đăng nhập/Bỏ qua → Chọn Cá nhân hoặc Gia đình), mặc định vào thẳng `syncMode: "local"` dù chọn Gia đình (chỉ thật sự cần đăng nhập khi bấm mời ở B). Chạy: cài app mới hoàn toàn, dùng thử. Test: ghi chép đầy đủ tính năng mà không cần tài khoản Google, không cần mạng.
8. **Nối sheet Thêm giao dịch ghi vào Local** — Code: gọi `LocalTransactionRepository` thay mock. Chạy: thêm 1 giao dịch thật. Test: xuất hiện đúng trong danh sách, còn nguyên sau khi khởi động lại app.
9. **Danh sách giao dịch theo ngày + chuyển xem tháng khác (đọc từ Local)** — Code: query local DB theo tháng. Chạy: thêm giao dịch nhiều tháng, chuyển qua lại. Test: nhóm đúng theo ngày, đúng tháng đang xem.
10. **Sửa/Xoá giao dịch qua reversal ledger** — Code: `updateTransaction`/`deleteTransaction` use case theo đúng cơ chế append-only ở `docs/financial-core-v2.md` mục 21 — sửa/xoá không mutate/xoá bản ghi gốc, mà tạo bản `reversalOfTxId`/`correctsTxId` mới, đánh dấu `reversedByTxId` lên bản gốc. **Màn "Chi tiết giao dịch" (`docs/design.html` màn 11) chỉ cho sửa `amountMinor` và `statusId`** — không cho đổi `categoryId`/`type`/`source`/`destination`; nhập sai hạng mục hoặc người ghi thì xoá rồi ghi lại từ màn Thêm giao dịch, tránh phải xử lý reversal phức tạp khi đổi cả loại giao dịch. Chạy: sửa số tiền 1 giao dịch, đổi trạng thái 1 giao dịch khác, rồi xoá 1 giao dịch. Test: sửa số tiền tạo đủ 3 bản ghi (gốc, hoàn tác, thay thế) và balance cuối đúng; đổi trạng thái **không** tạo bản ghi reversal nào (update thẳng `statusId`/`statusUpdatedAt`); UI danh sách chỉ hiện bản mới nhất (`reversedByTxId IS NULL`).
11. **Đổi trạng thái cho giao dịch đã ghi** — Code: `UpdateTransactionStatus` use case + màn "Chi tiết & đổi trạng thái" (`docs/design.html` màn 11) — statusId sửa được sau khi tạo, ghi `statusUpdatedAt`, không cố định lúc ghi. Chạy: tạo giao dịch Dâng hiến "Chưa chuẩn bị", mai mở lại đổi "Đã chuẩn bị" rồi "Đã dâng". Test: statusId/statusUpdatedAt cập nhật đúng, danh sách/tổng hợp phản ánh ngay.
12. **Quản lý Danh mục & Trạng thái trên Local** — Code: `LocalCategoryRepository`/`LocalStatusRepository` + màn "Danh mục — Danh sách/Chỉnh sửa" (`docs/design.html` màn 06-07, cần vẽ lại theo model V2 trước khi code phase này): xem/thêm/sửa/xoá danh mục (chọn `type`: Thu/Chi/Chuyển), thêm/sửa/xoá/sắp xếp từng bước trạng thái con, toggle `statsEnabled`. Chạy: tạo 1 danh mục mới + 2 bước trạng thái tự đặt tên. Test: danh mục mới xuất hiện đúng ở màn Thêm giao dịch, trạng thái tự sinh chip theo đúng thứ tự đã sắp xếp — không sửa code khi thêm danh mục mới, đúng nguyên tắc `CLAUDE.md` mục 9.
13. **Validate input khi ghi thật** — Code: số tiền > 0, bắt buộc chọn hạng mục + người ghi. Chạy: thử bấm Lưu khi thiếu dữ liệu. Test: nút Lưu khoá đúng.
14. **`syncMode: "local" | "cloud"`, mặc định `"local"`** — Code: field lưu cục bộ (SharedPreferences hoặc trong chính local DB). Chạy: kiểm tra giá trị khi tạo mới. Test: mọi tài khoản mới đều `"local"`, chưa đụng gì tới Firestore.
15. **`LocalFundRepository`, tạo được nhiều quỹ** — Code: implement `FundRepository` bằng local storage, hỗ trợ tạo nhiều `funds` tự đặt tên (không còn 1 quỹ cố định). Chạy: tạo 2 quỹ (Quỹ tiền ăn, Quỹ sinh hoạt), nạp/mua thử mỗi quỹ. Test: số dư từng quỹ độc lập, đúng, hoạt động hoàn toàn offline.
16. **Màn hình Danh sách Quỹ + tạo quỹ mới trên Local** — Code: nối UI "Quỹ — Danh sách" (`docs/design.html` màn 14) với `LocalFundRepository`. Chạy: dùng thử tạo quỹ, nạp + ghi mua trên máy thật. Test: số dư quỹ đúng như unit test `computeFundBalance` đã có.
17. **Chi tiêu nguồn là Quỹ (`source = FUND`) + chặn quỹ âm** — Code: màn Thêm giao dịch thêm phần chọn nguồn tiền (mặc định `MEMBER_AVAILABLE`, tuỳ chọn đổi sang 1 quỹ cụ thể), hiển thị số dư quỹ ngay tại chỗ; khoá lựa chọn nếu `amountMinor` > số dư quỹ, báo lỗi rõ nếu cố chọn. Chạy: nhập số tiền lớn hơn số dư 1 quỹ, thử chọn quỹ đó. Test: không cho chọn, thông điệp lỗi đúng; chọn quỹ đủ tiền thì **chỉ** trừ số dư quỹ — số dư người mua giữ nguyên, không trừ kép.
18. **Mốc kiểm tra: dùng đầy đủ ghi chép + Danh mục/Trạng thái tự quản lý + Quỹ liên tục nhiều ngày, hoàn toàn không cần Firebase** — Chạy: dùng thử thật vài ngày. Test: không phát sinh lỗi nào đòi hỏi mạng/Firebase cho việc ghi chép cá nhân.

### Giai đoạn B — Firebase & đồng bộ khi có người thứ 2 tham gia (17 phase, đánh số 19-35)

Chỉ bắt đầu giai đoạn này khi thật sự cần chia sẻ sổ với người khác — không có Firebase project nào được tạo trước đó.

19. **Tạo Firebase project thật** — Firebase Console, đặt tên, chọn khu vực gần VN. Chạy: mở lại project trên console. Test: project tồn tại, đúng cấu hình.
20. **Đăng ký app Android vào Firebase, tải `google-services.json`** — Code: đặt file vào `android/app/`, khai đúng `applicationId`. Chạy: `flutter build apk --debug`. Test: build qua, không lỗi thiếu config.
21. **`flutterfire configure` + `Firebase.initializeApp()` (chỉ init khi thật sự cần)** — Code: sinh `firebase_options.dart`, chỉ gọi init khi người dùng bấm "Mời người khác" lần đầu, không init ngay lúc mở app ở chế độ local. Chạy: bấm nút Mời. Test: Firebase khởi tạo đúng lúc cần, không tải SDK không cần thiết khi đang dùng local.
22. **Bật Cloud Firestore (Native mode)** — thao tác Console. Chạy: mở tab Firestore. Test: database trống đã tồn tại, đúng khu vực.
23. **Bật Firebase Authentication (Google Sign-In), kích hoạt khi cần mời** — Code: cấu hình OAuth client ID Android (SHA-1); màn hình đăng nhập (`docs/design.html` màn 02) chỉ hiện khi bấm "Mời người khác" hoặc "Chuyển sang Gia đình". Chạy: bấm Mời lần đầu trên máy thật. Test: được yêu cầu đăng nhập đúng lúc, `FirebaseAuth.instance.currentUser` đúng sau đó.
24. **Refactor `FamilyMember` → model vai trò tự do** — Code: thay enum cứng `{vo, chong}` bằng danh sách thành viên (`uid`, `roleLabel` tự do), cập nhật use case tính `availableBalance`/`savingsCash`/`savingsBank` và picker "người nhận" ở luồng Chuyển tiền cho thành viên khác. Chạy: `flutter test`. Test: toàn bộ test cũ pass lại với model tổng quát.
25. **Viết Security Rules bản đầu** (`families/{familyId}` chỉ `memberIds` đọc/ghi) — Code: `firestore.rules`. Chạy: `firebase deploy --only firestore:rules`. Test: deploy không lỗi cú pháp.
26. **Test rule bằng Firebase Emulator Suite** — Code: test rule (`@firebase/rules-unit-testing`). Chạy: `firebase emulators:exec`. Test: tài khoản ngoài family bị chặn đọc/ghi — rủi ro nghiêm trọng nhất của app, không được bỏ qua.
27. **Sinh mã mời có hạn dùng** — Code: `GenerateInvite` use case (mã ngẫu nhiên 6-8 ký tự, `expiresAt`, `maxUses`). Chạy: tạo thử 1 mã. Test: document `invites/{id}` đúng, mã không đoán được theo mẫu tuần tự.
28. **Màn hình chia sẻ mã/link mời (Android App Links)** — Code: UI hiển thị mã + nút chia sẻ link (không dùng Firebase Dynamic Links vì đã bị ngừng hỗ trợ). Chạy: chia sẻ thử qua tin nhắn. Test: bấm link trên máy khác mở đúng màn hình tham gia.
29. **Luồng tham gia qua mã/link** — Code: `JoinFamily` use case validate mã (chưa hết hạn, chưa hết lượt). Chạy: dùng tài khoản thứ 2 nhập mã. Test: mã hợp lệ được chấp nhận; mã hết hạn/hết lượt bị từ chối đúng.
30. **Migrate dữ liệu local → Firestore khi người thứ 2 thật sự tham gia** — Code: khi lời mời được chấp nhận, đọc toàn bộ giao dịch, Danh mục/Trạng thái tự tạo, và mọi Quỹ đang lưu local của người tạo, ghi đúng schema (`categories`, `categories/{id}/statuses`, `months/{yearMonth}/transactions`, `funds/`) lên Firestore, đổi `syncMode` sang `"cloud"`. Chạy: tạo ~20 giao dịch + 1 danh mục tự thêm + 2 quỹ local mẫu, mời + chấp nhận từ máy thứ 2. Test: toàn bộ dữ liệu local xuất hiện đúng trên Firestore, không trùng không mất; sau đó cả 2 máy đọc cùng dữ liệu.
31. **`FirestoreTransactionRepository` + chọn implementation theo `syncMode`** — Code: provider chọn Local hay Firestore lúc runtime dựa vào `syncMode` của gia đình hiện tại. Chạy: dùng thử app ở cả gia đình còn local và gia đình đã chuyển cloud. Test: đúng repository được dùng cho từng trường hợp, không lẫn lộn.
32. **Test rule cho `months/transactions`** — Code: rule con cho subcollection. Chạy: `firebase emulators:exec`. Test: user ngoài family bị chặn ghi vào bất kỳ tháng nào.
33. **Test offline ở chế độ cloud (Firestore local cache)** — Chạy: bật Airplane mode, thêm giao dịch, tắt Airplane mode. Test: giao dịch tự đồng bộ khi có mạng lại, không mất, không trùng.
34. **Test đồng bộ realtime 2 máy** — Chạy: máy A thêm giao dịch. Test: máy B thấy ngay không cần refresh.
35. **Màn hình Gia đình — Quản lý** (`docs/design.html` màn 04: danh sách thành viên, đổi `roleLabel`, nút "+ Mời thành viên mới", rời gia đình) — Code: `presentation/features/family/`. Chạy: đổi thử vai trò 1 thành viên. Test: `roleLabel` cập nhật đúng, hiển thị đúng ở toàn bộ app.

### Giai đoạn C — Tài khoản riêng từng thành viên, Danh mục/Quỹ trên Cloud & Tiết kiệm (12 phase, đánh số 36-47)

36. **Cloud Function `applyEffect` cập nhật `memberBalances`/`funds.balance`** — Code: trigger `onWrite` trên `transactions`, dùng `FieldValue.increment()` theo đúng `sourceKind/RefId` và `destinationKind/RefId` của giao dịch (1 hàm chung cho cả Income/Expense/Transfer, xem `docs/financial-core-v2.md` mục 6). Chạy: `firebase deploy --only functions`, thêm giao dịch thử đủ 3 loại. Test: `memberBalances/{uid}` đúng sau Income/Expense/Transfer, không pool nào bị âm.
37. **Nối 2 thẻ thành viên đọc `memberBalances` thật** — Code: đổi nguồn dữ liệu Trang chủ. Chạy: `flutter run`. Test: số hiển thị khớp Cloud Function tính.
38. **Unit test Cloud Function xử lý chuyển tiền cho thành viên khác** — Code: test bằng `firebase-functions-test`, dựa trên `sourceRefId`/`destinationRefId` tự do (không hardcode "Chồng đưa vợ"). Chạy: `npm test`. Test: chuyển giữa bất kỳ cặp thành viên nào đổi đúng dấu ở cả 2 phía, Tổng tài sản không đổi.
39. **`FirestoreCategoryRepository` + `FirestoreStatusRepository`** — Code: implement, thay `LocalCategoryRepository`/`LocalStatusRepository` khi `syncMode: "cloud"`, ghi vào `families/{id}/categories` và `categories/{id}/statuses`. Chạy: thêm/sửa/xoá 1 danh mục trên máy A. Test: máy B thấy thay đổi realtime, đúng schema.
40. **`FirestoreFundRepository`, hỗ trợ nhiều quỹ trên Cloud** — Code: implement, tạo/đọc `families/{id}/funds/{fundId}`. Chạy: tạo 2 quỹ. Test: document đúng path, không lẫn quỹ.
41. **Giao dịch nguồn/đích là Quỹ trên Firestore + Cloud Function chặn quỹ âm phía server** — Code: Cloud Function kiểm tra lại `balance` quỹ (và `availableBalance` người mua) trong cùng 1 Firestore Transaction trước khi `applyEffect`, từ chối nếu sẽ làm bất kỳ pool nào âm — không chỉ tin validate ở client vì 2 máy có thể ghi đồng thời. Chạy: giả lập 2 giao dịch cùng lúc từ 2 máy làm quỹ âm. Test: 1 trong 2 bị từ chối đúng, không pool nào bao giờ âm.
42. **Màn hình Danh sách Quỹ + Chi tiết quỹ với dữ liệu thật** — Code: `presentation/features/fund/`, hiển thị số dư + lịch sử (lọc `transactions` theo `sourceRefId`/`destinationRefId = fundId`) cho từng quỹ. Chạy: mở màn hình trên máy thật. Test: số dư = tổng nạp − tổng chi từ quỹ, khớp `computeFundBalance` đã unit test.
43. **Form nạp tiền vào quỹ (Firestore thật)** — Code: UI tạo 1 giao dịch `TRANSFER(FUND_TOPUP)`: `source = MEMBER_AVAILABLE` → `destination = FUND`. Chạy: nạp thử 500.000đ. Test: số dư quỹ tăng đúng, số dư người nạp giảm đúng, Tổng tài sản không đổi.
44. **Form ghi khoản chi tích quỹ (Firestore thật)** — Code: UI tạo 1 giao dịch `EXPENSE` với `source = FUND` (thay vì `MEMBER_AVAILABLE`), chặn chọn quỹ nếu `amountMinor` > số dư quỹ. Chạy: ghi thử "đi chợ 150.000đ" tích quỹ. Test: **chỉ** số dư quỹ giảm đúng — số dư người mua giữ nguyên (không trừ kép, xem test case 7 ở `docs/financial-core-v2.md`).
45. **Cloud Function cache `balance` lên `funds/{fundId}`** — đã gộp chung vào phase 36 (`applyEffect` cập nhật mọi pool cùng lúc) — Chạy/Test: xác nhận lại `balance` quỹ khớp tổng tính tay sau nhiều giao dịch liên tiếp.
46. **Nối tách tiết kiệm hiện tại/ngân hàng với dữ liệu thật** — Code: đổi nguồn `savingsCash`/`savingsBank` sang Cloud Function tính theo `transferKind` (`SAVINGS_TOPUP`/`SAVINGS_WITHDRAW`/`SAVINGS_TO_BANK`). Chạy: thêm giao dịch Tiết kiệm `SAVINGS_TO_BANK`. Test: đúng cột tăng, cột còn lại không đổi, `availableBalance` không đổi.
47. **Màn hình Tiết kiệm — Quản lý** (`docs/design.html` màn 16) — Code: `presentation/features/savings/`, 2 nút "Rút về ví chính"/"Gửi ngân hàng" mở lại màn Thêm giao dịch (09) với loại "Chuyển" → "Tiết kiệm" điền sẵn hành động tương ứng — **không dựng form nhập riêng**, đúng nguyên tắc chỉ 1 nơi tạo giao dịch duy nhất trong app (giống Quỹ ở phase 42-44). Chạy: rút thử 500.000 về ví chính, gửi thử 10.000.000 vào NH. Test: `SAVINGS_WITHDRAW` cộng đúng vào `availableBalance`; `SAVINGS_TO_BANK` chỉ đổi chỗ giữa `savingsCash`/`savingsBank`, Tổng tài sản không đổi.

### Giai đoạn D — Trạng thái & Tổng hợp tháng (9 phase, đánh số 48-56)

48. **Nối chọn trạng thái ghi thật** — Code: đã có UI generic theo `category.statuses`, đổi sang Firestore thật, ghi `statusId` (không phải chuỗi tự do). Chạy: thêm giao dịch Cho đi chọn "Đã chuẩn bị". Test: field `statusId` đúng trong document.
49. **Cloud Function tính rollup `months/{yearMonth}`** — Code: `onWrite` transactions → increment `categoryTotals`/`memberTotals`/`statusTotals` (khoá theo `statusId`), tách riêng `totalIncome`/`totalExpense`/`totalTransfer` theo `type`. Chạy: deploy, thêm giao dịch đa dạng Income/Expense/Transfer/trạng thái. Test: rollup doc khớp phép tính tay — `totalTransfer` không được cộng vào `totalExpense`.
50. **Nối màn hình Tổng hợp đọc rollup doc** — Code: đổi provider từ stream toàn bộ transactions sang đọc 1 document. Chạy: mở màn hình Tổng hợp. Test: số liệu khớp trước/sau khi đổi nguồn — đây là điểm mấu chốt giúp app nhanh dù dùng nhiều năm.
51. **Biểu đồ tròn theo hạng mục với dữ liệu thật** — Code: đổi nguồn data cho `fl_chart` đã dựng. Chạy: xem với >5 hạng mục có giao dịch. Test: % cộng lại đúng 100%.
52. **Card trạng thái tự sinh theo `category.statuses`, chỉ hiện danh mục có `statsEnabled = true`** — Code: đổi nguồn data, UI generic đã có sẵn không cần sửa, thêm điều kiện lọc `statsEnabled`. Chạy: bật/tắt `statsEnabled` cho vài danh mục. Test: chỉ danh mục bật mới hiện card ở Tổng hợp; tổng từng bước khớp rollup doc.
53. **Màn "Trạng thái — Chi tiết"** (`docs/design.html` màn 13) — Code: `presentation/features/status_detail/`, chọn 1 bước trạng thái xem danh sách giao dịch + tổng tiền, phục vụ đối chiếu cuối tháng. Chạy: xem danh mục Cho đi, chuyển qua từng bước. Test: tổng tiền mỗi bước khớp `statusTotals` trong rollup doc.
54. **Tỷ lệ tiết kiệm (Thu−Chi)/Thu ở Trang chủ với dữ liệu thật** — Code: đổi nguồn từ rollup. Chạy: xem sau vài giao dịch. Test: khớp domain logic đã unit test từ trước.
55. **Xem Tổng hợp theo năm** — Code: use case cộng 12 document `months/{yearMonth}`. Chạy: xem 1 năm có dữ liệu. Test: tổng năm = tổng 12 tháng cộng tay.
56. **Test hiệu năng đọc Firestore** — Chạy: đo số lượt đọc bằng Firebase Performance Monitoring khi mở Tổng hợp. Test: số lượt đọc không tăng theo số năm đã dùng (chỉ đọc rollup + tháng hiện tại, không quét lịch sử).

### Giai đoạn E — Ngân sách & nhắc nhở (5 phase, đánh số 57-61)

57. **Domain entity `Budget` + `budgets/{yearMonth}`** — Code: entity + repository interface thuần domain. Chạy: unit test logic. Test: test pass, không phụ thuộc Firebase.
58. **Màn hình đặt ngân sách theo hạng mục** — Code: `presentation/features/budget/`. Chạy: đặt thử ngân sách Sinh hoạt = 3.000.000đ. Test: lưu đúng vào Firestore.
59. **Cảnh báo 80%/100% ngân sách** — Code: so `categoryTotals` (rollup) với `budgets`. Chạy: chi vượt 80% thử. Test: cảnh báo hiện đúng ngưỡng.
60. **Cảnh báo theo tốc độ tiêu** (gợi ý chuyên gia — so % ngày đã qua trong tháng với % ngân sách đã dùng, cảnh báo sớm hơn ngưỡng cố định) — Code: `computeBudgetPace` use case, có unit test riêng. Chạy: giả lập ngày 15/30 đã tiêu 80%. Test: cảnh báo "tiêu nhanh hơn dự kiến" đúng lúc.
61. **Push notification nhắc ghi chi tiêu hàng ngày** — Code: Cloud Messaging + lịch gửi. Chạy: chờ tới giờ hẹn trên máy thật. Test: thông báo xuất hiện đúng giờ.

### Giai đoạn F — Bảo mật, di chuyển dữ liệu, hoàn thiện (6 phase, đánh số 62-67)

62. **Khoá PIN/vân tay** — Code: `local_auth`, `presentation/features/lock/`. Chạy: bật khoá, thoát app mở lại. Test: yêu cầu xác thực trước khi vào app.
63. **Công cụ import CSV từ Google Sheet cũ** — Code: script import vào đúng `months/{yearMonth}`, map đúng 9 hạng mục thật. Chạy: import thử 8 tháng dữ liệu thật đã có (~1700 dòng). Test: tổng số giao dịch import khớp số dòng gốc, không trùng lặp, số dư cuối tháng 8 khớp sheet cũ.
64. **Icon app + onboarding + empty state** — Code: `assets/icon`, hoàn thiện 3 màn khởi động đã dựng ở phase 7 (`docs/design.html` màn 01-03). Chạy: cài app mới hoàn toàn. Test: icon đúng, onboarding hiện đúng 1 lần, empty state rõ ràng khi chưa có giao dịch.
65. **Kiểm thử nhiều kích thước máy Android** — Chạy: chạy trên ≥3 kích thước màn hình/phiên bản OS. Test: UI không vỡ layout ở màn hình nhỏ nhất.
66. **Trang Chính sách quyền riêng tư** — Code: trang tĩnh khai đúng dữ liệu tài chính thu thập. Chạy: mở link. Test: nội dung đủ theo yêu cầu Play Console Data Safety.
67. **Cơ chế bắt buộc cập nhật (force update)** — Code: đọc `minSupportedVersion`/`latestVersion` từ Firebase Remote Config lúc khởi động; nếu `buildNumber` hiện tại < `minSupportedVersion` thì hiện màn chặn toàn bộ, chỉ có nút "Cập nhật ngay" mở Play Store, không có nút bỏ qua; nếu chỉ thấp hơn `latestVersion` thì hiện gợi ý, cho phép bỏ qua. Chạy: đổi `minSupportedVersion` trên Remote Config console cao hơn bản đang cài, mở lại app. Test: app bị chặn đúng lúc cần (vd khi chính sách/schema đổi phải ép người dùng lên bản mới), không cần chờ Google duyệt bản mới mới ép được.

### Giai đoạn G — Phát hành CH Play (5 phase, đánh số 68-72)

68. **Đăng ký Google Play Console + build & ký `.aab`** — Chạy: `flutter build appbundle --release`. Test: file `.aab` sinh ra không lỗi, mở được bằng `bundletool`.
69. **Khai báo Data Safety** — Test: khai đúng mục đích Personal Finance/Tools, không phải Lending/Payments (tránh bị yêu cầu giấy phép không cần thiết).
70. **Internal testing** — Chạy: upload `.aab`. Test: cài được qua link testing trên máy thật.
71. **Closed testing** — Test: đủ số ngày/người dùng tối thiểu Google yêu cầu với tài khoản developer mới.
72. **Phát hành Production** — Test: app xuất hiện công khai trên CH Play, cài + đăng nhập được từ tài khoản Google bất kỳ, không bị gắn cờ vi phạm chính sách.

### Giai đoạn H — Premium & Mở rộng, liên tục sau khi có người dùng thật (4 phase, đánh số 73-76)

73. **Bộ danh mục mẫu (template) cho gia đình mới** — CRUD danh mục/trạng thái đã có sẵn từ Giai đoạn A (phase 12), đúng nguyên tắc "hạng mục là dữ liệu" ở `CLAUDE.md` mục 9 — việc còn lại khi lên public là cung cấp vài bộ mẫu tham khảo (vd "Gia đình trẻ", "Có con nhỏ"...) để gia đình mới không bắt đầu từ màn trống, cộng hướng dẫn tạo danh mục đầu tiên. Test: 1 gia đình test chọn bộ mẫu khác hẳn 9 hạng mục seed của vợ chồng chủ dự án vẫn chạy đúng mà không cần sửa code.
74. **Đa ngôn ngữ Việt/Anh** — Code: `flutter_localizations` + `.arb`, tên hiển thị đổi theo locale (Ví Nhà Mình/HomeWallet). Test: đổi ngôn ngữ máy, toàn bộ UI đổi theo, không sót chuỗi hardcode.
75. **In-app purchase gói Premium** — Test: luồng mua hoạt động trơn tru từ giao diện đến ghi nhận quyền lợi trong Firestore.
76. **Widget màn hình chính, nhắc lịch hoá đơn định kỳ, xuất PDF/Excel** — Test: từng tính năng hoạt động độc lập, không phá vỡ luồng core đã ổn định.

---

## Bảng tổng hợp thời gian

| Giai đoạn | Số phase | Ước tính |
|---|---|---|
| A — Nền tảng & lưu trữ local-first | 18 (4 đã xong) | 6–8 ngày |
| B — Firebase & đồng bộ khi có người thứ 2 | 17 | 1.5–2 tuần |
| C — Tài khoản riêng, Danh mục/Quỹ cloud & Tiết kiệm | 12 | 1.5–2 tuần |
| D — Trạng thái & Tổng hợp | 9 | 1–1.5 tuần |
| E — Ngân sách & nhắc nhở | 5 | 4–6 ngày |
| F — Bảo mật & hoàn thiện | 6 | 1–1.5 tuần |
| G — Phát hành CH Play | 5 | 1–2 tuần (chủ yếu chờ Google) |
| H — Premium & mở rộng | 4 | Liên tục |

**Tổng: 76 phase, 4 đã xong.** **Thời gian tới khi có app trên CH Play (hết Giai đoạn G):** khoảng 8–11 tuần làm việc bán thời gian đều đặn — mỗi phase nhỏ, làm xong test qua trong ngày là chuyển tiếp được, không dồn việc lớn đến cuối mới kiểm thử. **Điểm mốc quan trọng: hết Giai đoạn A (phase 18) app đã dùng đầy đủ được rồi** — ghi chép, tự quản lý Danh mục/Trạng thái, tạo nhiều Quỹ — **hoàn toàn miễn phí, không cần đụng tới Firebase — cho tới khi thật sự cần chia sẻ với người thứ 2.**

## Chi phí

Google Play Developer: 25 USD một lần. Firebase: miễn phí (gói Spark) ở quy mô gia đình/vài chục người dùng đầu; chỉ cần nâng gói Blaze khi số lượng người dùng hoặc lượng đọc/ghi Firestore tăng đáng kể. Không cần server riêng trong toàn bộ Giai đoạn A–G.

### Ước tính chi phí ở quy mô 100.000 người dùng (~50.000 gia đình)

Con số dưới đây là **ước tính thô để có cảm giác về độ lớn**, không phải báo giá chính xác — luôn kiểm tra lại [công cụ tính giá chính thức của Firebase](https://firebase.google.com/pricing) trước khi ra quyết định, vì biểu giá có thể đổi theo thời gian.

- **Khối lượng dữ liệu:** mỗi giao dịch là 1 document rất nhỏ (~300 byte). 50.000 gia đình × ~200 giao dịch/tháng × vài năm ≈ hàng trăm triệu document, tổng dung lượng khoảng 100–150GB sau vài năm — Firestore xử lý tốt ở quy mô này, **dung lượng không phải điểm tốn tiền chính.**
- **Điểm tốn tiền chính là số lượt đọc/ghi:** ước tính ~40 triệu lượt ghi/tháng (giao dịch + Cloud Function cập nhật số dư/tổng hợp) và ~750 triệu lượt đọc/tháng (mở app, xem lại tháng, tổng hợp) → tổng chi phí Firestore + Cloud Functions rơi vào khoảng **vài trăm USD/tháng**, mức hoàn toàn khả thi nếu có doanh thu Premium.
- **Vì sao schema `months/{yearMonth}` + bảng tổng hợp tính sẵn (rollup) quan trọng:** nếu để client tự cộng dồn toàn bộ lịch sử giao dịch mỗi lần mở màn hình Tổng hợp (thay vì đọc 1 document rollup đã tính sẵn), chi phí đọc có thể **cao hơn 10–50 lần** và ngày càng tệ hơn qua từng năm dữ liệu tích luỹ. Quyết định kiến trúc này ảnh hưởng trực tiếp đến việc mô hình kinh doanh có bền vững hay không ở quy mô lớn.

### Bảo mật cần siết chặt hơn khi lên quy mô lớn

- **Security Rules là rủi ro số 1** — ở quy mô 50.000 gia đình, một lỗi rule có thể lộ dữ liệu tài chính của rất nhiều gia đình cùng lúc, không còn là "chỉ 2 người trong nhà" như lúc dựng MVP.
- **Firebase App Check** — chặn request không đến từ app thật, vừa là bảo mật vừa chống "billing DoS" (ai đó gửi hàng loạt request giả để đội chi phí Firestore lên).
- **Cloud Functions tự kiểm tra quyền**, không chỉ dựa vào Security Rules, vì Functions chạy với quyền admin — không có rule nào chặn được nếu code Function có lỗi.
- **Đặt Google Cloud Budget Alert** ngay khi lên gói Blaze — báo email nếu chi phí tháng vượt ngưỡng bất thường, tránh hoá đơn bất ngờ do bug (vd vòng lặp đọc Firestore).
- **Sao lưu định kỳ (Firestore scheduled export)** — mất dữ liệu ở quy mô nhỏ là phiền, ở quy mô 100k người dùng là khủng hoảng.

### Tạo tài khoản ở quy mô lớn

Firebase Authentication xử lý sẵn, đăng nhập Google gần như miễn phí ở mọi quy mô (không tính theo MAU với các phương thức OAuth như Google/Apple) — **không phải điểm nghẽn chi phí.** Cần cân nhắc thêm phương thức Email/Password làm dự phòng cho người dùng không có tài khoản Google.

## Rủi ro cần lưu ý

Google Play xét duyệt khắt khe hơn với app tài chính (Financial Services policy) dù đây chỉ là sổ ghi chép cá nhân, không kết nối ngân hàng — khai báo đúng mục đích sử dụng (Personal Finance/Tools, không phải Lending/Payments) để tránh bị yêu cầu giấy phép không cần thiết. Vì người dùng chính là dữ liệu tài chính gia đình, một lỗi đồng bộ sai (giao dịch của gia đình A lộ sang gia đình B) là rủi ro nghiêm trọng nhất về kỹ thuật — Security Rules và test rule ở Giai đoạn A phải được ưu tiên làm kỹ, không được bỏ qua để chạy nhanh MVP. Rủi ro này càng lớn hơn khi app mở rộng lên hàng chục nghìn gia đình (xem phần Chi phí ở trên).
