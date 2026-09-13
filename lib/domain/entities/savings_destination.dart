/// Sheet gốc chưa tách khoản Tiết kiệm — đây là phần mở rộng theo yêu cầu:
/// mỗi giao dịch Tiết kiệm ghi rõ tiền đang là tiền mặt hay đã gửi ngân hàng.
enum SavingsDestination {
  onHand('Hiện tại'),
  bank('Đã gửi ngân hàng');

  const SavingsDestination(this.label);

  final String label;
}
