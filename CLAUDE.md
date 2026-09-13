# CLAUDE.md — Hướng dẫn cho Claude khi làm việc trên dự án này

Đây là file định hướng cho Claude (hoặc bất kỳ ai/AI nào) khi bắt tay vào code dự án **app Quản lý Chi tiêu Gia đình**. Đọc `spec.md` để có đặc tả sản phẩm và lộ trình đầy đủ theo từng phase; file này chỉ nêu quy ước kỹ thuật và cách làm việc trong repo.

## 1. Tổng quan dự án

Ứng dụng Android (Flutter, phát hành qua CH Play/Google Play) giúp quản lý chi tiêu cá nhân hoặc chung giữa vợ chồng/gia đình, đồng bộ thời gian thực qua Firebase. Chuyển thể từ file Google Sheets "Quản lý tài chính 2026" hiện tại của chủ dự án sang app di động, giữ nguyên logic hạng mục (Sinh hoạt, Dâng hiến, Cho đi, Tự thưởng...) và quy trình trạng thái (Đã chuẩn bị/Đã gửi).

## 2. Ngăn xếp công nghệ (tech stack)

- **Frontend:** Flutter (Dart), state management bằng Riverpod, điều hướng bằng `go_router`.
- **Backend:** Firebase — Authentication, Cloud Firestore (nguồn dữ liệu chính, realtime + offline cache), Cloud Functions, Cloud Messaging, Firebase Storage.
- **Biểu đồ:** `fl_chart`. **Định dạng tiền tệ:** `intl` (VNĐ). **Khoá sinh trắc học:** `local_auth`. **Xuất báo cáo:** `excel`/`csv` + `share_plus`.

## 3. Kiến trúc thư mục (Clean Architecture rút gọn)

```
lib/
  presentation/   # screens, widgets, riverpod providers
  domain/         # entities, use cases (business logic thuần, không phụ thuộc Firebase)
  data/           # repositories, Firestore data sources, mapper DTO <-> entity
  core/           # DI, routing, theme, constants, utils
```

Nguyên tắc: `domain/` không được import bất cứ gì từ Firebase SDK — mọi truy cập Firestore đi qua interface repository ở `domain/`, implement cụ thể ở `data/`. Điều này giúp test logic nghiệp vụ (tính ngân sách, tổng hợp báo cáo) bằng unit test thuần, không cần Firebase emulator.

## 4. Quy ước code

Dùng `flutter_lints` (hoặc `very_good_analysis`) làm bộ lint chuẩn, không tắt rule trừ khi có lý do rõ ràng ghi chú trong code. Đặt tên file `snake_case.dart`, tên class `PascalCase`. Mỗi tính năng lớn (transactions, budgets, family) là một package con trong `presentation/features/`. Commit theo Conventional Commits (`feat:`, `fix:`, `chore:`...).

## 5. Lệnh thường dùng

```
flutter pub get                 # cài dependency
flutter run                     # chạy app (chọn thiết bị/emulator)
flutter test                    # chạy unit + widget test
flutter build appbundle         # đóng gói .aab để nộp Play Console
firebase emulators:start        # chạy Firestore/Auth emulator để test local, không đụng dữ liệu thật
```

## 6. Testing

Logic nghiệp vụ (tính tổng theo hạng mục, kiểm tra vượt ngân sách, tính tỷ lệ tiết kiệm) phải có unit test ở `domain/`. Màn hình quan trọng (thêm giao dịch, tổng hợp tháng) có widget test. Trước khi phát hành bản mới lên Play Console, chạy `flutter test` và tối thiểu test tay luồng: đăng nhập → tạo sổ chung → thêm giao dịch trên máy A → thấy realtime trên máy B.

## 7. Bảo mật — luôn ghi nhớ

Không bao giờ hardcode API key/secret trong code (dùng `.env` + `flutter_dotenv` hoặc Firebase config chuẩn, không commit file service account). Mọi thay đổi Firestore Security Rules phải giữ nguyên tắc: chỉ `memberIds` của một `family` mới đọc/ghi được dữ liệu family đó — xem chi tiết rule mẫu trong `spec.md` mục kiến trúc dữ liệu.

## 8. Quốc tế hoá (i18n) & thương hiệu — bắt buộc thiết kế từ đầu, không phải tính sau

App **không chỉ dành cho thị trường Việt Nam** — kiến trúc và thương hiệu phải sẵn sàng mở rộng đa ngôn ngữ/đa quốc gia ngay từ Phase 1, dù bản dịch tiếng Anh đầy đủ chỉ triển khai ở Phase 5 (xem `spec.md`).

- **Tên thương hiệu:** app có hai tên song song — **"Ví Nhà Mình"** (tên hiển thị cho locale tiếng Việt) và **"HomeWallet"** (tên quốc tế, dùng cho locale khác + làm tên gốc trong code/package). Không hardcode riêng một tên trong logic; tên hiển thị (app label, tiêu đề màn hình) phải đổi theo locale máy.
- **Không hardcode chuỗi text tiếng Việt trong widget.** Mọi label hiển thị (kể cả tên hạng mục mặc định như "Sinh hoạt", "Ăn uống"...) cuối cùng phải đi qua lớp localization (`flutter_localizations` + `.arb` files chuẩn Flutter), không viết thẳng chuỗi tiếng Việt trong `Text(...)`. Việc thêm ngôn ngữ mới sau này chỉ nên là thêm file `.arb`, không phải sửa lại từng widget.
- **Định dạng tiền tệ/ngày tháng qua `intl` theo locale**, không cộng cứng " đ" vào cuối số — hiện tại `Formatters.amount` đang hardcode VNĐ tạm thời cho Phase 1, cần thay bằng `NumberFormat.currency(locale: ..., symbol: ...)` khi làm i18n đầy đủ để hỗ trợ USD/EUR/... cho người dùng ở thị trường khác.
- **`applicationId`/package name giữ trung lập** (không gắn từ tiếng Việt), vì Android không cho đổi `applicationId` sau khi đã phát hành lên Play Store.

## 9. Hạng mục là dữ liệu, không phải hằng số cứng trong code — nguyên tắc bắt buộc

Sổ hiện tại của vợ chồng chủ dự án có "Cho đi", "Dâng hiến", và quy trình trạng thái Chưa chuẩn bị/Đã chuẩn bị/Đã dâng/Đã gửi — **đây là thói quen riêng của HỌ, không phải khái niệm chung cho mọi gia đình dùng app sau này.** Một gia đình khác có thể không có "Dâng hiến" mà có hạng mục hoàn toàn khác, và có thể không cần theo dõi trạng thái chuẩn bị/gửi chút nào — hoặc muốn bật trạng thái đó cho một hạng mục khác hẳn.

Vì vậy, **không bao giờ** viết logic kiểu `if (categoryId == 'cho_di')` hay `if (categoryId == 'dang_hien')` trong `domain/`/`presentation/`. Mọi hành vi đặc thù phải là **thuộc tính của `Category`** mà từng gia đình tự đặt khi tạo hạng mục:

- `statuses` (`List<String>`) — danh sách các bước trạng thái do CHÍNH gia đình đặt tên, theo đúng thứ tự họ muốn (vd Cho đi: `['Chưa chuẩn bị', 'Đã chuẩn bị', 'Đã gửi']`). **Không giới hạn số bước, không giới hạn tên bước** — gia đình khác có thể có 2 bước, 5 bước, tên hoàn toàn khác. Danh sách rỗng = hạng mục không theo dõi trạng thái. `hasStatus` chỉ là `statuses.isNotEmpty`, không phải field riêng để tránh 2 nguồn sự thật lệch nhau.
- `transferFrom` / `transferTo` (`FamilyMember?`) — chỉ hạng mục `kind == transfer` mới có, xác định ai bị trừ/ai được cộng, không hardcode theo tên hạng mục "Chồng đưa vợ".
- UI (màn hình Tổng hợp, sheet Thêm giao dịch) phải **lặp qua `category.statuses`** để tự sinh đúng số chip/dòng trạng thái tương ứng — không viết cứng "3 trạng thái" hay tên bước cụ thể ở bất kỳ đâu trong widget.

Giai đoạn hiện tại (Phase 1) code thẳng cho đúng 9 hạng mục mặc định của vợ chồng chủ dự án (xem `DefaultCategories` trong `core/constants/`) — điều đó **được phép** vì đây là dữ liệu seed mặc định, không phải logic hardcode. Khi lên Phase Premium/public (`spec.md` Phase 5 — "nhiều sổ chung"), việc mở khoá cho gia đình khác tự thêm/sửa hạng mục + tự đặt danh sách trạng thái qua UI phải hoạt động được **mà không cần sửa lại code** — vì cơ chế đã tách đúng từ đầu.

## 10. Gợi ý từ góc nhìn chuyên gia tài chính cá nhân — cân nhắc khi có thời gian

Vài ý tưởng nên cân nhắc thêm vào lộ trình (không bắt buộc làm ngay, ghi lại để không quên):

- **Quỹ (envelope budgeting) nên có mục tiêu + ETA, không chỉ số dư.** Với Quỹ tiền ăn hay quỹ tương lai (du lịch, hiếu hỉ...), thêm trường `targetAmount` tuỳ chọn — app tự tính "còn thiếu X, với tốc độ nạp hiện tại thì khoảng Y tháng nữa đạt mục tiêu". Đây là thứ khiến quỹ hữu ích hơn hẳn một cuốn sổ chi tiêu đơn thuần.
- **Cảnh báo ngân sách nên theo tốc độ tiêu, không chỉ ngưỡng %.** Thay vì chỉ báo "đã tiêu 80%", tính thêm "đến hôm nay đã qua 60% số ngày trong tháng nhưng đã tiêu 80% ngân sách" — cảnh báo sớm hơn nhiều so với đợi chạm mốc cố định.
- **Với hạng mục có `statuses` (như Cho đi/Dâng hiến): cảnh báo "già" trạng thái.** Một khoản ở bước đầu (`chưa chuẩn bị`) quá lâu (vd >7 ngày) nên được nhắc nhẹ — đúng mục đích ban đầu của trường trạng thái là không quên cam kết, không chỉ để ghi cho có.
- **Tỷ lệ Dâng hiến/Cho đi nên tính trên "Kế hoạch" (thường là % cố định của thu nhập), không chỉ trên số tiền đã ghi** — đúng như khối "Kế hoạch" trong sheet gốc; số kế hoạch này cũng nên là cấu hình do gia đình đặt (vd 10% thu nhập), không hardcode phần trăm trong code.
- **Xu hướng nhiều tháng quan trọng hơn 1 tháng đơn lẻ.** Một biểu đồ đường "tỷ lệ tiết kiệm theo tháng" trong 6-12 tháng gần nhất sẽ cho thấy insight thật (đang cải thiện hay đang xấu đi) mà một con số % của riêng tháng này không nói lên được.

## 11. Tài liệu liên quan

`spec.md` — đặc tả sản phẩm, mô hình dữ liệu, lộ trình theo phase, kế hoạch phát hành CH Play, tài chính domain logic (ngân sách, tỷ lệ tiết kiệm...). Đọc file đó trước khi bắt đầu bất kỳ phase nào.
