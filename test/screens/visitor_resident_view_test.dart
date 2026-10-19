// Ziyaretçi ve Kargo: sakin ekranı (VisitorResidentView) + ayrıntı penceresi.
//
// Kapsam: taşma matrisi (320x640 x2,0; 360x640 x1,5; yatay 640x360 x2,0; tablet 768x1024; açık / koyu), yükleniyor /
// hata / boş / dolu ayrımı (HATA ASLA "kayıt yok" demez), modül kapalı, okunmamış (kalın + "Yeni" rozeti + uyarı),
// açınca `seen` + rozet söner + geri çağrı, imleçli sayfalama, site süzgeci ve ekran okuyucu etiketleri.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/visitor_resident_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/visitor_log_parts.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart' show pumpList, tapFinder;
import 'visitor_fixtures.dart';

const List<PeopleSite> _oneSite = <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi')];
const List<PeopleSite> _twoSites = <PeopleSite>[
  PeopleSite(code: 11, name: 'Gül Sitesi'),
  PeopleSite(code: 12, name: 'Mavi Park'),
];

class _Rig {
  _Rig(this.service, this.auth);

  final FakeVisitorService service;
  final VisitorFakeAuth auth;
  final GlobalKey<VisitorResidentViewState> key = GlobalKey<VisitorResidentViewState>();
  int unreadChanged = 0;

  Future<void> pump(
    WidgetTester t, {
    double width = 400,
    double height = 2400,
    double scale = 1.0,
    bool dark = false,
    List<PeopleSite> sites = _oneSite,
  }) async {
    await pumpList(
      t,
      VisitorResidentView(
        key: key,
        authService: auth,
        service: service,
        sites: sites,
        onUnreadChanged: () => unreadChanged++,
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    await settleFor(t, 100);
    await settleFor(t, 100);
  }
}

_Rig _rig({bool empty = false}) {
  final auth = VisitorFakeAuth();
  final service = seededVisitor(auth);
  if (empty) service.rows.clear();
  return _Rig(service, auth);
}

List<int> _cardIds(WidgetTester t) => [
  for (final c in t.widgetList<VisitorResidentCard>(find.byType(VisitorResidentCard))) c.entry.id,
];

Future<void> _openCard(WidgetTester t, int id) async {
  await tapFinder(t, vkKey('visitor_card_$id'));
  await settleFor(t, 100);
  await settleFor(t, 100);
}

void main() {
  group('taşma matrisi', () {
    visitorMatrix('dolu liste: okunmamış kalın + Yeni rozeti, uyarı, çok siteli site adı', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark, sites: _twoSites);
      expect(_cardIds(t), <int>[3, 2, 1], reason: 'yalnız kendi dairesi; ortak alan (4) yok; id azalan');
      expect(find.text('Yeni'), findsOneWidget);
      expect(find.text('Görülmemiş 1 kaydınız var.'), findsOneWidget);
      expect(find.text('Yurtiçi Kargo'), findsOneWidget);
      expect(find.text('Gül Sitesi'), findsWidgets, reason: 'çok siteli sakinde kartta site adı');
      final bold = t.widget<Text>(find.text('Yurtiçi Kargo'));
      expect(bold.style?.fontWeight, FontWeight.w800);
      final plain = t.widget<Text>(find.text('Aras Kargo'));
      expect(plain.style?.fontWeight, isNot(FontWeight.w800));
      expect(find.textContaining('Kaydeden'), findsNothing, reason: 'görevli adı sakine gösterilmez');
    });

    visitorMatrix('boş / hata / modül kapalı ayrımı', (t, w, h, s, dark) async {
      final empty = _rig(empty: true);
      await empty.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Henüz kaydınız yok.'), findsOneWidget);

      final broken = _rig();
      broken.service.failures['listMine'] = <Object>[ApiException('Sunucuya bağlanılamadı.')];
      await broken.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Sunucuya bağlanılamadı.'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.text('Henüz kaydınız yok.'), findsNothing);

      final off = _rig();
      off.service.failures['listMine'] = <Object>[FakeVisitorService.moduleOff()];
      await off.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(vkKey('visitor_module_off'), findsOneWidget);
      expect(find.byType(VisitorResidentCard), findsNothing);
    });

    visitorMatrix('ayrıntı penceresi: taşma yok', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await _openCard(t, 2);
      expect(vkKey('visitor_resident_detail_close'), findsOneWidget);
      expect(vkKey('visitor_resident_detail_note'), findsOneWidget);
      expect(find.text('Haftalık temizlik için geldi.'), findsNWidgets(2), reason: 'kart + pencere');
      await t.pumpWidget(const SizedBox());
    });
  });

  group('liste durumları', () {
    testWidgets('yüklenirken iskelet; "kayıt yok" ve hata YOK', (t) async {
      final rig = _rig();
      final gate = Completer<void>();
      rig.service.gates['listMine'] = <Completer<void>>[gate];
      await pumpList(
        t,
        VisitorResidentView(key: rig.key, authService: rig.auth, service: rig.service, sites: _oneSite),
        width: 400, height: 2400, scale: 1.0, dark: false,
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.text('Henüz kaydınız yok.'), findsNothing);
      expect(find.byType(InlineNotice), findsNothing);
      gate.complete();
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(find.byType(VisitorResidentCard), findsNWidgets(3));
    });

    testWidgets('hata sonrası Tekrar Dene listeyi getirir; yenileme hatası eski listeyi silmez', (t) async {
      final rig = _rig();
      rig.service.failures['listMine'] = <Object>[ApiException('Bağlantı yok.')];
      await rig.pump(t);
      expect(find.byType(VisitorResidentCard), findsNothing);
      await tapFinder(t, find.text('Tekrar Dene'));
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(find.byType(VisitorResidentCard), findsNWidgets(3));
      rig.service.failures['listMine'] = <Object>[ApiException('Yenilenemedi.')];
      await rig.key.currentState!.reload();
      await settleFor(t, 100);
      expect(find.byType(VisitorResidentCard), findsNWidgets(3));
      expect(find.text('Yenilenemedi.'), findsOneWidget);
    });

    testWidgets('özet ucu hata verirse uyarı listeden sayılır; ekran çökmez', (t) async {
      final rig = _rig();
      rig.service.failures['summary'] = <Object>[ApiException('Özet alınamadı.')];
      await rig.pump(t);
      expect(find.text('Görülmemiş 1 kaydınız var.'), findsOneWidget);
      expect(find.text('Özet alınamadı.'), findsNothing);
    });

    testWidgets('imleçli sayfalama: 30 + "Daha fazla yükle" -> 35', (t) async {
      final auth = VisitorFakeAuth();
      final service = FakeVisitorService(authService: auth);
      for (var i = 1; i <= 35; i++) {
        service.rows.add(vkEntry(i, name: 'Kargo $i', seenAt: '2026-10-18T12:00:00Z'));
      }
      final rig = _Rig(service, auth);
      await rig.pump(t, height: 12000);
      expect(find.byType(VisitorResidentCard), findsNWidgets(30));
      await tapFinder(t, find.text('Daha fazla yükle'));
      await settleFor(t, 100);
      expect(find.byType(VisitorResidentCard), findsNWidgets(35));
      expect(find.text('Daha fazla yükle'), findsNothing);
      expect(service.listMineCalls.last.before, 6, reason: 'imleç son kartın kimliği');
    });

    testWidgets('site süzgeci site_code gönderir; yalnız çok siteli sakinde çıkar', (t) async {
      final rig = _rig();
      await rig.pump(t);
      expect(find.text('Tüm siteler'), findsNothing, reason: 'tek sitede süzgeç yok');
      await rig.pump(t, sites: _twoSites);
      await t.tap(find.byType(DropdownButtonFormField<int>));
      await settleFor(t, 100);
      await t.tap(find.text('Mavi Park').last);
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.listMineCalls.last.site, 12);
      expect(find.text('Bu sitede kaydınız yok.'), findsOneWidget);
    });

    testWidgets('site listesi boş: açıklayıcı kart, istek yine de çökmez', (t) async {
      final rig = _rig();
      await rig.pump(t, sites: const <PeopleSite>[]);
      expect(find.text('Kayıt görebileceğiniz site yok.'), findsOneWidget);
      expect(find.byType(VisitorResidentCard), findsNothing);
    });
  });

  group('görüldü', () {
    testWidgets('okunmamış kart açılınca seen çağrılır, kalınlık ve rozet söner, uyarı kalkar, geri çağrı', (t) async {
      final rig = _rig();
      await rig.pump(t, height: 1800);
      await _openCard(t, 3);
      expect(find.text('Kargo'), findsWidgets);
      expect(vkKey('visitor_resident_detail_note'), findsOneWidget);
      expect(rig.service.seenCalls, <int>[3]);
      await tapFinder(t, vkKey('visitor_resident_detail_close'));
      await settleFor(t, 100);
      expect(find.text('Yeni'), findsNothing, reason: 'görüldü: rozet söndü');
      expect(t.widget<Text>(find.text('Yurtiçi Kargo')).style?.fontWeight, isNot(FontWeight.w800));
      expect(vkKey('visitor_unread_notice'), findsNothing);
      expect(rig.unreadChanged, 1);
      expect(rig.service.rows.firstWhere((r) => r['id'] == 3)['resident_seen_at'], isNotNull);
    });

    testWidgets('görülmüş kart açılınca seen çağrılmaz; pencere yine açılır', (t) async {
      final rig = _rig();
      await rig.pump(t, height: 1800);
      await _openCard(t, 2);
      expect(rig.service.seenCalls, isEmpty);
      expect(find.text('Temizlik A.Ş.'), findsWidgets);
      expect(rig.unreadChanged, 0);
      await tapFinder(t, vkKey('visitor_resident_detail_close'));
      await settleFor(t, 100);
    });

    testWidgets('seen hatası sessiz: pencere açılır, rozet kalır, sonraki açılışta yinelenir', (t) async {
      final rig = _rig();
      rig.service.failures['seen'] = <Object>[ApiException('Sunucu yok.')];
      await rig.pump(t, height: 1800);
      await _openCard(t, 3);
      expect(vkKey('visitor_resident_detail_close'), findsOneWidget);
      await tapFinder(t, vkKey('visitor_resident_detail_close'));
      await settleFor(t, 100);
      expect(find.text('Yeni'), findsOneWidget);
      expect(rig.unreadChanged, 0);
      await _openCard(t, 3);
      expect(rig.service.seenCalls, <int>[3, 3]);
      await tapFinder(t, vkKey('visitor_resident_detail_close'));
      await settleFor(t, 100);
      expect(find.text('Yeni'), findsNothing);
    });
  });

  group('erişilebilirlik', () {
    testWidgets('kart tek birleşik etiket taşır: tür, ad, durum, yeni', (t) async {
      final rig = _rig();
      await rig.pump(t);
      final handle = t.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp(r'Kargo: Yurtiçi Kargo\. Durum: Bekliyor\. Daire: A Blok / 5\. Yeni, henüz görülmedi\.')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'Ziyaretçi: Ayşe Yılmaz\. Durum: İçeride\.')), findsOneWidget);
      handle.dispose();
    });
  });
}
