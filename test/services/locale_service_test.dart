import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/services/locale_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('varsayilan Turkce, tercih saklanir ve geri yuklenir', () async {
    SharedPreferences.setMockInitialValues({});
    final s = LocaleService();
    await s.load();
    expect(s.locale, const Locale('tr'));
    await s.setLocale(const Locale('en'));
    final s2 = LocaleService();
    await s2.load();
    expect(s2.locale, const Locale('en'));
  });

  test('bozuk deger Turkceye doner', () {
    expect(LocaleService.parse('xx'), const Locale('tr'));
    expect(LocaleService.parse(null), const Locale('tr'));
  });
}
