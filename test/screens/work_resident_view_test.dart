// İş Takibi: sakin "Taleplerim" ekranı (WorkResidentView) + "Yeni Talep" formu + sakin ayrıntı penceresi.
//
// Kapsam: taşma matrisi (320x640 x2,0; 360x640 x1,5; yatay 640x360 x2,0; tablet 768x1024; açık / koyu), yükleniyor /
// hata / boş / dolu ayrımı (HATA ASLA "talep yok" demez), modül kapalı durumu, durum süzgeci + imleçli sayfalama,
// site süzgeci, form doğrulaması + çift gönderim + hata + hız sınırı kilidi, ayrıntı (yalnız public olaylar, seen,
// yorum, iptal) ve ekran okuyucu etiketleri.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/work_resident_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/work_tracking_parts.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart' show pumpList, tapFinder;
import 'work_fixtures.dart';

const List<PeopleSite> _oneSite = <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi')];
const List<PeopleSite> _twoSites = <PeopleSite>[
  PeopleSite(code: 11, name: 'Gül Sitesi'),
  PeopleSite(code: 12, name: 'Mavi Park'),
];

class _Rig {
  _Rig(this.service, this.auth);

  final FakeWorkService service;
  final WorkFakeAuth auth;
  final GlobalKey<WorkResidentViewState> key = GlobalKey<WorkResidentViewState>();

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
      WorkResidentView(key: key, authService: auth, service: service, sites: sites),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    await settleFor(t, 100);
    await settleFor(t, 100);
  }
}

_Rig _rig({int count = 3}) {
  final auth = WorkFakeAuth();
  return _Rig(residentWork(auth, count: count), auth);
}

Future<void> _tapKey(WidgetTester t, String key) => tapFinder(t, wkKey(key));

Future<void> _type(WidgetTester t, String key, String text) async {
  final field = wkKey(key);
  await t.ensureVisible(field);
  await t.pump();
  await t.enterText(field, text);
  await t.pump();
}

Future<void> _openCard(WidgetTester t, int id) async {
  final card = find.byWidgetPredicate((w) => w is WorkResidentCard && w.item.id == id);
  await tapFinder(t, card);
  await settleFor(t, 100);
  await settleFor(t, 100);
}

void main() {
  group('taşma matrisi', () {
    workMatrix('dolu liste: durum rozeti, güncelleme göstergesi, acil çipi, Yeni Talep', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark, sites: _twoSites);
      final order = [for (final c in t.widgetList<WorkResidentCard>(find.byType(WorkResidentCard))) c.item.id];
      expect(order, <int>[3, 1], reason: 'varsayılan süzgeç "Açık": kapanan talep yok; id azalan');
      expect(find.text('Yeni güncelleme'), findsOneWidget);
      expect(find.text('Acil'), findsOneWidget);
      expect(find.text('İşlemde'), findsOneWidget);
      expect(find.text('Yeni Talep'), findsOneWidget);
      expect(find.text('1 talebinizde yeni güncelleme var.'), findsOneWidget);
      expect(find.text('Gül Sitesi'), findsWidgets, reason: 'çok siteli sakinde kartta site adı');
    });

    workMatrix('boş: gerçekten boşken açıklayıcı durum', (t, w, h, s, dark) async {
      final rig = _rig(count: 0);
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Açık talebiniz yok.'), findsOneWidget);
      expect(find.byType(WorkResidentCard), findsNothing);
    });

    workMatrix('hata: "talep yok" DEMEZ; Tekrar Dene görünür', (t, w, h, s, dark) async {
      final rig = _rig();
      rig.service.failures['listMine'] = <Object>[ApiException('Sunucuya bağlanılamadı.')];
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Sunucuya bağlanılamadı.'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.text('Açık talebiniz yok.'), findsNothing);
    });

    workMatrix('modül kapalı: açıklayıcı kart', (t, w, h, s, dark) async {
      final rig = _rig();
      rig.service.failures['listMine'] = <Object>[FakeWorkService.moduleOff()];
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(wkKey('work_module_off'), findsOneWidget);
      expect(find.text('İş takibi bu site için kapalı.'), findsOneWidget);
      expect(find.byType(WorkResidentCard), findsNothing);
    });
  });

  group('liste durumları', () {
    testWidgets('yüklenirken iskelet; "talep yok" ve hata YOK', (t) async {
      final rig = _rig();
      final gate = Completer<void>();
      rig.service.gates['listMine'] = <Completer<void>>[gate];
      await pumpList(
        t,
        WorkResidentView(key: rig.key, authService: rig.auth, service: rig.service, sites: _oneSite),
        width: 400, height: 2400, scale: 1.0, dark: false,
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.text('Açık talebiniz yok.'), findsNothing);
      expect(find.byType(InlineNotice), findsNothing);
      gate.complete();
      await settleFor(t, 100);
      expect(find.byType(WorkResidentCard), findsNWidgets(2));
    });

    testWidgets('hata sonrası Tekrar Dene listeyi getirir', (t) async {
      final rig = _rig();
      rig.service.failures['listMine'] = <Object>[ApiException('Bağlantı yok.')];
      await rig.pump(t);
      expect(find.byType(WorkResidentCard), findsNothing);
      await tapFinder(t, find.text('Tekrar Dene'));
      await settleFor(t, 100);
      expect(find.byType(WorkResidentCard), findsNWidgets(2));
      expect(find.text('Bağlantı yok.'), findsNothing);
    });

    testWidgets('hata varken eski liste korunur (yenileme hatası listeyi silmez)', (t) async {
      final rig = _rig();
      await rig.pump(t);
      rig.service.failures['listMine'] = <Object>[ApiException('Yenilenemedi.')];
      await rig.key.currentState!.reload();
      await settleFor(t, 100);
      expect(find.byType(WorkResidentCard), findsNWidgets(2));
      expect(find.text('Yenilenemedi.'), findsOneWidget);
    });

    testWidgets('durum süzgeci: Kapanan -> yalnız kapanan; Tümü -> hepsi; sorgu sunucuya gider', (t) async {
      final rig = _rig();
      await rig.pump(t);
      expect(rig.service.listMineCalls.last.status, 'open');
      await _tapKey(t, 'work_status_closed');
      await settleFor(t, 100);
      expect(rig.service.listMineCalls.last.status, 'closed');
      expect([for (final c in t.widgetList<WorkResidentCard>(find.byType(WorkResidentCard))) c.item.id], <int>[2]);
      await _tapKey(t, 'work_status_all');
      await settleFor(t, 100);
      expect(find.byType(WorkResidentCard), findsNWidgets(3));
      expect(find.text('Kapanmış talebiniz yok.'), findsNothing);
    });

    testWidgets('boş kapanan listesi kendi mesajını söyler', (t) async {
      final rig = _rig(count: 0);
      await rig.pump(t);
      await _tapKey(t, 'work_status_closed');
      await settleFor(t, 100);
      expect(find.text('Kapanmış talebiniz yok.'), findsOneWidget);
    });

    testWidgets('imleçli sayfalama: 30 + "Daha fazla yükle" -> 35', (t) async {
      final auth = WorkFakeAuth();
      final service = FakeWorkService(authService: auth);
      for (var i = 1; i <= 35; i++) {
        service.residentRows.add(wkResident(i, title: 'Talep $i'));
      }
      final rig = _Rig(service, auth);
      await rig.pump(t, height: 12000);
      expect(find.byType(WorkResidentCard), findsNWidgets(30));
      await tapFinder(t, find.text('Daha fazla yükle'));
      await settleFor(t, 100);
      expect(find.byType(WorkResidentCard), findsNWidgets(35));
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
    });
  });

  group('ayrıntı penceresi', () {
    testWidgets('okunmamış talep: seen çağrılır; yalnız public olaylar; iptal ve yorum görünür', (t) async {
      final rig = _rig();
      await rig.pump(t, height: 1800);
      await _openCard(t, 3);
      expect(find.text('Talep Ayrıntısı'), findsOneWidget);
      expect(find.text('Geçmiş'), findsOneWidget);
      expect(find.text('Talep açıldı'), findsOneWidget);
      expect(find.text('Teknisyen yarın gelecek.'), findsOneWidget);
      expect(rig.service.getMineCalls, <int>[3]);
      expect(rig.service.seenCalls, <int>[3]);
      expect(wkKey('work_resident_cancel'), findsOneWidget);
      expect(wkKey('work_resident_comment_send'), findsOneWidget);
      // Öncelik ve atanan adı sakine gösterilmez.
      expect(find.textContaining('Öncelik'), findsNothing);
      await _tapKey(t, 'work_resident_detail_close');
      await settleFor(t, 100);
      expect(find.text('Yeni güncelleme'), findsNothing, reason: 'görüldü: liste yenilendi, rozet söndü');
      expect(find.text('Yeni güncelleme', skipOffstage: false), findsNothing);
    });

    testWidgets('işlemdeki talep: iç not YOK, iptal düğmesi YOK; görevli atandı bilgisi var', (t) async {
      final rig = _rig();
      await rig.pump(t, height: 1800);
      await _openCard(t, 1);
      expect(find.text('Gizli iç not'), findsNothing);
      expect(wkKey('work_resident_cancel'), findsNothing);
      expect(find.text('Atandı'), findsOneWidget);
      expect(find.text('Durum: Yeni → İşlemde'), findsOneWidget);
      expect(rig.service.seenCalls, isEmpty);
      expect(wkKey('work_resident_comment_send'), findsOneWidget);
    });

    testWidgets('kapanmış talep: yorum kutusu yerine açıklama', (t) async {
      final rig = _rig();
      await rig.pump(t, height: 1800);
      await _tapKey(t, 'work_status_all');
      await settleFor(t, 100);
      await _openCard(t, 2);
      expect(wkKey('work_resident_comment_send'), findsNothing);
      expect(wkKey('work_resident_no_comment'), findsOneWidget);
      expect(wkKey('work_resident_cancel'), findsNothing);
    });

    testWidgets('yorum: doğrulama, gönderim, alan temizlenir, olay çizgide; hatada metin korunur', (t) async {
      final rig = _rig();
      await rig.pump(t, height: 1800);
      await _openCard(t, 1);
      await _tapKey(t, 'work_resident_comment_send');
      expect(find.text('Yorum boş olamaz.'), findsOneWidget);
      expect(rig.service.commentMineCalls, isEmpty);

      rig.service.failures['comment'] = <Object>[ApiException('Yorum şu an kaydedilemedi.')];
      await _type(t, 'work_resident_comment_field', 'Merhaba yönetim');
      await _tapKey(t, 'work_resident_comment_send');
      await settleFor(t, 100);
      expect(find.text('Yorum şu an kaydedilemedi.'), findsOneWidget);
      expect(find.descendant(of: wkKey('work_resident_comment_field'), matching: find.text('Merhaba yönetim')), findsOneWidget);

      await _tapKey(t, 'work_resident_comment_send');
      await settleFor(t, 100);
      expect(rig.service.commentMineCalls.map((c) => c.body), <String>['Merhaba yönetim', 'Merhaba yönetim']);
      expect(find.text('Merhaba yönetim'), findsOneWidget, reason: 'olay çizgide; alan temizlendi');
    });

    testWidgets('429: gönderim düğmesi kilitlenir ve sunucunun süre metni görünür', (t) async {
      final rig = _rig();
      await rig.pump(t, height: 1800);
      await _openCard(t, 1);
      rig.service.failures['comment'] = <Object>[
        ApiException('Çok fazla iş takibi işlemi. 2 dakika sonra tekrar deneyin.', statusCode: 429, retryAfterSeconds: 120),
      ];
      await _type(t, 'work_resident_comment_field', 'Acele');
      await _tapKey(t, 'work_resident_comment_send');
      await settleFor(t, 100);
      expect(find.text('Çok fazla iş takibi işlemi. 2 dakika sonra tekrar deneyin.'), findsOneWidget);
      final button = t.widget<WorkCommentBox>(find.byType(WorkCommentBox));
      expect(button.locked, isTrue);
      await _tapKey(t, 'work_resident_detail_close');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('yeni talebi iptal: onay penceresi, iptal çağrısı, durum "İptal"; vazgeçilince çağrı yok', (t) async {
      final rig = _rig();
      await rig.pump(t, height: 1800);
      await _openCard(t, 3);
      await _tapKey(t, 'work_resident_cancel');
      await settleFor(t, 100);
      await _tapKey(t, 'work_cancel_keep');
      await settleFor(t, 100);
      expect(rig.service.cancelCalls, isEmpty);
      await _tapKey(t, 'work_resident_cancel');
      await settleFor(t, 100);
      await _tapKey(t, 'work_cancel_confirm');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.cancelCalls, <int>[3]);
      expect(find.text('Durum: Yeni → İptal'), findsOneWidget);
      expect(wkKey('work_resident_cancel'), findsNothing);
    });

    testWidgets('talep artık yok (404): düz Türkçe uyarı, çift kapanış yok', (t) async {
      final rig = _rig();
      await rig.pump(t, height: 1800);
      rig.service.failures['getMine'] = <Object>[FakeWorkService.notFound()];
      await _openCard(t, 1);
      expect(wkKey('work_detail_gone'), findsOneWidget);
      expect(find.textContaining('Talep bulunamadı ya da erişiminiz yok'), findsOneWidget);
    });

    testWidgets('ayrıntı yüklenemedi: özet kart kalır, Tekrar Dene yeniden yükler', (t) async {
      final rig = _rig();
      await rig.pump(t, height: 1800);
      rig.service.failures['getMine'] = <Object>[ApiException('Ayrıntı alınamadı.')];
      await _openCard(t, 1);
      expect(find.text('Ayrıntı alınamadı.'), findsOneWidget);
      expect(find.text('Çatı sızıntısı'), findsWidgets);
      await tapFinder(t, find.text('Tekrar Dene'));
      await settleFor(t, 100);
      expect(find.text('Ayrıntı alınamadı.'), findsNothing);
      expect(find.text('Geçmiş'), findsOneWidget);
      expect(find.text('Talep açıldı'), findsOneWidget);
    });
  });

  group('yeni talep formu', () {
    testWidgets('boş gönderim: alan hataları + özet; istek yok', (t) async {
      final rig = _rig();
      await rig.pump(t, height: 1800);
      await _tapKey(t, 'work_new_request');
      await settleFor(t, 100);
      await _tapKey(t, 'work_form_send');
      await settleFor(t, 100);
      expect(find.text('Başlık boş olamaz.'), findsOneWidget);
      expect(find.text('Açıklama boş olamaz.'), findsOneWidget);
      expect(find.text('Lütfen işaretli alanları düzeltin.'), findsOneWidget);
      expect(rig.service.createCalls, isEmpty);
    });

    testWidgets('daire talebi: daire otomatik seçilir, acil işaretlenir, gövde doğru; liste yenilenir', (t) async {
      final rig = _rig();
      await rig.pump(t, height: 1800);
      await _tapKey(t, 'work_new_request');
      await settleFor(t, 100);
      await _tapKey(t, 'work_form_location_daire');
      await settleFor(t, 100);
      expect(rig.service.apartmentCalls, <int>[11]);
      expect(wkKey('work_form_apartment_single'), findsOneWidget);
      await _type(t, 'work_form_title', '  Musluk akıyor  ');
      await _type(t, 'work_form_description', 'Mutfak musluğu damlatıyor.');
      await _tapKey(t, 'work_form_urgent');
      await _tapKey(t, 'work_form_send');
      await settleFor(t, 100);
      await settleFor(t, 100);
      final sent = rig.service.createCalls.single;
      expect(sent.siteCode, 11);
      expect(sent.category, WorkCategory.ariza);
      expect(sent.locationType, WorkLocationType.daire);
      expect(sent.apartmentId, 301);
      expect(sent.urgent, isTrue);
      expect(sent.title.trim(), 'Musluk akıyor');
      expect(wkKey('work_form_send'), findsNothing, reason: 'form kapandı');
      expect(find.textContaining('Talebiniz alındı'), findsOneWidget);
      expect(find.text('Musluk akıyor'), findsOneWidget, reason: 'yeni talep açık listede');
    });

    testWidgets('ortak alan talebi: daire gönderilmez', (t) async {
      final rig = _rig();
      await rig.pump(t, height: 1800);
      await _tapKey(t, 'work_new_request');
      await settleFor(t, 100);
      await _type(t, 'work_form_title', 'Otopark ışığı');
      await _type(t, 'work_form_description', 'Yanmıyor.');
      await _tapKey(t, 'work_form_send');
      await settleFor(t, 100);
      final sent = rig.service.createCalls.single;
      expect(sent.locationType, WorkLocationType.ortakAlan);
      expect(sent.apartmentId, isNull);
      expect(sent.toJson('wk-12345678').containsKey('apartment_id'), isFalse);
      expect(rig.service.apartmentCalls, isEmpty);
    });

    testWidgets('birden çok daire: seçmeden gönderilemez', (t) async {
      final rig = _rig();
      rig.service.apartments = const <WorkApartmentChoice>[
        WorkApartmentChoice(id: 301, label: 'A Blok / 5'),
        WorkApartmentChoice(id: 302, label: 'B Blok / 2'),
      ];
      await rig.pump(t, height: 1800);
      await _tapKey(t, 'work_new_request');
      await settleFor(t, 100);
      await _tapKey(t, 'work_form_location_daire');
      await settleFor(t, 100);
      await _type(t, 'work_form_title', 'Musluk');
      await _type(t, 'work_form_description', 'Akıyor.');
      await _tapKey(t, 'work_form_send');
      await settleFor(t, 100);
      expect(find.text('Talebin ilgili olduğu daireyi seçin.'), findsOneWidget);
      expect(rig.service.createCalls, isEmpty);
    });

    testWidgets('gönderim hatası pencerede kalır, metin korunur; yeniden denemede başarı', (t) async {
      final rig = _rig();
      await rig.pump(t, height: 1800);
      rig.service.failures['create'] = <Object>[
        ApiException('Sitedeki açık talep sınırına ulaşıldı. Yönetimle iletişime geçin.', statusCode: 409, code: 'WORK_ITEM_LIMIT'),
      ];
      await _tapKey(t, 'work_new_request');
      await settleFor(t, 100);
      await _type(t, 'work_form_title', 'Kapı');
      await _type(t, 'work_form_description', 'Gıcırdıyor.');
      await _tapKey(t, 'work_form_send');
      await settleFor(t, 100);
      expect(find.text('Sitedeki açık talep sınırına ulaşıldı. Yönetimle iletişime geçin.'), findsOneWidget);
      expect(wkKey('work_form_send'), findsOneWidget);
      expect(find.descendant(of: wkKey('work_form_title'), matching: find.text('Kapı')), findsOneWidget);
      await _tapKey(t, 'work_form_send');
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(rig.service.createCalls.length, 2);
      expect(wkKey('work_form_send'), findsNothing);
    });

    testWidgets('çift gönderim: düğme kapanır, tek istek; geri tuşu gönderim sürerken kapatmaz', (t) async {
      final rig = _rig();
      await rig.pump(t, height: 1800);
      final gate = Completer<void>();
      rig.service.gates['create'] = <Completer<void>>[gate];
      await _tapKey(t, 'work_new_request');
      await settleFor(t, 100);
      await _type(t, 'work_form_title', 'Kapı');
      await _type(t, 'work_form_description', 'Gıcırdıyor.');
      await _tapKey(t, 'work_form_send');
      expect(find.text('Gönderiliyor...'), findsOneWidget);
      await t.tap(wkKey('work_form_send'), warnIfMissed: false);
      await t.pump();
      expect(rig.service.createCalls.length, 1);
      expect(t.widget<ElevatedButton>(wkKey('work_form_send')).onPressed, isNull);
      await t.binding.handlePopRoute();
      await t.pump();
      expect(wkKey('work_form_send'), findsOneWidget, reason: 'gönderim sürerken kapanmaz');
      gate.complete();
      await settleFor(t, 100);
      await settleFor(t, 500);
      expect(wkKey('work_form_send'), findsNothing);
    });

    testWidgets('429: gönder kilitlenir ve süre metni görünür', (t) async {
      final rig = _rig();
      await rig.pump(t, height: 1800);
      rig.service.failures['create'] = <Object>[
        ApiException('Bu saat içinde çok fazla talep açtınız. 30 dakika sonra tekrar deneyin.', statusCode: 429, code: 'WORK_ITEM_RATE_LIMITED', retryAfterSeconds: 1800),
      ];
      await _tapKey(t, 'work_new_request');
      await settleFor(t, 100);
      await _type(t, 'work_form_title', 'Kapı');
      await _type(t, 'work_form_description', 'Gıcırdıyor.');
      await _tapKey(t, 'work_form_send');
      await settleFor(t, 100);
      expect(find.text('Bu saat içinde çok fazla talep açtınız. 30 dakika sonra tekrar deneyin.'), findsOneWidget);
      expect(t.widget<ElevatedButton>(wkKey('work_form_send')).onPressed, isNull);
      await _tapKey(t, 'work_form_close');
      await settleFor(t, 100);
      await _tapKey(t, 'work_form_discard');
      await settleFor(t, 100);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('doldurulmuş form kapatılırken onay ister; "Yazmaya Dön" formu korur, "Vazgeç ve Kapat" kapatır', (t) async {
      final rig = _rig();
      await rig.pump(t, height: 1800);
      await _tapKey(t, 'work_new_request');
      await settleFor(t, 100);
      await _tapKey(t, 'work_form_close');
      await settleFor(t, 100);
      expect(wkKey('work_form_send'), findsNothing, reason: 'boş form onaysız kapanır');

      await _tapKey(t, 'work_new_request');
      await settleFor(t, 100);
      await _type(t, 'work_form_title', 'Yarım kalan');
      await _tapKey(t, 'work_form_close');
      await settleFor(t, 100);
      expect(find.text('Talep silinsin mi?'), findsOneWidget);
      await _tapKey(t, 'work_form_keep');
      await settleFor(t, 100);
      expect(wkKey('work_form_send'), findsOneWidget);
      await _tapKey(t, 'work_form_close');
      await settleFor(t, 100);
      await _tapKey(t, 'work_form_discard');
      await settleFor(t, 100);
      expect(wkKey('work_form_send'), findsNothing);
      expect(rig.service.createCalls, isEmpty);
    });
  });

  group('erişilebilirlik', () {
    testWidgets('kart tek birleşik etiket taşır: durum, güncelleme, acil, konum', (t) async {
      final rig = _rig();
      await rig.pump(t);
      final handle = t.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp(r'Talep: Asansör çalışmıyor\. Durum: Yeni\. Yeni güncelleme var\. Acil olarak işaretlendi\.')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'Talep: Çatı sızıntısı\. Durum: İşlemde\.')), findsOneWidget);
      handle.dispose();
    });

    workMatrix('ayrıntı penceresi: taşma yok (olay çizgisi, yorum kutusu, iptal)', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await _openCard(t, 3);
      expect(find.text('Talep Ayrıntısı'), findsOneWidget);
      expect(find.text('Teknisyen yarın gelecek.'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    workMatrix('yeni talep formu: taşma yok (daire, acil, sayaçlar)', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark, sites: _twoSites);
      await _tapKey(t, 'work_new_request');
      await settleFor(t, 100);
      await _tapKey(t, 'work_form_location_daire');
      await settleFor(t, 100);
      expect(wkKey('work_form_urgent'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  });
}
