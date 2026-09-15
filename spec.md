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

**Phân loại gốc: mọi danh mục chỉ thuộc Thu hoặc Chi — không còn `kind` nhiều giá trị như bản nháp đầu.** Tiết kiệm và 2 hạng mục chuyển khoản (Chồng đưa vợ/Vợ đưa chồng) đều là danh mục thuộc **Chi**, không có loại riêng — Tiết kiệm được đánh dấu bằng cờ `isSaving`, chuyển khoản được đánh dấu bằng `transferToUid`. Đây là thay đổi so với bản nháp đầu (không còn `kind: "income"|"expense"|"savings"|"transfer"`).

Danh sách hạng mục seed mặc định (Phase 1, đúng theo dropdown thật trong sheet):

| id | Tên hiển thị | Thu/Chi | isSaving | transferToUid | Có `statuses`? |
|---|---|---|---|---|---|
| `thu_nhap` | Thu nhập | Thu | — | — | không |
| `sinh_hoat` | Sinh hoạt | Chi | false | — | tự thêm được (không mặc định) |
| `dau_tu` | Đầu tư | Chi | false | — | không |
| `tu_thuong` | Tự thưởng | Chi | false | — | không |
| `cho_di` | Cho đi | Chi | false | — | **có, 3 bước mặc định** |
| `tiet_kiem` | Tiết kiệm | Chi | **true** | — | không (dùng `savingsAction` riêng, xem bên dưới) |
| `dang_hien` | Dâng hiến | Chi | false | — | **có, 3 bước mặc định** |
| `chong_dua_vo` | Chồng đưa vợ | Chi | false | uid của Vợ | không |
| `vo_dua_chong` | Vợ đưa chồng | Chi | false | uid của Chồng | không |

Cách một giao dịch ảnh hưởng đến số dư: category thuộc **Thu** → cộng vào số dư người ghi; category thuộc **Chi** → trừ khỏi số dư người ghi (kể cả `isSaving` và transfer); riêng `isSaving` còn cộng/trừ vào `savingsOnHand`/`savingsInBank` theo `savingsAction`; riêng category có `transferToUid` thì Cloud Function cộng thêm số tiền đó vào số dư của `transferToUid` (không hardcode theo tên "Chồng đưa vợ" — đọc từ field).

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
  displayName, roleLabel (chuỗi tự do, gia đình tự đặt), joinedAt, isOwner

families/{familyId}/invites/{inviteId}
  code (6-8 ký tự ngẫu nhiên), suggestedRoleLabel,
  createdBy, createdAt, expiresAt, maxUses, usedCount

families/{familyId}/categories/{categoryId}
  name, color, typeId ("thu" | "chi"),
  isSaving (bool, chi ap dung khi typeId = "chi"),
  transferToUid (uid?, chi danh muc chuyen khoan),
  statsEnabled (bool, hien o Tong hop trang thai),
  isDefault

families/{familyId}/categories/{categoryId}/statuses/{statusId}
  name (tu dat), sortOrder (int)

families/{familyId}/transactions/{txId}
  categoryId, statusId (FK, null neu danh muc khong co statuses),
  statusUpdatedAt (timestamp, moi lan doi trang thai),
  amount, note, spenderUid, date,
  fundId (FK?, co neu tich 1 Quy khi ghi giao dich),
  savingsDestination / savingsAction (chi khi category isSaving — xem muc Quy/Tiet kiem),
  createdBy, createdAt

families/{familyId}/memberBalances/{uid}
  balance,               // Số dư hiện tại của người này
  savingsOnHand,         // Tiết kiệm hiện tại (chưa gửi ngân hàng)
  savingsInBank          // Tiết kiệm đã gửi ngân hàng

families/{familyId}/budgets/{yearMonth}
  categoryLimits: { categoryId: amount }
```

`memberBalances` là số liệu dẫn xuất (derived) — tính lại từ toàn bộ `transactions` của người đó; có thể cache bằng Cloud Function cập nhật mỗi khi có giao dịch mới để tránh phải cộng dồn hàng nghìn dòng ở client mỗi lần mở app (tham khảo số dòng thật trong sheet: hơn 1700 dòng chỉ riêng 8 tháng đầu năm).

**Công thức cân đối bắt buộc đúng ở mọi domain logic tính tổng hợp:**

```
Tổng thu = Tổng chi + Số tiền còn lại
Tổng chi = Chi phí + Tiết kiệm
```

Vì Tiết kiệm chỉ là 1 `category` thuộc Chi (`isSaving = true`), phương trình trên luôn đúng bằng cộng dồn số học đơn giản (`totalIncome - totalSpending - totalSaving = remaining`) — không cần nhánh logic riêng cho tiết kiệm ở bất kỳ use case tổng hợp nào trong `domain/`.

**Chia dữ liệu theo tháng + bảng tổng hợp tính sẵn — quyết định kiến trúc quan trọng cho việc mở rộng nhiều người dùng, nhiều năm:**

Một collection `transactions` phẳng, cộng dồn mãi mãi, có hai vấn đề khi scale: (1) mỗi lần mở app phải nghe realtime toàn bộ lịch sử để tính lại số dư/báo cáo — càng dùng lâu càng chậm và càng tốn phí đọc; (2) không có ranh giới tự nhiên để phân trang theo tháng/năm như cách người dùng thực sự xem dữ liệu (sheet thật cũng tự chia theo "Tháng 1"…"Tháng 9"). Giải pháp:

```
families/{familyId}/months/{yearMonth}              // yearMonth dạng "2026-09"
  totalIncome,
  totalSpending,        // Chi phí thường (khong tinh cac category isSaving)
  totalSaving,          // Cong don cac category isSaving trong thang
  // totalIncome = (totalSpending + totalSaving) + remaining — xem cong thuc can bang ben duoi
  categoryTotals: { categoryId: amount },
  memberTotals: { uid: { income, expense, savingsOnHand, savingsInBank } },
  statusTotals: { statusId: amount, ... }   // khoa theo statusId thuc te cua tung category, khong hardcode ten buoc

families/{familyId}/months/{yearMonth}/transactions/{txId}
  categoryId, statusId, statusUpdatedAt, fundId,
  amount, note, spenderUid, date, savingsDestination / savingsAction,
  createdBy, createdAt
```

- **Realtime listener chỉ mở cho tháng đang xem** (`months/{currentYearMonth}/transactions`) — dữ liệu luôn nhỏ và nhanh dù sổ đã dùng 5 năm, vì tháng cũ không còn bị "nghe" nữa.
- **`months/{yearMonth}` là document tổng hợp tính sẵn** (giống hệt các con số trong sheet Tổng hợp — Thu nhập, Sinh hoạt, Đầu tư... theo %, và khối Chưa chuẩn bị/Đã chuẩn bị/Đã dâng/Đã gửi), cập nhật bằng Cloud Function `onWrite` trên `transactions` dùng `FieldValue.increment()`. Mở màn hình Tổng hợp chỉ cần đọc **1 document** thay vì cộng hàng trăm/nghìn giao dịch ở client.
- **Xem theo năm** = cộng 12 document `months/{yearMonth}` (12 lần đọc, rẻ) thay vì đọc lại toàn bộ giao dịch trong năm.
- `memberBalances/{uid}` (số dư/tiết kiệm trọn đời) cũng được Cloud Function này cập nhật cùng lúc, cùng cơ chế increment.
- Cấu trúc này scale tốt cho nhiều gia đình cùng lúc vì `familyId` đã là ranh giới tenant tự nhiên — chi phí/tốc độ của gia đình A không phụ thuộc gia đình B dùng bao lâu hay bao nhiêu dữ liệu.

**Quỹ (envelope budgeting) — tạo được nhiều cái, không còn cố định 1 "Quỹ tiền ăn" duy nhất.** Gia đình tự đặt tên tuỳ ý (Quỹ tiền ăn, Quỹ sinh hoạt, quỹ du lịch...), không giới hạn số lượng:

```
families/{familyId}/funds/{fundId}
  name, color, createdAt,
  balance                          // derived, cache boi Cloud Function

families/{familyId}/funds/{fundId}/entries/{entryId}
  kind ("topUp" | "purchase"),     // nap tien vao quy | mua gi do tu quy
  linkedTxId (FK -> transactions), // giao dich that da tru chi phi nguoi tao
  amount, note, date, createdBy
```

**Quỹ nối thẳng vào giao dịch thật, không phải sổ tách biệt hoàn toàn như bản nháp đầu:**

- **Nạp quỹ** = một giao dịch Chi thật (categoryId trỏ tới category "Nạp quỹ [tên quỹ]", hoặc field `fundId` + `fundAction: "topUp"` trên transaction) — trừ số dư người nạp **và** tạo `FUND_ENTRY(kind: topUp)` tăng `balance` của quỹ, hai việc xảy ra cùng lúc từ 1 hành động.
- **Chi tiêu tích 1 quỹ** = khi Thêm giao dịch, người dùng **tuỳ chọn** chọn 1 quỹ (hoặc "Không dùng quỹ") ở field `fundId` trên transaction — nếu chọn, giao dịch vẫn trừ số dư người mua như bình thường (theo `categoryId` đã chọn, vd Sinh hoạt), **đồng thời** tạo `FUND_ENTRY(kind: purchase, linkedTxId)` giảm `balance` của quỹ đó. Chi phí luôn tính cho người mua/người nhập giao dịch, không phải người đã nạp quỹ trước đó.
- **Quỹ không được phép âm:** UI phải đọc `balance` hiện tại của quỹ trước khi cho phép chọn — nếu `amount` giao dịch > `balance` quỹ, khoá lựa chọn quỹ đó (không chỉ validate ở client, Cloud Function ghi `FUND_ENTRY` cũng phải kiểm tra lại và từ chối nếu sẽ làm `balance` âm, tránh race condition 2 thiết bị ghi cùng lúc).

**Tiết kiệm — màn quản lý riêng, tách hẳn khỏi Quỹ.** Giao dịch dưới category `isSaving = true` mang thêm field `savingsAction`:

- `"topUp"` — nạp tiết kiệm, tăng `savingsOnHand`.
- `"withdrawToBalance"` — rút về ví chính (màn "Tiết kiệm — Nhập giao dịch"), giảm `savingsOnHand` **và** cộng lại vào `balance` chi tiêu của người đó — tiền rời khỏi tiết kiệm thật sự.
- `"moveToBank"` — gửi ngân hàng, giảm `savingsOnHand` và tăng `savingsInBank` tương ứng, không đụng `balance` chính (chỉ đổi chỗ tiền đang nằm, tổng tiết kiệm không đổi).

Cả 3 hành động đều qua 1 form chung: chọn loại hình, nhập số tiền + ghi chú, `date`/`createdAt` hệ thống tự gán — người dùng không nhập tay ngày tháng.

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
10. **Sửa/Xoá giao dịch** — Code: `EditTransaction`/`DeleteTransaction` use case. Chạy: sửa và xoá thử. Test: local DB cập nhật đúng, UI phản ánh ngay.
11. **Đổi trạng thái cho giao dịch đã ghi** — Code: `UpdateTransactionStatus` use case + màn "Chi tiết & đổi trạng thái" (`docs/design.html` màn 11) — statusId sửa được sau khi tạo, ghi `statusUpdatedAt`, không cố định lúc ghi. Chạy: tạo giao dịch Dâng hiến "Chưa chuẩn bị", mai mở lại đổi "Đã chuẩn bị" rồi "Đã dâng". Test: statusId/statusUpdatedAt cập nhật đúng, danh sách/tổng hợp phản ánh ngay.
12. **Quản lý Danh mục & Trạng thái trên Local** — Code: `LocalCategoryRepository`/`LocalStatusRepository` + màn "Danh mục — Danh sách/Chỉnh sửa" (`docs/design.html` màn 06-07): xem/thêm/sửa/xoá danh mục (chọn Thu/Chi, đánh dấu Tiết kiệm), thêm/sửa/xoá/sắp xếp từng bước trạng thái con, toggle `statsEnabled`. Chạy: tạo 1 danh mục mới + 2 bước trạng thái tự đặt tên. Test: danh mục mới xuất hiện đúng ở màn Thêm giao dịch, trạng thái tự sinh chip theo đúng thứ tự đã sắp xếp — không sửa code khi thêm danh mục mới, đúng nguyên tắc `CLAUDE.md` mục 9.
13. **Validate input khi ghi thật** — Code: số tiền > 0, bắt buộc chọn hạng mục + người ghi. Chạy: thử bấm Lưu khi thiếu dữ liệu. Test: nút Lưu khoá đúng.
14. **`syncMode: "local" | "cloud"`, mặc định `"local"`** — Code: field lưu cục bộ (SharedPreferences hoặc trong chính local DB). Chạy: kiểm tra giá trị khi tạo mới. Test: mọi tài khoản mới đều `"local"`, chưa đụng gì tới Firestore.
15. **`LocalFundRepository`, tạo được nhiều quỹ** — Code: implement `FundRepository` bằng local storage, hỗ trợ tạo nhiều `funds` tự đặt tên (không còn 1 quỹ cố định). Chạy: tạo 2 quỹ (Quỹ tiền ăn, Quỹ sinh hoạt), nạp/mua thử mỗi quỹ. Test: số dư từng quỹ độc lập, đúng, hoạt động hoàn toàn offline.
16. **Màn hình Danh sách Quỹ + tạo quỹ mới trên Local** — Code: nối UI "Quỹ — Danh sách" (`docs/design.html` màn 14) với `LocalFundRepository`. Chạy: dùng thử tạo quỹ, nạp + ghi mua trên máy thật. Test: số dư quỹ đúng như unit test `computeFundBalance` đã có.
17. **Giao dịch liên kết Quỹ (`fundId`) + chặn quỹ âm** — Code: màn Thêm giao dịch thêm phần chọn quỹ (tuỳ chọn, có "Không dùng quỹ"), hiển thị số dư quỹ ngay tại chỗ; khoá lựa chọn nếu `amount` > số dư quỹ, báo lỗi rõ nếu cố chọn. Chạy: nhập số tiền lớn hơn số dư 1 quỹ, thử chọn quỹ đó. Test: không cho chọn, thông điệp lỗi đúng; chọn quỹ đủ tiền thì trừ đúng cả số dư người mua lẫn số dư quỹ.
18. **Mốc kiểm tra: dùng đầy đủ ghi chép + Danh mục/Trạng thái tự quản lý + Quỹ liên tục nhiều ngày, hoàn toàn không cần Firebase** — Chạy: dùng thử thật vài ngày. Test: không phát sinh lỗi nào đòi hỏi mạng/Firebase cho việc ghi chép cá nhân.

### Giai đoạn B — Firebase & đồng bộ khi có người thứ 2 tham gia (17 phase, đánh số 19-35)

Chỉ bắt đầu giai đoạn này khi thật sự cần chia sẻ sổ với người khác — không có Firebase project nào được tạo trước đó.

19. **Tạo Firebase project thật** — Firebase Console, đặt tên, chọn khu vực gần VN. Chạy: mở lại project trên console. Test: project tồn tại, đúng cấu hình.
20. **Đăng ký app Android vào Firebase, tải `google-services.json`** — Code: đặt file vào `android/app/`, khai đúng `applicationId`. Chạy: `flutter build apk --debug`. Test: build qua, không lỗi thiếu config.
21. **`flutterfire configure` + `Firebase.initializeApp()` (chỉ init khi thật sự cần)** — Code: sinh `firebase_options.dart`, chỉ gọi init khi người dùng bấm "Mời người khác" lần đầu, không init ngay lúc mở app ở chế độ local. Chạy: bấm nút Mời. Test: Firebase khởi tạo đúng lúc cần, không tải SDK không cần thiết khi đang dùng local.
22. **Bật Cloud Firestore (Native mode)** — thao tác Console. Chạy: mở tab Firestore. Test: database trống đã tồn tại, đúng khu vực.
23. **Bật Firebase Authentication (Google Sign-In), kích hoạt khi cần mời** — Code: cấu hình OAuth client ID Android (SHA-1); màn hình đăng nhập (`docs/design.html` màn 02) chỉ hiện khi bấm "Mời người khác" hoặc "Chuyển sang Gia đình". Chạy: bấm Mời lần đầu trên máy thật. Test: được yêu cầu đăng nhập đúng lúc, `FirebaseAuth.instance.currentUser` đúng sau đó.
24. **Refactor `FamilyMember` → model vai trò tự do** — Code: thay enum cứng `{vo, chong}` bằng danh sách thành viên (`uid`, `roleLabel` tự do), cập nhật `compute_member_financials`/`transferToUid`. Chạy: `flutter test`. Test: toàn bộ test cũ pass lại với model tổng quát.
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

36. **Cloud Function cập nhật `memberBalances`** — Code: trigger `onWrite` trên `transactions`, dùng `FieldValue.increment()`, đọc `transferToUid` từ chính category thay vì hardcode tên hạng mục. Chạy: `firebase deploy --only functions`, thêm giao dịch thử. Test: `memberBalances/{uid}` đúng sau nhiều loại giao dịch (thu/chi/tiết kiệm/chuyển khoản).
37. **Nối 2 thẻ thành viên đọc `memberBalances` thật** — Code: đổi nguồn dữ liệu Trang chủ. Chạy: `flutter run`. Test: số hiển thị khớp Cloud Function tính.
38. **Unit test Cloud Function xử lý chuyển khoản 2 chiều** — Code: test bằng `firebase-functions-test`, dựa trên `transferToUid` tổng quát (không hardcode "Chồng đưa vợ"). Chạy: `npm test`. Test: mọi cặp category chuyển khoản đổi đúng dấu ở cả 2 phía.
39. **`FirestoreCategoryRepository` + `FirestoreStatusRepository`** — Code: implement, thay `LocalCategoryRepository`/`LocalStatusRepository` khi `syncMode: "cloud"`, ghi vào `families/{id}/categories` và `categories/{id}/statuses`. Chạy: thêm/sửa/xoá 1 danh mục trên máy A. Test: máy B thấy thay đổi realtime, đúng schema.
40. **`FirestoreFundRepository`, hỗ trợ nhiều quỹ trên Cloud** — Code: implement, ghi vào `families/{id}/funds/{fundId}/entries`. Chạy: tạo 2 quỹ, gọi thử `addEntry()` cho từng quỹ. Test: document đúng path, không lẫn quỹ.
41. **Giao dịch liên kết Quỹ trên Firestore (`fundId`) + Cloud Function chặn quỹ âm phía server** — Code: Cloud Function kiểm tra lại `balance` quỹ trước khi ghi `FUND_ENTRY`, từ chối (rollback transaction) nếu sẽ âm — không chỉ tin validate ở client vì 2 máy có thể ghi đồng thời. Chạy: giả lập 2 giao dịch cùng lúc từ 2 máy làm quỹ âm. Test: 1 trong 2 bị từ chối đúng, `balance` quỹ không bao giờ âm.
42. **Màn hình Danh sách Quỹ + Chi tiết quỹ với dữ liệu thật** — Code: `presentation/features/fund/`, hiển thị số dư + danh sách khoản cho từng quỹ. Chạy: mở màn hình trên máy thật. Test: số dư = tổng nạp − tổng mua, khớp `computeFundBalance` đã unit test.
43. **Form nạp tiền vào quỹ (Firestore thật)** — Code: UI + `addEntry(kind: topUp)`, đồng thời tạo giao dịch Chi trừ số dư người nạp. Chạy: nạp thử 500.000đ. Test: số dư quỹ tăng đúng, số dư người nạp giảm đúng, entry hiện trong danh sách.
44. **Form ghi khoản chi tích quỹ (Firestore thật)** — Code: UI + `addEntry(kind: purchase, linkedTxId)`, chặn chọn quỹ nếu `amount` > số dư quỹ. Chạy: ghi thử "đi chợ 150.000đ" tích quỹ. Test: số dư quỹ giảm đúng, số dư người mua giảm đúng qua giao dịch liên kết — không tạo thêm dòng trùng.
45. **Cloud Function cache `balance` lên `funds/{fundId}`** — Code: `onWrite` entries → increment. Chạy: deploy + test qua vài entry. Test: field `balance` khớp tổng tính tay.
46. **Nối tách tiết kiệm hiện tại/ngân hàng với dữ liệu thật** — Code: đổi nguồn `savingsOnHand`/`savingsInBank` sang Cloud Function tính theo `savingsAction`. Chạy: thêm giao dịch Tiết kiệm `moveToBank`. Test: đúng cột tăng, cột còn lại không đổi, `balance` chính không đổi.
47. **Màn hình Tiết kiệm — Quản lý + Nhập giao dịch** (`docs/design.html` màn 16-17) — Code: `presentation/features/savings/`, 2 nút "Rút về ví chính"/"Gửi ngân hàng" mở form chung (loại hình, số tiền, ghi chú, `createdAt` tự động). Chạy: rút thử 500.000 về ví chính, gửi thử 10.000.000 vào NH. Test: `withdrawToBalance` cộng đúng vào `balance` chính; `moveToBank` chỉ đổi chỗ giữa `savingsOnHand`/`savingsInBank`, tổng tiết kiệm không đổi.

### Giai đoạn D — Trạng thái & Tổng hợp tháng (9 phase, đánh số 48-56)

48. **Nối chọn trạng thái ghi thật** — Code: đã có UI generic theo `category.statuses`, đổi sang Firestore thật, ghi `statusId` (không phải chuỗi tự do). Chạy: thêm giao dịch Cho đi chọn "Đã chuẩn bị". Test: field `statusId` đúng trong document.
49. **Cloud Function tính rollup `months/{yearMonth}`** — Code: `onWrite` transactions → increment `categoryTotals`/`memberTotals`/`statusTotals` (khoá theo `statusId`), tách `totalSpending`/`totalSaving`. Chạy: deploy, thêm giao dịch đa dạng hạng mục/trạng thái/tiết kiệm. Test: rollup doc khớp phép tính tay, `totalIncome = totalSpending + totalSaving + remaining`.
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
