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

**Mô hình dữ liệu Firestore (đối chiếu trực tiếp với sheet "Quản lý tài chính 2026" thật — trang Ghi chép + Tổng hợp):**

Danh sách hạng mục (`categories`) lấy đúng theo dropdown thật trong sheet, **không phải** danh sách Ăn uống/Di chuyển đã đoán ở bản nháp đầu tiên:

| id | Tên hiển thị | Loại (`kind`) | Có theo dõi trạng thái? |
|---|---|---|---|
| `thu_nhap` | Thu nhập | income | không |
| `sinh_hoat` | Sinh hoạt | expense | không |
| `dau_tu` | Đầu tư | expense | không |
| `tu_thuong` | Tự thưởng | expense | không |
| `cho_di` | Cho đi | expense | **có** |
| `tiet_kiem` | Tiết kiệm | savings | không (nhưng số tiền có thể âm = rút ra) |
| `dang_hien` | Dâng hiến | expense | **có** |
| `chong_dua_vo` | Chồng đưa vợ | transfer | không |
| `vo_dua_chong` | Vợ đưa chồng | transfer | không |

`kind` quyết định cách một giao dịch ảnh hưởng đến số dư: `income` cộng vào số dư người ghi; `expense`/`savings` trừ khỏi số dư người ghi (riêng `savings` còn cộng/trừ vào quỹ tiết kiệm riêng của người đó — số âm nghĩa là rút tiết kiệm); `transfer` trừ số dư người chuyển và cộng số dư người nhận (`chong_dua_vo`: Chồng −, Vợ +; `vo_dua_chong`: Vợ −, Chồng +).

Với `cho_di` và `dang_hien`, mỗi giao dịch còn có trường `status` theo đúng quy trình thật trong sheet: `chua_chuan_bi` → `da_chuan_bi` → `da_xong` (hiển thị là "Đã gửi" cho Cho đi, "Đã dâng" cho Dâng hiến). Màn hình Tổng hợp phải tổng hợp được số tiền theo từng trạng thái cho 2 hạng mục này (đúng như khối "Kế hoạch / Chưa chuẩn bị / Đã chuẩn bị / Đã dâng / Đã gửi" trong sheet Tổng hợp thật).

**Tài khoản theo từng thành viên (Vợ/Chồng riêng biệt)** — đây là điểm khác biệt lớn nhất so với mô hình "một quỹ chung" ban đầu: sheet thật tính **Số dư** và **Tiết kiệm** riêng cho Vợ và cho Chồng (cột `K`/`N` "Tổng hợp"), dựa vào cột "Người tiêu" của từng giao dịch. App phải giữ đúng cơ chế này — không gộp chung thành một quỹ gia đình duy nhất.

**Tiết kiệm chia 2 loại con (yêu cầu mới, sheet hiện chưa có — cần bổ sung khi lên app):** mỗi tài khoản tiết kiệm (của Vợ, của Chồng) tách thành **tiết kiệm hiện tại** (tiền mặt/chưa gửi) và **tiết kiệm đã gửi ngân hàng**, để biết chính xác bao nhiêu đang nằm ở đâu.

```
families/{familyId}
  name, createdAt, memberIds: [uid1, uid2]

families/{familyId}/members/{uid}
  displayName, roleLabel ("Vợ" | "Chồng" | tuỳ chỉnh), joinedAt

families/{familyId}/categories/{categoryId}
  name, color, kind ("income" | "expense" | "savings" | "transfer"),
  hasStatus (bool), isDefault

families/{familyId}/transactions/{txId}
  categoryId, amount, note, spenderUid, date,
  status ("chua_chuan_bi" | "da_chuan_bi" | "da_xong" | null),
  createdBy, createdAt

families/{familyId}/memberBalances/{uid}
  balance,               // Số dư hiện tại của người này
  savingsOnHand,         // Tiết kiệm hiện tại (chưa gửi ngân hàng)
  savingsInBank          // Tiết kiệm đã gửi ngân hàng

families/{familyId}/budgets/{yearMonth}
  categoryLimits: { categoryId: amount }
```

`memberBalances` là số liệu dẫn xuất (derived) — tính lại từ toàn bộ `transactions` của người đó; có thể cache bằng Cloud Function cập nhật mỗi khi có giao dịch mới để tránh phải cộng dồn hàng nghìn dòng ở client mỗi lần mở app (tham khảo số dòng thật trong sheet: hơn 1700 dòng chỉ riêng 8 tháng đầu năm).

**Chia dữ liệu theo tháng + bảng tổng hợp tính sẵn — quyết định kiến trúc quan trọng cho việc mở rộng nhiều người dùng, nhiều năm:**

Một collection `transactions` phẳng, cộng dồn mãi mãi, có hai vấn đề khi scale: (1) mỗi lần mở app phải nghe realtime toàn bộ lịch sử để tính lại số dư/báo cáo — càng dùng lâu càng chậm và càng tốn phí đọc; (2) không có ranh giới tự nhiên để phân trang theo tháng/năm như cách người dùng thực sự xem dữ liệu (sheet thật cũng tự chia theo "Tháng 1"…"Tháng 9"). Giải pháp:

```
families/{familyId}/months/{yearMonth}              // yearMonth dạng "2026-09"
  totalIncome, totalExpense,
  categoryTotals: { categoryId: amount },
  memberTotals: { uid: { income, expense, savingsOnHand, savingsInBank } },
  statusTotals: { cho_di: { chuaChuanBi, daChuanBi, daXong }, dang_hien: {...} }

families/{familyId}/months/{yearMonth}/transactions/{txId}
  categoryId, amount, note, spenderUid, date, status, savingsDestination,
  createdBy, createdAt
```

- **Realtime listener chỉ mở cho tháng đang xem** (`months/{currentYearMonth}/transactions`) — dữ liệu luôn nhỏ và nhanh dù sổ đã dùng 5 năm, vì tháng cũ không còn bị "nghe" nữa.
- **`months/{yearMonth}` là document tổng hợp tính sẵn** (giống hệt các con số trong sheet Tổng hợp — Thu nhập, Sinh hoạt, Đầu tư... theo %, và khối Chưa chuẩn bị/Đã chuẩn bị/Đã dâng/Đã gửi), cập nhật bằng Cloud Function `onWrite` trên `transactions` dùng `FieldValue.increment()`. Mở màn hình Tổng hợp chỉ cần đọc **1 document** thay vì cộng hàng trăm/nghìn giao dịch ở client.
- **Xem theo năm** = cộng 12 document `months/{yearMonth}` (12 lần đọc, rẻ) thay vì đọc lại toàn bộ giao dịch trong năm.
- `memberBalances/{uid}` (số dư/tiết kiệm trọn đời) cũng được Cloud Function này cập nhật cùng lúc, cùng cơ chế increment.
- Cấu trúc này scale tốt cho nhiều gia đình cùng lúc vì `familyId` đã là ranh giới tenant tự nhiên — chi phí/tốc độ của gia đình A không phụ thuộc gia đình B dùng bao lâu hay bao nhiêu dữ liệu.

**Quỹ tiền ăn riêng (Quỹ) — góc nhìn tài chính cá nhân: kỹ thuật "phong bì ngân sách" (envelope budgeting).** Thay vì chỉ ghi từng khoản Sinh hoạt rời rạc, quỹ cho phép **nạp một khoản cố định** rồi tiêu dần trong khoản đó, biết ngay còn lại bao nhiêu — đúng tâm lý "tiêu trong giới hạn đã định" thay vì tiêu xong mới biết đã vượt. Thiết kế tổng quát (`Quỹ`) để sau này mở rộng thêm quỹ khác (quỹ du lịch, quỹ hiếu hỉ...) mà không đổi kiến trúc:

```
families/{familyId}/funds/{fundId}
  name ("Quỹ tiền ăn"), color, createdAt

families/{familyId}/funds/{fundId}/entries/{entryId}
  kind ("topUp" | "purchase"),   // nạp tiền vào quỹ | mua gì đó từ quỹ
  amount, note ("đi chợ", "thịt bò"...), date, createdBy
```

Số dư quỹ = tổng `topUp` − tổng `purchase` (derived, có thể cache vào field `balance` trên chính document `funds/{fundId}` bằng Cloud Function như trên). Một khoản `purchase` từ quỹ tiền ăn **không** đồng thời tạo thêm một dòng `Sinh hoạt` ở sổ chính — quỹ là sổ con độc lập để theo dõi chi tiêu ăn uống chi tiết, tránh đếm trùng khi tính tổng chi hộ gia đình.

**Quy tắc bảo mật Firestore (rút gọn):**

```
match /families/{familyId}/{document=**} {
  allow read, write: if request.auth.uid in get(/databases/$(database)/documents/families/$(familyId)).data.memberIds;
}
```

---

## Lộ trình theo Phase

### Phase 0 — Khởi tạo & Nền tảng
**Mục tiêu:** Có project chạy được, kiến trúc sẵn sàng, chưa cần tính năng.
**Công việc:** Khởi tạo Flutter project, cấu hình Firebase (Auth, Firestore, App Check), dựng khung 3 lớp `presentation/domain/data`, cấu hình lint + CI cơ bản (GitHub Actions chạy `flutter analyze` + `flutter test` mỗi lần push), thiết kế schema Firestore và viết Security Rules kèm test rule bằng Firebase emulator.
**Tiêu chí hoàn thành:** App build chạy trên thiết bị thật, đăng nhập Google thành công, ghi/đọc thử 1 document Firestore đúng rule.
**Thời gian ước tính:** 3–5 ngày.

### Phase 1 — MVP: Ghi chép & Đồng bộ realtime
**Mục tiêu:** Thay thế được sheet hiện tại cho việc ghi chép hàng ngày.
**Công việc:** Tạo/tham gia Sổ chung qua mã mời; CRUD giao dịch đầy đủ hạng mục/`kind`, số tiền, ghi chú, người chi (Vợ/Chồng), ngày, trạng thái (cho `cho_di`/`dang_hien`); danh mục mặc định lấy **đúng theo sheet thật** (Thu nhập, Sinh hoạt, Đầu tư, Tự thưởng, Cho đi, Tiết kiệm, Dâng hiến, Chồng đưa vợ, Vợ đưa chồng) và cho thêm danh mục tuỳ chỉnh; màn hình Trang chủ hiển thị **Số dư + Tiết kiệm riêng cho từng người** (không gộp chung); màn hình **Quỹ tiền ăn** riêng (nạp tiền vào quỹ, ghi từng khoản đã mua + số tiền, xem số dư quỹ còn lại) theo kiểu phong bì ngân sách; danh sách giao dịch theo tháng nhóm theo ngày, dữ liệu Firestore chia theo `months/{yearMonth}` để mở nhanh dù sổ đã dùng nhiều năm; đồng bộ realtime hai chiều giữa các thành viên; hoạt động offline nhờ Firestore local cache, tự đồng bộ khi có mạng lại.
**Tiêu chí hoàn thành:** Vợ thêm giao dịch trên điện thoại → chồng thấy ngay trên máy của mình mà không cần refresh; tắt mạng vẫn nhập được, bật mạng lại tự đồng bộ không mất dữ liệu; số dư/tiết kiệm của Vợ và Chồng hiển thị đúng, tách biệt.
**Thời gian ước tính:** 2–3 tuần.

### Phase 2 — Ngân sách & Báo cáo tài chính
**Mục tiêu:** Từ "ghi chép" tiến lên "quản lý" — đúng tinh thần tài chính cá nhân thực sự.
**Công việc:** Đặt ngân sách theo hạng mục/tháng và cảnh báo khi đạt 80%/100% ngân sách; màn hình Tổng hợp với biểu đồ tròn theo hạng mục và biểu đồ đường theo tháng; các chỉ số tài chính chủ chốt tính tự động — tỷ lệ tiết kiệm (Thu − Chi)/Thu, tỷ lệ Dâng hiến/Cho đi trên tổng thu, hạng mục chi nhiều nhất; khối theo dõi Chưa chuẩn bị/Đã chuẩn bị/Đã dâng/Đã gửi cho Dâng hiến & Cho đi (đúng khối K-L trong sheet Tổng hợp thật); tách **tiết kiệm hiện tại** và **tiết kiệm đã gửi ngân hàng** trong mục Tiết kiệm của mỗi người; nhắc nhở nhập chi tiêu hàng ngày qua thông báo đẩy.
**Tiêu chí hoàn thành:** Xem được một tháng bất kỳ và biết ngay: thu bao nhiêu, chi bao nhiêu, tiết kiệm được bao nhiêu %, hạng mục nào đang vượt ngân sách.
**Thời gian ước tính:** 1.5–2 tuần.

### Phase 3 — Hoàn thiện, di chuyển dữ liệu cũ & bảo mật
**Mục tiêu:** Sẵn sàng để người thật ngoài bạn dùng thử.
**Công việc:** Công cụ nhập CSV xuất từ Google Sheet hiện tại vào đúng schema Firestore (giữ lịch sử 8 tháng đã ghi); khoá app bằng mã PIN/sinh trắc học; hoàn thiện icon, onboarding, empty state; kiểm thử trên nhiều kích thước máy Android; viết trang Chính sách quyền riêng tư (bắt buộc để nộp Play Console vì app thu thập dữ liệu tài chính).
**Tiêu chí hoàn thành:** Cài app mới hoàn toàn, nhập dữ liệu cũ, dùng xuyên suốt 1 tuần không phát sinh lỗi mất dữ liệu hay đồng bộ sai người.
**Thời gian ước tính:** 1–1.5 tuần.

### Phase 4 — Kiểm thử & Phát hành CH Play
**Mục tiêu:** App lên Google Play, có người dùng thật đầu tiên.
**Công việc:** Đăng ký Google Play Console (25 USD, một lần); build `.aab`; đưa lên kênh Internal testing rồi Closed testing (mời vài người dùng thử tối thiểu vài ngày — Google yêu cầu điều này với tài khoản developer mới trước khi mở Production); khai báo mục Data Safety trung thực về dữ liệu tài chính thu thập; chuẩn bị mô tả, ảnh chụp màn hình, banner; sau khi ổn định, phát hành Production.
**Tiêu chí hoàn thành:** App có trên CH Play, cài đặt và đăng nhập được từ tài khoản Google bất kỳ, không bị Google gắn cờ vi phạm chính sách Financial Services/Data Safety.
**Thời gian ước tính:** 1–2 tuần (phần lớn là thời gian chờ xét duyệt/testing bắt buộc của Google, không phải thời gian code).

### Phase 5 — Premium & Mở rộng
**Mục tiêu:** Kiếm tiền từ app và giữ chân người dùng lâu dài.
**Công việc:** Tích hợp `in_app_purchase` cho gói Premium (mở khoá: nhiều sổ chung, backup không giới hạn, báo cáo xu hướng nhiều tháng, xuất PDF/Excel không giới hạn); widget màn hình chính; nhắc lịch hoá đơn định kỳ (tiền nhà, điện, nước); đa ngôn ngữ Việt/Anh; xem xét thêm Cloud Functions để tính báo cáo phía server khi dữ liệu lớn dần, giảm tải cho máy người dùng.
**Tiêu chí hoàn thành:** Có ít nhất một luồng mua Premium hoạt động trơn tru từ giao diện đến ghi nhận quyền lợi trong Firestore.
**Thời gian ước tính:** liên tục, không có điểm kết thúc cố định — đây là giai đoạn duy trì và tăng trưởng.

---

## Bảng tổng hợp thời gian

| Phase | Nội dung | Ước tính |
|---|---|---|
| 0 | Khởi tạo & nền tảng | 3–5 ngày |
| 1 | MVP ghi chép & đồng bộ | 2–3 tuần |
| 2 | Ngân sách & báo cáo | 1.5–2 tuần |
| 3 | Hoàn thiện & di chuyển dữ liệu | 1–1.5 tuần |
| 4 | Kiểm thử & phát hành CH Play | 1–2 tuần |
| 5 | Premium & mở rộng | Liên tục |

**Tổng thời gian tới khi có app trên CH Play (hết Phase 4):** khoảng 6–9 tuần làm việc bán thời gian đều đặn (nhanh hơn nếu làm toàn thời gian), tương ứng với năng lực bạn đã có sẵn từ việc từng xây web, app Android và app PC cùng Claude.

## Chi phí

Google Play Developer: 25 USD một lần. Firebase: miễn phí (gói Spark) ở quy mô gia đình/vài chục người dùng đầu; chỉ cần nâng gói Blaze khi số lượng người dùng hoặc lượng đọc/ghi Firestore tăng đáng kể. Không cần server riêng trong toàn bộ Phase 0–4.

## Rủi ro cần lưu ý

Google Play xét duyệt khắt khe hơn với app tài chính (Financial Services policy) dù đây chỉ là sổ ghi chép cá nhân, không kết nối ngân hàng — khai báo đúng mục đích sử dụng (Personal Finance/Tools, không phải Lending/Payments) để tránh bị yêu cầu giấy phép không cần thiết. Vì người dùng chính là dữ liệu tài chính gia đình, một lỗi đồng bộ sai (giao dịch của gia đình A lộ sang gia đình B) là rủi ro nghiêm trọng nhất về kỹ thuật — Security Rules và test rule ở Phase 0 phải được ưu tiên làm kỹ, không được bỏ qua để chạy nhanh MVP.
