# Đặc tả sản phẩm & Lộ trình phát triển
## Ứng dụng Quản lý Chi tiêu Cá nhân/Gia đình — phát hành trên CH Play (Google Play)

Tài liệu này được viết với hai vai trò: **chuyên gia tài chính cá nhân** (thiết kế mô hình dữ liệu và chỉ số sao cho app thực sự giúp kiểm soát dòng tiền, không chỉ ghi chép) và **chuyên gia lập trình Android/Flutter** (thiết kế kiến trúc, kế hoạch kỹ thuật và phát hành sao cho khả thi, bảo trì được lâu dài).

Nguồn gốc: file Google Sheets "Quản lý tài chính 2026" hiện tại, gồm trang **Ghi chép** (nhật ký giao dịch: STT, Hạng mục, Thành tiền, Chi tiết, Người tiêu, Ngày tháng, Trạng thái) và trang **Tổng hợp**. Quyết định kỹ thuật đã chốt: **Flutter**, **Firebase (đồng bộ realtime)**, mô hình **Freemium**, triển khai theo **MVP gọn nhẹ trước, mở rộng dần**.

---

## Nhận định của chuyên gia tài chính trước khi thiết kế

Sổ hiện tại của bạn ghi rất tốt phần **chi tiêu** (Sinh hoạt, Dâng hiến, Cho đi, Tự thưởng...), nhưng để app thực sự là công cụ *quản lý tài chính* chứ không chỉ sổ chép tay số hoá, cần bổ sung ba điều mà một sổ chi tiêu đơn thuần thường thiếu:

1. **Ghi nhận cả thu nhập** (lương, thu nhập freelance, thu nhập khác...), không chỉ chi tiêu — nếu không có vế thu, app không thể tính được số dư thực tế hay tỷ lệ tiết kiệm, chỉ có thể cộng dồn chi tiêu như sheet hiện tại đang làm.
2. **Tỷ lệ theo thu nhập, không chỉ số tuyệt đối** — ví dụ tỷ lệ Dâng hiến/Cho đi trên tổng thu, tỷ lệ tiết kiệm (Thu − Chi)/Thu mỗi tháng. Đây là chỉ số có ý nghĩa hành vi hơn nhiều so với việc chỉ nhìn tổng số tiền đã tiêu.
3. **Ngân sách theo hạng mục** (bạn định chi bao nhiêu cho Sinh hoạt/tháng) đối chiếu với thực chi, để phát hiện lệch sớm thay vì cuối tháng mới biết đã vượt.

Ba điểm này được đưa vào làm một phần bắt buộc trong thiết kế mô hình dữ liệu ngay từ Phase 1, để không phải làm lại (migration dữ liệu) khi thêm sau này.

---

## Kiến trúc kỹ thuật tổng thể

**Frontend:** Flutter/Dart, Riverpod cho state management, `go_router` cho điều hướng, kiến trúc 3 lớp `presentation / domain / data` (chi tiết xem `CLAUDE.md`).

**Backend:** Firebase Authentication, Cloud Firestore, Cloud Functions, Cloud Messaging, Firebase Storage.

**Mô hình dữ liệu Firestore (đối chiếu trực tiếp với sheet "Quản lý tài chính 2026" thật — trang Ghi chép + Tổng hợp):**

Danh sách hạng mục (`categories`) lấy đúng theo dropdown thật trong sheet, **không phải** danh sách Ăn uống/Di chuyển đã đoán ở bản nháp đầu tiên:

| id | Tên hiển thị | Loại (`kind`) | Có theo dõi trạng thái? |
|---|---|---|---|
| `thu_nhap` | Thu nhập | income | không |
| `sinh_hoat` | Sinh hoạt | expense | không |
| `dau_tu` | Đầu tư | expense | không |
| `tu_thuong` | Tự thưởng | expense | không |
| `cho_di` | Cho đi | expense | **có** |
| `tiet_kiem` | Tiết kiệm | savings | không (nhưng số tiền có thể âm = rút ra) |
| `dang_hien` | Dâng hiến | expense | **có** |
| `chong_dua_vo` | Chồng đưa vợ | transfer | không |
| `vo_dua_chong` | Vợ đưa chồng | transfer | không |

`kind` quyết định cách một giao dịch ảnh hưởng đến số dư: `income` cộng vào số dư người ghi; `expense`/`savings` trừ khỏi số dư người ghi (riêng `savings` còn cộng/trừ vào quỹ tiết kiệm riêng của người đó — số âm nghĩa là rút tiết kiệm); `transfer` trừ số dư người chuyển và cộng số dư người nhận (`chong_dua_vo`: Chồng −, Vợ +; `vo_dua_chong`: Vợ −, Chồng +).

Với `cho_di` và `dang_hien`, mỗi giao dịch còn có trường `status` theo đúng quy trình thật trong sheet: `chua_chuan_bi` → `da_chuan_bi` → `da_xong` (hiển thị là "Đã gửi" cho Cho đi, "Đã dâng" cho Dâng hiến). Màn hình Tổng hợp phải tổng hợp được số tiền theo từng trạng thái cho 2 hạng mục này (đúng như khối "Kế hoạch / Chưa chuẩn bị / Đã chuẩn bị / Đã dâng / Đã gửi" trong sheet Tổng hợp thật).

**Tài khoản theo từng thành viên (riêng biệt, không gộp chung)** — đây là điểm khác biệt lớn nhất so với mô hình "một quỹ chung" ban đầu: sheet thật tính **Số dư** và **Tiết kiệm** riêng cho Vợ và cho Chồng (cột `K`/`N` "Tổng hợp"), dựa vào cột "Người tiêu" của từng giao dịch. App giữ đúng cơ chế này cho MỌI thành viên, không riêng Vợ/Chồng.

**Tiết kiệm chia 2 loại con (yêu cầu mới, sheet hiện chưa có — cần bổ sung khi lên app):** mỗi tài khoản tiết kiệm tách thành **tiết kiệm hiện tại** (tiền mặt/chưa gửi) và **tiết kiệm đã gửi ngân hàng**, để biết chính xác bao nhiêu đang nằm ở đâu.

**Cá nhân hay Gia đình — không phải hai schema khác nhau, mà là cùng một mô hình.** "Cá nhân" thực chất là một `families/{familyId}` chỉ có 1 thành viên (`accountType: "personal"`); mời thêm người vào là chuyển tự nhiên sang gia đình, không cần màn hình "nâng cấp" riêng. **Vai trò (`roleLabel`) là chuỗi tự do do chính gia đình đặt** (Vợ/Chồng/Bố/Mẹ/Con/bất kỳ) — đúng nguyên tắc "dữ liệu, không hardcode" đã áp dụng cho hạng mục và trạng thái (xem `CLAUDE.md` mục 9); code Flutter hiện tại (Phase 1, dựng cho vợ chồng chủ dự án) đang dùng enum cứng `FamilyMember{vo, chong}` — việc thay bằng model vai trò tự do là một đợt refactor riêng, đã đưa vào Giai đoạn B bên dưới (làm cùng lúc với phần mời/tham gia thật), **chưa làm ngay** để tránh phá vỡ bản demo hiện tại.

**Mời qua mã hoặc đường link:** mỗi lời mời có mã ngẫu nhiên 6-8 ký tự (đủ khó đoán để không ai lẻn vào gia đình người khác), **có hạn dùng** (mặc định 7 ngày) và giới hạn số lần dùng. Link mời dùng **Android App Links** — không dùng Firebase Dynamic Links vì Google đã thông báo ngừng dịch vụ này, thiết kế đúng từ đầu để khỏi phải làm lại.

**Local-first: mặc định lưu trên máy, chỉ lên Firestore khi thật sự có người thứ 2 tham gia.** Firestore chỉ thật sự cần thiết để đồng bộ realtime giữa nhiều thiết bị — nếu chỉ 1 người dùng (kể cả đã chọn "Gia đình" lúc onboarding nhưng chưa mời ai), không có lý do gì phải trả phí/độ trễ mạng cho việc đó. Vì vậy:

- Mọi tài khoản mới **luôn bắt đầu ở `syncMode: "local"`** — dữ liệu lưu bằng database cục bộ trên máy (SQLite/Hive qua `drift`/`hive`), không cần đăng nhập, không cần mạng, không đụng tới Firebase.
- `families/{familyId}` trên Firestore **chỉ thật sự được tạo tại thời điểm lời mời đầu tiên được người khác chấp nhận.** Trước đó, "gia đình" chỉ tồn tại cục bộ trên máy người tạo.
- Khi người thứ 2 chấp nhận lời mời: toàn bộ dữ liệu local (giao dịch, Quỹ) được **migrate lên Firestore** đúng schema bên dưới, `syncMode` đổi thành `"cloud"`, và từ đó app dùng `FirestoreTransactionRepository` thay vì repository local — cả 2 máy đọc chung 1 nguồn.
- `TransactionRepository`/`FundRepository` là interface trừu tượng (đã thiết kế theo Clean Architecture ngay từ đầu) nên việc có 2 cách triển khai song song (local/cloud) không phá vỡ `domain/` hay `presentation/` — chỉ đổi implementation nào được inject lúc runtime dựa vào `syncMode`.

```
families/{familyId}
  name, accountType ("personal" | "family"), syncMode ("local" | "cloud"),
  ownerUid, createdAt, memberIds: [uid1, uid2, ...]

families/{familyId}/members/{uid}
  displayName, roleLabel (chuỗi tự do, gia đình tự đặt), joinedAt, isOwner

families/{familyId}/invites/{inviteId}
  code (6-8 ký tự ngẫu nhiên), suggestedRoleLabel,
  createdBy, createdAt, expiresAt, maxUses, usedCount

families/{familyId}/categories/{categoryId}
  name, color, kind ("income" | "expense" | "savings" | "transfer"),
  hasStatus (bool), isDefault

families/{familyId}/transactions/{txId}
  categoryId, amount, note, spenderUid, date,
  status ("chua_chuan_bi" | "da_chuan_bi" | "da_xong" | null),
  createdBy, createdAt

families/{familyId}/memberBalances/{uid}
  balance,               // Số dư hiện tại của người này
  savingsOnHand,         // Tiết kiệm hiện tại (chưa gửi ngân hàng)
  savingsInBank          // Tiết kiệm đã gửi ngân hàng

families/{familyId}/budgets/{yearMonth}
  categoryLimits: { categoryId: amount }
```

`memberBalances` là số liệu dẫn xuất (derived) — tính lại từ toàn bộ `transactions` của người đó; có thể cache bằng Cloud Function cập nhật mỗi khi có giao dịch mới để tránh phải cộng dồn hàng nghìn dòng ở client mỗi lần mở app (tham khảo số dòng thật trong sheet: hơn 1700 dòng chỉ riêng 8 tháng đầu năm).

**Chia dữ liệu theo tháng + bảng tổng hợp tính sẵn — quyết định kiến trúc quan trọng cho việc mở rộng nhiều người dùng, nhiều năm:**

Một collection `transactions` phẳng, cộng dồn mãi mãi, có hai vấn đề khi scale: (1) mỗi lần mở app phải nghe realtime toàn bộ lịch sử để tính lại số dư/báo cáo — càng dùng lâu càng chậm và càng tốn phí đọc; (2) không có ranh giới tự nhiên để phân trang theo tháng/năm như cách người dùng thực sự xem dữ liệu (sheet thật cũng tự chia theo "Tháng 1"…"Tháng 9"). Giải pháp:

```
families/{familyId}/months/{yearMonth}              // yearMonth dạng "2026-09"
  totalIncome, totalExpense,
  categoryTotals: { categoryId: amount },
  memberTotals: { uid: { income, expense, savingsOnHand, savingsInBank } },
  statusTotals: { cho_di: { chuaChuanBi, daChuanBi, daXong }, dang_hien: {...} }

families/{familyId}/months/{yearMonth}/transactions/{txId}
  categoryId, amount, note, spenderUid, date, status, savingsDestination,
  createdBy, createdAt
```

- **Realtime listener chỉ mở cho tháng đang xem** (`months/{currentYearMonth}/transactions`) — dữ liệu luôn nhỏ và nhanh dù sổ đã dùng 5 năm, vì tháng cũ không còn bị "nghe" nữa.
- **`months/{yearMonth}` là document tổng hợp tính sẵn** (giống hệt các con số trong sheet Tổng hợp — Thu nhập, Sinh hoạt, Đầu tư... theo %, và khối Chưa chuẩn bị/Đã chuẩn bị/Đã dâng/Đã gửi), cập nhật bằng Cloud Function `onWrite` trên `transactions` dùng `FieldValue.increment()`. Mở màn hình Tổng hợp chỉ cần đọc **1 document** thay vì cộng hàng trăm/nghìn giao dịch ở client.
- **Xem theo năm** = cộng 12 document `months/{yearMonth}` (12 lần đọc, rẻ) thay vì đọc lại toàn bộ giao dịch trong năm.
- `memberBalances/{uid}` (số dư/tiết kiệm trọn đời) cũng được Cloud Function này cập nhật cùng lúc, cùng cơ chế increment.
- Cấu trúc này scale tốt cho nhiều gia đình cùng lúc vì `familyId` đã là ranh giới tenant tự nhiên — chi phí/tốc độ của gia đình A không phụ thuộc gia đình B dùng bao lâu hay bao nhiêu dữ liệu.

**Quỹ tiền ăn riêng (Quỹ) — góc nhìn tài chính cá nhân: kỹ thuật "phong bì ngân sách" (envelope budgeting).** Thay vì chỉ ghi từng khoản Sinh hoạt rời rạc, quỹ cho phép **nạp một khoản cố định** rồi tiêu dần trong khoản đó, biết ngay còn lại bao nhiêu — đúng tâm lý "tiêu trong giới hạn đã định" thay vì tiêu xong mới biết đã vượt. Thiết kế tổng quát (`Quỹ`) để sau này mở rộng thêm quỹ khác (quỹ du lịch, quỹ hiếu hỉ...) mà không đổi kiến trúc:

```
families/{familyId}/funds/{fundId}
  name ("Quỹ tiền ăn"), color, createdAt

families/{familyId}/funds/{fundId}/entries/{entryId}
  kind ("topUp" | "purchase"),   // nạp tiền vào quỹ | mua gì đó từ quỹ
  amount, note ("đi chợ", "thịt bò"...), date, createdBy
```

Số dư quỹ = tổng `topUp` − tổng `purchase` (derived, có thể cache vào field `balance` trên chính document `funds/{fundId}` bằng Cloud Function như trên). Một khoản `purchase` từ quỹ tiền ăn **không** đồng thời tạo thêm một dòng `Sinh hoạt` ở sổ chính — quỹ là sổ con độc lập để theo dõi chi tiêu ăn uống chi tiết, tránh đếm trùng khi tính tổng chi hộ gia đình.

**Quy tắc bảo mật Firestore (rút gọn):**

```
match /families/{familyId}/{document=**} {
  allow read, write: if request.auth.uid in get(/databases/$(database)/documents/families/$(familyId)).data.memberIds;
}
```

---

## Lộ trình chi tiết theo mô hình thác nước

Mỗi phase dưới đây là **một đơn vị việc làm trọn vẹn theo đúng quy trình thác nước**: viết code xong → chạy thử thật (trên máy/thiết bị/emulator) → kiểm thử đạt tiêu chí → mới chuyển sang phase kế tiếp. Không phase nào bắt đầu khi phase trước chưa qua được bước Test. Phase đã có dấu ✅ là đã hoàn thành trong phiên làm việc dựng nền tảng ban đầu.

### Giai đoạn A — Nền tảng & lưu trữ local-first (15 phase, đánh số 1-15)

Toàn bộ tính năng ghi chép cá nhân (giao dịch + Quỹ tiền ăn) chạy đầy đủ ở giai đoạn này **mà chưa cần đụng tới Firebase** — chỉ khi thật sự có người thứ 2 tham gia (Giai đoạn B) mới cần lên mạng.

1. ✅ **Khởi tạo Flutter project + kiến trúc 3 lớp** — Code: `flutter create`, dựng `presentation/domain/data/core`. Chạy: `flutter run` trên điện thoại thật. Test: app mở được, không crash.
2. ✅ **Cấu hình lint chuẩn** — Code: bật `flutter_lints` trong `analysis_options.yaml`. Chạy: `dart analyze`. Test: 0 lỗi/cảnh báo.
3. **CI cơ bản trên GitHub Actions** — Code: workflow chạy `flutter analyze` + `flutter test` mỗi lần push. Chạy: push thử 1 commit. Test: Action chạy xanh.
4. ✅ **Đẩy code lên GitHub** — Code: `git init`, `git remote add`, push. Chạy: mở repo trên github.com. Test: đủ file, không lộ secret/API key.
5. ✅ **Domain entities & mock repository** — đã code/chạy/test qua `MockTransactionRepository` để dựng UI trước; sẽ thay bằng repository local ở phase kế mà không đổi domain.
6. **`LocalTransactionRepository` (lưu cục bộ trên máy)** — Code: implement `TransactionRepository` bằng SQLite/Hive, không phụ thuộc Firebase. Chạy: `flutter run` khi chưa cấu hình Firebase gì cả, thêm thử giao dịch. Test: lưu/đọc đúng, dữ liệu còn nguyên sau khi đóng/mở lại app.
7. **App dùng Local ngay từ lần mở đầu tiên, không bắt đăng nhập** — Code: bỏ yêu cầu đăng nhập ở luồng khởi động mặc định. Chạy: cài app mới hoàn toàn, dùng thử. Test: ghi chép đầy đủ tính năng mà không cần tài khoản Google, không cần mạng.
8. **Nối sheet Thêm giao dịch ghi vào Local** — Code: gọi `LocalTransactionRepository` thay mock. Chạy: thêm 1 giao dịch thật. Test: xuất hiện đúng trong danh sách, còn nguyên sau khi khởi động lại app.
9. **Danh sách giao dịch theo ngày + chuyển xem tháng khác (đọc từ Local)** — Code: query local DB theo tháng. Chạy: thêm giao dịch nhiều tháng, chuyển qua lại. Test: nhóm đúng theo ngày, đúng tháng đang xem.
10. **Sửa/Xoá giao dịch** — Code: `EditTransaction`/`DeleteTransaction` use case. Chạy: sửa và xoá thử. Test: local DB cập nhật đúng, UI phản ánh ngay.
11. **Validate input khi ghi thật** — Code: số tiền > 0, bắt buộc chọn hạng mục + người ghi. Chạy: thử bấm Lưu khi thiếu dữ liệu. Test: nút Lưu khoá đúng.
12. **`syncMode: "local" | "cloud"`, mặc định `"local"`** — Code: field lưu cục bộ (SharedPreferences hoặc trong chính local DB). Chạy: kiểm tra giá trị khi tạo mới. Test: mọi tài khoản mới đều `"local"`, chưa đụng gì tới Firestore.
13. **`LocalFundRepository` (Quỹ tiền ăn)** — Code: implement `FundRepository` bằng local storage. Chạy: nạp/mua thử quỹ. Test: số dư đúng, hoạt động hoàn toàn offline.
14. **Màn hình Quỹ tiền ăn hoạt động trên Local** — Code: nối UI đã có với `LocalFundRepository`. Chạy: dùng thử nạp + ghi mua trên máy thật. Test: số dư quỹ đúng như unit test `computeFundBalance` đã có.
15. **Mốc kiểm tra: dùng đầy đủ ghi chép + Quỹ liên tục nhiều ngày, hoàn toàn không cần Firebase** — Chạy: dùng thử thật vài ngày. Test: không phát sinh lỗi nào đòi hỏi mạng/Firebase cho việc ghi chép cá nhân.

### Giai đoạn B — Firebase & đồng bộ khi có người thứ 2 tham gia (17 phase, đánh số 16-32)

Chỉ bắt đầu giai đoạn này khi thật sự cần chia sẻ sổ với người khác — không có Firebase project nào được tạo trước đó.

16. **Tạo Firebase project thật** — Firebase Console, đặt tên, chọn khu vực gần VN. Chạy: mở lại project trên console. Test: project tồn tại, đúng cấu hình.
17. **Đăng ký app Android vào Firebase, tải `google-services.json`** — Code: đặt file vào `android/app/`, khai đúng `applicationId`. Chạy: `flutter build apk --debug`. Test: build qua, không lỗi thiếu config.
18. **`flutterfire configure` + `Firebase.initializeApp()` (chỉ init khi thật sự cần)** — Code: sinh `firebase_options.dart`, chỉ gọi init khi người dùng bấm "Mời người khác" lần đầu, không init ngay lúc mở app ở chế độ local. Chạy: bấm nút Mời. Test: Firebase khởi tạo đúng lúc cần, không tải SDK không cần thiết khi đang dùng local.
19. **Bật Cloud Firestore (Native mode)** — thao tác Console. Chạy: mở tab Firestore. Test: database trống đã tồn tại, đúng khu vực.
20. **Bật Firebase Authentication (Google Sign-In), kích hoạt khi cần mời** — Code: cấu hình OAuth client ID Android (SHA-1); màn hình đăng nhập chỉ hiện khi bấm "Mời người khác". Chạy: bấm Mời lần đầu trên máy thật. Test: được yêu cầu đăng nhập đúng lúc, `FirebaseAuth.instance.currentUser` đúng sau đó.
21. **Refactor `FamilyMember` → model vai trò tự do** — Code: thay enum cứng `{vo, chong}` bằng danh sách thành viên (`uid`, `roleLabel` tự do), cập nhật `compute_member_financials`/`transferFrom-To`. Chạy: `flutter test`. Test: toàn bộ test cũ pass lại với model tổng quát.
22. **Viết Security Rules bản đầu** (`families/{familyId}` chỉ `memberIds` đọc/ghi) — Code: `firestore.rules`. Chạy: `firebase deploy --only firestore:rules`. Test: deploy không lỗi cú pháp.
23. **Test rule bằng Firebase Emulator Suite** — Code: test rule (`@firebase/rules-unit-testing`). Chạy: `firebase emulators:exec`. Test: tài khoản ngoài family bị chặn đọc/ghi — rủi ro nghiêm trọng nhất của app, không được bỏ qua.
24. **Sinh mã mời có hạn dùng** — Code: `GenerateInvite` use case (mã ngẫu nhiên 6-8 ký tự, `expiresAt`, `maxUses`). Chạy: tạo thử 1 mã. Test: document `invites/{id}` đúng, mã không đoán được theo mẫu tuần tự.
25. **Màn hình chia sẻ mã/link mời (Android App Links)** — Code: UI hiển thị mã + nút chia sẻ link (không dùng Firebase Dynamic Links vì đã bị ngừng hỗ trợ). Chạy: chia sẻ thử qua tin nhắn. Test: bấm link trên máy khác mở đúng màn hình tham gia.
26. **Luồng tham gia qua mã/link** — Code: `JoinFamily` use case validate mã (chưa hết hạn, chưa hết lượt). Chạy: dùng tài khoản thứ 2 nhập mã. Test: mã hợp lệ được chấp nhận; mã hết hạn/hết lượt bị từ chối đúng.
27. **Migrate dữ liệu local → Firestore khi người thứ 2 thật sự tham gia** — Code: khi lời mời được chấp nhận, đọc toàn bộ giao dịch + Quỹ đang lưu local của người tạo, ghi đúng schema `families/{id}/months/{yearMonth}/transactions` (và `funds/`) lên Firestore, đổi `syncMode` sang `"cloud"`. Chạy: tạo ~20 giao dịch local mẫu, mời + chấp nhận từ máy thứ 2. Test: toàn bộ dữ liệu local xuất hiện đúng trên Firestore, không trùng không mất; sau đó cả 2 máy đọc cùng dữ liệu.
28. **`FirestoreTransactionRepository`/`FirestoreFundRepository` + chọn implementation theo `syncMode`** — Code: provider chọn Local hay Firestore lúc runtime dựa vào `syncMode` của gia đình hiện tại. Chạy: dùng thử app ở cả gia đình còn local và gia đình đã chuyển cloud. Test: đúng repository được dùng cho từng trường hợp, không lẫn lộn.
29. **Test rule cho `months/transactions`** — Code: rule con cho subcollection. Chạy: `firebase emulators:exec`. Test: user ngoài family bị chặn ghi vào bất kỳ tháng nào.
30. **Test offline ở chế độ cloud (Firestore local cache)** — Chạy: bật Airplane mode, thêm giao dịch, tắt Airplane mode. Test: giao dịch tự đồng bộ khi có mạng lại, không mất, không trùng.
31. **Test đồng bộ realtime 2 máy** — Chạy: máy A thêm giao dịch. Test: máy B thấy ngay không cần refresh.
32. **Màn hình quản lý thành viên** (đổi `roleLabel`, xem danh sách, rời/xoá thành viên) — Code: `presentation/features/members/`. Chạy: đổi thử vai trò 1 thành viên. Test: `roleLabel` cập nhật đúng, hiển thị đúng ở toàn bộ app.

### Giai đoạn C — Tài khoản riêng từng thành viên & Quỹ tiền ăn (9 phase, đánh số 33-41)

33. **Cloud Function cập nhật `memberBalances`** — Code: trigger `onWrite` trên `transactions`, dùng `FieldValue.increment()`. Chạy: `firebase deploy --only functions`, thêm giao dịch thử. Test: `memberBalances/{uid}` đúng sau nhiều loại giao dịch (thu/chi/tiết kiệm/chuyển khoản).
34. **Nối 2 thẻ Vợ/Chồng đọc `memberBalances` thật** — Code: đổi nguồn dữ liệu Trang chủ. Chạy: `flutter run`. Test: số hiển thị khớp Cloud Function tính.
35. **Unit test Cloud Function xử lý chuyển khoản 2 chiều** — Code: test bằng `firebase-functions-test`. Chạy: `npm test`. Test: cả Chồng đưa vợ và Vợ đưa chồng đổi đúng dấu ở cả 2 phía.
36. **Nối tách tiết kiệm hiện tại/ngân hàng với dữ liệu thật** — Code: đã có UI, đổi nguồn `savingsOnHand`/`savingsInBank`. Chạy: thêm giao dịch Tiết kiệm chọn "Đã gửi ngân hàng". Test: đúng cột tăng, cột còn lại không đổi.
37. **`FirestoreFundRepository`** — Code: implement, ghi vào `families/{id}/funds/{fundId}/entries`. Chạy: gọi thử `addEntry()`. Test: document đúng path.
38. **Màn hình Quỹ tiền ăn** — Code: `presentation/features/fund/`, hiển thị số dư + danh sách khoản. Chạy: mở màn hình trên máy thật. Test: số dư = tổng nạp − tổng mua, khớp `computeFundBalance` đã unit test.
39. **Form nạp tiền vào quỹ** — Code: UI + `addEntry(kind: topUp)`. Chạy: nạp thử 500.000đ. Test: số dư quỹ tăng đúng, entry hiện trong danh sách.
40. **Form ghi khoản đã mua từ quỹ** — Code: UI + `addEntry(kind: purchase)`. Chạy: ghi thử "đi chợ 150.000đ". Test: số dư giảm đúng; xác nhận **không** tạo thêm dòng Sinh hoạt ở sổ chính (tránh đếm trùng).
41. **Cloud Function cache `balance` lên `funds/{fundId}`** — Code: `onWrite` entries → increment. Chạy: deploy + test qua vài entry. Test: field `balance` khớp tổng tính tay.

### Giai đoạn D — Trạng thái & Tổng hợp tháng (8 phase, đánh số 42-49)

42. **Nối chọn trạng thái ghi thật** — Code: đã có UI generic theo `category.statuses`, đổi sang Firestore thật. Chạy: thêm giao dịch Cho đi chọn "Đã chuẩn bị". Test: field `status` đúng trong document.
43. **Cloud Function tính rollup `months/{yearMonth}`** — Code: `onWrite` transactions → increment `categoryTotals`/`memberTotals`/`statusTotals`. Chạy: deploy, thêm giao dịch đa dạng hạng mục/trạng thái. Test: rollup doc khớp phép tính tay.
44. **Nối màn hình Tổng hợp đọc rollup doc** — Code: đổi provider từ stream toàn bộ transactions sang đọc 1 document. Chạy: mở màn hình Tổng hợp. Test: số liệu khớp trước/sau khi đổi nguồn — đây là điểm mấu chốt giúp app nhanh dù dùng nhiều năm.
45. **Biểu đồ tròn theo hạng mục với dữ liệu thật** — Code: đổi nguồn data cho `fl_chart` đã dựng. Chạy: xem với >5 hạng mục có giao dịch. Test: % cộng lại đúng 100%.
46. **Card trạng thái tự sinh theo `category.statuses` với dữ liệu thật** — Code: đổi nguồn data, UI generic đã có sẵn không cần sửa. Chạy: xem Cho đi + Dâng hiến có dữ liệu thật. Test: tổng từng bước khớp rollup doc.
47. **Tỷ lệ tiết kiệm (Thu−Chi)/Thu ở Trang chủ với dữ liệu thật** — Code: đổi nguồn từ rollup. Chạy: xem sau vài giao dịch. Test: khớp domain logic đã unit test từ trước.
48. **Xem Tổng hợp theo năm** — Code: use case cộng 12 document `months/{yearMonth}`. Chạy: xem 1 năm có dữ liệu. Test: tổng năm = tổng 12 tháng cộng tay.
49. **Test hiệu năng đọc Firestore** — Chạy: đo số lượt đọc bằng Firebase Performance Monitoring khi mở Tổng hợp. Test: số lượt đọc không tăng theo số năm đã dùng (chỉ đọc rollup + tháng hiện tại, không quét lịch sử).

### Giai đoạn E — Ngân sách & nhắc nhở (5 phase, đánh số 50-54)

50. **Domain entity `Budget` + `budgets/{yearMonth}`** — Code: entity + repository interface thuần domain. Chạy: unit test logic. Test: test pass, không phụ thuộc Firebase.
51. **Màn hình đặt ngân sách theo hạng mục** — Code: `presentation/features/budget/`. Chạy: đặt thử ngân sách Sinh hoạt = 3.000.000đ. Test: lưu đúng vào Firestore.
52. **Cảnh báo 80%/100% ngân sách** — Code: so `categoryTotals` (rollup) với `budgets`. Chạy: chi vượt 80% thử. Test: cảnh báo hiện đúng ngưỡng.
53. **Cảnh báo theo tốc độ tiêu** (gợi ý chuyên gia — so % ngày đã qua trong tháng với % ngân sách đã dùng, cảnh báo sớm hơn ngưỡng cố định) — Code: `computeBudgetPace` use case, có unit test riêng. Chạy: giả lập ngày 15/30 đã tiêu 80%. Test: cảnh báo "tiêu nhanh hơn dự kiến" đúng lúc.
54. **Push notification nhắc ghi chi tiêu hàng ngày** — Code: Cloud Messaging + lịch gửi. Chạy: chờ tới giờ hẹn trên máy thật. Test: thông báo xuất hiện đúng giờ.

### Giai đoạn F — Bảo mật, di chuyển dữ liệu, hoàn thiện (6 phase, đánh số 55-60)

55. **Khoá PIN/vân tay** — Code: `local_auth`, `presentation/features/lock/`. Chạy: bật khoá, thoát app mở lại. Test: yêu cầu xác thực trước khi vào app.
56. **Công cụ import CSV từ Google Sheet cũ** — Code: script import vào đúng `months/{yearMonth}`, map đúng 9 hạng mục thật. Chạy: import thử 8 tháng dữ liệu thật đã có (~1700 dòng). Test: tổng số giao dịch import khớp số dòng gốc, không trùng lặp, số dư cuối tháng 8 khớp sheet cũ.
57. **Icon app + onboarding + empty state** — Code: `assets/icon`, `presentation/features/onboarding/`. Chạy: cài app mới hoàn toàn. Test: icon đúng, onboarding hiện đúng 1 lần, empty state rõ ràng khi chưa có giao dịch.
58. **Kiểm thử nhiều kích thước máy Android** — Chạy: chạy trên ≥3 kích thước màn hình/phiên bản OS. Test: UI không vỡ layout ở màn hình nhỏ nhất.
59. **Trang Chính sách quyền riêng tư** — Code: trang tĩnh khai đúng dữ liệu tài chính thu thập. Chạy: mở link. Test: nội dung đủ theo yêu cầu Play Console Data Safety.
60. **Cơ chế bắt buộc cập nhật (force update)** — Code: đọc `minSupportedVersion`/`latestVersion` từ Firebase Remote Config lúc khởi động; nếu `buildNumber` hiện tại < `minSupportedVersion` thì hiện màn chặn toàn bộ, chỉ có nút "Cập nhật ngay" mở Play Store, không có nút bỏ qua; nếu chỉ thấp hơn `latestVersion` thì hiện gợi ý, cho phép bỏ qua. Chạy: đổi `minSupportedVersion` trên Remote Config console cao hơn bản đang cài, mở lại app. Test: app bị chặn đúng lúc cần (vd khi chính sách/schema đổi phải ép người dùng lên bản mới), không cần chờ Google duyệt bản mới mới ép được.

### Giai đoạn G — Phát hành CH Play (5 phase, đánh số 61-65)

61. **Đăng ký Google Play Console + build & ký `.aab`** — Chạy: `flutter build appbundle --release`. Test: file `.aab` sinh ra không lỗi, mở được bằng `bundletool`.
62. **Khai báo Data Safety** — Test: khai đúng mục đích Personal Finance/Tools, không phải Lending/Payments (tránh bị yêu cầu giấy phép không cần thiết).
63. **Internal testing** — Chạy: upload `.aab`. Test: cài được qua link testing trên máy thật.
64. **Closed testing** — Test: đủ số ngày/người dùng tối thiểu Google yêu cầu với tài khoản developer mới.
65. **Phát hành Production** — Test: app xuất hiện công khai trên CH Play, cài + đăng nhập được từ tài khoản Google bất kỳ, không bị gắn cờ vi phạm chính sách.

### Giai đoạn H — Premium & Mở rộng, liên tục sau khi có người dùng thật (4 phase, đánh số 66-69)

66. **Mở khoá tự tạo/sửa hạng mục cho gia đình khác** — đây là lúc hiện thực hoá nguyên tắc "hạng mục là dữ liệu" đã thiết kế từ Phase 1: UI cho gia đình mới tự định nghĩa `kind`/`statuses`/`transferFrom-To` thay vì dùng 9 hạng mục seed cứng của vợ chồng chủ dự án. Test: 1 gia đình test tạo bộ hạng mục hoàn toàn khác vẫn chạy đúng mà không cần sửa code.
67. **Đa ngôn ngữ Việt/Anh** — Code: `flutter_localizations` + `.arb`, tên hiển thị đổi theo locale (Ví Nhà Mình/HomeWallet). Test: đổi ngôn ngữ máy, toàn bộ UI đổi theo, không sót chuỗi hardcode.
68. **In-app purchase gói Premium** — Test: luồng mua hoạt động trơn tru từ giao diện đến ghi nhận quyền lợi trong Firestore.
69. **Widget màn hình chính, nhắc lịch hoá đơn định kỳ, xuất PDF/Excel** — Test: từng tính năng hoạt động độc lập, không phá vỡ luồng core đã ổn định.

---

## Bảng tổng hợp thời gian

| Giai đoạn | Số phase | Ước tính |
|---|---|---|
| A — Nền tảng & lưu trữ local-first | 15 (4 đã xong) | 5–7 ngày |
| B — Firebase & đồng bộ khi có người thứ 2 | 17 | 1.5–2 tuần |
| C — Tài khoản riêng & Quỹ | 9 | 1–1.5 tuần |
| D — Trạng thái & Tổng hợp | 8 | 1–1.5 tuần |
| E — Ngân sách & nhắc nhở | 5 | 4–6 ngày |
| F — Bảo mật & hoàn thiện | 6 | 1–1.5 tuần |
| G — Phát hành CH Play | 5 | 1–2 tuần (chủ yếu chờ Google) |
| H — Premium & mở rộng | 4 | Liên tục |

**Tổng: 69 phase, 4 đã xong.** **Thời gian tới khi có app trên CH Play (hết Giai đoạn G):** khoảng 7–10 tuần làm việc bán thời gian đều đặn — mỗi phase nhỏ, làm xong test qua trong ngày là chuyển tiếp được, không dồn việc lớn đến cuối mới kiểm thử. **Điểm mốc quan trọng: hết Giai đoạn A (phase 15) app đã dùng đầy đủ được rồi — hoàn toàn miễn phí, không cần đụng tới Firebase — cho tới khi thật sự cần chia sẻ với người thứ 2.**

## Chi phí

Google Play Developer: 25 USD một lần. Firebase: miễn phí (gói Spark) ở quy mô gia đình/vài chục người dùng đầu; chỉ cần nâng gói Blaze khi số lượng người dùng hoặc lượng đọc/ghi Firestore tăng đáng kể. Không cần server riêng trong toàn bộ Giai đoạn A–G.

### Ước tính chi phí ở quy mô 100.000 người dùng (~50.000 gia đình)

Con số dưới đây là **ước tính thô để có cảm giác về độ lớn**, không phải báo giá chính xác — luôn kiểm tra lại [công cụ tính giá chính thức của Firebase](https://firebase.google.com/pricing) trước khi ra quyết định, vì biểu giá có thể đổi theo thời gian.

- **Khối lượng dữ liệu:** mỗi giao dịch là 1 document rất nhỏ (~300 byte). 50.000 gia đình × ~200 giao dịch/tháng × vài năm ≈ hàng trăm triệu document, tổng dung lượng khoảng 100–150GB sau vài năm — Firestore xử lý tốt ở quy mô này, **dung lượng không phải điểm tốn tiền chính.**
- **Điểm tốn tiền chính là số lượt đọc/ghi:** ước tính ~40 triệu lượt ghi/tháng (giao dịch + Cloud Function cập nhật số dư/tổng hợp) và ~750 triệu lượt đọc/tháng (mở app, xem lại tháng, tổng hợp) → tổng chi phí Firestore + Cloud Functions rơi vào khoảng **vài trăm USD/tháng**, mức hoàn toàn khả thi nếu có doanh thu Premium.
- **Vì sao schema `months/{yearMonth}` + bảng tổng hợp tính sẵn (rollup) quan trọng:** nếu để client tự cộng dồn toàn bộ lịch sử giao dịch mỗi lần mở màn hình Tổng hợp (thay vì đọc 1 document rollup đã tính sẵn), chi phí đọc có thể **cao hơn 10–50 lần** và ngày càng tệ hơn qua từng năm dữ liệu tích luỹ. Quyết định kiến trúc này ảnh hưởng trực tiếp đến việc mô hình kinh doanh có bền vững hay không ở quy mô lớn.

### Bảo mật cần siết chặt hơn khi lên quy mô lớn

- **Security Rules là rủi ro số 1** — ở quy mô 50.000 gia đình, một lỗi rule có thể lộ dữ liệu tài chính của rất nhiều gia đình cùng lúc, không còn là "chỉ 2 người trong nhà" như lúc dựng MVP.
- **Firebase App Check** — chặn request không đến từ app thật, vừa là bảo mật vừa chống "billing DoS" (ai đó gửi hàng loạt request giả để đội chi phí Firestore lên).
- **Cloud Functions tự kiểm tra quyền**, không chỉ dựa vào Security Rules, vì Functions chạy với quyền admin — không có rule nào chặn được nếu code Function có lỗi.
- **Đặt Google Cloud Budget Alert** ngay khi lên gói Blaze — báo email nếu chi phí tháng vượt ngưỡng bất thường, tránh hoá đơn bất ngờ do bug (vd vòng lặp đọc Firestore).
- **Sao lưu định kỳ (Firestore scheduled export)** — mất dữ liệu ở quy mô nhỏ là phiền, ở quy mô 100k người dùng là khủng hoảng.

### Tạo tài khoản ở quy mô lớn

Firebase Authentication xử lý sẵn, đăng nhập Google gần như miễn phí ở mọi quy mô (không tính theo MAU với các phương thức OAuth như Google/Apple) — **không phải điểm nghẽn chi phí.** Cần cân nhắc thêm phương thức Email/Password làm dự phòng cho người dùng không có tài khoản Google.

## Rủi ro cần lưu ý

Google Play xét duyệt khắt khe hơn với app tài chính (Financial Services policy) dù đây chỉ là sổ ghi chép cá nhân, không kết nối ngân hàng — khai báo đúng mục đích sử dụng (Personal Finance/Tools, không phải Lending/Payments) để tránh bị yêu cầu giấy phép không cần thiết. Vì người dùng chính là dữ liệu tài chính gia đình, một lỗi đồng bộ sai (giao dịch của gia đình A lộ sang gia đình B) là rủi ro nghiêm trọng nhất về kỹ thuật — Security Rules và test rule ở Giai đoạn A phải được ưu tiên làm kỹ, không được bỏ qua để chạy nhanh MVP. Rủi ro này càng lớn hơn khi app mở rộng lên hàng chục nghìn gia đình (xem phần Chi phí ở trên).
