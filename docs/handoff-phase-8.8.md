# BÀN GIAO — Phase 8.8 "Vay & Cho vay" (Presentation)

> **DỪNG theo yêu cầu người dùng tại trạng thái này.** Không commit, không
> reset, không revert, không tiếp tục implement. Báo cáo dưới đây phản ánh
> ĐÚNG những gì đã thật sự chạy — không có gì được "sửa vội để tạo PASS giả".

## Trạng thái tổng quan

- **Phase 8.6B, Phase 8.7 = PASS hoàn toàn**, đã báo cáo đầy đủ trong hội thoại trước. Foundation (schema v6, `Counterparty`, `Obligation`, `PoolKind.receivable`, atomic settlement, reversal/correction, `computeObligationSummary`, `totalReceivables`/`totalPayables`/`netWorth`) **KHÔNG được sửa** ở Phase 8.8 — đây là frozen layer.
- **Phase 8.8 (Presentation) đã code XONG phần UI**, đã wire vào Home/Summary, **domain+repository regression suite cũ (317 test) vẫn PASS 100%**, `flutter analyze` sạch (chỉ còn 17 issue info/warning có từ trước, không liên quan).
- **CHƯA XONG:** bộ widget test MỚI viết cho Phase 8.8 (`test/presentation/features/loans_screen_test.dart`) đang **FAIL TOÀN BỘ (0/9)**. Đây là việc cần Codex tiếp tục điều tra/sửa.
- **CHƯA COMMIT gì** trong suốt cả phiên làm việc này (đúng chỉ thị "Không commit" xuyên suốt 8.6B/8.7/8.8). Toàn bộ thay đổi đang nằm ở working tree.

## Việc CẦN LÀM TIẾP (ưu tiên cao nhất)

### 1. Debug `test/presentation/features/loans_screen_test.dart` (0/9 PASS)
Triệu chứng lặp lại ở hầu hết test: `tester.tap(find.byIcon(Icons.add_rounded))` xong, rồi `tester.tap(find.byKey(const Key('createLoan_save')))` báo:
```
The finder "Found 0 widgets with key [<'createLoan_save'>]: []" ... could not find any matching widgets.
```
→ Nghĩa là **bottom sheet "Cho vay" không hề mở ra** sau khi tap FAB, hoặc `LoansScreen` chưa render xong FAB lúc đó.

**Root cause ĐÃ XÁC NHẬN (không còn là giả thuyết)** — chạy riêng test đơn giản nhất "1 — mở màn, empty state" (KHÔNG hề có `tester.tap` nào) và để chạy tới khi tự kết thúc: **treo đúng 10 phút rồi timeout**, lỗi cuối:
```
A Timer is still pending even after the widget tree was disposed.
Failed assertion: line 2543 pos 12: '!timersPending'
```
Stack trace cho thấy Timer bị leak nằm trong `StreamQueryStore`/`QueryStream` của Drift (`package:drift/src/runtime/executor/stream_queries.dart`) — cơ chế stream-query nội bộ của Drift tạo ra 1 `Timer` không được huỷ đúng lúc trong vòng đời `pumpAndSettle()`/dispose của `ProviderScope`/widget test.

**Kết luận:** nguyên nhân là do **kết hợp DB Drift THẬT** (`AppDatabase.forTesting(NativeDatabase.memory())` override `appDatabaseProvider`) **với `pumpAndSettle()` trong widget test** — KHÔNG phải lỗi logic của `LoansScreen`/`create_loan_sheet.dart` (test không-tap cũng treo y hệt). Mọi widget test khác trong repo (`add_transaction_sheet_test.dart`, `home_screen_test.dart`, `transaction_detail_screen_test.dart`) đều dùng **fake repository in-memory kiểu `StreamController`** (không đụng Drift thật) — đã chứng minh ổn định. `loans_screen_test.dart` là file DUY NHẤT trong repo thử kết hợp Drift thật + widget test, và đó chính là điểm gãy.

**Khuyến nghị sửa (chưa làm — ưu tiên #1, vì root cause đã xác nhận là do Drift stream + widget test, không phải lỗi UI):** Viết lại `loans_screen_test.dart` theo ĐÚNG convention đã có trong repo — dùng **fake repository** (`implements TransactionRepository`/`CounterpartyRepository`/`ObligationRepository`, `StreamController` broadcast, mirror `RecordingTransactionRepository`/`_FakeTransactionRepository` đã có ở `test/application/support/recording_transaction_repository.dart` và `test/presentation/features/add_transaction_sheet_test.dart`), thay vì Drift thật. Cần viết fake cho cả 3 repository (Transaction/Counterparty/Obligation) vì `LoansScreen`/`CreateLoanSheet`/`SettleLoanSheet`/`LoanDetailScreen` đều phụ thuộc cả 3. Đây là hướng sửa AN TOÀN nhất — không cần hiểu sâu internals của Drift's `StreamQueryStore`, chỉ cần đổi cách test dựng dữ liệu, không đổi code `lib/`.

Nếu MUỐN giữ Drift thật (test end-to-end sát thực tế hơn), sẽ cần xử lý tận gốc Timer leak trong `StreamQueryStore` — rủi ro cao hơn, có thể cần patch cách đóng `AppDatabase` giữa các test hoặc dùng `tester.runAsync`/`fakeAsync` khác đi. **Không khuyến nghị hướng này trước** vì tốn thời gian điều tra hơn nhiều so với việc đổi sang fake repository.

**Việc bắt buộc trước khi coi Phase 8.8 = PASS:** phải có ít nhất bộ test widget PASS thật (không phải giả định), phủ tối thiểu: mở màn rỗng, tạo Receivable, tạo Payable, nhận tiền (không lãi + có lãi + preview đúng), trả tiền, hoàn tác, sửa, error mapping an toàn — đúng yêu cầu gốc mục 27 của prompt Phase 8.8 (không cần đủ 42 test riêng, nhưng phải THẬT SỰ PASS, không được báo PASS giả).

### 2. Sau khi test pass, chạy lại đầy đủ
```bash
flutter analyze
flutter test --concurrency=1
flutter test test/golden_data/real_data_golden_test.dart
```
Golden checkpoint bắt buộc khớp: Vợ avail 244.000/savings 4.740.000, Chồng avail 835.000/savings 70.500.000, Total Assets 76.319.000.

### 3. Viết Final Report
Sau khi xanh hết, viết Final Report theo đúng khung mục A→AG đã yêu cầu trong prompt gốc Phase 8.8 (Pre-implementation audit / Navigation decision / Files changed / .../ REVIEW NEEDED / BLOCKER / Final verdict), rồi DỪNG — không tự chuyển sang phase khác, không commit trừ khi được yêu cầu.

## Danh sách file đã thay đổi (chưa commit)

Chạy `git status` để xác nhận danh sách mới nhất. Tại thời điểm bàn giao:

**Domain (Phase 8.6B + 8.7, đã PASS, KHÔNG động vào nữa trừ khi có blocker thật):**
- `lib/domain/entities/counterparty.dart`, `obligation.dart`, `obligation_direction.dart` (mới)
- `lib/domain/entities/pool_kind.dart`, `transaction.dart` (sửa — thêm `PoolKind.receivable`, `obligationId`/`settlementGroupId`)
- `lib/domain/engine/obligation_settlement.dart` (mới)
- `lib/domain/engine/financial_engine.dart` (sửa — `isSameLogicalTransaction` thêm so `obligationId`)
- `lib/domain/usecases/compute_obligation_summary.dart` (mới)
- `lib/domain/usecases/compute_financial_summary.dart`, `compute_recovery_summary.dart`, `compute_three_totals.dart` (sửa — 8.6B + 8.7)
- `lib/domain/repositories/counterparty_repository.dart`, `obligation_repository.dart` (mới)
- `lib/domain/repositories/transaction_repository.dart` (sửa — 3 method mới: `settleObligation`/`reverseObligationSettlement`/`correctObligationSettlement`)
- `lib/domain/errors/domain_exceptions.dart` (sửa — exception mới cho recovery/obligation)

**Data (Phase 8.7):**
- `lib/data/local/app_database.dart` + `.g.dart` (schema v6)
- `lib/data/repositories/local_transaction_repository.dart` (sửa — implement 3 method mới)
- `lib/data/repositories/local_counterparty_repository.dart`, `local_obligation_repository.dart` (mới)

**Application:**
- `lib/application/commands/settle_obligation_command.dart` (mới)
- `lib/application/use_cases/settle_obligation_use_case.dart`, `reverse_obligation_settlement_use_case.dart`, `correct_obligation_settlement_use_case.dart` (mới)
- `lib/application/commands/create_transaction_command.dart` + `create_transaction_command_factory.dart` + `lib/application/use_cases/add_transaction_use_case.dart` (sửa — thêm `obligationId`)

**Presentation (Phase 8.8 — MỚI, chưa test pass):**
- `lib/presentation/features/loans/` — thư mục mới:
  - `loans_screen.dart` — màn chính "Vay & Cho vay" (segment Receivable/Payable, search, filter, list card)
  - `loan_detail_screen.dart` — chi tiết + lịch sử gộp leg + hoàn tác/sửa
  - `create_loan_sheet.dart` — form "Cho vay"/"Đi vay" (bottom sheet), có Counterparty inline picker/create
  - `settle_loan_sheet.dart` — form "Nhận tiền"/"Trả tiền" + preview gốc/lãi (dùng `buildObligationSettlementLegs` — KHÔNG tự tính lại)
  - `loan_history.dart` — gộp 2 ledger leg thành 1 dòng lịch sử hiển thị (thuần Dart, không widget)
  - `loan_error_mapping.dart` — map exception → message tiếng Việt an toàn
- `lib/presentation/providers/counterparty_providers.dart`, `obligation_providers.dart` (mới, viết ở Phase 8.7)
- `lib/presentation/features/home/home_screen.dart` (sửa — thêm card "Vay & Cho vay" + dòng "Tài sản ròng" khi có Payable)
- `lib/presentation/features/summary/summary_screen.dart` (sửa — thêm Phải thu/Phải trả/Tài sản ròng, KHÔNG cộng Receivable 2 lần vào Total Assets)
- `lib/core/utils/formatters.dart` (sửa — thêm `Formatters.dayMonthYear`)
- `lib/core/constants/default_categories.dart` (sửa ở Phase 8.7 — thêm `choVay`/`laiChoVay`/`vayNo`/`traNo`)

**Test:**
- `test/domain/obligation_settlement_test.dart` (mới, Phase 8.7 — 11 test, PASS)
- `test/data/repositories/obligation_repository_test.dart` (mới, Phase 8.7 — 15 test atomicity/idempotency/reversal/correction, PASS)
- `test/data/local/app_database_test.dart` (sửa — thêm test migration v5→v6, PASS)
- `test/domain/compute_financial_summary_test.dart` + `compute_recovery_summary_test.dart` (sửa — 8.6B + 8.7, PASS)
- `test/presentation/features/home_screen_test.dart`, `add_transaction_sheet_test.dart`, `transaction_detail_screen_test.dart` + `test/presentation/providers/transaction_stream_provider_test.dart` + `test/application/support/recording_transaction_repository.dart` (sửa — thêm stub 3 method mới của `TransactionRepository` cho các fake, PASS)
- **`test/presentation/features/loans_screen_test.dart` (MỚI, Phase 8.8 — 9 test, ĐANG FAIL 0/9 — CẦN SỬA, xem mục 1 ở trên)**

## Ràng buộc BẮT BUỘC phải giữ khi tiếp tục (đọc lại prompt gốc Phase 8.8 để đầy đủ)

1. **KHÔNG dùng thuật ngữ kỹ thuật trong UI**: Receivable/Payable/Obligation/settlement/PoolKind/principal leg/settlement group/clientTxId/obligationId — TUYỆT ĐỐI không lộ ra text hiển thị hay error message.
2. **Không tự tính lại tài chính trong Presentation** — mọi outstanding/gốc/lãi/status phải đọc từ `computeObligationSummary`/`buildObligationSettlementLegs`/`FinancialSummary` đã có, KHÔNG viết công thức mới trong widget.
3. **Không sửa Financial Engine/schema v6/atomicity/idempotency/principal-first rule** trừ khi phát hiện blocker thật — nếu cần sửa, phải STOP và báo trước, không tự quyết.
4. **Golden 2026 phải EXACT PASS**, không được reinterpret dòng "Chị hằng mượn tiền về quê".
5. Double-submit phải có guard (`_submitting` flag) — đã làm trong `create_loan_sheet.dart`/`settle_loan_sheet.dart`, cần test xác nhận.
6. Correction chỉ cho phép trên lần tất toán MỚI NHẤT — đã derive qua `LoanHistoryEntry.isLatestSettlement`, KHÔNG dựa vào exception để disable UI.
7. Reversal/Correction phải luôn gọi qua `reverseObligationSettlementUseCaseProvider`/`correctObligationSettlementUseCaseProvider` — KHÔNG bao giờ gọi `reverseTransactionUseCaseProvider`/`updateTransactionUseCaseProvider` (generic) lên giao dịch có `obligationId`. **LƯU Ý: đã phát hiện 1 gap thật ở Phase 8.7** — `ObligationHasSettlementsException` được định nghĩa trong `lib/domain/errors/domain_exceptions.dart` nhưng CHƯA wire vào `reverseTransaction`/`updateTransaction` generic trong `LocalTransactionRepository` — nếu ai đó reverse/sửa giao dịch TẠO khoản vay đã có tất toán qua đường generic, có thể làm pool `receivable` âm (vi phạm Invariant 7). Phase 8.8 **cố tình không xây UI** cho việc sửa/xoá giao dịch TẠO khoản vay (chỉ có action trên các dòng tất toán trong lịch sử) để né gap này — **PHẢI giữ nguyên quyết định này**, không thêm nút "Sửa"/"Xoá" cho dòng "Cho vay"/"Đi vay" gốc trong `loan_detail_screen.dart` trừ khi gap đó được vá đúng cách ở tầng Repository trước (và đó sẽ là 1 thay đổi cần STOP + báo trước, không tự quyết).
8. Không thêm Firebase/Billing/Android-only dependency.

## Cách chạy lại nhanh
```bash
flutter analyze
flutter test test/presentation/features/loans_screen_test.dart   # đang fail, cần sửa trước
flutter test --concurrency=1                                     # xem mục "Trình tự test đã chạy" — CHƯA rerun full kèm file trên
flutter test test/golden_data/real_data_golden_test.dart
```

## Trình tự lệnh THẬT ĐÃ CHẠY (theo đúng thứ tự, không suy đoán)

1. `flutter analyze lib` (nhiều lần trong lúc code Phase 8.7 + 8.8) → sạch, chỉ còn 17 issue info/warning pre-existing.
2. `flutter test --concurrency=1` (SAU khi hoàn tất code Phase 8.7 + phần lib/ của Phase 8.8, TRƯỚC KHI tạo file `loans_screen_test.dart`) → **317/317 PASS**. Lúc này `test/presentation/features/loans_screen_test.dart` CHƯA TỒN TẠI.
3. Tạo `test/presentation/features/loans_screen_test.dart` (9 test) → chạy riêng file này:
   - Lần 1: lỗi compile (code thừa/hỏng do viết vội) → đã sửa.
   - Lần 2: `flutter analyze test/presentation/features/loans_screen_test.dart` → sạch, không lỗi tĩnh.
   - Lần 3 (chạy thật): **0/9 PASS — cả 9 test đều fail**, lỗi lặp lại `Found 0 widgets with key [<'createLoan_save'>]` (bottom sheet không mở được trong môi trường test).
4. **CHƯA chạy lại `flutter test --concurrency=1` (full suite) kể từ khi file `loans_screen_test.dart` tồn tại.** Vì vậy con số "317/317" ở bước 2 là trạng thái CŨ (đúng tại thời điểm đó), KHÔNG phải trạng thái hiện tại của toàn repo — hiện tại nếu chạy full suite, tổng sẽ là 326 test với ít nhất 9 fail (326-9=317 pass, đúng bằng số cũ, NHƯNG suite tổng thể KHÔNG còn "toàn xanh" nữa vì có file mới fail).
5. **CHƯA chạy lại** `flutter test test/golden_data/real_data_golden_test.dart` riêng kể từ sau khi sửa `home_screen.dart`/`summary_screen.dart` ở Phase 8.8 — lần cuối nó chắc chắn PASS là trong lần full-suite ở bước 2 (baseline `computeFinancialSummary` không đổi ý nghĩa `totalAssets`/golden fixture, rủi ro thấp, nhưng CHƯA re-verify độc lập sau đó).

## Quyết định/giả định MỚI phát sinh trong phiên (chưa có trong audit gốc)

- Thêm `Formatters.dayMonthYear` (phụ trợ hiển thị, không ảnh hưởng tài chính).
- Danh sách "Vay & Cho vay" (`loans_screen.dart`) hiển thị NGÀY cho vay bằng cách gọi `findObligationCreationTransaction` riêng cho từng dòng (không cache) — chấp nhận chi phí quét lại vì scale nhỏ (cá nhân/gia đình).
- `create_loan_sheet.dart`: double-submit qua RETRY (không phải double-tap) được bảo vệ bằng cách tự đóng băng `obligationId`/Counterparty-cần-tạo/`CreateTransactionCommand` trong state của sheet — CHƯA có test xác nhận hành vi này (nằm trong 9 test đang fail).
- **Phát hiện gap thật ở Phase 8.7 (không phải giả định mới, là finding):** `ObligationHasSettlementsException` được định nghĩa nhưng chưa wire vào `reverseTransaction`/`updateTransaction` generic — Phase 8.8 né bằng cách không xây UI sửa/xoá giao dịch TẠO khoản vay. Xem mục ràng buộc #7 bên dưới.

## REVIEW NEEDED / BLOCKER tại thời điểm dừng

- **BLOCKER cho việc tuyên bố "Phase 8.8 = PASS":** `test/presentation/features/loans_screen_test.dart` fail 9/9. Nguyên nhân kỹ thuật CHƯA được xác nhận (chỉ có giả thuyết ở mục 1 phía trên) — cần điều tra thêm trước khi sửa, không đoán mò sửa test để "cho qua".
- Không phát hiện BLOCKER nào ở tầng Domain/Data/Application (317 test đó vẫn là bằng chứng hợp lệ cho tầng đó, KHÔNG bị ảnh hưởng bởi vấn đề của widget test mới).
- Không có REVIEW NEEDED nào về financial semantics — mọi logic tài chính Phase 8.8 đều gọi lại API Phase 8.7 có sẵn, không tự tính toán mới.

## Next exact implementation step (việc kế tiếp, theo đúng thứ tự)

1. **Root cause đã xác nhận** (xem mục 1 phía trên — Timer leak trong Drift `StreamQueryStore` khi kết hợp DB thật với `pumpAndSettle`). Viết lại `test/presentation/features/loans_screen_test.dart` dùng fake repository (StreamController-based) thay vì `AppDatabase.forTesting(NativeDatabase.memory())`, theo đúng convention `add_transaction_sheet_test.dart`/`home_screen_test.dart` đã có. KHÔNG cần sửa code trong `lib/presentation/features/loans/` — vấn đề nằm ở cách dựng test, không phải logic UI.
2. Sau khi 9 test đó pass thật (bằng fake repository), chạy `flutter test --concurrency=1` cho TOÀN BỘ repo (không filter path) để có con số tổng chính xác của trạng thái mới.
3. Chạy riêng `flutter test test/golden_data/real_data_golden_test.dart` để xác nhận lại EXACT PASS sau các thay đổi Home/Summary.
4. Viết Final Report theo khung A→AG trong prompt gốc Phase 8.8.
5. STOP — không tự chuyển sang phase khác, không commit trừ khi được yêu cầu rõ.
