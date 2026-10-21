// Platform Faz 2a: "Kişiler" ekranı (PeopleView): Kişiler | Daireler | Araçlar sekmeleri.
//
// AGENTS.md kural 6: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema; yükleniyor / boş / hata / dolu
// durumlar taşmaz. Kural 7: yenile düğmesi ve `reload()` (aşağı çekip yenileme) çalışır; işlem sonrası
// liste otomatik yenilenir. Yarış korumaları: art arda arama, süzgeç değişimi sırasında "Daha fazla
// yükle", site değişimi.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/people_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/apartment_crm_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/person_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/vehicle_card.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart';
import 'people_fixtures.dart';

/// Araç kaldırma düğmeleri: "{plaka} plakalı aracı kaldır" ipucu/anlamı.
final Finder _removeButtons = find.byWidgetPredicate(
  (w) => w is IconButton && (w.tooltip ?? '').endsWith('plakalı aracı kaldır'),
);
Finder _removeFor(String plate) => find.byTooltip('$plate plakalı aracı kaldır');

const List<PeopleSite> _board = <PeopleSite>[PeopleSite(code: 12, name: 'Mavi Park')];

Future<GlobalKey<PeopleViewState>> _pump(
  WidgetTester t,
  PeopleFakeAuth auth, {
  double width = 400,
  double height = 1600,
  double scale = 1.0,
  bool dark = false,
  bool manage = true,
  List<PeopleSite> readOnly = const <PeopleSite>[],
}) async {
  final key = GlobalKey<PeopleViewState>();
  await pumpList(
    t,
    PeopleView(key: key, authService: auth, manageSites: manage, readOnlySites: readOnly),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  // Önce siteler gelir, sekme sonra kurulur ve kendi verisini çeker: iki aşama.
  await settleFor(t, 100);
  await settleFor(t, 100);
  return key;
}

Finder _tab(int index) => find.byKey(ValueKey<String>('people_tab_$index'));

Future<void> _openTab(WidgetTester t, int index) async {
  await tapFinder(t, _tab(index));
  await settleFor(t);
}

Future<void> _type(WidgetTester t, String key, String text) async {
  final field = find.byKey(ValueKey<String>(key));
  await t.ensureVisible(field);
  await t.pump();
  await t.enterText(field, text);
  await t.pump();
}

/// Arama gecikmesi (350 ms) + yanıt.
Future<void> _debounce(WidgetTester t) async {
  await t.pump(const Duration(milliseconds: 400));
  await t.pump();
}

Future<void> _choose(WidgetTester t, Finder field, String label) async {
  await t.ensureVisible(field);
  await t.pump();
  await t.tap(field);
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  await t.tap(find.text(label).last);
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

/// 5 aktif kişi (sayfalama testleri için).
PeopleFakeAuth _many({int count = 5}) {
  final auth = PeopleFakeAuth.seeded();
  auth.peopleJson.clear();
  for (var i = 1; i <= count; i++) {
    auth.peopleJson[i] = pplPersonJson(
      i,
      'Kişi $i',
      apts: <PplApt>[(300 + i, 'A Blok - $i', ResidencyRelation.resident)],
    );
  }
  return auth;
}

void main() {
  group('taşma matrisi', () {
    listMatrix('Kişiler sekmesi: dolu görünüm', (t, w, h, s, dark) async {
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);

      expect(find.byType(PersonCard), findsNWidgets(2), reason: 'varsayılan: yalnız aktif kişiler');
      expect(find.text('Ayşe Yılmaz'), findsOneWidget);
      expect(find.text('Mehmet Demir'), findsOneWidget);
      expect(find.text('Zeynep Kaya'), findsNothing);
      expect(find.text('Hesabı var'), findsOneWidget);
      expect(find.text('Malik'), findsOneWidget);
      expect(find.text('Kiracı'), findsOneWidget);
      expect(find.text('A Blok - 5'), findsOneWidget);
      expect(find.text('1 araç'), findsOneWidget);
      expect(find.text('+90 555 111 22 33'), findsOneWidget);
      expect(find.text('Kişi Ekle'), findsOneWidget);
      expect(find.text('Kişi ara'), findsOneWidget);
      expect(find.byTooltip('Yenile'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        expect(_tab(i), findsOneWidget);
      }
      expect(find.text('Yönetim kurulu üyesi olarak kayıtları yalnızca görüntüleyebilirsiniz.'), findsNothing);
    });

    listMatrix('Kişiler sekmesi: yükleniyor', (t, w, h, s, dark) async {
      final auth = PeopleFakeAuth.seeded()..peopleGates.add(Completer<void>());
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.byType(PersonCard), findsNothing);
      expect(find.text('Henüz kişi kaydı yok.'), findsNothing);
    });

    listMatrix('Kişiler sekmesi: boş', (t, w, h, s, dark) async {
      await _pump(t, PeopleFakeAuth(), width: w, height: h, scale: s, dark: dark);
      expect(find.byType(EmptyCard), findsOneWidget);
      expect(find.text('Henüz kişi kaydı yok.'), findsOneWidget);
      expect(find.text('Kişi Ekle ile ilk kaydı oluşturabilirsiniz.'), findsOneWidget);
    });

    listMatrix('Kişiler sekmesi: hata (InlineNotice + Tekrar Dene), "kayıt yok" yazmaz', (t, w, h, s, dark) async {
      final auth = PeopleFakeAuth.seeded()
        ..peopleError = ApiException('Bu işlem için yetkiniz yok.', statusCode: 403, code: 'FORBIDDEN_ROLE');
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(InlineNotice), findsOneWidget);
      expect(find.text('Bu işlem için yetkiniz yok.'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.text('Henüz kişi kaydı yok.'), findsNothing);
      expect(find.byType(PersonCard), findsNothing);
    });

    listMatrix('Daireler sekmesi: dolu görünüm (alan çipleri, malik / kiracı, blok süzgeci)', (t, w, h, s, dark) async {
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      await _openTab(t, 1);

      expect(find.byType(ApartmentCrmCard), findsNWidgets(3));
      expect(find.text('A Blok - 5'), findsOneWidget);
      expect(find.text('Kat 2'), findsOneWidget);
      expect(find.text('3+1'), findsOneWidget);
      expect(find.text('Brüt 120,5 m²'), findsOneWidget);
      expect(find.text('Net 100 m²'), findsOneWidget);
      expect(find.text('Arsa payı 35/1000'), findsOneWidget);
      expect(find.text('Malik: Ayşe Yılmaz'), findsOneWidget);
      expect(find.text('Kiracı: Mehmet Demir'), findsOneWidget);
      expect(find.text('Malik: kayıtlı değil'), findsNWidgets(2));
      expect(find.text('1 güncel sakin'), findsNWidgets(2));
      expect(find.text('Daire ara'), findsOneWidget);
      expect(find.text('Blok'), findsOneWidget, reason: 'iki blok: süzgeç görünür');
    });

    listMatrix('Araçlar sekmesi: dolu görünüm (kaldır düğmeleri yazma yetkisiyle)', (t, w, h, s, dark) async {
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      await _openTab(t, 2);

      expect(find.byType(VehicleCard), findsNWidgets(2));
      expect(find.text('34 ABC 123'), findsOneWidget);
      expect(find.text('06 XYZ 789'), findsOneWidget);
      expect(find.text('Araç Ekle'), findsOneWidget);
      expect(_removeButtons, findsNWidgets(2));
      expect(_removeFor('34 ABC 123'), findsOneWidget);
      expect(find.text('Araç ara'), findsOneWidget);
    });

    listMatrix('kurul üyesi: HİÇBİR yazma düğmesi yok (üç sekme)', (t, w, h, s, dark) async {
      final auth = PeopleFakeAuth.seeded(role: UserRole.apartmentOwner);
      await _pump(
        t,
        auth,
        width: w,
        height: h,
        scale: s,
        dark: dark,
        manage: false,
        readOnly: const <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi')],
      );
      expect(find.text('Yönetim kurulu üyesi olarak kayıtları yalnızca görüntüleyebilirsiniz.'), findsOneWidget);
      expect(find.byType(PersonCard), findsNWidgets(2));
      expect(find.text('Kişi Ekle'), findsNothing);

      await _openTab(t, 1);
      expect(find.byType(ApartmentCrmCard), findsNWidgets(3));
      await _openTab(t, 2);
      expect(find.byType(VehicleCard), findsNWidgets(2));
      expect(find.text('Araç Ekle'), findsNothing);
      expect(_removeButtons, findsNothing);
      expect(auth.listSitesCalls, 0, reason: 'kurul üyesi yönetim site listesini çağırmaz');
    });
  });

  group('site seçimi ve boş / hata durumları', () {
    testWidgets('site yok: "Kayıtlı site bulunamadı."', (t) async {
      final auth = PeopleFakeAuth(sites: const []);
      await _pump(t, auth);
      expect(find.text('Kayıtlı site bulunamadı.'), findsOneWidget);
      expect(find.byType(PersonCard), findsNothing);
    });

    testWidgets('yalnız onaylı siteler listelenir; tek sitede seçici yerine site çipi', (t) async {
      final auth = PeopleFakeAuth(
        sites: <SiteRecord>[pplSite(11, 'Gül Sitesi'), pplSite(13, 'Onaysız', approval: 'pending')],
        people: <int, Map<String, dynamic>>{},
      );
      await _pump(t, auth);
      expect(find.text('Gül Sitesi'), findsOneWidget);
      expect(find.text('Site'), findsNothing, reason: 'tek site: açılır liste yok');
      expect(auth.peopleCalls.single.site, 11);
    });

    testWidgets('site listesi hatası: InlineNotice + Tekrar Dene; tekrar denenince yüklenir', (t) async {
      final auth = PeopleFakeAuth.seeded()
        ..listSitesError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      await _pump(t, auth);
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsOneWidget);
      expect(find.byType(PersonCard), findsNothing);
      expect(find.text('Kayıtlı site bulunamadı.'), findsNothing);

      auth.listSitesError = null;
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.byType(PersonCard), findsNWidgets(2));
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsNothing);
    });

    testWidgets('site yüklenirken iskelet; sonra liste', (t) async {
      final auth = PeopleFakeAuth.seeded()..sitesGate = Completer<void>();
      await _pump(t, auth);
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.text('Kayıtlı site bulunamadı.'), findsNothing);
      auth.sitesGate!.complete();
      await settleFor(t);
      expect(find.byType(PersonCard), findsNWidgets(2));
    });

    testWidgets('çok siteli yönetici: Site seçici; kurul üyesi olunan site salt okunur, yönetilen yazılabilir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth, readOnly: _board);
      expect(find.text('Site'), findsOneWidget);
      expect(find.text('Kişi Ekle'), findsOneWidget);

      await _choose(t, find.byType(DropdownButtonFormField<int>).first, 'Mavi Park (12)');
      expect(auth.peopleCalls.last.site, 12);
      expect(find.text('Kişi Ekle'), findsNothing, reason: 'kurul üyesi olunan sitede yazma yok');
      expect(find.text('Yönetim kurulu üyesi olarak kayıtları yalnızca görüntüleyebilirsiniz.'), findsOneWidget);

      await _choose(t, find.byType(DropdownButtonFormField<int>).first, 'Gül Sitesi (11)');
      expect(auth.peopleCalls.last.site, 11);
      expect(find.text('Kişi Ekle'), findsOneWidget);
    });

    testWidgets('site değişince eski sitenin geç gelen yanıtı yeni sitenin listesini EZMEZ', (t) async {
      final auth = PeopleFakeAuth.seeded();
      auth.sites = <SiteRecord>[pplSite(11, 'Gül Sitesi'), pplSite(12, 'Mavi Park')];
      final gate = Completer<void>();
      // Açılışta (Gül Sitesi) yanıt kapıda bekler; kapı açılınca eski site verisi teslim edilir.
      auth.peopleGates.add(gate);
      await _pump(t, auth);
      expect(find.byType(ListSkeleton), findsOneWidget);

      // İkinci site: kayıtlar değişti.
      auth.peopleJson
        ..clear()
        ..[7] = pplPersonJson(7, 'Mavi Parklı Kişi');
      await _choose(t, find.byType(DropdownButtonFormField<int>).first, 'Mavi Park (12)');
      expect(find.text('Mavi Parklı Kişi'), findsOneWidget);

      gate.complete();
      await settleFor(t);
      expect(find.text('Mavi Parklı Kişi'), findsOneWidget);
      expect(find.text('Ayşe Yılmaz'), findsNothing, reason: 'eski sitenin yanıtı yazılmadı');
      expect(find.byType(PersonCard), findsOneWidget);
    });
  });

  group('Kişiler sekmesi davranışı', () {
    testWidgets('ilk istek: aktif kişiler, limit 50, offset 0, arama yok', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      final call = auth.peopleCalls.single;
      expect(call.site, 11);
      expect(call.status, 'active');
      expect(call.limit, 50);
      expect(call.offset, 0);
      expect(call.query, '');
      expect(call.relation, isNull);
      expect(auth.listSitesCalls, 1);
    });

    testWidgets('arama: duraksayınca sunucuya gider, liste süzülür; temizlenince geri gelir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      await _type(t, 'people_search', 'meh');
      expect(auth.peopleCalls, hasLength(1), reason: 'yazarken beklenir (350 ms)');
      await _debounce(t);

      expect(auth.peopleCalls.last.query, 'meh');
      expect(find.byType(PersonCard), findsOneWidget);
      expect(find.text('Mehmet Demir'), findsOneWidget);

      await tapFinder(t, find.byTooltip('Aramayı temizle'));
      await _debounce(t);
      expect(auth.peopleCalls.last.query, '');
      expect(find.byType(PersonCard), findsNWidgets(2));
    });

    testWidgets('aramada sonuç yoksa "Bu arama ve süzgeç için kişi bulunamadı."', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      await _type(t, 'people_search', 'yokböyleibiri');
      await _debounce(t);
      expect(find.text('Bu arama ve süzgeç için kişi bulunamadı.'), findsOneWidget);
      expect(find.text('Henüz kişi kaydı yok.'), findsNothing);
    });

    testWidgets('hızlı art arda arama: eski yanıt (geç gelse de) yenisini EZMEZ', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      final first = Completer<void>();
      final second = Completer<void>();
      auth.peopleGates.addAll(<Completer<void>>[first, second]);

      await _type(t, 'people_search', 'ayş');
      await _debounce(t);
      await _type(t, 'people_search', 'meh');
      await _debounce(t);
      expect(auth.peopleCalls.map((c) => c.query).toList(), <String?>['', 'ayş', 'meh']);

      second.complete();
      await settleFor(t);
      expect(find.text('Mehmet Demir'), findsOneWidget);
      expect(find.byType(PersonCard), findsOneWidget);

      first.complete(); // eski aramanın yanıtı geç gelir
      await settleFor(t);
      expect(find.text('Mehmet Demir'), findsOneWidget);
      expect(find.text('Ayşe Yılmaz'), findsNothing, reason: 'eski arama sonucu yenisini ezmedi');
      expect(find.byType(PersonCard), findsOneWidget);
    });

    testWidgets('İlişki süzgeci: ilişki sunucuya gider; Durum süzgeci: Eski sakinler listelenir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);

      await _choose(t, find.byKey(const ValueKey<String>('people_relation_')), 'Kiracı');
      expect(auth.peopleCalls.last.relation, ResidencyRelation.tenant);
      expect(find.byType(PersonCard), findsOneWidget);
      expect(find.text('Mehmet Demir'), findsOneWidget);

      await _choose(t, find.byKey(const ValueKey<String>('people_relation_tenant')), 'Tümü');
      expect(auth.peopleCalls.last.relation, isNull);

      await _choose(t, find.byKey(const ValueKey<String>('people_status_active')), 'Eski sakinler');
      expect(auth.peopleCalls.last.status, 'inactive');
      expect(find.text('Zeynep Kaya'), findsOneWidget);
      expect(find.text('Eski sakin'), findsWidgets);
      expect(find.text('Ayşe Yılmaz'), findsNothing);

      await _choose(t, find.byKey(const ValueKey<String>('people_status_inactive')), 'Tümü');
      expect(auth.peopleCalls.last.status, 'all');
      expect(find.byType(PersonCard), findsNWidgets(3));
    });

    testWidgets('Daha fazla yükle: sonraki sayfa offset ile eklenir, son sayfada düğme kalkar', (t) async {
      final auth = _many()..maxPage = 2;
      await _pump(t, auth);
      expect(find.byType(PersonCard), findsNWidgets(2));
      expect(find.text('Daha fazla yükle'), findsOneWidget);

      await tapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(auth.peopleCalls.last.offset, 2);
      expect(find.byType(PersonCard), findsNWidgets(4));

      await tapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(auth.peopleCalls.last.offset, 4);
      expect(find.byType(PersonCard), findsNWidgets(5));
      expect(find.text('Daha fazla yükle'), findsNothing);
    });

    testWidgets('Daha fazla yükle hatası: mesaj + Tekrar Dene, liste kalır, tekrar denenince devam eder', (t) async {
      final auth = _many()..maxPage = 2;
      await _pump(t, auth);
      auth.peopleError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');

      await tapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsOneWidget);
      expect(find.byType(PersonCard), findsNWidgets(2));

      auth.peopleError = null;
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.byType(PersonCard), findsNWidgets(4));
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsNothing);
    });

    testWidgets('"Daha fazla yükle" sürerken arama değişirse eski sayfa EKLENMEZ ve bayrak sıfırlanır', (t) async {
      final auth = _many()..maxPage = 2;
      await _pump(t, auth);
      final gate = Completer<void>();
      auth.peopleGates.add(gate);

      await tapText(t, 'Daha fazla yükle'); // offset 2 isteği kapıda bekler
      await _type(t, 'people_search', 'Kişi 1');
      await _debounce(t); // yeni arama (kapısız) ilk sayfayı yeniden çeker
      expect(find.byType(PersonCard), findsOneWidget);

      gate.complete(); // eski (2. sayfa) yanıt geç gelir
      await settleFor(t);
      expect(find.byType(PersonCard), findsOneWidget, reason: 'eski sayfa aramanın sonucuna eklenmedi');
      expect(
        find.descendant(of: find.byType(PersonCard), matching: find.text('Kişi 1')),
        findsOneWidget,
      );
      expect(find.text('Daha fazla yükle'), findsNothing,
          reason: 'bayrak yeni aramaya göre: tek sonuç, devam yok');
    });

    testWidgets('yenile düğmesi listeyi yeniden çeker; yenileme sürerken eski liste ekranda kalır', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      expect(auth.peopleCalls, hasLength(1));

      final gate = Completer<void>();
      auth.peopleGates.add(gate);
      await t.tap(find.byTooltip('Yenile'));
      await t.pump();
      expect(auth.peopleCalls, hasLength(2));
      expect(find.byType(PersonCard), findsNWidgets(2), reason: 'iskelet değil, eski liste kalır');
      expect(find.byType(ListSkeleton), findsNothing);

      gate.complete();
      await settleFor(t);
      expect(find.byType(PersonCard), findsNWidgets(2));
    });

    testWidgets('reload() (aşağı çekip yenileme): siteler + görünen sekme yeniden çekilir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      final key = await _pump(t, auth);
      final sitesBefore = auth.listSitesCalls;
      final peopleBefore = auth.peopleCalls.length;

      auth.peopleJson[9] = pplPersonJson(9, 'Yeni Eklenen');
      await key.currentState!.reload();
      await settleFor(t);
      expect(auth.listSitesCalls, sitesBefore + 1);
      expect(auth.peopleCalls.length, peopleBefore + 1);
      expect(find.text('Yeni Eklenen'), findsOneWidget);
    });

    testWidgets('hata sonrası Tekrar Dene listeyi getirir; hata varken "kayıt yok" yazılmaz', (t) async {
      final auth = PeopleFakeAuth.seeded()..peopleError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      await _pump(t, auth);
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsOneWidget);
      expect(find.text('Henüz kişi kaydı yok.'), findsNothing);

      auth.peopleError = null;
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.byType(PersonCard), findsNWidgets(2));
    });

    testWidgets('yenileme hatası eski listeyi silmez: liste + hata bildirimi birlikte', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      auth.peopleError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      await t.tap(find.byTooltip('Yenile'));
      await settleFor(t);
      expect(find.byType(PersonCard), findsNWidgets(2));
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsOneWidget);
    });

    testWidgets('süper kullanıcı: yazma yetkisi var (Kişi Ekle)', (t) async {
      final auth = PeopleFakeAuth.seeded(role: UserRole.superUser);
      await _pump(t, auth);
      expect(find.text('Kişi Ekle'), findsOneWidget);
    });

    testWidgets('kişi kartına dokununca kişi kartı penceresi açılır ve ayrıntı çekilir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      await tapText(t, 'Ayşe Yılmaz');
      await settleFor(t);
      expect(auth.getPersonCalls, <int>[1]);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Bilgiler'), findsOneWidget);
    });
  });

  group('okuma hız sınırı ve sayfalama kararı (sunucu düzeltmeleri)', () {
    testWidgets('aynı sorgu tekrar çağrılmaz: gecikme sayacı + Enter tek istek; aynı süzgeci yeniden seçmek istek atmaz', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      expect(auth.peopleCalls, hasLength(1));

      await _type(t, 'people_search', 'meh');
      await _debounce(t);
      expect(auth.peopleCalls, hasLength(2));

      // Klavyeden gönder: aynı sorgu zaten çalıştı.
      await t.testTextInput.receiveAction(TextInputAction.search);
      await settleFor(t);
      expect(auth.peopleCalls, hasLength(2), reason: 'aynı sorgu ikinci kez gönderilmedi');

      // Aynı metni yeniden yazmak (boşluk eklemek) sorguyu değiştirmez.
      await _type(t, 'people_search', ' meh ');
      await _debounce(t);
      expect(auth.peopleCalls, hasLength(2));
    });

    testWidgets('sekme değişimi gereksiz istek atmaz (kurulu sekme durumunu korur)', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      await _openTab(t, 1);
      await _openTab(t, 2);
      await _openTab(t, 0);
      await _openTab(t, 2);
      expect(auth.peopleCalls, hasLength(1));
      expect(auth.apartmentCalls, hasLength(1));
      expect(auth.vehicleCalls, hasLength(1));
    });

    testWidgets('sonraki sayfa kararı total ve offset\'e göredir: sunucu limiti kıssa da devam edilir, boş sayfa döngüye girmez', (t) async {
      final auth = PeopleFakeAuth.seeded()..totalOverride = 9;
      await _pump(t, auth);
      // İstenen limit 50, sunucu 2 kayıt verdi; total 9: hâlâ devam var.
      expect(auth.peopleCalls.single.limit, 50);
      expect(find.byType(PersonCard), findsNWidgets(2));
      expect(find.text('Daha fazla yükle'), findsOneWidget);

      await tapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(auth.peopleCalls.last.offset, 2);
      expect(find.byType(PersonCard), findsNWidgets(2), reason: 'sayfa boş geldi');
      expect(find.text('Daha fazla yükle'), findsNothing,
          reason: 'boş sayfa sonrası devam edilmez (sonsuz döngü yok)');
    });

    testWidgets('yinelenen kayıt ayıklansa da offset sunucunun saydığı gibi ilerler', (t) async {
      final auth = _many()..maxPage = 2;
      await _pump(t, auth);
      await tapText(t, 'Daha fazla yükle');
      await settleFor(t);
      await tapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(auth.peopleCalls.map((c) => c.offset).toList(), <int>[0, 2, 4]);
    });
  });

  group('Kişi Ekle: giriş bilgisi e-postası sonucu (credentials_sent)', () {
    Future<void> addPerson(WidgetTester t, PeopleFakeAuth auth) async {
      await _pump(t, auth);
      await tapText(t, 'Kişi Ekle');
      await _type(t, 'person_name', 'Yeni Kişi');
      await _type(t, 'person_email', 'yeni@example.com');
      await tapText(t, 'Kaydet');
      await settleFor(t);
    }

    testWidgets('true: "Giriş bilgileri e-postayla gönderildi"', (t) async {
      final auth = PeopleFakeAuth.seeded()..nextCredentialsSent = true;
      await addPerson(t, auth);
      expect(find.text('Kişi eklendi. Giriş bilgileri e-postayla gönderildi.'), findsOneWidget);
      expect(auth.createPersonCalls, hasLength(1));
      expect(find.text('Yeni Kişi'), findsOneWidget, reason: 'liste otomatik yenilendi');
    });

    testWidgets('false: "E-posta gönderilemedi" uyarısı', (t) async {
      final auth = PeopleFakeAuth.seeded()..nextCredentialsSent = false;
      await addPerson(t, auth);
      expect(
        find.text(
          "Kişi eklendi ve hesap açıldı; ancak giriş bilgisi e-postası gönderilemedi. PIN saklanmadığı için Daireler ekranından PIN'i sıfırlayın.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('null + adres: gönderim sürüyor (sunucu ~8 sn beklemedi), hesap açıldı', (t) async {
      final auth = PeopleFakeAuth.seeded()..nextCredentialsEmail = 'yeni@example.com';
      await addPerson(t, auth);
      expect(
        find.text("Kişi eklendi ve hesap açıldı; giriş bilgisi e-postası gönderiliyor. Ulaşmazsa Daireler ekranından PIN'i sıfırlayın."),
        findsOneWidget,
      );
      expect(find.textContaining('Yalnız kayıt'), findsNothing);
    });

    testWidgets('alan yoksa (null) ve hesap açılmadıysa: "yalnız kayıt olarak tutuldu" söylenir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await addPerson(t, auth);
      expect(find.text('Kişi eklendi. Yalnız kayıt olarak tutuldu; giriş hesabı açılmadı.'), findsOneWidget);
      expect(find.textContaining('Giriş bilgileri'), findsNothing);
      expect(find.textContaining('gönderilemedi'), findsNothing);
    });
  });

  group('Daireler ve Araçlar sekmeleri davranışı', () {
    testWidgets('sekmeler tembel kurulur: Daireler ilk açılışta çağrılmaz, açılınca bir kez çekilir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      expect(auth.apartmentCalls, isEmpty);
      expect(auth.vehicleCalls, isEmpty);
      await _openTab(t, 1);
      expect(auth.apartmentCalls, hasLength(1));
      await _openTab(t, 0);
      await _openTab(t, 1);
      expect(auth.apartmentCalls, hasLength(1), reason: 'sekme durumu korunur, yeniden çekilmez');
    });

    testWidgets('Daireler: blok süzgeci blok numarasını, arama metni sunucuya gönderir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      await _openTab(t, 1);

      await _choose(t, find.byType(DropdownButtonFormField<int>).last, 'B Blok');
      expect(auth.apartmentCalls.last.block, 2);
      expect(find.byType(ApartmentCrmCard), findsOneWidget);
      expect(find.text('B Blok - 2'), findsOneWidget);

      await _type(t, 'apartments_search', 'zzz');
      await _debounce(t);
      expect(auth.apartmentCalls.last.query, 'zzz');
      expect(find.text('Bu arama ve süzgeç için daire bulunamadı.'), findsOneWidget);
    });

    testWidgets('Daireler: blok listesi alınamazsa (kurul üyesi) süzgeç gizli kalır, liste çalışır', (t) async {
      final auth = PeopleFakeAuth.seeded()..structureFails = true;
      await _pump(t, auth);
      await _openTab(t, 1);
      expect(find.byType(ApartmentCrmCard), findsNWidgets(3));
      expect(find.text('Blok'), findsNothing);
      expect(auth.structureCalls, 1);
    });

    testWidgets('Daireler: kart penceresi açılır ve daire ayrıntısı çekilir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      await _openTab(t, 1);
      await tapText(t, 'A Blok - 5');
      await settleFor(t);
      expect(auth.getApartmentCalls, <int>[301]);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('Daireler hata: Tekrar Dene; Daireler boş: "Bu sitede daire bulunamadı."', (t) async {
      final auth = PeopleFakeAuth.seeded()..apartmentsError = ApiException('Daireler alınamadı.');
      await _pump(t, auth);
      await _openTab(t, 1);
      expect(find.text('Daireler alınamadı.'), findsOneWidget);
      expect(find.text('Bu sitede daire bulunamadı.'), findsNothing);
      auth.apartmentsError = null;
      auth.apartmentsJson.clear();
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.text('Bu sitede daire bulunamadı.'), findsOneWidget);
    });

    testWidgets('Araçlar: arama plakayı sunucuya gönderir; araç kaldırma onayla çalışır, liste yenilenir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      await _openTab(t, 2);

      await _type(t, 'vehicles_search', 'xyz');
      await _debounce(t);
      expect(auth.vehicleCalls.last.query, 'xyz');
      expect(find.byType(VehicleCard), findsOneWidget);
      expect(find.text('06 XYZ 789'), findsOneWidget);

      await tapFinder(t, _removeButtons);
      expect(find.text('06 XYZ 789 plakalı araç kaldırılsın mı? Kayıt silinmez, pasifleşir.'), findsOneWidget);
      await tapText(t, 'Vazgeç');
      expect(auth.removeVehicleCalls, isEmpty, reason: 'vazgeçilince kaldırılmaz');

      await tapFinder(t, _removeButtons);
      await tapText(t, 'Kaldır');
      await settleFor(t);
      expect(auth.removeVehicleCalls, <int>[2]);
      expect(find.byType(VehicleCard), findsNothing);
      expect(find.text('Bu arama için araç bulunamadı.'), findsOneWidget);
    });

    testWidgets('Araçlar: kaldırma sunucu tarafından reddedilirse hata görünür, araç listede kalır', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      await _openTab(t, 2);
      auth.writeError = ApiException('Bu işlem için yetkiniz yok.', statusCode: 403, code: 'FORBIDDEN_ROLE');
      await tapFinder(t, _removeButtons);
      await tapText(t, 'Kaldır');
      await settleFor(t);
      expect(find.text('Bu işlem için yetkiniz yok.'), findsOneWidget);
      expect(find.byType(VehicleCard), findsNWidgets(2));
    });

    testWidgets('Araçlar boş durum ve hata durumu', (t) async {
      final auth = PeopleFakeAuth.seeded()..vehiclesError = ApiException('Araçlar alınamadı.');
      await _pump(t, auth);
      await _openTab(t, 2);
      expect(find.text('Araçlar alınamadı.'), findsOneWidget);
      expect(find.text('Henüz araç kaydı yok.'), findsNothing);
      auth.vehiclesError = null;
      auth.vehiclesJson.clear();
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.text('Henüz araç kaydı yok.'), findsOneWidget);
    });

    testWidgets('bir sekmedeki değişiklik diğer kurulu sekmeyi bayatlatır; o sekmeye geçince yeniden çekilir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      expect(find.text('1 araç'), findsOneWidget);
      await _openTab(t, 2);
      final peopleBefore = auth.peopleCalls.length;

      await tapFinder(t, _removeButtons.first);
      await tapText(t, 'Kaldır');
      await settleFor(t);
      expect(auth.removeVehicleCalls, isNotEmpty);

      await _openTab(t, 0);
      await settleFor(t);
      expect(auth.peopleCalls.length, greaterThan(peopleBefore),
          reason: 'Kişiler sekmesi bayat işaretlendi ve geri dönüşte yenilendi');
      expect(find.text('1 araç'), findsNothing, reason: 'araç sayısı güncel');
    });
  });
}
