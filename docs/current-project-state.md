# Current Project State

> Bộ nhớ dài hạn của repo cho các phiên Claude mới. Giữ NGẮN (≤ ~250 dòng), không phải nhật ký — lịch sử dùng `git log`.
> Đọc kèm: `CLAUDE.md`, `docs/account-wallet-security-foundation.md` (kiến trúc Account/Wallet, §31 lộ trình), `docs/financial-core-v2.md` (nguồn sự thật tài chính).

## Product
**Ví Nhà Mình** (tên quốc tế HomeWallet) — app Flutter/Android quản lý chi tiêu cá nhân/gia đình, **local-first** (SQLite/Drift). Auth tuỳ chọn (P5, chỉ danh tính); dữ liệu tài chính chưa lên cloud.

## Current Phase
**P8.3–P8.5 — Personal encrypted backup, delta sync, restore — AUTOMATED PASS (fake backend + Firebase emulator + real SQLCipher host tests, 2026-09-27). LIVE DEV Pixel: PENDING (no UI yet; needs owner's Backup Password + Google re-auth).** Schema v11 (additive: `sync_state.backup_state`, `sync_conflicts`) — PROD NOT migrated. DEV Functions deployed (`enableBackup` + updated batch/changes; Family endpoints NOT deployed). Idle worker = 0 cloud calls. Restore = new final-named SQLCipher file + own key (no rename), activation after full verification. Account-switch gate (`WalletAccessGate`): Family/claimed Wallet hidden from other Accounts without deleting anything. Family backend (invite/accept/key-share storage/revoke) emulator PASS but client + key-wrap crypto NOT done. Details: CLAUDE.md §26–27, `docs/p8-cloud-backup-architecture.md` §8e. PROD untouched.

**P8.2 — Explicit Personal Wallet Claim + trusted backend — PASS (code + emulator + DEV live Pixel, 2026-09-26)**. DEV: claim/idempotent replay/stale 403/sign-out offline/wrong account/abandon/App Lock đều PASS; revoked chỉ kiểm ở emulator. `claimWallet`/`getWalletClaim`/`abandonClaim` (1 Firestore transaction, P7.1 authorize, chỉ metadata sở hữu, whitelist trường), `putEncryptedBatch` từ chối ví đã claim. App: `WalletClaimService` (NONE→CLAIMING→ACTIVE, id lưu trước khi gọi mạng, retry cùng id, release khi máy chủ từ chối dứt khoát), `WalletClaimControls` ("Sao lưu ví này", "Bạn là ai?", xác nhận, step-up), registry đồng bộ TỪ DB lúc khởi động; ví Personal vẫn mở khi đăng xuất/offline. Chỉ DEV. PROD không claim/không đụng. Chi tiết CLAUDE.md §25, `docs/p8-cloud-backup-architecture.md` §8d.

**P8.1 — Local Cloud-Sync Foundation (schema v10) — PASS (code + PROD, 2026-09-26)**: `cloud_binding` (NONE/CLAIMING/ACTIVE, DB là nguồn sự thật), `sync_outbox` (trigger SQLite, chỉ khi ACTIVE; chỉ danh tính/ý định, gộp, tombstone, ack theo seq), `sync_state` (cờ `withoutSyncCapture` trong 1 transaction), `wallet_settings` (quỹ chính chuyển từ prefs, prefs = dự phòng đọc + di trú 1 lần), `SeedProfile.none` (rỗng tuyệt đối, SQLCipher từ lúc tạo). Test phủ bảng bắt buộc. Không upload, không claim, BackupGate đóng. Chi tiết: CLAUDE.md §24, `docs/p8-cloud-backup-architecture.md` §8c.
PROD (Pixel, `install -r`): trước v9 / sau v10; **1.849 → 1.849** giao dịch; 9/9 bảng cũ trùng số dòng + digest; walletId `3cbd8878…` không đổi; integrity ok, FK 0; SQLCipher 4.18 vẫn bật (bản kéo ra: sqlite3 thường "file is not a database"); `cloud_binding` 0, `sync_outbox` 0, `sync_state` 0, `sqlite_sequence` = (sync_outbox, 0) ⇒ chưa từng có dòng outbox; `wallet_settings` 1 dòng `primary_fund_id = an_uong` (đúng giá trị prefs); Home trước/sau/sau force-stop trùng từng pixel. Không upload. Sao lưu mã hoá trước di trú: `Documents/ViNhaMinh_backups/2026-09-26/p8_1_pre/` + trên máy `_p8_1_pre_backup/` (SHA-256 `ead04837…3dff`). Lưu ý công cụ: logcat cắt `[db-report]` ở ~1 KB khi có 14 bảng — đọc phần còn lại trên màn hình báo cáo.

**SQLCipher Local DB Encryption — PASS** (2026-09-26): mọi file ví mã hoá bằng SQLCipher 4.18, khoá riêng mỗi ví bọc bằng Keystore; PROD di trú tại chỗ (1.849 → 1.849 giao dịch, 9/9 bảng trùng digest, walletId/v9/integrity/FK giữ nguyên), bản sao PROD kéo ra không đọc được. Mất khoá ⇒ màn khôi phục, không tạo khoá mới. Chi tiết `docs/sqlcipher-local-encryption.md`. Cổng dữ liệu thật lên cloud VẪN ĐÓNG (chưa có engine P8).

**P7.1 + P8 Security Foundation — PASS (DEV deploy + Pixel DEV, 2026-09-26)**. Mật khẩu sao lưu chuẩn hoá NFC (`kdf.norm`). Chưa live: B hoàn tất grant đã duyệt / dùng lại / hết hạn / sai installation và rate limit (chỉ emulator). P7.1: Auth một mình không thay thiết bị active (TAKEOVER_REQUIRED), chuyển máy cần A chấp thuận, mất máy cần credential suy ra từ Mật khẩu sao lưu/Recovery Key (epoch+1, máy cũ DEVICE_REVOKED). P8 crypto: BMK/DEK/IDK, Argon2id + Recovery Key, envelope chung không lộ loại thực thể, backend chỉ nhận ciphertext, chỉ fixture DEV (cổng SQLCipher). Chi tiết: `docs/p7-exclusive-session.md` (P7.1), `docs/p8-cloud-backup-architecture.md`. Full backup/restore engine, claim, đồng bộ: CHƯA.

**P7 — Exclusive Account Session Foundation — PASS** (2026-09-26). Callable DEV `vi-nha-minh-55c60` (Node 22) đã triển khai; Pixel: kích hoạt tường minh, Keystore giữ qua force-stop, thiết bị cũ bị SERVER từ chối (403), đăng xuất cũ không tắt được phiên mới, kích hoạt lại thay thế, đăng xuất xoá credential. Rules deny-all. Không dữ liệu tài chính trên cloud; Wallet không claim. PROD chỉ đọc: v8, integrity ok, FK 0, 1.849 giao dịch. Chi tiết: `docs/p7-exclusive-session.md`. **P8 chưa bắt đầu.**

## Last Completed Phase
P7 (phiên độc quyền, PASS). P6/P6.1 (cách ly Wallet, PASS). P5 (Auth & môi trường, PASS). Trước đó P4 (enum `FamilyMember` bị xoá; thành viên = dữ liệu). Trước đó P3 (App Lock + tắt Auto Backup), P2 Local Wallet Identity — PASS (`22560a1`, `7dc8e9d`).

## Current Schema
**v11** on DEV/tests (v10→v11 additive: `sync_state.backup_state`, `sync_conflicts`); PROD still **v10**. Previously **v10** (v9→v10 cộng thêm, nguyên tử, P8.1): `cloud_binding`, `sync_outbox`, `sync_state`, `wallet_settings` + trigger `sync_capture_*`. v9: `actor_member_id`. v8: `wallet_meta` + `financial_member_rows`.

## Auth & Environments (P5)
- 3 môi trường qua Android flavor + `AppEnvironment.current` (nguồn duy nhất, từ `appFlavor`): dev=`com.vinhamimh.vi_nha_minh.dev`, pilot=`...pilot`, prod=`com.vinhamimh.vi_nha_minh` (không đổi). Mỗi môi trường 1 dự án Firebase riêng; cấu hình client công khai qua `--dart-define-from-file=env/<env>.json` (mẫu `env/*.example.json`; file thật gitignored; `FirebaseEnvConfig.isUsableFor(env)` từ chối cấu hình khác môi trường/giá trị mẫu). Không có google-services.json/service account trong repo.
- `AuthRepository` (domain, độc lập nhà cung cấp) → `FirebaseAuthRepository` (Firebase Auth + `google_sign_in` 7.x) / `UnavailableAuthRepository` khi chưa cấu hình. `bootstrapAuth()` không bao giờ ném; app local khởi động không phụ thuộc mạng. `AccountIdentity` chỉ uid/email/tên/ảnh/provider — KHÔNG walletId/memberId/vai trò.
- UI: thẻ Tài khoản đầu Cài đặt (`AccountSettingsCard`), đăng nhập TUỲ CHỌN, không claim/upload. Đăng xuất chỉ xoá phiên; Wallet cục bộ + App Lock giữ nguyên.
- **Mạng:** P5 Auth; P7 thêm callable session DEV (UUID/credential phiên, không tài chính). Không import Firestore/Storage ở đâu trong `lib/` (test tĩnh). Financial data vẫn 100% local. `CloudSession` tách biệt App Lock/Wallet, secret lưu qua Keystore; chi tiết `docs/p7-exclusive-session.md`.

## Local Wallet Architecture (P6)
- 1 Wallet = 1 file SQLite. Ví cục bộ hiện tại = `vi_nha_minh.sqlite` (không di chuyển), `wallet_meta` singleton, `walletId` mờ ổn định.
- **Registry toàn app** `wallet_registry.json` (thư mục tài liệu, ghi nguyên tử; `WalletRegistry`, `data/local/wallet_registry.dart`): chỉ metadata (`walletId`, `kind`, `dbFileName` thuần, `createdAt`, `boundAccountId?`). `main` gọi `bootstrapWalletRegistry()` (không bao giờ ném) đăng ký ví cục bộ TẠI CHỖ, idempotent; registry hỏng ⇒ rỗng và tự đăng ký lại đúng walletId. Xoá registry không xoá ví.
- **Phạm vi phiên** `WalletAccessScope` (local | account(uid)) từ `accountProvider` (chỉ uid). `WalletRegistryEntry.canOpen`: ví LOCAL chưa claim mở được ở mọi phạm vi; ví gắn Account mở bởi đúng Account đó, và (P8.2) ví Personal còn mở được ở phạm vi local (đã đăng xuất) — Account khác thì không. `resolveActive` ưu tiên ví gắn Account, rồi ví cục bộ. Đăng nhập KHÔNG gắn/claim/đổi kind; `boundAccountId` chỉ được gán bằng `reconcileRegistryFromDb` phản chiếu `cloud_binding` ACTIVE (P8.2).
- `appDatabaseProvider` watch `activeWalletProvider`: đổi ví/Account ⇒ DB cũ đóng, mọi repository/stream dựng lại. `selectedWalletIdProvider`, `currentTabProvider`, `syncModeProvider`, `primaryFundIdProvider` gắn `walletSessionKeyProvider` nên reset khi đổi ví/đăng xuất. Đăng xuất chỉ xoá phiên; file ví, App Lock, prefs thiết bị giữ nguyên.
- Primary fund = WALLET data trong `wallet_settings` (v10); khoá prefs cũ (`primary_fund_id` / `primary_fund_id.<walletId>`) chỉ còn đọc dự phòng + di trú 1 lần. Explorer sort/App Lock = DEVICE, không đổi.

## Financial Members
Runtime = bảng `financial_member_rows` qua `MemberRepository` (`watchMembers/getMembers/getMemberById/createMember`), UI qua `memberDirectoryProvider` (`MemberDirectory`: nhãn, mặc định = đầu theo `displayOrder`, `otherThan`). Enum `FamilyMember` và `WalletMemberResolver` đã XOÁ; domain dùng `String memberId`.
Wallet di sản hiện tại: `memberId = vo`/`chong` (giữ nguyên, đã nằm trong `*_ref_id`). DB MỚI (`SeedProfile.fresh`): 2 thành viên ID mờ (`OpaqueId`), nhãn Vợ/Chồng; `createMember` cũng ID mờ. Không suy nhãn từ `memberId`. Nợ tạm: thành viên mặc định = người đầu theo `displayOrder`; `'vo'/'chong'` còn ở seed di sản + importer debug (đã tự khoá vì đòi schema v7). Chi tiết: `docs/p4-financial-member-audit.md`.

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
- Nội dung tài chính sao lưu mã hoá phía client (zero-knowledge, 2026-09-26); metadata Auth/phiên/ví không E2EE. Mã hoá DB cục bộ BẮT BUỘC trước cloud pilot/Play (SQLCipher hoặc tương đương, khoá DB độc lập với PIN).
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
- **SQLCipher: ĐÃ BẬT (2026-09-26)** — khoá mỗi ví trong Keystore, độc lập App Lock; App Lock không phải lớp mã hoá.

## Release Gates
- Gỡ/vô hiệu hoá cứng debug real-data importer trước Play (CLAUDE.md §19).
- Không commit DB thật/Excel/backup; không đóng gói vào APK/AAB.
- Android Auto Backup phải tắt (allowBackup=false + rules) — P3.
- ~~Mã hoá DB cục bộ~~ ✅ (SQLCipher). Gỡ thêm công cụ debug DB benchmark/báo cáo toàn vẹn trước Play.
- Kiểm thử Auth + Firestore Rules (emulator) trước Family pilot.

## Testing (gate mới nhất — P6.1 đang nghiệm thu)
P6.1: Summary chỉ có Ngày/Tháng/Năm, không còn All time; Transaction/Summary dùng chung `TransactionRow`; trường số tiền Add/Edit dùng state cục bộ để gõ không ghi DB. `Số liệu` dùng `computeFinancialSummary` cho số dư/tổng tài sản. `flutter test --concurrency=1` pass; `flutter analyze` có 15 info deprecated có sẵn, 0 error. PROD updated in place bằng APK ký tương thích (không uninstall/clear). Pixel: Summary mới đúng, có `Số liệu`, dòng giao dịch mới, nhập tiền + preview/bàn phím hệ thống hoạt động và form đóng không lưu. PROD trước/sau: SHA-256 `803de56…420771eb6`, integrity ok, FK rỗng, 1.822 giao dịch, schema v9, walletId `3cbd8878…` không đổi. Backup: `Documents/ViNhaMinh_backups/2026-09-22/p6_1_pre`.
P6.1 mở rộng (2026-09-26): mọi giao dịch (kể cả Chi từ Quỹ, Chuyển, Tiết kiệm) hiện trong Tổng hợp, chỉ Thu/Chi được cộng; mọi nơi mở cùng chi tiết/sửa/xóa theo `Transaction.id`; repository chặn đổi nhóm chính (`MainGroupChangeException`). Chưa commit. PROD chỉ đọc: 1.849 giao dịch, schema v8, integrity ok.

P6: `flutter test --concurrency=1` 1022 pass, 3 skip; analyze 15 info có sẵn, 0 lỗi; không đổi schema (v8). Test: `test/wallet/*`. Pixel prod: DB sha256 trước/sau giống hệt (1.809 giao dịch, walletId `3cbd8878…`); registry tạo đúng 1 dòng local. DEV: phiên Auth giữ, registry không đổi khi đăng nhập/đăng xuất, sandbox tách biệt. Lưu ý: flavor prod chưa có `env/prod.json` ⇒ Auth prod "chưa cấu hình", nên đăng nhập chỉ thử trên DEV. Backup: `ViNhaMinh_backups/2026-09-21/p6_pre|p6_post`.
Widget-local state (bộ lọc trong màn hình) chưa reset khi đổi ví — chưa có UI đổi ví ở v1.
P5 (tham chiếu):
P5: `flutter test --concurrency=1` 1005 pass, 3 skip; `flutter analyze` 15 info có sẵn, 0 lỗi; không đổi schema. Test P5: `test/auth/*`.
P4 (tham chiếu): 977 pass. Test P4: `test/domain/financial_member_as_data_test.dart` (ID mờ + nhãn "Vợ", repo, directory), thêm ca P4 ở home/add/summary widget test; fixture `test/support/legacy_members.dart`.
Pixel: DB trước/sau P4 giống byte-for-byte (1.809 giao dịch); walletId + `financial_member_rows` không đổi; integrity ok.
Gate: `flutter test --concurrency=1` một lần cuối phase; analyze cuối phase; Golden chỉ khi UI ảnh hưởng.

## Known Backlog
- Giới hạn P3: phần Kotlin (Keystore/PBKDF2/chặn tạm) chỉ kiểm chứng trên thiết bị, không unit test được.
- P7 giới hạn (giữ trung thực): token Firebase của thiết bị cũ không bị thu hồi; secret là bearer, không phải attestation; đăng xuất offline có thể để bản ghi server active tới khi bị thay; App Check chưa là quyền phiên; P8+ ghi tài chính phải kiểm tra phiên trong CÙNG transaction.
- Claim + Personal Pro sao lưu/khôi phục (P8); đồng bộ (P9); Family (P10); SQLCipher trước P8.
- Backlog UI/i18n không chặn (chuỗi hardcode tiếng Việt, `Formatters.amount` VNĐ cứng).
- Backlog: rà soát clientTxId/tombstone/idempotency trước đồng bộ.

## Next Planned Phases (docs/account-wallet-security-foundation.md §31)
P3 ✅ → P4 Thành viên là dữ liệu → P5 Nền Auth & môi trường → P6 Cách ly Account/Wallet → P7 Phiên thiết bị độc quyền → P8 Claim + Pro sao lưu/khôi phục → P9 Đồng bộ Personal → P10 Membership Family.
Mỗi phase kết thúc: test → nghiệm thu Pixel → sao lưu → DỪNG chờ duyệt.


Schema v9 (2026-09-26): `actorMemberId` cho Chi từ Quỹ; sửa đầu nguồn/đích Chuyển theo `transferKind`; sửa giữ nguyên `Transaction.id`. Xem docs/phase-p6-1.md.
