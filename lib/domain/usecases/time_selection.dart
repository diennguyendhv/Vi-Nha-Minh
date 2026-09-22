/// Kiểu chọn thời gian của Summary / Transaction Explorer.
enum TimeKind { day, month, year }

/// Lựa chọn thời gian: 1 ngày, 1 tháng hoặc 1 năm. Chỉ là cách
/// người dùng CHỌN; bộ lọc chỉ cần [from]/[to]. Ngày so theo ngày lịch địa
/// phương (không có múi giờ/giờ phút).
///
/// Bấm chọn 1 kiểu (Ngày / Tháng / Năm) luôn về KỲ HIỆN TẠI (hôm nay / tháng
/// này / năm nay) — xem [TimeSelection.current]; mũi tên lùi/tiến ([shift]) mới
/// dịch sang kỳ khác.
class TimeSelection {
  const TimeSelection._(this.kind, this.anchor);

  final TimeKind kind;

  /// Ngày làm mốc cho day/month/year (month/year chỉ dùng tháng/năm của nó).
  final DateTime anchor;

  static DateTime _d(DateTime v) => DateTime(v.year, v.month, v.day);

  factory TimeSelection.day(DateTime date) =>
      TimeSelection._(TimeKind.day, _d(date));

  factory TimeSelection.month(DateTime date) =>
      TimeSelection._(TimeKind.month, DateTime(date.year, date.month));

  factory TimeSelection.year(DateTime date) =>
      TimeSelection._(TimeKind.year, DateTime(date.year));

  /// Kỳ HIỆN TẠI của [kind] tính từ [today]. Mọi lựa chọn đều có khoảng ngày
  /// hữu hạn để Explorer không bao giờ tải lịch sử không giới hạn.
  factory TimeSelection.current(TimeKind kind, DateTime today) {
    switch (kind) {
      case TimeKind.day:
        return TimeSelection.day(today);
      case TimeKind.month:
        return TimeSelection.month(today);
      case TimeKind.year:
        return TimeSelection.year(today);
    }
  }

  /// Ngày đầu (bao gồm).
  DateTime get from {
    switch (kind) {
      case TimeKind.day:
        return anchor;
      case TimeKind.month:
        return DateTime(anchor.year, anchor.month);
      case TimeKind.year:
        return DateTime(anchor.year);
    }
  }

  /// Ngày cuối (bao gồm).
  DateTime get to {
    switch (kind) {
      case TimeKind.day:
        return anchor;
      case TimeKind.month:
        return DateTime(anchor.year, anchor.month + 1, 0);
      case TimeKind.year:
        return DateTime(anchor.year, 12, 31);
    }
  }

  /// Lùi/tiến 1 đơn vị (ngày/tháng/năm).
  TimeSelection shift(int step) {
    switch (kind) {
      case TimeKind.day:
        return TimeSelection.day(
          DateTime(anchor.year, anchor.month, anchor.day + step),
        );
      case TimeKind.month:
        return TimeSelection.month(DateTime(anchor.year, anchor.month + step));
      case TimeKind.year:
        return TimeSelection.year(DateTime(anchor.year + step));
    }
  }

  @override
  bool operator ==(Object other) =>
      other is TimeSelection &&
      other.kind == kind &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(kind, from, to);
}
