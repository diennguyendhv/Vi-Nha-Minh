import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tính năng NÂNG CAO (Vay & Cho vay, Hoàn tiền / Thu hồi) — engine, schema và
/// lịch sử giữ nguyên, nhưng điểm vào UI mặc định bị ẩn để người dùng phổ
/// thông không phải hiểu chúng (SIMPLE BY DEFAULT). Giao dịch cũ thuộc các
/// tính năng này vẫn hiển thị đầy đủ trong lịch sử/chi tiết.
///
/// Mặc định `false`; bật lại sau này chỉ cần override provider này (hoặc nối
/// với 1 công tắc trong Cài đặt) — không cần sửa engine.
final advancedFeaturesEnabledProvider = Provider<bool>((ref) => false);
