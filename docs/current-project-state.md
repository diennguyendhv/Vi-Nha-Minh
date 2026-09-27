# Current Project State — Ví Nhà Mình / HomeWallet

> Bộ nhớ dài hạn của repo. Phiên Claude/Codex MỚI đọc: (1) `CLAUDE.md`, (2) file này,
> (3) chỉ tài liệu kiến trúc liên quan trực tiếp tới phase đang làm. Sau đó chỉ đọc code
> liên quan. KHÔNG đọc lại hội thoại cũ, KHÔNG audit lại các phase đã PASS.
> Giữ file này ngắn; lịch sử chi tiết = `git log` + tài liệu kiến trúc.

**CURRENT PHASE:** P11 — Real Family Pilot Monitoring
**CURRENT STATUS:** Pilot thật hai vợ chồng đang chạy trên production (từ 2026-09-27).
**NEXT PHASE:** P12 — Pilot UX / Reliability Fixes
**STOP CONDITION:** KHÔNG bắt đầu P12 cho tới khi đã thu thập quan sát pilot (báo cáo
P11) hoặc chủ dự án yêu cầu tường minh.

---

## 1. Trạng thái sản phẩm (2026-09-27)
- Hai vợ chồng dùng CHUNG 1 Wallet thật trên 2 điện thoại (Pixel 7a của chồng, Xiaomi
  23090RA98G của vợ), đồng bộ mã hoá hai chiều tự động.
- Lịch sử tài chính thật được giữ nguyên qua di trú production. Lúc bắt đầu pilot đã
  xác minh **1.853** giao dịch — đây là MỐC, KHÔNG phải số cố định: người dùng liên tục
  thêm giao dịch thật.
- Real Wallet: `walletId = 3cbd8878-58c3-41f0-a009-8d5f3c92b373`.
  - Owner Account = tài khoản của chồng → FinancialMember có sẵn `chong` ("Chồng").
  - Member Account = tài khoản của vợ → FinancialMember có sẵn `vo` ("Vợ").
  - Account ≠ FinancialMember; Owner/Member là QUYỀN, Chồng/Vợ là NGƯỜI.
  - (Email chỉ ghi ở tài liệu vận hành nội bộ; KHÔNG hiển thị email không cần thiết trên UI.)
    Owner: diennguyendhv@gmail.com · Member: kerenza1111@gmail.com.
- Chưa phát hành CH Play. App thật = bản release-signed cài tay (sideload).

## 2. Kiến trúc cloud hiện hành
- **MỘT dự án Firebase duy nhất: `vi-nha-minh-55c60` = PRODUCTION CLOUD.** Chứa: Auth thật,
  Functions production (codebase `p7-session`, Node 22, `maxInstances 5`, không
  minInstances), Firestore (chỉ Functions ghi; rules deny-all), bản sao lưu mã hoá của
  Wallet thật, membership Family, dữ liệu đồng bộ mã hoá, FCM.
- Khái niệm cũ "vi-nha-minh-55c60 = DEV" đã LỖI THỜI.
- Backend `functions/env.js`: allowlist project → môi trường (`vi-nha-minh-55c60` → `prod`,
  emulator `demo-homewallet-p7` → `dev`); project không liệt kê ⇒ mọi callable bị từ chối.
- Mọi lời gọi mang `clientEnv`, máy chủ bắt buộc khớp (`CLIENT_ENVIRONMENT`) ⇒ bản DEV
  (kể cả bản cũ đã cài) không thể ghi vào production.
- App PROD `com.vinhamimh.vi_nha_minh` dùng dự án thật (`env/prod.json`, gitignored,
  `CLOUD_ENABLED=true`; App Android đã đăng ký trong Firebase với SHA debug + release).
- App DEV `com.vinhamimh.vi_nha_minh.dev`: CHỈ Firebase Emulator Suite
  (`FIREBASE_EMULATOR_HOST` + project `demo-*`), fixture cục bộ, tài khoản test. Không có
  override. KHÔNG tải fixture tài chính lên production.
- Dữ liệu thử lịch sử trong dự án (ví `dc268fde…` claim khi còn là DEV, ví `fixture-…`,
  3 lời mời thử, tài khoản test B/X, người dùng ẩn danh) bị ĐÓNG BĂNG
  (`ENVIRONMENT_MISMATCH`, ẩn khỏi `listBackupWallets`), CHƯA xoá — xoá chỉ khi chủ dự án
  duyệt từng mục (P13).
- Local-first khoá cứng: UI chỉ đọc SQLite. Cloud = vận chuyển / sao lưu / đồng bộ Family.

## 3. Phát hành & bảo mật
- Bản thật ký bằng khoá RELEASE nằm NGOÀI git: `C:\Users\Admin\Documents\ViNhaMinh_keys\`
  (`release.jks` + `key.properties`), SHA-256 `0b723838…d677`. Gradle đọc qua
  `HW_RELEASE_KEY_PROPERTIES` hoặc đường dẫn mặc định; thiếu file ⇒ release không được ký
  (không bao giờ lặng lẽ ký debug). Mất khoá ⇒ không cập nhật đè được app ⇒ chủ dự án phải
  sao lưu thư mục này.
- APK release hiện hành: `C:\Users\Admin\Documents\ViNhaMinh_release\ViNhaMinh-1.0.0-prod-release.apk`
  (cập nhật tại chỗ bằng `adb install -r`, cùng khoá ⇒ giữ dữ liệu).
- KHÔNG BAO GIỜ commit: `release.jks`, `key.properties`, mật khẩu, Recovery Key, khoá riêng,
  `env/*.json` thật, DB/backup/Excel thật.
- DB thật: SQLCipher 4.18, khoá DB bọc bằng Android Keystore, độc lập App Lock.
- Cloud chỉ chứa ciphertext (`{v,id,rev,n,c,aad}`); máy chủ/admin không đọc được số tiền,
  ghi chú, danh mục, quỹ, thành viên; máy chủ không có BMK bản rõ.
- Sao lưu: Mật khẩu sao lưu + Recovery Key; tạo lại Recovery Key được.
- Phiên: 1 Account = 1 installation tin cậy đang hoạt động; tiếp quản / khôi phục mất máy.
- Family v1: 1 Owner + tối đa 1 Member.
- Bản release KHÔNG có công cụ debug (báo cáo toàn vẹn `[db-report]` chỉ có ở bản debug).

## 4. Các mốc đã PASS (KHÔNG làm lại / thiết kế lại khi không có bằng chứng lỗi)
- P1–P8.8: Financial Core cục bộ, repository, toàn vẹn, Vay, nền dữ liệu thật.
- P2 Wallet + FinancialMember · P3 App Lock · P4 thành viên là dữ liệu · P5 môi trường build
- P6 registry, 1 Wallet = 1 DB mã hoá · P6.1 hợp nhất hiển thị giao dịch
- P7 phiên thiết bị tin cậy · P7.1 tiếp quản an toàn · P8 kiến trúc zero-knowledge
- SQLCipher · P8.1 nền đồng bộ cục bộ · P8.2 claim Personal tường minh
- P8.3 sao lưu mã hoá ban đầu LIVE · P8.4 đồng bộ delta LIVE · P8.5 khôi phục Mật khẩu +
  Recovery Key LIVE
- P10 Family LIVE: Personal→Family tại chỗ; mời; ánh xạ Account↔FinancialMember; chia sẻ
  BMK zero-knowledge (SAS 12 số + Mã ví); chồng→vợ và vợ→chồng; tín hiệu FCM + dự phòng
  foreground; giữ bản thua khi xung đột; xoá-vs-sửa không hồi sinh; Account sai ⇒ ẩn ví;
  thu hồi Member; cùng Wallet sau khi đổi Account.
- Pilot production (2026-09-27): onboarding PASS — di trú v10→v11 diễn tập + thật (digest
  không đổi), claim + sao lưu COMPLETE, chuyển sang bản release (gỡ CHỈ sau khi sao lưu
  xong), khôi phục, mời vợ, đồng bộ tự động được chủ dự án xác nhận.
- Gate tự động gần nhất: **Flutter 1264 pass / 5 skip / 0 fail**, analyze 0 lỗi/0 cảnh
  báo; **backend emulator 31/31**. Commit gần nhất liên quan: `43b48c8`.

## 5. Hành vi đồng bộ trong pilot
- Chính: tín hiệu đẩy FCM data-only `{t:'head'}` tới máy thành viên kia sau mỗi batch.
- Dự phòng (`FamilyForegroundSync`): mở/quay lại app ⇒ kéo 1 lần + thử đăng ký tín hiệu
  lại; máy KHÔNG có tín hiệu đẩy ⇒ kéo ~30 giây/lần CHỈ khi app ở foreground; vào nền ⇒
  dừng (0 lời gọi).
- Lý do: máy Xiaomi của vợ từng trả `SERVICE_NOT_AVAILABLE` khi lấy token FCM; máy Owner
  chưa đăng ký tín hiệu vì ví thành Family khi app đang chạy.
- KHÔNG làm polling dày hơn; KHÔNG polling nền. Theo dõi pin + chi phí Firebase. Mục tiêu
  tương lai: giảm phụ thuộc vào polling dự phòng.

## 6. Giới hạn Family v1 đã chấp nhận
1. Lời mời gửi tay (chưa có email từ máy chủ).
2. UI xem lại xung đột tối giản (chỉ số đếm; bản thua nằm trong `sync_conflicts`).
3. Máy bị thu hồi mà offline vẫn giữ dữ liệu đã tải + BMK đã có.
4. Chưa xoay BMK sau khi thu hồi Member.
5. Hai máy offline cùng chi có thể làm tổng số dư âm sau khi hội tụ (chỉ phát hiện + cảnh báo).
6. Máy chủ không cưỡng chế được ngữ nghĩa số dư (payload là ciphertext).
7. Chưa bật App Check / Play Integrity.
8. Dự phòng foreground có thể kiểm tra ~30 giây/lần khi không có tín hiệu đẩy.
KHÔNG "giải" các giới hạn này bằng cách cho máy chủ đọc bản rõ tài chính.

## 7. Backlog pilot (không chặn; thuộc P12)
1. Sau khi tham gia Family phải mở lại app mới thấy dữ liệu.
2. Lỗi kích hoạt thiết bị quá chung chung ("Chưa thực hiện được") — nên nói "Hãy kích hoạt
   thiết bị trước".
3. Luồng mời nhiều bước/ô nhập dễ nhầm (Owner nhập nhầm mã 12 số vào ô "Mã mời").
4. Offline + outbox còn N có thể hiện cùng lúc "Đã đồng bộ" và "Chờ tải lên: N".
5. Chưa có màn xem chi tiết bản thua khi xung đột.
6. Cảnh báo thiếu font Manrope (đã rơi về font hệ thống).

## 8. Lộ trình từ mốc này (đánh số dùng từ nay)
**P11 — Real Family Pilot Monitoring — HIỆN TẠI.** ~1–2 tuần dùng thật, quan sát thay vì
thêm tính năng. Theo dõi: độ trễ chồng→vợ / vợ→chồng, outbox kẹt, giao dịch thiếu/trùng,
số xung đột, offline→online, sức khoẻ sao lưu, crash, phiên/Auth, pin Xiaomi, chi phí
Functions/Firestore, hành vi dự phòng 30 giây. Nghi ngờ ⇒ so sánh hai máy. Chỉ sửa NGAY khi:
mất dữ liệu tài chính, sai số dư, thiếu/trùng giao dịch, đồng bộ kẹt, sao lưu hỏng, lỗi
truy cập Family, lỗi bảo mật, crash chặn dùng hằng ngày. Còn lại ⇒ ghi cho P12.
Kết thúc P11 = báo cáo: A số ngày dùng · B số giao dịch thật tạo · C sự cố đồng bộ · D sự
cố sao lưu · E xung đột · F crash · G pin · H thay đổi chi phí Firebase · I phàn nàn UX của
chồng · J của vợ · K blocker · L danh sách sửa P12 chính xác. DỪNG sau báo cáo; KHÔNG tự
bắt đầu P12.

**P12 — Pilot UX / Reliability Fixes — ĐÃ LÊN KẾ HOẠCH.** Mở ví Family ngay sau khi tham
gia; thông báo kích hoạt thiết bị rõ ràng; gọn luồng Mời → Chấp nhận → So mã → Chia sẻ
khoá → Mở ví; trạng thái đồng bộ đúng khi offline/outbox; màn xem xung đột; dọn font; lỗi
tìm thấy ở P11. Không thiết kế lại Financial Core nếu không có lỗi đúng/sai thật. Test
có mục tiêu khi làm; 1 lần full suite khi ổn định.

**P13 — Technical Cleanup + Documentation — ĐÃ LÊN KẾ HOẠCH.** Gỡ/cô lập công cụ debug
khỏi source production; dọn dữ liệu cloud thử CHỈ khi được duyệt (không xoá tự động);
cập nhật `CLAUDE.md`, file này, `spec.md` (giả định Firestore realtime bản rõ đã lỗi thời),
`docs/design.html`, `AGENTS.md`; tài liệu hoá kiến trúc thật (SQLCipher cục bộ + đồng bộ
delta mã hoá + cloud zero-knowledge + phân quyền Account Family); cải thiện quy trình DEV
emulator (màn đăng nhập tài khoản test).

**P14 — Personal Free / Single-User Wallet — BẮT BUỘC TRƯỚC CH PLAY.** Người dùng mới cài
app có ví CÁ NHÂN cục bộ, không cần đăng nhập: đúng 1 FinancialMember nhãn mặc định "Tôi"
(đổi tên được), KHÔNG seed "Vợ"+"Chồng" (hiện `app_database.dart` seed 2 thành viên cho mọi
ví mới — phải đổi cho ví mới, ví thật giữ nguyên). UI chính: Thu, Chi; không có thao tác
"Chuyển" giữa thành viên; giữ Quỹ (Nạp tiền/Rút tiền), Tiết kiệm (Bỏ vào tiết kiệm/Rút tiết
kiệm), Danh mục, Trạng thái, Tổng hợp; ngữ nghĩa Transfer nội bộ giữ trong Financial Core.
Nâng cấp: "Mời người vào ví" ⇒ cần đăng nhập/cloud ⇒ mời thành viên thứ 2 ⇒ CÙNG Wallet,
CÙNG lịch sử ⇒ thành Family; không tạo Wallet thay thế. Phải chứng minh: ví mới = 1 thành
viên; không seed Vợ/Chồng; không có UI chuyển giữa thành viên; Quỹ + Tiết kiệm chạy; dùng
cục bộ không cần Account; Personal→Family giữ walletId/lịch sử; Wallet Family thật không bị
chạm.

**P15 — Budgets + Reminders.** Ngân sách tháng theo danh mục; cảnh báo theo tốc độ tiêu;
nhắc giao dịch nằm lâu ở trạng thái đầu; cảnh báo ít, hữu ích. Chỉ sau khi P14 ổn định.

**P16 — Reporting / Export.** Xu hướng tỷ lệ tiết kiệm 6–12 tháng; xu hướng chi tiêu dài
hạn; mục tiêu Quỹ + thời gian dự kiến; xuất CSV/Excel. Giữ local-first/quyền riêng tư.

**P17 — Play Store Readiness.** Gỡ công cụ debug; App Check / Play Integrity; biện pháp
chặn chi phí Firebase; chính sách quyền riêng tư; Data Safety; audit log + quyền; Play App
Signing (tiếp nối khoá release hiện có); AAB; Play internal testing; onboarding; Personal
Free đã xong; hành vi nâng cấp Family/paywall rõ ràng. Tên: "Ví Nhà Mình" (vi) /
"HomeWallet" (quốc tế). Không phát hành trước khi pilot + Personal Free ổn định.

**P18 — Premium / Expansion — TƯƠNG LAI.** Personal Cloud, Family subscription, bộ danh mục
mẫu, vai trò/nhãn tự do, Family > 2 người, xoay khoá sau thu hồi / forward secrecy, xử lý
xung đột phong phú hơn. Giá đang cân nhắc: Free = ví cá nhân cục bộ; Personal Cloud
19.000đ/tháng · 149.000đ/năm; Family 39.000đ/tháng · 299.000đ/năm. KHÔNG làm billing chỉ vì
có trong lộ trình.

## 9. Mô hình sản phẩm (khoá)
- **FREE PERSONAL:** cục bộ, 1 người, không cần Account; Thu/Chi, Quỹ, Tiết kiệm, danh mục/
  trạng thái/lịch sử; không bắt buộc cloud.
- **PERSONAL CLOUD:** như Free + sao lưu mã hoá, khôi phục, thiết bị tin cậy/cloud.
- **FAMILY:** Wallet dùng chung mã hoá, Owner + Member, đồng bộ hai máy, phân quyền Family.
- Nguyên tắc: đơn giản mặc định, mạnh khi cần.

## 10. An toàn dữ liệu thật — QUY TẮC VĨNH VIỄN
Wallet thật đang được dùng hằng ngày. KHÔNG BAO GIỜ:
- khôi phục về số giao dịch cũ; ghi đè bằng Excel cũ; reset DB thật để test;
- `pm clear` / gỡ app thật để thử nghiệm;
- tạo xung đột cố ý trên dữ liệu thật; thu hồi vợ chỉ để test;
- dùng dữ liệu thật trong DEV/emulator; chép dữ liệu cloud PROD vào fixture DEV;
- thay đổi phá huỷ bất kỳ khi chưa có chấp thuận tường minh.
Mọi test phá huỷ: CHỈ DEV / emulator / fixture.

## 11. Vận hành (công thức đã kiểm chứng)
- adb: `C:\Users\Admin\AppData\Local\Android\Sdk\platform-tools` (không nằm trong PATH);
  Git Bash cần `MSYS_NO_PATHCONV=1` cho đường dẫn `/sdcard`. Pixel = wireless debug
  (`adb-3A131JEHN01127-…`), máy vợ = USB (`MNCUZDGUROZTNFTS`). Không chạm màn hình máy
  người dùng khi họ đang dùng; chỉ đọc (uiautomator dump / logcat) trừ khi được nhờ.
- Firebase CLI: `functions/node_modules/.bin/firebase` (`--project vi-nha-minh-55c60`);
  deploy `--only functions:p7-session,firestore:rules`.
- Backend test: `firebase emulators:exec --only auth,firestore,functions --project
  demo-homewallet-p7 "cd functions && npm test"` — cần Java (JBR của Android Studio) trong PATH.
- Build: `flutter build apk --release --flavor prod --dart-define-from-file=env/prod.json`
  (Flutter ở `C:\tools\flutter`).
- Kiểm tra cloud: Firebase Console / Logs Explorer qua trình duyệt (không trích xuất token
  từ máy host). Log request cho thấy từng callable + mã HTTP.
- Diễn tập di trú DB: bản debug `--dart-define=DB_REHEARSAL=true` (xem `CLAUDE.md` §29).
