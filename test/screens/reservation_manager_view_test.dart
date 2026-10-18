// Rezervasyon ve Konsiyerj: yönetim "Rezervasyonlar" ekranı (ReservationManagerView): takvim listesi + karar penceresi,
// konsiyerj talepleri + durum ilerletme, ortak alan yönetimi + alan formu.
//
// Kapsam: taşma matrisi (320x640 x2,0; 360x640 x1,5; yatay 640x360 x2,0; tablet 768x1024; açık / koyu), ROL MATRİSİ
// (yönetici: alan yönetimi + karar; görevli: karar, alan yok; kurul: hiçbir düğme + salt okunur notu, telefon yok),
// yükleniyor / hata / boş / dolu ayrımı, modül kapalı, süzgeçler, opak imleçli sayfalama, karar akışı (gerekçe
// zorunlu, çakışma, çift gönderim) ve alan formu doğrulaması (yalnız değişen alanlar gönderilir).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/reservation_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart' show PrimaryActionButton;
import 'package:site_kapi_kontrol/ui/views/reservation_manager_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/reservation_parts.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart' show pumpList, tapFinder;
import 'reservation_fixtures.dart';

class _Rig {
  _Rig(this.service, this.auth, {this.access = ReservationSiteAccess.manager});

  final FakeReservationService service;
  final ReservationFakeAuth auth;
  final ReservationSiteAccess access;
  final GlobalKey<ReservationManagerViewState> key = GlobalKey<ReservationManagerViewState>();
  int modulesOpened = 0;

  Future<void> pump(
    WidgetTester t, {
    double width = 400,
    double height = 2400,
    double scale = 1.0,
    bool dark = false,
    List<ReservationSite>? sites,
  }) async {
    await pumpList(
      t,
      ReservationManagerView(
        key: key,
        authService: auth,
        service: service,
        sites: sites ?? <ReservationSite>[ReservationSite(code: 11, name: 'Gül Sitesi', access: access)],
        onOpenModules: () => modulesOpened++,
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    await settleFor(t, 100);
    await settleFor(t, 100);
    await settleFor(t, 100);
  }
}

_Rig _rig({ReservationSiteAccess kind = ReservationSiteAccess.manager}) {
  final auth = ReservationFakeAuth();
  return _Rig(seededReservation(auth, kind: kind), auth, access: kind);
}

Future<void> _tapKey(WidgetTester t, String key) => tapFinder(t, rzKey(key));

Future<void> _settle(WidgetTester t) async {
  await settleFor(t, 100);
  await settleFor(t, 100);
}

Future<void> _type(WidgetTester t, String key, String text) async {
  final field = rzKey(key);
  await t.ensureVisible(field);
  await t.pump();
  await t.enterText(field, text);
  await t.pump();
}

Finder _prefixKey(String prefix) => find.byWidgetPredicate(
  (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith(prefix),
);

Future<void> _typeFinder(WidgetTester t, Finder field, String text) async {
  await t.ensureVisible(field);
  await t.pump();
  await t.enterText(field, text);
  await t.pump();
}

Future<void> _openTab(WidgetTester t, String key) async {
  await _tapKey(t, key);
  await _settle(t);
}

List<int> _ids(WidgetTester t) => [
  for (final c in t.widgetList<ManagedReservationCard>(find.byType(ManagedReservationCard))) c.record.id,
];

void main() {
  group('taşma matrisi', () {
    reservationMatrix('takvim: yönetici düğmeleri, bekleyen sayacı, başvuran bilgisi', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(_ids(t), <int>[1, 2, 3, 4], reason: 'başlangıç artan (kimlik artan)');
      expect(find.text('Onay bekleyen (1)'), findsOneWidget);
      expect(rzKey('rez_approve_2'), findsOneWidget);
      expect(rzKey('rez_reject_2'), findsOneWidget);
      expect(rzKey('rez_cancel_1'), findsOneWidget);
      expect(rzKey('rez_approve_1'), findsNothing, reason: 'yalnız bekleyen onaylanır');
      expect(rzKey('rez_cancel_3'), findsNothing, reason: 'tamamlanan iptal edilemez');
      expect(find.text('Yapan: Veli Kaya'), findsOneWidget);
      expect(find.text('Tel: +905559998877'), findsOneWidget);
      expect(rzKey('reservation_read_only_note'), findsNothing);
    });

    reservationMatrix('takvim: kurul SALT OKUR (düğme yok, not var, telefon yok)', (t, w, h, s, dark) async {
      final rig = _rig(kind: ReservationSiteAccess.board);
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(rzKey('reservation_read_only_note'), findsOneWidget);
      expect(find.byType(ManagedReservationCard), findsNWidgets(4));
      expect(find.byType(PrimaryActionButton), findsNothing);
      expect(find.textContaining('Tel:'), findsNothing);
      expect(find.text('Yapan: Veli Kaya'), findsOneWidget, reason: 'kurul yalnız adı görür');
    });

    reservationMatrix('konsiyerj: sayaçlı süzgeç, açık talepler', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await _openTab(t, 'rezm_tab_concierge');
      expect(find.byType(ConciergeCard), findsNWidgets(2));
      expect(find.text('Açık (2)'), findsOneWidget);
      expect(find.text('Yeni (1)'), findsOneWidget);
      expect(find.text('Hazırlanıyor (1)'), findsWidgets);
      expect(find.text('Açan: Ayşe Yılmaz'), findsOneWidget);
    });

    reservationMatrix('alanlar: pasif alan etiketi, yönetici düğmeleri', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await _openTab(t, 'rezm_tab_areas');
      expect(find.byType(ReservationAreaCard), findsNWidgets(3));
      expect(find.text('Pasif'), findsOneWidget);
      expect(find.text('3 alan, 2 aktif'), findsOneWidget);
      expect(rzKey('rezm_area_add'), findsOneWidget);
      expect(rzKey('rezm_area_edit_1'), findsOneWidget);
      expect(find.text('Etkinleştir'), findsWidgets, reason: 'pasif alanın düğmesi');
      expect(find.text('Pazartesi: 09:00-22:00'), findsWidgets);
    });

    reservationMatrix('alan formu: tüm alanlar ve yedi günlük saatler', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await _openTab(t, 'rezm_tab_areas');
      await _tapKey(t, 'rezm_area_add');
      await _settle(t);
      for (final key in const <String>[
        'area_form_name',
        'area_form_capacity',
        'area_form_slot',
        'area_form_approval',
        'area_form_weekly',
        'area_form_1_0_start',
        'area_form_7_0_end',
        'area_form_send',
      ]) {
        await t.ensureVisible(rzKey(key));
        await t.pump();
        expect(rzKey(key), findsOneWidget, reason: key);
      }
    });

    reservationMatrix('karar penceresi: gerekçe alanı', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await _tapKey(t, 'rez_reject_2');
      await _settle(t);
      expect(find.text('Rezervasyonu Reddet'), findsOneWidget);
      expect(rzKey('rez_decision_note'), findsOneWidget);
      expect(find.text('Gerekçe'), findsOneWidget);
      expect(rzKey('rez_decision_send'), findsOneWidget);
    });

    reservationMatrix('konsiyerj ayrıntısı: durum + sakine görünür not', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await _openTab(t, 'rezm_tab_concierge');
      await tapFinder(t, find.byWidgetPredicate((x) => x is ConciergeCard && x.record.id == 1));
      await _settle(t);
      expect(find.text('Konsiyerj Talebi'), findsOneWidget);
      expect(_prefixKey('cnc_manage_status_'), findsOneWidget);
      expect(_prefixKey('cnc_manage_note_'), findsOneWidget);
      expect(rzKey('cnc_manage_save'), findsOneWidget);
    });

    reservationMatrix('hata: "kayıt yok" DEMEZ; Tekrar Dene görünür', (t, w, h, s, dark) async {
      final rig = _rig();
      rig.service.failures['listManaged'] = <Object>[ApiException('Sunucuya bağlanılamadı.')];
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Sunucuya bağlanılamadı.'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.text('Yaklaşan rezervasyon yok.'), findsNothing);
    });

    reservationMatrix('modül kapalı: açıklayıcı kart + Modüller düğmesi', (t, w, h, s, dark) async {
      final rig = _rig();
      rig.service.failures['listManaged'] = <Object>[FakeReservationService.moduleOff()];
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(rzKey('reservation_module_off'), findsOneWidget);
      expect(rzKey('reservation_open_modules'), findsOneWidget);
      expect(find.byType(ManagedReservationCard), findsNothing);
    });
  });

  group('rol matrisi', () {
    testWidgets('yönetici: alan yönetimi + karar', (t) async {
      final rig = _rig();
      await rig.pump(t);
      expect(rzKey('rez_approve_2'), findsOneWidget);
      await _openTab(t, 'rezm_tab_areas');
      expect(rzKey('rezm_area_add'), findsOneWidget);
      expect(rzKey('rezm_area_edit_1'), findsOneWidget);
      expect(rzKey('rezm_areas_staff_note'), findsNothing);
    });

    testWidgets('görevli: karar verir, alan TANIMLAYAMAZ (düğme yok, açıklama var)', (t) async {
      final rig = _rig(kind: ReservationSiteAccess.staff);
      await rig.pump(t);
      expect(rzKey('rez_approve_2'), findsOneWidget);
      expect(rzKey('reservation_read_only_note'), findsNothing);
      await _openTab(t, 'rezm_tab_areas');
      expect(rzKey('rezm_area_add'), findsNothing);
      expect(rzKey('rezm_area_edit_1'), findsNothing);
      expect(rzKey('rezm_areas_staff_note'), findsOneWidget);
      expect(find.byType(ReservationAreaCard), findsNWidgets(3), reason: 'görevli alanları okur');
    });

    testWidgets('kurul: alan düğmeleri yok, konsiyerj ayrıntısı salt okunur ve telefonsuz', (t) async {
      final rig = _rig(kind: ReservationSiteAccess.board);
      await rig.pump(t);
      await _openTab(t, 'rezm_tab_areas');
      expect(rzKey('rezm_area_add'), findsNothing);
      expect(rzKey('rezm_area_toggle_1'), findsNothing);
      await _openTab(t, 'rezm_tab_concierge');
      await tapFinder(t, find.byWidgetPredicate((x) => x is ConciergeCard && x.record.id == 1));
      await _settle(t);
      expect(rzKey('cnc_manage_save'), findsNothing);
      expect(_prefixKey('cnc_manage_status_'), findsNothing);
      expect(find.text('Telefon'), findsNothing);
      expect(find.text('Talebi açan'), findsOneWidget);
      expect(rzKey('reservation_read_only_note'), findsWidgets);
    });
  });

  group('takvim listesi', () {
    testWidgets('yükleniyor: iskelet; "kayıt yok" ve hata YOK', (t) async {
      final rig = _rig();
      final gate = Completer<void>();
      rig.service.gates['listManaged'] = <Completer<void>>[gate];
      await pumpList(
        t,
        ReservationManagerView(
          key: rig.key,
          authService: rig.auth,
          service: rig.service,
          sites: const <ReservationSite>[ReservationSite(code: 11, name: 'Gül Sitesi')],
        ),
        width: 400,
        height: 2400,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t, 100);
      await settleFor(t, 100);
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.text('Yaklaşan rezervasyon yok.'), findsNothing);
      gate.complete();
      await settleFor(t, 100);
      expect(find.byType(ManagedReservationCard), findsNWidgets(4));
    });

    testWidgets('hata sonrası Tekrar Dene; yenileme hatası eski listeyi silmez', (t) async {
      final rig = _rig();
      rig.service.failures['listManaged'] = <Object>[ApiException('Bağlantı yok.')];
      await rig.pump(t);
      expect(find.byType(ManagedReservationCard), findsNothing);
      await tapFinder(t, find.text('Tekrar Dene'));
      await _settle(t);
      expect(find.byType(ManagedReservationCard), findsNWidgets(4));
      rig.service.failures['listManaged'] = <Object>[ApiException('Yenilenemedi.')];
      await rig.key.currentState!.reload();
      await _settle(t);
      expect(find.byType(ManagedReservationCard), findsNWidgets(4));
      expect(find.text('Yenilenemedi.'), findsOneWidget);
    });

    testWidgets('rezervasyon yoksa boş durum; süzgeçli boş durum kendi mesajını söyler', (t) async {
      final auth = ReservationFakeAuth();
      final rig = _Rig(FakeReservationService(authService: auth), auth);
      await rig.pump(t);
      expect(find.text('Yaklaşan rezervasyon yok.'), findsOneWidget);
      await _tapKey(t, 'rezm_status_iptal');
      await _settle(t);
      expect(find.text('Bu süzgeç için rezervasyon bulunamadı.'), findsOneWidget);
    });

    testWidgets('durum süzgeci sunucuya gider; alan süzgeci area_id gönderir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      expect(rig.service.listManagedCalls.last.status, isNull, reason: 'Tümü: durum gönderilmez');
      await _tapKey(t, 'rezm_status_beklemede');
      await _settle(t);
      expect(rig.service.listManagedCalls.last.status, 'beklemede');
      expect(_ids(t), <int>[2]);
      await _tapKey(t, 'rezm_status_all');
      await _settle(t);
      await t.tap(find.byType(DropdownButtonFormField<int>));
      await settleFor(t, 100);
      await t.tap(find.text('Toplantı Odası').last);
      await _settle(t);
      expect(rig.service.listManagedCalls.last.area, 2);
      expect(_ids(t), <int>[2]);
    });

    testWidgets('tarih süzgeci: başlangıç seçilir (YYYY-AA-GG), sıfırlanınca kalkar', (t) async {
      final rig = _rig();
      await rig.pump(t, width: 800, height: 3000);
      expect(rig.service.listManagedCalls.last.from, isNull);
      await _tapKey(t, 'rezm_from');
      await settleFor(t, 300);
      await t.tap(find.text('OK'));
      await _settle(t);
      expect(rig.service.listManagedCalls.last.from, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(rzKey('rezm_dates_reset'), findsOneWidget);
      await _tapKey(t, 'rezm_dates_reset');
      await _settle(t);
      expect(rig.service.listManagedCalls.last.from, isNull);
      expect(rzKey('rezm_dates_reset'), findsNothing);
    });

    testWidgets('opak imleçli sayfalama: 30 + "Daha fazla yükle" -> 35 (imleç sunucudan geldiği gibi gider)', (t) async {
      final auth = ReservationFakeAuth();
      final service = FakeReservationService(authService: auth);
      service.areas.add(rzArea(1));
      for (var i = 1; i <= 35; i++) {
        service.reservations.add(rzReservation(i));
      }
      final rig = _Rig(service, auth);
      await rig.pump(t, height: 16000);
      expect(find.byType(ManagedReservationCard), findsNWidgets(30));
      await tapFinder(t, find.text('Daha fazla yükle'));
      await settleFor(t, 100);
      expect(find.byType(ManagedReservationCard), findsNWidgets(35));
      expect(find.text('Daha fazla yükle'), findsNothing);
      expect(service.listManagedCalls.last.cursor, 'c30');
    });

    testWidgets('site değişince liste yeni siteyle baştan yüklenir; kurul sitesinde düğmeler kalkar', (t) async {
      final rig = _rig();
      await rig.pump(
        t,
        sites: const <ReservationSite>[
          ReservationSite(code: 11, name: 'Gül Sitesi'),
          ReservationSite(code: 12, name: 'Mavi Park', access: ReservationSiteAccess.board),
        ],
      );
      expect(rzKey('rez_approve_2'), findsOneWidget);
      await t.tap(rzKey('rezm_site_11_2'));
      await settleFor(t, 100);
      await t.tap(find.text('Mavi Park').last);
      await _settle(t);
      expect(rig.service.listManagedCalls.last.site, 12);
      expect(find.byType(ManagedReservationCard), findsNothing);
      expect(find.text('Yaklaşan rezervasyon yok.'), findsOneWidget);
      expect(rzKey('reservation_read_only_note'), findsOneWidget);
    });

    testWidgets('modül kapalıyken Modüller düğmesi geri çağırımı tetikler', (t) async {
      final rig = _rig();
      rig.service.failures['listManaged'] = <Object>[FakeReservationService.moduleOff()];
      await rig.pump(t);
      await _tapKey(t, 'reservation_open_modules');
      expect(rig.modulesOpened, 1);
    });
  });

  group('karar penceresi', () {
    testWidgets('onay: not isteğe bağlı; gövde doğru; liste ve sayaç yenilenir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _tapKey(t, 'rez_approve_2');
      await _settle(t);
      expect(find.text('Rezervasyonu Onayla'), findsOneWidget);
      expect(find.text('Not (isteğe bağlı)'), findsOneWidget);
      await _tapKey(t, 'rez_decision_send');
      await _settle(t);
      final call = rig.service.decideCalls.single;
      expect(call.site, 11);
      expect(call.id, 2);
      expect(call.action, 'approve');
      expect(call.note, isNull);
      expect(rzKey('rez_decision_send'), findsNothing, reason: 'pencere kapandı');
      expect(find.textContaining('Rezervasyon onaylandı'), findsOneWidget);
      expect(rzKey('rez_approve_2'), findsNothing, reason: 'artık beklemede değil');
      expect(find.text('Onay bekleyen (0)'), findsOneWidget);
    });

    testWidgets('ret: gerekçe ZORUNLU (boşsa istek yok); gerekçe kartta görünür', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _tapKey(t, 'rez_reject_2');
      await _settle(t);
      await _tapKey(t, 'rez_decision_send');
      await settleFor(t, 100);
      expect(find.text('Gerekçe boş olamaz.'), findsOneWidget);
      expect(rig.service.decideCalls, isEmpty);
      await _type(t, 'rez_decision_note', '  Uygun değil.  ');
      await _tapKey(t, 'rez_decision_send');
      await _settle(t);
      final call = rig.service.decideCalls.single;
      expect(call.action, 'reject');
      expect(call.note, 'Uygun değil.');
      expect(find.text('Karar notu (Ben Yönetici): Uygun değil.'), findsOneWidget);
      expect(find.text('Reddedildi'), findsOneWidget);
    });

    testWidgets('yönetici iptali: gerekçe gerekir; sakine "Yönetim iptal etti." görünür', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _tapKey(t, 'rez_cancel_1');
      await _settle(t);
      expect(find.text('Rezervasyonu İptal Et'), findsOneWidget);
      await _type(t, 'rez_decision_note', 'Bakım var.');
      await _tapKey(t, 'rez_decision_send');
      await _settle(t);
      expect(rig.service.decideCalls.single.action, 'cancel');
      expect(find.text('Yönetim iptal etti.'), findsWidgets);
    });

    testWidgets('çakışma (409): hata pencerede, gerekçe korunur; kapatınca liste sunucuyla eşitlenir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      final before = rig.service.listManagedCalls.length;
      rig.service.failures['decide'] = <Object>[
        FakeReservationService.error(409, 'INVALID_TRANSITION', payload: <String, dynamic>{'from': 'iptal', 'to': 'onaylandi'}),
      ];
      await _tapKey(t, 'rez_reject_2');
      await _settle(t);
      await _type(t, 'rez_decision_note', 'Uygun değil');
      await _tapKey(t, 'rez_decision_send');
      await _settle(t);
      expect(find.textContaining('Başka biri tarafından güncellenmiş olabilir'), findsOneWidget);
      expect(find.descendant(of: rzKey('rez_decision_note'), matching: find.text('Uygun değil')), findsOneWidget);
      await _tapKey(t, 'rez_decision_close');
      await _settle(t);
      expect(rig.service.listManagedCalls.length, before + 1);
    });

    testWidgets('kayıt kalkmış (404): uyarı, gönder düğmesi yok', (t) async {
      final rig = _rig();
      await rig.pump(t);
      rig.service.failures['decide'] = <Object>[FakeReservationService.error(404, 'RESERVATION_NOT_FOUND')];
      await _tapKey(t, 'rez_approve_2');
      await _settle(t);
      await _tapKey(t, 'rez_decision_send');
      await _settle(t);
      expect(rzKey('rez_decision_gone'), findsOneWidget);
      expect(rzKey('rez_decision_send'), findsNothing);
    });

    testWidgets('çift gönderim: tek istek; 429: düğme kilitlenir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      final gate = Completer<void>();
      rig.service.gates['decide'] = <Completer<void>>[gate];
      await _tapKey(t, 'rez_approve_2');
      await _settle(t);
      await _tapKey(t, 'rez_decision_send');
      expect(find.text('Gönderiliyor...'), findsOneWidget);
      await t.tap(rzKey('rez_decision_send'), warnIfMissed: false);
      await t.pump();
      expect(rig.service.decideCalls.length, 1);
      expect(t.widget<ElevatedButton>(rzKey('rez_decision_send')).onPressed, isNull);
      gate.complete();
      await settleFor(t, 100);
      await settleFor(t, 500);
      expect(rzKey('rez_decision_send'), findsNothing);

      rig.service.failures['decide'] = <Object>[
        ApiException('Çok fazla rezervasyon işlemi. 1 dakika sonra tekrar deneyin.', statusCode: 429, retryAfterSeconds: 60),
      ];
      await _tapKey(t, 'rez_cancel_1');
      await _settle(t);
      await _type(t, 'rez_decision_note', 'Acele');
      await _tapKey(t, 'rez_decision_send');
      await settleFor(t, 100);
      expect(find.text('Çok fazla rezervasyon işlemi. 1 dakika sonra tekrar deneyin.'), findsOneWidget);
      expect(t.widget<ElevatedButton>(rzKey('rez_decision_send')).onPressed, isNull);
      await t.pump(const Duration(seconds: 61));
      expect(t.widget<ElevatedButton>(rzKey('rez_decision_send')).onPressed, isNotNull);
      await _tapKey(t, 'rez_decision_close');
      await _settle(t);
    });

    testWidgets('aynı karar tekrarı (changed=false): bilgi mesajı', (t) async {
      final rig = _rig();
      await rig.pump(t);
      // Başka biri bu arada onayladı: sunucu aynı kararı 200 + changed:false ile yanıtlar.
      rig.service.reservations.firstWhere((r) => r['id'] == 2)
        ..['status'] = 'onaylandi'
        ..['can_decide'] = false;
      await _tapKey(t, 'rez_approve_2');
      await _settle(t);
      await _tapKey(t, 'rez_decision_send');
      await _settle(t);
      expect(find.textContaining('Bu karar zaten verilmişti'), findsOneWidget);
    });
  });

  group('konsiyerj yönetimi', () {
    Future<void> openRequest(WidgetTester t, int id) async {
      await tapFinder(t, find.byWidgetPredicate((x) => x is ConciergeCard && x.record.id == id));
      await _settle(t);
    }

    testWidgets('durum süzgeci: Tümü -> hepsi; kategori süzgeci sunucuya gider', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openTab(t, 'rezm_tab_concierge');
      expect(rig.service.listManagedRequestsCalls.last.status, 'open');
      await _tapKey(t, 'cncm_status_all');
      await _settle(t);
      expect(rig.service.listManagedRequestsCalls.last.status, isNull);
      expect(find.byType(ConciergeCard), findsNWidgets(3));
      await t.tap(rzKey('cncm_category_'));
      await settleFor(t, 100);
      await t.tap(find.text('Temizlik').last);
      await _settle(t);
      expect(rig.service.listManagedRequestsCalls.last.category, 'temizlik');
      expect(find.byType(ConciergeCard), findsOneWidget);
    });

    testWidgets('durumu ilerlet + sakine görünür not: yalnız değişenler gönderilir; liste yenilenir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openTab(t, 'rezm_tab_concierge');
      await openRequest(t, 1);
      expect(rig.service.getManagedRequestCalls, <int>[1]);
      expect(find.text('Telefon'), findsOneWidget, reason: 'yönetici sakin telefonunu görür');
      // Hiçbir şey değişmediyse kaydet pasif.
      expect(t.widget<PrimaryActionButton>(rzKey('cnc_manage_save')).onPressed, isNull);
      await tapFinder(t, _prefixKey('cnc_manage_status_'));
      await settleFor(t, 100);
      await t.tap(find.text('Hazırlanıyor').last);
      await settleFor(t, 100);
      await _typeFinder(t, _prefixKey('cnc_manage_note_'), '  Ekip yolda.  ');
      await _tapKey(t, 'cnc_manage_save');
      await _settle(t);
      final call = rig.service.updateRequestCalls.single;
      expect(call.id, 1);
      expect(call.fields, <String, Object?>{'status': 'hazirlaniyor', 'note': 'Ekip yolda.'});
      await _tapKey(t, 'cnc_manage_close');
      await _settle(t);
      expect(find.text('Yönetim notu: Ekip yolda.'), findsOneWidget, reason: 'kapanışta liste yenilendi');
    });

    testWidgets('notu silmek `note: null` gönderir; yalnız not değiştiyse durum gönderilmez', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openTab(t, 'rezm_tab_concierge');
      await openRequest(t, 2);
      await _typeFinder(t, _prefixKey('cnc_manage_note_'), '');
      await _tapKey(t, 'cnc_manage_save');
      await _settle(t);
      expect(rig.service.updateRequestCalls.single.fields, <String, Object?>{'note': null});
    });

    testWidgets('tamamlanmış talep değiştirilemez (düğme yok, açıklama var)', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openTab(t, 'rezm_tab_concierge');
      await _tapKey(t, 'cncm_status_all');
      await _settle(t);
      await openRequest(t, 3);
      expect(rzKey('cnc_manage_closed_note'), findsOneWidget);
      expect(rzKey('cnc_manage_save'), findsNothing);
    });

    testWidgets('geçersiz geçiş (409): hata pencerede, durum sunucuyla eşitlenir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openTab(t, 'rezm_tab_concierge');
      await openRequest(t, 1);
      rig.service.failures['updateRequest'] = <Object>[
        FakeReservationService.error(409, 'INVALID_TRANSITION', payload: <String, dynamic>{'from': 'yeni', 'to': 'tamamlandi'}),
      ];
      await _typeFinder(t, _prefixKey('cnc_manage_note_'), 'Not');
      await _tapKey(t, 'cnc_manage_save');
      await _settle(t);
      expect(find.textContaining('Başka biri tarafından güncellenmiş olabilir'), findsOneWidget);
      expect(rig.service.getManagedRequestCalls.length, 2, reason: '409 sonrası ayrıntı sessizce tazelendi');
    });

    testWidgets('talep kalkmış (404): düz Türkçe uyarı', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openTab(t, 'rezm_tab_concierge');
      rig.service.failures['getManagedRequest'] = <Object>[FakeReservationService.error(404, 'CONCIERGE_NOT_FOUND')];
      await openRequest(t, 1);
      expect(rzKey('cnc_manage_gone'), findsOneWidget);
    });

    testWidgets('konsiyerj listesi hatası "talep yok" DEMEZ', (t) async {
      final rig = _rig();
      rig.service.failures['listManagedRequests'] = <Object>[ApiException('Talepler alınamadı.')];
      await rig.pump(t);
      await _openTab(t, 'rezm_tab_concierge');
      expect(find.text('Talepler alınamadı.'), findsOneWidget);
      expect(find.text('Açık konsiyerj talebi yok.'), findsNothing);
    });
  });

  group('alan yönetimi', () {
    testWidgets('yeni alan: varsayılanlar + ad; gövde sunucu alan adlarıyla; liste yenilenir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openTab(t, 'rezm_tab_areas');
      await _tapKey(t, 'rezm_area_add');
      await _settle(t);
      await _type(t, 'area_form_name', '  Tenis Kortu  ');
      await _tapKey(t, 'area_form_send');
      await _settle(t);
      final body = rig.service.createAreaCalls.single;
      expect(body['name'], 'Tenis Kortu');
      expect(body['description'], isNull);
      expect(body['capacity'], 1);
      expect(body['slot_minutes'], 60);
      expect(body['min_slots'], 1);
      expect(body['max_slots'], 4);
      expect(body['max_days_ahead'], 14);
      expect(body['approval_mode'], 'otomatik');
      expect(body['cancel_cutoff_hours'], 2);
      expect(body['per_user_daily_limit'], 2);
      expect(body['per_user_weekly_limit'], 5);
      expect((body['weekly_hours'] as List).length, 7);
      expect((body['weekly_hours'] as List).first, <String, dynamic>{'weekday': 1, 'start': '09:00', 'end': '22:00'});
      expect(rzKey('area_form_send'), findsNothing, reason: 'form kapandı');
      expect(find.textContaining('Alan eklendi'), findsOneWidget);
      expect(find.text('Tenis Kortu'), findsOneWidget, reason: 'yeni alan listede');
    });

    testWidgets('doğrulama: ad boş, en az > en çok, dilim 5\'in katı değil; istek yok', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openTab(t, 'rezm_tab_areas');
      await _tapKey(t, 'rezm_area_add');
      await _settle(t);
      await _type(t, 'area_form_slot', '17');
      await _type(t, 'area_form_min', '5');
      await _type(t, 'area_form_max', '2');
      await _tapKey(t, 'area_form_send');
      await _settle(t);
      expect(find.text('Alan adı boş olamaz.'), findsOneWidget);
      expect(find.text('Dilim süresi 5 ve katları olmalıdır.'), findsOneWidget);
      expect(find.text('En az dilim, en çok dilimden büyük olamaz.'), findsOneWidget);
      expect(find.text('Lütfen işaretli alanları düzeltin.'), findsOneWidget);
      expect(rig.service.createAreaCalls, isEmpty);
    });

    testWidgets('açık saat doğrulaması: kapanış açılıştan sonra; çakışma; dilim sığmaz', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openTab(t, 'rezm_tab_areas');
      await _tapKey(t, 'rezm_area_add');
      await _settle(t);
      await _type(t, 'area_form_name', 'Salon');
      await _type(t, 'area_form_1_0_end', '08:00');
      await _tapKey(t, 'area_form_send');
      await _settle(t);
      expect(find.text('Pazartesi: kapanış saati açılıştan sonra olmalıdır.'), findsOneWidget);

      await _type(t, 'area_form_1_0_end', '09:30');
      await _tapKey(t, 'area_form_send');
      await _settle(t);
      expect(find.textContaining('Pazartesi: her aralığa en az bir dilim'), findsOneWidget);

      await _type(t, 'area_form_1_0_end', '12:00');
      await _tapKey(t, 'area_form_add_1');
      await _settle(t);
      await _type(t, 'area_form_1_1_start', '11:00');
      await _type(t, 'area_form_1_1_end', '14:00');
      await _tapKey(t, 'area_form_send');
      await _settle(t);
      expect(find.text('Pazartesi: açık saat aralıkları çakışamaz.'), findsOneWidget);
      expect(rig.service.createAreaCalls, isEmpty);
    });

    testWidgets('aralık sil / ekle: silinen gün kapalı olur; günde en çok 3 aralık', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openTab(t, 'rezm_tab_areas');
      await _tapKey(t, 'rezm_area_add');
      await _settle(t);
      await _tapKey(t, 'area_form_remove_7_0');
      await _settle(t);
      expect(rzKey('area_form_closed_7'), findsOneWidget);
      await _type(t, 'area_form_name', 'Hafta içi salon');
      await _tapKey(t, 'area_form_send');
      await _settle(t);
      final hours = rig.service.createAreaCalls.single['weekly_hours'] as List;
      expect(hours.length, 6, reason: 'pazar kapalı');
      expect(hours.any((h) => (h as Map)['weekday'] == 7), isFalse);

      await _tapKey(t, 'rezm_area_add');
      await _settle(t);
      await _tapKey(t, 'area_form_add_2');
      await _tapKey(t, 'area_form_add_2');
      expect(rzKey('area_form_add_2'), findsNothing, reason: 'günde en çok 3 aralık');
    });

    testWidgets('ad çakışması (409): hata pencerede, girilenler korunur', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openTab(t, 'rezm_tab_areas');
      await _tapKey(t, 'rezm_area_add');
      await _settle(t);
      await _type(t, 'area_form_name', 'Spor Salonu');
      await _tapKey(t, 'area_form_send');
      await _settle(t);
      expect(find.textContaining('aynı adlı bir alan zaten var'), findsOneWidget);
      expect(find.descendant(of: rzKey('area_form_name'), matching: find.text('Spor Salonu')), findsOneWidget);
      expect(rzKey('area_form_send'), findsOneWidget);
    });

    testWidgets('düzenleme: mevcut değerler dolu; yalnız DEĞİŞEN alan gönderilir; değişiklik yoksa istek yok', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openTab(t, 'rezm_tab_areas');
      await _tapKey(t, 'rezm_area_edit_1');
      await _settle(t);
      expect(find.text('Alanı Düzenle'), findsOneWidget);
      expect(find.descendant(of: rzKey('area_form_name'), matching: find.text('Spor Salonu')), findsOneWidget);
      expect(find.descendant(of: rzKey('area_form_capacity'), matching: find.text('1')), findsOneWidget);
      // Değişiklik yok: kaydet sunucuya gitmeden kapanır.
      await _tapKey(t, 'area_form_send');
      await _settle(t);
      expect(rig.service.updateAreaCalls, isEmpty);
      expect(rzKey('area_form_send'), findsNothing);

      await _tapKey(t, 'rezm_area_edit_1');
      await _settle(t);
      await _type(t, 'area_form_capacity', '5');
      await _tapKey(t, 'area_form_send');
      await _settle(t);
      expect(rig.service.updateAreaCalls.single.id, 1);
      expect(rig.service.updateAreaCalls.single.fields, <String, Object?>{'capacity': 5});
      expect(find.textContaining('Alan güncellendi'), findsOneWidget);
    });

    testWidgets('pasifleştir: onay penceresi, `is_active: false`; pasif alan tek dokunuşla etkinleşir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openTab(t, 'rezm_tab_areas');
      await _tapKey(t, 'rezm_area_toggle_1');
      await settleFor(t, 100);
      expect(find.text('Alan pasifleştirilsin mi?'), findsOneWidget);
      await _tapKey(t, 'area_deactivate_keep');
      await settleFor(t, 100);
      expect(rig.service.updateAreaCalls, isEmpty);
      await _tapKey(t, 'rezm_area_toggle_1');
      await settleFor(t, 100);
      await _tapKey(t, 'area_deactivate_confirm');
      await _settle(t);
      expect(rig.service.updateAreaCalls.single.fields, <String, Object?>{'is_active': false});
      expect(find.textContaining('Alan pasifleştirildi'), findsOneWidget);

      await _tapKey(t, 'rezm_area_toggle_3');
      await _settle(t);
      expect(rig.service.updateAreaCalls.last.id, 3);
      expect(rig.service.updateAreaCalls.last.fields, <String, Object?>{'is_active': true});
    });

    testWidgets('alan listesi hatası "alan yok" DEMEZ; modül kapalıysa açıklayıcı kart', (t) async {
      final rig = _rig();
      await rig.pump(t);
      rig.service.failures['listManagedAreas'] = <Object>[ApiException('Alanlar alınamadı.')];
      await _openTab(t, 'rezm_tab_areas');
      expect(find.text('Alanlar alınamadı.'), findsOneWidget);
      expect(find.text('Henüz ortak alan tanımlanmamış.'), findsNothing);
      rig.service.failures['listManagedAreas'] = <Object>[FakeReservationService.moduleOff()];
      await rig.key.currentState!.reload();
      await _settle(t);
      expect(rzKey('reservation_module_off'), findsOneWidget);
    });
  });
}
