# Phase 8.8 — Presentation containment và create-flow safety audit

Ngày: 2026-09-18. Trạng thái: **REVIEW NEEDED — CREATE OBLIGATION ATOMICITY**.

## A. Pre-implementation/handover audit

Repository được dùng làm bằng chứng; không dùng lại kết quả 317/317 hay khẳng định Drift là root cause từ handoff. Working tree đã có thay đổi trước phiên này. Phân loại sơ bộ theo code và diff: 8.6B gồm recovery profit/loss, recovery summary/three totals và regression tương ứng; 8.7 gồm Counterparty/Obligation, settlement, schema v6, application commands/use cases/providers và test nền; 8.8 gồm loans UI, Home/Summary wiring, date formatter và loans widget tests. Một số file trộn nhiều phase nên không gán cả file cho một phase. Audit tài liệu/diff toàn diện chưa hoàn tất; không chứng nhận các phase cũ PASS.

Đã lưu SHA-256 các file tracked/untracked không bị ignore trước khi sửa, rồi đối chiếu sau sửa. Không commit/reset/revert/stash/discard. Handoff mâu thuẫn giữa “root cause đã xác nhận” và “chưa xác nhận”; chưa tái xác nhận bộ 9 test vì safety gate chưa qua.

## B. Root cause của 0/9 widget tests

Chưa điều tra lại, đúng thứ tự review decision: xử lý containment rồi create safety trước. Không mặc định Drift gây lỗi. Lần đầu chạy bộ Transaction Detail bị lỗi compile do cache thiếu package; `flutter pub get --enforce-lockfile` khôi phục được. Lỗi môi trường này không phải kết luận về 9 loans tests.

## C. Fix đã thực hiện

Transaction Detail trả về view chỉ đọc khi `obligationId != null`, trước nhánh edit generic. Handler Save/Delete/Recovery guard cả argument đã capture và snapshot stream hiện tại; Delete kiểm tra lại sau khi người dùng xác nhận. Không sửa business logic hoặc use-case contract.

## D. Navigation decision

Giữ lịch sử giao dịch. Trong detail chỉ đọc, “Xem khoản vay” lấy đúng metadata theo `obligationId`, dùng `direction` của metadata để mở LoanDetailScreen. Không suy đoán direction từ loại giao dịch (interest cũng là Income). Metadata chưa sẵn sàng/lỗi/thiếu thì action bị disable, giao dịch vẫn chỉ đọc.

## E. Files changed

Chỉ thay đổi trong phiên review này:

- `docs/design.html`: ghi quy tắc giao diện được duyệt trước khi sửa code.
- `lib/presentation/features/transactions/transaction_detail_screen.dart`: view chỉ đọc, navigation, guards; format file.
- `test/presentation/features/transaction_detail_screen_test.dart`: 8 test mới; format file.
- `test/presentation/features/create_loan_safety_audit_test.dart`: 3 test chẩn đoán failure/retry/race, không phải acceptance cho hành vi lỗi.
- `docs/phase-8.8-review-report.md`: báo cáo này.

## F. Main Vay & Cho vay screen

Code hiện có đọc obligation/transaction/counterparty streams. Chưa chạy lại loans screen tests.

## G. Receivable list

Đọc domain summary, bỏ metadata chưa có creation transaction (`summary == null`). Chưa xác nhận runtime toàn luồng.

## H. Payable list

Cùng cách đọc summary. Khoản vay bị mất liên kết creation sẽ không có summary để hiện như một khoản nợ thật — liên quan trực tiếp blocker bên dưới.

## I. Search/filter

Có code tìm theo tên/ghi chú, lọc đang còn/đã tất toán/tất cả. Chưa kiểm thử lại.

## J. Counterparty UX

Create sheet tìm tên đã có hoặc tạo người mới trước metadata. Test failure xác nhận người mới còn tồn tại sau khi bước ghi transaction thất bại. Chưa kiểm chứng mọi trường hợp trùng tên/stream loading.

## K. Create Receivable

Cùng pipeline hai bước với Payable. Chưa được chứng nhận an toàn; không sửa pipeline. Audit race tự động tập trung vào Payable vì command mất linkage vẫn có hình dạng Income thông thường.

## L. Create Payable — create-flow atomicity audit

Thứ tự chính xác trong `_save`:

1. Resolve hoặc `addCounterparty`, await.
2. Sinh `_obligationId`, `addObligation`, await; sau đó đặt `_obligationPersisted = true`.
3. `CreateTransactionCommandFactory.create`, await, lưu `_pendingCommand`.
4. `AddTransactionUseCase`, await.
5. Pop sheet nếu thành công; catch chỉ hiện message; finally bỏ `_submitting`.

Các kết quả đã tái hiện bằng production widget và production factory/use case, với repository doubles và Completer để điều khiển ranh giới async (không dùng delay):

- **Transaction thất bại trước khi ghi:** Counterparty + Obligation metadata còn lại; không có transaction. `computeObligationSummary` trả **null**, không phải một khoản vay đã tất toán có outstanding = 0. LoansScreen bỏ qua summary null.
- **Retry cùng form, cùng sheet:** tái sử dụng obligation ID, transaction ID và clientTxId; không thêm metadata lần nữa. Test đã pass.
- **Sửa số tiền sau failure rồi retry:** `_resetPending` xóa identity; tạo metadata thứ hai; metadata thứ nhất không có creation transaction và không có summary. Đây là orphan ẩn, chưa phải bằng chứng tự nó làm balance sai; chưa có cơ chế recovery/cleanup rõ ràng sau đóng sheet.
- **Race xác nhận:** trong khi `addObligation` đang await, form vẫn edit được. Sửa amount chạy `_resetPending`, đặt `_obligationId = null`. Khi await hoàn tất, `_obligationPersisted = true` nhưng ID vẫn null. Factory nhận `obligationId = null`, amount giữ giá trị capture trước khi sửa. Với Payable, transaction chuyển tới repository là Income không gắn khoản vay. Repository double nhận thành công, sheet đóng; metadata không có summary. Đây là bằng chứng trực tiếp về command mất linkage và UI thành công giả. Test này không phải bằng chứng đã thực thi ghi sai trên database thật; chưa chạy tình huống phá dữ liệu với LocalTransactionRepository.

**STOP:** không tự thêm compensation, không thay repository/application contracts.

Smallest-safe alternatives cần review, chưa triển khai:

1. Presentation giữ immutable submission snapshot/identity xuyên suốt attempt; khóa toàn bộ edit và dismiss khi đang ghi; định nghĩa rõ retry hoặc chỉnh sửa sau metadata đã persisted. Cần thêm test failure và retry ở từng ranh giới, gồm đóng/mở lại sheet. Chỉ khóa nút Save là chưa đủ.
2. Atomic create use case cho metadata + transaction trong cùng DB transaction là lựa chọn khác, nhưng đụng frozen contracts/repository nên cần mở phạm vi riêng; không triển khai trong phiên này.

## M. Receivable detail

Navigation test đã xác nhận đúng obligationId và direction. Chưa chứng nhận toàn bộ detail/business actions.

## N. Payable detail

Navigation được test tương tự; cùng giới hạn kiểm chứng.

## O. Settlement UX

Không sửa. Chưa kiểm thử lại nhận/trả tiền trong phiên này.

## P. Interest preview

Không sửa allocation. Chưa kiểm chứng độc lập preview.

## Q. Partial settlement

Không sửa; chưa chạy regression settlement.

## R. Due date/overdue

Không sửa; chưa xác minh UI trên thiết bị.

## S. Reversal UX — generic containment

Transaction tạo Receivable/Payable, principal, interest và Payable settlement đều không có generic Delete/Reverse/Recovery action. Stale Delete callback và dialog đã mở trước snapshot mới không gọi generic reverse. Giao dịch thường vẫn reverse được theo regression cũ.

## T. Correction UX — generic containment

Các transaction có obligationId không có editable field hay generic Save. Stale Save callback không gọi generic update. Normal note/amount/status edits vẫn pass. Không thay settlement correction API.

## U. Double-submit

Normal transaction detail double-delete regression vẫn pass. Create form có `_submitting` cho Save nhưng không khóa các field; không đủ bảo vệ state đang await, như audit L đã tái hiện. Không chứng nhận create double-submit/retry an toàn tổng thể.

## V. Error mapping

Regression Transaction Detail cho các exception hiện có pass. Create failure không đóng sheet và cho retry; audit không đánh giá toàn bộ message map khoản vay.

## W. Source-of-truth verification

Read-only detail và guard đọc stream snapshot; không increment/decrement tài chính bằng widget state. Domain summary được gọi nguyên trạng trong audit. Create linkage race phá liên hệ metadata–ledger trước khi source-of-truth có thể tạo loan summary; chưa sửa.

## X. Home dashboard

Không thay đổi trong phiên này; chưa chạy lại Home tests.

## Y. Summary screen

Không thay đổi trong phiên này; chưa chạy lại Summary tests.

## Z. Widget test result

`flutter test test/presentation/features/transaction_detail_screen_test.dart --reporter expanded`: **25/25 PASS**, gồm 17 test trước đó + 8 mới. Creation và settlement read-only, no generic mutations, navigation đúng, missing metadata an toàn, normal transaction regression đều được kiểm tra.

`flutter test test/presentation/features/create_loan_safety_audit_test.dart --reporter expanded`: **3/3 characterization tests PASS**. Nghĩa là đã tái hiện failure/retry và bug như mô tả; **không có nghĩa create-flow safety PASS**.

`loans_screen_test.dart`: chưa chạy/chưa sửa; không tuyên bố 0/9 hoặc 9/9 là kết quả hiện tại.

## AA. Loans/domain/repository regression

Chưa chạy do second safety gate không qua. Không thay các layer này.

## AB. Full test result

Chưa chạy `flutter test --concurrency=1` trong phiên review. Không tái sử dụng 317/317 hoặc suy ra tổng suite.

## AC. Golden 2026 result

Chưa chạy lại. Không đọc/import/reinterpret fixture hoặc đổi expected. Mốc yêu cầu vẫn là Vợ Available 244.000, Savings 4.740.000; Chồng Available 835.000, Savings 70.500.000; Total Assets 76.319.000. Không tuyên bố EXACT PASS.

## AD. Analyze result

Đã chạy **`flutter analyze` toàn repo**: 0 error, 1 warning unused import trong fund_list_screen, 16 info deprecated APIs. Tất cả vị trí issue là code đã có trước thay đổi; 2 info trong transaction detail nằm trên dropdown `value` cũ, chỉ đổi số dòng vì formatting. Không có issue ở test mới. Không gọi kết quả này là analyze sạch.

## AE. Pixel 7a readiness

Chưa READY FOR DEVICE TEST cho toàn Phase 8.8 vì create-flow blocker; chưa chạy trên thiết bị.

## AF. iOS portability

Không thêm platform-specific dependency hay code Android-only. Chưa build/test iOS.

## AG. Frozen-layer verification và final git audit

SHA-256 so với đầu phiên xác nhận không sửa Domain, Application, Data, schema v6, generated database, providers, Home/Summary hay loans production files. Pubspec và lockfile không đổi. Không thêm Firebase/Billing/migration v7. Không có private Golden JSON/CSV được track; không stage hoặc commit file. `git status`/`git diff --stat` vẫn gồm cả thay đổi 8.6B/8.7/8.8 có trước, không được quy tất cả cho phiên này.

## AH. Known technical debt

Repository-level protection cho generic mutations của obligation transactions (`ObligationHasSettlementsException`) vẫn chưa được xử lý. Presentation guard không thay thế invariant/guard ở repository. Localization toàn diện vẫn chưa có trong phần UI kế thừa.

## AI. REVIEW NEEDED

**REVIEW NEEDED — CREATE OBLIGATION ATOMICITY**: cần quyết định lifecycle của immutable create request, edit/dismiss khi đang lưu, retry sau persisted metadata, và xử lý orphan sau thất bại/đóng sheet. Không tự chọn compensation hay atomic contract mới.

## AJ. BLOCKER

Command tạo khoản đi vay có thể mất obligationId khi sửa form giữa hai bước ghi; UI vẫn đóng sau callback thành công. Retry sau sửa form cũng đổi identity và bỏ metadata cũ. Containment generic đã pass nhưng không giải quyết các lỗi này.

## AK. Final verdict

**GENERIC TRANSACTION CONTAINMENT = PASS (25/25 targeted tests).**

**PHASE 8.8 = BLOCKED — CREATE-FLOW REVIEW REQUIRED.**

**LOANS PRESENTATION chưa READY FOR DEVICE TEST.**

Dừng tại Phase 8.8. Không commit, không sang Phase 8.9, không tự sửa frozen layers hoặc create compensation.
