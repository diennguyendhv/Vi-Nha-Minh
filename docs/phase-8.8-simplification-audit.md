# Phase 8.8 — Product Simplification: AUDIT (chưa code, chờ REVIEW)

Ngày: 2026-09-19. Trạng thái: **DỪNG TẠI CỔNG QUYẾT ĐỊNH** — 1 việc cần thay đổi schema (additive). Không có dòng code nào bị sửa.

## 1. Trả lời 12 câu hỏi của brief

1. **4 nhóm có đổi financial effect không?** Không. Chúng chỉ là phân loại/báo cáo. `TransactionType` giữ INCOME/EXPENSE/TRANSFER.
2. **Có cần sửa `applyEffect` không?** Không.
3. **Có cần schema migration không?** Có, nhưng rất nhỏ (xem mục 3): 1 cột additive trên `category_rows`. Vì brief nói "cần migration → STOP", mình dừng để xin duyệt.
4. **Có cần `parentCategoryId` không?** Không. 2 tầng = "nhóm chính (do hệ thống định nghĩa)" → "danh mục con (Category hiện có)". Nhóm chính suy ra từ các cờ trên Category, không cần bảng cha.
5. **Có thể biểu diễn 2 tầng bằng master data hiện có không?** Một nửa:
   - **Thu:** được. Doanh thu = `income && !excludeFromTotals`; Khoản thu khác = `income && excludeFromTotals` (đúng ngữ nghĩa sẵn có của "Số dư ban đầu", "Hoàn tiền").
   - **Chi:** không. Hiện KHÔNG có trường nào phân biệt Chi tiêu với Chi phí kinh doanh. Người dùng tự tạo nhiều danh mục kinh doanh (Lương GV, Quảng cáo…) nên không thể dựa vào 1 id cố định; dựa vào tên là bị cấm.
6. **Category phẳng hiện tại có đủ không?** Đủ cho Thu; thiếu cho Chi (mục 5).
7. **Số dư ban đầu → ?** Khoản thu khác (đã `excludeFromTotals`, không phải doanh thu). Không đổi gì.
8. **Recovery ảnh hưởng reportable income thế nào?** Hiện chỉ phần LỢI NHUẬN vượt vốn (`computeRecoveryProfitPortions`) được cộng vào `totalIncome`, phần hoàn vốn thì không. Với mô hình mới (người dùng tự nhập "Khoản thu khác" + "Doanh thu" lãi) thì Recovery không cần hiện nữa; giữ code cho lịch sử.
9. **Loans ảnh hưởng Income/Expense thế nào?** Tạo khoản Đi vay (income) không tính thu nhập; Tất toán Đi vay chỉ phần LÃI tính vào Chi; Cho vay = TRANSFER (không đụng Thu/Chi); Lãi cho vay = income thường (đang tính vào Thu).
10. **Golden 2026 bị ảnh hưởng chỗ nào?** Không, nếu chỉ THÊM số liệu báo cáo mới và không sửa `computeThreeTotals`/`applyEffect`. Golden đang dùng `thu_nhap` (224), `chi_phi_kinh_doanh` (24), `so_du_ban_dau` (5) — khớp mô hình mới.
11. **DB Pixel hiện có xử lý ra sao?** Không viết lại giao dịch. 2 danh mục Chi do người dùng tự tạo ("Chi phi kinh doanh", "Chi Phí Vận Hành") sẽ mặc định là Chi tiêu cho tới khi người dùng đổi nhóm 1 lần trong màn sửa danh mục (không đoán theo tên/Note).
12. **Nguy cơ 2 nguồn sự thật?** Chỉ nếu thêm cột trùng ý với `excludeFromTotals`. Đề xuất tránh: KHÔNG thêm cột cho nhóm Thu.

## 2. Financial Core compatibility
- `computeThreeTotals`, `computeReportableIncomeEntries`, Total Assets/Net Worth, reversal/correction: **giữ nguyên**.
- Các số mới (Doanh thu, Khoản thu khác, Chi tiêu, Chi phí kinh doanh, Thu nhập ròng, Dòng tiền ròng) là **hàm báo cáo mới, chỉ đọc**, tính từ đúng danh sách giao dịch hiệu lực + cờ Category. Không đụng số dư.
- Total Assets ≠ "Thu − Chi": vẫn do Financial Engine quyết. Nhãn "Số dư còn lại" trên Home dễ gây nhầm (đang là Available của từng người); đề xuất đổi wording thành "Tiền đang có" — chỉ nhãn.

## 3. Thay đổi schema cần duyệt (nhỏ nhất có thể)
Thêm **1 cột nullable** `group_key TEXT NULL` vào `category_rows` (schema 6 → 7, `ALTER TABLE ADD COLUMN`, Drift `addColumn`):
- Giá trị hợp lệ: `business_expense` (Chi phí kinh doanh) hoặc `hidden_system` (danh mục thuộc tính năng nâng cao: Cho vay, Đi vay, Trả nợ, Lãi cho vay, Hoàn tiền/Thu hồi). `NULL` = mặc định (Chi tiêu / Doanh thu / Khoản thu khác theo `excludeFromTotals`).
- Migration dữ liệu duy nhất: gán `hidden_system` cho các id hệ thống đã biết; danh mục người dùng tạo KHÔNG bị đổi. Không viết lại giao dịch.
- Không đổi `Transaction`, engine, ledger, Golden.
- Bản seed mới (DB mới) ghi sẵn nhóm; DB cũ nhận qua migration + người dùng tự đổi nhóm cho 2 danh mục kinh doanh đã tạo.

## 4. Phạm vi triển khai đề xuất (sau khi được duyệt)
Domain/report: `computeGroupedTotals` (Doanh thu, Khoản thu khác, Chi tiêu, Chi phí kinh doanh, Thu nhập ròng = Doanh thu − Chi phí kinh doanh, Dòng tiền = Doanh thu + Khoản thu khác − Chi tiêu − Chi phí kinh doanh) + 17 test theo ma trận của brief.
Presentation: Thêm giao dịch (Thu/Chi có bước "Nhóm" 2 lựa chọn + danh mục con lọc theo nhóm; Chuyển chỉ Từ/Đến), màn Danh mục 2 tầng (4 nhóm cố định, chỉ thêm/sửa/ngừng danh mục con, đổi nhóm cho danh mục Chi), ẩn Vay & Cho vay / Hoàn tiền-Thu hồi khỏi Home/Chi tiết giao dịch/pickers (giữ engine, lịch sử vẫn hiển thị), Summary/Home hiển thị 5 số mới gọn, lịch sử giao dịch dùng "Nhóm · Danh mục".

## 5. Điểm giữ nguyên / không làm
Savings, Firebase, Phase 8.9, import Excel, xoá engine Recovery/Loans, parse Note, >2 tầng category, R5/R6, F14/F27/F22.
