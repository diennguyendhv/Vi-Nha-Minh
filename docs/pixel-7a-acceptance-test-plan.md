# Kế hoạch test nghiệm thu trên Pixel 7a

Nguồn: yêu cầu của chủ dự án (2026-09-19). Test **thật trên thiết bị**, không thay bằng widget test. Không thêm feature trong lúc test — chỉ ghi phát hiện.
Trạng thái mỗi mục: `[ ]` chưa test · `[x]` đạt · `[!]` phát hiện lỗi/lệch (ghi mã F-xx ở báo cáo kết quả) · `[~]` đạt một phần · `[-]` chưa thể test (feature chưa có / cần điều kiện khác).

Cách chạy (xem thêm memory `pixel7a-acceptance-test-2026-09-19`): adb không nằm trong PATH — `C:\Users\Admin\AppData\Local\Android\Sdk\platform-tools\adb.exe`; đọc DB bằng `run-as com.vinhamimh.vi_nha_minh cat app_flutter/vi_nha_minh.sqlite` rồi Python sqlite3; chụp màn hình bằng Bash (không dùng PowerShell redirect).

## 1. Cài đặt và khởi động
- [x] Build APK/AAB debug hoặc release thành công. _(debug APK OK; release/AAB chưa build)_
- [x] Cài mới trên Pixel 7a thành công.
- [!] Icon, tên app, splash screen đúng. _(tên đúng theo locale; icon + splash vẫn là logo Flutter mặc định → F7)_
- [!] Mở app lần đầu không crash. _(không crash nhưng có Unhandled Exception google_fonts/Manrope → F8)_
- [x] Tắt app → mở lại bình thường. _(nền→mở lại, vuốt khỏi recents, system kill)_
- [x] Force stop → mở lại bình thường.
- [x] Restart Pixel 7a → dữ liệu vẫn còn. _(reboot qua adb, mở khoá, DB + Home khớp tuyệt đối)_
- [x] App không đòi quyền không cần thiết. _(chỉ quyền thường: INTERNET, NETWORK_STATE, BIOMETRIC/FINGERPRINT (local_auth), LOCAL_NETWORK)_
- [x] Không cần Internet vẫn dùng được toàn bộ chức năng local. _(Wi-Fi + dữ liệu di động tắt, ping unreachable: chuyển tiền/tiết kiệm/quỹ đều chạy)_
- [x] Bật/tắt Wi-Fi, 4G khi đang dùng không gây lỗi. _(bật lại: app không crash, dữ liệu nguyên)_
- [x] Dark/light mode (nếu app hỗ trợ) không vỡ UI. _(app không hỗ trợ dark (không có darkTheme) — luôn sáng, không vỡ)_

## 2. UI thật trên điện thoại
- [x] Không overflow chữ/nút. _(trên các màn đã mở)_
- [x] Bàn phím mở lên không che ô nhập hoặc nút Lưu. _(ô nhập không bị che; nút Lưu ẩn khi đang gõ, hiện lại khi đóng bàn phím)_
- [x] Nhập số tiền bằng bàn phím số thuận tiện.
- [!] Format `1.200.000đ` đúng. _(hiển thị đúng; ô nhập vẫn raw digits → F4)_
- [!] Date picker dễ sử dụng. _(dễ dùng nhưng toàn tiếng Anh → F6)_
- [x] Dropdown/category/status không bị che.
- [x] Bottom sheet thêm giao dịch cuộn được trên màn hình nhỏ. _(phải cuộn 1 lần mới thấy Lưu)_
- [x] Back gesture Android hoạt động đúng. _(vuốt mép: đóng sheet, rồi thoát app)_
- [x] Không mất dữ liệu form khi bàn phím đóng/mở.
- [x] Bấm nhanh nhiều lần không làm UI giật hoặc tạo giao dịch kép. _(một phần: 5 tap song song qua adb)_

## 3. CRUD giao dịch cơ bản
Dữ liệu: Opening Vợ 1.000.000, Chồng 2.000.000 → Thu nhập Chồng +1.000.000, Chi Vợ −200.000 ⇒ **Vợ 800.000 · Chồng 3.000.000 · Total 3.800.000**.
- [x] Tạo Thu · [x] Tạo Chi · [x] Sửa note · [ ] Sửa category · [ ] Sửa ngày · [x] Sửa amount · [ ] Đổi status
- [x] Reverse/xoá giao dịch · [x] Giao dịch đã reverse không còn ảnh hưởng balance · [x] Mở lại app kết quả vẫn đúng

## 4. Chuyển Vợ ↔ Chồng
Chồng → Vợ 500.000 ⇒ Chồng −500.000, Vợ +500.000; Total Assets / Income / Expense **không đổi**. Test cả hai chiều, nhiều lần.
- [x] Chồng → Vợ 500k · [x] Vợ → Chồng 300k · [x] Chuyển nhiều lần liên tiếp (thêm 100k) — Tổng/Thu/Chi không đổi; người gửi = người nhận bị khoá nút Lưu

## 5. Tiết kiệm
Chồng Available → Savings 500.000 (Available −500k, Savings +500k, Total không đổi); Savings → Available 200.000 đảo chiều đúng.
- [~] Nạp tiết kiệm Chồng→Ngân hàng 500k ✓ (Available −500k, Savings +500k, Total không đổi) · [ ] Rút về ví · [ ] Chuyển đổi · [ ] Vợ và Chồng savings riêng · [ ] Nhiều SavingsAssetType · [x] Không rút quá số dư (rút 700k khi có 500k bị chặn, DB không ghi) · [ ] Sửa savings · [ ] Reverse savings — **xem F11: mô hình loại tài sản mặc định cần chỉnh**

## 6. Quỹ
Chồng → Quỹ du lịch 1.000.000; Quỹ du lịch → Vợ 300.000 ⇒ Quỹ 700.000, Total không đổi.
- [x] Nạp quỹ (Chồng→Quỹ tiền ăn 1.000.000, Total không đổi) · [ ] Rút quỹ (`FUND_WITHDRAW`) · [ ] Chọn đúng người nhận · [ ] Rút hết quỹ · [ ] Rút quá balance bị chặn · [ ] Double-tap Rút không tạo 2 transaction

## 7. Dashboard / Summary
Sau mỗi nhóm trên kiểm tra đồng thời: Available Vợ · Available Chồng · Savings Vợ · Savings Chồng · Tổng Savings · từng Fund · Tổng Fund · Total Assets · Income tháng · Expense tháng · Net tháng.
- [ ] Trang chủ và Tổng hợp cho **cùng một sự thật tài chính** (dùng chung `FinancialSummary`).

## 8. Ngày tháng
- [ ] Hôm nay · [ ] Tháng trước · [ ] 31/01→01/02 · [ ] 31/12→01/01 · [ ] Sửa ngày sang tháng khác
- [ ] `transactionDate` quyết định báo cáo tháng, không phải `createdAt` · [ ] Tạo hôm nay nhưng chọn ngày tháng trước → xuất hiện đúng báo cáo tháng trước

## 9. Status (Dâng hiến/Cho đi)
Chưa chuẩn bị → Đã chuẩn bị → Đã gửi/Đã dâng.
- [ ] Expense chỉ tính một lần · [ ] Đổi status không trừ balance lần nữa · [ ] Đổi đi đổi lại không double-count · [ ] Restart app status vẫn đúng

## 10. Correction / Reversal (trọng tâm độ tin cậy)
Nhập nhầm Chi 500.000 → sửa 350.000: kết quả cuối phải là 350.000, không phải 850.000. Sau đó reverse.
- [x] Original vẫn tồn tại trong ledger · [x] Correction đúng (200k→350k, không phải 550k) · [ ] Không double reversal · [ ] Không sửa được transaction stale theo cách phá ledger · [x] Dashboard cuối đúng

## 11. Idempotency / double tap
Bấm Lưu nhanh 2–5 lần: [x] chỉ 1 transaction (5 tap song song) · [x] không double Expense · [ ] không double Income · [ ] không double Fund top-up · [ ] không double Fund withdraw · [ ] retry cùng request vẫn chỉ 1 logical transaction.

## 12. Lỗi số dư
Savings chỉ có 500k, rút 700k:
- [!] Báo lỗi dễ hiểu ("Số dư không đủ để ghi giao dịch này." nhưng nằm sau bottom sheet → F1) · [x] Không lộ `SqliteException` · [x] Không ghi nửa transaction · [x] Balance không đổi · [ ] Sửa xuống 400k rồi Lưu được · [ ] Retry đúng lifecycle đã thiết kế

## 13. Non-income inflow
Mua quạt 2.000.000, bán lại 450.000 (category `excludeFromTotals`):
- [ ] 450k quay lại Available · [ ] Total Assets +450k · [ ] Không thành reportable Income · [ ] Expense gốc không biến mất ngoài ý muốn

## 14. Linked Refund / Asset Recovery
Mua iPad 6.000.000: bán 4.500.000 (lỗ ròng 1,5m) · bán 6.000.000 (hoà vốn) · bán 6.500.000 (lãi 500k, Available nhận đủ 6,5m).
- [ ] Partial refund · [ ] Nhiều recovery · [ ] Correction · [ ] Reversal · [ ] Tìm lại giao dịch gốc sau nhiều tháng

## 15. Receivable / Cho vay
Chị Hằng mượn 1.200.000 (08/05/2026): trả 200k, trả 500k (còn 500k), trả nốt 500k (còn 0). Không lần nào tạo Income/Expense giả.
- [ ] Chuỗi trả nợ đúng · [ ] Tháng 6/2026 cho vay → tháng 7/2027 vẫn tìm được khoản gốc và ghi nhận trả nợ

## 16. Tìm kiếm với dữ liệu lớn (~1.800 transaction)
- [ ] Note · [ ] Người · [ ] Category · [ ] Amount · [ ] Ngày/tháng/năm · [ ] >1 năm trước · [ ] Đã reversed · [ ] Linked · [ ] Cuộn danh sách dài · [ ] Mở transaction detail nhanh

## 17. Dữ liệu thật 2026 (golden)
Sau import: Vợ Available 244.000 · Vợ Savings 4.740.000 · Chồng Available 835.000 · Chồng Savings 70.500.000 (Bank 70.000.000, Other 500.000) · **Total Assets 76.319.000**. Dart test PASS mà Pixel ra số khác → không release cho tới khi biết nguyên nhân.

## 18. Persistence kiểu người dùng thật (nhiều ngày)
- [ ] 20–50 giao dịch · [ ] Restart máy · [ ] Force stop · [ ] Android kill app nền · [ ] Pin yếu · [ ] Mất mạng · [ ] Đổi ngày hệ thống rồi đổi lại · [ ] Update bản mới, dữ liệu cũ còn · [ ] Migration không mất dữ liệu

## 19. Hiệu năng (~1.800 giao dịch)
- [ ] Cold start · [ ] Trang chủ · [ ] Tổng hợp · [ ] Chuyển tab · [ ] Thêm transaction · [ ] Search · [ ] Scroll · [ ] Nhiệt độ · [ ] RAM khi mở/đóng nhiều màn

## 20. Hai vợ chồng dùng thật (sau Firebase/Family Sync)
Chồng thêm giao dịch → Firebase → điện thoại Vợ. Test: conflict, offline→online, hai người nhập đồng thời, retry, sync chậm, cùng sửa một transaction, mất mạng giữa lúc ghi, đăng xuất/đăng nhập lại, không double-count. → `[-]` cho tới khi có Family Sync.

---
# Kết quả các đợt chạy
(Điền bên dưới sau mỗi đợt — mỗi đợt ghi ngày, build, mục đã chạy, phát hiện F-xx.)

## Đợt 0 — 2026-09-19 (trước khi có file này)
Đã chạy: Thu/Chi cơ bản, Cho vay/Đi vay + tách gốc/lãi, sửa/hoàn tác tất toán (chiều Cho vay), tìm kiếm/lọc, kiểm toán DB. Phát hiện: F1 (snackbar lỗi nằm sau bottom sheet), F2 (thiếu preview gốc/lãi ở Trả tiền), F3 (thẻ Đi vay "Đã trả" gộp lãi), F4 (ô tiền chưa có dấu phân cách nghìn), F5 (`corrects_tx_id` trống ở dòng tất toán được sửa). Chi tiết trong memory và hội thoại.

## Đợt 1 — 2026-09-19 (build debug, Pixel 7a Android 17, cài sạch)
Đã chạy: Mục 1 (trừ restart máy, offline, Wi-Fi/4G), Mục 2, một phần Mục 3/10/11.

**Kịch bản Mục 3** — Opening Vợ 1.000.000 + Chồng 2.000.000 → Chi Vợ 200.000 → Thu Chồng +1.000.000 ⇒ Vợ 800.000 · Chồng 3.000.000 · Tổng 3.800.000 ✓ (Home khớp, Số dư ban đầu không tính vào Thu tháng).
**Sửa amount (Mục 10)** 200.000 → 350.000 + ghi chú: bản gốc `reversed_by`, 1 dòng đảo ngược, bản mới `corrects_tx_id` → gốc; UI chỉ hiện 350.000; tổng ngày 3.650.000 ✓.
**Xoá (reverse)** bản 350.000: thêm 1 dòng đảo ngược, Vợ về 1.000.000, Tổng 4.000.000, Chi 0; sau force-stop vẫn đúng ✓. Audit DB: không pool âm, không client_tx_id trùng, liên kết đảo ngược nhất quán.
**Double-tap** Lưu (5 tap song song): 1 giao dịch duy nhất ✓ (một phần — sheet đóng sau tap đầu).

| Mã | Mức | Phát hiện |
|---|---|---|
| F6 | Thấp–TB | Date picker hiển thị tiếng Anh ("Select date", "Sat, Sep 19", Cancel/OK) dù máy + app tiếng Việt — thiếu localization delegate/locale `vi` cho Material date picker. |
| F7 | TB (chặn Play Store) | Icon launcher và splash vẫn là logo Flutter mặc định. |
| F8 | TB | `google_fonts` bị `allowRuntimeFetching=false` nhưng font Manrope không có trong assets (phần `fonts:` trong pubspec đang comment) → Unhandled Exception lúc khởi động, UI rơi về font hệ thống. |
| F9 | Thấp | Sheet Thêm giao dịch chỉ có 5 chip ghi chú soạn sẵn (Chợ, Xăng xe, Cà phê, Hoá đơn, Khác), không có ô ghi chú tự do; màn chi tiết thì có. |
| F10 | Thấp | Thẻ "Còn lại" hiện −200.000 ở tháng đầu (Thu 0, Chi 200.000) dù Tổng tài sản dương — nhãn dễ hiểu nhầm (thực chất là Thu − Chi tháng). |

**Chưa chạy trong đợt này:** restart Pixel, Internet/Wi-Fi/4G (cần tắt mạng — adb qua Wi-Fi sẽ mất kết nối, cần bạn thao tác tay), Mục 4–9, 12–13 và phần còn lại của 3/10/11 (đổi category/ngày/status, double reversal, stale). Mục 14, 17, 20 chưa có feature/dữ liệu.

## Đợt 2 — 2026-09-19 (kết nối USB, được phép tắt mạng/khởi động lại máy)
Đã chạy: Mục 1 phần còn lại (offline, Wi-Fi/4G, restart), Mục 4 đầy đủ, Mục 5 (nạp + guard), Mục 6 (nạp quỹ), Mục 12 (guard số dư).
- **Offline thật** (Wi-Fi + dữ liệu di động tắt): chuyển Chồng→Vợ 500k chạy bình thường, ghi đúng 1 dòng `transfer`.
- **Restart máy**: mở khoá bằng PIN (chủ máy cấp phép cho lần này — không lưu PIN), DB giữ nguyên 12 dòng (8 còn hiệu lực), pool khớp UI.
- **Số liệu cuối đợt:** Vợ 1.100.000 · Chồng khả dụng 1.400.000 · Tiết kiệm Chồng 500.000 · Quỹ tiền ăn 1.000.000 · Tổng 4.000.000 · Thu 1.000.000 · Chi 0 (Total bất biến qua mọi lệnh chuyển).
- Lưu ý phương pháp: ảnh chụp màn hình PIN pad bị Android chặn (đen); cú vuốt xuống dài trên bottom sheet sẽ đóng cả sheet.

| Mã | Mức | Phát hiện |
|---|---|---|
| F11 | **Thiết kế (chủ dự án góp ý)** | Loại tài sản tiết kiệm mặc định "Tiền mặt" + "Ngân hàng" sai về khái niệm: tiền mặt và tiền trong tài khoản ngân hàng cùng là tiền khả dụng (`MEMBER_AVAILABLE`); "gửi ngân hàng" (tiết kiệm/kỳ hạn) mới là một loại tài sản, cùng nhóm với vàng, chứng khoán… Tách cash/bank làm sai luồng "dùng tiền này mua vàng/chứng khoán". Cơ chế `SavingsAssetType` là dữ liệu tự do nên chỉ cần đổi seed (`lib/core/constants/default_savings_asset_types.dart`) + ví dụ trong `financial-core-v2.md` mục 9/12 và `design.html`; engine không đổi. Chờ chủ dự án chốt bộ loại mặc định. |
| F1 (mở rộng) | TB | Snackbar lỗi nằm sau bottom sheet xảy ra cả ở sheet Thêm giao dịch (không chỉ sheet Vay). |
| F12 | Thấp | Gợi ý "Xem theo từng loại tài sản ở Cài đặt › Tiết kiệm" trên thẻ Trang chủ, nhưng thanh điều hướng dưới không có tab Cài đặt (chưa xác minh đường vào qua avatar "GĐ"). |
| F13 | Thấp | Chỉ có 1 quỹ mặc định "Quỹ tiền ăn"; chưa thấy chỗ tạo quỹ mới (kịch bản gốc dùng "Quỹ du lịch") trong sheet Chuyển — cần xác minh ở màn Danh mục/Cài đặt. |

## Đợt 3 — 2026-09-19 (sau khi sửa F11)
**F11 (seed mặc định → Gửi ngân hàng / Vàng / Chứng khoán / Khác):** đã sửa ở code + test + tài liệu. Chi tiết trong báo cáo hội thoại. Máy Pixel vẫn giữ DB cũ (seed cũ "Tiền mặt"/"Ngân hàng") — chưa xác minh seed mới trên máy thật, xem F24.
Đã chạy trên máy (DB cũ): rút Savings 200k về Available (Chồng, loại "Ngân hàng" cũ) ✓; Rút hết quỹ 1.000.000 về Vợ, bấm Lưu 3 lần chỉ ra 1 dòng, quỹ = 0, Tổng tài sản 4.000.000 không đổi ✓; dropdown "Sang loại tài sản" tự loại loại nguồn ✓.
| Mã | Mức | Phát hiện |
|---|---|---|
| F23 | **Cao** | Chạm avatar "GĐ" → màn Cài đặt hiện lỗi đỏ "No Material widget found — _InkResponseStateWidget … SettingsRow". `SettingsScreen` trả về `ListView` không có `Scaffold`/`Material` nhưng được push bằng `MaterialPageRoute` từ `home_screen.dart:133`. Hậu quả: KHÔNG vào được Quỹ/Tiết kiệm/Cài đặt trên máy thật (đồng thời làm F12 và F13 thành không kiểm chứng được). Widget test không bắt được vì test bọc Material sẵn. |
| F24 | TB | Seed chỉ chạy khi file DB được tạo mới (`wasCreated`). Bản cài đè/đang dùng giữ nguyên "Tiền mặt"/"Ngân hàng"; người dùng cũ sẽ không thấy bộ mặc định mới. Không có cơ chế reseed/đổi tên. Chọn: chấp nhận (chỉ DB mới), hoặc thêm bước đổi tên có kiểm soát — cần chủ dự án quyết. |

## Đợt 4 — 2026-09-19 (DB sạch, seed F11, sau khi sửa F23)
**Chuẩn bị:** xoá DB test trên Pixel (được duyệt), backup còn nguyên: `app_flutter/_orig_backup` (hash `b7f1af62…`, 12 giao dịch) và `_pre_delete_backup` (hash `ac178e5e…`, 14 giao dịch); bản sao trên PC trong scratchpad. DB mới: 4 loại tài sản đúng (Gửi ngân hàng/Vàng/Chứng khoán/Khác), 0 giao dịch, 15 category, 6 status, integrity ok — đối chiếu cả SQLite và UI (màn Tiết kiệm + Tổng hợp).
**F23 đã sửa** (`SettingsScreen` thêm `Scaffold`+`AppBar`), regression test `settings_navigation_test.dart` 4 test: FAIL trên code cũ, PASS trên code sửa. Trên máy: Home → avatar → Cài đặt → Tiết kiệm/Quỹ → Back đều chạy.
**Savings (DB sạch):** Available→Gửi ngân hàng ✓ · Available→Vàng ✓ · Gửi ngân hàng→Vàng ✓ (làm lại đúng sau khi lần đầu vô tình chọn Chứng khoán) · Vàng→Available một phần ✓ · rút hết ✓ · rút vượt số dư bị chặn, DB không đổi ✓ · Vợ/Chồng riêng ✓ · sửa 200k→150k (chuỗi đảo ngược + corrects) ✓ · hoàn tác ✓ · kill/relaunch khớp ✓.
**Quỹ:** tạo quỹ mới ✓ (F13 đóng: UI có sẵn) · nạp 1.000.000 ✓ · rút một phần 300k về Vợ ✓ · rút 200k về Chồng bấm 3 lần → 1 dòng ✓ · rút hết 500k ✓ · rút 900k > 700k bị chặn ✓ · Tổng tài sản bất biến ✓.
**Payable:** Đi vay 700k, trả 200k, trả 600k ✓ · sửa lần trả mới nhất 600k→700k ⇒ gốc 700k + lãi 200k ✓ · hoàn tác ⇒ còn 500k, lãi 0 ✓ · kill/relaunch khớp ✓.
**Status:** CĐ Chi 100k, đổi CCB→ĐCB: 0 giao dịch mới, số dư không đổi ✓. Đổi tiếp sang ĐG, sửa ngày/category/note: CHƯA chạy (bị gián đoạn).
| Mã | Mức | Phát hiện |
|---|---|---|
| F23 | Cao | ĐÃ SỬA + test (xem trên) |
| F24 | – | ACCEPTED DECISION: seed mới chỉ áp cho DB tạo mới, không migration |
| F25 | **Cao — REVIEW NEEDED** | Tổng hợp: "Thu nhập của Vợ tháng 9" = 1.000.000 (chính là Số dư ban đầu) trong khi "Tổng thu nhà" trên cùng màn và "Thu tháng 9" ở Trang chủ = 0. Nguyên nhân: `computeMemberIncomeTotal` (compute_member_outflow_breakdown.dart:46) cộng mọi INCOME vào thành viên, không nhận `categories` nên không loại `excludeFromTotals` (Số dư ban đầu) và gốc Đi vay. Sai lệch báo cáo, không ảnh hưởng ledger/số dư. |
| F27 | TB | Sheet Sửa lần trả Đi vay: "Còn phải trả 600.000" (đúng phải 500.000) — dường như cộng lại cả phần lãi của lần đang sửa. Kết quả lưu vẫn đúng. |
| F14 (thêm bằng chứng) | Thấp | Danh sách: mọi thao tác Tiết kiệm đều nhãn "Tiết kiệm"; RÚT quỹ hiện nhãn "Nạp quỹ". |
| F22 (thêm) | Thấp | Cài đặt: công tắc "Khoá vân tay" BẬT sẵn dù chưa có màn khoá nào. |
| F1 (thêm) | TB | Snackbar lỗi vẫn nằm sau sheet ở lần rút Savings vượt số dư (Add Transaction). |
Hạn chế công cụ (không phải lỗi app): `adb input text` không gõ được dấu tiếng Việt nên tên quỹ test là "Quy du lich".

## Đợt 5 — 2026-09-19 (F25: thu nhập theo thành viên)
**F25 đã sửa (domain, additive, không schema/engine):** use case dùng chung `computeReportableIncomeEntries`; `computeThreeTotals` và `computeMemberIncomeTotal` cộng từ cùng nguồn → `Σ thu nhập thành viên == Total Income gia đình`. Test: `compute_member_reportable_income_test.dart` (12) + `summary_member_income_test.dart` (2). Logic cũ chạy trên A/C/E cho 1.000.000 / 700.000 / 6.500.000 (sai).
**Pixel (DB hiện có):** Tổng hợp trước khi nhập thu nhập thật: Thu nhập của Vợ = 0 (Opening 1tr + Đi vay 700k bị loại) = Tổng thu nhà 0. Sau khi thêm income thật Vợ 500k + Chồng 300k: Vợ 500.000, Chồng 300.000, Tổng thu nhà 800.000, Trang chủ "Thu tháng 9" 800.000; Python độc lập trên SQLite: vo=500000 chong=300000 family=800000. Khớp.
Ghi chú: DB trên máy có thêm giao dịch tiết kiệm và 1 đối tác mồ côi do thao tác tay sau đợt 4 (không thuộc lượt test này, không đụng).
F27, F1 vẫn OPEN.

## Đợt 6 — 2026-09-19 (metadata + đối chiếu chéo) — TẠM DỪNG: máy khoá màn hình
Đã làm (không cần thao tác máy): sao lưu DB test hiện tại (scratchpad `r6_backup`), script đối chiếu độc lập `reconcile.py`/`integrity.py`/`cats.py` từ SQLite.
- **DB hiện tại:** integrity ok, 28 giao dịch (20 hiệu lực, 4 cặp đảo ngược), không trùng clientTxId, liên kết đảo ngược hai chiều đúng, không đảo ngược đôi, không pool âm, 1 obligation Payable (Chi Lan) có đúng 1 giao dịch mở, không obligation mồ côi. Đối tác mồ côi "c hằng" (455149) VẪN TỒN TẠI — không xoá.
- **Đối chiếu độc lập (tháng 9):** Available Vợ 2.500.000 / Chồng 400.000; Savings 1.300.000; Quỹ 0; Receivable 0; Payable còn 500.000; Total Assets 4.200.000; Net Worth 3.700.000; Thu Vợ 500.000 + Chồng 300.000 = 800.000; Chi 100.000; Chuyển khoản 4.400.000 — khớp đúng các số UI đã thấy ở Trang chủ + Tổng hợp trước khi máy khoá.
- **Danh mục (SQLite):** 15 category, không trùng id/tên, không mồ côi; Số dư ban đầu và Hoàn tiền/Thu hồi có `excludeFromTotals`; CĐ và DH có `statsEnabled` và 3 status (CCB/ĐCB/ĐG|ĐD). Ghi nhận: "Đi vay" (`vay_no`) `excludeFromTotals=0` vì loại khỏi thu nhập bằng cấu trúc `obligationId` (F25) — màn Danh mục không hiển thị "Không tính vào Tổng thu" cho hạng mục này (F28, copy/UX thấp).
Chưa chạy (cần máy mở khoá): Test A (Thu nhập 111.000 tháng trước), B (sửa ngày sang tháng trước), category/note, status ĐG (CĐ/DH), đối chiếu màn Giao dịch/Danh mục trên UI.

## Đợt 6b — 2026-09-19 (metadata + đối chiếu chéo + recovery + audit yêu cầu mới) — KHÔNG sửa code
**Ngày tháng:** Thu 111.000 chọn 15/08 → `transactionDate`=2026-08-15, `createdAt`=14:17 hôm nay; Available/Total Assets tăng ngay; tháng 9 không tăng; tháng 8 tăng đúng (Giao dịch tab tháng 8 hiện đúng dòng). Sửa ngày khoản Chồng 300.000 từ 19/09 → 20/08: sửa tại chỗ (v1, không reversal/correction — đúng spec mục 21 vì ngày không ảnh hưởng balance), balance/Total Assets không đổi, thu nhập chuyển tháng 9→8 (Chồng 300k: T9 0, T8 300k). Không thấy F19 cản (ngày tương lai bị khoá, ngày quá khứ chọn được).
**Category/note:** Chi 1.000.000 (Sinh hoạt) đổi sang Tự thưởng + note: amount/balance không đổi thêm, Expense chỉ tính 1 lần, note hiện ở danh sách + chi tiết, không sinh dòng mới (sửa tại chỗ).
**Status:** CĐ CCB→ĐCB→ĐG→CCB và DH tạo mới CCB→ĐCB→ĐD: 0 giao dịch mới, `version` giữ 1, chỉ `status_id`+`status_updated_at` đổi; Available/Total Assets/Income/Expense không đổi (chỉ khoản DH mới −50.000).
**Trả lương (Expense ngoài):** 1.000.000: Available −1tr, Total Assets −1tr, Expense +1tr, Income không đổi.
**Recovery (UI thật):** A) mua 6tr, thu hồi 4,5tr: Available +4,5tr, Chi gốc giữ, thu nhập báo cáo +0, chi tiết "Đã thu hồi 4.500.000 · Chi phí ròng 1.500.000", `recovery_of_tx_id` đúng. B) mua 6tr, thu hồi 6,5tr: Available +6,5tr, chi phí ròng 0, lợi nhuận 500.000, thu nhập báo cáo +500.000 (Vợ), Trang chủ/Tổng hợp/Python độc lập cùng ra 1.000.000 (500k thật + 500k lợi nhuận).
**Cross-screen (T9):** Vợ 8.561.000 · Chồng 400.000 · Savings 1.300.000 · Quỹ 0 · Receivable 0 · Payable còn 500.000 · Total Assets 10.261.000 · Net Worth 9.761.000 · Thu 1.000.000 (Vợ 1.000.000, Chồng 0) · Chi 13.150.000 — Trang chủ = Tổng hợp = SQLite. DB: integrity ok, 36 giao dịch/28 hiệu lực, không dup, link đảo ngược đúng, không pool âm. Đối tác mồ côi "c hằng" vẫn còn (không xoá).
**Danh mục (UI):** đủ 15, nhóm Thu/Chi/Chuyển ("HỆ THỐNG, KHÔNG TỰ TẠO/XOÁ ĐƯỢC"), CĐ/DH "3 trạng thái · Thống kê: bật", Số dư ban đầu/Hoàn tiền "Không tính vào Tổng thu".
**Danh sách giao dịch (F14 thêm bằng chứng):** mọi thao tác Savings (nạp/rút/đổi) đều nhãn "Tiết kiệm"; RÚT quỹ nhãn "Nạp quỹ"; Cho vay/Đi vay/Trả nợ dùng tên hạng mục.
| Mã | Mức | Phát hiện mới |
|---|---|---|
| F29 | Thấp | Trả lương giáo viên không có hạng mục riêng; người dùng phải chọn Sinh hoạt/Tự thưởng… (không phải lỗi tài chính; gợi ý tạo hạng mục Chi qua Danh mục). |
| F30 | **TB (suy từ code, chưa chạy trên máy)** | `LocalCategoryRepository._loadAll` nạp MỌI status kể cả `isActive=false`; form Thêm giao dịch/Chi tiết/Danh mục-sửa dùng `category.statuses` không lọc → status đã "xoá mềm" vẫn hiện và chọn được; còn màn Sửa danh mục hiện lại status đã xoá. Phải sửa trước khi làm CRUD status. |

## Đợt 7 — 2026-09-19 (Category tối giản + F30 + ẩn thu nhập ròng + Chi phí kinh doanh + Ghi chú tự do F9)
**Code:** màn Thêm/Sửa danh mục gọn (Tên, Thu/Chi, Tuỳ chọn nâng cao, Lưu; validation "Nhập tên danh mục"); F30 (`Category.activeStatuses`/`statusById`, `reactivateStatus`, form chỉ chọn bước đang dùng, lịch sử vẫn resolve tên, "Sử dụng lại", đổi tên bước); ẨN cấu hình/hiển thị thu nhập ròng (Category edit/list, thẻ Tổng hợp) — cột `linkedExpenseCategoryId` + `computeNetIncome` giữ nguyên, giá trị cũ được bảo toàn khi lưu; seed "Chi phí kinh doanh" (Expense thường, chỉ DB mới); ô Ghi chú tự do trong sheet Thêm giao dịch (phủ Thu/Chi/Chuyển/Tiết kiệm x3/Quỹ x2/Recovery).
**Regression:** full suite 421/421, Golden 11/11 EXACT (76.319.000), analyze 16 issues/0 error.
**Pixel (DB hiện có, không xoá):** màn Thêm danh mục đúng thiết kế, validation hiện; tạo hạng mục Chi (ASCII "Chi phi kinh doanh": stats 0, linked None). Thu 2.000.000 note "HP lop tin hoc"; Chi 700.000 "Tra luong giao vien"; Chi 200.000 "Quang cao". Delta so với trước: Thu +2.000.000, Chi +900.000, Total Assets +1.100.000. Sửa note khoản 200k → "Quang cao tren mang thang 9": sửa tại chỗ (v1, 41 dòng không đổi), số dư/Thu/Chi không đổi. Kill/relaunch: note còn nguyên ở danh sách + chi tiết. Trang chủ = Tổng hợp = SQLite (Total 12.361.000, Thu T9 5.000.000, Chi T9 15.050.000). Integrity ok, không dup, liên kết đảo ngược đúng, không pool âm.
Hạn chế công cụ: bàn phím máy là Telex nên adb không gõ được tiếng Việt có dấu / tổ hợp x,s,f,r,j → dùng note ASCII; tên hạng mục seed tiếng Việt chỉ kiểm bằng test, chưa xem trên máy (DB cũ không có seed mới — chấp nhận như F24).
| Mã | Mức | Ghi nhận |
|---|---|---|
| F31 | Thấp (accepted) | DB đã tồn tại không nhận hạng mục seed "Chi phí kinh doanh" (seed chỉ khi tạo DB mới, không migration) — tạo tay qua UI Thêm danh mục. |
| F9 | ĐÃ SỬA | Ô Ghi chú tự do có ở mọi luồng của sheet Thêm giao dịch; chip chỉ là gợi ý. |
| F30 | ĐÃ SỬA | Status ẩn không chọn được cho giao dịch mới; lịch sử vẫn resolve; có "Sử dụng lại". |

## Đợt 8 — 2026-09-19 (F1 hardening — lỗi trong bottom sheet) — FIXED
**Code (Presentation):** `SheetErrorBanner` trong Thêm giao dịch / Tạo khoản vay / Tất toán khoản vay; SnackBar bị che đã gỡ khỏi 3 sheet. Harden thêm: Settle sheet xoá banner khi đổi số tiền/người trả/ngày; Create Loan xoá banner khi bấm Lưu lại.
**Pixel 7a (DB hiện có, không xoá; baseline 61 giao dịch → 65 sau 4 giao dịch hợp lệ):**
- Thêm giao dịch (Chi 5.000.000 từ Chồng, có 930.000): banner "Số dư không đủ để ghi giao dịch này." trong sheet, sheet mở, không SnackBar, DB không đổi sau 6 lần Lưu (kể cả rapid tap ×5). Xoá 1 chữ số → banner ẩn; Lưu 500.000 + rapid tap ×5 → đúng 1 giao dịch; Chồng 930.000 → 430.000; Tổng tài sản −500.000.
- Ghi chú đổi → banner ẩn; khôi phục đúng form → banner hiện lại (semantics "form intent", có test).
- Tạo khoản vay 5.000.000 từ Chồng: banner "Không đủ số dư để thực hiện." trong sheet, form giữ nguyên, 0 khoản vay/0 giao dịch, chỉ 1 đối tác dù Lưu 6 lần. Sửa 400.000 + rapid tap ×5 → đúng 1 khoản vay + 1 giao dịch mở khoản.
- Tất toán (Trả 500.000 bằng Chồng ~30.000): banner trong sheet, không settlement. Đổi sang Vợ → banner ẩn. Rapid tap ×5 → đúng 1 dòng `tra_no` 500.000; còn phải trả 500.000.
- SQLite cuối: 65 giao dịch, integrity_check ok, foreign_key_check 0, không trùng clientTxId, không reversal lỗi, không obligation thiếu giao dịch mở khoản.
**Regression:** full suite 436/436, Golden 21/21 EXACT, analyze 16 issues/0 error.
| Mã | Trạng thái | Ghi chú |
|---|---|---|
| F1 | **FIXED** | Add + Create Loan + Settle, Pixel PASS. |
| R1 | mở → xem Đợt 9 | Add Transaction dùng keypad tự vẽ, trái quy tắc bàn phím hệ thống. |
| R2 | mở → xem Đợt 9 | Bàn phím hệ thống che banner + Lưu khi ở ô Ghi chú. |
| R3 | mở | Vuốt xuống vẫn đóng Create Loan sheet dù `isDismissible/enableDrag=false` (DraggableScrollableSheet tự đóng ở min extent). |
| R4 | mở | Add/Settle không chặn Back/nút đóng khi đang submit. |
| R5 | mở | Tap thừa sau khi sheet đóng rơi xuống màn hình bên dưới (trúng nút "+" Home). |

## Đợt 9 — 2026-09-19 (R1 + R2: ô số tiền dùng bàn phím hệ thống) — FIXED
**Code (Presentation):** sheet Thêm giao dịch bỏ `_Keypad` tự vẽ; thay bằng `TextField` số lớn (`add_amount_field`, `TextInputType.number`, `AmountInputFormatter`: chỉ chữ số, bỏ số 0 đầu, tối đa 9 chữ số) + dòng xem trước "1.200.000 đ" (`add_amount_preview`; không format trong lúc gõ để tránh nhảy con trỏ). Banner lỗi + nút Lưu chuyển ra footer cố định ngoài vùng cuộn nên luôn nằm trên bàn phím. File mới: `lib/presentation/widgets/amount_input_formatter.dart`.
**Audit ô nhập tiền:** Create Loan / Settle / Sửa giao dịch đã dùng `TextInputType.number` (không formatter — `- , .` lọt vào, `int.tryParse` → 0, chưa sửa vì ngoài scope). Ô tên Quỹ / loại Tiết kiệm / Danh mục không phải ô tiền.
**Pixel 7a:** CASE 1 Thu 1.200.000 (số nguyên đúng, Vợ nhận, Tổng thu tháng 9 +1.2tr); CASE 2 Chi 500.000 note "Tra luong giao vien"; CASE 3 Chi 5.000.000 từ Chồng (30.000) gửi khi bàn phím Ghi chú đang mở → banner "Số dư không đủ…" + Lưu đều nằm trên bàn phím; rapid tap ×5 → 0 ghi; sửa 20.000 → banner ẩn, Lưu khi bàn phím mở → đúng 1 giao dịch. Amount → Note → Amount: bàn phím số/chữ đổi đúng, dữ liệu giữ nguyên, Back đóng bàn phím trước. DB: 65 → 68 (đúng +3), integrity ok, không trùng clientTxId, lần lỗi ghi 0 dòng.
Ghi chú công cụ: bàn phím Telex của máy đổi "x"/"W" thành dấu ("Excel" → "Ẽcl", "Web" → "Ưeb") — không phải lỗi app; app lưu đúng chuỗi phím gửi.
**Regression:** full suite 447/447, Golden 21/21 EXACT, analyze 16 issues/0 error.
| Mã | Trạng thái | Ghi chú |
|---|---|---|
| R1 | **FIXED** | Add Transaction dùng bàn phím số hệ thống, không keypad tự vẽ. |
| R2 | **FIXED** | Bàn phím mở: Lưu + banner luôn nhìn thấy. |
| R6 | mới, thấp | Khi có banner + bàn phím, vùng cuộn hẹp → ô Ghi chú bị cắt một phần. |
| R7 | mới, thấp | Ô tiền Create Loan/Settle/Sửa giao dịch chưa có formatter (cho lọt `- , .`), raw digits không phân cách nghìn. |
| R3 | mở (xác nhận thêm) | Vuốt xuống trong sheet Thêm giao dịch cũng đóng sheet và mất dữ liệu. |

## Đợt 10 — 2026-09-19 (R7: ô số tiền nhất quán — Create Loan / Tất toán / Sửa giao dịch) — FIXED
**Audit:** cả 3 ô đều là số nguyên dương VND (parse `int.tryParse`, `> 0` mới lưu, không âm, không thập phân, không flow nào cần `- . ,`), nên dùng lại `AmountInputFormatter` (chỉ chữ số, bỏ số 0 đầu, tối đa 9 chữ số). Formatter chỉ làm sạch INPUT; quy tắc gốc/lãi vẫn do domain (nhận 1.500.000 trên khoản 1.200.000 vẫn ra gốc 1.200.000 + lãi 300.000).
**Code (Presentation):** `create_loan_sheet.dart`, `settle_loan_sheet.dart`, `transaction_detail_screen.dart` áp formatter; thêm widget dùng chung `lib/presentation/widgets/amount_preview.dart` (dòng "400.000 đ" dùng `Formatters.amount`, chỉ hiện khi > 0). Màn sửa giao dịch: nút Lưu khoá khi số tiền trống/0 (trước đây bấm không phản hồi). Không đổi domain/use case/reversal/correction.
**Pixel 7a:** A) Cho vay Chi Mai: nhập "0400000" + chạm `-` `,` `.` → ô vẫn 400000, xem trước 400.000 đ, Back đóng bàn phím trước; Lưu → +1 khoản vay, +1 giao dịch mở khoản 400.000. B) Nhận 500.000 trên khoản 400.000: breakdown Thu hồi gốc 400.000 + Tiền lãi 100.000; 2 dòng cùng nhóm tất toán. C) Sửa Chi 20.000: rỗng → Lưu xám; "015000" → 15000; Lưu → dòng hoàn tác 20.000 + dòng mới 15.000 (`corrects_tx_id` đúng), hiệu lực vẫn 51. SQLite: 68 → 73 dòng, integrity ok, không trùng clientTxId, không reversal đôi, settlement group đủ anchor. App khớp script đối chiếu độc lập (Vợ 10.390.000, Chồng 15.000, Tổng tài sản 12.105.000, Net worth 11.605.000).
Ghi chú công cụ: 1/5 lần `adb input text "0500000"` mất 1 chữ số (ra 50000); gõ từng phím và lặp lại 3/3 lần đều ra 500000 → lỗi bơm phím, không phải formatter.
**Regression:** full suite 457/457, Golden 21/21 EXACT, analyze 16 issues/0 error.
| Mã | Trạng thái | Ghi chú |
|---|---|---|
| R7 | **FIXED** | 3 ô tiền dùng bàn phím số hệ thống + formatter chung. |
| R8 | mới, TB | Sheet Vay/Tất toán: nút Lưu và banner nằm trong vùng cuộn, khi bàn phím mở nút Lưu bị che (phải đóng bàn phím) — Add Transaction đã có footer cố định (R2), 2 sheet này chưa. |
| R6 | mở, không tệ hơn | R7 không đụng sheet Thêm giao dịch. |

## Đợt 11 — 2026-09-19 (Vòng đời bottom sheet: R3 / R4 / R5 / R8) — FIXED (R4 một phần bằng widget test)
**Root cause:** (R3) `DraggableScrollableSheet.shouldCloseOnMinExtent` mặc định `true` → kéo tới mức tối thiểu sẽ `pop` route, bất chấp `isDismissible/enableDrag=false`; (R5) khi route đang đóng Flutter bọc nó trong `IgnorePointer` và ngay sau đó tap kế tiếp rơi xuống trang dưới (nút "+" của Home nằm đúng dưới nút Lưu).
**Code (Presentation):** cả 3 sheet (Thêm giao dịch / Tạo khoản vay / Tất toán): `isDismissible:false`, `enableDrag:false`, `shouldCloseOnMinExtent:false`, `PopScope(canPop: !_submitting)`, nút X khoá khi đang submit, `closeSheetAfterSave` (bật `TapGuard` 600ms rồi pop đúng 1 lần). Create Loan + Tất toán: banner + nút Lưu chuyển ra footer cố định, `Padding(viewInsets)` như Thêm giao dịch. File mới `lib/presentation/widgets/tap_guard.dart` (+ `TapGuardScope` trong `MaterialApp.router.builder`).
**Pixel 7a (DB không xoá; 73→81 dòng, 1 khoản vay mới):**
- Thêm giao dịch: vuốt xuống khi có dữ liệu → sheet chỉ thu nhỏ, dữ liệu giữ; rapid tap ×5 gửi TRÊN MÁY → đúng 1 giao dịch, sheet đóng, KHÔNG mở sheet mới (R5).
- Create Loan: bàn phím mở → nút Lưu nằm trên bàn phím; lỗi thiếu số dư → banner hiện trên nút Lưu, form giữ nguyên, rapid tap → 0 khoản vay/0 giao dịch; vuốt xuống → chỉ thu nhỏ; Back lúc rảnh đóng, không lưu; Lưu hợp lệ + rapid tap ×5 → đúng 1 khoản vay + 1 giao dịch mở khoản.
- Tất toán (Trả tiền): bàn phím mở → Lưu + banner nằm trên bàn phím; rapid tap khi lỗi → 0 ghi; vuốt xuống → chỉ thu nhỏ; Lưu hợp lệ 100.000 + rapid tap ×5 → đúng 1 dòng `tra_no`, còn phải trả 400.000.
- SQLite cuối: integrity ok, foreign_key ok, không trùng clientTxId, không reversal đôi, đủ anchor nhóm tất toán, mọi khoản vay đều có giao dịch mở khoản; số dư khớp script độc lập (Vợ 10.180.000, Chồng 15.315.000).
**Giới hạn đã biết:** (a) R5 — cửa sổ chặn 600ms giảm chứ không loại bỏ tap-xuyên nếu người dùng bấm cách nhau > 600ms (vòng lặp `adb` từ Windows ~0,3–0,5s/tap vẫn mở sheet mới); (b) R4 chặn Back lúc đang submit chỉ có bằng chứng widget test (ghi DB xong trong vài chục ms, không thể bấm Back đúng lúc trên máy thật); (c) Add + Tất toán không còn đóng khi chạm ra ngoài vùng tối (giống Create Loan trước đó) — quyết định để tránh mất dữ liệu.
**Regression:** full suite 469/469, Golden 21/21 EXACT, analyze 16 issues/0 error; đột biến `shouldCloseOnMinExtent:true` / `arm()` no-op làm test R3/R5 fail như mong đợi.
| Mã | Trạng thái | Ghi chú |
|---|---|---|
| R3 | **FIXED** | 3 sheet không tự đóng khi vuốt; Pixel PASS. |
| R4 | **FIXED (widget test)** | Back/X bị chặn khi submit (test), Pixel chỉ xác nhận idle/lỗi/thành công. |
| R5 | **FIXED (trong cửa sổ 600ms)** | Pixel PASS với chuỗi tap trên máy; xem giới hạn (a). |
| R8 | **FIXED** | Create Loan + Tất toán: Lưu + banner trên bàn phím; Pixel PASS. |
| R6 | mở, không tệ hơn | Note vẫn có thể bị cắt một phần khi có banner + bàn phím. |

## Đợt 12 — 2026-09-19 (Phase 8.8 Product Simplification: 4 nhóm Thu/Chi, schema v7)
**Thiết kế đã duyệt:** `category_rows.group_key` nullable (chỉ `business_expense`; NULL = Chi tiêu). Nhóm Thu dùng `excludeFromTotals` (false = Doanh thu, true = Khoản thu khác). Không đổi `applyEffect`/ledger/Total Assets. Vay, Hoàn tiền/Thu hồi, Cho vay/Đi vay/Trả nợ/Lãi cho vay bị ẩn khỏi UI bằng ID hệ thống (`AdvancedSystemCategories`) + cờ `advancedFeaturesEnabledProvider` (mặc định tắt); engine + lịch sử giữ nguyên.
**Pixel 7a (DB thật 90 giao dịch, không xoá):**
- Migration v6 → v7 khi cài đè APK: `user_version=7`, cột `group_key` mới, 17 danh mục đều NULL, toàn bộ 90 dòng giao dịch giống hệt trước (so sánh từng cột), integrity ok.
- Home không còn thẻ Vay & Cho vay; Danh mục hiện 2 tầng, danh mục nâng cao/Chuyển đã ẩn; 2 danh mục Chi cũ mặc định vào Chi tiêu (đúng thiết kế).
- Đổi "Chi phi kinh doanh" sang nhóm Chi phí kinh doanh: chỉ 1 dòng `group_key` đổi, 90 giao dịch nguyên vẹn; Summary: Chi phí KD 1.761.000 (= tổng SQL), Chi tiêu 22.996.000 → 21.235.000, Thu nhập ròng 21.830.000 → 20.069.000; Doanh thu không đổi.
- Nghiệm thu 4 giao dịch: Doanh thu · Hoc phi 2.000.000; Khoản thu khác · Khac 450.000; Chi tiêu · Sinh hoạt 300.000; Chi phí kinh doanh · Luong nhan vien 700.000. Summary +2.000.000 / +450.000 / +300.000 / +700.000, Thu nhập ròng 20.069.000 → 21.369.000 (+1.300.000), số dư khả dụng +1.450.000 (= dòng tiền ròng). Home "Thu tháng 9" = Doanh thu 23.830.000, "Chi tháng 9" = 21.535.000 + 2.461.000 = 23.996.000. Lịch sử hiện "Chi phí kinh doanh · Luong nhan vien", "Khoản thu khác · Khac"… kèm ghi chú · Vợ/Chồng.
- SQLite cuối: 94 giao dịch (90 + 4), integrity ok, foreign_key ok, không trùng clientTxId, 90 dòng cũ giữ nguyên.
**Thay đổi theo yêu cầu owner giữa chừng:** bỏ chip ghi chú nhanh (Chợ/Xăng xe/Cà phê/Hoá đơn/Khác) và câu ví dụ ở ô Ghi chú; danh sách giao dịch + Home hiện thêm Vợ/Chồng ("Vợ → Chồng" khi chuyển).
**Ghi chú owner:** CĐ và DH dùng 4 trạng thái CCB, ĐCB, ĐD, ĐG (DB Pixel đã đúng 4). Seed cho DB MỚI hiện vẫn 3 trạng thái — chưa đổi, chờ xác nhận.
**Regression:** full suite 514/514, Golden 24/24 (21 lõi EXACT + 3 báo cáo 4 nhóm trên dữ liệu thật), analyze 16 issues/0 error.

## Đợt 13 — 2026-09-19 (Phase 8.8 Summary / Transaction Explorer + Final Hardening) — PASS
**Code:** `explore_transactions.dart` (domain, lọc trong bộ nhớ) + `summary_screen.dart` (3 số tháng này, "Tổng theo trạng thái" thu gọn, Explorer: chip Vợ/Chồng, thời gian, tìm Ghi chú, Bộ lọc Nhóm → Danh mục → Trạng thái). Hardening: (1) tìm Ghi chú không phân biệt dấu tiếng Việt (`lib/core/utils/text_search.dart`: hoa/thường, đ/Đ→d, dấu rời, khoảng trắng; chỉ truy xuất văn bản, không parse Note); (2) header "Vào/Ra" → "Thu/Chi" (phép tính không đổi). Financial Core không đổi; không commit.
**Pixel 7a (DB thật 94 giao dịch, KHÔNG ghi thêm, integrity ok, FK ok, không trùng clientTxId):**
- Số tháng 9 khớp SQLite: Thu nhập ròng Vợ 4.039.000 · Chồng 17.330.000; Chi tiêu gia đình 21.535.000; Tất cả 70 (Thu 53.580.000 · Chi 25.296.000); Vợ 42 (Thu 28.050.000 · Chi 17.081.000) — Chuyển (Tiết kiệm) hiện trong danh sách, không cộng vào Thu/Chi.
- A) Chi tiêu → CĐ: chip trạng thái CCB/ĐCB/ĐG/ĐD (không có "Da chuyen" vì không còn giao dịch). Chọn CCB → 0 giao dịch + trạng thái rỗng (SQL: không dòng CĐ nào dùng CCB; brief ghi 1 là kỳ vọng cũ). Chọn ĐD → 2 giao dịch, Chi 110.000 (100.000 + 10.000 "Tét trang thai") — khớp SQL.
- B) Chi tiêu → DH (chip CCB/ĐCB/ĐD/ĐG đúng seed) → ĐD: 1 giao dịch, Chi 50.000 — khớp SQL. Đổi danh mục CĐ→DH tự reset trạng thái (Bộ lọc 3→2).
- C) Vợ + Chi tiêu + Sinh hoạt + "di": 1 giao dịch "Di sieu thi" 18/09, Chi 300.000 — khớp SQL (Vợ + Sinh hoạt không có "di" = 4 dòng → AND thật sự thu hẹp).
- Tìm không dấu → có dấu: "quang cao" → 3 giao dịch (Thu 100.000 · Chi 861.000): "Quảng cáo trả lại", "Quảng cáo", "Quang cao tren mang thang 9". "luong" → 5 giao dịch, Chi 3.100.000, gồm "Lương c Bích" (trước hardening: 4 / 2.900.000).
- Tìm có dấu → không dấu (gõ Telex "lương" qua bàn phím Laban): 5 giao dịch, Chi 3.100.000, gồm "Luong giao vien", "Tra luong giao vien".
- Giữ bộ lọc: mở chi tiết rồi Back (mũi tên app và nút Back hệ thống) → về đúng Tổng hợp, "quang cao" + kết quả còn nguyên; chuyển tab rồi quay lại → còn nguyên. Xóa bộ lọc → về 70 giao dịch, Thu/Chi như ban đầu. Khoản nhỏ 10.000 / 15.000 nhìn rõ trong danh sách.
**Quan sát nhỏ (không chặn):** sau khi Back từ chi tiết, ô tìm lấy lại focus nên bàn phím tự mở lại (lần chuyển tab thì không). Một lần Back hệ thống thoát ra màn hình chính trong lúc thao tác adb lộn xộn (sau chạm nhầm + gõ chữ + Enter); 2 lần thử sạch sau đó không tái hiện.
**Regression:** full suite 561/561, Golden 24/24, analyze 16 issues/0 error; 31 test domain + 18 test widget cho Explorer (gồm 1.800 dòng).
**Còn mở:** F6 date range picker tiếng Anh (không sửa lượt này); R5 timer hardening, R6 (không đụng).
**Issue UX LOW (mới, không sửa ở checkpoint này):** tìm Ghi chú không dấu + khớp một phần có thể cho kết quả thừa sau khi bỏ dấu — vd "chợ" → "cho" cũng khớp "chồng" → "chong". Không ảnh hưởng dữ liệu hay ngữ nghĩa tài chính; không mở lại scope Summary vì issue này.

## Đợt 14 — 2026-09-20 (Master data cleanup + Trang chủ tối giản) — PASS
**Code:** Category/Status xóa hẳn khi ĐÃ NGỪNG + CHƯA TỪNG có giao dịch (kể cả đã hoàn tác); đã dùng → chỉ ngừng sử dụng. `deleteCategoryPermanently`/`deleteStatusPermanently` kiểm tra lại trong 1 DB transaction (+ FK ON). Màn Danh mục có khu "Ngừng sử dụng (n)" (Sử dụng lại · Xóa hẳn khi an toàn, hoặc "Đã được dùng trong lịch sử nên không thể xóa."). Tạo danh mục trùng tên mục đã ngừng → gợi ý "Sử dụng lại" (cùng id). Nút "Xoá" danh mục đổi thành "Ngừng sử dụng". Trang chủ viết lại: Vợ/Chồng (Thu nhập tháng này · Số dư hiện tại · Tiết kiệm), Chi tiêu gia đình (+ Xem chi tiết → Tổng hợp), Quỹ tiền ăn (id `an_uong`, Còn lại/Đã hết + Nạp quỹ); ẩn Tổng tài sản/Net Worth/Vay/Recovery/Doanh thu/Chi phí KD/Khoản thu khác/Giao dịch gần đây. Financial Core không đổi.
**Pixel 7a (DB thật, cài đè APK, không reset):**
- Trang chủ khớp SQLite từng đồng: Vợ 4.039.000 / 11.830.000 / 0; Chồng 17.330.000 / 15.715.000 / 200.000; Chi tiêu gia đình 21.535.000; Quỹ tiền ăn 500.000.
- "Xem chi tiết" → tab Tổng hợp; chạm thẻ Quỹ → chi tiết quỹ, Back về Trang chủ; "Nạp quỹ" mở đúng 1 sheet (Chuyển › Nạp quỹ › Quỹ tiền ăn), bấm nhanh 5 lần (`adb` vòng lặp trên máy) vẫn đúng 1 sheet, đóng bằng X không lưu.
- Master data: danh mục thử "ZZ Tét A" (chưa dùng) → Ngừng sử dụng → Xóa hẳn → biến mất khỏi UI và DB; giao dịch không đổi. Danh mục thử "ZZ B" + 2 bước; 1 giao dịch 1.000đ dùng "Buoc dung": sau khi ngừng, "Buoc dung" chỉ có Sử dụng lại (+ lời giải thích), "Buoc chua" có thêm Xóa hẳn → xóa thật khỏi DB; ngừng ZZ B → không có Xóa hẳn; lịch sử vẫn đọc "Chi tiêu · ZZ B". Hoàn tác giao dịch thử → số dư trở lại đúng (Vợ 11.830.000, Chồng 15.715.000). Danh mục thật "Chi Phí Vận Hành" (ngừng, 0 giao dịch theo danh mục nhưng 1 giao dịch dùng bước con) đúng là bị chặn xóa.
- SQLite cuối: 96 dòng (94 + 1 giao dịch thử + 1 dòng hoàn tác), integrity ok, foreign_key_check rỗng, không status mồ côi, không trùng clientTxId. Còn lại 1 danh mục thử "ZZ B" (ngừng, đã dùng nên không xóa được theo thiết kế).
**Regression:** full suite 604/604, Golden 24/24, analyze 16 issues/0 error.

## Đợt 15 — 2026-09-20 (Savings 2 tầng Option A2 + Integrity hardening) — PASS
**Code:** tài sản hệ thống ảo `savings_unallocated` ("Chưa phân bổ", không row DB, không schema/PoolKind/applyEffect mới); Savings Total = tổng dẫn xuất pool tiết kiệm của từng người; guard hoàn tác không-âm tổng quát + kiểm tra sau khi sửa số tiền; `validateSavingsMembers` (nạp/rút/phân bổ cùng 1 người) ở tầng ghi; loại tài sản đã ngừng không nhận tiền vào; vòng đời loại tài sản (xoá hẳn khi đã ngừng + chưa từng dùng, đổi tên/dùng lại giữ id); màn Tiết kiệm mới; dòng Tiết kiệm trên Trang chủ chạm được; nhãn Explorer/Giao dịch đời thường.
**Pixel 7a (DB thật, không reset; Vợ Khả dụng 11.830.000 / Tiết kiệm 0; Chồng 15.715.000 / 200.000 ở Gửi ngân hàng):**
- Trang chủ → chạm dòng Tiết kiệm Vợ/Chồng → đúng người; dữ liệu cũ của Chồng vẫn 200.000 ở Gửi ngân hàng, Chưa phân bổ 0.
- Ca 1 (Vợ Thêm vào 1.000.000, không hỏi loại; bấm nhanh 4 lần vẫn +1 dòng): Khả dụng 10.830.000, Savings 1.000.000 (`savings_unallocated|vo`), Total Assets không đổi.
- Ca 2: Vàng đang ngừng nên KHÔNG có trong danh sách đích → "Sử dụng lại" Vàng (cùng id) → phân bổ 600.000: Chưa phân bổ 400.000, Vàng 600.000, tổng 1.000.000 (bấm nhanh 3 lần vẫn +1 dòng).
- Ca 3: Vàng → Gửi ngân hàng 200.000: Vàng 400.000, Gửi NH Vợ 200.000; tổng, Khả dụng không đổi (Gửi NH của Chồng vẫn riêng).
- Ca 4: Rút 300.000 từ Vàng: Vàng 100.000, Khả dụng 11.130.000, Savings 700.000.
- Ca 5: hoàn tác lần nạp 1.000.000 khi tiền đã phân bổ → BỊ CHẶN với thông báo "Không thể hoàn tác vì một phần số tiền này đã được chuyển hoặc sử dụng. Hãy xử lý giao dịch phát sinh sau trước." (0 dòng mới, số dư nguyên, ở lại màn chi tiết); hoàn tác theo thứ tự rút → chuyển đổi → phân bổ → nạp đều được, Vợ về đúng 11.830.000 / 0.
- Ca 6: Chồng không đổi qua mọi thao tác của Vợ (Khả dụng 15.715.000, Savings 200.000); Thu nhập ròng/Chi tiêu gia đình trên Home không đổi (4.039.000 / 17.330.000 / 21.535.000).
- Vòng đời loại tài sản: tạo loại thử → đổi tên (giữ id) → ngừng → xoá hẳn (biến mất khỏi DB); Vàng/Chứng khoán (đã dùng) chỉ có Sử dụng lại + lời giải thích; "Chưa phân bổ" không có Đổi tên/Ngừng.
- Nhãn Giao dịch: "Thêm vào tiết kiệm", "Rút từ tiết kiệm · Vàng", "Tiết kiệm · Vàng → Gửi ngân hàng", "Tiết kiệm · Chưa phân bổ → Vàng"; chỉ 1 tên thành viên.
**Lỗi phát hiện & sửa trong đợt:** danh sách "an toàn xoá hẳn" của loại tài sản không cập nhật ngay khi vừa tạo/ngừng trong cùng phiên (chỉ đúng sau khi khởi động lại; tái hiện trên máy với loại vừa tạo). Sửa: suy ra danh sách trực tiếp từ loại tài sản + sổ giao dịch đang xem (`computeDeletableAssetTypeIds`); xoá thật vẫn kiểm tra lại trong DB. Kiểm lại trên máy: loại vừa tạo + ngừng có "Xóa hẳn" ngay.
**SQLite cuối:** 104 dòng (96 + 4 giao dịch thử + 4 dòng hoàn tác), integrity ok, foreign_key_check rỗng, không trùng clientTxId, liên kết hoàn tác đúng, không pool âm; Vợ 11.830.000 / Tiết kiệm 0; Chồng 15.715.000 / 200.000; Total Assets (tổng pool) 28.695.000 = trước khi thử; loại tài sản về đúng trạng thái ban đầu (Vàng/Chứng khoán/Khác ngừng), không còn loại thử.
**Regression:** full suite 671/671, Golden 24/24 (không sửa), analyze 16 issues/0 error.
