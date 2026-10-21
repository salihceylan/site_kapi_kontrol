import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/equipment_api.dart';

void main() {
  test('formatKurus ve parseKurus tamsayı kuruş ile çalışır', () {
    expect(formatKurus(123450), '1.234,50 TL');
    expect(formatKurus(5), '0,05 TL');
    expect(formatKurus(-100), '-1,00 TL');
    expect(parseKurus('1.250,5'), 125050);
    expect(parseKurus('12'), 1200);
    expect(parseKurus('1,234'), isNull);
    expect(parseKurus('abc'), isNull);
  });

  test('varsayılan türler ve yıllık yasal kontrol', () {
    expect(equipmentKinds.length, 9);
    expect(equipmentKinds.firstWhere((k) => k.code == 'asansor').legalMonths, 12);
    expect(equipmentKindLabel('hidrofor'), 'Hidrofor');
    expect(equipmentKindLabel('ozel'), 'ozel');
    expect(intervalLabel(12), 'Yılda bir');
    expect(intervalLabel(3), '3 ayda bir');
  });

  test('teklif ve plan JSON eşlemesi', () {
    final q = EquipmentQuote.fromJson(<String, dynamic>{
      'id': 4,
      'topic': 'Asansör bakımı',
      'vendor_name': 'Yıldız',
      'amount_kurus': 250000,
      'status': 'open',
      'lowest': true,
      'expired': false,
    });
    expect(q.amountKurus, 250000);
    expect(q.lowest, isTrue);
    final p = MaintenancePlan.fromJson(<String, dynamic>{'id': 1, 'title': 'Yıllık', 'interval_months': 12, 'legal': true, 'next_due': '2026-12-01', 'days_left': -3});
    expect(p.legal, isTrue);
    expect(p.daysLeft, -3);
  });
}
