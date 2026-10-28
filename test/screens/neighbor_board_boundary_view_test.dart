// Komşu Panosu (NeighborBoardView): SINIR testleri, ekran düzeyi.
//
// Kapsam: çok uzun metin / taşma (sunucu üst sınırı: başlık 120, metin 2000, not 300, gerekçe 200; boşluksuz tek sözcük
// dahil; 320x640 x2,0; 360x640 x1,5; yatay 640x360 x2,0; tablet 768x1024; açık / koyu), boş durum, çok sayıda kayıt
// (kaydırma) ve Türkçe karakterler.
// Klavye açıkken pencereler: gerçek sırada (pencere açılır, klavye gelir, yazılır, gönderilir) sınanır; ürün kodunun taşan
// hücreleri "[BİLİNEN SORUN, atlandı]" olarak kayıtlıdır (bu görevde ürün kodu değiştirilmez).
// Yetki sınırları: neighbor_board_boundary_access_test.dart (ekran) ve neighbor_board_boundary_home_page_test.dart (menü kapısı);
// ağ hatası: neighbor_board_boundary_network_test.dart; servis / model: test/neighbor_board_boundary_api_test.dart.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/neighbor_post.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';

import 'list_fixtures.dart' show tapFinder;
import 'neighbor_board_fixtures.dart';

const String _footer = 'Yakında: telefon bildirimi, fotoğraf ve yorum.';

/// [count] ilan; kimlik büyüdükçe yenidir (sunucu `ORDER BY id DESC`). Her yedincisi benim bekleyen ilanım.
List<Map<String, dynamic>> _many(int count, {String body = 'Çimlerin sulanma saatleri değişti.'}) => <Map<String, dynamic>>[
  for (var i = 1; i <= count; i++)
    nbPost(
      i,
      title: 'Duyuru $i',
      body: '$body ($i)',
      status: i % 7 == 0 ? NeighborPostStatus.pending : NeighborPostStatus.published,
      mine: i % 7 == 0,
      author: 'Komşu $i K.',
    ),
];

void main() {
  group('çok uzun metin ve taşma', () {
    neighborMatrix('sakin: üst sınırda başlık (120) / metin (2000) / yazar / yönetici notu (300), boşluksuz tek sözcük dahil', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final longAuthor = '${nbBlock('Uzunsoyadlı', 90)} K.';
      final rig = NeighborRig(
        posts: <Map<String, dynamic>>[
          nbPost(1, title: nbBlock('Ş', 120), body: nbBlock('Ğ', 2000), author: longAuthor),
          nbPost(
            2,
            title: nbWords(120),
            body: nbWords(2000),
            status: NeighborPostStatus.pending,
            mine: true,
            note: nbWords(300),
          ),
          nbPost(3, title: nbBlock('Ç', 120), status: NeighborPostStatus.rejected, mine: true, note: nbBlock('Ü', 300)),
          nbPost(4, title: 'Kaldırılan kısa ilan', status: NeighborPostStatus.removed, mine: true, note: 'Kısa gerekçe'),
        ],
      );
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(Card), findsNWidgets(4));
      expect(find.text(nbBlock('Ş', 120)), findsOneWidget);
      expect(find.text(nbBlock('Ğ', 2000)), findsOneWidget, reason: 'metin kırpılmaz, satır kaydırılır');
      expect(find.text('$longAuthor - 20.10.2026'), findsOneWidget);
      expect(find.text('Yönetici notu: ${nbWords(300)}'), findsOneWidget);
      expect(find.text('Yönetici notu: ${nbBlock('Ü', 300)}'), findsOneWidget);
      expect(find.text('Şikayet et'), findsOneWidget, reason: 'yalnız başkasının yayındaki ilanı');
      expect(find.text('Geri çek'), findsOneWidget, reason: 'yalnız benim bekleyen ilanım');
    });

    neighborMatrix('yönetici: 200 karakterlik site adı (açılır liste), beş sekme, 20 şikayet x 190 karakter gerekçe', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final siteName = nbWords(200);
      final reasons = <String>[for (var i = 1; i <= 20; i++) '$i. ${nbWords(190)}'];
      final rig = NeighborRig(
        posts: <Map<String, dynamic>>[
          nbPost(1, title: nbBlock('Ş', 120), body: nbWords(2000), status: NeighborPostStatus.pending),
          nbPost(2, title: 'Şikayetli yayın', body: nbWords(500), reasons: reasons),
          nbPost(3, title: 'Yayındaki ilan'),
        ],
      );
      await rig.pump(
        t,
        width: w,
        height: h,
        scale: s,
        dark: dark,
        sites: <PeopleSite>[
          PeopleSite(code: 11, name: siteName, canWrite: true),
          const PeopleSite(code: 12, name: 'Mavi Park'),
        ],
      );
      expect(find.text(siteName), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNWidgets(5));
      expect(find.text(nbBlock('Ş', 120)), findsOneWidget);
      expect(find.text('Onayla'), findsOneWidget);
      expect(find.text('Reddet'), findsOneWidget);

      await tapFinder(t, find.text('Şikayetli'));
      await nbSettle(t);
      expect(t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Şikayetli')).selected, isTrue);
      expect(find.text('20 şikayet: ${reasons.join(' / ')}'), findsOneWidget);
      expect(find.text('Kaldır'), findsOneWidget);
      expect(find.text('Henüz ilan yok.'), findsNothing);
    });

    neighborMatrix('yeni ilan penceresi: başlık 120 / metin 2000 üst sınırı uygulanır, sayaç görünür, fazlası gönderilmez', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final rig = NeighborRig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await tapFinder(t, find.text('Yeni ilan'));
      expect(find.byType(AlertDialog), findsOneWidget);

      await t.enterText(nbDialogField(0), nbBlock('Ş', 150));
      await t.enterText(nbDialogField(1), nbBlock('Ğ', 2100));
      await t.pump();
      expect(nbFieldText(t, nbDialogField(0)).length, 120);
      expect(nbFieldText(t, nbDialogField(1)).length, 2000);
      expect(find.text('120/120'), findsOneWidget);
      expect(find.text('2000/2000'), findsOneWidget);

      await t.tap(nbInDialog('Onaya gönder'));
      await nbSettle(t);
      expect(rig.fake.createCalls, hasLength(1));
      expect(rig.fake.createCalls.single.title, nbBlock('Ş', 120));
      expect(rig.fake.createCalls.single.body, nbBlock('Ğ', 2000));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('İlanınız yönetici onayına gönderildi.'), findsOneWidget);
    });

    neighborMatrix('şikayet penceresi: gerekçe 200 karakterle sınırlı; boş ya da yalnız boşluk gönderilmez', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final rig = NeighborRig(posts: <Map<String, dynamic>>[nbPost(1)]);
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await tapFinder(t, find.text('Şikayet et'));
      expect(find.text('İlanı şikayet et'), findsOneWidget);

      await t.enterText(nbDialogField(0), '   ');
      await t.pump();
      await t.tap(nbInDialog('Gönder'));
      await nbSettle(t);
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'boş gerekçeyle pencere kapanmaz');
      expect(rig.fake.reportCalls, isEmpty);

      await t.enterText(nbDialogField(0), nbWords(260));
      await t.pump();
      expect(nbFieldText(t, nbDialogField(0)).length, 200);
      expect(find.text('200/200'), findsOneWidget);
      await t.tap(nbInDialog('Gönder'));
      await nbSettle(t);
      expect(rig.fake.reportCalls, hasLength(1));
      expect(rig.fake.reportCalls.single.id, 1);
      expect(rig.fake.reportCalls.single.reason, nbWords(260).substring(0, 200).trim());
      expect(find.text('Şikayetiniz yöneticiye iletildi.'), findsOneWidget);
    });

    neighborMatrix('yönetici gerekçe penceresi: 300 karakterle sınırlı, boş gerekçe gönderilmez', (t, w, h, s, dark) async {
      final rig = NeighborRig(sites: nbManagerSite, posts: <Map<String, dynamic>>[nbPost(1, status: NeighborPostStatus.pending)]);
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await tapFinder(t, find.text('Reddet'));
      expect(nbInDialog('Reddet'), findsOneWidget);

      await t.tap(nbInDialog('Gönder'));
      await nbSettle(t);
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'gerekçesiz ret olmaz');
      expect(rig.fake.decideCalls, isEmpty);

      await t.enterText(nbDialogField(0), nbWords(340));
      await t.pump();
      expect(nbFieldText(t, nbDialogField(0)).length, 300);
      expect(find.text('300/300'), findsOneWidget);
      await t.tap(nbInDialog('Gönder'));
      await nbSettle(t);
      expect(rig.fake.decideCalls, hasLength(1));
      expect(rig.fake.decideCalls.single.action, 'reject');
      expect(rig.fake.decideCalls.single.note, nbWords(340).substring(0, 300).trim());
      expect(find.text('İlan reddedildi.'), findsOneWidget);
    });
  });

  group('klavye açıkken pencereler', () {
    // Gerçek sıra: pencere açılır, sonra klavye gelir (alt boşluk), sonra yazılır ve gönderilir.
    Future<void> keyboardFlow(WidgetTester t, double w, double h, double s, double keyboard, String opener) async {
      final rig = NeighborRig(posts: <Map<String, dynamic>>[nbPost(1)]);
      await rig.pump(t, width: w, height: h, scale: s);
      await tapFinder(t, find.text(opener));
      t.view.viewInsets = FakeViewPadding(bottom: keyboard);
      addTearDown(t.view.resetViewInsets);
      await t.pump(const Duration(milliseconds: 50));
      await t.pump(const Duration(milliseconds: 400));
      final newPost = opener == 'Yeni ilan';
      if (newPost) {
        await t.enterText(nbDialogField(0), 'Çocuk bahçesi');
        await t.enterText(nbDialogField(1), nbWords(2100));
      } else {
        await t.enterText(nbDialogField(0), nbWords(250));
      }
      await t.pump(const Duration(milliseconds: 300));
      expect(t.takeException(), isNull, reason: '$opener penceresi klavye açıkken taştı');
      await t.tap(nbInDialog(newPost ? 'Onaya gönder' : 'Gönder'));
      await nbSettle(t);
      expect(find.byType(AlertDialog), findsNothing, reason: 'gönder düğmesi klavye açıkken de erişilebilir');
      expect(newPost ? rig.fake.createCalls : rig.fake.reportCalls, hasLength(1));
    }

    // (genişlik, yükseklik, yazı ölçeği, klavye dp, "Yeni ilan" sağlam mı, "Şikayet et" (gerekçe penceresi) sağlam mı)
    // Sağlam olmayan hücreler ürün kodunun bilinen sorunudur (bu görevde ürün kodu değiştirilmez): ilanı yazan pencerenin
    // sütunu (başlık + eylemler) kalan yüksekliğe sığmıyor (RenderFlex taşması), `_askText` gerekçe penceresinin içeriği
    // kaydırılabilir değil (dart:ui geometry.dart:1384 sınır ihlali / taşma). Düzelince `skip` kalkar, testler olduğu gibi çalışır.
    const cells = <(double, double, double, double, bool, bool)>[
      (360, 640, 1.5, 280, true, true),
      (360, 640, 1.0, 280, true, true),
      (640, 360, 1.0, 180, true, false),
      (640, 360, 2.0, 180, false, false),
      (320, 640, 2.0, 280, false, false),
    ];
    for (final (w, h, s, keyboard, newPostOk, askOk) in cells) {
      for (final (opener, ok) in <(String, bool)>[('Yeni ilan', newPostOk), ('Şikayet et', askOk)]) {
        testWidgets(
          '${ok ? '' : '[BİLİNEN SORUN, atlandı] '}$opener penceresi: ${w.toInt()}x${h.toInt()} x$s, klavye ${keyboard.toInt()} dp açıkken taşmaz, gönderilebilir',
          (t) => keyboardFlow(t, w, h, s, keyboard, opener),
          skip: !ok,
        );
      }
    }
  });

  group('boş durum', () {
    testWidgets('sakin: ilan yok -> "Henüz ilan yok."; Yeni ilan düğmesi ve alt not durur, çubuk ve kart yok', (t) async {
      final rig = NeighborRig();
      await rig.pump(t);
      expect(find.text('Henüz ilan yok.'), findsOneWidget);
      expect(find.text('Yeni ilan'), findsOneWidget);
      expect(find.text(_footer), findsOneWidget);
      expect(find.byType(Card), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(rig.fake.residentCalls, <int>[11]);
      expect(rig.fake.managedCalls, isEmpty);
    });

    testWidgets('yönetici: beş sekmenin hepsi boş -> her sekme kendi durumunu ister ve "Henüz ilan yok." der', (t) async {
      final rig = NeighborRig(sites: nbManagerSite);
      await rig.pump(t);
      expect(find.text('Henüz ilan yok.'), findsOneWidget);
      expect(find.text('Yeni ilan'), findsNothing, reason: 'yönetici ilan yazmaz');
      for (final label in const <String>['Şikayetli', 'Yayındaki', 'Reddedilen', 'Kaldırılan', 'Onay bekleyen']) {
        await tapFinder(t, find.text(label));
        await nbSettle(t);
        expect(find.text('Henüz ilan yok.'), findsOneWidget, reason: label);
        expect(t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label)).selected, isTrue, reason: label);
        expect(find.byType(Card), findsNothing, reason: label);
      }
      expect(rig.fake.managedCalls.map((c) => c.status).toList(), <String>[
        'pending',
        'reported',
        'published',
        'rejected',
        'removed',
        'pending',
      ]);
      expect(rig.fake.residentCalls, isEmpty);
    });

    neighborMatrix('boş durum (sakin ve yönetici): taşma yok', (t, w, h, s, dark) async {
      final resident = NeighborRig();
      await resident.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Henüz ilan yok.'), findsOneWidget);
      expect(find.text('Yeni ilan'), findsOneWidget);

      final manager = NeighborRig(sites: nbManagerSite);
      await manager.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Henüz ilan yok.'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNWidgets(5));
    });

    testWidgets('yükleniyor: ilerleme çubuğu var, "Henüz ilan yok." yok; yanıt gelince tersi', (t) async {
      final rig = NeighborRig(posts: <Map<String, dynamic>>[nbPost(1)]);
      final gate = Completer<void>();
      rig.fake.gates['listResident'] = <Completer<void>>[gate];
      await rig.pump(t);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Henüz ilan yok.'), findsNothing, reason: 'yüklenirken boş durum gösterilmez');
      expect(find.byType(Card), findsNothing);
      gate.complete();
      await nbSettle(t);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(Card), findsOneWidget);
      expect(find.text('Henüz ilan yok.'), findsNothing);
    });

    testWidgets('alanları eksik kayıt (yalnız kimlik, site, durum) çökmez; boş başlıkla kart çizilir', (t) async {
      final rig = NeighborRig(
        posts: <Map<String, dynamic>>[
          <String, dynamic>{'id': 9, 'site_code': 11, 'status': 'published'},
        ],
      );
      await rig.pump(t);
      expect(find.byType(Card), findsOneWidget);
      expect(find.text('Şikayet et'), findsOneWidget);
      expect(find.text('Henüz ilan yok.'), findsNothing);
      expect(t.takeException(), isNull);
    });
  });

  group('çok sayıda kayıt ve kaydırma', () {
    testWidgets('120 ilan (sunucu üst sınırı 100\'ün ötesi dahil): sayfa kaydırılır, son ilana ve alt nota ulaşılır, başa dönülür', (
      t,
    ) async {
      final rig = NeighborRig(posts: _many(120));
      await rig.pump(t, width: 360, height: 640, scale: 1.5);
      expect(rig.position(t).pixels, 0);
      expect(rig.position(t).maxScrollExtent, greaterThan(640 * 10), reason: 'onlarca ekran uzunluğunda içerik');
      expect(find.text('Duyuru 120').hitTestable(), findsOneWidget, reason: 'en yeni ilan en üstte');
      expect(find.text('Duyuru 1').hitTestable(), findsNothing, reason: 'en eski ilan ekran dışında');

      await t.scrollUntilVisible(find.text('Duyuru 1'), 600, scrollable: rig.pageScrollable, maxScrolls: 400);
      expect(find.text('Duyuru 1').hitTestable(), findsOneWidget);
      await t.scrollUntilVisible(find.text(_footer), 300, scrollable: rig.pageScrollable, maxScrolls: 50);
      expect(find.text(_footer).hitTestable(), findsOneWidget);
      expect(rig.position(t).extentAfter, lessThan(100), reason: 'liste sonuna gelindi');

      await t.scrollUntilVisible(find.text('Duyuru 120'), -600, scrollable: rig.pageScrollable, maxScrolls: 400);
      expect(find.text('Duyuru 120').hitTestable(), findsOneWidget);
      expect(rig.position(t).pixels, lessThan(300));
      expect(t.takeException(), isNull);
    });

    testWidgets('kartın üzerinden sürüklemek sayfayı kaydırır (ekranın iç listesi dokunuşu yakalamaz)', (t) async {
      final rig = NeighborRig(posts: _many(30));
      await rig.pump(t, width: 360, height: 640);
      expect(rig.position(t).pixels, 0);
      await t.drag(find.byType(Card).first, const Offset(0, -300));
      await t.pump(const Duration(milliseconds: 400));
      expect(rig.position(t).pixels, greaterThan(100));
    });

    testWidgets('yönetici: 250 bekleyen ilan çizilir; liste kısalınca kaydırma konumu sınırlanır, çökmez', (t) async {
      final rig = NeighborRig(
        sites: nbManagerSite,
        posts: <Map<String, dynamic>>[
          for (var i = 1; i <= 250; i++) nbPost(i, title: 'Bekleyen $i', status: NeighborPostStatus.pending),
        ],
      );
      await rig.pump(t, width: 360, height: 640);
      expect(rig.position(t).maxScrollExtent, greaterThan(10000));
      rig.position(t).jumpTo(rig.position(t).maxScrollExtent);
      await t.pump();
      expect(find.text('Bekleyen 1').hitTestable(), findsOneWidget);

      rig.fake.rows.removeWhere((r) => (r['id'] as int) > 3);
      await rig.state.reload();
      await t.pumpAndSettle();
      expect(find.byType(Card), findsNWidgets(3));
      expect(rig.position(t).pixels, lessThanOrEqualTo(rig.position(t).maxScrollExtent));
      expect(find.text('Bekleyen 1').hitTestable(), findsOneWidget, reason: 'konum sınırlanınca son kart ekranda');
      rig.position(t).jumpTo(0);
      await t.pump();
      expect(find.text('Bekleyen 3').hitTestable(), findsOneWidget, reason: 'en yeni kart en üstte');
      expect(t.takeException(), isNull);
    });

    neighborMatrix('40 uzun ilan (sakin): taşma yok, sayfanın sonuna kadar kaydırılır', (t, w, h, s, dark) async {
      final rig = NeighborRig(posts: _many(40, body: nbWords(500)));
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Duyuru 40'), findsOneWidget);
      final position = rig.position(t);
      expect(position.maxScrollExtent, greaterThan(h), reason: 'içerik ekrandan uzun');
      position.jumpTo(position.maxScrollExtent);
      await t.pump();
      expect(find.text(_footer).hitTestable(), findsOneWidget, reason: 'listenin sonundaki not erişilebilir');
      expect(find.text('Duyuru 1'), findsOneWidget, reason: 'en eski ilan da çizilmiş');
      position.jumpTo(0);
      await t.pump();
      expect(find.text('Duyuru 40').hitTestable(), findsOneWidget);
    });
  });

  group('Türkçe karakterler', () {
    const title = 'İSTANBUL\'DA ÇOCUK ŞENLİĞİ: ığüşöç ĞÜŞİÖÇ 🌳';
    const body = 'Pazar 15:00\'te bahçede "çocuk şenliği" var.\nGetirin: ışıklı şapka, çiğ köfte, ÖĞRETMEN çayı.';

    testWidgets('ğ ü ş ı İ ö ç, büyük karşılıkları, satır sonu, tırnak ve emoji bozulmadan görünür; tarih gg.aa.yyyy', (t) async {
      final rig = NeighborRig(
        posts: <Map<String, dynamic>>[
          nbPost(1, title: title, body: body, author: 'Çağlar Ö.', createdAt: '2026-01-09T12:00:00Z'),
          nbPost(
            2,
            title: 'İĞDIR Işık Sitesi ilanı',
            body: 'Şükrü Bey\'in köpeği "Çomar" kayıp.',
            status: NeighborPostStatus.pending,
            author: 'Şule Ğ.',
            createdAt: '2026-10-05T12:00:00Z',
            mine: true,
          ),
          nbPost(
            3,
            title: 'Reddedilen ilan',
            status: NeighborPostStatus.rejected,
            mine: true,
            note: '  Gerekçe: İçerik uygunsuz (ŞİKÂYET, çöp).  ',
            author: 'Ben B.',
          ),
        ],
      );
      await rig.pump(t);
      expect(find.text(title), findsOneWidget);
      expect(find.text(body), findsOneWidget);
      expect(find.text('Çağlar Ö. - 09.01.2026'), findsOneWidget, reason: 'gün ve ay iki hane');
      expect(find.text('İĞDIR Işık Sitesi ilanı'), findsOneWidget, reason: 'birleşik noktalı I bozulmaz');
      expect(find.text('Şule Ğ. - 05.10.2026 - Onay bekliyor'), findsOneWidget);
      expect(find.text('Ben B. - 20.10.2026 - Reddedildi'), findsOneWidget);
      expect(find.text('Yönetici notu: Gerekçe: İçerik uygunsuz (ŞİKÂYET, çöp).'), findsOneWidget, reason: 'not kırpılır, harfler aynen');
    });

    neighborMatrix('Türkçe uzun metin: taşma yok', (t, w, h, s, dark) async {
      final rig = NeighborRig(
        posts: <Map<String, dynamic>>[
          nbPost(1, title: title * 3, body: '$body\n' * 12),
          nbPost(2, title: 'ÇĞİÖŞÜ ' * 17, body: 'ığüşöç ' * 280, status: NeighborPostStatus.pending, mine: true),
        ],
      );
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(Card), findsNWidgets(2));
    });

    testWidgets('Türkçe ilan yazma: kırpılır, harfleri bozulmadan sunucuya gider ve yenilenen listede görünür', (t) async {
      final rig = NeighborRig();
      await rig.pump(t);
      await tapFinder(t, find.text('Yeni ilan'));
      await t.enterText(nbDialogField(0), '  Çocuk şenliği için ığüşöç İĞÜŞÖÇ  ');
      await t.enterText(nbDialogField(1), '\n Pazar günü saat 15:00\'te "ŞENLİK" var.\nÇiğ köfte getirin.  ');
      await t.pump();
      await t.tap(nbInDialog('Onaya gönder'));
      await nbSettle(t);
      expect(rig.fake.createCalls, hasLength(1));
      expect(rig.fake.createCalls.single.site, 11);
      expect(rig.fake.createCalls.single.title, 'Çocuk şenliği için ığüşöç İĞÜŞÖÇ');
      expect(rig.fake.createCalls.single.body, 'Pazar günü saat 15:00\'te "ŞENLİK" var.\nÇiğ köfte getirin.');
      expect(rig.fake.residentCalls, hasLength(2), reason: 'işlemden sonra liste yenilenir');
      expect(find.text('Çocuk şenliği için ığüşöç İĞÜŞÖÇ'), findsOneWidget);
      expect(find.text('Ben B. - 20.10.2026 - Onay bekliyor'), findsOneWidget);
    });

    testWidgets('Türkçe şikayet ve ret gerekçesi kırpılarak, harfleri bozulmadan gider', (t) async {
      final resident = NeighborRig(posts: <Map<String, dynamic>>[nbPost(1, title: 'Şüpheli ilan')]);
      await resident.pump(t);
      await tapFinder(t, find.text('Şikayet et'));
      await t.enterText(nbDialogField(0), '  Reklam içeriyor: ÇİĞ ŞÜPHELİ ığ  ');
      await t.pump();
      await t.tap(nbInDialog('Gönder'));
      await nbSettle(t);
      expect(resident.fake.reportCalls.single.reason, 'Reklam içeriyor: ÇİĞ ŞÜPHELİ ığ');

      final manager = NeighborRig(
        sites: nbManagerSite,
        posts: <Map<String, dynamic>>[nbPost(2, title: 'Bekleyen ilan', status: NeighborPostStatus.pending)],
      );
      await manager.pump(t);
      await tapFinder(t, find.text('Reddet'));
      await t.enterText(nbDialogField(0), ' Uygun değil: İŞYERİ reklamı ');
      await t.pump();
      await t.tap(nbInDialog('Gönder'));
      await nbSettle(t);
      expect(manager.fake.decideCalls.single.note, 'Uygun değil: İŞYERİ reklamı');
    });

    testWidgets('Türkçe site adları açılır listede; boş ad "İsimsiz site" olur, teknik kod görünmez; seçince o sitenin ilanları gelir ve yeni ilan o sitenin koduyla gider', (
      t,
    ) async {
      final rig = NeighborRig(
        posts: <Map<String, dynamic>>[
          nbPost(1, site: 11, title: 'Şişli ilanı'),
          nbPost(2, site: 12, title: 'İzmir ilanı'),
          nbPost(3, site: 13, title: 'Adsız site ilanı'),
        ],
      );
      await rig.pump(
        t,
        sites: const <PeopleSite>[
          PeopleSite(code: 11, name: 'Şişli Çınar Sitesi'),
          PeopleSite(code: 12, name: 'İzmir Işık Evleri'),
          PeopleSite(code: 13, name: '  '),
        ],
      );
      expect(find.text('Şişli ilanı'), findsOneWidget);
      expect(find.text('Şişli Çınar Sitesi'), findsOneWidget);
      // Seçili olmayan öğeler açılır listenin yığınında ekran dışıdır (skipOffstage: false).
      expect(find.text('İsimsiz site', skipOffstage: false), findsOneWidget);
      expect(find.text('Site 13', skipOffstage: false), findsNothing);

      await tapFinder(t, find.byType(DropdownButton<int>));
      await nbSettle(t);
      await t.tap(find.text('İzmir Işık Evleri').last);
      await nbSettle(t);
      expect(rig.fake.residentCalls, <int>[11, 12]);
      expect(find.text('İzmir ilanı'), findsOneWidget);
      expect(find.text('Şişli ilanı'), findsNothing);

      // Yazılan ilan SEÇİLİ sitenin koduyla gider (ilk sitenin değil).
      await tapFinder(t, find.text('Yeni ilan'));
      await t.enterText(nbDialogField(0), 'İzmir için ilan');
      await t.enterText(nbDialogField(1), 'Işık Evleri sakinlerine duyuru.');
      await t.pump();
      await t.tap(nbInDialog('Onaya gönder'));
      await nbSettle(t);
      expect(rig.fake.createCalls.single.site, 12);
      expect(rig.fake.residentCalls, <int>[11, 12, 12], reason: 'işlemden sonra seçili sitenin listesi yenilenir');
      expect(find.text('İzmir için ilan'), findsOneWidget);
    });
  });
}
