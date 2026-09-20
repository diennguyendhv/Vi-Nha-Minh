# HANDOFF — True Transaction Delete (checkpoint 2026-09-20, CHƯA COMMIT)

> Trạng thái: scope đã được owner DUYỆT PASS và cho phép commit ("CHECKPOINT APPROVED — COMMIT TRUE TRANSACTION DELETE"), nhưng owner nhắn "dừng lại đã" ngay lúc đang chạy pre-commit check → **chưa commit**. Việc tiếp theo: hỏi owner có commit không (hoặc chờ chỉ dẫn), rồi commit đúng như dưới.

## Baseline (đã xác nhận)
HEAD = `adc8ed5` (Savings 2 tầng). Working tree: 24 file sửa + 4 file mới (untracked):
`lib/application/use_cases/delete_transaction_use_case.dart`, `lib/domain/usecases/compute_deletable_master_data.dart`, `test/data/repositories/transaction_true_delete_test.dart`, `test/domain/compute_deletable_master_data_test.dart`.
Gate: full suite **712/712**, Golden **24/24** (không sửa), analyze **16/0**, schema **v7**, Pixel PASS (Đợt 16 trong `docs/pixel-7a-acceptance-test-plan.md`), SQLite integrity ok.
Pre-commit check ĐÃ chạy sạch: không DB/APK/file tạm/secret, `lib/data/local` + `test/golden_data` không đổi.

## Đã làm (nội dung commit)
- **Xóa giao dịch = XÓA THẬT**: `TransactionRepository.deleteTransaction` xóa vật lý cả "họ giao dịch" (gốc+hoàn tác+thay thế, nối qua reversalOf/corrects/reversedBy) trong 1 DB transaction; hàm thuần trong `financial_engine.dart`: `transactionFamilyIds`, `deleteBlockReason`, `poolOverdrawnByRemoval`. Chặn: pool âm → `DeleteWouldOverdrawException`; dính Vay/Hoàn tiền (obligationId/settlementGroupId/recoveryOfTxId cả 2 chiều) → `TransactionDeleteBlockedException`. `DeleteTransactionUseCase` + provider; màn chi tiết đổi câu chữ "Xóa giao dịch" (bỏ chữ "hoàn tác").
- **Dọn lịch sử ẩn cũ**: `purgeDeletedHistory(categoryId)` + nút "Dọn lịch sử đã xóa" ở danh mục ngừng (chỉ khi danh mục chỉ còn bị giữ bởi cặp gốc+hoàn tác ẩn). Chỉ cho Category (owner: đủ).
- **Bất biến status↔category**: `InvalidStatusForCategoryException` khi ghi/sửa; đổi danh mục không chỉ định trạng thái hợp lệ → xóa trạng thái cũ (cả đường sửa tại chỗ và đường hoàn tác+thay thế; `buildCorrection(clearStatus)`); lưu lại giao dịch cũ bị lệch → chữa. Root cause: UI gửi statusId=null nhưng repo hiểu null = "không đổi".
- **Fix stale "Xóa hẳn"**: danh sách an toàn-xóa-hẳn của Category/Status/SavingsAssetType suy ra từ dữ liệu đang xem (`compute_deletable_master_data.dart`, `computeDeletableAssetTypeIds`) thay vì stream Drift `customSelect('SELECT 1')` (Drift không phát lại khi kết quả giống hệt). Xóa thật vẫn re-check trong DB.
- Docs: `financial-core-v2.md` Invariant 18–19, `CLAUDE.md` §15, `design.html` (+ tab nhúng đã sync), plan Đợt 16.
- Test: 32 test tích hợp Drift thật (A–N), test hàm thuần, UI Danh mục/chi tiết; 2 test cũ đổi fixture (status lệch giả lập bằng SQL; FK statusId không tồn tại vẫn PersistenceConstraint).

## Commit đề xuất
`feat(finance): support safe transaction deletion` — body nêu: true delete + family cleanup, negative-pool guard, loan/recovery block, status/category integrity, master-data cleanup interaction (derive deletable from live data); baseline 712/24/16, schema v7. Trailer: `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`. Sau commit báo A–G (hash, message, files, tests, golden, analyze, git status clean) rồi STOP.

## Owner decisions đã chốt
- clientTxId được giải phóng sau hard-delete: ACCEPT (local MVP). **BACKLOG QUAN TRỌNG: review clientTxId/idempotency (tombstone) TRƯỚC Firebase two-user sync.** Không mở schema/tombstone bây giờ.
- Dữ liệu Pixel "Chi Phí Vận Hành": giao dịch Sinh hoạt 1.000.000đ (19/09) gắn bước "Chưa trả" của danh mục khác. KHÔNG repair trong source commit; sau commit owner sẽ xử lý riêng (mở giao dịch → Lưu để tự chữa). Danh mục "Chi Phí Vận Hành" hiện đang ACTIVE (owner đã "Sử dụng lại").
- KHÔNG tự làm: Status/SavingsAssetType "dọn lịch sử ẩn" UI, Firebase, tombstone, F6, R5, R6, i18n ARB, maturity/interest.

## Trạng thái máy/Pixel
Pixel 7a wireless adb (mdns), DB đã dọn: 102 giao dịch; Vợ 11.830.000 / Tiết kiệm 0; Chồng 15.715.000 / 200.000 (savings_bank); Total Assets 28.695.000; loại tài sản Vàng/Chứng khoán/Khác đang ngừng; không còn danh mục thử ZZ. Còn vài dòng giao dịch/hoàn tác thử của Savings (số dư về mốc gốc).
