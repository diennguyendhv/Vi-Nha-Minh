# Account / Wallet / Security Foundation — Audit & Kiến trúc (Phase P1)

> **CẬP NHẬT SAU P1 (2026-09-21, P2):** chủ dự án đã DUYỆT P1 và chốt các quyết định mở (xem "Phụ lục C" cuối tài liệu).
> Nếu một đoạn phía dưới còn ghi "OPEN"/"đề xuất" trái với Phụ lục C thì **Phụ lục C thắng**.

> Trạng thái: **AUDIT + THIẾT KẾ — chưa triển khai gì.** Không đổi schema, không thêm Firebase, không chạm dữ liệu thật.
> Tài liệu này KHÔNG chứa số liệu tài chính thật (số tiền, số dư, số giao dịch cụ thể). Mọi con số ở đây là số schema/số file trong mã nguồn.
> Ngày audit: 2026-09-21. Mã nguồn tham chiếu: nhánh `master`, schema Drift **v7**.

---

## 1. Kiến trúc cục bộ hiện tại (đã đọc trực tiếp từ mã nguồn)

### 1.1 Lưu trữ
- **1 file SQLite duy nhất**: `<app documents>/vi_nha_minh.sqlite` (`lib/data/local/app_database.dart`, `_openConnection()`), mở bằng `NativeDatabase.createInBackground`, `PRAGMA foreign_keys = ON` mỗi lần mở. Seed chỉ chạy khi file được **tạo mới** (`details.wasCreated`).
- 7 bảng Drift: `transaction_rows`, `category_rows`, `status_rows`, `fund_rows`, `savings_asset_type_rows`, `counterparty_rows`, `obligation_rows`.
- Cài đặt cục bộ: `SharedPreferences` chỉ có **2 khóa**: `primary_fund_id` và `explorer_sort`. Mọi thứ khác (bộ lọc Tổng hợp, tab hiện tại, `biometricLockProvider`, `syncModeProvider`, `advancedFeaturesEnabledProvider`) chỉ nằm trong bộ nhớ hoặc là hằng số.
- Firebase: `firebase_core`, `firebase_auth`, `cloud_firestore` **đã khai báo trong `pubspec.yaml` nhưng chưa được khởi tạo/import ở đâu** (chỉ có 1 dòng comment trong `main.dart`); **không có `google-services.json`**. `local_auth` cũng đã khai báo nhưng **không được gọi**.
- *(Trạng thái P1, đã lỗi thời từ P3/P5 — nay có `INTERNET` và `allowBackup=false`.)* Manifest chính (`android/app/src/main/AndroidManifest.xml`): **không có quyền `INTERNET`** (chỉ có ở debug/profile) và **không đặt `android:allowBackup`** ⇒ mặc định `true` (thiết bị báo cờ `ALLOW_BACKUP`).

### 1.2 Danh tính thành viên hiện tại
- `FamilyMember { vo, chong }` (`lib/domain/entities/family_member.dart`) — enum cứng, dùng ở **23 file** trong `lib/`.
- Trong DB, thành viên chỉ tồn tại dưới dạng **chuỗi**: `'vo'`, `'chong'` nằm trong `source_ref_id` / `destination_ref_id` khi `*_kind = memberAvailable`, và trong khóa ghép `"<assetTypeId>|<vo|chong>"` khi `*_kind = memberSavingsAsset` (`savingsAssetRefId`). **Không có bảng thành viên, không có khóa ngoại.**
- ID bản ghi: `IdGenerator.generate()` = `"<micro giây>-<số ngẫu nhiên 32 bit>"`; ID nhập từ Excel là tất định (`imp:<băm workbook>:...`). `client_tx_id` có `UNIQUE` toàn DB.
- Bản ghi giao dịch có `created_at`, `version` (mặc định 1) nhưng **không có** `updated_at`, `created_by`, `updated_by`.

### 1.3 Trả lời các câu hỏi của mục 14
| Câu hỏi | Trả lời |
|---|---|
| DB hiện là 1 Wallet ngầm định? | **Có.** Toàn bộ file = 1 Wallet ngầm định, không có khái niệm ranh giới sở hữu. |
| Vợ/Chồng chỉ là enum/giá trị? | **Có.** Enum + chuỗi trong cột ref; không có bảng, không có ID ổn định riêng. |
| Bảng nào chưa có phạm vi sở hữu? | **Cả 7 bảng.** Không bảng nào có `walletId`/`ownerId`. |
| Dữ liệu nào ai mở app cũng thấy? | **Tất cả** (không có khoá màn hình ứng dụng, `biometricLockProvider` chỉ là công tắc giả mặc định `true`, không thực thi). |

### 1.4 Phân loại dữ liệu theo phạm vi tương lai (mục 14 + 40)
| Dữ liệu | Hiện tại | Phạm vi tương lai | Ghi chú |
|---|---|---|---|
| `transaction_rows` | không phạm vi | **WALLET DATA** | thêm `createdByAccountId` (chỉ ở cloud/metadata, xem §13) |
| `category_rows` – danh mục người dùng/nhập Excel (`isDefault=false`) | không phạm vi | **WALLET DATA** | đồng bộ |
| `category_rows` – 8 danh mục hệ thống có ID cố định (`chuyen_tien_thanh_vien`, `nap_quy`, `tiet_kiem`, `cho_vay`, `lai_cho_vay`, `vay_no`, `tra_no`, `hoan_tien_thu_hoi`) | có dòng trong DB, `isDefault=true` | **APP INFRASTRUCTURE** | **không đồng bộ như bản ghi người dùng**; sinh từ danh mục hằng số của app + `systemCatalogVersion` |
| `status_rows` | không phạm vi | **WALLET DATA** | thứ tự `sort_order` là dữ liệu ví |
| `fund_rows` (kể cả Quỹ tiền ăn `an_uong`) | không phạm vi | **WALLET DATA** | quỹ thuộc ví, không thuộc 1 thành viên |
| `savings_asset_type_rows` (kể cả `savings_bank`) | không phạm vi | **WALLET DATA** | |
| `savings_unallocated` | **không có dòng DB** | **VIRTUAL/DERIVED** | không bao giờ đồng bộ/lưu; sinh bởi `resolveSavingsAsset` |
| `counterparty_rows`, `obligation_rows` | không phạm vi | **WALLET DATA** (tính năng nâng cao, đang ẩn) | |
| Danh tính thành viên (`vo`/`chong`) | chuỗi trong cột ref | **WALLET DATA — cần bảng riêng** | xem §6 |

Kết luận: **toàn bộ 7 bảng phải trở thành dữ liệu của 1 Wallet**, riêng các dòng danh mục hệ thống là hạ tầng ứng dụng.

---

## 2. Khoảng trống về sở hữu & bảo mật hiện tại (rủi ro)

| # | Rủi ro | Mức | Cách xử lý (phase) |
|---|---|---|---|
| R1 | Không có khái niệm Wallet/Owner: không thể nói "dữ liệu này của ai" | Cao | P2 |
| R2 | Danh tính Vợ/Chồng là enum + chuỗi, không có ID thành viên ổn định ⇒ không thể gắn tài khoản vào thành viên | Cao | P2, P4 |
| R3 | Ai cầm điện thoại đã mở khoá là xem/sửa được hết; công tắc "khoá vân tay" là **giả** (không lưu, không thực thi, mặc định bật) | Cao (dữ liệu tiền thật) | P3 |
| R4 | `allowBackup` mặc định `true` ⇒ DB có thể bị sao lưu tự động lên Google Drive / `adb backup` ngoài ý muốn | Trung–Cao | P3 (đặt `allowBackup=false` + `dataExtractionRules`) |
| R5 | DB không mã hoá (dựa vào sandbox Android + FBE); bản debug cho phép `run-as` đọc DB | Trung (bản release ổn hơn) | Quyết định mở §18.3 |
| R6 | Đổi tài khoản trên cùng máy chưa có ranh giới dữ liệu (chỉ có 1 file DB) | Cao khi có Account | P6 |
| R7 | Manifest chính thiếu `INTERNET` ⇒ bản release không thể gọi Firebase | Thấp (chỉ là việc phải nhớ) | P5 |
| R8 | ID sinh cục bộ (`micro giây + 32 bit ngẫu nhiên`) đủ cho 1 người nhưng yếu khi 2 người ghi song song, không có UUID | Thấp–Trung | §20 |
| R9 | Xóa vật lý không để lại dấu vết ⇒ đồng bộ sẽ "hồi sinh" dòng đã xoá nếu không có tombstone | Cao (khi sync) | §21, P9 |
| R10 | `spec.md` + `CLAUDE.md` mục 7 mô tả mô hình cũ `families/{familyId}` + `memberIds:[uid]` (danh tính = uid) — **mâu thuẫn** mô hình Wallet/memberId đã khoá | Trung | cập nhật tài liệu khi chủ dự án duyệt (§27) |
| R11 | Importer debug + route nhập còn trong bản debug | Đã có gate CLAUDE.md §19 | gỡ trước Play |
| R12 | Log/ghi chú/số tiền có thể lọt vào log khi thêm Crashlytics | Trung | §24 (chính sách) |

---

## 3. Quyết định sản phẩm đã KHOÁ (chỉ ghi lại, không bàn lại)

1. **Wallet** là container tài chính; đúng **1 Owner**; tối đa **1 Member** thêm; Family v1 ≤ 2 người.
2. Danh tính tài chính = **`memberId` ổn định**. Email **không** phải danh tính tài chính; `accountId/uid` cũng **không** phải danh tính sở hữu tài chính.
3. **Owner ≠ Chồng**, Member ≠ Vợ. Owner/Member = **quyền**; Vợ/Chồng = **người**. Cả hai cách (Vợ làm Owner / Chồng làm Owner) phải chạy.
4. Personal và Family dùng **cùng một mô hình Wallet** (Personal = 1 FinancialMember, 0 Member thêm).
5. Chỉ Owner quản trị thành viên: mời, huỷ lời mời, thay tài khoản Member, thu hồi ngay, quản lý gói. Member **không** thể thêm người thứ 3, thay Owner, tự đổi ràng buộc, tự nâng quyền. **Phải cưỡng chế phía máy chủ.**
6. Mỗi giao dịch phân biệt 3 danh tính: `walletId`, `memberId` (ai chịu tác động tài chính), `createdByAccountId` (ai bấm lưu).
7. Thay tài khoản Member **giữ nguyên `memberId` và toàn bộ lịch sử**; không chuyển giao dịch từ UID cũ sang UID mới.
8. Có 2 luồng khác nhau: **thay thế an toàn** (mời tài khoản mới, chấp nhận mới đổi) và **thu hồi ngay**.
9. Family v1: cả Owner và Member thấy **toàn bộ** Wallet chung; không có "giao dịch riêng tư".
10. **Một tài khoản – một thiết bị hoạt động** tại một thời điểm.
11. Local SQLite vẫn là nguồn vận hành; UI không đọc Firestore trực tiếp.

---

## 4. Mô hình Account

```
Account                         (Firebase Auth user)
  accountId (= Firebase uid)
  email                         (chỉ để liên hệ/đăng nhập, KHÔNG là khoá dữ liệu tài chính)
  authProviders[]
  createdAt
  session/current { installationId, generation, sessionSecretHash, activatedAt, active } ← §21
```

- Account chỉ là **danh tính xác thực + thiết bị**. Nó không "chứa" dữ liệu tài chính; nó **có quyền truy cập** vào Wallet thông qua Membership.
- Một Account về cấu trúc có thể có nhiều Wallet (Personal + Family sau này); UI v1 chỉ hiện 1 ví hoạt động (§16).

## 5. Mô hình Wallet

```
Wallet
  walletId                      (ngẫu nhiên 128-bit, tạo 1 lần, KHÔNG suy ra từ uid/email)
  kind                          LOCAL | PERSONAL | FAMILY   (LOCAL = chưa gắn Account)
  ownerAccountId                (null khi LOCAL; do máy chủ ghi khi claim; bất biến sau đó trừ luồng chuyển quyền tương lai)
  systemCatalogVersion          (§26)
  createdAt
  entitlement                   (chỉ máy chủ ghi: gói, hạn)
```

- `ownerAccountId` **không nằm trong tài liệu client-ghi được**; nó được suy ra từ Membership có `accessRole = OWNER`. Có đúng 1 dòng OWNER.

## 6. Mô hình FinancialMember (danh tính tài chính ổn định)

```
FinancialMember
  memberId                      (chuỗi ổn định, KHÔNG BAO GIỜ đổi, không bao giờ dùng lại)
  walletId
  displayName / roleLabel       (Vợ, Chồng, hoặc tên tuỳ chọn — dữ liệu, không hardcode)
  linkedAccountId               (nullable — tài khoản hiện đang đại diện; đổi được)
  slotState                     UNLINKED | INVITED | ACTIVE
```

- Wallet có **1 hoặc 2** FinancialMember (Personal: 1; Family: 2). Tối đa 2 dòng, cưỡng chế ở máy chủ và ở lớp ghi cục bộ.
- **Lịch sử tài chính thuộc `memberId`.** `linkedAccountId` chỉ trả lời "hiện giờ ai điều khiển slot này".
- **Với dữ liệu thật hiện có:** `memberId` của 2 thành viên cũ được đặt **đúng bằng token cũ `vo` / `chong`**. Nhờ đó **không phải viết lại bất kỳ giao dịch nào** (các cột ref đã chứa đúng `vo`/`chong`, kể cả khóa ghép tiết kiệm `assetTypeId|vo`). Ví mới tạo sau này dùng `memberId` ngẫu nhiên.

## 7. Mô hình Membership / Access

```
Membership   (wallets/{walletId}/memberships/{accountId})
  walletId, accountId
  memberId                      (slot tài chính mà tài khoản này đại diện)
  accessRole                    OWNER | MEMBER
  state                         INVITED | ACTIVE | REVOKED
  since, revokedAt?
```

**Bất biến (phải test):**
- I1. Mỗi Wallet có **đúng 1** Membership `OWNER` ở trạng thái `ACTIVE`.
- I2. Mỗi Wallet có **tối đa 1** Membership `MEMBER` ở trạng thái `ACTIVE` hoặc `INVITED` (đồng thời).
- I3. Mỗi `memberId` có **tối đa 1** Membership `ACTIVE`.
- I4. Owner luôn gắn với **đúng 1 FinancialMember** (không có Owner "vô hình").
- I5. `accountId` xuất hiện **tối đa 1 lần** trong Membership ACTIVE của cùng Wallet.
- I6. Chấp nhận lời mời **không bao giờ tạo FinancialMember mới**; chỉ gắn `accountId` vào `memberId` **đã tồn tại** do lời mời trỏ tới (điều kiện sống còn của mục 21 đề bài).
- I7. `memberId`, `walletId` của mọi bản ghi tài chính không đổi khi Membership đổi.

**Phân biệt hai trường hợp đổi tài khoản (mục 12 đề bài):**
| Trường hợp | Hiện tượng | Xử lý |
|---|---|---|
| A. Cùng tài khoản đổi email | `uid` giữ nguyên | **Không** cần rebind Membership; chỉ cập nhật email trong Account |
| B. Tài khoản/UID khác hẳn | UID mới | Rebind slot qua luồng thay thế (§11) hoặc thu hồi + mời lại (§12) |

Thuật ngữ UI: **"Đổi tài khoản thành viên"**, không dùng "Đổi email".

## 8. Quyền của Owner

Chỉ Owner (Membership `OWNER`, `ACTIVE`) được: mời 1 Member theo email; huỷ lời mời đang chờ; **thay tài khoản** Member; **thu hồi ngay**; quản lý gói (entitlement); chọn/đổi slot của chính mình khi slot kia còn `UNLINKED` (§19); (tương lai) chuyển quyền Owner — **không có trong v1**.

## 9. Quyền của Member

Member (Membership `MEMBER`, `ACTIVE`) được: đọc/ghi giao dịch và dữ liệu chính của Wallet trong phạm vi tài chính bình thường (thêm/sửa/xoá giao dịch, danh mục, trạng thái, quỹ, tiết kiệm — **như Owner** ở v1, vì cả hai thấy toàn Wallet). **Không** được: mời/thay/huỷ thành viên; đổi `accessRole`; đổi `walletId`/`ownerAccountId`; đổi ràng buộc `linkedAccountId` của mình hay người khác; ghi vào `entitlement`.

---

## 10. Vòng đời lời mời (Invite lifecycle)

Trạng thái slot: `UNLINKED → INVITED → ACTIVE` (và `ACTIVE → UNLINKED` khi thu hồi).

```
Invite  (wallets/{walletId}/invites/{inviteId})
  inviteId              (ngẫu nhiên 128-bit)
  memberId              (slot đích — ĐÃ tồn tại)
  kind                  INITIAL | REPLACEMENT
  targetEmailNormalized (chữ thường, cắt khoảng trắng; KHÔNG chuẩn hoá dot/+ của Gmail)
  tokenHash             (băm SHA-256 của token dùng 1 lần; token thật chỉ gửi qua kênh mời)
  state                 PENDING | ACCEPTED | CANCELLED | EXPIRED
  createdBy(=Owner), createdAt, expiresAt (mặc định 7 ngày), acceptedByAccountId?
```

Quy trình:
1. Owner nhập email ⇒ **Cloud Function** `createInvite` (Owner-only) ghi Invite `PENDING`, đặt slot `INVITED`. **Không** kiểm tra/không tiết lộ email đã có tài khoản hay chưa (phản hồi giống hệt nhau).
2. Người nhận mở liên kết mời (App Link) hoặc nhập mã ngắn, **đăng nhập bằng tài khoản có email đã xác minh trùng `targetEmailNormalized`**.
3. Function `acceptInvite` (Firestore transaction) kiểm tra: Invite `PENDING`, chưa hết hạn, token khớp băm, email đã xác minh của người gọi khớp, slot đúng trạng thái, người gọi chưa có Membership ACTIVE ở Wallet này ⇒ tạo Membership `MEMBER/ACTIVE` gắn **`memberId` của Invite**, đặt slot `ACTIVE`, Invite `ACCEPTED`. Một lần duy nhất (token dùng-một-lần).

## 11. Email sai trước khi chấp nhận (mục 8 đề bài)

Owner: **Huỷ lời mời** (Invite → `CANCELLED`, slot → `UNLINKED`) ⇒ nhập email khác ⇒ Invite mới. Không có dữ liệu tài chính nào đổi; `memberId`/dữ liệu ví nguyên vẹn. Token cũ vô hiệu vì trạng thái `CANCELLED`.

## 12. Thay tài khoản Member an toàn (mục 9–11 đề bài)

Điều kiện: slot đang `ACTIVE` với `UID_OLD`.
1. Owner chọn "Đổi tài khoản thành viên", nhập email mới.
2. `createInvite(kind=REPLACEMENT)` ghi Invite `PENDING` gắn **cùng `memberId`**. **Tài khoản cũ vẫn ACTIVE, vẫn truy cập bình thường.**
3. Tài khoản mới đăng nhập, xác minh email, `acceptReplacement`.
4. **Một Firestore transaction duy nhất** (all-or-nothing):
   - đọc: Invite (PENDING, chưa hết hạn, email khớp), slot (ACTIVE, `linkedAccountId == UID_OLD`), Owner không đổi, `UID_NEW` chưa có Membership ACTIVE trong Wallet;
   - ghi: Membership(`UID_OLD`) → `REVOKED`; Membership(`UID_NEW`) → `MEMBER/ACTIVE` với **cùng `memberId`**; slot `linkedAccountId = UID_NEW`; Invite → `ACCEPTED`; chỉ mục `accounts/{uid}/wallets/{walletId}` tương ứng.
5. Sau commit (ngoài transaction, best-effort): thu hồi refresh token của UID_OLD và đóng phiên. **Việc chặn truy cập của UID_OLD không phụ thuộc bước này** vì Security Rules đọc trực tiếp tài liệu Membership (§30).
6. Nếu lời mời huỷ/hết hạn/lỗi ⇒ **không có gì đổi**; `UID_OLD` vẫn ACTIVE. **Không bao giờ gỡ tài khoản cũ trước khi tài khoản mới chấp nhận** trong luồng thường.
7. Đồng thời tối đa 1 Invite REPLACEMENT PENDING cho 1 slot (tránh đua); Function từ chối Invite thứ hai.

## 13. Thu hồi quyền ngay (mục 11 đề bài)

Trường hợp mất máy/tài khoản bị lộ. Owner xác nhận ⇒ Function `revokeMember` (Firestore transaction): Membership → `REVOKED`; slot → `UNLINKED`; mọi Invite PENDING của slot → `CANCELLED`; sau commit thu hồi refresh token. **`memberId` và lịch sử tài chính giữ nguyên.** Sau đó Owner có thể mời tài khoản mới vào **đúng slot đó**. Khác luồng thay thế ở chỗ: không đợi tài khoản mới, có khoảng slot `UNLINKED`.

**Giới hạn của thu hồi (phải nói thật, không hứa điều không làm được):** thu hồi phía máy chủ chặn NGAY các truy cập/ghi **cloud** trong tương lai, nhưng **không thể xoá hồi tố dữ liệu văn bản thường đã được lưu đệm cục bộ trên thiết bị đang offline**. Vì vậy an toàn về sau dựa vào: khoá ứng dụng, mã hoá DB, sandbox Android, và kiểm tra phiên khi kết nối lại. Không được quảng cáo "xoá từ xa".

**Nguồn sự thật duy nhất của Owner (cloud, tương lai):** `wallet.ownerAccountId` là **chuẩn** cho việc quản trị membership. Có thể có một dòng Membership `OWNER` để kiểm tra quyền đồng nhất, nhưng logic máy chủ **phải cưỡng chế nó khớp** `wallet.ownerAccountId`; không được có hai nguồn thẩm quyền Owner độc lập, mâu thuẫn.

## 14. Danh tính lịch sử: `createdByAccountId` (mục 13 đề bài)

- Bản ghi giao dịch tương lai mang `walletId` (ngầm qua đường dẫn), `memberId`, `createdByAccountId`.
- Khi Member đổi tài khoản: **không viết lại** `createdByAccountId` cũ. Giao dịch cũ vẫn ghi `UID_OLD` là người tạo, còn `memberId` vẫn là `M002`.
- Khả năng của mô hình hiện tại: `transaction_rows` chưa có cột nào để lưu tác nhân. **Khuyến nghị:** *không* thêm cột tác nhân vào Drift ở P2. Tác nhân là **metadata của lớp đồng bộ/cloud** (`createdByAccountId`, `updatedByAccountId`) — lưu trong tài liệu cloud và (nếu cần hiển thị) một bảng phụ cục bộ khi Family ra mắt. Lý do: Personal 1 thiết bị không cần; giữ Financial Core sạch; dữ liệu Excel đã nhập không có tác nhân (cho phép `null` = "dữ liệu di trú").
- Metadata tác nhân **khác** lịch sử hiệu chỉnh tài chính: sửa giao dịch thường là "đổi trạng thái hiện tại" (đã chốt), không tạo giao dịch hiệu chỉnh ẩn.

---

## 15. Hiện trạng ↔ mô hình đích — di trú ví ngầm định (mục 19–21 đề bài)

### 15.1 Nguyên tắc
Đọc **DB Pixel thực tế tại thời điểm di trú** (số dòng có thể đã đổi do dùng hằng ngày — **không ép về con số cũ nào**). Chỉ **thêm** metadata sở hữu; **không** đổi dòng tài chính nào.

### 15.2 Hai giai đoạn (tách rời để giảm rủi ro)
**Giai đoạn cục bộ (P2, không cần Account):** thêm 2 bảng nhỏ vào chính DB hiện tại (schema v8, cộng thêm, không copy dữ liệu):
- `wallet_meta` (1 dòng): `walletId` (sinh 1 lần), `kind = LOCAL`, `createdAt`, `systemCatalogVersion`, `migratedFromSchema`.
- `financial_member_rows`: `memberId` = **`vo`**, **`chong`** (giữ nguyên token), `displayName` ("Vợ"/"Chồng"), `linkedAccountId = NULL`, `slotState = UNLINKED`.

Không dòng giao dịch/danh mục/trạng thái/quỹ/tiết kiệm nào bị sửa.

**Giai đoạn claim (P8, cần Account + cloud):** khi người dùng chủ động bật Pro/sao lưu:

### 15.3 Màn "Bạn là ai trong Ví hiện tại?" (không suy đoán ngầm)
- Hiển thị 2 lựa chọn **Vợ / Chồng** kèm *tóm tắt trung tính* của từng thành viên (số giao dịch + khoảng thời gian, không số tiền) để người dùng tự nhận.
- Người dùng chọn (ví dụ "Chồng"). Ứng dụng hiện màn xác nhận: *"Tài khoản của bạn sẽ đại diện cho Chồng. Dữ liệu của Vợ giữ nguyên và sẽ được gắn với tài khoản khác khi bạn mời. Không giao dịch nào bị thay đổi."*
- Máy chủ `claimWallet(walletId, ownerMemberId)`:
  - tạo Wallet (chỉ khi `walletId` chưa tồn tại — ID ngẫu nhiên 128-bit, không đoán được);
  - Membership `OWNER/ACTIVE` ⇒ `memberId` đã chọn; slot còn lại `UNLINKED`;
  - tải dữ liệu lên với các ID cũ nguyên vẹn; máy chủ đối chiếu **dấu vân tay sổ cái** (băm chuẩn hoá tất cả dòng + số dư từng pool) do client gửi với giá trị tự tính; chỉ đánh dấu `CLAIMED` khi khớp.
- **Trong toàn bộ quá trình không dòng nào đổi `memberId` (`vo`/`chong`).**
- Cho phép **đổi lựa chọn** ("Tôi chọn nhầm") **chỉ khi slot còn lại vẫn `UNLINKED`**; thao tác này chỉ đổi Membership của Owner (đây là dữ liệu quyền, không phải tài chính). Sau khi slot kia đã ACTIVE thì khoá.

### 15.4 Mời người còn lại sau claim (mục 21)
Owner đã claim "Chồng". Sau đó mời Vợ bằng email ⇒ lời mời trỏ **`memberId = vo` đã tồn tại**. Khi Vợ chấp nhận, **gắn** tài khoản của cô ấy vào `vo`. **Cấm tạo FinancialMember mới cho Vợ** (bất biến I6). Test bắt buộc: sau chấp nhận, số FinancialMember vẫn là 2, `count(giao dịch memberId='vo')` không đổi.

### 15.5 Kiểm thử chọn Owner (mục 50)
| Kịch bản | Kỳ vọng |
|---|---|
| Owner chọn Chồng | Membership OWNER→`chong`; `vo` UNLINKED; mọi giao dịch của `vo` giữ nguyên; sau đó Vợ chấp nhận ⇒ Membership MEMBER→`vo` |
| Owner chọn Vợ (ngược lại) | Đối xứng hoàn toàn |
| Chọn nhầm rồi đổi (slot kia UNLINKED) | Đổi Membership Owner sang slot kia; không dòng tài chính nào đổi |
| Cố đổi khi slot kia đã ACTIVE | Bị từ chối |

---

## 16. Cách ly dữ liệu cục bộ — so sánh & khuyến nghị (mục 15–16 đề bài)

### 16.1 Bốn phương án
- **A.** 1 file SQLite, mọi bảng thêm cột `walletId`.
- **B.** **1 file SQLite cho mỗi Wallet.**
- **C.** 1 file cho mỗi Account.
- **D.** Lai: registry nhỏ (danh sách ví + tài khoản + phiên) + **file riêng cho mỗi Wallet**.

| Tiêu chí | A: 1 DB, cột walletId | B: DB/Wallet | C: DB/Account | D: Lai (B + registry) |
|---|---|---|---|---|
| Cách ly dữ liệu | Yếu: dựa vào `WHERE walletId=?` ở mọi truy vấn | **Mạnh: cách ly theo cấu trúc** (file khác nhau) | Mạnh nhưng sai đơn vị | **Mạnh** |
| Nguy cơ rò truy vấn do quên điều kiện | **Cao** (1 lỗi = lộ ví khác) | **Không thể xảy ra** (không có dữ liệu ví khác trong file) | Không | Không |
| Độ phức tạp Drift | Rất cao: sửa **mọi** bảng, khoá, chỉ mục, `UNIQUE(clientTxId)`→`UNIQUE(walletId,clientTxId)`, mọi repository/stream | **Thấp:** schema hiện tại **giữ nguyên**; chỉ chọn đường dẫn file | Thấp | Thấp–Trung (thêm registry) |
| Độ phức tạp di trú dữ liệu thật | Cao (thêm cột vào mọi dòng) | **Thấp nhất:** DB hiện tại **chính là** file của Wallet LOCAL; **không di chuyển/copy** | Trung | Thấp |
| Ví Family dùng chung | Tự nhiên | **Tự nhiên** (1 file = 1 ví; hai tài khoản mở cùng ví) | **Không hỗ trợ** (ví chung thuộc 2 tài khoản) | Tự nhiên |
| Chuyển đổi tài khoản | Cần lọc/xoá theo ví | **Đóng file này, mở file kia** | Tự nhiên | Tự nhiên |
| Sao lưu/khôi phục | Khó: phải cắt theo ví | **Dễ:** 1 file = 1 ví (khôi phục = tạo file mới từ snapshot) | Dễ | Dễ |
| Mã hoá | 1 khoá cho tất cả ví | **Khoá riêng theo ví** | Theo tài khoản | Theo ví |
| Đồng bộ | Tự nhiên | Tự nhiên (outbox riêng mỗi ví) | Lệch với ví chung | Tự nhiên |
| Kiểm thử | Phải test rò rỉ ở mọi truy vấn | Test cách ly = test "mở file khác" | | |
| iOS/desktop sau này | OK | **OK** (đường dẫn file khác nền tảng) | OK | OK |

### 16.2 Khuyến nghị: **Phương án D — mỗi Wallet một file SQLite + registry mỏng**
- Registry (một kho nhỏ riêng ngoài các file ví, không chứa dữ liệu tài chính): danh sách ví trên máy (`walletId`, đường dẫn file, `kind`, `accountId` đã liên kết nếu có), tài khoản đang đăng nhập, thiết bị. Ví LOCAL hiện có **được đăng ký trỏ vào đúng file `vi_nha_minh.sqlite` hiện tại** — **không di chuyển file**.
- Cách ly theo cấu trúc: đăng xuất rồi tài khoản B đăng nhập ⇒ B chỉ có thể mở file thuộc B (registry lọc theo `accountId`); ví Personal của A không nằm trong danh sách của B.
- Về **1 Account = 1 Wallet?** Mô hình D **không giả định** điều đó: registry có thể liệt kê nhiều ví/tài khoản. **Khuyến nghị v1:** hỗ trợ **cấu trúc** nhiều ví (registry là danh sách) nhưng **UI chỉ hiện 1 ví hoạt động**, để không đóng cửa tương lai Personal + Family mà không phải trả chi phí UI ngay.

### 16.3 Ranh giới đăng xuất (mục 24 đề bài)
Khi đăng xuất/đổi tài khoản, phải làm sạch **tất cả** thứ sau (checklist P6):
| Bề mặt | Hành động |
|---|---|
| File SQLite của ví | Đóng kết nối; **không** xoá file ví LOCAL/Personal của chính tài khoản (dữ liệu của họ), nhưng **không mở** trong phiên tài khoản khác |
| Riverpod providers/cache | Huỷ toàn bộ provider có trạng thái (`ProviderScope` khởi tạo lại), đặc biệt `appDatabaseProvider`, streams |
| SharedPreferences | Khoá cài đặt gắn **`accountId+walletId`** (không dùng khoá chung); `primary_fund_id`, `explorer_sort` hiện dùng khoá chung ⇒ phải đổi tiền tố |
| Trạng thái điều hướng / bộ lọc | Đặt lại (đang chỉ trong bộ nhớ) |
| Token Auth, khoá ứng dụng | Xoá token; giữ PIN/sinh trắc (thuộc thiết bị, §18) |
| Tập tin/tạm | Xoá cache, export tạm; hiện app không có tệp đính kèm |
| Tác vụ nền / outbox | Dừng; outbox thuộc ví, không gửi bằng danh tính khác |
| Ảnh chụp/snapshot UI | `FLAG_SECURE` tuỳ chọn; xoá thumbnail đa nhiệm khi khoá |

---

## 17. Personal Free có cần tài khoản? (OPEN — cần chủ dự án quyết định)

| Tiêu chí | **A: Personal Free hoàn toàn cục bộ, không đăng nhập** | **B: Bắt buộc đăng nhập, tắt cloud nếu không Pro** |
|---|---|---|
| Ma sát khi bắt đầu | **Không có** | Có (đăng nhập ngay lần đầu) |
| Riêng tư | **Tốt nhất** (không có gì rời máy, không định danh) | Có Account nhưng dữ liệu vẫn cục bộ |
| Offline-first | Trọn vẹn | Cần mạng để đăng nhập lần đầu |
| Khôi phục khi mất máy | **Không** (trừ xuất/nhập tệp) | Không (Free) nhưng đã có tài khoản để nâng cấp |
| Nâng cấp lên Pro | Cần "claim" ví LOCAL (§15) — quy trình đã thiết kế | Đơn giản hơn (đã có Account) |
| Chuyển tài khoản | Không áp dụng | Cần cách ly (§16.3) ngay từ đầu |
| "Nhận" dữ liệu (data claiming) | Có bước claim | Không |
| Mời Family sau này | Cần Account tại thời điểm nâng cấp | Sẵn sàng |
| Ràng buộc 1 thiết bị | Không áp dụng (chưa có cloud) | Áp dụng cho phiên cloud |
| Độ phức tạp triển khai | **Thấp** (không cần Auth cho lõi); claim là phần thêm | Trung (Auth phải xong trước khi dùng được app) |

**Khuyến nghị: Phương án A.** Lý do: người dùng thật **hiện đang dùng app không có đăng nhập** với dữ liệu thật; đưa đăng nhập bắt buộc vào sẽ phá trải nghiệm hiện tại và tăng rủi ro. Mô hình ví LOCAL (`kind = LOCAL`, `walletId` + `memberId` đã có, chưa gắn tài khoản) cho phép **nâng cấp không tạo lại dữ liệu**. **Không tự quyết — cần chủ dự án duyệt.**

### 17.1 Quy trình claim ví LOCAL sạch nhất
1. Người dùng chọn "Bật sao lưu/Pro" ⇒ đăng nhập (Google).
2. Chọn "Bạn là ai?" (§15.3).
3. `claimWallet` ⇒ Wallet trên cloud dùng **cùng `walletId`/`memberId`**; ví cục bộ đổi `kind = PERSONAL` (hoặc FAMILY sau khi mời), gắn `accountId`.
4. Tải sổ cái lên bằng chính ID cũ; đối chiếu dấu vân tay; **không tạo lại giao dịch**.
5. Nếu bước nào lỗi ⇒ trạng thái vẫn `LOCAL`, không mất gì (§28).

---

## 18. Bảo mật thiết bị & khoá ứng dụng

Ba khái niệm **khác nhau**, không được nhầm:

| | Trả lời câu hỏi | Công cụ |
|---|---|---|
| **A. Xác thực** | Ai là Account trên cloud? | Google Sign-In / Firebase Auth |
| **B. Khoá ứng dụng** | Người cầm điện thoại đã mở khoá có mở được Ví Nhà Mình không? | PIN + sinh trắc học |
| **C. Bảo vệ DB lúc nghỉ** | Ai copy được file DB thì đọc được không? | Sandbox, FBE, (tuỳ chọn) SQLCipher |

### 18.1 Khoá ứng dụng — khuyến nghị v1 (P3)
- **Sinh trắc học** qua `local_auth` (đã có trong `pubspec`) làm cách mở nhanh; **PIN** làm dự phòng bắt buộc.
- **Không lưu PIN thô. Không dùng `SHA256(pin)`** làm xác thực (PIN 4–6 số bị vét cạn trong tích tắc).
- Xác minh PIN: `verifier = HMAC-SHA256(K_keystore, KDF(pin, salt))` với `KDF` = PBKDF2/scrypt/Argon2id có chi phí cao; `salt` ngẫu nhiên riêng cài đặt; **`K_keystore` là khoá không xuất được** trong **Android Keystore** (ưu tiên StrongBox/TEE) ⇒ kẻ chép file `verifier` ra ngoài **không thể vét cạn offline** nếu không có Keystore của chính máy đó.
- Giới hạn thử: bộ đếm thử sai lưu bằng khoá bảo vệ, khoá tạm theo cấp số nhân (ví dụ 30 s → 1 phút → 5 phút…); thử sai nhiều lần ⇒ buộc dùng lại xác thực hệ thống.
- Thời điểm khoá: khi vào nền quá N giây (mặc định 30 s, chọn được) và khi mở app. Xoá thumbnail đa nhiệm (`FLAG_SECURE` tuỳ chọn).
- **Hiện trạng cần sửa:** công tắc "Khoá vân tay" hiện **không làm gì** — đây là rủi ro R3.
- Trạng thái PIN/sinh trắc là **DEVICE-ONLY**, **không bao giờ đồng bộ** lên cloud.

### 18.2 Sao lưu Android
Đặt `android:allowBackup="false"` và `dataExtractionRules`/`fullBackupContent` loại trừ DB ví + SharedPreferences (R4). Việc khôi phục dữ liệu đi qua **Personal Pro cloud restore**, không qua auto-backup của hệ điều hành.

### 18.3 Mã hoá DB cục bộ (OPEN — mục 41)
| Lựa chọn | Lợi ích | Chi phí/rủi ro |
|---|---|---|
| Chỉ sandbox Android (+ FBE của hệ điều hành) | Không thêm gì | Máy root/bản debug/`adb` có thể đọc; ổn cho đa số mối đe doạ |
| **SQLCipher** với **khoá DB ngẫu nhiên 256-bit được bọc bởi Keystore** | Chống chép file/backup/đọc offline | Dùng `sqlcipher_flutter_libs` thay `sqlite3_flutter_libs`; di trú DB thô → mã hoá (`sqlcipher_export`) cần sao lưu + kiểm tra; hiệu năng ~5–15% chậm hơn; kích thước app tăng |
| Khoá DB suy ra từ PIN | Không cần Keystore | Đổi PIN phải mã hoá lại toàn bộ; PIN yếu ⇒ khoá yếu — **không khuyến nghị** |

**ĐÃ CHỐT:** mã hoá DB cục bộ **BẮT BUỘC cho v1 sản xuất, trước mọi cloud/family pilot thật hoặc phát hành Play** (nhiều khả năng SQLCipher hoặc tương đương + vật liệu khoá được bảo vệ bằng Android Keystore, khoá DB độc lập với PIN). **KHÔNG triển khai ở P2**; một phase riêng sẽ audit di trú/hiệu năng/sao lưu. Trong lúc chờ: sandbox + FBE + `allowBackup=false` + khoá ứng dụng + bản release không debuggable. Đã ghi thành release gate trong `CLAUDE.md`.

### 18.4 Mã hoá cloud (mục 42)
| Lớp | Có sẵn? |
|---|---|
| TLS khi truyền | Có (Firebase mặc định) |
| Mã hoá lúc nghỉ do nhà cung cấp | Có, **do Google quản lý khoá** (có thể CMEK, tốn kém) |
| Mã hoá mức ứng dụng (client mã hoá trường) | Không tự có; phải tự làm |
| **E2EE thật** (máy chủ không đọc được nội dung) | **Firebase KHÔNG tự cung cấp E2EE** |

> **CẬP NHẬT 2026-09-26 (ĐÃ DUYỆT, thay khuyến nghị bên dưới cho DỮ LIỆU TÀI CHÍNH SAO LƯU):** nội dung tài chính lên cloud được **mã hoá phía client (zero-knowledge)**: BMK 256-bit ngẫu nhiên (chỉ là khoá gốc) → HKDF ra DEK (mã hoá AES-256-GCM) / IDK (id mờ); BMK được bọc bởi Password KEK (Argon2id 64 MiB, t=3, p=4 + HKDF) VÀ Recovery KEK (Recovery Key 256-bit + HKDF); credential tiếp quản thiết bị suy ra tách miền, máy chủ chỉ lưu SHA-256. Firebase/Admin không giữ khoá giải mã nào. KHÔNG E2EE: metadata Auth/phiên/ví, số lượng/kích thước/thời điểm bản ghi. Mất cả Mật khẩu sao lưu + Recovery Key + mọi thiết bị tin cậy ⇒ không khôi phục được, không có reset của quản trị. Không thay thế SQLCipher. Chi tiết: `docs/p8-cloud-backup-architecture.md`.

E2EE thật sẽ **phá vỡ**: Security Rules kiểm tra nội dung, kiểm tra bất biến tài chính phía máy chủ (số dư không âm), truy vấn theo trường, hợp nhất đồng bộ phía máy chủ, khôi phục khi mất khoá (mất khoá = mất dữ liệu vĩnh viễn). **Khuyến nghị v1:** không E2EE; phát biểu trung thực *"mã hoá khi truyền và khi lưu bởi nhà cung cấp"*; giảm dữ liệu nhạy cảm gửi lên; cân nhắc mã hoá trường `note` sau (P-later). Không được quảng cáo "E2EE".

---

## 19. Kiến trúc Personal Pro (mục 27)

Local-first, **UI không đọc Firestore**:
```
UI → Repository cục bộ → SQLite (nguồn vận hành)
                          │
                    outbox (thao tác chờ gửi, có ID, mỗi ví một outbox)
                          │
             Sync engine ⇄ Cloud (Firestore + Cloud Functions)
                          │
   thay đổi từ cloud → kiểm tra hợp lệ → áp vào SQLite → UI (stream Drift)
```
- Mọi thay đổi người dùng đi qua repository ⇒ ghi SQLite **và** ghi outbox trong **cùng 1 transaction DB**.
- Thay đổi tải xuống được xác thực (đúng ví, đúng phiên bản, qua kiểm tra bất biến) rồi mới ghi vào SQLite.
- Personal Pro hứa: sao lưu, đồng bộ, khôi phục, chuyển máy, **một thiết bị hoạt động**.

## 20. Kiến trúc Family Pro (mục 28) — tương thích tương lai
Wallet W, Owner A, Member B; hai tài khoản cùng thấy 1 ví; cả hai ghi giao dịch; mỗi tài khoản có ràng buộc 1 thiết bị **riêng**; danh tính tài chính = `memberId`, danh tính tác nhân = `accountId`; không dùng chung mật khẩu. Không có ẩn giao dịch riêng tư ở v1 (mục 29). Lưu ý kỹ thuật lớn nhất: **hai người ghi cùng ví** ⇒ cần thứ tự ghi có thẩm quyền phía máy chủ để bảo toàn "pool không âm" (§23.3).

---

## 21. Phiên thiết bị độc quyền — một Account, một thiết bị (mục 22–23)

### 21.1 Quyết định P7 thay thế thiết kế claims cũ (2026-09-25)
Firebase Auth xác nhận Account; secret phiên do backend cấp xác nhận phiên cloud.
Không dùng custom claims để nhận dạng thiết bị, không dùng `revokeRefreshTokens`
làm cơ chế độc quyền. Claims cấp Account có thể lan sang token mới của cùng UID;
token bị sao chép vẫn giữ nguyên mọi claim, không chứng minh phần cứng đang gọi.

### 21.2 Cổng phiên đáng tin cậy
- `accounts/{uid}/session/current`: `generation`, `installationId`,
  `sessionSecretHash`, `activatedAt`, `active`. Chỉ backend ghi; client không đọc.
- Xác nhận kích hoạt → callable `activateSession`: kiểm Auth UID, tạo secret 256-bit
  CSPRNG, tăng generation và thay hash trong một Firestore transaction, trả secret
  cho lần kích hoạt đó. Installation UUID v4 chỉ nhận diện, không cấp quyền.
- Mỗi thao tác được bảo vệ kiểm UID + secret hash + generation + installationId
  + trạng thái hợp lệ/active. `protectedPing` là thao tác duy nhất của P7.
- **P8+: mọi thao tác cloud cần phiên độc quyền phải đi qua backend gate này.**
  Không cho phép đường client Firestore/Storage khác bỏ qua gate. Mutation phải
  kiểm phiên và ghi trong cùng transaction; thêm Membership ACTIVE ở phase Family.
- Secret lưu AES-256-GCM bằng khóa Android Keystore riêng, không dùng khóa PIN.
  Không lưu plaintext trong prefs, không log secret/token/email. Không tự kích hoạt
  khi Auth refresh, mở app hoặc reconnect; kích hoạt lại luôn là thao tác rõ ràng.

### 21.2b P7.1 — tiếp quản an toàn (2026-09-26)
Firebase Auth một mình KHÔNG thay được installation đang active: `activateSession` trả TAKEOVER_REQUIRED. Chuyển máy bình thường = B xin → A (credential hiện hành + đăng nhập gần đây + xác minh thiết bị) chấp thuận → B hoàn tất bằng secret yêu cầu dùng 1 lần, ngắn hạn, gắn uid + installation đích (máy chủ chỉ lưu băm). Mất máy = đăng nhập gần đây + credential tiếp quản suy ra từ Mật khẩu sao lưu/Recovery Key ⇒ `epoch+1`, A bị đưa vào `revokedInstallations` (403 DEVICE_REVOKED ⇒ client xoá credential + BMK cục bộ; kích hoạt lại ⇒ RECOVERY_REQUIRED). Có rate limit phía máy chủ. Chi tiết: `docs/p7-exclusive-session.md` mục P7.1. (Mục 21.3 bên dưới mô tả P7; điểm "A cũ có thể kích hoạt lại" đã bị P7.1 thay thế.)

### 21.3 Giới hạn chính xác
- Sau transaction kích hoạt B commit, request mới dùng secret A bị từ chối dù
  Firebase ID token A còn hợp lệ hoặc refresh thành công. Request đã được xét trước
  điểm thay thế không bị hủy hồi tố. Không tuyên bố Firebase Auth A bị thu hồi ngay.
- Ai sở hữu secret hiện hành **và** Firebase credential cùng UID có quyền phiên đó;
  không chống sao chép credential đã giải mã trên thiết bị bị chiếm quyền.
- Offline/cached/local Wallet vẫn dùng được. Không có financial outbox ở P7.
  Reconnect không cấp lại quyền; future outbox phải đi qua gate tại lúc server ghi.
- Đăng xuất cố deactivation bằng chính credential hiện có, rồi xóa credential cục bộ
  và Auth kể cả khi offline. A cũ không thể deactivation B. Offline logout có thể
  để record server còn active; kích hoạt tiếp theo thay thế nó.
- P7 không claim Wallet, không Membership, không upload tài chính, không thay schema v8.
  Bằng chứng emulator và giới hạn nghiệm thu: `docs/p7-exclusive-session.md`.

---

## 22. Nhà cung cấp xác thực & mời qua email (mục 26)

- **Khuyến nghị khởi điểm:** **Google Sign-In qua Firebase Auth** (người dùng Android, không lưu mật khẩu, email đã xác minh sẵn). Bổ sung **email-link** sau nếu cần (không bắt buộc v1). Email/mật khẩu **không khuyến nghị** (phải quản lý đặt lại mật khẩu, vét cạn). Trạng thái: **OPEN** (nhà cung cấp ban đầu).
- **Lời mời phải hoạt động cả khi người được mời chưa có tài khoản:** lời mời gắn với **email chuẩn hoá** chứ không gắn `uid`. Khi họ đăng nhập lần đầu bằng email đó (đã xác minh), Function ghép Membership.
- **Không tiết lộ email đã đăng ký hay chưa:** `createInvite` luôn trả cùng một phản hồi; không có endpoint "kiểm tra email tồn tại"; không hiện lỗi khác nhau.
- **Cách gửi lời mời (ĐÃ CHỐT, thay đề xuất P1):** **backend đáng tin cậy tạo lời mời** (token mờ, chỉ lưu băm phía máy chủ, dùng một lần, gắn email đã xác minh, có hạn, thu hồi được) và **backend gửi email mời**. Nhà cung cấp email giao dịch **hoãn tới phase mời Family**; kiến trúc lõi KHÔNG được gắn chặt vào một nhà cung cấp. Liên kết dùng Android App Links (Dynamic Links đã ngừng).
- Cảnh báo chuẩn hoá: **không** gộp dấu `.`/`+` của Gmail (dễ gây nhận nhầm); so khớp đúng địa chỉ đã xác minh, chữ thường.

## 23. Đồng bộ, ID, xoá, chỉnh sửa

### 23.1 ID / idempotency (mục 35)
- **Giữ nguyên toàn bộ ID hiện có** (`id`, `client_tx_id`) — bao gồm ID tất định của dữ liệu nhập Excel. Không viết lại.
- Phạm vi duy nhất: ID chỉ cần duy nhất **trong 1 ví** (cloud: `wallets/{walletId}/transactions/{id}`; cục bộ: file riêng theo ví ⇒ `UNIQUE(client_tx_id)` hiện tại **tương đương** `UNIQUE(walletId, client_tx_id)`). **Không** cần tiền tố `deviceId`/`accountId` (tài khoản/thiết bị đổi không được làm ID đổi).
- Với bản ghi mới: nâng `IdGenerator` lên **UUID v4/v7** (≥ 122 bit ngẫu nhiên) từ P2; ID cũ giữ nguyên. Hiện `micro giây + 32 bit` đủ cho 1 người nhưng yếu khi 2 người ghi song song.
- `client_tx_id` vẫn là khoá chống ghi trùng khi thử lại (retry) và khi outbox gửi lại.
- Lưu ý Firestore: ID chứa `:` (ví dụ `imp:…`) hợp lệ; không dùng `/`.

### 23.2 Xoá thật + đồng bộ (mục 36) — OPEN
Hiện tại "Xóa giao dịch" là **xoá vật lý**. Cloud cần biết dòng đã xoá.
- **Khuyến nghị:** giữ nguyên ngữ nghĩa cục bộ "xóa hẳn"; ở tầng đồng bộ ghi **tombstone**: cloud giữ `{ id, deleted: true, deletedAt, rev }`; cục bộ, việc xoá sinh **một mục outbox `DELETE`** tồn tại độc lập với dòng đã xoá (outbox không phụ thuộc dòng gốc).
- Thiết bị khác biết dòng đã xoá nhờ **feed thay đổi theo `rev` tăng đơn điệu của ví** (kèm tombstone).
- **Khôi phục/thiết bị mới không "hồi sinh" dòng đã xoá:** khôi phục tải **ảnh chụp trạng thái hiện tại** (không gồm dòng đã xoá) + phần feed sau mốc; dòng đã xoá không nằm trong ảnh chụp.
- **ĐÃ CHỐT (thay đề xuất 90–180 ngày của P1):** ngữ nghĩa cục bộ vẫn là "Xóa hẳn"; phía cloud/đồng bộ giữ **tombstone/sự kiện xoá tối thiểu**. **v1 KHÔNG tự động compaction tombstone.** Giữ đủ metadata chống hồi sinh: `objectId`, `walletId`, phiên bản/`rev` xoá, `deletedAt`, tác nhân nếu cần. **Compaction an toàn** chỉ được làm ở phase sau, khi mọi mốc đồng bộ (watermark) liên quan đã xác nhận xoá. Không có mã tombstone ở P2.

### 23.3 Chỉnh sửa (trạng thái hiện tại) + đồng bộ (mục 37)
- Chỉnh sửa thường = đổi trạng thái hiện tại (đã chốt), không sinh lịch sử hiệu chỉnh tài chính ẩn.
- **Cần ngay (Personal, P8–P9):** `updatedAt`, `version` (đã có cột `version` cục bộ), `serverRev`; ghi kiểu *check-and-set theo `version`* để từ chối ghi dựa trên phiên bản cũ.
- **Có thể để sau:** `updatedByAccountId` (khi Family), kiểu hợp nhất theo trường.
- **Family (P11) cần mạnh hơn:** hai người ghi cùng ví ⇒ **thứ tự ghi có thẩm quyền phía máy chủ** (Cloud Function nhận lô thao tác, kiểm tra bất biến "pool không âm", gán `rev`). *Last-write-wins* đơn thuần **không đủ** vì hai lần chi ngoại tuyến cùng một pool có thể đồng thời hợp lệ ở từng máy nhưng làm pool âm khi gộp ⇒ máy chủ phải từ chối lần thứ hai và máy khách hiện lỗi "Không đủ số dư" để xử lý.

### 23.4 Khôi phục (mục 22 tài liệu)
Khôi phục ví Pro trên máy mới: đăng nhập ⇒ kích hoạt phiên (đẩy máy cũ ra) ⇒ tạo file ví mới **không seed** (seed hiện chỉ chạy khi `wasCreated` ⇒ phải có chế độ "rỗng" cho đường khôi phục, nếu không sẽ tạo lại các dòng mặc định đã xoá) ⇒ tải ảnh chụp + feed ⇒ đối chiếu dấu vân tay sổ cái ⇒ đăng ký vào registry.

---

## 24. Cài đặt: phạm vi sở hữu (mục 38–39)

### 24.1 Bảng phân loại
| Cài đặt | Hiện ở đâu | Phạm vi khuyến nghị | Đồng bộ? |
|---|---|---|---|
| `primary_fund_id` (Quỹ chính Trang chủ) | SharedPreferences (tạm thời) | **WALLET DATA** (ĐÃ CHỐT sau P1: là thuộc tính của trải nghiệm Ví chung; khôi phục/đồng bộ phải giữ) — hiện vẫn ở SharedPreferences, **di trú vào dữ liệu ví ở phase sau** | Có (cùng ví) |
| `explorer_sort` (sắp xếp Tổng hợp) | SharedPreferences | **DEVICE** (ưu tiên hiển thị, giá trị thấp) | Không |
| Bộ lọc Tổng hợp, tab hiện tại | Bộ nhớ | DEVICE (không lưu) | Không |
| Thành viên đang chọn ở bộ lọc | Bộ nhớ | DEVICE (không lưu) | Không |
| Khoá ứng dụng bật/tắt, PIN verifier, cấu hình sinh trắc | *(chưa có thật)* | **DEVICE-ONLY** (bảo mật) | **Không bao giờ** |
| Chủ đề (theme), ngôn ngữ | Chưa lưu | APP-GLOBAL / DEVICE | Không |
| Onboarding đã xem | Chưa có | DEVICE | Không |
| `advancedFeaturesEnabled` | Hằng số `false` | WALLET (tính năng bật cho ví) khi ra mắt | Có (sau) |
| `syncMode` | Bộ nhớ (stub) | **WALLET** (`kind` + trạng thái đồng bộ) | Có |
| Tên hiển thị/vai trò thành viên | (enum) | WALLET (bảng thành viên) | Có |

Quy tắc: khoá SharedPreferences phải mang tiền tố phạm vi (`<accountId|LOCAL>.<walletId>.<key>`) từ P6 để tránh rò giữa tài khoản.

### 24.2 Mặc định quỹ chính khi khôi phục
Người dùng khôi phục Personal Pro trên máy mới **phải thấy lại đúng Quỹ chính** ⇒ **ĐÃ CHỐT: WALLET DATA** (không phải ACCOUNT×WALLET như đề xuất P1). **Yêu cầu di trú tương lai:** chuyển `primary_fund_id` từ SharedPreferences vào dữ liệu của ví (bảng cài đặt ví hoặc cột trên `wallet_meta`) cùng lúc với phase đồng bộ; P2 KHÔNG di trú nó.

---

## 25. Quyền riêng tư nhật ký/phân tích (mục 43)

**Cấm ghi vào log/Crashlytics/analytics/chẩn đoán:** ghi chú giao dịch; số tiền chính xác; email; token xác thực/mời; `walletId`/`memberId`/`accountId` đầy đủ khi không cần; toàn bộ payload tài chính.

| Kênh | Được phép | Quy tắc che |
|---|---|---|
| Log bản phát hành | Mã lỗi, tên màn hình, loại thao tác, thời lượng | Không thông điệp có dữ liệu người dùng; `debugPrint` bị vô hiệu ở release |
| Crashlytics | Stack trace, phiên bản, loại thiết bị | Đặt `setUserIdentifier` bằng **băm ngắn**, không email/uid thô; không gắn khoá tuỳ chỉnh chứa tiền/ghi chú; lọc exception có `toString()` chứa dữ liệu (ví dụ ngoại lệ có số tiền) |
| Analytics | Sự kiện ẩn danh (mở màn hình, bật tính năng) | **Không** tham số tiền/ghi chú/tên; mặc định tắt cho tới khi có đồng ý |
| Chẩn đoán hỗ trợ | Số lượng bản ghi, phiên bản schema, kết quả kiểm tra toàn vẹn | Người dùng **chủ động xuất** và xem trước; không tự gửi |
| ID trong log | 6–8 ký tự đầu của băm | Không ID đầy đủ |
Cần test tự động quét: mọi `Exception.toString()` do app tạo không chứa số tiền/ghi chú (P5).

## 26. Dữ liệu chủ (master data) hệ thống vs ví (mục 40)

| Mục | Phân loại | Đại diện trên cloud |
|---|---|---|
| Danh mục hệ thống (8 ID cố định) | **APP INFRASTRUCTURE** | **Không có bản ghi**; nằm trong danh mục hằng số của app; ví chỉ ghi `systemCatalogVersion`. Giao dịch tham chiếu theo ID ổn định |
| Danh mục người dùng/nhập | **WALLET DATA** | `wallets/{w}/categories/{id}` |
| Trạng thái | **WALLET DATA** | `.../statuses/{id}` (kèm `categoryId`, `sortOrder`) |
| Quỹ (kể cả `an_uong`) | **WALLET DATA** | `.../funds/{id}` |
| Loại tiết kiệm (kể cả `savings_bank`) | **WALLET DATA** | `.../savingsAssets/{id}` |
| `savings_unallocated` | **VIRTUAL/DERIVED** | **Không lưu, không đồng bộ** |
Lý do: không nhân bản định nghĩa bất biến như bản ghi người dùng tuỳ ý (tránh xung đột phiên bản, tránh việc một thiết bị "sửa" danh mục hệ thống). Nếu app nâng cấp danh mục hệ thống, `systemCatalogVersion` cho phép di trú có kiểm soát.

---

## 27. Hình dạng dữ liệu cloud & quy tắc bảo mật (mục 30, 46–48)

### 27.1 Hình dạng đề xuất (khác mẫu ở vài điểm có chủ ý)
```
accounts/{accountId}
  profile, session/current(generation, installationId, sessionSecretHash, activatedAt, active), preferences/{walletId} ← ACCOUNT-scoped
  wallets/{walletId}            ← chỉ mục "tài khoản này thuộc ví nào" (máy chủ ghi, client chỉ đọc)

wallets/{walletId}                          meta: kind, systemCatalogVersion, entitlement(máy chủ ghi)
wallets/{walletId}/members/{memberId}       FinancialMember (linkedAccountId do máy chủ ghi)
wallets/{walletId}/memberships/{accountId}  Membership (máy chủ ghi hoàn toàn)
wallets/{walletId}/invites/{inviteId}       Invite (máy chủ ghi; tokenHash)
wallets/{walletId}/transactions/{id}        + createdByAccountId, updatedAt, version, rev, deleted?
wallets/{walletId}/categories/{id}          (chỉ danh mục người dùng)
wallets/{walletId}/statuses/{id}
wallets/{walletId}/funds/{id}
wallets/{walletId}/savingsAssets/{id}
wallets/{walletId}/counterparties|obligations/{id}   (sau)
wallets/{walletId}/tombstones|changefeed              (theo rev)
```
Khác mẫu: (1) thêm chỉ mục `accounts/{a}/wallets/{w}` để liệt kê ví mà **không cần** truy vấn collection group; (2) `memberships` khoá theo `accountId` (kiểm tra `exists` O(1) trong Rules); (3) bảng tombstone/feed theo `rev`.

> **P8 (2026-09-26) thay hình dạng trên cho dữ liệu tài chính:** không còn collection tài chính theo loại với nội dung rõ. Dùng 1 collection chung `wallets/{walletId}/entities/{opaqueId}` chứa envelope mã hoá `{v, id, rev, n, c, aad, serverRev}` (loại thực thể nằm TRONG ciphertext), `wallets/{walletId}/batches/{batchId}` (biên nhận idempotent) và `accounts/{uid}/backupKeyrings/{walletId}` (khoá đã bọc). Mọi ghi qua Function + cổng phiên; Rules deny-all. Chi tiết `docs/p8-cloud-backup-architecture.md`. Các dòng "Rules (client trực tiếp)" ở bảng dưới KHÔNG còn áp dụng.

### 27.2 Việc nào phải do máy chủ (Cloud Function/Trusted), việc nào Rules đủ
| Thao tác | Cơ chế | Lý do |
|---|---|---|
| `claimWallet` | **Cloud Function (transaction)** | Tạo Wallet + Membership OWNER + kiểm ID chưa tồn tại |
| Mời / huỷ mời | **Function** (Owner-only) | Token băm, hạn, không lộ email |
| Chấp nhận mời | **Function (transaction)** | Kiểm email đã xác minh, một lần, gắn `memberId` sẵn có |
| Thay Member / Thu hồi | **Function (transaction)** | Nguyên tử, không có khoảng trống (§12, §13) |
| Gán/đổi Owner, `accessRole`, `walletId`, `linkedAccountId` | **Chỉ Function**; Rules **từ chối mọi ghi từ client** | Không tin client gửi các trường này |
| Entitlement (gói) | **Function** (xác minh Play Billing) | Client không được tự nâng gói |
| Kích hoạt phiên thiết bị | **Function** | Tăng generation, thay hash secret trong transaction (§21) |
| Ghi giao dịch/danh mục/trạng thái/quỹ thường ngày | **Rules** (client trực tiếp) cho Personal | Kiểm tra: phiên hợp lệ + Membership ACTIVE + đúng `walletId` đường dẫn + `memberId` thuộc ví |
| Ghi giao dịch Family (2 người) | **Function nhận lô** (P11) | Bảo toàn "pool không âm" |

### 27.3 Ma trận kiểm thử Rules — Personal (mục 47)
| # | Tình huống | Kỳ vọng |
|---|---|---|
| P-1 | Chưa đăng nhập đọc/ghi | **DENY** |
| P-2 | Owner A đọc Wallet A (phiên hiện hành) | **ALLOW** |
| P-3 | Tài khoản B không liên quan đọc Wallet A | **DENY** |
| P-4 | Client tự đổi `ownerAccountId`/Membership OWNER | **DENY** |
| P-5 | Client tự tạo Membership cho chính mình | **DENY** |
| P-6 | Phiên cũ (`gen` cũ) ghi | **DENY** |
| P-7 | Phiên hiện hành ghi giao dịch hợp lệ vào ví của mình | **ALLOW** |
| P-8 | Ghi giao dịch với `memberId` không thuộc ví | **DENY** |
| P-9 | Client ghi entitlement | **DENY** |
| P-10 | Ghi vào `walletId` khác trong nội dung tài liệu (khác đường dẫn) | **DENY** |

### 27.4 Ma trận kiểm thử Rules — Family (mục 48)
| # | Tình huống | Kỳ vọng |
|---|---|---|
| F-1 | Owner đọc/ghi Wallet chung | **ALLOW** |
| F-2 | Member ACTIVE đọc/ghi Wallet chung (phạm vi tài chính thường) | **ALLOW** |
| F-3 | Người ngoài | **DENY** |
| F-4 | Member mời thêm người | **DENY** |
| F-5 | Member đổi Owner | **DENY** |
| F-6 | Member thay ràng buộc Member | **DENY** |
| F-7 | Member đổi `accessRole` | **DENY** |
| F-8 | Member tự nâng lên Owner | **DENY** |
| F-9 | Tài khoản Member cũ đã `REVOKED` | **DENY** |
| F-10 | Tài khoản Member mới sau khi chấp nhận thay thế | **ALLOW** |
| F-11 | Tài khoản Member cũ **trong lúc** thay thế chưa hoàn tất | **ALLOW** (vẫn ACTIVE) |
| F-12 | Hai tài khoản cùng ACTIVE cho một `memberId` | **Không thể xảy ra** (bất biến I3, kiểm bằng test transaction đồng thời) |

### 27.5 Nguyên tắc: Membership **không** nằm trong custom claim
Rules đọc tài liệu Membership (`exists`/`get`) ⇒ thu hồi/thay thế **có hiệu lực ngay cho mọi lần ghi**, không đợi hết hạn token. Custom claim chỉ chứa `dev`/`gen`.

### 27.6 Khôi phục Owner mất truy cập (mục 33)
Owner điều khiển việc gắn/thay Member nên đây là điểm nhạy cảm. **Khuyến nghị v1 thực tế:**
- Khôi phục dựa vào **khôi phục tài khoản của nhà cung cấp xác thực** (Google account recovery). Không có "đặt lại Owner" bằng hỗ trợ khách hàng trong v1.
- Member **không thể** âm thầm tự nâng quyền (F-5, F-8). Nếu Owner mất tài khoản vĩnh viễn, Member vẫn đọc/ghi dữ liệu nhưng không quản trị được; đây là hạn chế **chấp nhận và công bố**.
- Biện pháp giảm nhẹ: cho phép **xuất dữ liệu ví ra tệp** (Excel/CSV) để không mất dữ liệu; cân nhắc tính năng **"chuyển quyền Owner"** có chủ ý (Owner hiện tại xác nhận) ở phase sau, **không có trong v1**.

## 28. Môi trường, App Check

### 28.1 DEV / PILOT / PROD (mục 44)
| Môi trường | Firebase project | `applicationId` | Dữ liệu |
|---|---|---|---|
| DEV | riêng | hậu tố `.dev` | dữ liệu giả/thử; **cấm** dữ liệu thật của chủ dự án |
| PILOT | riêng | hậu tố `.pilot` | chỉ sau khi chủ dự án **duyệt rõ ràng** (thử nghiệm Family với máy Vợ) |
| PROD | riêng | `com.vinhamimh.vi_nha_minh` (không đổi — Android không cho đổi sau phát hành) | người dùng thật |
- Cấu hình Flutter: `--dart-define-from-file=env/<env>.json` + `productFlavors` Android (mỗi flavor một `google-services.json`); hằng `AppEnv` đọc lúc biên dịch.
- **Lá chắn chống nhầm:** DEV/PILOT có `applicationId` khác ⇒ **sandbox khác** ⇒ dữ liệu thật trên Pixel (thuộc ứng dụng PROD/hiện tại) **không tồn tại** trong bản DEV. Thêm kiểm tra khởi động: ví `kind` thật bị **từ chối** mở trong build DEV.
- Dữ liệu thật của chủ dự án **không bao giờ** được tải lên DEV. Lên PILOT/PROD chỉ qua claim (P8) sau phê duyệt.

### 28.2 Firebase App Check (mục 45)
Bật App Check (Play Integrity) làm **phòng thủ theo chiều sâu**: giảm lạm dụng API từ client giả. **App Check KHÔNG thay thế** Authentication, Security Rules hay uỷ quyền phía máy chủ. Triển khai: chế độ quan sát → thực thi (enforce) cho Firestore/Functions; debug provider cho DEV. Chưa triển khai ở P1.

---

## 29. Mô hình mối đe doạ (tổng hợp)

| # | Mối đe doạ | Tác động | Biện pháp |
|---|---|---|---|
| T1 | Người cầm máy đã mở khoá mở app | Lộ dữ liệu | Khoá ứng dụng PIN/sinh trắc (P3) |
| T2 | Copy file DB / auto-backup / adb | Lộ dữ liệu | `allowBackup=false`, bản release không debuggable, (tuỳ chọn) SQLCipher |
| T3 | Email mời gõ sai | Người lạ nhận lời mời | Token dùng-một-lần + đối chiếu email đã xác minh + hạn; Owner huỷ được |
| T4 | Liên kết mời bị chuyển tiếp | Người khác cố chấp nhận | Email đã xác minh của người chấp nhận phải khớp; token băm dùng một lần |
| T5 | Token mời bị đánh cắp | Chấp nhận trái phép | Token 128-bit, lưu băm, hạn 7 ngày, đối chiếu email |
| T6 | Chấp nhận lời mời hết hạn / đã huỷ | Truy cập trái phép | Function kiểm `state` và `expiresAt` |
| T7 | Owner đổi ý sau khi gửi | — | Huỷ mời (state `CANCELLED`) |
| T8 | Hai lần thay thế đồng thời | Slot lệch | Chỉ 1 Invite REPLACEMENT PENDING; Firestore transaction |
| T9 | Member cũ cố sửa membership | Nâng quyền | Rules từ chối mọi ghi vào `memberships`/`members`/`ownerAccountId` từ client |
| T10 | Phiên cũ/offline/outbox ghi sau khi bị đá | Ghi trái phép | Backend kiểm secret hiện hành; cấm đường client bỏ qua gate (§21) |
| T11 | Token bị sao chép | Mạo danh thiết bị | Firebase token riêng không đủ; token cùng secret hiện hành bị sao chép vẫn có quyền (§21.3) |
| T12 | Owner mất tài khoản | Không quản trị được | §27.6 |
| T13 | Đọc chéo giữa tài khoản trên cùng máy | Lộ ví cá nhân | DB theo ví + registry + ranh giới đăng xuất (§16.3) |
| T14 | Lộ số tiền/ghi chú qua log | Lộ riêng tư | Chính sách §25 |
| T15 | Client giả gọi API | Lạm dụng | App Check (phòng thủ chiều sâu) + Rules + Functions |
| T16 | Hồi sinh dòng đã xoá | Sai số liệu | Tombstone + ảnh chụp không chứa dòng đã xoá |
| T17 | Hai người ghi đồng thời làm pool âm | Sai số dư | Ghi có thẩm quyền phía máy chủ (P11) |

---

## 30. Kế hoạch di trú DỮ LIỆU THẬT & hoàn tác (mục 49–51)

Áp dụng cho P2 (schema v8) và P8 (claim). **Luôn đọc DB thực tế tại thời điểm thực hiện.**

### 30.1 Trước khi di trú
1. Đóng app, **sao lưu file DB** (không chép khi app đang mở) ra ngoài Git; ghi SHA-256.
2. Ghi lại **thước đo tham chiếu** (từ chính DB đó, không dùng con số cũ): tổng số giao dịch, số danh mục, trạng thái, quỹ, loại tiết kiệm; số dư từng pool (khả dụng từng thành viên, tiết kiệm theo loại, quỹ); Tổng tài sản; các tổng báo cáo; `integrity_check`; `foreign_key_check`; băm sổ cái chuẩn hoá (tất cả cột tài chính, sắp theo `id`).
3. Kiểm `user_version`, số dòng theo bảng.

### 30.2 Sau khi di trú — điều kiện PASS
- Băm sổ cái chuẩn hoá **giống hệt** (chỉ **thêm** bảng/cột metadata sở hữu).
- Không: trùng, mất, đổi số tiền, đổi danh mục/trạng thái, đổi `memberId` (`vo`/`chong`), đổi phân bổ tiết kiệm, đổi số dư quỹ, đổi `client_tx_id`.
- `integrity_check = ok`, `foreign_key_check` rỗng.

### 30.3 Hoàn tác
- Di trú schema chạy trong **một transaction**; lỗi ⇒ rollback tự động (DB nguyên trạng).
- Điều kiện hoàn tác: bất kỳ đo lường nào ở §30.2 lệch, hoặc `integrity_check` ≠ ok.
- Cách hoàn tác: dừng app, **thay lại file DB bằng bản sao lưu** (đã có băm); dữ liệu cũ luôn khôi phục được. Không xoá bản sao lưu trước khi chủ dự án xác nhận.
- Với claim (P8): nếu tải lên/đối chiếu thất bại ⇒ ví cục bộ vẫn `LOCAL`, cloud không có Wallet `CLAIMED`.

---

## 31. Lộ trình triển khai (mục 52) — nhỏ, có cổng, suy ra từ kiến trúc thực tế

> Mỗi phase kết thúc bằng: test → nghiệm thu Pixel → sao lưu → **dừng chờ duyệt**. Không phase nào tải dữ liệu thật lên cloud trước P8.

| Phase | Phạm vi | Ảnh hưởng schema | Ảnh hưởng bảo mật | Kiểm thử chính | Nghiệm thu Pixel | Điểm hoàn tác |
|---|---|---|---|---|---|---|
| **P2 — Local Wallet Identity** | Thêm `wallet_meta` + `financial_member_rows` (memberId = `vo`/`chong`), `IdGenerator` v2 (UUID) cho bản ghi mới; **không** đổi hành vi | **v7→v8, cộng thêm**, một transaction | Chưa | Migration v7→v8 giữ băm sổ cái; Golden/Financial Core không đổi; ID cũ nguyên | Cài đè, dữ liệu y nguyên, thao tác bình thường | Sao lưu DB trước; rollback = thay file |
| **P3 — Khoá ứng dụng + gia cố sao lưu** | PIN + sinh trắc thật (Keystore), `allowBackup=false`, `dataExtractionRules`; sửa công tắc giả | **Không** | Cao (T1, T2) | Kiểm thử KDF/HMAC, khoá tạm, không lưu PIN thô; test quyền manifest | Khoá/mở, thử sai, ép dừng/mở lại | Tắt khoá qua cờ; không đụng DB |
| **P4 — Thành viên là dữ liệu** | Thay enum `FamilyMember` bằng danh sách thành viên lấy từ `financial_member_rows` (vẫn `vo`/`chong`); Ví Personal 1 thành viên hợp lệ | Không (dùng bảng P2) | Không | Toàn bộ test hiện có + test ví 1 thành viên; Golden nguyên | Số dư/Trang chủ giống hệt | Cờ tính năng; sao lưu |
| **P5 — Nền Auth & môi trường** | Flavors DEV/PILOT/PROD, Firebase DEV, Google Sign-In, thêm `INTERNET`, **chưa tải dữ liệu**; chính sách log | Không | Trung (bề mặt mạng mới) | Test cấu hình môi trường; quét log không lộ dữ liệu | Đăng nhập trên bản DEV; ví thật **không** hiện ở DEV | Xoá bản DEV; PROD không đổi |
| **P6 — Cách ly Account/Wallet** | Registry ví; đường dẫn file theo ví; ranh giới đăng xuất; tiền tố khoá cài đặt | Registry (ngoài file ví) | Cao (T13) | Đăng xuất/đổi tài khoản không lộ dữ liệu; test provider bị huỷ | A đăng xuất, B đăng nhập không thấy ví A | Registry có thể xoá, file ví nguyên |
| **P7 — Phiên thiết bị độc quyền** | Callable activation, secret Keystore, backend gate; Rules deny client access | Không (cloud) | Cao (T10, T11) | Emulator Auth/Functions/Rules: token còn hợp lệ + secret cũ bị từ chối | DEV + client logic thứ hai; kích hoạt B chặn A | Tắt Function; local không đổi |
| **P8 — Claim + Personal Pro sao lưu/khôi phục** | `claimWallet`, màn "Bạn là ai?", tải sổ cái, dấu vân tay, khôi phục ví mới **không seed**; **quyết định SQLCipher trước** | Có thể thêm metadata đồng bộ (outbox) | Cao (dữ liệu thật lên cloud) | Test §15.5, §30; Rules P-1..P-10 | Claim thật trên PILOT **chỉ sau khi chủ dự án duyệt**; khôi phục sang máy thử | Sao lưu bắt buộc; ví vẫn LOCAL nếu lỗi |
| **P9 — Đồng bộ Personal (cứng hoá)** | Outbox, tombstone, `rev`, CAS theo `version`, App Check enforce | Bảng outbox/tombstone | Trung–Cao | Xoá/hồi sinh, offline, retry idempotent | Ngắt mạng thêm/xoá/sửa rồi đồng bộ | Tắt đồng bộ, dùng local |
| **P10 — Nền tảng Membership Family** | Wallet/Member/Invite trên cloud, Rules Family, Function mời/chấp nhận | Cloud | Cao | Ma trận F-1..F-12 (emulator) | Hai tài khoản thử trên PILOT | Xoá dữ liệu PILOT |
| **P11 — Thay/Thu hồi Member + Đồng bộ 2 tài khoản** | Thay thế nguyên tử, thu hồi ngay, ghi có thẩm quyền, xung đột pool | Cloud | Cao (T8, T17) | Đồng thời, nguyên tử, không pool âm | Thay Member, thu hồi, hai máy ghi đồng thời | Tắt Family; Personal nguyên |
| **P12 — Pilot máy Vợ** | Cài trên máy Vợ, mời/chấp nhận, dùng thật có giám sát | Không | Cao | Danh sách nghiệm thu thực địa | Trên hai điện thoại thật | Thu hồi ngay + khôi phục sao lưu |

Ghi chú thứ tự: P3 (khoá ứng dụng) **độc lập với cloud** và nên làm sớm vì chủ dự án đang dùng dữ liệu thật. P4 tách riêng khỏi P2 để mỗi bước chỉ có một loại rủi ro.

---

## 32. BẢNG QUYẾT ĐỊNH

| QUYẾT ĐỊNH | KHOÁ / MỞ | LỰA CHỌN | KHUYẾN NGHỊ | VÌ SAO | CẦN CHỦ DỰ ÁN DUYỆT |
|---|---|---|---|---|---|
| Wallet là container tài chính | **LOCKED** | — | — | Mô hình chung Personal/Family | Đã khoá |
| Đúng 1 Owner | **LOCKED** | — | — | Phân quyền rõ | Đã khoá |
| Tối đa 1 Member thêm | **LOCKED** | — | — | Family v1 ≤ 2 người | Đã khoá |
| `memberId` ổn định sở hữu danh tính tài chính | **LOCKED** | — | Dùng `vo`/`chong` làm memberId của ví cũ | Không phải viết lại dữ liệu | Đã khoá |
| Email không phải danh tính tài chính | **LOCKED** | — | — | Email đổi được | Đã khoá |
| Ràng buộc tài khoản có thể thay | **LOCKED** | — | — | Mất máy/đổi tài khoản | Đã khoá |
| Thay thế giữ nguyên `memberId`/lịch sử | **LOCKED** | — | — | Lịch sử thuộc thành viên | Đã khoá |
| Chỉ Owner quản trị membership | **LOCKED** | — | Cưỡng chế bằng Function+Rules | Client không đáng tin | Đã khoá |
| Có thu hồi quyền ngay | **LOCKED** | — | — | Mất máy/lộ tài khoản | Đã khoá |
| Family v1: cả hai thấy toàn Wallet | **LOCKED** | — | — | Số dư/báo cáo nhất quán | Đã khoá |
| 1 Account = 1 thiết bị hoạt động | **LOCKED** | — | Secret phiên do backend cấp + gate (§21) | Yêu cầu sản phẩm | Đã khoá |
| Personal & Family dùng chung mô hình Wallet | **LOCKED** | — | — | Tránh 2 hệ thống không tương thích | Đã khoá |
| Personal Free có cần tài khoản không? | **LOCKED (duyệt sau P1)** | A: cục bộ, không đăng nhập | **A** — hoàn toàn cục bộ, không đăng nhập, không thanh toán; Pro sau này mới cần Account | Dữ liệu thật đang dùng không đăng nhập; riêng tư | Đã duyệt |
| 1 SQLite hay DB theo ví? | **LOCKED (duyệt sau P1)** | D | **Mỗi Wallet 1 file SQLite; registry mỏng ở phase sau; UI v1 1 ví; P2 chỉ thêm trừu tượng `WalletDescriptor`, KHÔNG di chuyển DB** | Cách ly theo cấu trúc; giữ schema | Đã duyệt |
| Mã hoá DB ở v1? | **LOCKED (duyệt sau P1)** | — | **BẮT BUỘC trước cloud/family pilot thật hoặc Play; không làm ở P2** (SQLCipher hoặc tương đương + Keystore) | Bảo vệ dữ liệu tiền thật lúc nghỉ | Đã duyệt |
| Mô hình xoá/tombstone cloud chính xác | **LOCKED (duyệt sau P1)** | — | Tombstone/sự kiện xoá tối thiểu; **v1 không tự động compaction**; compaction an toàn sau, dựa trên watermark | Không hồi sinh dòng đã xoá | Đã duyệt |
| Quỹ chính: thiết bị hay ví? | **LOCKED (duyệt sau P1)** | — | **WALLET DATA** (khác đề xuất ACCOUNT×WALLET của P1); chưa di trú ở P2 | Thuộc trải nghiệm Ví chung; khôi phục/đồng bộ phải giữ | Đã duyệt |
| Nhà cung cấp Auth ban đầu | **LOCKED (duyệt sau P1)** | — | **Google Sign-In trước; lớp Auth độc lập nhà cung cấp; email-link thêm sau** | Không mật khẩu, email đã xác minh | Đã duyệt |
| Cách gửi lời mời | **LOCKED (duyệt sau P1)** | — | **Backend tạo + backend gửi email**; nhà cung cấp email hoãn tới phase mời Family; không gắn lõi vào 1 vendor | Bảo mật token phía máy chủ | Đã duyệt |
| Chuyển quyền Owner | **LOCKED (duyệt sau P1)** | — | **KHÔNG hỗ trợ ở Family v1** (không có UI/mutation MEMBER→OWNER); khôi phục Owner dựa vào khôi phục tài khoản của nhà cung cấp Auth | Giảm bề mặt tấn công | Đã duyệt |
| Nhiều ví trên 1 tài khoản (cấu trúc) | **LOCKED (duyệt sau P1)** | — | Kiến trúc cho phép nhiều Wallet; **UI v1 chỉ 1 ví hoạt động**; không có UI chuyển ví ở P2 | Không đóng cửa tương lai | Đã duyệt |
| E2EE | **THAY ĐỔI 2026-09-26** | — | Nội dung tài chính sao lưu: **mã hoá phía client (zero-knowledge)**, xem §18.4 + `docs/p8-cloud-backup-architecture.md`. Metadata Auth/phiên/ví vẫn không E2EE. *(Bản cũ: Không E2EE ở v1.)* Ngăn xếp: TLS + mã hoá lúc nghỉ của nhà cung cấp + Auth/Rules/server chặt + App Check + DB cục bộ mã hoá. Không được mô tả Firebase là E2EE | E2EE phá Rules/sync/khôi phục | Đã duyệt |
| Cập nhật `spec.md`/`CLAUDE.md` §7 (mô hình `families/memberIds` cũ) | **DONE ở P2** | — | Đã thay bằng Account/Wallet/FinancialMember/Membership (xem Phụ lục C) | Tránh hai mô hình mâu thuẫn | Đã làm |

---

## Phụ lục A — Danh sách tham chiếu mã nguồn đã audit
`lib/data/local/app_database.dart` (bảng, migration, `_openConnection`, seed khi `wasCreated`) · `lib/data/local/seed_defaults.dart` · `lib/domain/entities/family_member.dart` · `lib/domain/entities/pool_kind.dart` (`savingsAssetRefId`) · `lib/core/utils/id_generator.dart` · `lib/core/constants/advanced_system_categories.dart` · `lib/core/constants/default_categories.dart`, `default_funds.dart` · `lib/presentation/providers/{primary_fund_provider, explorer_sort_provider, app_state_providers, sync_mode_provider, feature_providers}.dart` · `lib/main.dart` · `pubspec.yaml` · `android/app/src/main/AndroidManifest.xml` · `spec.md` (mô hình Firestore cũ) · `CLAUDE.md` §7, §14, §19.

## Phụ lục B — Điều KHÔNG làm trong phase này
Không thêm gói Firebase mới (các gói `firebase_*` đã có trong `pubspec.yaml` từ trước, chưa khởi tạo), không tạo dự án Firebase, không Auth, không đổi schema Drift, không di trú Pixel, không tải dữ liệu, không màn hình Account, không đổi ngữ nghĩa giao dịch.

## Phụ lục C — Quyết định đã duyệt sau P1 & thay đổi thực hiện ở P2

**Quyết định chốt (P2, 2026-09-21):** Personal Free hoàn toàn cục bộ, không đăng nhập; Personal Pro sau này: Account + sao lưu/đồng bộ/khôi phục + 1 Account 1 thiết bị; Family sau này: 1 Wallet, đúng 1 Owner, 0–1 Member, Owner mời bằng email, `memberId` ổn định sở hữu danh tính tài chính, thay tài khoản KHÔNG di trú lịch sử; 1 Wallet = 1 SQLite, registry mỏng ở phase sau, UI v1 1 ví; mã hoá DB bắt buộc trước cloud/pilot/Play (không ở P2); Quỹ chính = WALLET DATA; sắp xếp/lọc Explorer = DEVICE-ONLY; Auth = Google trước, độc lập nhà cung cấp; không chuyển quyền Owner ở v1; cả hai thấy toàn Wallet ở v1; không E2EE ở v1; tombstone tối thiểu không tự nén.

**Quy tắc bổ sung:**
- **Danh tính gắn tài khoản là chuyện của phase sau; Account ≠ FinancialMember.** P2 KHÔNG có Account/Auth/Owner/Invite/Firebase/sync/createdByAccountId.
- **Không đoán "bạn là Vợ hay Chồng"** ở P2. Phase claim sẽ hỏi rõ "Bạn là ai trong Ví hiện tại?"; thành viên được chọn gắn vào Owner Account, thành viên còn lại là slot Member chưa gắn. Người được mời sau này gắn vào **`memberId` ĐÃ CÓ**, không tạo FinancialMember mới (nếu Owner claim `chong` rồi mời Vợ ⇒ gắn vào `vo`; ngược lại tương tự).
- **Nguồn sự thật Owner:** `wallet.ownerAccountId` là chuẩn (xem §13).
- **Giới hạn thu hồi:** chỉ chặn được truy cập cloud tương lai, không xoá hồi tố dữ liệu đã lưu đệm offline (xem §13).

**Đã thực hiện ở P2 (schema v8, cộng thêm):**
- `wallet_meta` — SINGLETON (khóa chính CHECK = 1): `wallet_id` mờ (UUID v4 sinh 1 lần), `kind = local`, `created_at`.
- `financial_member_rows` — `member_id`, `label`, `display_order`, `created_at`; Wallet di sản: `vo`/"Vợ", `chong`/"Chồng" (giữ nguyên token đang nằm trong `*_ref_id`, nên **không viết lại dòng nào**).
- **Chiến lược ID:** Wallet di sản dùng `vo`/`chong` vì ĐÚNG là chuỗi mà mã hiện tại còn ghi vào cột ref. Wallet/thành viên MỚI dùng ID mờ (`OpaqueId`). ID mờ chỉ nối vào ứng dụng ở phase "thành viên là dữ liệu" (khi enum `FamilyMember` được thay). Trước đó mọi DB (kể cả cài mới) dùng `vo`/`chong` để giữ tương thích; đó là quyết định tương thích di sản, **không** phải chiến lược ID chung.
- **Lớp phân giải thành viên:** `WalletMemberResolver` ánh xạ `FamilyMember` ↔ `FinancialMember` (không đổi hành vi hiển thị).
- **Descriptor ví:** `WalletDescriptor` + `AppDatabase(wallet: …)`; DB hiện tại = `WalletDescriptor.legacyLocal` (file `vi_nha_minh.sqlite`, KHÔNG di chuyển). Registry bền vững nhiều ví **hoãn** tới phase cách ly Account/Wallet, vì thêm ngay sẽ mở rộng phạm vi khởi động không cần thiết.
