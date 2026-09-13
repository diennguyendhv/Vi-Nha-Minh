/// Trạng thái đồng bộ của gia đình hiện tại — mọi gia đình mới luôn bắt đầu
/// ở `local`; chỉ chuyển sang `cloud` khi người thứ 2 thật sự chấp nhận lời
/// mời (Giai đoạn B, phase 27: migrate dữ liệu local → Firestore).
enum SyncMode { local, cloud }
