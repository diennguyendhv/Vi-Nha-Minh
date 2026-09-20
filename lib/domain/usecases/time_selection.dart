/// Kiểu chọn thời gian của Summary / Transaction Explorer.
enum TimeKind { day, month, year, all }

/// Lựa chọn thời gian: 1 ngày, 1 tháng, 1 năm hoặc mọi thời gian. Chỉ là cách
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

  factory TimeSelection.day(DateTime date) => TimeSelection._(TimeKind.day, _d(date));

  factory TimeSelection.month(DateTime date) =>
      TimeSelection._(TimeKind.month, DateTime(date.year, date.month));

  factory TimeSelection.year(DateTime date) =>
      TimeSelection._(TimeKind.year, DateTime(date.year));

  factory TimeSelection.all(DateTime today) => TimeSelection._(TimeKind.all, _d(today));

  /// Kỳ HIỆN TẠI của [kind] tính từ [today]: Ngày → hôm nay, Tháng → tháng này,
  /// Năm → năm nay, Tất cả → không giới hạn.
  factory TimeSelection.current(TimeKind kind, DateTime today) {
    switch (kind) {
      case TimeKind.day:
        return TimeSelection.day(today);
      case TimeKind.month:
        return TimeSelection.month(today);
      case TimeKind.year:
        return TimeSelection.year(today);
      case TimeKind.all:
        return TimeSelection.all(today);
    }
  }

  /// Ngày đầu (bao gồm) — `null` khi [TimeKind.all].
  DateTime? get from {
    switch (kind) {
      case TimeKind.day:
        return anchor;
      case TimeKind.month:
        return DateTime(anchor.year, anchor.month);
      case TimeKind.year:
        return DateTime(anchor.year);
      case TimeKind.all:
        return null;
    }
  }

  /// Ngày cuối (bao gồm) — `null` khi [TimeKind.all].
  DateTime? get to {
    switch (kind) {
      case TimeKind.day:
        return anchor;
      case TimeKind.month:
        return DateTime(anchor.year, anchor.month + 1, 0);
      case TimeKind.year:
        return DateTime(anchor.year, 12, 31);
      case TimeKind.all:
        return null;
    }
  }

  /// Lùi/tiến 1 đơn vị (ngày/tháng/năm). "Tất cả" không dịch.
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
      case TimeKind.all:
        return this;
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
