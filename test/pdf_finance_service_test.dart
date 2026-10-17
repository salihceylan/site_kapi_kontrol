// Platform Faz 4b: makbuz / ekstre / rapor PDF üretimi (docs/PLATFORM_FINANS_4B.md "Ö1" ve "PDF (istemci)").
//
// Çevrimdışı: yazı tipi uygulamaya GÖMÜLÜdür; `PdfGoogleFonts` ÇAĞRILMAZ (ağ erişimi test boyunca kapalı).
// Türkçe glif: ğüşıöçĞÜŞİÖÇ ve ₺ gömülü yazı tiplerinde VAR olmalı ve belgede GERÇEKTEN yazılmalıdır; eksik glif =
// test başarısız (sessiz kutu / yedek yazı tipi yok). PDF görsel olarak çizilemediğinden metin, yazı tipi
// eşlemesinden (ToUnicode) okunarak doğrulanır.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:site_kapi_kontrol/models/receipt_models.dart';
import 'package:site_kapi_kontrol/models/report_models.dart';
import 'package:site_kapi_kontrol/services/background_work.dart';
import 'package:site_kapi_kontrol/services/pdf_finance_service.dart';
import 'package:site_kapi_kontrol/services/pdf_font_set.dart';

import 'support/pdf_text_probe.dart';

/// Ağa çıkan her HttpClient'ı reddeder: PDF üretimi çevrimdışı çalışmalı.
class _NoNetwork extends HttpOverrides {
  int created = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    created++;
    throw StateError('PDF üretimi ağa çıkmamalı');
  }
}

const String _allTurkish = 'ğüşıöçĞÜŞİÖÇ₺';

Map<String, dynamic> _snapshot({
  String number = 'MK-2026-000123',
  String kind = 'collection',
  int amount = 123456,
  String site = 'Işık Sitesi Çağdaş Yönetimi',
  String apartment = 'Şeker Blok - 5',
  String? payerName = 'Ayşe Güneş Öztürk',
  String issuer = 'Yönetici İsmail Çelik',
  String? cancelsNumber,
  String? cancelledByNumber,
  String? cancelReason,
}) => <String, dynamic>{
  'number': number,
  'kind': kind,
  'amount_minor': amount,
  'issued_on': '2026-10-16',
  'paid_on': '2026-10-14',
  'method': 'cash',
  'site': <String, dynamic>{'name': site},
  'apartment': <String, dynamic>{'label': apartment},
  'payer': <String, dynamic>{'party': 'owner', 'name': payerName},
  'issuer': <String, dynamic>{'name': issuer},
  'cancels_number': cancelsNumber,
  'cancelled_by_number': cancelledByNumber,
  'cancel_reason_code': cancelReason,
  'verification_code': 'AB12CD34EF56',
  'cekince': true,
  'template_version': 1,
};

Receipt _receipt({
  String status = 'active',
  Map<String, dynamic>? snapshot,
  int copyCount = 0,
  Map<String, dynamic>? template,
}) => Receipt.fromJson(<String, dynamic>{
  'id': 9,
  'status': status,
  'copy_count': copyCount,
  'snapshot': snapshot ?? _snapshot(),
  'template': ?template,
});

final DateTime _printed = DateTime.utc(2026, 10, 16, 9, 30);

Map<String, dynamic> _entryJson(int id, int amount, {String kind = 'charge', String date = '2026-10-01', String? name}) =>
    <String, dynamic>{
      'id': id,
      'kind': kind,
      'amount_minor': amount,
      'entry_date': date,
      'definition_name': ?name,
      'method': kind == 'payment' ? 'cash' : null,
    };

ApartmentStatement _statement({int rows = 3}) {
  var running = 0;
  final items = <Map<String, dynamic>>[];
  for (var i = 0; i < rows; i++) {
    final isPayment = i % 3 == 2;
    final amount = isPayment ? -50000 : 90000;
    running += amount;
    items.add(<String, dynamic>{
      ..._entryJson(i + 1, amount, kind: isPayment ? 'payment' : 'charge', name: isPayment ? null : 'Aylık aidat'),
      if (isPayment && i == 2) 'receipt': <String, dynamic>{'id': 3, 'number': 'MK-2026-000045'},
      'running_balance_minor': running,
    });
  }
  return ApartmentStatement.fromJson(<String, dynamic>{
    'site': <String, dynamic>{'name': 'Işık Sitesi'},
    'generated_at': '2026-10-16T09:00:00Z',
    'closed_through': '2026-09',
    'apartment': <String, dynamic>{'id': 301, 'label': 'Şeker 5', 'block_name': 'Çınar Blok', 'responsible_party': 'owner'},
    'from': '2026-01-01',
    'to': '2026-10-16',
    'opening_balance_minor': 0,
    'closing_balance_minor': running,
    'items': items,
    'totals': <String, dynamic>{'charged_minor': 180000, 'late_fee_minor': 0, 'paid_minor': 50000, 'reversed_minor': 0},
    'overdue_minor': 130000,
  });
}

Map<String, dynamic> _buckets(int v) => <String, dynamic>{
  'not_due_minor': v,
  'd0_30_minor': v,
  'd31_60_minor': v,
  'd61_90_minor': v,
  'd91_180_minor': v,
  'd181_365_minor': v,
  'd366_plus_minor': v,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PdfFinanceService.debugCompress = false;
    BackgroundWork.debugRunInline = true;
  });

  tearDown(() {
    PdfFinanceService.debugCompress = true;
    BackgroundWork.debugRunInline = false;
  });

  group('gömülü yazı tipi', () {
    test('Roboto Regular + Bold varlıktan yüklenir; ğüşıöçĞÜŞİÖÇ₺ glifleri HER İKİSİNDE var', () async {
      final fonts = await PdfFontSet.loadBundled();
      expect(fonts.regular, isNotNull);
      expect(fonts.bold, isNotNull);
      expect(fonts.regular!.lengthInBytes, greaterThan(100000));
      for (final entry in <String, Uint8List?>{'Regular': fonts.regular, 'Bold': fonts.bold}.entries) {
        final parser = TtfParser(ByteData.sublistView(entry.value!));
        for (final rune in _allTurkish.runes) {
          expect(
            parser.charToGlyphIndexMap.containsKey(rune),
            isTrue,
            reason: 'Roboto ${entry.key}: "${String.fromCharCode(rune)}" glifi eksik',
          );
        }
      }
      final resolved = fonts.resolve();
      expect(resolved.regular, isA<pw.TtfFont>(), reason: 'Helvetica yedeğine düşülmemeli');
      expect(resolved.bold, isA<pw.TtfFont>());
    });

    test('makbuz / rapor üretimi ağdan yazı tipi indiren PdfGoogleFonts / loadRoboto KULLANMAZ (kaynak denetimi)', () {
      final source = File('lib/services/pdf_finance_service.dart').readAsStringSync();
      expect(source.contains('PdfGoogleFonts'), isFalse);
      expect(source.contains('loadRoboto'), isFalse);
      expect(source.contains('loadBundled'), isTrue);
    });

    test('Roboto lisansı (Apache-2.0) varlık olarak gömülü ve pubspec varlık listesinde', () async {
      final license = await rootBundle.loadString('assets/fonts/LICENSE_Roboto.txt');
      expect(license, contains('Apache License'));
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('assets/fonts/Roboto-Regular.ttf'));
      expect(pubspec, contains('assets/fonts/Roboto-Bold.ttf'));
      expect(pubspec, contains('assets/fonts/LICENSE_Roboto.txt'));
    });
  });

  group('makbuz PDF', () {
    test('R13 P2-11: ödeyen "both" ise ad malik/kiracı sıfatıyla birleştirilmez; owner ise "Malik - ad"', () async {
      final both = _snapshot();
      (both['payer'] as Map<String, dynamic>)['party'] = 'both';
      final bothText = extractPdfText(await PdfFinanceService.generateReceiptPdf(receipt: _receipt(snapshot: both), stamp: 'ASIL', printedAt: _printed));
      expect(bothText, contains('Ayşe Güneş Öztürk'));
      expect(bothText, isNot(contains('Malik / kiracı')));
      final ownerText = extractPdfText(await PdfFinanceService.generateReceiptPdf(receipt: _receipt(), stamp: 'ASIL', printedAt: _printed));
      expect(ownerText, contains('Malik - Ayşe Güneş Öztürk'));
    });

    test('sunucu şablon metni verirse PDF onu kullanır (tek kaynak); vermezse paketlenmiş sürüm 1 metinleri', () async {
      final withTemplate = _receipt(
        template: <String, dynamic>{
          'version': 2,
          'draft': false,
          'mahsup_text': 'Mahsup: şablon sürüm iki metni, ığüşöç.',
          'cekince_text': 'Çekince: şablon sürüm iki metni.',
          'disclaimer_text': 'Uyarı: şablon sürüm iki uyarısı.',
        },
      );
      expect(withTemplate.template?.version, 2);
      final text = extractPdfText(await PdfFinanceService.generateReceiptPdf(receipt: withTemplate, stamp: 'ASIL', printedAt: _printed));
      expect(text, contains('Mahsup: şablon sürüm iki metni, ığüşöç.'));
      expect(text, contains('Çekince: şablon sürüm iki metni.'));
      expect(text, contains('Uyarı: şablon sürüm iki uyarısı.'));
      expect(text, isNot(contains(PdfFinanceService.mahsupText)));
      final plain = extractPdfText(await PdfFinanceService.generateReceiptPdf(receipt: _receipt(), stamp: 'ASIL', printedAt: _printed));
      expect(plain, contains(PdfFinanceService.mahsupText));
      expect(_receipt().template, isNull);
      // Boş şablon (hiç metin yok) paketlenmiş metinleri DEĞİŞTİRMEZ.
      expect(_receipt(template: <String, dynamic>{'version': 1, 'draft': true}).template, isNull);
    });

    test('tahsilat makbuzu: numara, tutar rakam + yazıyla, mahsup ve çekince, ASIL damgası, doğrulama kodu', () async {
      final bytes = await PdfFinanceService.generateReceiptPdf(receipt: _receipt(), stamp: receiptStampText(1), printedAt: _printed);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      final text = extractPdfText(bytes);
      expect(text, contains('TAHSİLAT MAKBUZU'));
      expect(text, contains('Makbuz No: MK-2026-000123'));
      expect(text, contains('1.234,56 ₺'));
      expect(text, contains('Yazıyla: bin iki yüz otuz dört lira elli altı kuruş'));
      expect(text, contains('Tahsil edilen tutar'));
      expect(text, contains(PdfFinanceService.mahsupText));
      expect(text, contains(PdfFinanceService.cekinceText));
      expect(text, contains(PdfFinanceService.ledgerDisclaimer));
      expect(text, contains('ASIL'));
      expect(text, contains('Doğrulama kodu: AB12-CD34-EF56'));
      expect(text, contains('Şablon sürümü 1'));
      expect(text, contains('16.10.2026'), reason: 'düzenleme tarihi');
      expect(text, contains('14.10.2026'), reason: 'tahsilat tarihi ayrı satır');
      expect(text, contains('Işık Sitesi Çağdaş Yönetimi'));
      expect(text, contains('Şeker Blok - 5'));
      expect(text, contains('Malik - Ayşe Güneş Öztürk'));
      expect(text, contains('Nakit'));
      expect(text, contains('Yönetici İsmail Çelik'));
      expect(text, contains('Kaşe / İmza'));
      expect(text, isNot(contains('İPTAL EDİLMİŞTİR')));
      expect(text, isNot(contains('KOPYA')));
    });

    test('Türkçe harfler belgeye GERÇEKTEN yazılır (ğüşıöçĞÜŞİÖÇ ve ₺ eşlemede); Helvetica yok', () async {
      final receipt = _receipt(
        snapshot: _snapshot(site: 'ĞÜŞİÖÇ ğüşıöç Sitesi', apartment: 'Çiçek ₺ Blok', payerName: 'Öğüt Şükrü Ispanak İnci'),
      );
      final bytes = await PdfFinanceService.generateReceiptPdf(receipt: receipt, stamp: 'ASIL', printedAt: _printed);
      final mapped = pdfMappedCodePoints(bytes);
      for (final rune in _allTurkish.runes) {
        expect(mapped.contains(rune), isTrue, reason: '"${String.fromCharCode(rune)}" belgede yazılmamış');
      }
      final raw = latin1.decode(bytes);
      expect(raw, isNot(contains('Helvetica')), reason: 'yedek yazı tipi kullanılmamalı');
      expect(raw, contains('/FontFile2'), reason: 'TTF gömülü');
      expect(raw, contains('Roboto-Regular'));
      expect(raw, contains('Roboto-Bold'));
      expect(extractPdfText(bytes), contains('Öğüt Şükrü Ispanak İnci'));
    });

    test('ÇEVRİMDIŞI: ağ erişimi kapalıyken makbuz ve rapor üretilir, Türkçe harfler kaybolmaz', () async {
      final guard = _NoNetwork();
      final bytes = await HttpOverrides.runWithHttpOverrides(
        () => PdfFinanceService.generateReceiptPdf(receipt: _receipt(), stamp: 'ASIL', printedAt: _printed),
        guard,
      );
      expect(guard.created, 0, reason: 'HttpClient hiç kurulmamalı');
      expect(extractPdfText(bytes), contains('TAHSİLAT MAKBUZU'));
      final statement = await HttpOverrides.runWithHttpOverrides(
        () => PdfFinanceService.generateStatementPdf(statement: _statement(), printedAt: _printed),
        guard,
      );
      expect(guard.created, 0);
      expect(extractPdfText(statement), contains('Önceki bakiye'));
    });

    test('KOPYA damgaları: yönetici ikinci basım "KOPYA (2)", sakin cihazı "KOPYA"', () async {
      final copy2 = await PdfFinanceService.generateReceiptPdf(receipt: _receipt(copyCount: 1), stamp: receiptStampText(2), printedAt: _printed);
      expect(extractPdfText(copy2), contains('KOPYA (2)'));
      expect(extractPdfText(copy2), isNot(contains('ASIL')));
      final resident = await PdfFinanceService.generateReceiptPdf(receipt: _receipt(), stamp: 'KOPYA', printedAt: _printed);
      final text = extractPdfText(resident);
      expect(text, contains('KOPYA'));
      expect(text, isNot(contains('ASIL')));
    });

    test('iptal edilmiş makbuz: "İPTAL EDİLMİŞTİR — iptal makbuzu No ..." ve diyagonal İPTAL damgası', () async {
      final receipt = _receipt(
        status: 'cancelled',
        snapshot: _snapshot(cancelledByNumber: 'MK-2026-000124'),
      );
      final text = extractPdfText(await PdfFinanceService.generateReceiptPdf(receipt: receipt, stamp: 'KOPYA (2)', printedAt: _printed));
      expect(text, contains('İPTAL EDİLMİŞTİR — iptal makbuzu No MK-2026-000124'));
      expect(text, contains('İPTAL'), reason: 'diyagonal damga');
      expect(text, contains('TAHSİLAT MAKBUZU'));
    });

    test('iptal makbuzu: başlık, iptal edilen numara ve neden', () async {
      final receipt = Receipt.fromJson(<String, dynamic>{
        'id': 10,
        'snapshot': _snapshot(
          number: 'MK-2026-000124',
          kind: 'cancellation',
          cancelsNumber: 'MK-2026-000123',
          cancelReason: 'issued_in_error',
        ),
      });
      final text = extractPdfText(await PdfFinanceService.generateReceiptPdf(receipt: receipt, stamp: 'ASIL', printedAt: _printed));
      expect(text, contains('İPTAL MAKBUZU'));
      expect(text, contains('Makbuz No: MK-2026-000124'));
      expect(text, contains('Bu makbuz MK-2026-000123 numaralı makbuzu iptal eder.'));
      expect(text, contains('İptal nedeni: Makbuz hatalı düzenlendi.'));
      expect(text, contains('İptal edilen tutar'));
    });

    test('payer.name yoksa yalnız sorumlu taraf yazılır; uydurma ad YOK', () async {
      final receipt = _receipt(snapshot: _snapshot(payerName: null));
      final text = extractPdfText(await PdfFinanceService.generateReceiptPdf(receipt: receipt, stamp: 'ASIL', printedAt: _printed));
      expect(text, contains('Malik'));
      expect(text, isNot(contains('Ayşe')));
    });

    test('çok uzun site ve daire adı: yine TEK sayfa', () async {
      final longName = List<String>.filled(14, 'Çok Uzun Adlı Konut Yapı Kooperatifi').join(' ');
      final receipt = _receipt(snapshot: _snapshot(site: longName, apartment: 'Blok ${'Ş' * 60} - 5', payerName: longName));
      final bytes = await PdfFinanceService.generateReceiptPdf(receipt: receipt, stamp: 'ASIL', printedAt: _printed);
      final raw = latin1.decode(bytes);
      expect(RegExp(r'/Type/Page/').allMatches(raw).length, 1, reason: 'A4 tek sayfa');
    });

    test('tutar biçimi: en büyük tutar ve kuruşlu tutarlar tam yazılır (kayan nokta yok)', () async {
      for (final minor in <int>[1, 99, 100, 123456, 99999999999]) {
        final receipt = _receipt(snapshot: _snapshot(amount: minor));
        final text = extractPdfText(await PdfFinanceService.generateReceiptPdf(receipt: receipt, stamp: 'ASIL', printedAt: _printed));
        final lira = minor ~/ 100;
        final kurus = (minor % 100).toString().padLeft(2, '0');
        final grouped = lira.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
        expect(text, contains('$grouped,$kurus ₺'), reason: '$minor kuruş');
      }
    });

    test('dosya adları ASCII: Makbuz_MK-2026-000123.pdf; Türkçe harfler sadeleşir', () {
      expect(PdfFinanceService.receiptFileName(_receipt()), 'Makbuz_MK-2026-000123.pdf');
      expect(PdfFinanceService.asciiName('Çınar Blok / Şeker 5'), 'Cinar_Blok_Seker_5');
      expect(PdfFinanceService.asciiName('ÖĞÜT İŞ'), 'OGUT_IS');
      expect(PdfFinanceService.asciiName('ığ'), 'ig');
      expect(PdfFinanceService.statementFileName('Şeker 5', DateTime(2026, 10, 16)), 'Ekstre_Seker_5_20261016.pdf');
      expect(PdfFinanceService.statementFileName('???', DateTime(2026, 1, 2)), 'Ekstre_Daire_20260102.pdf');
      expect(PdfFinanceService.reportFileName('Yaşlandırma', DateTime(2026, 10, 16)), 'Rapor_Yaslandirma_20261016.pdf');
      for (final name in <String>[
        PdfFinanceService.receiptFileName(_receipt()),
        PdfFinanceService.statementFileName('Şeker 5', DateTime(2026, 10, 16)),
      ]) {
        expect(RegExp(r'^[A-Za-z0-9_.\-]+$').hasMatch(name), isTrue, reason: name);
      }
    });

    test('doğrulama kodu okunaklı gruplanır; 12 karakter değilse olduğu gibi', () {
      expect(formatVerificationCode('ab12cd34ef56'), 'AB12-CD34-EF56');
      expect(formatVerificationCode('ABC'), 'ABC');
      expect(formatVerificationCode(''), '');
    });
  });

  group('R13: ekstre başlığı ve tazminat ters kaydı', () {
    test('P2-5: daire başlığında blok adı TEKRARLANMAZ (A Blok - 5, "A Blok / A Blok - 5" değil); farklıysa blok / daire', () async {
      Map<String, dynamic> json(String label, String? block) => <String, dynamic>{
        'site': <String, dynamic>{'name': 'Işık Sitesi'},
        'generated_at': '2026-10-16T09:00:00Z',
        'apartment': <String, dynamic>{'id': 301, 'label': label, 'block_name': block, 'responsible_party': 'owner'},
        'from': '2026-01-01',
        'to': '2026-10-16',
        'opening_balance_minor': 0,
        'closing_balance_minor': 0,
        'items': <Object?>[],
        'totals': <String, dynamic>{'charged_minor': 0, 'late_fee_minor': 0, 'paid_minor': 0, 'reversed_minor': 0},
      };
      final dup = extractPdfText(await PdfFinanceService.generateStatementPdf(statement: ApartmentStatement.fromJson(json('A Blok - 5', 'A Blok')), printedAt: _printed));
      expect(dup, contains('A Blok - 5'));
      expect(dup, isNot(contains('A Blok / A Blok - 5')));
      final plain = extractPdfText(await PdfFinanceService.generateStatementPdf(statement: ApartmentStatement.fromJson(json('Daire 7', 'Güneş Blok')), printedAt: _printed));
      expect(plain, contains('Güneş Blok / Daire 7'));
    });

    test('P2-1: tazminat kalemi "Gecikme tazminatı", ters kaydı "Ters kayıt" (alacak sütununda)', () async {
      final statement = ApartmentStatement.fromJson(<String, dynamic>{
        'site': <String, dynamic>{'name': 'Işık Sitesi'},
        'generated_at': '2026-10-16T09:00:00Z',
        'apartment': <String, dynamic>{'id': 301, 'label': 'A Blok - 5', 'block_name': 'A Blok', 'responsible_party': 'owner'},
        'from': '2026-01-01',
        'to': '2026-10-16',
        'opening_balance_minor': 0,
        'closing_balance_minor': 0,
        'items': <Map<String, dynamic>>[
          <String, dynamic>{..._entryJson(1, 12345, name: 'Gecikme tazminatı'), 'late_fee_run_id': 40, 'running_balance_minor': 12345},
          <String, dynamic>{..._entryJson(2, -12345, kind: 'reversal', name: 'Gecikme tazminatı'), 'late_fee_run_id': 40, 'reverses_entry_id': 1, 'running_balance_minor': 0},
        ],
        'totals': <String, dynamic>{'charged_minor': 0, 'late_fee_minor': 12345, 'paid_minor': 0, 'reversed_minor': -12345},
      });
      final text = extractPdfText(await PdfFinanceService.generateStatementPdf(statement: statement, printedAt: _printed));
      expect(text, contains('Gecikme tazminatı'));
      expect(text, contains('Ters kayıt'));
    });
  });

  group('ekstre ve raporlar', () {
    test('ekstre: önceki / dönem sonu bakiye, makbuz numarası, toplamlar, uyarı ve altbilgi', () async {
      final bytes = await PdfFinanceService.generateStatementPdf(statement: _statement(), printedAt: _printed);
      final text = extractPdfText(bytes);
      expect(text, contains('Hesap Ekstresi'));
      expect(text, contains('Işık Sitesi'));
      expect(text, contains('Çınar Blok / Şeker 5'));
      expect(text, contains('Önceki bakiye'));
      expect(text, contains('Dönem sonu bakiye'));
      expect(text, contains('MK-2026-000045'), reason: 'ödeme satırında makbuz numarası');
      expect(text, contains('Aylık aidat'));
      expect(text, contains(PdfFinanceService.reportDisclaimer));
      expect(text, contains('Kapalı dönem: Eylül 2026 ve öncesi. Sonraki aylar kesinleşmemiştir.'));
      expect(text, contains('1.300,00 ₺'), reason: 'vadesi geçmiş tutar');
    });

    test('ekstre: kapanış yoksa "kesinleşmemiştir" notu', () async {
      final json = <String, dynamic>{
        'apartment': <String, dynamic>{'id': 1, 'label': '5'},
        'opening_balance_minor': 0,
        'closing_balance_minor': 0,
        'items': <dynamic>[],
        'totals': <String, dynamic>{'charged_minor': 0, 'paid_minor': 0, 'reversed_minor': 0},
      };
      final text = extractPdfText(await PdfFinanceService.generateStatementPdf(statement: ApartmentStatement.fromJson(json), printedAt: _printed));
      expect(text, contains('Kapatılmış dönem yok: rakamlar kesinleşmemiştir.'));
    });

    test('200 satırdan uzun ekstre arka plan işine gider; kısa olan gitmez', () async {
      BackgroundWork.debugRunCount = 0;
      await PdfFinanceService.generateStatementPdf(statement: _statement(rows: 40), printedAt: _printed);
      expect(BackgroundWork.debugRunCount, 0);
      final long = await PdfFinanceService.generateStatementPdf(statement: _statement(rows: 260), printedAt: _printed);
      expect(BackgroundWork.debugRunCount, 1);
      final raw = latin1.decode(long);
      expect(RegExp(r'/Type/Page/').allMatches(raw).length, greaterThan(1), reason: 'çok sayfalı');
      expect(extractPdfText(long), contains('Dönem sonu bakiye'));
    });

    test('gerçek izoleyle de üretilir (debugRunInline kapalı)', () async {
      BackgroundWork.debugRunInline = false;
      final bytes = await PdfFinanceService.generateStatementPdf(statement: _statement(rows: 230), printedAt: _printed);
      expect(extractPdfText(bytes), contains('Önceki bakiye'));
      expect(extractPdfText(bytes), contains('Çınar Blok / Şeker 5'));
    });

    test('yaşlandırma: kova başlıkları, TOPLAM satırı ve kesinleşmemiş notu', () async {
      final report = AgingReport.fromJson(<String, dynamic>{
        'site': <String, dynamic>{'name': 'Işık Sitesi'},
        'as_of': '2026-10-16',
        'closed_through': '2026-09',
        'totals': <String, dynamic>{..._buckets(100), 'credit_minor': 500, 'late_fee_outstanding_minor': 300, 'total_overdue_minor': 600},
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'apartment_id': 301,
            'label': 'Şeker 5',
            'block_name': 'Çınar Blok',
            ..._buckets(10),
            'credit_minor': 0,
            'total_overdue_minor': 60,
          },
        ],
        'total': 1,
      });
      final text = extractPdfText(await PdfFinanceService.generateAgingPdf(report: report, printedAt: _printed));
      expect(text, contains('Borç / Alacak Yaşlandırma Raporu'));
      expect(text, contains('Vadesi gelmemiş'));
      expect(text, contains('366 gün ve üzeri'));
      expect(text, contains('Çınar Blok / Şeker 5'));
      expect(text, contains('TOPLAM'));
      expect(text, contains('ödenmemiş gecikme tazminatı toplamı 3,00 ₺'));
      expect(text, contains(PdfFinanceService.reportDisclaimer));
    });

    test('gelir-gider: kesinleşmemiş ay "*" ile işaretlenir; oran yoksa "-"; kategori tablosu', () async {
      final report = IncomeExpenseReport.fromJson(<String, dynamic>{
        'site': <String, dynamic>{'name': 'Işık Sitesi'},
        'from': '2026-09',
        'to': '2026-10',
        'closed_through': '2026-09',
        'months': <Map<String, dynamic>>[
          <String, dynamic>{
            'period': '2026-09',
            'charged_minor': 100000,
            'collected_minor': 80000,
            'expense_minor': 30000,
            'net_cash_minor': 50000,
            'collection_rate_bp': 8000,
            'expense_by_category': <Map<String, dynamic>>[
              <String, dynamic>{'category_name': 'Asansör bakım', 'total_minor': 30000},
            ],
          },
          <String, dynamic>{
            'period': '2026-10',
            'charged_minor': 0,
            'collected_minor': 0,
            'expense_minor': 0,
            'net_cash_minor': 0,
            'collection_rate_bp': null,
          },
        ],
      });
      final text = extractPdfText(await PdfFinanceService.generateIncomeExpensePdf(report: report, printedAt: _printed));
      expect(text, contains('Aylık Gelir-Gider Raporu'));
      expect(text, contains('Eylül 2026'));
      expect(text, contains('Ekim 2026 *'));
      expect(text, isNot(contains('Eylül 2026 *')));
      expect(text, contains('%80,00'));
      expect(text, contains('Asansör bakım'));
      expect(text, contains('TOPLAM'));
    });

    test('kasa durumu: düzeltme ayrı sütun, eşlenmemiş tahsilat uyarısı, mutabakat farkı', () async {
      final report = CashPositionReport.fromJson(<String, dynamic>{
        'site': <String, dynamic>{'name': 'Işık Sitesi'},
        'as_of': '2026-10-16',
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'account_id': 1,
            'name': 'Şube Kasası',
            'kind': 'cash',
            'opening_minor': 100,
            'collections_minor': 200,
            'expenses_minor': -50,
            'transfers_in_minor': 0,
            'transfers_out_minor': 0,
            'adjustments_minor': -5,
            'reversals_minor': 0,
            'balance_minor': 245,
            'last_reconciliation': <String, dynamic>{'as_of_date': '2026-10-01', 'difference_minor': -500},
          },
        ],
        'totals': <String, dynamic>{'balance_minor': 245},
        'unassigned_payments': <String, dynamic>{'count': 2, 'total_minor': 150000},
      });
      final text = extractPdfText(await PdfFinanceService.generateCashPositionPdf(report: report, printedAt: _printed));
      expect(text, contains('Kasa / Banka Durumu'));
      expect(text, contains('Düzeltme'));
      expect(text, contains('Şube Kasası'));
      expect(text, contains('son mutabakat 01.10.2026, fark -5,00 ₺'));
      expect(text, contains('Uyarı: hesaba eşlenmemiş 2 tahsilat var (toplam 1.500,00 ₺).'));
    });

    test('kurul özeti: uyarılar, yalnız yanıtta olan bölümler, kişi adı yok', () async {
      final report = BoardSummaryReport.fromJson(<String, dynamic>{
        'site': <String, dynamic>{'name': 'Işık Sitesi'},
        'from': '2026-01',
        'to': '2026-12',
        'collection': <String, dynamic>{'charged_minor': 1000000, 'collected_minor': 900000, 'collection_rate_bp': 9000},
        'receivables': <String, dynamic>{
          'total_overdue_minor': 100000,
          'debtor_count': 7,
          'debtor_ratio_bp': 1750,
          'aging': <Map<String, dynamic>>[
            <String, dynamic>{'bucket': 'not_due', 'count': 2, 'total_minor': 70000},
            <String, dynamic>{'bucket': 'd0_30', 'count': 3, 'total_minor': 40000},
          ],
        },
        // Sunucunun kurul özeti hesap satırı: yalnız bakiye (+ son mutabakat); hareket kırılımı YOK.
        'cash': <String, dynamic>{
          'accounts': <Map<String, dynamic>>[
            <String, dynamic>{'id': 1, 'name': 'Şube Kasası', 'kind': 'cash', 'balance_minor': 125000, 'last_reconciliation': null},
          ],
          'total_balance_minor': 125000,
        },
        'debtor_list': <Map<String, dynamic>>[
          <String, dynamic>{'label': 'A Blok - 5', 'total_overdue_minor': 60000},
        ],
        'warnings': <Map<String, dynamic>>[
          <String, dynamic>{'code': 'UNCLOSED_PAST_PERIODS'},
        ],
      });
      final text = extractPdfText(await PdfFinanceService.generateBoardSummaryPdf(report: report, printedAt: _printed));
      expect(text, contains('Vadesi geçmiş borç'));
      expect(text, isNot(contains('Toplam borç')), reason: 'değer yalnız vadesi geçmiş borçtur');
      expect(text, contains('Vadesi gelmemiş (bilgi, toplama dahil değil) (2 daire)'));
      expect(text, contains('700,00 ₺'));
      expect(text, contains('Şube Kasası'));
      expect(text, contains('1.250,00 ₺'));
      expect(text, contains('A Blok - 5'));
      expect(text, contains('600,00 ₺'));
      expect(text, contains('Yönetim Kurulu Özet Raporu'));
      expect(text, contains('Uyarılar'));
      expect(text, contains('kapatılmamış dönemler'));
      expect(text, contains('Tahsilat oranı'));
      expect(text, contains('%90,00'));
      expect(text, contains('7 (%17,50)'));
      expect(text, contains('0-30 gün (3 daire)'));
      expect(text, isNot(contains('Gider')), reason: 'yanıtta olmayan bölüm uydurma sıfırla çizilmez');
      expect(text, contains(PdfFinanceService.reportDisclaimer));
    });
  });

  group('paylaşım', () {
    test('sharePdf: PDF dosyası ASCII adla share_plus\'a verilir', () async {
      ShareParams? captured;
      await PdfFinanceService.sharePdf(
        Uint8List.fromList(<int>[1, 2, 3]),
        fileName: 'Makbuz_MK-2026-000123.pdf',
        subject: 'Makbuz',
        shareFn: (params) async {
          captured = params;
          return const ShareResult('', ShareResultStatus.success);
        },
      );
      expect(captured!.files!.single.mimeType, 'application/pdf');
      expect(captured!.fileNameOverrides, <String>['Makbuz_MK-2026-000123.pdf']);
    });
  });
}
