// Karar Defteri PDF'i (lib/services/pdf_decision_service.dart).
//
// Çevrimdışı: yazı tipi uygulamaya GÖMÜLÜ Roboto'dur (ağ test boyunca kapalı). Türkçe harfler belgede GERÇEKTEN yazılmalı
// (yazı tipi eşlemesinden, ToUnicode, okunur; Helvetica yedeğinde bu eşleme olmaz). İçerik: üstbilgi (site, yıl), yalnız
// o yılın KESİN kararları numara sırasıyla, metin, oylama, katılanlar, kesinleştirme bilgisi ve altbilgi notu.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/decision_models.dart';
import 'package:site_kapi_kontrol/services/background_work.dart';
import 'package:site_kapi_kontrol/services/pdf_decision_service.dart';
import 'package:site_kapi_kontrol/services/pdf_font_set.dart';

import 'screens/decision_fixtures.dart';
import 'support/pdf_text_probe.dart';

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => throw StateError('PDF üretimi ağa çıkmamalı');
}

const String _site = 'Işık Sitesi Çağdaş Yönetimi';
final DateTime _printed = DateTime.utc(2026, 10, 19, 9, 30);

List<Decision> _sample() => <Decision>[
  Decision.fromJson(dcJson(
    3,
    no: 2,
    date: '2026-06-20',
    status: 'kesin',
    title: 'Güvenlik görevlisi işe alınması',
    body:
        'Gece vardiyası için bir güvenlik görevlisi işe alınmasına oybirliğiyle karar verildi.\n\nÜcret aidattan ödenecektir.\n'
        'Harf denetimi: ğüşıöç ĞÜŞİÖÇ.',
    attendees: 'Şükrü Öztürk, Ayşe Güneş',
    supersedesId: 1,
    supersedesLabel: '2026/1',
  )),
  Decision.fromJson(dcJson(
    1,
    no: 1,
    status: 'kesin',
    title: 'Çatı onarımı',
    supersededBy: <Map<String, dynamic>>[<String, dynamic>{'id': 3, 'number_label': '2026/2'}],
  )),
  Decision.fromJson(dcJson(2, title: 'Taslak İçerik Görünmemeli')),
  Decision.fromJson(dcJson(4, no: 1, date: '2025-11-02', status: 'kesin', title: 'Geçen Yılın Kararı')),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PdfDecisionService.debugCompress = false;
    BackgroundWork.debugRunInline = true;
  });

  tearDown(() {
    PdfDecisionService.debugCompress = true;
    BackgroundWork.debugRunInline = false;
  });

  test('yılın kesin kararları: Türkçe metin gömülü yazı tipiyle yazılır; taslak ve başka yıl girmez; numara sırası', () async {
    final bytes = await HttpOverrides.runZoned(
      () async => PdfDecisionService.generateYearPdf(
        siteName: _site,
        year: 2026,
        decisions: _sample(),
        printedAt: _printed,
        fonts: await PdfFontSet.loadBundled(),
      ),
      createHttpClient: _NoNetwork().createHttpClient,
    );
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final text = extractPdfText(bytes);
    expect(text, contains('Karar Defteri — 2026'));
    expect(text, contains(_site));
    expect(text, contains('2026 yılının kesinleşmiş kararları (2 karar)'));
    expect(text, contains('Karar No: 2026/1'));
    expect(text, contains('Karar No: 2026/2'));
    expect(text.indexOf('Karar No: 2026/1'), lessThan(text.indexOf('Karar No: 2026/2')), reason: 'numara sırası');
    expect(text, contains('Güvenlik görevlisi işe alınması'));
    expect(text, contains('oybirliğiyle karar verildi.'));
    expect(text, contains('Ücret aidattan ödenecektir.'));
    expect(text, contains('Kabul edildi (Kabul 3, Ret 0, Çekimser 1)'));
    expect(text, contains('Şükrü Öztürk, Ayşe Güneş'));
    expect(text, contains('Değiştirdiği karar: 2026/1'));
    expect(text, contains('2026/2 sayılı kararla değiştirildi'));
    expect(text, contains('Kesinleştiren: Ayşe Yılmaz'));
    expect(text, contains('05.03.2026'));
    expect(text, contains('Yönetim Kurulu'));
    expect(text, contains(kDecisionLegalNotice));
    expect(text, isNot(contains('Taslak İçerik Görünmemeli')));
    expect(text, isNot(contains('Geçen Yılın Kararı')));
    final mapped = pdfMappedCodePoints(bytes);
    expect(text, contains('Harf denetimi: ğüşıöç ĞÜŞİÖÇ.'));
    for (final rune in 'ğüşıöçĞÜŞİÖÇ'.runes) {
      expect(mapped.contains(rune), isTrue, reason: '"${String.fromCharCode(rune)}" belgede yazılı olmalı');
    }
  });

  test('uzun metin (10.000 karakter) sayfalara bölünür; çok karar arka planda üretilir', () async {
    final fonts = await PdfFontSet.loadBundled();
    final long = List<String>.generate(80, (i) => 'Paragraf ${i + 1}: ${'Sakinlerin ortak alan kullanımı düzenlenmiştir. ' * 2}').join('\n');
    expect(long.length, lessThanOrEqualTo(DecisionInput.bodyMax));
    final decisions = <Decision>[
      for (var i = 1; i <= PdfDecisionService.isolateDecisionThreshold + 1; i++)
        Decision.fromJson(dcJson(i, no: i, status: 'kesin', body: i == 1 ? long : 'Kısa metin $i')),
    ];
    final before = BackgroundWork.debugRunCount;
    final bytes = await PdfDecisionService.generateYearPdf(
      siteName: 'Gül Sitesi',
      year: 2026,
      decisions: decisions,
      printedAt: _printed,
      fonts: fonts,
    );
    expect(BackgroundWork.debugRunCount, before + 1);
    final text = extractPdfText(bytes);
    expect(text, contains('Paragraf 80:'));
    expect(text, contains('Karar No: 2026/21'));
    expect(RegExp(r'/Type\s*/Page\b').allMatches(String.fromCharCodes(bytes)).length, greaterThan(2));
  });

  int pageCount(Uint8List bytes) => RegExp(r'/Type\s*/Page\b').allMatches(String.fromCharCodes(bytes)).length;

  test('sayfadan uzun TEK satır (10.000 karakter, satır sonu yok) sonraki sayfalara akar', () async {
    final fonts = await PdfFontSet.loadBundled();
    final words = StringBuffer();
    var n = 0;
    while (words.length < DecisionInput.bodyMax - 20) {
      words.write('kelime${n++} ');
    }
    final oneLine = '${words.toString().trim()} SON-İŞARET';
    expect(oneLine.length, lessThanOrEqualTo(DecisionInput.bodyMax));
    expect(oneLine.contains('\n'), isFalse);
    final bytes = await PdfDecisionService.generateYearPdf(
      siteName: 'Gül Sitesi',
      year: 2026,
      decisions: <Decision>[Decision.fromJson(dcJson(1, no: 1, status: 'kesin', body: oneLine))],
      printedAt: _printed,
      fonts: fonts,
    ).timeout(const Duration(seconds: 60));
    expect(pageCount(bytes), greaterThan(1));
    final text = extractPdfText(bytes);
    expect(text, contains('kelime0 kelime1'));
    expect(text, contains('SON-İŞARET'), reason: 'son sayfadaki son sözcük kaybolmaz');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('boşluksuz 10.000 karakterlik sözcük satır sonlarında bölünür, sayfalara akar ve tamamı yazılır', () async {
    final token = 'x' * DecisionInput.bodyMax;
    final bytes = await PdfDecisionService.generateYearPdf(
      siteName: 'Gül Sitesi',
      year: 2026,
      decisions: <Decision>[Decision.fromJson(dcJson(1, no: 1, status: 'kesin', body: token))],
      printedAt: _printed,
      fonts: await PdfFontSet.loadBundled(),
    ).timeout(const Duration(seconds: 60));
    expect(pageCount(bytes), greaterThan(1));
    final text = extractPdfText(bytes);
    expect('x'.allMatches(text).length, DecisionInput.bodyMax);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('150 satırlık katılanlar listesi sayfalara akar (iki kararda da)', () async {
    final attendees = List<String>.generate(150, (i) => 'Üye ${(i + 1).toString().padLeft(3, '0')}').join('\n');
    expect(attendees.length, lessThanOrEqualTo(DecisionInput.attendeesMax));
    final bytes = await PdfDecisionService.generateYearPdf(
      siteName: 'Gül Sitesi',
      year: 2026,
      decisions: <Decision>[
        Decision.fromJson(dcJson(1, no: 1, status: 'kesin', attendees: attendees, body: 'Kısa metin')),
        Decision.fromJson(dcJson(2, no: 2, status: 'kesin', attendees: attendees, body: 'İkinci karar')),
      ],
      printedAt: _printed,
      fonts: await PdfFontSet.loadBundled(),
    ).timeout(const Duration(seconds: 60));
    expect(pageCount(bytes), greaterThan(2));
    final text = extractPdfText(bytes);
    expect(text, contains('Katılanlar:'));
    expect(text, contains('Üye 001'));
    expect('Üye 150'.allMatches(text).length, 2, reason: 'iki kararın da son katılanı yazılır');
    expect(text, contains('Karar No: 2026/2'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('kesin karar yoksa belge yine üretilir ve bunu söyler', () async {
    final bytes = await PdfDecisionService.generateYearPdf(
      siteName: 'Gül Sitesi',
      year: 2024,
      decisions: _sample(),
      printedAt: _printed,
      fonts: await PdfFontSet.loadBundled(),
    );
    expect(extractPdfText(bytes), contains('2024 yılında kesinleşmiş karar yok.'));
  });

  test('dosya adı ASCII', () {
    expect(PdfDecisionService.fileName(_site, 2026), 'Karar_Defteri_Isik_Sitesi_Cagdas_Yonetimi_2026.pdf');
    expect(PdfDecisionService.fileName('  ', 2026), 'Karar_Defteri_Site_2026.pdf');
  });

  test('kaynak denetimi: ağdan yazı tipi indiren PdfGoogleFonts / loadRoboto KULLANILMAZ', () {
    final source = File('lib/services/pdf_decision_service.dart').readAsStringSync();
    expect(source.contains('PdfGoogleFonts'), isFalse);
    expect(source.contains('loadRoboto'), isFalse);
    expect(source.contains('loadBundled'), isTrue);
  });
}
