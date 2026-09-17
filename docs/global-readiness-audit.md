# Phase 3.5 — Global Readiness Audit

**Ngày audit:** 2026-09-17
**Phạm vi:** Domain, Financial Engine, Repository contracts/implementation, Drift schema, Presentation (chỉ để phân loại, không sửa), tests, tài liệu (`spec.md`, `CLAUDE.md`, `docs/financial-core-v2.md`, `docs/design.html`).
**Quy tắc:** Đây là audit thuần tuý — **không có dòng code nào bị sửa** trong phase này. Mọi finding đều trích dẫn file:line cụ thể.

---

## 1. Executive Summary

Kiến trúc Financial Core (Domain + Financial Engine) đã được xây dựng **khá tốt cho global-readiness** ngay từ đầu — không phải vì được thiết kế riêng cho mục tiêu này, mà vì nguyên tắc "hạng mục/dữ liệu do gia đình tự tạo, không hardcode" (`CLAUDE.md` mục 9) và "amountMinor + currency" (`docs/financial-core-v2.md` F-08, dòng 127, dòng 515) đã được chốt từ audit trước khi code (`docs/audit-pre-implementation.md`).

**Điểm mấu chốt:** không có blocker nào nằm trong Financial Engine hay Database schema buộc phải sửa migration/refactor lớn. Toàn bộ VND/tiếng Việt hard-code hiện tại nằm ở **Presentation layer** (đúng vị trí, dễ sửa sau) hoặc là **default value/seed data** (thay được không phá dữ liệu). Vấn đề đáng chú ý nhất — `FamilyMember` là enum cố định 2 giá trị mang tên "vợ/chồng" — **đã được biết và chấp nhận từ trước** (`spec.md` phase 24, Giai đoạn B), không phải phát hiện bất ngờ của audit này; nhưng nó thực sự là giới hạn kiến trúc thật (N-member transfer chưa chạy được với N>2).

**Không có 🔴 GLOBAL BLOCKER nào trong Financial Core/Repository/Database** — mọi phát hiện nghiêm trọng nhất đều xếp 🟠/🟡, có smallest-safe-change rõ ràng, không đòi hỏi sửa migration đã có ở Phase 2.

---

## 2. Currency Audit

| Câu hỏi | Trả lời |
|---|---|
| Transaction có `currencyCode`? | **Có** — `Transaction.currency` (String, default `'VND'`), [transaction.dart:26,67](lib/domain/entities/transaction.dart#L26) |
| Family có `baseCurrency`? | **Không có Family entity nào cả** (đã xác nhận từ Phase 2: Giai đoạn A local-first = 1 gia đình ngầm định/máy, không có bảng `Family`) |
| Money có Value Object? | **Không** — `amountMinor` là `int` trần, không có class `Money` bọc `(amountMinor, currencyCode)` cùng nhau |
| `amountMinor` chỉ là integer hay gắn với currency? | Integer độc lập; `currency` là field **cùng cấp**, không phải thuộc tính của 1 Value Object — 2 field rời nhau trên `Transaction` |
| Financial Engine hard-code VND? | **Không** — `grep` toàn bộ `financial_engine.dart` không có literal `'VND'`/`đ`; `buildReversal`/`buildCorrection` chỉ copy `currency: original.currency` xuyên qua, không rẽ nhánh theo giá trị |
| Repository hard-code VND? | **Không** — `LocalTransactionRepository` chỉ map field `currency` qua lại (`_toDomain`/`_toCompanion`), không đọc/so sánh giá trị |
| Database biết currency? | **Có** — `TransactionRows.currency` (TEXT, default `'VND'`) [app_database.dart:44](lib/data/local/app_database.dart#L44) |
| Formatting tiền nằm trong Domain? | **Không** — nằm ở `lib/core/utils/formatters.dart` (Presentation-adjacent, đúng vị trí) |

### Phân loại

| Hạng mục | Phân loại |
|---|---|
| `amountMinor` là integer thuần, Financial Engine không biết currency | 🟢 SAFE |
| `Transaction.currency` mặc định hard-code `'VND'` trong constructor | 🟠 LOCAL ASSUMPTION (default value, không phải business rule) |
| `TransactionRows.currency` DB default `'VND'` | 🟠 LOCAL ASSUMPTION (default value, dễ đổi, không cần migration schema mới — chỉ đổi default) |
| Không có nơi enforce "1 family = 1 currency" | 🟠 IMPORTANT BEFORE UI — xem mục 3 |
| Không có `Family.baseCurrency` (vì chưa có bảng Family) | ⚪ FUTURE (đúng roadmap — Family chỉ tồn tại thật ở Giai đoạn B) |
| Formatter không nhân/chia theo `decimalDigits` của currency | 🟡 GLOBAL-LAUNCH TODO — xem mục 3/6 |

**Không có GLOBAL BLOCKER** trong currency model — nền tảng (`amountMinor` + `currency` tách biệt, Financial Engine mù currency) đã đúng hướng từ audit trước khi code.

---

## 3. Minor-Unit Audit

**Tìm kiếm:** `grep -rn "/ 100\|\* 100\|toStringAsFixed\|decimalDigits"` trong `lib/domain` và `lib/data`.

Kết quả duy nhất: `compute_three_totals.dart:26` và `compute_expense_breakdown.dart:12` — cả 2 đều là **tính phần trăm tiết kiệm/tỷ trọng chi tiêu** (`(x / total) * 100).round()`), **không liên quan đến số thập phân của tiền tệ**. Không có phép `/100` hay `.00` nào áp dụng lên `amountMinor` để "đổi ra đơn vị chính" — Financial Engine hoàn toàn không giả định số chữ số thập phân của currency.

**Vấn đề thật (không nằm ở Financial Engine mà ở Presentation):** `Formatters.amount` ([formatters.dart:8](lib/core/utils/formatters.dart#L8)) in thẳng `amountMinor` bằng `NumberFormat.decimalPattern` rồi nối `' đ'` — **ngầm giả định `decimalDigits = 0`** (đúng với VND, vốn không có hào/xu trong thực tế dùng), KHÔNG chia `amountMinor` cho `10^decimalDigits` trước khi hiển thị. Nếu tái sử dụng nguyên si formatter này cho 1 family dùng USD (2 decimal), số `1250` (= $12.50) sẽ hiển thị sai thành "1.250 đ" thay vì "$12.50".

### Phân loại

| Vấn đề | Vị trí | Phân loại |
|---|---|---|
| Financial Engine không có phép toán decimal-digit nào | `lib/domain/engine/financial_engine.dart` | 🟢 SAFE |
| `amountMinor` là `int` thuần trong Domain lẫn DB (`IntColumn`) | `transaction.dart`, `app_database.dart:26` | 🟢 SAFE |
| `Formatters.amount` giả định `decimalDigits = 0`, không currency-aware | [formatters.dart:8](lib/core/utils/formatters.dart#L8) | 🟡 GLOBAL-LAUNCH TODO (Presentation, không phải Domain — đúng vị trí, chỉ chưa tổng quát hoá) |

### Đánh giá mô hình "1 Family = 1 base currency" (mục 3 đề bài)

**Phù hợp với kiến trúc hiện tại**, với 1 lưu ý: hiện `currency` đang là field **của từng `Transaction`**, không phải của 1 `Family`/`FamilySettings` entity (vì Family chưa tồn tại như 1 bảng). Điều này về mặt kỹ thuật cho phép 2 transaction trong cùng 1 local DB có `currency` khác nhau — **không có gì chặn việc này**, dù hiện tại không xảy ra (UI luôn tạo `Transaction` với `currency` mặc định `'VND'`, không có currency picker). Đây không phải lỗi đã xảy ra, nhưng là 1 lỗ hổng invariant chưa được enforce.

**Khuyến nghị cho tương lai (KHÔNG implement ở phase này):** khi Giai đoạn A thêm 1 bảng nhỏ kiểu `FamilySettings`/`AppSettings` (1 dòng duy nhất, local) chứa `baseCurrencyCode`, mọi `Transaction` mới nên lấy `currency` từ đó thay vì hard-code default trong constructor — không cần sửa `TransactionRows.currency` (giữ nguyên cột, chỉ đổi NGUỒN giá trị default).

---

## 4. Locale / I18n Audit (Domain, Repository, Database, Financial Engine)

`grep -rn "locale\|Locale\|vi_VN\|vi-VN\|Intl\." lib/` → **duy nhất 1 kết quả**: [formatters.dart:6](lib/core/utils/formatters.dart#L6) `NumberFormat.decimalPattern('vi_VN')`.

- **Domain:** không có `locale` nào.
- **Repository (`local_transaction_repository.dart` và các repo khác):** không có.
- **Database (`app_database.dart`):** không có.
- **Financial Engine:** không có.

→ Locale hard-code **chỉ tồn tại ở đúng 1 điểm trong Presentation-adjacent utility** (`lib/core/utils/formatters.dart`), đúng như mục tiêu "Locale → Presentation Layer, không phải Locale → Financial Core". **Không phải architecture issue.**

### Phân loại
🟢 GLOBAL-READY cho Domain/Repository/Database/Financial Engine. 🟡 GLOBAL-LAUNCH TODO cho `formatters.dart` (cần đổi sang nhận `locale`/`currencyCode` làm tham số thay vì hard-code).

---

## 5. Language / I18n Audit (user-facing strings) — 4 nhóm

**A. Domain/internal identifiers** — không cần dịch:
`TransactionType.{income,expense,transfer}`, `PoolKind.{memberAvailable,memberSavingsAsset,fund,external}`, `TransferKind.*`, `SyncMode.{local,cloud}` — tất cả persist bằng `.name` (xem mục 6), không phải label. ✅ Đúng chuẩn.

**B. User-facing labels hard-code tiếng Việt** (cần localization tương lai — nằm ở Presentation, không phải Domain):
- `FamilyMember.label` = `'Vợ'`/`'Chồng'` — **đây là điểm lệch:** field này nằm NGAY TRONG domain entity ([family_member.dart:1-8](lib/domain/entities/family_member.dart)), không phải trong Presentation, nhưng lại là **display label** thuần tuý (không phải business identity — identity thật là `FamilyMember.name` = `'vo'`/`'chong'`, dùng làm `sourceRefId`/`destinationRefId`). `.label` được dùng trực tiếp ở **9 vị trí Presentation** (`summary_screen.dart`, `home_screen.dart`, `add_transaction_sheet.dart`, `savings_screen.dart`, `transaction_detail_screen.dart`) mà không qua bất kỳ lớp localization nào.
- Toàn bộ text trong `docs/design.html`, `lib/presentation/**` (vd "Thu"/"Chi"/"Chuyển", "Ghi chú", "Hôm nay", "Ví của...") — đúng vị trí (Presentation), nhưng hiện là chuỗi Việt cứng trong widget, vi phạm `CLAUDE.md` mục 8 ("Không hardcode chuỗi text tiếng Việt trong widget") — **đã được chính `CLAUDE.md` xác nhận là nợ kỹ thuật cố ý ("tạm thời cho Phase 1"), có kế hoạch sửa ở phase 74 (`spec.md` dòng 315, Giai đoạn Đa ngôn ngữ)**.

**C. User-created content** — không bị đụng tới ở đâu trong code hiện tại (không có logic nào tự dịch tên Category/Fund/SavingsAssetType do người dùng đặt). ✅ Đúng chuẩn.

**D. System seed/default content** (`DefaultCategories`, `DefaultFunds`, `DefaultSavingsAssetTypes`):
- Tên hiển thị (`name`) là tiếng Việt hard-code ("Sinh hoạt", "Quỹ tiền ăn", "Tiền mặt"...) — nhưng **`id` là khoá ổn định độc lập với `name`** (`sinh_hoat`, `an_uong`, `savings_cash`...) — xem mục 7/9, đây chính là điểm mấu chốt khiến seed data KHÔNG phải blocker: đổi `name` không phá `Transaction.categoryId` nào cả vì FK là theo `id`.

### Phân loại
| Nhóm | Vị trí | Phân loại |
|---|---|---|
| A (enum identity) | Domain | 🟢 GLOBAL-READY |
| B — `FamilyMember.label` trong Domain entity | [family_member.dart](lib/domain/entities/family_member.dart) | 🟡 GLOBAL-LAUNCH TODO (nên chuyển thành lookup trong localization layer thay vì field trong entity) |
| B — UI string hard-code | `lib/presentation/**`, `docs/design.html` | 🟡 GLOBAL-LAUNCH TODO (đã có kế hoạch — `spec.md` phase 74) |
| C (user content) | — | 🟢 GLOBAL-READY |
| D (seed `name`) | `default_*.dart` | 🟡 GLOBAL-LAUNCH TODO (cần bộ template đa ngôn ngữ — đã có hướng trong `CLAUDE.md` mục 9: "Phase Premium cung cấp thêm bộ mẫu tham khảo") |

---

## 6. Enum Persistence Audit

Kiểm tra `LocalTransactionRepository._toDomain`/`_toCompanion` ([local_transaction_repository.dart:26-76](lib/data/repositories/local_transaction_repository.dart#L26-L76)):

```dart
type: TransactionType.values.byName(row.type),        // DB lưu "income"/"expense"/"transfer"
sourceKind: PoolKind.values.byName(row.sourceKind),     // DB lưu "memberAvailable"/"fund"/...
transferKind: TransferKind.values.byName(...)           // DB lưu "memberToMember"/...
```

Tất cả persist bằng **`.name`** (chuỗi ổn định gắn với tên hằng số Dart, ví dụ `"income"`), **không phải index** (an toàn khi thêm/xoá/sắp xếp lại giá trị enum — thêm 1 `PoolKind` mới ở giữa danh sách không làm lệch dữ liệu cũ) và **không phải label đã dịch** (không bao giờ lưu "Thu"/"Income"/tiếng Nhật). Đây đúng chuẩn G-04 đề xuất.

**Ngoại lệ cần lưu ý:** `savingsAssetRefId()` ([pool_kind.dart:29-31](lib/domain/entities/pool_kind.dart#L29-L31)) ghép `'$assetTypeId|${member.name}'` — dùng `member.name` (= `'vo'`/`'chong'`, KHÔNG phải `.label`) làm 1 phần khoá persist → đúng chuẩn (không lưu label dịch).

### Phân loại
🟢 GLOBAL-READY toàn bộ enum persistence.

---

## 7. Category / Status Audit

| Câu hỏi | Trả lời |
|---|---|
| Default category tên tiếng Việt hard-code? | Có (`DefaultCategories`, [default_categories.dart](lib/core/constants/default_categories.dart)) — nhưng chỉ là **seed data**, CRUD đầy đủ từ Phase 1 (`CLAUDE.md` mục 9) |
| ID phụ thuộc tên? | **Không** — `id: 'sinh_hoat'` là hằng số riêng, không derive từ `name` runtime; đổi `name` qua UI không đổi `id` |
| Transaction reference category bằng ID hay text? | **Bằng ID** — `Transaction.categoryId` là FK tới `CategoryRows.id` (có FK thật từ Phase 2) |
| Rename category có phá lịch sử? | **Không** — `LocalCategoryRepository.updateCategory` chỉ update `name`/`color`/... không đụng `id`; giao dịch cũ vẫn `categoryId` y nguyên, chỉ đổi cách hiển thị |

### Đối chiếu với mô hình lý tưởng (mục 10 đề bài: System Category = stable key + localized label; User Category = user-entered name)

**Đã đạt phần "stable key" (id ≠ name).** Nhưng **CHƯA đạt phần "UI label localized"** cho SYSTEM category — hiện `name` VỪA LÀ khoá hiển thị VỪA LÀ dữ liệu (không có tầng "system category → tra `.arb` theo `id` để lấy label localized", mà hiển thị thẳng `category.name` đã lưu trong DB). Điều này **không phải blocker cấu trúc** (vì `id` đã tách biệt, sửa được sau bằng cách thêm 1 bảng lookup label hoặc convention `.arb` key = `category.id`), nhưng cần 1 quyết định thiết kế trước khi làm i18n thật: seed data tiếng Việt có nên được "dịch" hiển thị theo locale (yêu cầu thêm tầng lookup) hay giữ nguyên vì đã là **dữ liệu người dùng có thể tự sửa** (coi seed như 1 gợi ý ban đầu bằng tiếng Việt, không phải "system label")?

→ Đây là quyết định sản phẩm, không phải bug — nêu ra ở mục 15 (Global MVP Decision).

### Phân loại
| Vấn đề | Phân loại |
|---|---|
| `id` ≠ `name`, FK theo `id`, rename an toàn | 🟢 GLOBAL-READY |
| Seed category `name` tiếng Việt cứng, không có tầng label-lookup riêng | 🟡 GLOBAL-LAUNCH TODO |

---

## 8. Status Audit

`Status` ([status.dart](lib/domain/entities/status.dart)): `id`, `categoryId`, `name`, `sortOrder`. Hoàn toàn **user-created per category** (`CLAUDE.md` mục 9: "Không giới hạn số bước, không giới hạn tên bước"). `Transaction.statusId` reference bằng `id` (FK thật từ Phase 2), không bằng `name`. Seed status (`cho_di_chua_chuan_bi`...) cũng theo đúng pattern `id` ổn định + `name` hiển thị tiếng Việt — giống hệt Category.

Không có "system status" cứng nào trong Financial Engine (`isVisible`/`applyEffect` hoàn toàn không đọc `statusId`, đúng Invariant 9).

### Phân loại
🟢 GLOBAL-READY (giống Category, cùng pattern id/name tách biệt).

---

## 9. Savings Asset Type Audit

`DefaultSavingsAssetTypes` chỉ seed 2 loại ("Tiền mặt"/"savings_cash", "Ngân hàng"/"savings_bank") — nhưng **không phải enum cố định**, là **user-extendable data** giống Fund/Category (`SavingsAssetType` là 1 class với `id`/`name`/`color`, CRUD đầy đủ qua `LocalSavingsAssetTypeRepository`, không giới hạn số lượng — đúng nguyên tắc `CLAUDE.md` mục 9 "Không dùng lại MEMBER_SAVINGS_CASH/MEMBER_SAVINGS_BANK cố định"). Gia đình ở bất kỳ đâu có thể tự thêm "401k", "ISA", "Cổ phiếu"... mà không cần sửa code.

### Phân loại
🟢 GLOBAL-READY — kiến trúc đã đúng hướng "không giả định asset type phổ biến ở VN" từ thiết kế V2.

---

## 10. Family / Member Cultural Audit

`grep -rn "husband\|wife\|chồng\|vợ\|father\|mother\|bố\|mẹ\|male\|female" lib/` (case-insensitive) → 3 file: `family_member.dart`, `compute_member_outflow_breakdown.dart` (chỉ trong doc-comment giải thích, không phải logic), `settings_screen.dart` (1 UI string tĩnh "Vợ · Chồng đang đồng bộ").

**Phát hiện cốt lõi:** [family_member.dart](lib/domain/entities/family_member.dart):
```dart
enum FamilyMember {
  vo('Vợ'),
  chong('Chồng');
  ...
}
```

- **Financial Engine hoàn toàn KHÔNG biết `FamilyMember`** — `applyEffect`/`computeAllPoolBalances` chỉ thao tác `(PoolKind, String? refId)`, `refId` là `String` tự do, không ràng buộc kiểu `FamilyMember`. **`MEMBER_TO_MEMBER` transfer ở tầng Financial Engine hoạt động đúng với BẤT KỲ số lượng `refId` nào** — không có logic `husband → wife` cứng ở đây. ✅
- **Giới hạn thật nằm ở tầng UI/Usecase phía trên**, nơi code lặp `FamilyMember.values` (chỉ có 2 phần tử) hoặc dùng biến kiểu `FamilyMember` (`_transferFrom`/`_transferTo` trong `add_transaction_sheet.dart`, `compute_member_financials.dart`, `compute_member_outflow_breakdown.dart`) — với đúng 2 gia đình có 3+ thành viên, các hàm/UI này **không chạy được** (không phải "chạy sai", mà là **không có cách nào chọn thành viên thứ 3** vì kiểu dữ liệu chỉ có 2 giá trị).
- **Đây KHÔNG phải phát hiện mới** — `spec.md` (phase 24, Giai đoạn B) và bộ nhớ dự án đã ghi nhận: *"FamilyMember stays a fixed 2-value enum (vợ/chồng) through Giai đoạn A by design... the user was told this limitation clearly and accepted it."* Audit này xác nhận lại đúng phạm vi ảnh hưởng.

### Đối chiếu yêu cầu mục 13: "MEMBER_TO_MEMBER phải hoạt động với 2, 3, 5 members"
**Financial Core: ĐẠT.** **Domain enum + Usecase + UI: KHÔNG ĐẠT** (giới hạn cứng ở 2).

### Phân loại
| Layer | Vấn đề | Phân loại |
|---|---|---|
| Financial Engine (`applyEffect`, transfer logic) | `refId` tự do, không phụ thuộc `FamilyMember` | 🟢 GLOBAL-READY |
| Domain entity `FamilyMember` | Enum cố định 2 giá trị + label tiếng Việt hard-code trong entity | 🔴 GLOBAL BLOCKER **cho tính năng multi-member** (không phải cho Phase 4) — nhưng **đã được chấp nhận có chủ đích** cho Giai đoạn A, có kế hoạch sửa Giai đoạn B (`spec.md` phase 24) |
| Usecases (`compute_member_financials`, `compute_member_outflow_breakdown`) | Nhận tham số kiểu `FamilyMember`, không phải `String memberId` tự do | 🟡 GLOBAL-LAUNCH TODO (refactor cùng lúc với Giai đoạn B) |
| UI (person-toggle, `_transferFrom`/`_transferTo`) | Cứng 2 nút Vợ/Chồng | 🟡 GLOBAL-LAUNCH TODO (đã ghi nhận ở `docs/design.html` F-15: "không scale khi gia đình >2 người... giữ nguyên lộ trình cũ") |

**Kết luận mục này:** không cần hành động ngay ở Phase 3.5/4 — giữ nguyên quyết định đã chốt. Chỉ xác nhận lại phạm vi để Giai đoạn B không bị bất ngờ.

---

## 11. Date / Timezone Audit

**3 field cần phân biệt semantics** (`Transaction`):
- `transactionDate` — **business/calendar date**, người dùng chọn qua date-picker (`docs/design.html` màn 09), dùng để rollup tháng.
- `createdAt` — audit timestamp hệ thống (`DateTime.now()` lúc tạo bản ghi).
- `statusUpdatedAt` — audit timestamp hệ thống (lúc đổi status).

**Vấn đề phát hiện:** cả 3 field đều khai báo kiểu `DateTime` (Drift: `dateTime()` → lưu unix-epoch INTEGER, tức 1 **instant có time-of-day**, không phải date-only) — `transactionDate` **nên** là date-only về mặt semantics (theo đúng F-07: "ngày nghiệp vụ") nhưng lại được lưu trữ như 1 instant đầy đủ giờ/phút/giây.

Cụ thể ở [add_transaction_sheet.dart:113](lib/presentation/features/add_transaction/add_transaction_sheet.dart#L113):
```dart
DateTime _transactionDate = DateTime.now();  // mặc định: instant đầy đủ giờ/phút/giây
```
Nếu người dùng **không** bấm chọn ngày (giữ mặc định "Hôm nay"), `transactionDate` được gửi vào `Transaction` **kèm nguyên giờ:phút:giây hiện tại** — không phải `DateTime(year, month, day)` sạch. Nếu người dùng CÓ bấm `showDatePicker` ([add_transaction_sheet.dart:118-126](lib/presentation/features/add_transaction/add_transaction_sheet.dart#L118-L126)), Flutter trả về `DateTime` ở **00:00:00** của ngày được chọn. → **2 con đường tạo ra 2 dạng dữ liệu khác nhau cho cùng 1 field ý nghĩa "ngày nghiệp vụ".**

**Hiện tại KHÔNG có bug thật** vì:
- Không có `.toUtc()`/`.toLocal()` nào trong toàn bộ `lib/` (`grep` xác nhận 0 kết quả thực thi, chỉ có chữ "toLocal" xuất hiện trong 1 dòng comment giải thích).
- App là local-only, 1 device, 1 timezone — `DateTime.now()` luôn là giờ địa phương của đúng thiết bị đang dùng, đọc lại trên cùng thiết bị đó không có sai lệch.
- Rollup tháng (`computeThreeTotals`, `compute_member_outflow_breakdown`...) chỉ so `.year`/`.month`, không nhạy với phần giờ/phút/giây.

**Rủi ro tương lai (Giai đoạn B — đồng bộ Firestore, có thể nhiều device/timezone):** nếu 1 instant (không phải date-only) được đồng bộ giữa 2 thiết bị ở 2 timezone khác nhau và có bất kỳ bước `.toUtc()`/`.toLocal()` nào được thêm vào (rất có khả năng khi Firestore SDK serialize `Timestamp`), ngày hiển thị có thể lệch — đúng nguy cơ nêu ở mục 14 đề bài ("2026-09-17 tự biến thành 2026-09-16").

### Phân loại
| Vấn đề | Vị trí | Phân loại |
|---|---|---|
| `transactionDate` lưu như instant, không phải date-only, dù semantics là business date | `transaction.dart`, `app_database.dart`, `add_transaction_sheet.dart:113` | 🟠 IMPORTANT BEFORE UI mở rộng/cloud sync (chưa gây bug thật ở Giai đoạn A local-only, nhưng nên chuẩn hoá trước khi Giai đoạn B thêm timezone thật) |
| Không có `.toUtc()`/`.toLocal()` ở bất kỳ đâu | toàn bộ `lib/` | 🟢 SAFE cho hiện tại (nhất quán vì đơn giản), nhưng đồng nghĩa **chưa có chiến lược timezone** cho Giai đoạn B |
| `createdAt`/`statusUpdatedAt` là audit timestamp thuần, không trộn với business logic | Financial Engine không đọc 2 field này | 🟢 GLOBAL-READY |

**Smallest safe change đề xuất cho tương lai (KHÔNG làm bây giờ):** khi bắt đầu Giai đoạn B, chuẩn hoá `transactionDate` thành `DateTime(year, month, day)` (date-only, luôn 00:00:00, không timezone) NGAY LÚC TẠO ở Presentation (kể cả khi giữ mặc định "Hôm nay"), tách hẳn khỏi `createdAt`/`statusUpdatedAt` (giữ nguyên là instant UTC khi lên cloud).

---

## 12. Idempotency + Global Date (mục 16 đề bài)

Đã **freeze ở Phase 3.1**: `isSameLogicalTransaction` so cả `transactionDate` (cùng `note`, `statusId`) — **giữ nguyên, không đổi ở audit này**.

**Yêu cầu xác nhận lại cho Phase 4 (đã ghi trong IMPLEMENTATION NOTE cuối Phase 3.1, nhắc lại ở đây vì liên quan trực tiếp mục 16):**
> Một logical create command phải snapshot **`clientTxId` VÀ `transactionDate`** đúng 1 lần tại thời điểm người dùng bấm Lưu, tái sử dụng nguyên vẹn cho mọi lần retry. Hiện `add_transaction_sheet.dart:174` gọi `final now = DateTime.now();` **mỗi lần `_buildTransaction()` chạy** — nếu Phase 4 dùng lại đúng pattern này cho retry logic (gọi lại `_buildTransaction()` khi retry thay vì tái sử dụng object đã build), `transactionDate`/`createdAt` sẽ bị regenerate mỗi lần, gây `ClientTxIdConflictException` giả cho 1 retry hợp lệ.

### Phân loại
🟠 IMPORTANT BEFORE UI retry-logic (Phase 4 Application layer phải snapshot request 1 lần, không rebuild mỗi lần gọi repository).

---

## 13. Default / Seed Data Audit

| Seed data | Nội dung | Phân loại |
|---|---|---|
| `DefaultCategories` (10 category + status con) | "Sinh hoạt", "Cho đi"("CĐ"), "Dâng hiến"("DH")... | **SYSTEM DEFAULT** (không phải test fixture) — phản ánh thói quen ghi sổ CỦA VỢ CHỒNG CHỦ DỰ ÁN cụ thể (`CLAUDE.md` mục 9 tự xác nhận rõ điều này), nhưng **id ổn định + CRUD đầy đủ** nên KHÔNG phải "production system identity" khoá cứng — gia đình khác **đã xoá/sửa được ngay từ Phase 1** |
| `DefaultFunds` (1 quỹ "Quỹ tiền ăn") | Tiếng Việt | SYSTEM DEFAULT, sửa/xoá được |
| `DefaultSavingsAssetTypes` (2 loại) | "Tiền mặt", "Ngân hàng" | SYSTEM DEFAULT, sửa/xoá được |
| Test fixtures (`test/**`) | `'vo'`/`'chong'` string literal, category id tiếng Việt (`'cat1'` trung lập, nhưng dùng lại `DefaultCategories` ở vài chỗ) | TEST — không ảnh hưởng production |

**Kết luận:** seed data hiện tại **KHÔNG phải blocker** vì đã tách `id` khỏi `name` và có CRUD đầy đủ (không giống 1 hệ thống mà "Cho đi"/"Dâng hiến" là khái niệm cứng không xoá được). Vấn đề duy nhất là **trải nghiệm ban đầu** của 1 gia đình ngoài VN sẽ thấy toàn bộ danh mục mặc định bằng tiếng Việt cho tới khi tự sửa — đây là sản phẩm/UX quyết định (có bộ template theo ngôn ngữ hay không), không phải kiến trúc sai.

### Phân loại
🟡 GLOBAL-LAUNCH TODO (cần bộ seed/template theo locale trước khi launch toàn cầu — đã có hướng đi ở `CLAUDE.md` mục 9, Giai đoạn Premium/public).

---

## 14. Test Assumptions Audit

`grep` cho `'VND'`/`'vo'`/`'chong'`/`vi_VN`/"2 members" trong `test/`:

| File | Assumption | Harmless fixture hay Architecture assumption? |
|---|---|---|
| `test/domain/compute_usecases_test.dart` | `memberRefId = 'vo'` mặc định trong helper `_income()`/`_expense()` | **Harmless fixture** — chỉ là giá trị test, hàm dưới test (`computeMemberFinancials`...) nhận `String`/`FamilyMember` tổng quát, không assert riêng cho "vo"/"chong" |
| `test/domain/financial_engine_test.dart` | Không tìm thấy literal VND/vo/chong trong core Financial Engine test — test dùng `PoolKind`/`refId` string tự do (`'fund1'`, `'a'`, `'b'`...) | 🟢 Không có assumption văn hoá nào — đúng vì Financial Engine tự nó không biết member là gì |
| `test/data/repositories/local_transaction_repository_test.dart` | `destinationRefId: 'vo'` mặc định trong `buildTx()` helper | **Harmless fixture** — string tự do, không test riêng hành vi 2-member |
| `test/data/local/app_database_test.dart` | Không có assumption văn hoá | — |

**Không tìm thấy** test nào assert cứng "phải đúng 2 member", "phải là VND", "phải định dạng dd/MM/yyyy", hay "phải 2 chữ số thập phân" ở tầng Domain/Financial Engine/Repository/Database. Toàn bộ test hiện tại dùng string/số nguyên tự do cho refId/amount — **không cần rewrite** theo yêu cầu mục 24 đề bài.

### Phân loại
🟢 GLOBAL-READY — bộ test hiện tại không khoá kiến trúc vào giả định địa phương nào.

---

## 15. Privacy Architecture Notes (chỉ audit kiến trúc, không kết luận pháp lý)

| Thành phần | Trạng thái hiện tại |
|---|---|
| Local-only | **Có** — Giai đoạn A hoàn toàn local SQLite, chưa có network call nào |
| Cloud sync | Chưa có — `main.dart` comment rõ "Firebase.initializeApp() sẽ được bật... khi có project Firebase thật" ([main.dart:8-9](lib/main.dart#L8)) |
| Account/đăng nhập | Chưa có |
| Analytics | Không có bất kỳ package/call nào |
| Crash reporting | Không có |
| Tracking | Không có |

**Thành phần tương lai sẽ ảnh hưởng privacy khi global (đánh dấu để lưu ý, không implement):**
- Cloud sync (Giai đoạn B) — dữ liệu tài chính gia đình rời khỏi thiết bị, cần xem xét vị trí đặt Firebase region, chính sách lưu trữ theo khu vực (không kết luận pháp lý ở đây).
- Account (Google Sign-In, Giai đoạn B) — thu thập định danh người dùng.
- Backup/Restore, Import CSV (Giai đoạn F) — nếu xuất file có thể chứa dữ liệu tài chính nhạy cảm.
- Chia sẻ sổ qua mã mời (Giai đoạn B) — quan hệ nhiều người dùng cùng 1 tập dữ liệu.

### Phân loại
🟢 GLOBAL-READY cho trạng thái hiện tại (local-only, không thu thập gì). ⚪ FUTURE — cần đánh giá privacy khi bắt đầu Giai đoạn B, không phải bây giờ.

---

## 16. Regional Business Rules Audit (mục 23 đề bài)

`grep -rn "Vietnam\|Việt Nam\|if.*vietnam" lib/domain lib/data` (case-insensitive) → **0 kết quả** trong Financial Engine/Domain/Data. Không có bất kỳ `if (region == ...)`/`if (country == 'VN')` nào trong business logic. Financial Core hoàn toàn region-neutral về mặt code (dù seed data/label là tiếng Việt — đã phân loại ở mục 5/7/13).

### Phân loại
🟢 GLOBAL-READY.

---

## 17. Global MVP vs Future — Decision Table (mục 25 đề bài)

| CAPABILITY | GLOBAL MVP | FUTURE |
|---|---|---|
| `amountMinor` + `currency` tách biệt trên Transaction | ✅ Đã có (Phase 1) | — |
| Currency mặc định lấy từ `FamilySettings.baseCurrencyCode` thay vì hard-code `'VND'` | GLOBAL MVP | — |
| Formatter currency-aware (số decimal theo `currencyCode`, ký hiệu `$`/`€`/`đ` theo locale) | GLOBAL MVP | — |
| English localization (`.arb`, `flutter_localizations`) | GLOBAL MVP (đã có kế hoạch — `spec.md` phase 74) | — |
| Locale-aware date/number formatting | GLOBAL MVP | — |
| Seed category/fund/savings-type theo locale/template | GLOBAL MVP (tối thiểu: English template) | Bộ template phong phú (Premium) → FUTURE |
| `FamilyMember` tổng quát hoá (N thành viên, `roleLabel` tự do) | — | FUTURE (đã lên lịch Giai đoạn B phase 24, KHÔNG cần cho Global MVP nếu MVP vẫn nhắm hộ gia đình 2 người) |
| `transactionDate` chuẩn hoá date-only, tách hẳn timezone khỏi `createdAt` | GLOBAL MVP (nên làm SỚM, trước khi có cloud sync) | — |
| Multi-currency ledger (1 family dùng nhiều currency cùng lúc) | — | FUTURE |
| FX conversion | — | FUTURE |
| Historical exchange rates | — | FUTURE |
| Nhiều gia đình/family switching trên 1 device | — | FUTURE |
| Cloud sync | — | FUTURE/theo roadmap Giai đoạn B hiện có |

---

## 18. Proposed Global Architecture Invariants (đề xuất — chưa implement)

| Mã | Invariant | Trạng thái hiện tại |
|---|---|---|
| G-01 | Financial Core không biết locale | ✅ Đạt |
| G-02 | Financial Core không format currency | ✅ Đạt |
| G-03 | Money calculation dùng integer minor units | ✅ Đạt |
| G-04 | Persistent enum identity không dùng translated label | ✅ Đạt |
| G-05 | Member transfer không phụ thuộc husband/wife (ở Financial Engine) | ✅ Đạt ở Financial Engine; ⚠️ CHƯA đạt ở Domain entity `FamilyMember` (có chủ đích, xem mục 10) |
| G-06 | Business date và audit timestamp là 2 semantics khác nhau | ⚠️ Khác nhau về Ý NGHĨA nhưng CHƯA khác nhau về REPRESENTATION (cả 2 đều lưu instant đầy đủ giờ/phút/giây) — xem mục 11 |
| G-07 | Retry reuse `clientTxId` + `transactionDate` | ✅ Đã freeze ở Phase 3.1 (`isSameLogicalTransaction`); ⚠️ cần Phase 4 tuân thủ đúng khi implement retry (xem mục 12) |
| G-08 | Một family chỉ có một base currency trong Global MVP | ⚠️ Chưa có nơi enforce (vì chưa có Family entity) — không vi phạm (vì cũng chưa có tính năng đổi currency), nhưng cần quyết định trước khi thêm currency picker |
| G-09 | Currency formatting thuộc Presentation | ✅ Đạt (Formatters ở `lib/core/utils`, không phải Domain) |
| G-10 | System default identity độc lập localized label | ✅ Đạt cho Category/Status/Fund/SavingsAssetType (`id` ≠ `name`); ⚠️ CHƯA đạt cho `FamilyMember.label` (label nằm trong entity, không tách lớp lookup) |

---

## 19. Issues by Severity — Tổng hợp

### 🔴 GLOBAL BLOCKER
*(Không có blocker mới nào đòi hỏi hành động ngay trước Phase 4.)*
- `FamilyMember` cố định 2 giá trị — là blocker THẬT cho tính năng multi-member, nhưng **đã được chấp nhận có chủ đích, đã lên lịch Giai đoạn B** (`spec.md` phase 24). Không hành động thêm ở Phase 3.5/4.

### 🟠 IMPORTANT BEFORE UI (nên xử lý trước khi Phase 4/UI mở rộng thêm)
1. Không có nơi enforce "1 family = 1 base currency" trước khi thêm currency picker (mục 2/3, G-08).
2. `transactionDate` lưu như instant đầy đủ giờ/phút/giây thay vì date-only, dù mặc định "Hôm nay" và date-picker cho ra 2 dạng dữ liệu khác nhau (mục 11, G-06).
3. Phase 4 phải snapshot `clientTxId` + `transactionDate` đúng 1 lần cho mỗi logical create command, không rebuild `DateTime.now()` mỗi lần retry (mục 12, G-07) — **đã ghi trong IMPLEMENTATION NOTE Phase 3.1**.

### 🟡 GLOBAL-LAUNCH TODO (không cần bây giờ, cần trước khi launch toàn cầu)
1. `Formatters.amount` hard-code `vi_VN` + hậu tố `' đ'`, không currency-aware (mục 3/6).
2. `FamilyMember.label` hard-code tiếng Việt ngay trong Domain entity, dùng trực tiếp ở 9 nơi Presentation không qua localization (mục 5/10, G-10).
3. Toàn bộ string UI tiếng Việt hard-code trong `lib/presentation/**` (đã có kế hoạch — `spec.md` phase 74, `CLAUDE.md` mục 8).
4. Seed data (Category/Fund/SavingsAssetType) chỉ có bản tiếng Việt, chưa có template theo locale khác (mục 7/13).
5. Usecases (`compute_member_financials`, `compute_member_outflow_breakdown`) nhận tham số kiểu `FamilyMember` thay vì `String memberId` tổng quát — cần refactor cùng lúc Giai đoạn B phase 24.

### ⚪ FUTURE MULTI-CURRENCY
- Multi-currency ledger, FX conversion, historical exchange rates, `Money` Value Object bọc `(amountMinor, currencyCode)` — không cần cho Global MVP theo đúng mục 4 đề bài.

### 🟢 GLOBAL-READY
- Financial Engine (toàn bộ): không biết locale/currency/member culture.
- Enum persistence (`.name`, không phải index/translated label).
- Category/Status/Fund/SavingsAssetType: `id` ≠ `name`, FK theo `id`, CRUD đầy đủ, không giới hạn số lượng.
- Repository/Database: không hard-code VND trong logic (chỉ default value).
- Test suite: không khoá cứng giả định văn hoá/tiền tệ nào.
- Không có regional `if` nào trong Financial Core.
- Privacy: local-only, không thu thập gì ở trạng thái hiện tại.

---

## 20. Recommended Actions Before Phase 4

**Không có action bắt buộc phải làm TRƯỚC Phase 4** — Phase 4 (Application/Use Cases) hoạt động trên Repository contract đã "FROZEN" ở Phase 3.1, và không có 🔴 blocker nào trong chính Repository/Financial Core/Database buộc phải sửa trước.

**Duy nhất 1 điều cần Phase 4 tuân thủ ngay từ khi thiết kế** (không phải "sửa trước", mà là "làm đúng ngay từ đầu"): khi implement use case tạo giao dịch có cơ chế retry, **snapshot `clientTxId` và `transactionDate` một lần** ở đầu logical command, không gọi lại `DateTime.now()`/generate `clientTxId` mới cho mỗi lần retry — đúng theo IMPLEMENTATION NOTE đã ghi ở cuối Phase 3.1 và nhắc lại ở mục 12 báo cáo này.

Mọi mục 🟡/⚪ khác đều có thể xử lý ở phase sau (i18n, currency picker, Giai đoạn B) mà không đòi hỏi migration/refactor lớn lên phần đã build (Phase 1-3.1), vì nền tảng (`amountMinor`+`currency` tách biệt, enum persist bằng `.name`, `id`≠`name` cho mọi entity có seed data, Financial Engine mù văn hoá/locale) đã đúng hướng từ đầu.

---

## FINAL VERDICT

# GLOBAL ARCHITECTURE = READY FOR PHASE 4

Không có 🔴 GLOBAL BLOCKER nào trong Domain, Financial Engine, Repository contract, hay Database schema. Các phát hiện 🟠/🟡 đều nằm ngoài phạm vi Phase 4 (Application/Use Cases) hoặc đã có kế hoạch xử lý ở giai đoạn phù hợp (Giai đoạn B, i18n phase 74). Phase 4 có thể bắt đầu trên nền Repository contract đã frozen, chỉ cần tuân thủ đúng 1 lưu ý idempotency+date đã nêu ở mục 12/20.
