/// Cách một hạng mục ảnh hưởng tới số dư của người ghi giao dịch.
///
/// Khớp với 9 hạng mục thật trong sheet "Quản lý tài chính 2026": income
/// (Thu nhập) cộng vào số dư; expense (Sinh hoạt, Đầu tư, Tự thưởng, Cho đi,
/// Dâng hiến) trừ khỏi số dư; savings (Tiết kiệm) trừ khỏi số dư và cộng vào
/// quỹ tiết kiệm riêng (số âm = rút tiết kiệm); transfer (Chồng đưa vợ, Vợ
/// đưa chồng) chuyển tiền giữa hai người, không đổi tổng quỹ gia đình.
enum CategoryKind { income, expense, savings, transfer }
