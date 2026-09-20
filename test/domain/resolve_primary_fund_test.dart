import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_nha_minh/core/constants/default_funds.dart';
import 'package:vi_nha_minh/domain/entities/fund.dart';
import 'package:vi_nha_minh/domain/usecases/resolve_primary_fund.dart';

Fund _fund(String id, {bool active = true}) =>
    Fund(id: id, name: 'Quỹ $id', color: Colors.blue, isActive: active);

void main() {
  test('Quỹ chính = quỹ đang dùng có đúng id; tên thật của quỹ, không gắn cứng', () {
    final funds = [_fund('an_uong'), _fund('du_lich')];
    expect(resolvePrimaryFund(funds, 'du_lich')?.name, 'Quỹ du_lich');
    expect(resolvePrimaryFund(funds, DefaultFunds.anUongId)?.id, 'an_uong');
  });

  test('Chưa chọn (null) / id không tồn tại (đã xóa) / đã ngừng → null, KHÔNG tự chọn quỹ khác', () {
    final funds = [_fund('a'), _fund('b', active: false)];
    expect(resolvePrimaryFund(funds, null), isNull);
    expect(resolvePrimaryFund(funds, 'da_xoa'), isNull);
    expect(resolvePrimaryFund(funds, 'b'), isNull);
    expect(resolvePrimaryFund(const [], DefaultFunds.anUongId), isNull);
  });
}
