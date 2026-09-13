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

## 8. Tài liệu liên quan

`spec.md` — đặc tả sản phẩm, mô hình dữ liệu, lộ trình theo phase, kế hoạch phát hành CH Play, tài chính domain logic (ngân sách, tỷ lệ tiết kiệm...). Đọc file đó trước khi bắt đầu bất kỳ phase nào.
