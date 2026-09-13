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

**Mô hình dữ liệu Firestore:**

```
families/{familyId}
  name, createdAt, memberIds: [uid1, uid2]

families/{familyId}/members/{uid}
  displayName, roleLabel ("Vợ"/"Chồng"/tuỳ chỉnh), joinedAt

families/{familyId}/categories/{categoryId}
  name, icon, color, type ("income" | "expense"), isDefault

families/{familyId}/transactions/{txId}
  type ("income" | "expense"), categoryId, amount, note,
  spenderUid, date, status ("prepared" | "sent" | null), createdBy, createdAt

families/{familyId}/budgets/{yearMonth}
  categoryLimits: { categoryId: amount }
```

Trường `type` ở `categories` và `transactions` chính là phần bổ sung "thu nhập" nói ở trên — về sau mọi tính năng tỷ lệ tiết kiệm/báo cáo dòng tiền đều dựa vào trường này.

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
**Công việc:** Tạo/tham gia Sổ chung qua mã mời; CRUD giao dịch với đầy đủ trường `type` (thu/chi), hạng mục, số tiền, ghi chú, người chi, ngày, trạng thái; danh mục mặc định dựng từ sheet hiện tại (Sinh hoạt, Ăn uống, Di chuyển, Tự thưởng, Dâng hiến, Cho đi, Tiết kiệm) và cho thêm danh mục tuỳ chỉnh; danh sách giao dịch theo tháng nhóm theo ngày; đồng bộ realtime hai chiều giữa các thành viên; hoạt động offline nhờ Firestore local cache, tự đồng bộ khi có mạng lại.
**Tiêu chí hoàn thành:** Vợ thêm giao dịch trên điện thoại → chồng thấy ngay trên máy của mình mà không cần refresh; tắt mạng vẫn nhập được, bật mạng lại tự đồng bộ không mất dữ liệu.
**Thời gian ước tính:** 2–3 tuần.

### Phase 2 — Ngân sách & Báo cáo tài chính
**Mục tiêu:** Từ "ghi chép" tiến lên "quản lý" — đúng tinh thần tài chính cá nhân thực sự.
**Công việc:** Đặt ngân sách theo hạng mục/tháng và cảnh báo khi đạt 80%/100% ngân sách; màn hình Tổng hợp với biểu đồ tròn theo hạng mục và biểu đồ đường theo tháng; các chỉ số tài chính chủ chốt tính tự động — tỷ lệ tiết kiệm (Thu − Chi)/Thu, tỷ lệ Dâng hiến/Cho đi trên tổng thu, hạng mục chi nhiều nhất; nhắc nhở nhập chi tiêu hàng ngày qua thông báo đẩy.
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
