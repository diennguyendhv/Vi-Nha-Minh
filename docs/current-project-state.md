# Current Project State

> Bộ nhớ dài hạn của repo cho các phiên Claude mới. Giữ NGẮN (≤ ~250 dòng), không phải nhật ký — lịch sử dùng `git log`.
> Đọc kèm: `CLAUDE.md`, `docs/account-wallet-security-foundation.md` (kiến trúc Account/Wallet, §31 lộ trình), `docs/financial-core-v2.md` (nguồn sự thật tài chính).

## Product
**Ví Nhà Mình** (tên quốc tế HomeWallet) — app Flutter/Android quản lý chi tiêu cá nhân/gia đình, **local-first** (SQLite/Drift). Chưa có Account/Auth/Firebase/cloud.

## Current Phase
**P3 — Local Security — PASS** (nghiệm thu Pixel 2026-09-21). Phase kế tiếp (chưa bắt đầu, chờ duyệt): **P4 — FinancialMember là dữ liệu**.

## Last Completed Phase
P3 (App Lock + tắt Android Auto Backup). Trước đó: P2 Local Wallet Identity — PASS (`22560a1`, `7dc8e9d`).

## Current Schema
**v8** (v7→v8 cộng thêm, nguyên tử): `wallet_meta` (singleton) + `financial_member_rows`. P3 KHÔNG đổi schema.

## Local Wallet Architecture
- 1 Wallet cục bộ hiện tại = 1 file SQLite `vi_nha_minh.sqlite` (không di chuyển).
- `wallet_meta` singleton, `walletId` mờ và ổn định.
- Chưa Account/Auth/Firebase. Registry nhiều Wallet vật lý hoãn lại (đích: 1 Wallet = 1 SQLite; UI v1 chỉ 1 ví).

## Financial Members
Wallet cục bộ di sản dùng `memberId = vo` / `chong` (ID tương thích, đã nằm trong `*_ref_id`).
Wallet/thành viên MỚI sau này dùng ID mờ ổn định. **Không giả định toàn cục `memberId == vo/chong`**; chỉ qua lớp `WalletMemberResolver`.

## Live Data Rule
Chủ dự án đang nhập DỮ LIỆU THẬT trên Pixel. Mốc kiểm chứng gần nhất: 1.808 giao dịch — **chỉ là mốc tham chiếu, KHÔNG phải số bắt buộc**.
Mỗi phase di trú/bảo mật: **đọc DB Pixel THỰC TẾ trước**, sao lưu + kiểm chứng, so sánh trước/sau field-by-field. Không bao giờ khôi phục về số dòng cũ chỉ vì mốc 1.808.

## Reference Checkpoint (live data may have advanced)
Mốc gần nhất đã xác minh (2026-09-21), chỉ để đối chiếu:
- 1.808 giao dịch; master data: 17 danh mục, 11 trạng thái, 1.569 giao dịch `status_id` NULL.
- Tổng tài sản 80.538.000; doanh thu 301.954.000; chi phí KD 24.790.000; chi tiêu 220.599.000.
- SQLite integrity ok, FK rỗng.
(Không chép ghi chú giao dịch riêng tư vào file này.)

## Locked Architecture Decisions
- Wallet là container tài chính; Personal Free KHÔNG cần Account (local).
- 1 Wallet = 1 SQLite (đích); kiến trúc cho phép nhiều Wallet, UI v1 một ví hoạt động.
- Family: đúng 1 Owner + tối đa 1 Member; cả hai thấy toàn bộ Wallet.
- FinancialMember ổn định; email là danh tính mời/đăng nhập, KHÔNG là danh tính tài chính; Owner/Member là quyền, Vợ/Chồng là người.
- Đổi tài khoản gắn với Member không đổi memberId/lịch sử. Chỉ Owner quản trị membership. Không chuyển Owner ở v1.
- 1 Account = 1 thiết bị hoạt động. Google Auth trước; lớp Auth độc lập nhà cung cấp; lời mời do backend tạo/gửi.
- Không E2EE ở v1. Mã hoá DB cục bộ BẮT BUỘC trước cloud pilot/Play (SQLCipher hoặc tương đương, khoá DB độc lập với PIN).
- Quỹ chính (primary fund) là WALLET DATA (tạm còn SharedPreferences); sắp xếp/lọc Explorer là DEVICE-ONLY.
- Cloud sau này xoá bằng tombstone; xoá cục bộ hiện tại giữ nguyên ngữ nghĩa (xoá thật) cho tới phase đồng bộ.
- App Lock / sinh trắc là DEVICE security, không phải Account Auth, không đồng bộ.

## Financial Core Invariants (tóm tắt; đầy đủ ở financial-core-v2.md)
- Income / External Expense / Transfer là 3 tổng tách biệt; Transfer không vào Thu/Chi.
- Mọi giao dịch đi qua 1 `applyEffect`; Category chỉ là nhãn báo cáo, dòng tiền nằm trên Transaction (source/destination).
- Mọi pool (khả dụng, quỹ, tiết kiệm) không bao giờ âm; kiểm tra ở tầng ghi. Status không bao giờ đổi số dư.
- Xoá giao dịch = xoá thật cả họ; chặn khi làm pool âm/dính Vay-Hoàn tiền. Sửa số tiền/người = thay dòng.
- Category/Status/Quỹ/Loại tiết kiệm do gia đình tạo; hạng mục không hardcode theo id.

## Current Security State
- **App Lock thật (P3):** PIN 6 số; verifier = HMAC-SHA256(khoá Android Keystore không xuất được, PBKDF2(pin, salt ngẫu nhiên, 210k vòng)) trong `AppLockBridge.kt`, lưu ở SharedPreferences native `app_lock_secure` (không phải SQLite/prefs Flutter). API 24–25 chỉ dùng PBKDF2WithHmacSHA1 làm KDF dự phòng, vẫn HMAC Keystore.
- Chặn dò PIN từ lần sai thứ 5 (30s→30p), lưu bền. Quên PIN = xác minh khóa màn hình hệ thống rồi đặt PIN mới; không cửa hậu, không xoá dữ liệu.
- Sinh trắc tuỳ chọn (chỉ mở khoá phiên). Trạng thái mở khoá chỉ trong RAM; khởi động lạnh/nền ≥30s ⇒ khoá; `LockGate` không dựng nội dung tài chính khi khoá; `FLAG_SECURE` khi rời foreground.
- **Android Auto Backup TẮT:** `allowBackup=false` + `backup_rules.xml` + `data_extraction_rules.xml` (loại trừ mọi domain, cloud & device-transfer).
- **SQLCipher/mã hoá DB: CHƯA làm — vẫn BẮT BUỘC trước cloud pilot/Play.** App Lock không bảo vệ DB-at-rest.

## Release Gates
- Gỡ/vô hiệu hoá cứng debug real-data importer trước Play (CLAUDE.md §19).
- Không commit DB thật/Excel/backup; không đóng gói vào APK/AAB.
- Android Auto Backup phải tắt (allowBackup=false + rules) — P3.
- Mã hoá DB cục bộ trước cloud pilot/Play.
- Kiểm thử Auth + Firestore Rules (emulator) trước Family pilot.

## Testing (kết quả P3 — gate mới nhất)
`flutter test --concurrency=1`: 958 pass, 3 skip; Golden 24/24; `flutter analyze` 15 issue có sẵn, 0 lỗi; không đổi schema. Test bảo mật: `test/presentation/security/`, `test/security/android_security_config_test.dart`.
Pixel: DB trước/sau P3 giống field-for-field (chỉ +1 giao dịch do chủ máy tự nhập lúc nghiệm thu); walletId + financial_member_rows không đổi; integrity ok; FK rỗng.
Gate: `flutter test --concurrency=1` một lần cuối phase; analyze cuối phase; Golden chỉ khi UI ảnh hưởng.

## Known Backlog
- Giới hạn P3: phần Kotlin (Keystore/PBKDF2/chặn tạm) chỉ kiểm chứng trên thiết bị, không unit test được.
- FinancialMember enum → dữ liệu (P4); registry Wallet bền (P6); Auth (P5); phiên thiết bị độc quyền (P7).
- Claim + Personal Pro sao lưu/khôi phục (P8); đồng bộ (P9); Family (P10); SQLCipher trước P8.
- Backlog UI/i18n không chặn (chuỗi hardcode tiếng Việt, `Formatters.amount` VNĐ cứng).
- Backlog: rà soát clientTxId/tombstone/idempotency trước đồng bộ.

## Next Planned Phases (docs/account-wallet-security-foundation.md §31)
P3 ✅ → P4 Thành viên là dữ liệu → P5 Nền Auth & môi trường → P6 Cách ly Account/Wallet → P7 Phiên thiết bị độc quyền → P8 Claim + Pro sao lưu/khôi phục → P9 Đồng bộ Personal → P10 Membership Family.
Mỗi phase kết thúc: test → nghiệm thu Pixel → sao lưu → DỪNG chờ duyệt.
