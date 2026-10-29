// Belge metni ayrıştırıcısı (P2-13): TR biçimli tutar / tarih / IBAN adayları ve yanlış pozitifler. Saf Dart; ML Kit ve ağ yok.
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/document_text_parser.dart';

// Sınama IBAN'ları (mod 97 geçerli, gerçek hesap değil).
const String _ibanA = 'TR330006100519786457841326';
const String _ibanB = 'TR360001000123456789012345';

const String _dekont = '''
T. İŞ BANKASI
İşlem Tarihi: 15.10.2026 14:32
Gönderen: AHMET YILMAZ
Gönderen IBAN: TR33 0006 1005 1978 6457 8413 26
Alıcı: GÜL SİTESİ YÖNETİMİ
Alıcı IBAN: TR36 0001 0001 2345 6789 0123 45
Tutar: 1.250,50 TL
Komisyon: 2,50 TL
Bakiye: 5.000,00 TL
''';

List<int> _minors(DocumentSuggestions s) => [for (final a in s.amounts) a.minor];

void main() {
  group('tutar', () {
    test('dekontta etiketli tutar başta; komisyon ve bakiye geride', () {
      final s = parseDocumentText(_dekont);
      expect(_minors(s), <int>[125050, 500000, 250]);
    });

    test('TR biçimleri: binlik nokta, düz tamsayı, ₺ ve TL işareti', () {
      expect(_minors(parseDocumentText('Tutar 1.234,56')), <int>[123456]);
      expect(_minors(parseDocumentText('Toplam: ₺12.345,00')), <int>[1234500]);
      expect(_minors(parseDocumentText('Ödenen 980,5 TL ve 7500,00 TL')), <int>[750000]);
    });

    test('yanlış pozitifler: yüzde, sıfır, bozuk gruplama, tarih ve tek haneli kuruş', () {
      expect(parseDocumentText('KDV %18,00').amounts, isEmpty);
      expect(parseDocumentText('KDV 18,00 %').amounts, isEmpty);
      expect(parseDocumentText('Tutar 0,00 TL').amounts, isEmpty);
      expect(parseDocumentText('Tutar 1.23,45').amounts, isEmpty);
      expect(parseDocumentText('Tutar 250,5').amounts, isEmpty);
      expect(parseDocumentText('Tarih 05,10,2026').amounts, isEmpty);
      expect(parseDocumentText('Tel 0212 555 12 34 No 4471').amounts, isEmpty);
    });

    test('etiket bir önceki satırda kalsa da tutar öne çıkar; aynı tutar bir kez gelir', () {
      final s = parseDocumentText('Genel Toplam\n3.400,00\nKDV\n20,00\n3.400,00 TL');
      expect(_minors(s), <int>[340000, 2000]);
    });
  });

  group('tarih', () {
    test('işlem tarihi başta; vade tarihi geride', () {
      final s = parseDocumentText('Vade Tarihi: 30.10.2026\nİşlem Tarihi: 15.10.2026 09:05');
      expect(s.dates, <DateTime>[DateTime(2026, 10, 15), DateTime(2026, 10, 30)]);
    });

    test('farklı yazımlar aynı tarihi verir', () {
      expect(parseDocumentText('15/10/2026').dates, <DateTime>[DateTime(2026, 10, 15)]);
      expect(parseDocumentText('5.3.2026').dates, <DateTime>[DateTime(2026, 3, 5)]);
      expect(parseDocumentText('2026-10-15T08:00').dates, <DateTime>[DateTime(2026, 10, 15)]);
      expect(parseDocumentText('15 EKİM 2026').dates, <DateTime>[DateTime(2026, 10, 15)]);
      expect(parseDocumentText('3 Şubat 2026').dates, <DateTime>[DateTime(2026, 2, 3)]);
    });

    test('yanlış pozitifler: gerçek olmayan tarih, eski yıl, sürüm numarası', () {
      expect(parseDocumentText('31.02.2026').dates, isEmpty);
      expect(parseDocumentText('15.13.2026').dates, isEmpty);
      expect(parseDocumentText('01.01.1999').dates, isEmpty);
      expect(parseDocumentText('Sürüm 1.2.3').dates, isEmpty);
      expect(parseDocumentText('IP 10.20.30.40').dates, isEmpty);
    });

    test('formun kabul ettiği aralık dışındaki tarihler elenir', () {
      final s = parseDocumentText('Tarih 15.10.2026 ve 30.11.2026', notBefore: DateTime(2025, 10, 21), notAfter: DateTime(2026, 10, 21));
      expect(s.dates, <DateTime>[DateTime(2026, 10, 15)]);
    });
  });

  group('IBAN', () {
    test('gönderen ve alıcı rolü etiketten tahmin edilir', () {
      final s = parseDocumentText(_dekont);
      expect([for (final i in s.ibans) i.iban], <String>[_ibanA, _ibanB]);
      expect([for (final i in s.ibans) i.role], <IbanRole>[IbanRole.sender, IbanRole.receiver]);
    });

    test('boşluksuz, küçük harfli ve OCR karışıklıklı (O/I) IBAN kabul edilir', () {
      expect(parseDocumentText('iban $_ibanA').ibans.single.iban, _ibanA);
      expect(parseDocumentText('IBAN: tr33 0006 1005 1978 6457 8413 26').ibans.single.iban, _ibanA);
      expect(parseDocumentText('IBAN: TR33 OOO6 1O05 1978 6457 8413 26').ibans.single.iban, _ibanA);
      expect(parseDocumentText('IBAN: $_ibanA\nIBAN: TR33 0006 1005 1978 6457 8413 26').ibans.length, 1);
    });

    test('yanlış pozitifler: hane denetimi tutmayan, uzun ya da kısa dizi', () {
      expect(parseDocumentText('IBAN: TR34 0006 1005 1978 6457 8413 26').ibans, isEmpty);
      expect(parseDocumentText('IBAN: TR33 0006 1005 1978 6457 8413 261').ibans, isEmpty);
      expect(parseDocumentText('IBAN: TR33 0006 1005 1978 6457 8413').ibans, isEmpty);
      expect(parseDocumentText('Sipariş TR1234 ve ABC330006100519786457841326').ibans, isEmpty);
    });
  });

  test('boş ve anlamsız metin öneri üretmez', () {
    expect(parseDocumentText('').isEmpty, isTrue);
    expect(parseDocumentText('Teşekkür ederiz, iyi günler.').isEmpty, isTrue);
  });

  test('foldTurkish uzunluğu korur ve Türkçe harfleri indirger', () {
    const text = 'İŞLEM TARİHİ ığüşöç';
    final folded = foldTurkish(text);
    expect(folded, 'islem tarihi igusoc');
    expect(folded.length, text.length);
  });
}
