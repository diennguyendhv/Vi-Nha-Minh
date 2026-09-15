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

Sổ hiện tại của vợ chồng chủ dự án có "Cho đi", "Dâng hiến", và quy trình trạng thái Chưa chuẩn bị/Đã chuẩn bị/Đã dâng/Đã gửi — **đây là thói quen riêng của HỌ, không phải khái niệm chung cho mọi gia đình dùng app sau này.** Một gia đình khác có thể không có "Dâng hiến" mà có hạng mục hoàn toàn khác, và có thể không cần theo dõi trạng thái chuẩn bị/gửi chút nào — hoặc muốn bật trạng thái đó cho một hạng mục khác hẳn, kể cả "Sinh hoạt".

Vì vậy, **không bao giờ** viết logic kiểu `if (categoryId == 'cho_di')` hay `if (categoryId == 'dang_hien')` trong `domain/`/`presentation/`. Mọi hành vi đặc thù phải là **thuộc tính của `Category`** (bản vẽ đầy đủ ở [`docs/design.html`](docs/design.html)) mà từng gia đình tự đặt khi tạo hạng mục:

- **Phân loại gốc chỉ có Thu hoặc Chi** (`typeId`) — không còn `kind` nhiều giá trị (`income`/`expense`/`savings`/`transfer`) như bản nháp đầu. Tiết kiệm và 2 hạng mục chuyển khoản đều là danh mục thuộc Chi, phân biệt bằng 2 cờ dưới đây, không phải loại riêng.
- `isSaving` (`bool`) — chỉ có ý nghĩa khi `typeId` là Chi; đánh dấu category dùng cho tiết kiệm, giao dịch dưới category này mang thêm `savingsAction` (`topUp`/`withdrawToBalance`/`moveToBank`).
- `transferToUid` (`String?`) — chỉ hạng mục chuyển khoản mới có, xác định ai được cộng tiền (người bị trừ luôn là `spenderUid` của chính giao dịch đó) — không hardcode theo tên hạng mục "Chồng đưa vợ".
- `statuses` — **là subcollection `categories/{id}/statuses/{statusId}` (`name`, `sortOrder`), không phải mảng cứng trong 1 field.** Xem/thêm/sửa/xoá/sắp xếp qua UI (`docs/design.html` màn "Danh mục — Chỉnh sửa"), do CHÍNH gia đình đặt tên và thứ tự. **Không giới hạn số bước, không giới hạn tên bước** — gia đình khác có thể có 2 bước, 5 bước, tên hoàn toàn khác. Rỗng = hạng mục không theo dõi trạng thái. Giao dịch tham chiếu `statusId` (không phải chuỗi tự do) và **sửa được sau khi tạo** — trạng thái không cố định lúc ghi, người dùng đổi lại bất cứ lúc nào (vd hôm nay "Chưa chuẩn bị", mai đổi "Đã chuẩn bị").
- `statsEnabled` (`bool`) — bật/tắt việc category có hiện ở màn Tổng hợp trạng thái hay không. Nhiều category có `statuses` nhưng không phải cái nào cũng cần lên báo cáo tổng hợp thường xuyên.
- `fundId` (trên transaction, không phải trên category) — tuỳ chọn, gắn 1 giao dịch Chi với 1 Quỹ cụ thể; xem mục Quỹ bên dưới.
- UI (màn hình Tổng hợp, sheet Thêm giao dịch) phải **lặp qua `category.statuses`** để tự sinh đúng số chip/dòng trạng thái tương ứng — không viết cứng "3 trạng thái" hay tên bước cụ thể ở bất kỳ đâu trong widget.

**Khác với bản nháp đầu: CRUD danh mục/trạng thái là tính năng của Phase 1 (Giai đoạn A, xem `spec.md`), không đợi tới Phase Premium.** 9 hạng mục mặc định của vợ chồng chủ dự án (`DefaultCategories` trong `core/constants/`) chỉ là dữ liệu seed ban đầu — người dùng (kể cả bản demo hiện tại) đã xem/thêm/sửa/xoá được ngay từ đầu qua UI, không cần sửa code. Việc còn lại ở Phase Premium/public (`spec.md` Giai đoạn H) chỉ là cung cấp thêm bộ mẫu (template) tham khảo cho gia đình mới, cơ chế CRUD nền tảng đã có sẵn.

**Quỹ (`funds`) cũng là dữ liệu tạo được nhiều cái, không hardcode 1 "Quỹ tiền ăn" duy nhất.** Nạp quỹ và khoản chi tích 1 quỹ đều là **giao dịch Chi thật** (trừ số dư người thực hiện bình thường) kèm `fundId`, tự sinh `FUND_ENTRY` liên kết (`linkedTxId`) — khác bản nháp đầu (từng coi Quỹ là sổ con hoàn toàn tách biệt). Luôn kiểm tra `balance` quỹ trước khi cho chọn — **quỹ không bao giờ được phép âm**, kiểm tra cả ở client (UI khoá lựa chọn) lẫn server (Cloud Function từ chối nếu sẽ âm, tránh race condition 2 máy ghi cùng lúc).

**Công thức cân đối bắt buộc đúng ở mọi domain logic tổng hợp:** `Tổng thu = Tổng chi + Số tiền còn lại`, trong đó `Tổng chi = Chi phí + Tiết kiệm`. Vì tiết kiệm chỉ là 1 category có `isSaving = true`, phương trình đúng bằng cộng dồn số học đơn giản — không viết nhánh logic riêng cho tiết kiệm.

## 10. Gợi ý từ góc nhìn chuyên gia tài chính cá nhân — cân nhắc khi có thời gian

Vài ý tưởng nên cân nhắc thêm vào lộ trình (không bắt buộc làm ngay, ghi lại để không quên):

- **Quỹ (envelope budgeting) nên có mục tiêu + ETA, không chỉ số dư.** Với Quỹ tiền ăn hay quỹ tương lai (du lịch, hiếu hỉ...), thêm trường `targetAmount` tuỳ chọn — app tự tính "còn thiếu X, với tốc độ nạp hiện tại thì khoảng Y tháng nữa đạt mục tiêu". Đây là thứ khiến quỹ hữu ích hơn hẳn một cuốn sổ chi tiêu đơn thuần.
- **Cảnh báo ngân sách nên theo tốc độ tiêu, không chỉ ngưỡng %.** Thay vì chỉ báo "đã tiêu 80%", tính thêm "đến hôm nay đã qua 60% số ngày trong tháng nhưng đã tiêu 80% ngân sách" — cảnh báo sớm hơn nhiều so với đợi chạm mốc cố định.
- **Với hạng mục có `statuses` (như Cho đi/Dâng hiến): cảnh báo "già" trạng thái.** Một khoản ở bước đầu (`chưa chuẩn bị`) quá lâu (vd >7 ngày) nên được nhắc nhẹ — đúng mục đích ban đầu của trường trạng thái là không quên cam kết, không chỉ để ghi cho có.
- **Tỷ lệ Dâng hiến/Cho đi nên tính trên "Kế hoạch" (thường là % cố định của thu nhập), không chỉ trên số tiền đã ghi** — đúng như khối "Kế hoạch" trong sheet gốc; số kế hoạch này cũng nên là cấu hình do gia đình đặt (vd 10% thu nhập), không hardcode phần trăm trong code.
- **Xu hướng nhiều tháng quan trọng hơn 1 tháng đơn lẻ.** Một biểu đồ đường "tỷ lệ tiết kiệm theo tháng" trong 6-12 tháng gần nhất sẽ cho thấy insight thật (đang cải thiện hay đang xấu đi) mà một con số % của riêng tháng này không nói lên được.

## 11. Tài liệu liên quan

- `spec.md` — đặc tả sản phẩm, mô hình dữ liệu, lộ trình theo phase (76 phase, Giai đoạn A-H), kế hoạch phát hành CH Play, tài chính domain logic (ngân sách, tỷ lệ tiết kiệm...). Đọc file đó trước khi bắt đầu bất kỳ phase nào.
- `docs/design.html` — bản vẽ giao diện đã chốt: sơ đồ use case (9 nhóm/35 use case), ERD quan hệ (12 bảng, khớp `spec.md`), và 18 màn hình mô phỏng có tương tác (chọn/đổi trạng thái, CRUD danh mục, chọn quỹ có validate âm quỹ...). Mọi màn hình thật khi code phải khớp luồng trong file này; nếu cần đổi khác đi, cập nhật lại `docs/design.html` trước rồi mới đổi code, để 2 nơi không lệch nhau.
