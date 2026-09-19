/// Chuẩn hoá chuỗi CHỈ để so khớp khi tìm kiếm (Explorer tìm Ghi chú): không
/// phân biệt hoa/thường, không phân biệt dấu tiếng Việt, gộp khoảng trắng.
/// Không parse/diễn giải nội dung — chỉ là công cụ truy xuất văn bản.
///
/// Dart không có Unicode normalization sẵn, nên dùng bảng ký tự tường minh
/// (đủ cho tiếng Việt: a/e/i/o/u/y có dấu, ă â ê ô ơ ư, đ) và bỏ luôn các dấu
/// kết hợp (U+0300–U+036F) để chuỗi gõ kiểu "a" + dấu rời cũng khớp.
String foldForSearch(String input) {
  final lower = input.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    if (rune >= 0x0300 && rune <= 0x036F) continue; // dấu kết hợp
    final ch = String.fromCharCode(rune);
    out.write(_fold[ch] ?? ch);
  }
  return out.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// [text] có chứa [query] theo nghĩa của [foldForSearch] không. Query rỗng
/// (sau chuẩn hoá) = khớp tất cả.
bool matchesSearch(String text, String query) {
  final q = foldForSearch(query);
  if (q.isEmpty) return true;
  return foldForSearch(text).contains(q);
}

const _groups = <String, String>{
  'a': 'àáảãạăằắẳẵặâầấẩẫậ',
  'e': 'èéẻẽẹêềếểễệ',
  'i': 'ìíỉĩị',
  'o': 'òóỏõọôồốổỗộơờớởỡợ',
  'u': 'ùúủũụưừứửữự',
  'y': 'ỳýỷỹỵ',
  'd': 'đ',
};

final Map<String, String> _fold = {
  for (final e in _groups.entries)
    for (final rune in e.value.runes) String.fromCharCode(rune): e.key,
};
