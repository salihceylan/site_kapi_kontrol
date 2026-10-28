// Komşu Panosu (NeighborBoardView): YETKİ sınırları.
//
// Kapsam: erişimi olmayan kullanıcı (site listesi boş: modül kapalı / ilişki yok / süper kullanıcı) hiçbir istek atmaz;
// sakin (yazma yetkisi yok) yönetim uçlarına dokunmaz, yönetim denetimi çizmez, eylemler durum ve sahipliğe göre sınırlı;
// sunucu yönetime özel alanları ya da başkasının bekleyen ilanını yanlışlıkla gönderse bile arayüz bunları göstermez;
// yönetici ilan yazma / şikayet / geri çekme eylemi görmez; yetki SEÇİLİ siteye göre değişir; sunucu reddi (403 / 404 / 409)
// kullanıcıya sunucunun iletisiyle gösterilir ve HATA ASLA "Henüz ilan yok." demez.
// Gerçek servis üzerinden 401 / 403 / oturum yok davranışı: neighbor_board_boundary_network_test.dart. Menüde kimin
// "Komşu Panosu"nu görebileceği (ana kabuk kapısı): neighbor_board_boundary_home_page_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/neighbor_post.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';

import 'list_fixtures.dart' show tapFinder;
import 'neighbor_board_fixtures.dart';

void main() {
  group('erişimi olmayan kullanıcı (site listesi boş)', () {
    testWidgets('"açık değil" iletisi; hiçbir istek, düğme ya da sekme yok; elle yenileme de istek atmaz', (t) async {
      final rig = NeighborRig(posts: <Map<String, dynamic>>[nbPost(1)], sites: const <PeopleSite>[]);
      await rig.pump(t);
      expect(find.text('Komşu Panosu bu sitede açık değil.'), findsOneWidget);
      expect(find.text('Yeni ilan'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(Card), findsNothing);
      expect(find.text('Henüz ilan yok.'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await rig.state.reload();
      await nbSettle(t);
      expect(rig.fake.residentCalls, isEmpty);
      expect(rig.fake.managedCalls, isEmpty);
    });

    testWidgets('ekran açıkken erişim kalkarsa (site listesi boşalır) eski ilanlar kaybolur; erişim dönünce yeniden yüklenir', (t) async {
      final rig = NeighborRig(posts: <Map<String, dynamic>>[nbPost(1, title: 'Gizlenecek ilan')]);
      await rig.pump(t);
      expect(find.text('Gizlenecek ilan'), findsOneWidget);
      expect(rig.fake.residentCalls, <int>[11]);

      await rig.rebuild(t, sites: const <PeopleSite>[]);
      expect(find.text('Komşu Panosu bu sitede açık değil.'), findsOneWidget);
      expect(find.text('Gizlenecek ilan'), findsNothing);
      expect(find.text('Yeni ilan'), findsNothing);
      expect(rig.fake.residentCalls, <int>[11], reason: 'erişimsizken yeni istek yok');

      await rig.rebuild(t, sites: nbResidentSite);
      expect(find.text('Gizlenecek ilan'), findsOneWidget);
      expect(rig.fake.residentCalls, <int>[11, 11]);
    });

    testWidgets('seçili site listeden çıkarsa ilk siteye geçilir ve yönetim denetimleri kalkar (yetki yeni sitenin yetkisidir)', (t) async {
      final rig = NeighborRig(
        posts: <Map<String, dynamic>>[
          nbPost(1, title: 'Yönetilen sitenin bekleyeni', status: NeighborPostStatus.pending),
          nbPost(2, site: 12, title: 'Mavi Park ilanı'),
        ],
      );
      await rig.pump(t, sites: nbMixedSites);
      expect(find.byType(ChoiceChip), findsNWidgets(5));
      expect(find.text('Onayla'), findsOneWidget);

      await rig.rebuild(t, sites: const <PeopleSite>[PeopleSite(code: 12, name: 'Mavi Park')]);
      expect(find.byType(ChoiceChip), findsNothing, reason: 'yönetici yetkisi kalktı');
      expect(find.text('Onayla'), findsNothing);
      expect(find.text('Yönetilen sitenin bekleyeni'), findsNothing);
      expect(find.text('Yeni ilan'), findsOneWidget);
      expect(find.text('Mavi Park ilanı'), findsOneWidget);
      expect(rig.fake.residentCalls, <int>[12]);
    });
  });

  group('sakin (yazma yetkisi yok)', () {
    testWidgets('yönetim uçlarına dokunmaz, yönetim denetimi çizmez; "Geri çek" yalnız benim bekleyen / yayındaki ilanımda, "Şikayet et" yalnız başkasının yayındakinde', (
      t,
    ) async {
      final rig = NeighborRig(
        posts: <Map<String, dynamic>>[
          nbPost(1, title: 'Başkasının yayını'),
          nbPost(2, title: 'Benim yayınım', mine: true),
          nbPost(3, title: 'Benim bekleyenim', status: NeighborPostStatus.pending, mine: true),
          nbPost(4, title: 'Benim reddedilenim', status: NeighborPostStatus.rejected, mine: true, note: 'Uygun değil'),
          nbPost(5, title: 'Benim kaldırılanım', status: NeighborPostStatus.removed, mine: true, note: 'Kural dışı'),
          nbPost(6, title: 'Benim geri çektiğim', status: NeighborPostStatus.withdrawn, mine: true),
          nbPost(7, title: 'Başkasının bekleyeni', status: NeighborPostStatus.pending),
          nbPost(8, title: 'Başkasının reddedileni', status: NeighborPostStatus.rejected),
          nbPost(9, title: 'Başkasının kaldırılanı', status: NeighborPostStatus.removed),
        ],
      )..fake.ignoreVisibility = true; // sunucu hatası: görünürlük kuralı uygulanmamış
      await rig.pump(t);

      expect(rig.fake.managedCalls, isEmpty, reason: 'sakin yönetim uçlarını çağırmaz');
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('Yeni ilan'), findsOneWidget);
      expect(find.byType(Card), findsNWidgets(9));
      expect(find.text('Onayla'), findsNothing);
      expect(find.text('Reddet'), findsNothing);
      expect(find.text('Kaldır'), findsNothing);
      expect(find.text('Geri çek'), findsNWidgets(2), reason: 'benim yayındaki + benim bekleyen');
      expect(find.text('Şikayet et'), findsOneWidget, reason: 'yalnız başkasının YAYINDAKİ ilanı');
      expect(find.text('Yönetici notu: Uygun değil'), findsOneWidget);
      expect(find.text('Yönetici notu: Kural dışı'), findsOneWidget);
    });

    testWidgets('sunucu yönetime özel alanları (şikayet sayısı / gerekçeleri) yanlışlıkla gönderse bile sakine gösterilmez', (t) async {
      final rig = NeighborRig(
        posts: <Map<String, dynamic>>[
          nbPost(1, title: 'Şikayetli yayın', reasons: <String>['Reklam içeriyor', 'Hakaret var']),
          nbPost(2, title: 'Benim şikayetli ilanım', mine: true, reasons: <String>['Gürültü şikayeti']),
        ],
      )..fake.leakManagerFields = true;
      await rig.pump(t);
      expect(find.byType(Card), findsNWidgets(2));
      expect(find.textContaining('şikayet:'), findsNothing);
      expect(find.textContaining('Reklam içeriyor'), findsNothing);
      expect(find.textContaining('Hakaret var'), findsNothing);
      expect(find.textContaining('Gürültü şikayeti'), findsNothing);
    });
  });

  group('yönetici (yazma yetkili site)', () {
    testWidgets('ilan yazma / şikayet / geri çekme yok; düğmeler yalnız duruma göre: bekleyen Onayla+Reddet, yayındaki Kaldır, diğerleri düğmesiz', (t) async {
      final rig = NeighborRig(
        sites: nbManagerSite,
        posts: <Map<String, dynamic>>[
          nbPost(1, title: 'Bekleyen A', status: NeighborPostStatus.pending),
          nbPost(2, title: 'Bekleyen B', status: NeighborPostStatus.pending),
          nbPost(3, title: 'Şikayetli yayın', reasons: <String>['Reklam', 'Hakaret']),
          nbPost(4, title: 'Temiz yayın'),
          nbPost(5, title: 'Reddedilen ilan', status: NeighborPostStatus.rejected, note: 'Uygunsuz'),
          nbPost(6, title: 'Kaldırılan ilan', status: NeighborPostStatus.removed, note: 'Kural dışı'),
        ],
      );
      await rig.pump(t);

      // (sekme, kart, Onayla, Reddet, Kaldır)
      final tabs = <(String, int, int, int, int)>[
        ('Onay bekleyen', 2, 2, 2, 0),
        ('Şikayetli', 1, 0, 0, 1),
        ('Yayındaki', 2, 0, 0, 2),
        ('Reddedilen', 1, 0, 0, 0),
        ('Kaldırılan', 1, 0, 0, 0),
      ];
      for (final (label, cards, approve, reject, remove) in tabs) {
        await tapFinder(t, find.text(label));
        await nbSettle(t);
        expect(find.byType(Card), findsNWidgets(cards), reason: label);
        expect(find.text('Onayla'), findsNWidgets(approve), reason: label);
        expect(find.text('Reddet'), findsNWidgets(reject), reason: label);
        expect(find.text('Kaldır'), findsNWidgets(remove), reason: label);
        expect(find.text('Yeni ilan'), findsNothing, reason: label);
        expect(find.text('Şikayet et'), findsNothing, reason: label);
        expect(find.text('Geri çek'), findsNothing, reason: label);
      }
      expect(rig.fake.residentCalls, isEmpty, reason: 'yönetici sakin ucunu çağırmaz');
      expect(rig.fake.managedCalls.map((c) => c.status).toList(), <String>['pending', 'pending', 'reported', 'published', 'rejected', 'removed']);
      expect(find.text('Yönetici notu: Kural dışı'), findsOneWidget);
    });

    testWidgets('şikayet sayısı ve gerekçeleri yöneticide görünür; şikayeti olmayan ilanda satır yok', (t) async {
      final rig = NeighborRig(
        sites: nbManagerSite,
        posts: <Map<String, dynamic>>[
          nbPost(1, title: 'Şikayetli yayın', reasons: <String>['Reklam içeriyor', 'Hakaret var']),
          nbPost(2, title: 'Temiz yayın'),
        ],
      );
      await rig.pump(t);
      await tapFinder(t, find.text('Yayındaki'));
      await nbSettle(t);
      expect(find.byType(Card), findsNWidgets(2));
      expect(find.text('2 şikayet: Reklam içeriyor / Hakaret var'), findsOneWidget);
      expect(find.textContaining('şikayet:'), findsOneWidget, reason: 'şikayeti olmayan ilanda satır çizilmez');
    });

    testWidgets('Onayla gerekçe istemez; Kaldır gerekçesiz gönderilmez, gerekçeyle gider; her işlemden sonra liste yenilenir', (t) async {
      final rig = NeighborRig(
        sites: nbManagerSite,
        posts: <Map<String, dynamic>>[
          nbPost(1, title: 'Bekleyen A', status: NeighborPostStatus.pending),
          nbPost(2, title: 'Bekleyen B', status: NeighborPostStatus.pending),
        ],
      );
      await rig.pump(t);

      await tapFinder(t, find.text('Onayla')); // en yeni (id 2)
      await nbSettle(t);
      expect(rig.fake.decideCalls, <({int site, int id, String action, String? note})>[(site: 11, id: 2, action: 'approve', note: null)]);
      expect(find.text('İlan yayınlandı.'), findsOneWidget);
      expect(find.text('Bekleyen B'), findsNothing, reason: 'yayınlandı, bekleyenler listesinden çıktı');
      expect(find.text('Bekleyen A'), findsOneWidget);
      expect(rig.fake.managedCalls.where((c) => c.status == 'pending'), hasLength(2));
      await nbExpireSnack(t);

      await tapFinder(t, find.text('Yayındaki'));
      await nbSettle(t);
      expect(find.text('Bekleyen B'), findsOneWidget);
      await tapFinder(t, find.text('Kaldır'));
      expect(nbInDialog('Kaldır'), findsOneWidget);
      await t.enterText(nbDialogField(0), '   ');
      await t.pump();
      await t.tap(nbInDialog('Gönder'));
      await nbSettle(t);
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'gerekçesiz kaldırma olmaz');
      expect(rig.fake.decideCalls, hasLength(1));

      await t.enterText(nbDialogField(0), 'Süresi geçmiş duyuru');
      await t.pump();
      await t.tap(nbInDialog('Gönder'));
      await nbSettle(t);
      expect(rig.fake.decideCalls.last, (site: 11, id: 2, action: 'remove', note: 'Süresi geçmiş duyuru'));
      expect(find.text('İlan kaldırıldı.'), findsOneWidget);
      expect(find.text('Bekleyen B'), findsNothing, reason: 'kaldırıldı, yayındakiler listesinden çıktı');
    });
  });

  group('yetki seçili siteye göre değişir', () {
    testWidgets('yönetici siteden sakin siteye ve geri: denetimler ve uç noktalar siteyle birlikte değişir', (t) async {
      final rig = NeighborRig(
        posts: <Map<String, dynamic>>[
          nbPost(1, title: 'Yönetilen sitenin bekleyeni', status: NeighborPostStatus.pending),
          nbPost(2, site: 12, title: 'Mavi Park ilanı'),
        ],
      );
      await rig.pump(t, sites: nbMixedSites);
      expect(find.byType(ChoiceChip), findsNWidgets(5));
      expect(find.text('Yeni ilan'), findsNothing);
      expect(find.text('Yönetilen sitenin bekleyeni'), findsOneWidget);
      expect(find.text('Onayla'), findsOneWidget);

      await tapFinder(t, find.byType(DropdownButton<int>));
      await nbSettle(t);
      await t.tap(find.text('Mavi Park').last);
      await nbSettle(t);
      expect(find.byType(ChoiceChip), findsNothing, reason: '12 numaralı sitede yazma yetkisi yok');
      expect(find.text('Yeni ilan'), findsOneWidget);
      expect(find.text('Mavi Park ilanı'), findsOneWidget);
      expect(find.text('Yönetilen sitenin bekleyeni'), findsNothing);
      expect(find.text('Onayla'), findsNothing);
      expect(rig.fake.residentCalls, <int>[12]);

      await tapFinder(t, find.byType(DropdownButton<int>));
      await nbSettle(t);
      await t.tap(find.text('Gül Sitesi').last);
      await nbSettle(t);
      expect(find.byType(ChoiceChip), findsNWidgets(5));
      expect(find.text('Yeni ilan'), findsNothing);
      expect(find.text('Yönetilen sitenin bekleyeni'), findsOneWidget);
      expect(rig.fake.managedCalls.map((c) => c.site).toList(), <int>[11, 11]);
      expect(rig.fake.residentCalls, <int>[12], reason: 'yönetilen sitede sakin ucu çağrılmaz');
    });
  });

  group('sunucu reddi: iletisi gösterilir, hata "Henüz ilan yok." demez', () {
    final listCases = <(String, bool, ApiException)>[
      ('sakin: 404 POST_NOT_FOUND (siteyle ilişkisi yok)', false, FakeNeighborService.postNotFound()),
      ('sakin: 403 MODULE_DISABLED (modül kapalı)', false, FakeNeighborService.moduleOff()),
      ('yönetici: 403 FORBIDDEN_ROLE (kurul üyesi ya da görevli)', true, FakeNeighborService.forbiddenRole()),
      ('yönetici: 403 FORBIDDEN_SITE (başka sitenin yöneticisi)', true, FakeNeighborService.forbiddenSite()),
    ];
    for (final (name, manager, error) in listCases) {
      testWidgets('liste: $name', (t) async {
        final rig = NeighborRig(
          sites: manager ? nbManagerSite : nbResidentSite,
          posts: <Map<String, dynamic>>[
            nbPost(1, title: 'Erişilebilir ilan', status: manager ? NeighborPostStatus.pending : NeighborPostStatus.published),
          ],
        );
        rig.fake.failures[manager ? 'listManaged' : 'listResident'] = <Object>[error];
        await rig.pump(t);

        expect(find.text(error.message), findsOneWidget);
        expect(find.text('Henüz ilan yok.'), findsNothing, reason: 'hata "ilan yok" demez');
        expect(find.byType(Card), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        final message = t.widget<Text>(find.text(error.message));
        expect(message.style?.color, Theme.of(t.element(find.text(error.message))).colorScheme.error, reason: 'hata rengi');

        // Yetki verilince / düzelince elle yenileme çalışır ve hata kalkar.
        await rig.state.reload();
        await nbSettle(t);
        expect(find.text(error.message), findsNothing);
        expect(find.text('Erişilebilir ilan'), findsOneWidget);
      });
    }

    // (ad, yönetici mi, sunucunun reddi, başarı iletisi, eylem)
    final actionCases = <(String, bool, ApiException, String, Future<void> Function(WidgetTester t))>[
      (
        'şikayet: 409 OWN_POST',
        false,
        FakeNeighborService.error(409, 'OWN_POST', 'Kendi ilanınızı şikayet edemezsiniz.'),
        'Şikayetiniz yöneticiye iletildi.',
        (t) async {
          await tapFinder(t, find.text('Şikayet et'));
          await t.enterText(nbDialogField(0), 'Reklam');
          await t.pump();
          await t.tap(nbInDialog('Gönder'));
        },
      ),
      (
        'geri çekme: 404 POST_NOT_FOUND',
        false,
        FakeNeighborService.postNotFound(),
        'İlan geri çekildi.',
        (t) async {
          await tapFinder(t, find.text('Geri çek'));
        },
      ),
      (
        'ilan yazma: 409 PENDING_LIMIT',
        false,
        FakeNeighborService.error(409, 'PENDING_LIMIT', 'Onay bekleyen en fazla 5 ilanınız olabilir.'),
        'İlanınız yönetici onayına gönderildi.',
        (t) async {
          await tapFinder(t, find.text('Yeni ilan'));
          await t.enterText(nbDialogField(0), 'Çocuk bahçesi');
          await t.enterText(nbDialogField(1), 'Cumartesi sabahı bahçede buluşalım.');
          await t.pump();
          await t.tap(nbInDialog('Onaya gönder'));
        },
      ),
      (
        'onaylama: 409 POST_STATE',
        true,
        FakeNeighborService.postState(),
        'İlan yayınlandı.',
        (t) async {
          await tapFinder(t, find.text('Onayla'));
        },
      ),
      (
        'onaylama: 403 FORBIDDEN_SITE (yetkisi bu sırada alınmış yönetici)',
        true,
        FakeNeighborService.forbiddenSite(),
        'İlan yayınlandı.',
        (t) async {
          await tapFinder(t, find.text('Onayla'));
        },
      ),
    ];
    for (final (name, manager, error, success, act) in actionCases) {
      testWidgets('eylem: $name -> iletisi snackbar\'da, başarı iletisi yok, liste yeniden yüklenir', (t) async {
        final rig = NeighborRig(
          sites: manager ? nbManagerSite : nbResidentSite,
          posts: <Map<String, dynamic>>[
            if (manager)
              nbPost(1, status: NeighborPostStatus.pending)
            else if (name.startsWith('geri çekme'))
              nbPost(1, mine: true)
            else
              nbPost(1),
          ],
        );
        final op = name.startsWith('şikayet')
            ? 'report'
            : name.startsWith('geri çekme')
            ? 'withdraw'
            : name.startsWith('ilan yazma')
            ? 'create'
            : 'decide';
        rig.fake.failures[op] = <Object>[error];
        await rig.pump(t);
        final before = manager ? rig.fake.managedCalls.length : rig.fake.residentCalls.length;

        await act(t);
        await nbSettle(t);

        expect(find.text(error.message), findsOneWidget);
        expect(find.text(success), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(manager ? rig.fake.managedCalls.length : rig.fake.residentCalls.length, before + 1, reason: 'reddedilse de liste yeniden çekilir');
        expect(find.byType(Card), findsOneWidget, reason: 'liste yenilemesi başarılı: ilan hâlâ listede');
      });
    }
  });
}
