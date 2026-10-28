// "Dokun-ara" saf mantığı (P2-23, K13): aranabilir numara biçimi, tel: adresi, gösterim biçimi, arama sonucu (başladı / açılamadı /
// geçersiz) ve sunucu yanıtının savunmacı okunması. Widget testleri: test/screens/dokun_ara_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/manager_contact.dart';
import 'package:site_kapi_kontrol/ui/helpers/dial_call.dart';

void main() {
  group('dialableNumber', () {
    test('boşluk, parantez, tire ve nokta atılır; baştaki + korunur', () {
      expect(dialableNumber('0532 123 45 67'), '05321234567');
      expect(dialableNumber('+90 (532) 123-45-67'), '+905321234567');
      expect(dialableNumber('  0212.555.12.34 '), '02125551234');
      expect(dialableNumber('0212/555 12 34'), '02125551234');
    });

    test('kısa hizmet numaraları (112, 185, 444 1 234) aranabilir', () {
      expect(dialableNumber('112'), '112');
      expect(dialableNumber(' 185 '), '185');
      expect(dialableNumber('444 1 234'), '4441234');
    });

    test('harf, *, #, ;, , ve ortadaki + reddedilir (USSD / özel kod / çoklu arama çevrilmez)', () {
      for (final bad in <String?>[
        null,
        '',
        '   ',
        'abc',
        '*123#',
        '#31#05321234567',
        '0532;1234567',
        '0532,1234567',
        '05321x34567',
        '0532 123 + 45 67',
        '11',
        '1234567890123456',
        'tel:112',
      ]) {
        expect(dialableNumber(bad), isNull, reason: '$bad aranabilir sayılmamalı');
      }
    });
  });

  test('telUri: tel şeması ve yol; + işareti yolda kalır', () {
    final plain = telUri('112');
    expect(plain.scheme, 'tel');
    expect(plain.path, '112');
    expect(plain.toString(), 'tel:112');
    expect(telUri('+905321234567').path, '+905321234567');
  });

  test('formatPhoneForDisplay: Türkiye numaraları gruplanır, ötekiler olduğu gibi', () {
    expect(formatPhoneForDisplay('05321234567'), '0532 123 45 67');
    expect(formatPhoneForDisplay('+905321234567'), '+90 532 123 45 67');
    expect(formatPhoneForDisplay('02125551234'), '0212 555 12 34');
    expect(formatPhoneForDisplay('112'), '112');
    expect(formatPhoneForDisplay('4441234'), '4441234');
    expect(formatPhoneForDisplay('+4915112345678'), '+4915112345678');
  });

  group('dialPhone', () {
    test('açılırsa started; launcher tel: adresiyle çağrılır', () async {
      final calls = <Uri>[];
      final outcome = await dialPhone('0532 123 45 67', launcher: (uri) async {
        calls.add(uri);
        return true;
      });
      expect(outcome, DialOutcome.started);
      expect(calls.single.toString(), 'tel:05321234567');
    });

    test('açılamazsa unavailable (kuru mod): hata fırlatmaz', () async {
      expect(await dialPhone('112', launcher: (_) async => false), DialOutcome.unavailable);
    });

    test('geçersiz numarada launcher HİÇ çağrılmaz', () async {
      var called = 0;
      for (final bad in <String?>[null, '', 'abc', '*123#', '12']) {
        expect(
          await dialPhone(bad, launcher: (_) async {
            called++;
            return true;
          }),
          DialOutcome.invalid,
          reason: '$bad',
        );
      }
      expect(called, 0);
    });

    test('acil numara sabiti 112', () {
      expect(kEmergencyNumber, '112');
    });
  });

  group('ManagerContact (sunucu yanıtı)', () {
    test('tam satır okunur', () {
      final list = ManagerContact.listFromJson(<String, dynamic>{
        'sites': <Map<String, dynamic>>[
          <String, dynamic>{
            'site_code': 1000000001,
            'site_name': 'Gül Sitesi',
            'manager_name': 'Ali Yönetici',
            'manager_phone': '05321234567',
            'is_self': false,
          },
        ],
      });
      expect(list, hasLength(1));
      expect(list.single.siteCode, 1000000001);
      expect(list.single.siteName, 'Gül Sitesi');
      expect(list.single.managerName, 'Ali Yönetici');
      expect(list.single.phone, '05321234567');
      expect(list.single.isSelf, isFalse);
    });

    test('telefon yok / boş: phone null (uydurma numara yok); is_self yalnız true ise', () {
      final list = ManagerContact.listFromJson(<String, dynamic>{
        'sites': <Object?>[
          <String, dynamic>{'site_code': 1, 'site_name': 'A', 'manager_phone': null},
          <String, dynamic>{'site_code': 2, 'site_name': 'B', 'manager_phone': '   '},
          <String, dynamic>{'site_code': 3, 'site_name': 'C', 'is_self': 'true'},
          <String, dynamic>{'site_code': 4, 'site_name': 'D', 'is_self': true},
        ],
      });
      expect(list.map((c) => c.phone), everyElement(isNull));
      expect(list.map((c) => c.isSelf), <bool>[false, false, false, true]);
    });

    test('bozuk yanıt çökmez: liste olmayan sites, nesne olmayan satır, eksik ad', () {
      expect(ManagerContact.listFromJson(null), isEmpty);
      expect(ManagerContact.listFromJson(<String, dynamic>{'sites': 'x'}), isEmpty);
      expect(ManagerContact.listFromJson(<String, dynamic>{'sites': <Object?>[1, null, 'a']}), isEmpty);
      final list = ManagerContact.listFromJson(<String, dynamic>{
        'sites': <Object?>[<String, dynamic>{}],
      });
      expect(list.single.siteName, 'Site');
      expect(list.single.siteCode, 0);
      expect(list.single.managerName, isNull);
    });
  });
}
