// Sayaç modülü istemci katmanı: dosya okuyucu (CSV), para/okuma biçimleri, model çözümleme, hata metinleri.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/meter_models.dart';
import 'package:site_kapi_kontrol/services/meter_api.dart';
import 'package:site_kapi_kontrol/services/meter_file_reader.dart';

Uint8List csv(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  group('readMeterFile', () {
    test('başlıklı CSV: sütunlar adlarından bulunur, boş satırlar atlanır', () {
      final read = readMeterFile(csv('Seri no;Okuma\nA-1;12,5\n\nA-2;100\n'), 'okuma.csv');
      expect(read.error, isNull);
      expect(read.rows.map((r) => '${r.code}=${r.value}').toList(), <String>['A-1=12,5', 'A-2=100']);
    });

    test('başlıksız CSV: ilk satır veridir', () {
      final read = readMeterFile(csv('A Blok - 5;10.250\nA Blok - 6;20\n'), 'x.csv');
      expect(read.rows, hasLength(2));
      expect(read.rows.first.code, 'A Blok - 5');
    });

    test('yanlış uzantı, boş dosya ve veri yok düz Türkçe hata verir', () {
      expect(readMeterFile(csv('a;1'), 'x.pdf').error, contains('.xlsx ve .csv'));
      expect(readMeterFile(Uint8List(0), 'x.csv').error, 'Dosya boş.');
      expect(readMeterFile(csv('Daire kodu;Değer\n'), 'x.csv').error, isNotNull);
    });

    test('satır numarası dosyadaki sıradır ve JSON gövdeye girer', () {
      final read = readMeterFile(csv('Kod;Değer\nB1;5\n'), 'x.csv');
      expect(read.rows.single.toJson(), <String, dynamic>{'n': 2, 'code': 'B1', 'value': '5'});
    });
  });

  group('para', () {
    test('formatMinorTl binlik ayraç ve virgül', () {
      expect(formatMinorTl(123456), '1.234,56 ₺');
      expect(formatMinorTl(5), '0,05 ₺');
      expect(formatMinorTl(100000000), '1.000.000,00 ₺');
    });
    test('parseTlToMinor tam kuruş, geçersizde null', () {
      expect(parseTlToMinor('45,5'), 4550);
      expect(parseTlToMinor('45.50'), 4550);
      expect(parseTlToMinor('12'), 1200);
      expect(parseTlToMinor('0'), isNull);
      expect(parseTlToMinor('1,234'), isNull);
      expect(parseTlToMinor('abc'), isNull);
      expect(parseTlToMinor('-3'), isNull);
    });
  });

  group('model', () {
    test('Meter.fromJson son okumayı ve türü çözer', () {
      final meter = Meter.fromJson(<String, dynamic>{
        'id': 3,
        'kind': 'hot_water',
        'serial_no': 'S1',
        'is_active': true,
        'apartment_id': 9,
        'apartment_label': 'A - 1',
        'last_reading': <String, dynamic>{'value': '12.500', 'date': '2026-09-30'},
      });
      expect(meter.kind, MeterKind.hotWater);
      expect(meter.lastValue, '12.500');
      expect(Meter.fromJson(<String, dynamic>{'id': 1}).lastValue, isNull);
    });

    test('BillingPreview.fromJson ve eksik nedenleri', () {
      final preview = BillingPreview.fromJson(<String, dynamic>{
        'total_minor': 10000,
        'apartment_count': 1,
        'zero_count': 0,
        'preview_hash': 'h',
        'can_post': false,
        'params': <String, dynamic>{},
        'lines': <Object>[
          <String, dynamic>{'apartment_id': 1, 'label': 'A - 1', 'consumption': '5.000', 'amount_minor': 10000, 'account_party': 'tenant'},
        ],
        'missing': <Object>[
          <String, dynamic>{'label': 'A - 2', 'reason': 'no_opening'},
        ],
      });
      expect(preview.lines.single.amountMinor, 10000);
      expect(preview.missing.single.reasonText, 'başlangıç okuması yok');
      expect(preview.canPost, isFalse);
      expect(preview.areaBasis, isNull, reason: 'eski sunucu / ısı payı dışı yöntem');
    });

    test('K5 ısı payı alan payı tabanı: seçenekler eşit (varsayılan), arsa payı, kişi sayısı (m² yok); önizleme seçilen tabanı ve eksik veri nedenlerini taşır', () {
      expect(HeatAreaBasis.values.first, HeatAreaBasis.equal, reason: 'varsayılan taban EŞİT');
      expect(HeatAreaBasis.values.map((b) => b.api).toList(), <String>['equal', 'land_share', 'person_count']);
      expect(HeatAreaBasis.values.every((b) => b.label.isNotEmpty && b.help.isNotEmpty), isTrue);
      final preview = BillingPreview.fromJson(<String, dynamic>{
        'total_minor': 600000,
        'apartment_count': 2,
        'zero_count': 0,
        'preview_hash': 'h',
        'can_post': false,
        'area_basis': 'person_count',
        'params': <String, dynamic>{'area_basis': 'person_count'},
        'lines': <Object>[],
        'missing': <Object>[
          <String, dynamic>{'label': 'A - 3', 'reason': 'person_count_missing'},
          <String, dynamic>{'label': 'A - 4', 'reason': 'land_share_missing'},
        ],
      });
      expect(preview.areaBasis, HeatAreaBasis.personCount);
      expect(preview.missing.map((m) => m.reasonText).toList(), <String>['dairede kayıtlı güncel kişi yok', 'arsa payı tanımlı değil']);
      expect(BillingPreview.fromJson(<String, dynamic>{'area_basis': 'area'}).areaBasis, isNull, reason: 'm² tabanı tanınmaz');
    });

    test('içe aktarma satır nedenleri Türkçe', () {
      expect(MeterImportRow.reasonText('METER_NOT_FOUND'), contains('sayaç'));
      expect(MeterImportRow.reasonText('bilinmeyen'), 'Satır okunamadı');
    });
  });

  group('hata metinleri', () {
    test('bilinen kodlar düz Türkçe, bilinmeyen null', () {
      expect(MeterApi.meterErrorMessage('SERIAL_TAKEN'), contains('seri numaralı'));
      expect(MeterApi.meterErrorMessage('BILLING_OVERLAP'), contains('çakışıyor'));
      expect(MeterApi.meterErrorMessage('AREA_BASIS_INCOMPLETE'), contains('alan payı tabanı'));
      expect(MeterApi.meterErrorMessage('AREA_BASIS_UNUSABLE'), contains('dağıtılacak pay yok'));
      expect(MeterApi.meterErrorMessage('BAMBASKA'), isNull);
    });
  });
}
