import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vi_nha_minh/presentation/providers/primary_fund_provider.dart';

Future<PrimaryFundController> _boot(Map<String, Object> stored) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  return createPersistentPrimaryFundController(prefs);
}

void main() {
  test('A — cài mới: quỹ chính mặc định = an_uong', () async {
    expect((await _boot({})).state, 'an_uong');
    expect(ProviderContainer().read(primaryFundIdProvider), 'an_uong');
  });

  test('I — chọn quỹ khác → khởi động lại app vẫn nhớ', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await createPersistentPrimaryFundController(prefs).select('du_lich');

    // "Force-stop/mở lại": dựng controller mới từ cùng nơi lưu.
    expect(createPersistentPrimaryFundController(prefs).state, 'du_lich');
  });

  test('E/J — xóa quỹ chính → bỏ chọn và nhớ; KHÔNG tự sống lại an_uong sau khi mở lại', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = createPersistentPrimaryFundController(prefs);
    expect(c.state, 'an_uong');

    await c.clearIfPrimary('an_uong');
    expect(c.state, isNull);
    expect(createPersistentPrimaryFundController(prefs).state, isNull,
        reason: 'giá trị rỗng = chủ động không có quỹ chính, khác với "chưa từng lưu"');
  });

  test('D — xóa quỹ KHÔNG phải quỹ chính: quỹ chính giữ nguyên', () async {
    final c = await _boot({});
    await c.select('du_lich');
    await c.clearIfPrimary('quy_khac');
    expect(c.state, 'du_lich');
  });

  test('G/H — sau khi bỏ chọn, chọn lại một quỹ (có sẵn hoặc vừa tạo) cập nhật ngay và bền vững', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = createPersistentPrimaryFundController(prefs);
    await c.clearIfPrimary('an_uong');
    await c.select('quy_moi');
    expect(c.state, 'quy_moi');
    expect(createPersistentPrimaryFundController(prefs).state, 'quy_moi');
  });
}
