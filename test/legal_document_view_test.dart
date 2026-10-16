// Belge görüntüleyici (LegalDocumentView) ve giriş ekranı alt bağlantıları (LegalFooterLinks).
//
// Durumlar: yükleniyor | hata (ASLA "boş belge" gibi görünmez; "Yeniden dene") | belge (başlık, sürüm,
// yürürlük tarihi, taslak uyarısı, Markdown) | yenileme hatası eski metni korur.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/pages/login_page.dart';
import 'package:site_kapi_kontrol/ui/views/legal_document_view.dart';
import 'package:site_kapi_kontrol/ui/views/legal_footer_links.dart';
import 'package:site_kapi_kontrol/ui/views/legal_markdown.dart' show kLegalMarkdownTruncatedMessage;
import 'package:site_kapi_kontrol/ui/views/legal_parts.dart';

import 'design/harness.dart';
import 'legal_fixtures.dart';

Future<void> _pumpView(
  WidgetTester t,
  FakeLegalServer server, {
  String id = 'privacy',
  double width = 400,
  double height = 800,
  double scale = 1.0,
  bool dark = false,
  LegalLinkOpenerAlias? opener,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    harnessApp(
      LegalDocumentView(documentId: id, titleHint: 'Gizlilik', api: server.api, onOpenLink: opener),
      scale: scale,
      dark: dark,
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

typedef LegalLinkOpenerAlias = Future<bool> Function(Uri uri);

void main() {
  group('LegalDocumentView', () {
    testWidgets('yükleniyor: iskelet ve başlık ipucu; yanıt gelince belge', (t) async {
      final server = FakeLegalServer()..docGate = Completer<void>();
      server.contents['privacy'] = '# Gizlilik Politikası\n\nKişisel verileriniz **korunur**.';
      await _pumpView(t, server);
      expect(find.byType(SkeletonBox), findsWidgets);
      expect(find.text('Gizlilik'), findsOneWidget, reason: 'AppBar başlık ipucu');
      expect(find.text('Yeniden dene'), findsNothing);

      server.docGate!.complete();
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(SkeletonBox), findsNothing);
      expect(find.textContaining('Kişisel verileriniz', findRichText: true), findsOneWidget);
    });

    testWidgets('belge: başlık, sürüm, yürürlük tarihi (GG.AA.YYYY), Markdown; taslak uyarısı yok', (t) async {
      final server = FakeLegalServer();
      server.contents['privacy'] = '## Madde 1\n\n- bir\n- iki';
      await _pumpView(t, server);
      expect(find.text('Sürüm: 2026-10-16'), findsOneWidget);
      expect(find.text('Yürürlük: 16.10.2026'), findsOneWidget);
      expect(find.textContaining('Madde 1', findRichText: true), findsOneWidget);
      expect(find.textContaining('köşeli parantezli'), findsNothing);
    });

    testWidgets('belge sınırı aşılıp KESİLİRSE uyarı + "Web sayfasını aç" (sunucunun /legal/:id sayfası)', (t) async {
      final opened = <Uri>[];
      final server = FakeLegalServer();
      server.contents['privacy'] = '# Gizlilik\n\n${'a' * 800000}';
      await _pumpView(
        t,
        server,
        opener: (uri) async {
          opened.add(uri);
          return true;
        },
      );
      expect(find.text(kLegalMarkdownTruncatedMessage), findsOneWidget);
      await t.ensureVisible(find.text('Web sayfasını aç'));
      await t.pump();
      await t.tap(find.text('Web sayfasını aç'));
      await t.pump();
      expect(opened.map((u) => u.toString()), <String>['https://api.example.test/legal/privacy']);
    });

    testWidgets('kesilmeyen belgede kesme uyarısı yok', (t) async {
      final server = FakeLegalServer();
      server.contents['privacy'] = '# Gizlilik\n\nNormal metin';
      await _pumpView(t, server);
      expect(find.text(kLegalMarkdownTruncatedMessage), findsNothing);
      expect(find.text('Web sayfasını aç'), findsNothing);
    });

    testWidgets('complete:false: taslak uyarısı gösterilir', (t) async {
      final server = FakeLegalServer(
        documents: <Map<String, dynamic>>[legalDoc('privacy', title: 'Gizlilik Politikası', complete: false)],
      );
      await _pumpView(t, server);
      expect(find.textContaining('köşeli parantezli'), findsOneWidget);
      expect(find.textContaining('taslak niteliğindedir'), findsOneWidget);
    });

    testWidgets('metin boşsa "boş döndü" notu (hata değil)', (t) async {
      final server = FakeLegalServer();
      server.contents['privacy'] = '   ';
      await _pumpView(t, server);
      expect(find.textContaining('metni boş döndü'), findsOneWidget);
    });

    testWidgets('HATA: neden + "Yeniden dene"; belge boşmuş gibi görünmez; yeniden denenince yüklenir', (t) async {
      final server = FakeLegalServer()..docStatus = 500;
      server.contents['privacy'] = 'Yüklendi metni';
      await _pumpView(t, server);
      expect(find.byType(LegalRetryNotice), findsOneWidget);
      expect(find.text('Yeniden dene'), findsOneWidget);
      expect(find.textContaining('metni boş döndü'), findsNothing);
      expect(find.textContaining('Yüklendi metni', findRichText: true), findsNothing);

      server.docStatus = 200;
      await t.tap(find.text('Yeniden dene'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Yeniden dene'), findsNothing);
      expect(find.textContaining('Yüklendi metni', findRichText: true), findsOneWidget);
    });

    testWidgets('404: "Belge bulunamadı" + yeniden dene', (t) async {
      final server = FakeLegalServer();
      await _pumpView(t, server, id: 'olmayan_belge');
      expect(find.text('Belge bulunamadı'), findsOneWidget);
      expect(find.text('Yeniden dene'), findsOneWidget);
    });

    testWidgets('"Yeniden dene" çift dokunuşta tek istek', (t) async {
      final server = FakeLegalServer()..docStatus = 500;
      await _pumpView(t, server);
      expect(server.count('GET', '/public/legal-documents/privacy'), 1);
      server.docStatus = 200;
      server.docGate = Completer<void>();
      final retryAt = t.getCenter(find.text('Yeniden dene'));
      await t.tapAt(retryAt);
      await t.tapAt(retryAt);
      await t.pump();
      server.docGate!.complete();
      await t.pump(const Duration(milliseconds: 100));
      expect(server.count('GET', '/public/legal-documents/privacy'), 2);
    });

    testWidgets('aşağı çekerek yenileme: eski metin kalır, hata üstte gösterilir', (t) async {
      final server = FakeLegalServer();
      server.contents['privacy'] = 'Eski metin';
      await _pumpView(t, server);
      expect(find.textContaining('Eski metin', findRichText: true), findsOneWidget);

      server.docStatus = 503;
      await t.fling(find.byType(SingleChildScrollView), const Offset(0, 400), 1000);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      expect(find.textContaining('Eski metin', findRichText: true), findsOneWidget);
      expect(find.byType(LegalRetryNotice), findsOneWidget);
    });

    for (final (w, h, s) in const <(double, double, double)>[
      (320, 640, 2.0),
      (360, 640, 1.5),
      (640, 360, 2.0), // yatay + büyük yazı
    ]) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('taşma yok: belge / hata / yükleniyor (${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'})', (
          t,
        ) async {
          final long = '# Çok Uzun Bir Belge Başlığı Taşma Denemesi\n\n'
              '${List<String>.filled(30, 'Uzun bir paragraf, **kalın** ve [bağlantı](https://example.com/uzun/adres) içerir.').join('\n\n')}\n\n'
              '- madde bir çok uzun bir madde metni olabilir ve satıra sarmalıdır\n1. sıralı madde';
          final ok = FakeLegalServer();
          ok.contents['privacy'] = long;
          await _pumpView(t, ok, width: w, height: h, scale: s, dark: dark);
          expect(t.takeException(), isNull);

          await _pumpView(t, FakeLegalServer()..docStatus = 500, width: w, height: h, scale: s, dark: dark);
          expect(t.takeException(), isNull);

          final gated = FakeLegalServer()..docGate = Completer<void>();
          await _pumpView(t, gated, width: w, height: h, scale: s, dark: dark);
          expect(t.takeException(), isNull);
          gated.docGate!.complete();
          await t.pump(const Duration(milliseconds: 100));
        });
      }
    }
  });

  group('AppBar başlığı büyük yazıda kırpılmaz (R4)', () {
    // Başlık paragrafı: AppBar içindeki başlık Text'i.
    RenderParagraph titleParagraph(WidgetTester t, String title) => t.renderObject<RenderParagraph>(
      find.descendant(of: find.byType(AppBar), matching: find.text(title)),
    );

    /// Metnin GERÇEK (kırpılmamış) yüksekliği: RenderParagraph.size araç çubuğu yüksekliğine kırpıldığından
    /// (sınırlar sıkı) taşmayı yakalamaz; metin kutularının alt kenarı yakalar.
    double contentHeight(RenderParagraph paragraph) {
      final length = paragraph.text.toPlainText().length;
      final boxes = paragraph.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: length));
      return boxes.map((b) => b.bottom).fold<double>(0, math.max);
    }

    testWidgets('araç çubuğu yüksekliği başlığın gerçek satır yüksekliğinden hesaplanır (1,0x: 56 dp altına inmez)', (t) async {
      final server = FakeLegalServer();
      final heights = <double, double>{};
      for (final scale in const <double>[1.0, 1.15, 1.34, 1.5, 2.0, 3.0]) {
        await _pumpView(t, server, scale: scale);
        heights[scale] = t.getSize(find.byType(AppBar)).height;
      }
      expect(heights[1.0], kToolbarHeight, reason: 'normal yazı: varsayılan 56 dp');
      expect(heights[2.0]!, greaterThan(kToolbarHeight), reason: 'büyük yazıda iki satır için yer açılır');
      // AppBar başlığı en çok 1,34x büyütür: bu ölçekten sonra yükseklik sabittir.
      expect(heights[1.5], heights[1.34]);
      expect(heights[2.0], heights[1.34]);
      expect(heights[3.0], heights[1.34]);
      // 18 sp x 1,34 x 1,3 satır aralığı x 2 satır + 8 dp pay.
      expect(heights[2.0]!, closeTo(18 * 1.34 * 1.3 * 2 + 8, 0.5));
      // Ölçek büyüdükçe yükseklik azalmaz.
      expect(heights[1.15]!, greaterThanOrEqualTo(heights[1.0]!));
      expect(heights[1.34]!, greaterThanOrEqualTo(heights[1.15]!));
    });

    for (final (w, s) in const <(double, double)>[(360, 2.0), (360, 1.5), (412, 2.0), (640, 2.0)]) {
      testWidgets('iki satıra sığan başlık kırpılmaz ve araç çubuğundan taşmaz (${w.toInt()} dp x$s)', (t) async {
        const title = 'Gizlilik Politikası';
        final server = FakeLegalServer(
          documents: <Map<String, dynamic>>[legalDoc('privacy', title: title, version: '2026-10-16')],
        );
        await _pumpView(t, server, width: w, height: 800, scale: s);
        final paragraph = titleParagraph(t, title);
        expect(paragraph.didExceedMaxLines, isFalse, reason: 'başlık iki satıra sığar, elips yok');
        if (w <= 412) {
          // Dar çubukta başlık gerçekten iki satıra sarar (test yazı tipinde harfler geniştir): kırpma burada olurdu.
          final lines = paragraph
              .getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: title.length))
              .map((b) => b.top.round())
              .toSet();
          expect(lines.length, 2, reason: 'iki satır');
          expect(contentHeight(paragraph), greaterThan(kToolbarHeight), reason: 'varsayılan 56 dp çubuğa sığmaz: çubuk büyümeli');
        }
        // Başlık kutusu araç çubuğunun yüksekliğinden büyük OLAMAZ (eski 56 dp'de iki satır ~94 dp idi: kırpılırdı).
        expect(contentHeight(paragraph), lessThanOrEqualTo(t.getSize(find.byType(AppBar)).height));
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('çok uzun başlık: en çok 2 satır + elips; araç çubuğunu aşmaz; tam ad gövdede okunur', (t) async {
      const longTitle = 'Kişisel Verilerin Korunması Kanunu Kapsamında Aydınlatma Metni ve Açık Rıza Beyanı';
      final server = FakeLegalServer(
        documents: <Map<String, dynamic>>[legalDoc('privacy', title: longTitle, version: '2026-10-16')],
      );
      await _pumpView(t, server, width: 360, height: 900, scale: 2.0);
      final bar = titleParagraph(t, longTitle);
      expect(contentHeight(bar), lessThanOrEqualTo(t.getSize(find.byType(AppBar)).height));
      expect(bar.maxLines, 2);
      expect(bar.didExceedMaxLines, isTrue, reason: 'üç+ satır: ikinci satırdan sonra elips');
      // Gövdedeki başlık kırpılmaz (tam ad).
      expect(find.descendant(of: find.byType(AppBar), matching: find.text(longTitle)), findsOneWidget);
      final bodyTitle = find.descendant(of: find.byType(AppCard), matching: find.text(longTitle));
      expect(bodyTitle, findsWidgets, reason: 'belge kartı başlığı (+ varsayılan metindeki başlık)');
      final bodyParagraph = t.renderObject<RenderParagraph>(bodyTitle.first);
      expect(bodyParagraph.didExceedMaxLines, isFalse);
    });

    testWidgets('yükleniyor / hata durumunda başlık ipucu aynı kurala uyar', (t) async {
      final server = FakeLegalServer()..docStatus = 500;
      await _pumpView(t, server, width: 360, height: 800, scale: 2.0);
      final paragraph = titleParagraph(t, 'Gizlilik');
      expect(contentHeight(paragraph), lessThanOrEqualTo(t.getSize(find.byType(AppBar)).height));
      expect(paragraph.didExceedMaxLines, isFalse);
    });
  });

  group('LegalFooterLinks / giriş ekranı', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    testWidgets('üç bağlantı: Kullanım Koşulları · Gizlilik · KVKK; >= 48 dp; tam adla okunur', (t) async {
      final semantics = t.ensureSemantics();
      try {
        await t.pumpWidget(harnessApp(const LegalFooterLinks()));
        await t.pump();
        for (final label in const <String>['Kullanım Koşulları', 'Gizlilik', 'KVKK']) {
          final button = find.widgetWithText(TextButton, label);
          expect(button, findsOneWidget, reason: label);
          expect(t.getSize(button).height, greaterThanOrEqualTo(48), reason: label);
        }
        expect(find.bySemanticsLabel('Gizlilik Politikası belgesini aç'), findsOneWidget);
        expect(find.bySemanticsLabel('KVKK Aydınlatma Metni belgesini aç'), findsOneWidget);
        expect(find.bySemanticsLabel('Kullanım Koşulları belgesini aç'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('bağlantı doğru belgeyi açar (terms / privacy / kvkk_notice), çift dokunma tek sayfa', (t) async {
      final server = FakeLegalServer();
      for (final entry in const <(String, String)>[
        ('Kullanım Koşulları', 'terms'),
        ('Gizlilik', 'privacy'),
        ('KVKK', 'kvkk_notice'),
      ]) {
        await t.pumpWidget(harnessApp(LegalFooterLinks(api: server.api)));
        final at = t.getCenter(find.widgetWithText(TextButton, entry.$1));
        await t.tapAt(at);
        await t.tapAt(at);
        await t.pump();
        await t.pump(const Duration(milliseconds: 500));
        expect(find.byType(LegalDocumentView), findsOneWidget, reason: entry.$1);
        expect(server.where('GET', '/public/legal-documents/${entry.$2}'), hasLength(1), reason: entry.$1);
        t.state<NavigatorState>(find.byType(Navigator).first).pop();
        await t.pump(const Duration(milliseconds: 500));
      }
    });

    testWidgets('büyük yazıda alt alta (ayırıcısız), taşma yok (320 x 2,0)', (t) async {
      await pumpAt(t, const LegalFooterLinks(), width: 320, height: 640, scale: 2.0);
      expect(find.text('·'), findsNothing);
      final tops = <double>[
        for (final label in const <String>['Kullanım Koşulları', 'Gizlilik', 'KVKK'])
          t.getTopLeft(find.widgetWithText(TextButton, label)).dy,
      ];
      expect(tops[0] < tops[1] && tops[1] < tops[2], isTrue);
      expect(t.takeException(), isNull);
    });

    testWidgets('yatay büyük yazı (640x360, 2,0x): taşma yok, bağlantılar erişilebilir', (t) async {
      await pumpAt(t, const LegalFooterLinks(), width: 640, height: 360, scale: 2.0);
      expect(t.takeException(), isNull);
      for (final label in const <String>['Kullanım Koşulları', 'Gizlilik', 'KVKK']) {
        expect(t.getSize(find.widgetWithText(TextButton, label)).height, greaterThanOrEqualTo(48), reason: label);
      }
    });

    testWidgets('normal yazıda yan yana ayırıcılı', (t) async {
      await pumpAt(t, const LegalFooterLinks(), width: 800, height: 640, scale: 1.0);
      final dy = <double>[
        for (final label in const <String>['Kullanım Koşulları', 'Gizlilik', 'KVKK'])
          t.getTopLeft(find.widgetWithText(TextButton, label)).dy,
      ];
      expect(dy.toSet(), hasLength(1));
    });

    testWidgets('LoginPage altında bağlantılar var ve giriş testlerinin beklediği öğeler korunur', (t) async {
      t.view.physicalSize = const Size(400, 1000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        harnessApp(
          LoginPage(authService: AuthService(api: AuthApi(baseUrl: 'http://localhost')), legalApi: FakeLegalServer().api),
        ),
      );
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byType(LegalFooterLinks), findsOneWidget);
      expect(find.text('Giriş Yap'), findsOneWidget);
      expect(find.text('Yeni Hesap Oluştur'), findsOneWidget);
      // Bağlantılar giriş düğmesinden SONRA gelir.
      expect(
        t.getTopLeft(find.byType(LegalFooterLinks)).dy,
        greaterThan(t.getTopLeft(find.text('Giriş Yap')).dy),
      );
    });
  });
}
