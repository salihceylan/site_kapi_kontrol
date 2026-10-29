// Acil durum akışı modelleri ve içeriği (lib/models/emergency_models.dart): adres satırı DOĞRU siteden kurulur, senaryo içeriği sabittir,
// kopyalanabilir metin (kuru mod) numara + adres taşır ve HİÇBİR yerde "arandı" demez.
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/audit_log.dart';
import 'package:site_kapi_kontrol/models/emergency_models.dart';

EmergencySite _site({
  int code = 11,
  String name = 'Gül Sitesi',
  String? address = 'Atatürk Mah. 12. Sok. No: 5',
  String? city = 'İstanbul',
  String? district = 'Kadıköy',
  String? firmName,
  String? firmPhone,
  bool canEdit = false,
}) => EmergencySite(
  siteCode: code,
  siteName: name,
  address: address,
  city: city,
  district: district,
  elevatorFirmName: firmName,
  elevatorFirmPhone: firmPhone,
  canEdit: canEdit,
);

void main() {
  group('EmergencySite.fromJson', () {
    test('sunucu alanları okunur; boşluk-yalnız metin null olur; eksik alanlar güvenli varsayılan', () {
      final site = EmergencySite.fromJson(<String, dynamic>{
        'site_code': 1000000001,
        'site_name': ' Gül Sitesi ',
        'address': 'Atatürk Mah. 12. Sok. No: 5',
        'city': 'İstanbul',
        'district': '   ',
        'elevator_firm_name': 'Yıldız Asansör',
        'elevator_firm_phone': '+905321234567',
        'can_edit': true,
      });
      expect(site.siteCode, 1000000001);
      expect(site.siteName, 'Gül Sitesi');
      expect(site.district, isNull);
      expect(site.canEdit, isTrue);
      expect(site.hasElevatorFirm, isTrue);
      final empty = EmergencySite.fromJson(<String, dynamic>{});
      expect(empty.siteCode, 0);
      expect(empty.label, 'İsimsiz site');
      expect(empty.canEdit, isFalse);
      expect(empty.hasElevatorFirm, isFalse);
      expect(empty.addressLine, isNull);
    });

    test('canEdit yalnız true değerinde açılır (metin "true" yetki vermez)', () {
      expect(EmergencySite.fromJson(<String, dynamic>{'can_edit': 'true'}).canEdit, isFalse);
      expect(EmergencySite.fromJson(<String, dynamic>{'can_edit': 1}).canEdit, isFalse);
    });
  });

  group('adres satırı', () {
    test('adres + ilçe / il', () {
      expect(_site().addressLine, 'Atatürk Mah. 12. Sok. No: 5, Kadıköy / İstanbul');
      expect(_site().hasAddress, isTrue);
    });

    test('adres ilçeyi ve ili zaten içeriyorsa yinelenmez (İ/ı katlaması dahil)', () {
      expect(_site(address: 'Atatürk Mah. 12. Sok. No: 5 Kadıköy/İstanbul').addressLine, 'Atatürk Mah. 12. Sok. No: 5 Kadıköy/İstanbul');
      expect(_site(address: 'Atatürk Mah. Kadıköy İSTANBUL').addressLine, 'Atatürk Mah. Kadıköy İSTANBUL');
      // İlçe adresin içinde ama il yoksa yer bilgisi eklenir.
      expect(_site(address: 'Atatürk Mah. Kadıköy').addressLine, 'Atatürk Mah. Kadıköy, Kadıköy / İstanbul');
    });

    test('yalnız il ya da yalnız ilçe; adres yoksa yalnız yer; hiçbiri yoksa null', () {
      expect(_site(address: null, district: null).addressLine, 'İstanbul');
      expect(_site(address: null, city: null).addressLine, 'Kadıköy');
      expect(_site(address: null).addressLine, 'Kadıköy / İstanbul');
      expect(_site(address: null, city: null, district: null).addressLine, isNull);
      expect(_site(address: null, city: null, district: null).hasAddress, isFalse);
    });

    test('çok satırlı adres virgülle birleşir', () {
      expect(_site(address: 'Atatürk Mah.\r\n12. Sok.\n\nNo: 5').addressLine, 'Atatürk Mah., 12. Sok., No: 5, Kadıköy / İstanbul');
    });

    test('her site KENDİ adresini üretir (iki site karışmaz)', () {
      final a = _site(code: 1, name: 'Gül Sitesi');
      final b = _site(code: 2, name: 'Lale Sitesi', address: 'Cumhuriyet Mah. 3. Cad. No: 9', city: 'Ankara', district: 'Çankaya');
      expect(a.addressLine, isNot(b.addressLine));
      expect(b.addressLine, 'Cumhuriyet Mah. 3. Cad. No: 9, Çankaya / Ankara');
      expect(emergencySayLines(b), (siteName: 'Lale Sitesi', address: 'Cumhuriyet Mah. 3. Cad. No: 9, Çankaya / Ankara'));
      expect(emergencySayLines(null), (siteName: null, address: null));
    });
  });

  group('aranabilir numara', () {
    test('emergencyDialable: boşluk, tire ve parantez atılır; baştaki + korunur; 3 haneden azı null', () {
      expect(emergencyDialable('+90 212 555 12 34'), '+902125551234');
      expect(emergencyDialable('0212 555 12 34'), '02125551234');
      expect(emergencyDialable('444 1 234'), '4441234');
      expect(emergencyDialable('(0212) 555-12-34'), '02125551234');
      expect(emergencyDialable('112'), '112');
      expect(emergencyDialable('11'), isNull);
      expect(emergencyDialable(''), isNull);
      expect(emergencyDialable(null), isNull);
      expect(emergencyDialable('abc'), isNull);
    });

    test('bakım firması: telefonu aranabilirse var; yalnız ad varsa yok', () {
      expect(_site(firmPhone: '0212 555 12 34').hasElevatorFirm, isTrue);
      expect(_site(firmName: 'Yıldız Asansör').hasElevatorFirm, isFalse);
      expect(_site(firmPhone: '12').hasElevatorFirm, isFalse);
      expect(_site(firmName: 'Yıldız Asansör', firmPhone: '0212 555 12 34').elevatorFirmLabel, 'Yıldız Asansör');
      expect(_site(firmPhone: '0212 555 12 34').elevatorFirmLabel, 'Asansör bakım firması');
    });

    test('withElevatorFirm yalnız firma alanlarını değiştirir (adres, ad, yetki korunur); boş değer temizler', () {
      final base = _site(firmName: 'Eski', firmPhone: '111', canEdit: true);
      final next = base.withElevatorFirm(name: ' Yıldız ', phone: ' 0212 555 12 34 ');
      expect(next.elevatorFirmName, 'Yıldız');
      expect(next.elevatorFirmPhone, '0212 555 12 34');
      expect(next.addressLine, base.addressLine);
      expect(next.siteName, base.siteName);
      expect(next.canEdit, isTrue);
      final cleared = base.withElevatorFirm();
      expect(cleared.elevatorFirmName, isNull);
      expect(cleared.hasElevatorFirm, isFalse);
      expect(base == base.withElevatorFirm(name: 'Eski', phone: '111'), isTrue);
      expect(base == next, isFalse);
    });
  });

  group('senaryo içeriği', () {
    test('112 sabittir', () => expect(kEmergencyNumber, '112'));

    test('her senaryoda adres sorusu, iletişim sorusu ve ilk söylenecek cümle vardır', () {
      for (final scenario in EmergencyScenario.values) {
        final guide = emergencyGuideOf(scenario);
        expect(guide.scenario, scenario);
        expect(guide.questions.length, greaterThanOrEqualTo(4), reason: scenario.name);
        expect(guide.questions.any((q) => q.startsWith('Adres:')), isTrue, reason: scenario.name);
        expect(guide.questions.any((q) => q.contains('telefon numarası')), isTrue, reason: scenario.name);
        expect(guide.sayLine, isNotEmpty, reason: scenario.name);
        expect(guide.scriptTitle, startsWith('ACİL DURUM'), reason: scenario.name);
      }
    });

    test('yangın: asansör kullanılmaz, 112; asansör: alarm düğmesi, kapı zorlanmaz, tehlikede 112', () {
      final fire = emergencyGuideOf(EmergencyScenario.fire);
      expect(fire.steps.join(' '), contains('asansör kullanmayın'));
      expect(fire.steps.join(' '), contains('112'));
      expect(fire.sayLine, 'Yangın var.');
      expect(fire.questions.first, contains('Yangın nerede'));
      final elevator = emergencyGuideOf(EmergencyScenario.elevator);
      expect(elevator.steps.join(' '), contains('kapıyı zorlamayın'));
      expect(elevator.steps.join(' '), contains('112'));
      expect(elevator.summary, contains('bakım firmasına'));
      expect(elevator.questions.first, contains('Hangi blok'));
    });

    test('hiçbir içerik metni "arandı / aranıyor / arama yapıldı" demez (dürüst kuru mod)', () {
      final pattern = RegExp('arandı|aranıyor|arama yapıldı|çağrı yapıldı', caseSensitive: false);
      for (final scenario in EmergencyScenario.values) {
        final guide = emergencyGuideOf(scenario);
        final all = [guide.title, guide.summary, guide.sayLine, ...guide.steps, ...guide.questions].join('\n');
        expect(pattern.hasMatch(all), isFalse, reason: scenario.name);
      }
    });
  });

  group('kopyalanabilir metin (kuru mod)', () {
    test('genel: numara, söylenecek cümle, site adı, adres ve sorular', () {
      final text = buildEmergencyScript(EmergencyScenario.general, _site());
      expect(text, startsWith('ACİL DURUM - 112\n'));
      expect(text, contains('Aranacak numara: 112'));
      expect(text, contains('Söyleyin: Acil bir durum var.'));
      expect(text, contains('Site: Gül Sitesi'));
      expect(text, contains('Adres: Atatürk Mah. 12. Sok. No: 5, Kadıköy / İstanbul'));
      expect(text, contains('Sorulabilecekler:'));
      expect(text, contains('1. Ne oldu?'));
    });

    test('yangın: 112 + "Yangın var." + DOĞRU sitenin adresi', () {
      final other = _site(code: 2, name: 'Lale Sitesi', address: 'Cumhuriyet Mah. 3. Cad. No: 9', city: 'Ankara', district: 'Çankaya');
      final text = buildEmergencyScript(EmergencyScenario.fire, other);
      expect(text, startsWith('ACİL DURUM - YANGIN\n'));
      expect(text, contains('Aranacak numara: 112'));
      expect(text, contains('Söyleyin: Yangın var.'));
      expect(text, contains('Site: Lale Sitesi'));
      expect(text, contains('Cumhuriyet Mah. 3. Cad. No: 9, Çankaya / Ankara'));
      expect(text, isNot(contains('Atatürk Mah.')));
      expect(text, isNot(contains('Gül Sitesi')));
    });

    test('asansör + bakım firması: firma adı ve telefonu, tehlikede 112', () {
      final text = buildEmergencyScript(
        EmergencyScenario.elevator,
        _site(firmName: 'Yıldız Asansör', firmPhone: '0212 555 12 34'),
      );
      expect(text, startsWith('ACİL DURUM - ASANSÖR ARIZASI\n'));
      expect(text, contains('Asansör bakım firması: Yıldız Asansör, 0212 555 12 34'));
      expect(text, contains('Mahsur kalan kişide tehlike varsa: 112'));
      expect(text, contains('Söyleyin: Asansör arızası var.'));
    });

    test('asansör, firma kayıtlı değil: dürüstçe söyler ve yönetimden istenir; yine de 112 verilir', () {
      final text = buildEmergencyScript(EmergencyScenario.elevator, _site());
      expect(text, contains('Asansör bakım firması: kayıtlı değil (site yönetiminden isteyin)'));
      expect(text, contains('Mahsur kalan kişide tehlike varsa: 112'));
      // Yalnız ad var, telefon yok: aranabilir firma sayılmaz.
      expect(buildEmergencyScript(EmergencyScenario.elevator, _site(firmName: 'Yıldız Asansör')), contains('kayıtlı değil'));
    });

    test('site yok / adres kayıtlı değil: adres uydurulmaz', () {
      final noSite = buildEmergencyScript(EmergencyScenario.fire, null);
      expect(noSite, contains('Adres: kayıtlı değil, adresi kendiniz söyleyin'));
      expect(noSite, isNot(contains('Site:')));
      final noAddress = buildEmergencyScript(
        EmergencyScenario.fire,
        _site(address: null, city: null, district: null),
      );
      expect(noAddress, contains('Site: Gül Sitesi'));
      expect(noAddress, contains('Adres: kayıtlı değil, adresi kendiniz söyleyin'));
    });

    test('hiçbir senaryo metni "arandı" demez', () {
      final pattern = RegExp('arandı|aranıyor|arama yapıldı|çağrı yapıldı', caseSensitive: false);
      for (final scenario in EmergencyScenario.values) {
        for (final site in <EmergencySite?>[null, _site(), _site(firmName: 'Yıldız', firmPhone: '0212 555 12 34')]) {
          expect(pattern.hasMatch(buildEmergencyScript(scenario, site)), isFalse, reason: '${scenario.name} $site');
        }
      }
    });
  });

  test('denetim kaydı etiketi: bilinen eylem Türkçe, bilinmeyen null; denetim satırı etiketi kullanır', () {
    expect(emergencyActionLabel('emergency.info_updated'), 'Acil durum bilgisi güncellendi');
    expect(emergencyActionLabel('emergency.baska'), isNull);
    expect(const AuditLogEntry(id: 1, action: 'emergency.info_updated').actionLabel, 'Acil durum bilgisi güncellendi');
    expect(const AuditLogEntry(id: 2, action: 'emergency.baska').actionLabel, 'Diğer işlem');
  });
}
