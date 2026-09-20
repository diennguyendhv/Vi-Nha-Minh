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

Vì vậy, **không bao giờ** viết logic kiểu `if (categoryId == 'cho_di')` hay `if (categoryId == 'dang_hien')` trong `domain/`/`presentation/`. Mọi hành vi đặc thù phải là **thuộc tính của `Category`** (bản vẽ đầy đủ ở [`docs/design.html`](docs/design.html), Financial Core ở [`docs/financial-core-v2.md`](docs/financial-core-v2.md)) mà từng gia đình tự đặt khi tạo hạng mục:

- **`Category` chỉ là nhãn để nhóm báo cáo — không quyết định tiền chạy đi đâu.** `category.type` chỉ có 3 giá trị: `INCOME`/`EXPENSE`/`TRANSFER`. Tiết kiệm, Quỹ, chuyển khoản giữa thành viên đều là category `type = TRANSFER` — **không phải Chi** (khác hẳn 1 bản nháp cũ hơn từng gộp chúng vào Chi, đã sửa vì làm sai Tổng chi/dòng tiền, xem `docs/financial-core-v2.md` mục F-01/F-02).
- **Dòng tiền thật nằm trên `Transaction`, không nằm trên `Category`:** mỗi giao dịch có `sourceKind`/`sourceRefId` (tiền lấy từ đâu: `MEMBER_AVAILABLE`, `MEMBER_SAVINGS_ASSET` (1 loại tài sản tiết kiệm tự do do gia đình tạo — xem `SavingsAssetType` bên dưới, không phải 2 kind cố định), `FUND`, hoặc `EXTERNAL`) và `destinationKind`/`destinationRefId` (tiền tới đâu, cùng enum). 1 hàm Financial Engine duy nhất (`applyEffect`) xử lý mọi giao dịch — không viết nhánh if/else riêng cho quỹ/tiết kiệm/chuyển khoản ở bất kỳ đâu.
- `statuses` — **là subcollection `categories/{id}/statuses/{statusId}` (`name`, `sortOrder`), không phải mảng cứng trong 1 field.** Xem/thêm/sửa/xoá/sắp xếp qua UI (`docs/design.html` màn "Danh mục — Chỉnh sửa"), do CHÍNH gia đình đặt tên và thứ tự. **Không giới hạn số bước, không giới hạn tên bước.** Giao dịch tham chiếu `statusId` (không phải chuỗi tự do), sửa được sau khi tạo. **Status không bao giờ ảnh hưởng balance** — đổi trạng thái chỉ là đổi nhãn, tuyệt đối không gọi tới Financial Engine.
- `statsEnabled` (`bool`) — **LEGACY, không còn UI/ngữ nghĩa** (mục 17): Tổng hợp không dựa vào cờ này; mọi giao dịch đều lọc/tổng hợp được. Giữ cột DB (không migration), chỉ bảo toàn giá trị khi lưu.
- UI (màn hình Tổng hợp, sheet Thêm giao dịch) phải **lặp qua `category.statuses`** để tự sinh đúng số chip/dòng trạng thái tương ứng — không viết cứng "3 trạng thái" hay tên bước cụ thể ở bất kỳ đâu trong widget.

**Khác với bản nháp đầu: CRUD danh mục/trạng thái là tính năng của Phase 1 (Giai đoạn A, xem `spec.md`), không đợi tới Phase Premium.** 9 hạng mục mặc định của vợ chồng chủ dự án (`DefaultCategories` trong `core/constants/`) chỉ là dữ liệu seed ban đầu — người dùng (kể cả bản demo hiện tại) đã xem/thêm/sửa/xoá được ngay từ đầu qua UI, không cần sửa code. Việc còn lại ở Phase Premium/public (`spec.md` Giai đoạn H) chỉ là cung cấp thêm bộ mẫu (template) tham khảo cho gia đình mới, cơ chế CRUD nền tảng đã có sẵn.

**Quỹ (`funds`) là dữ liệu tạo được nhiều cái, không hardcode 1 "Quỹ tiền ăn" duy nhất.** Quỹ là 1 "pool" tiền như `MEMBER_AVAILABLE` — không có subcollection `entries` riêng, lịch sử quỹ = lọc `transactions` theo `sourceRefId`/`destinationRefId = fundId`. Nạp quỹ là `TRANSFER` (trừ `MEMBER_AVAILABLE` người nạp, cộng `FUND`); **chi tiêu dùng quỹ chỉ trừ đúng 1 pool là quỹ, tuyệt đối không đụng số dư người mua** (bản nháp cũ hơn từng trừ cả 2 — lỗi trừ kép đã sửa, xem `docs/financial-core-v2.md` mục F-03/test case 7). `MEMBER_AVAILABLE` và mọi pool đều **không bao giờ được phép âm**, kiểm tra cả client (UI khoá lựa chọn) lẫn server (Cloud Function từ chối nếu sẽ âm, trong 1 Firestore Transaction để tránh race condition 2 máy ghi cùng lúc).

**Chuyển tiền cho thành viên khác là 1 luồng chung, không phải category cố định theo từng cặp người.** Chọn người nhận từ danh sách thành viên khi ghi giao dịch (`sourceRefId` = người đang ghi, `destinationRefId` = người được chọn) — chạy đúng với bất kỳ số lượng thành viên nào, không cần thêm category mới khi gia đình có người thứ 3 trở lên.

**Sửa/xoá giao dịch dùng reversal ledger — `Transaction` là append-only.** Không bao giờ `UPDATE`/xoá cứng 1 giao dịch đã tồn tại. Sửa/xoá đều tạo bản ghi mới (`reversalOfTxId`/`correctsTxId`), đánh dấu `reversedByTxId` lên bản gốc thay vì mutate nó. Chi tiết ở `docs/financial-core-v2.md` mục 21.

**Công thức tài chính:** `Total Income`, `Total External Expense`, `Total Transfer` là 3 tổng **tách biệt hoàn toàn** — Transfer không bao giờ được cộng vào Income/Expense. `Tổng tài sản = Tổng tài sản đầu kỳ + Total Income − Total External Expense` (Transfer tự cân bằng nội bộ, không xuất hiện trong công thức). Không dùng công thức "Tổng thu = Tổng chi + Số tiền còn lại" của bản nháp đầu — công thức đó tự mâu thuẫn vì gộp cả Transfer vào Chi. Chi tiết ở `docs/financial-core-v2.md` mục 17.

**`SavingsAssetType` là mô hình Tiết kiệm DUY NHẤT** — loại tài sản tiết kiệm (Gửi ngân hàng, Vàng, Chứng khoán...) là dữ liệu gia đình tự tạo không giới hạn số lượng, y hệt nguyên tắc Category/Fund. **Tiền mặt và tiền trong tài khoản ngân hàng dùng hằng ngày KHÔNG phải loại tiết kiệm** — cả hai đều là tiền khả dụng (`MEMBER_AVAILABLE`); "Gửi ngân hàng" là tiền gửi tiết kiệm/sinh lời (quyết định chủ dự án 2026-09-19). **Không dùng lại** `MEMBER_SAVINGS_CASH`/`MEMBER_SAVINGS_BANK`/`SAVINGS_TO_BANK` (model cũ, cố định 2 loại) ở bất kỳ đâu — nếu thấy 3 tên này xuất hiện lại trong code/tài liệu mới, đó là dấu hiệu quay lại model sai, cần sửa ngay. Chi tiết ở `docs/financial-core-v2.md` mục 9.

**Reversal ledger có thêm 3 ràng buộc bắt buộc** (Invariant 13-15, `docs/financial-core-v2.md` mục 18): không được hoàn tác 2 lần trên cùng 1 giao dịch; sửa nhiều lần liên tiếp luôn thao tác trên bản mới nhất (`reversedByTxId == null`), không bao giờ trên bản gốc; giao dịch Transfer không được có source = destination. **Fund → Fund** và **Savings người A → Savings người B** trực tiếp **chưa hỗ trợ trong MVP** (đi qua rút/chuyển/nạp lại) — đây là quyết định phạm vi có chủ đích, không phải thiếu sót.

## 10. Gợi ý từ góc nhìn chuyên gia tài chính cá nhân — cân nhắc khi có thời gian

Vài ý tưởng nên cân nhắc thêm vào lộ trình (không bắt buộc làm ngay, ghi lại để không quên):

- **Quỹ (envelope budgeting) nên có mục tiêu + ETA, không chỉ số dư.** Với Quỹ tiền ăn hay quỹ tương lai (du lịch, hiếu hỉ...), thêm trường `targetAmount` tuỳ chọn — app tự tính "còn thiếu X, với tốc độ nạp hiện tại thì khoảng Y tháng nữa đạt mục tiêu". Đây là thứ khiến quỹ hữu ích hơn hẳn một cuốn sổ chi tiêu đơn thuần.
- **Cảnh báo ngân sách nên theo tốc độ tiêu, không chỉ ngưỡng %.** Thay vì chỉ báo "đã tiêu 80%", tính thêm "đến hôm nay đã qua 60% số ngày trong tháng nhưng đã tiêu 80% ngân sách" — cảnh báo sớm hơn nhiều so với đợi chạm mốc cố định.
- **Với hạng mục có `statuses` (như Cho đi/Dâng hiến): cảnh báo "già" trạng thái.** Một khoản ở bước đầu (`chưa chuẩn bị`) quá lâu (vd >7 ngày) nên được nhắc nhẹ — đúng mục đích ban đầu của trường trạng thái là không quên cam kết, không chỉ để ghi cho có.
- **Tỷ lệ Dâng hiến/Cho đi nên tính trên "Kế hoạch" (thường là % cố định của thu nhập), không chỉ trên số tiền đã ghi** — đúng như khối "Kế hoạch" trong sheet gốc; số kế hoạch này cũng nên là cấu hình do gia đình đặt (vd 10% thu nhập), không hardcode phần trăm trong code.
- **Xu hướng nhiều tháng quan trọng hơn 1 tháng đơn lẻ.** Một biểu đồ đường "tỷ lệ tiết kiệm theo tháng" trong 6-12 tháng gần nhất sẽ cho thấy insight thật (đang cải thiện hay đang xấu đi) mà một con số % của riêng tháng này không nói lên được.

## 11. Tài liệu liên quan

- `spec.md` — đặc tả sản phẩm, mô hình dữ liệu, lộ trình theo phase (76 phase, Giai đoạn A-H), kế hoạch phát hành CH Play, tài chính domain logic (ngân sách, tỷ lệ tiết kiệm...). Đọc file đó trước khi bắt đầu bất kỳ phase nào.
- `docs/financial-core-v2.md` — **đọc trước khi viết bất kỳ dòng domain logic nào liên quan tới tiền.** Audit đầy đủ các lỗi tài chính đã sửa (trừ kép ở Quỹ, Transfer bị tính nhầm thành Chi...), model `Transaction` với `source`/`destination`, 15 invariant bắt buộc đúng, 20 test case (double-count + reversal ledger) phải pass trước khi merge bất kỳ PR nào đụng tới Financial Engine. Đây là **source of truth cao nhất cho business logic tài chính** — nếu `spec.md`/`CLAUDE.md`/`docs/design.html` có chỗ nào mâu thuẫn với file này, sửa lại theo file này.
- `docs/design.html` — bản vẽ giao diện: sơ đồ use case, ERD, màn hình mô phỏng có tương tác. Đã đồng bộ theo model V2 ở `financial-core-v2.md` (đợt rà soát `docs/audit-pre-implementation.md`, 2026-09-16) — mọi màn hình thật khi code phải khớp luồng trong file này; nếu cần đổi khác đi, cập nhật lại `docs/design.html` trước rồi mới đổi code, để các tài liệu không lệch nhau.
- `docs/audit-pre-implementation.md` — audit trước-khi-code: đối chiếu toàn bộ `spec.md`/`CLAUDE.md`/`financial-core-v2.md`/`design.html`/code hiện có, liệt kê mọi mâu thuẫn/BLOCKER đã tìm thấy và cách đã sửa. Tham khảo nếu cần hiểu tại sao 1 đoạn tài liệu được viết như hiện tại.

## 12. Phase 8.8 — Đơn giản hoá sản phẩm (4 nhóm Thu/Chi)
Người dùng chỉ thấy 2 tầng: 4 nhóm chính cố định (Doanh thu · Khoản thu khác · Chi tiêu · Chi phí kinh doanh) → danh mục con tự tạo. Nhóm Thu suy từ `excludeFromTotals`; nhóm Chi suy từ `Category.groupKey` (`business_expense`, schema v7). KHÔNG phân nhóm theo tên/Ghi chú. Vay & Cho vay và Hoàn tiền/Thu hồi là tính năng nâng cao: engine giữ nguyên, entry point UI ẩn sau `advancedFeaturesEnabledProvider` (mặc định tắt) + `AdvancedSystemCategories` (ID hệ thống). Chi tiết ở `docs/phase-8.8-simplification-audit.md` và `docs/financial-core-v2.md` cuối file.

## 13. Vòng đời Danh mục/Trạng thái & Trang chủ tối giản
- **UNUSED master data → xóa hẳn được; USED → chỉ ngừng sử dụng.** Category/Status đã ngừng và chưa từng được giao dịch nào tham chiếu (kể cả đã hoàn tác) có thể xóa khỏi DB (`deleteCategoryPermanently` / `deleteStatusPermanently`, kiểm tra lại trong 1 DB transaction; Category còn cần: không phải Chuyển/danh mục hệ thống nâng cao, không ai trỏ `linkedExpenseCategoryId`, các bước con chưa từng dùng). Đã dùng → KHÔNG hard-delete, lịch sử vẫn resolve tên. UI không dùng thuật ngữ kỹ thuật; chỉ hiện "Xóa hẳn" khi an toàn. Không bao giờ chạm giao dịch/ledger.
- **Trang chủ = 8 câu trả lời nhanh**, không phải báo cáo: Thu nhập tháng này / Số dư hiện tại / Tiết kiệm của Vợ và Chồng, Chi tiêu gia đình, Quỹ tiền ăn (id ổn định `DefaultFunds.anUongId`). Dùng lại `computeMemberNetIncome`, `computeMemberFinancials`, `computeGroupedTotals(...).spending`, `computeFundBalance` — không tự tính lại. Tổng tài sản/Net Worth/Vay/Recovery… chỉ ẩn ở UI (Engine giữ nguyên).

## 14. Savings 2 tầng (Option A2)
Savings Total = tổng dẫn xuất mọi pool `memberSavingsAsset` của từng thành viên; "Chưa phân bổ" là tài sản hệ thống ảo `savings_unallocated` (KHÔNG có row DB, KHÔNG schema/migration, KHÔNG `PoolKind` mới, KHÔNG đổi `applyEffect`). Thêm vào tiết kiệm = Khả dụng → Chưa phân bổ; phân bổ = `SAVINGS_CONVERT`. Không rải `if (id == 'savings_unallocated')` — chỉ resolve qua `resolveSavingsAsset`. Bất biến thành viên và guard hoàn tác không-âm nằm ở tầng ghi (Invariant 16–17, `docs/financial-core-v2.md`); lifecycle loại tài sản theo luật chung "chưa từng dùng + đã ngừng → xoá hẳn được".

## 15. Xóa giao dịch = XÓA THẬT (thay thế "delete = reversal")
Hành động người dùng "Xóa giao dịch" xóa VẬT LÝ dòng + cả họ (gốc/hoàn tác/thay thế) trong 1 DB transaction; số dư tính lại từ các dòng còn lại; KHÔNG tạo giao dịch hoàn tác. Bị chặn (không ghi gì, không cascade) khi làm pool âm (`DeleteWouldOverdrawException`) hoặc dính Vay/Hoàn tiền (`TransactionDeleteBlockedException`). Điều này thay thế ghi chú cũ "Transaction là append-only — sửa/xoá đều tạo bản ghi mới" ở mục 9: reversal/correction chỉ còn dùng cho SỬA số tiền/người và nghiệp vụ Vay. Vòng đời Danh mục/Trạng thái/Loại tài sản dựa trên dữ liệu HIỆN TẠI (xóa hết giao dịch dùng nó → xóa hẳn được ngay). Danh sách "an toàn xóa hẳn" ở UI suy ra trực tiếp từ dữ liệu đang xem — KHÔNG dùng stream `customSelect('SELECT 1')` riêng (Drift không phát lại khi kết quả giống hệt → hiển thị cũ). Bất biến `status.categoryId == transaction.categoryId`. Chi tiết: `docs/financial-core-v2.md` Invariant 18–19.

## 16. Sửa giao dịch = thay dòng; Category/Status bị chặn xóa phải chỉ ra giao dịch giữ nó
- **Sửa** số tiền/người = THAY dòng cũ bằng dòng mới (id + clientTxId mới) trong 1 DB transaction (`updateTransaction`): xoá cả họ cũ (dữ liệu legacy) rồi ghi dòng mới, rollback nếu lỗi/pool âm. KHÔNG tạo reversal/correction mới khi user sửa. Sửa ghi chú/ngày/trạng thái/danh mục (không đổi số dư) update tại chỗ. Đổi danh mục xóa trạng thái cũ (UI đặt null ngay, repo enforce lại — Invariant `status.categoryId == transaction.categoryId`).
- **Blocker**: xóa/sửa làm pool âm ném `DeleteWouldOverdrawException`/`ChangeWouldOverdrawException` kèm `blockingTransactionIds`; UI mở `showBlockingTransactions` (ngày · số tiền · [Mở giao dịch]). Danh mục/Trạng thái chưa xóa được dùng `DeletionCheckResult` (`domain/usecases/deletion_check.dart`) — không để UI tự đoán từ nhiều query.
- **`linkedExpenseCategoryId` là metadata legacy** (không còn ngữ nghĩa trong mô hình 4 nhóm, ẩn khỏi UI): không chặn xóa danh mục; `deleteCategoryPermanently` gỡ liên kết trỏ tới nó trong cùng transaction.
- Lịch sử ẩn legacy (gốc/hoàn tác) giữ danh mục/trạng thái → nút "Dọn lịch sử đã xóa" (`purgeDeletedHistory[ForStatus]`): họ đã xóa → xoá cả họ; họ còn dòng hiệu lực → xoá dòng ẩn, giữ dòng sống, bỏ `correctsTxId` treo (số dư không đổi).
- Backlog: REVIEW clientTxId / tombstone / idempotency TRƯỚC khi đồng bộ Firebase hai người dùng.
- Backlog nhỏ (chưa làm): màn Sửa danh mục nên giải thích VÌ SAO "Ngừng sử dụng" bị chặn; trường `linkedExpenseCategoryId` ẩn nên gỡ hẳn khỏi Presentation; ca tay Vay/Hoàn tiền trên Pixel là kiểm tra nâng cao tuỳ chọn.

## 17. Tổng hợp / Transaction Explorer kiểu Excel
- **Tổng hợp = TỔNG QUAN (vài con số tháng này) + GIAO DỊCH (Explorer)**. Explorer lọc `exploreTransactions` với `TransactionFilter`: OR trong cùng chiều (nhiều Danh mục, nhiều Trạng thái kể cả "Không có trạng thái"), AND giữa các chiều (Thời gian · Vợ/Chồng · Danh mục · Trạng thái · Ghi chú). **Các chiều ĐỘC LẬP** — không chiều nào tự xoá chiều khác; thứ tự chọn không đổi kết quả; giao rỗng ⇒ 0 dòng, bộ lọc giữ nguyên.
- Thời gian = `TimeSelection` (Ngày/Tháng/Năm/Tất cả, so theo ngày lịch; **không có khoảng ngày** — quyết định sản phẩm). Bấm chip Ngày/Tháng/Năm luôn về KỲ HIỆN TẠI (hôm nay/tháng này/năm nay); mũi tên lùi/tiến để sang kỳ khác. Sắp xếp CHỈ theo **Ngày** hoặc **Số tiền** (tăng/giảm, 1 tiêu chí trên UI — chọn 2 tiêu chí làm rối giao diện; `SortKey` không có Người/Danh mục/Trạng thái), tie-break ổn định (Ngày ↓, giờ tạo ↓, id). **Không có lọc theo số tiền** (quyết định sản phẩm) — chỉ sắp xếp.
- **Thẻ Tổng quan** (Thu nhập ròng Vợ/Chồng, Chi tiêu gia đình) theo KỲ THỜI GIAN đang chọn (`computeMemberNetIncome/computeGroupedTotals(from:, to:)`, dùng chung `inReportPeriod`); KHÔNG theo Danh mục/Trạng thái/Ghi chú — phần đó là tổng của Explorer bên dưới.
- Trạng thái trùng tên ở 2 danh mục vẫn là 2 id — bộ chọn hiển thị "ĐD · Cho đi". Danh mục/Trạng thái đã ngừng chỉ hiện trong bộ chọn khi còn giao dịch dùng.
- Không có cờ "hiển thị thống kê": user quyết định bằng bộ lọc. Nhóm chính (4 nhóm) chỉ còn dùng để NHÓM hiển thị trong bộ chọn danh mục, không phải bộ lọc bắt buộc.

