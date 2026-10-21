import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/views/management_company_view.dart';

void main() {
  test('companyMoney kuruşu binlik ayraçla yazar', () {
    expect(companyMoney(0), '0,00 TL');
    expect(companyMoney(123456), '1.234,56 TL');
    expect(companyMoney(100000000), '1.000.000,00 TL');
    expect(companyMoney(-50), '-0,50 TL');
  });

  test('companyRate baz puanı yüzde yazar; oransız site açıklanır', () {
    expect(companyRate(8750), '%87,5');
    expect(companyRate(10000), '%100');
    expect(companyRate(0), '%0');
    expect(companyRate(505), '%5,05');
    expect(companyRate(null), 'Borçlandırma yok');
  });
}
