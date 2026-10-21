// Banka ekstresi: tutar ayrıştırma, MT940, CSV okuyucu ve eşleme (Dalga 2 / 2C). Saf Dart; arayüz yok.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/bank_amount.dart';
import 'package:site_kapi_kontrol/services/bank_statement_reader.dart';
import 'package:site_kapi_kontrol/services/mt940_parser.dart';

void main() {
  group('parseAmountMinor', () {
    test('türkçe ve ingilizce biçimler kuruşu kuruşuna', () {
      expect(parseAmountMinor('1.250,00'), 125000);
      expect(parseAmountMinor('-1.250,00'), -125000);
      expect(parseAmountMinor('1250.00'), 125000);
      expect(parseAmountMinor('1,250.50'), 125050);
      expect(parseAmountMinor('1250'), 125000);
      expect(parseAmountMinor('0,05'), 5);
      expect(parseAmountMinor('1.250'), 125000);
      expect(parseAmountMinor('12,5'), 1250);
      expect(parseAmountMinor('1.234.567,89 TL'), 123456789);
    });
    test('işaret göstergeleri', () {
      expect(parseAmountMinor('1.250,00 B'), -125000);
      expect(parseAmountMinor('1.250,00 A'), 125000);
      expect(parseAmountMinor('(300,00)'), -30000);
      expect(parseAmountMinor('300,00-'), -30000);
    });
    test('okunamayan ve kuruştan ince tutar null', () {
      expect(parseAmountMinor(''), isNull);
      expect(parseAmountMinor('abc'), isNull);
      expect(parseAmountMinor('1,234,5,6'), isNull);
      expect(parseAmountMinor('10,0051'), isNull);
      expect(numToMinor(1250.5), 125050);
      expect(numToMinor(0.1 + 0.2), 30);
      expect(numToMinor(10.005), isNull);
    });
  });

  group('MT940', () {
    const sample = ':20:STMT1\r\n:25:TR330006100519786457841326\r\n:28C:1/1\r\n:60F:C261001TRY10000,00\r\n'
        ':61:2610020102C1500,00NTRFNONREF//BANK123\r\n:86:?20Gul A2 aidat?21ekim?32AHMET?33YILMAZ\r\n?31TR110006200000000000000001\r\n'
        ':61:2610030103D250,50NCHGREF9\r\n:86:HESAP ISLETIM UCRETI\r\n:62F:C261003TRY11249,50\r\n';
    test('çok satırlı :86:, işaretler, bakiyeler', () {
      final s = parseMt940(sample);
      expect(s.accountIban, 'TR330006100519786457841326');
      expect(s.openingMinor, 1000000);
      expect(s.closingMinor, 1124950);
      expect(s.lines.length, 2);
      expect(s.lines[0].valueDate, '2026-10-02');
      expect(s.lines[0].amountMinor, 150000);
      expect(s.lines[0].description, 'Gul A2 aidat ekim');
      expect(s.lines[0].counterpartyName, 'AHMETYILMAZ');
      expect(s.lines[0].counterpartyIban, 'TR110006200000000000000001');
      expect(s.lines[0].bankReference, 'BANK123');
      expect(s.lines[1].amountMinor, -25050);
      expect(s.lines[1].description, 'HESAP ISLETIM UCRETI');
    });
    test('LF satır sonu ve çok blok', () {
      final s = parseMt940('${sample.replaceAll('\r\n', '\n')}\n$sample');
      expect(s.lines.length, 4);
      expect(looksLikeMt940(sample), isTrue);
    });
    test('hareket yoksa hata', () {
      expect(() => parseMt940(':20:X\n:25:TR1\n'), throwsA(isA<Mt940Exception>()));
    });
  });

  group('CSV okuyucu ve eşleme', () {
    Uint8List csv(String text) => Uint8List.fromList(utf8.encode(text));
    test('önsöz satırları atlanır, ayrı borç/alacak sütunları', () {
      final file = readBankFile(
        csv('Hesap Ekstresi;;;\nMüşteri: X;;;\nTarih;Açıklama;Borç;Alacak;Bakiye\n01.10.2026;GUL A2 aidat;;1.500,00;11.500,00\n02.10.2026;Komisyon;25,50;;11.474,50\n'),
        'e.csv',
      );
      expect(file.kind, BankFileKind.csv);
      final table = file.table!;
      expect(table.headers.first, 'Tarih');
      final r = applyBankMapping(table, table.guess);
      expect(r.lines.length, 2);
      expect(r.lines[0].amountMinor, 150000);
      expect(r.lines[0].valueDate, '2026-10-01');
      expect(r.lines[1].amountMinor, -2550);
      expect(r.lines[1].balanceAfterMinor, 1147450);
      expect(file.sha256.length, 64);
    });
    test('tek tutar sütunu ve B/A göstergesi', () {
      final file = readBankFile(csv('Tarih;Açıklama;Tutar;B/A\n03.10.2026;Havale;500,00;A\n04.10.2026;Ödeme;75,25;B\n'), 'e.csv');
      final r = applyBankMapping(file.table!, file.table!.guess);
      expect(r.lines.map((e) => e.amountMinor), <int>[50000, -7525]);
    });
    test('okunamayan tutar hata listesine, tarihsiz satır atlanır', () {
      final file = readBankFile(csv('Tarih;Açıklama;Tutar\n03.10.2026;a;xx\nToplam;;100\n04.10.2026;b;10,00\n'), 'e.csv');
      final r = applyBankMapping(file.table!, file.table!.guess);
      expect(r.errors, <int>[2]);
      expect(r.skipped, 1);
      expect(r.lines.length, 1);
    });
    test('MT940 dosyası türüyle tanınır', () {
      final file = readBankFile(csv(':20:A\n:25:TR330006100519786457841326\n:61:2610020102C10,00NTRFNONREF\n:86:test\n'), 'x.sta');
      expect(file.kind, BankFileKind.mt940);
      expect(bankLinesOfMt940(file.mt940!).lines.single.amountMinor, 1000);
    });
    test('başlık imzası aynı biçimde kararlı', () {
      final a = readBankFile(csv('Tarih;Açıklama;Tutar\n03.10.2026;a;1,00\n'), 'a.csv');
      final b = readBankFile(csv('Tarih;Açıklama;Tutar\n09.10.2026;z;2,00\n'), 'b.csv');
      expect(a.table!.signature, b.table!.signature);
    });
  });
}
