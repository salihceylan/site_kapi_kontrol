// Rezervasyon ve Konsiyerj: sakin "Rezervasyon" ekranı (ReservationResidentView) + rezervasyon penceresi + konsiyerj formu.
//
// Kapsam: taşma matrisi (320x640 x2,0; 360x640 x1,5; yatay 640x360 x2,0; tablet 768x1024; açık / koyu), yükleniyor /
// hata / boş / dolu ayrımı (HATA ASLA "kayıt yok" demez), modül kapalı durumu, alan -> gün -> dilim -> süre -> gönder
// akışı, onay modu bilgisi, çakışma / hız sınırı / çift gönderim, rezervasyonlarım (yaklaşan / geçmiş, iptal süresi
// dolunca PASİF düğme + neden), konsiyerj talebi açma / iptal, site süzgeci ve imleçli sayfalama.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/reservation_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/design/buttons.dart' show PrimaryActionButton;
import 'package:site_kapi_kontrol/ui/dialogs/concierge_request_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/reservation_resident_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/reservation_parts.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart' show pumpList, tapFinder;
import 'reservation_fixtures.dart';

const List<PeopleSite> _oneSite = <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi')];
const List<PeopleSite> _twoSites = <PeopleSite>[
  PeopleSite(code: 11, name: 'Gül Sitesi'),
  PeopleSite(code: 12, name: 'Mavi Park'),
];

class _Rig {
  _Rig(this.service, this.auth);

  final FakeReservationService service;
  final ReservationFakeAuth auth;
  final GlobalKey<ReservationResidentViewState> key = GlobalKey<ReservationResidentViewState>();

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
      ReservationResidentView(key: key, authService: auth, service: service, sites: sites),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    await settleFor(t, 100);
    await settleFor(t, 100);
  }
}

_Rig _rig() {
  final auth = ReservationFakeAuth();
  return _Rig(seededReservation(auth), auth);
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

Future<void> _openTab(WidgetTester t, String key) async {
  await _tapKey(t, key);
  await _settle(t);
}

Future<void> _openBooking(WidgetTester t, int areaId) async {
  await _tapKey(t, 'rez_book_$areaId');
  await _settle(t);
}

void main() {
  group('taşma matrisi', () {
    reservationMatrix('alanlar: aktif alanlar, onay modu, Rezervasyon Yap', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark, sites: _twoSites);
      expect(find.byType(ReservationAreaCard), findsNWidgets(2));
      expect(find.text('Spor Salonu'), findsOneWidget);
      expect(find.text('Toplantı Odası'), findsOneWidget);
      expect(find.text('Eski Sauna'), findsNothing, reason: 'pasif alan sakine gösterilmez');
      expect(find.text('Yönetici onaylı'), findsOneWidget);
      expect(find.text('Otomatik onay'), findsOneWidget);
      expect(rzKey('rez_book_1'), findsOneWidget);
      expect(rzKey('rez_book_2'), findsOneWidget);
      expect(find.text('Gül Sitesi'), findsWidgets, reason: 'çok siteli sakinde kartta site adı');
    });

    reservationMatrix('rezervasyonlarım: rozetler, iptal düğmesi pasif + neden metni', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark, sites: _twoSites);
      await _openTab(t, 'rez_tab_mine');
      expect(find.byType(MyReservationCard), findsNWidgets(2));
      expect(find.text('Onaylandı'), findsOneWidget);
      expect(find.text('Onay bekliyor'), findsOneWidget);
      expect(t.widget<PrimaryActionButton>(rzKey('rez_cancel_1')).onPressed, isNotNull);
      expect(t.widget<PrimaryActionButton>(rzKey('rez_cancel_2')).onPressed, isNull);
      expect(find.text('Son iptal zamanı: 20.10.2026 16:00'), findsOneWidget);
      expect(find.textContaining('İptal süresi doldu'), findsOneWidget);
    });

    reservationMatrix('konsiyerj: açık talepler, yönetim notu, iptal', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await _openTab(t, 'rez_tab_concierge');
      expect(find.byType(ConciergeCard), findsNWidgets(2));
      expect(find.text('Yeni'), findsOneWidget);
      expect(find.text('Hazırlanıyor'), findsOneWidget);
      expect(find.text('Yönetim notu: Ekip öğleden sonra gelecek.'), findsOneWidget);
      expect(rzKey('cnc_new_request'), findsOneWidget);
      expect(rzKey('cnc_cancel_1'), findsOneWidget);
      expect(rzKey('cnc_cancel_2'), findsNothing, reason: 'hazırlanıyor: sakin iptal edemez');
    });

    reservationMatrix('hata: "kayıt yok" DEMEZ; Tekrar Dene görünür', (t, w, h, s, dark) async {
      final rig = _rig();
      rig.service.failures['listAreas'] = <Object>[ApiException('Sunucuya bağlanılamadı.')];
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Sunucuya bağlanılamadı.'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.text('Rezervasyona açık alan yok.'), findsNothing);
    });

    reservationMatrix('modül kapalı: açıklayıcı kart', (t, w, h, s, dark) async {
      final rig = _rig();
      rig.service.failures['listAreas'] = <Object>[FakeReservationService.moduleOff()];
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      expect(rzKey('reservation_module_off'), findsOneWidget);
      expect(find.text('Rezervasyon ve Konsiyerj bu site için kapalı.'), findsOneWidget);
      expect(find.byType(ReservationAreaCard), findsNothing);
    });

    reservationMatrix('rezervasyon penceresi: gün, dilim, onay notu', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await _openBooking(t, 2);
      expect(rzKey('rez_approval_note'), findsOneWidget);
      expect(rzKey('rez_day_2026-10-20'), findsOneWidget);
      expect(rzKey('rez_day_2026-10-22'), findsOneWidget);
      expect(find.text('Çar 21.10'), findsOneWidget);
      expect(rzKey('rez_slot_0'), findsOneWidget);
      expect(rzKey('rez_booking_send'), findsOneWidget);
    });

    reservationMatrix('konsiyerj formu', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark, sites: _twoSites);
      await _openTab(t, 'rez_tab_concierge');
      await _tapKey(t, 'cnc_new_request');
      await _settle(t);
      expect(rzKey('cnc_form_category'), findsOneWidget);
      expect(rzKey('cnc_form_note'), findsOneWidget);
      expect(rzKey('cnc_form_date'), findsOneWidget);
      expect(rzKey('cnc_form_send'), findsOneWidget);
    });
  });

  group('liste durumları', () {
    testWidgets('yüklenirken iskelet; "kayıt yok" ve hata YOK', (t) async {
      final rig = _rig();
      final gate = Completer<void>();
      rig.service.gates['listAreas'] = <Completer<void>>[gate];
      await pumpList(
        t,
        ReservationResidentView(key: rig.key, authService: rig.auth, service: rig.service, sites: _oneSite),
        width: 400,
        height: 2400,
        scale: 1.0,
        dark: false,
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.text('Rezervasyona açık alan yok.'), findsNothing);
      expect(find.byType(InlineNotice), findsNothing);
      gate.complete();
      await settleFor(t, 100);
      expect(find.byType(ReservationAreaCard), findsNWidgets(2));
    });

    testWidgets('hata sonrası Tekrar Dene listeyi getirir', (t) async {
      final rig = _rig();
      rig.service.failures['listAreas'] = <Object>[ApiException('Bağlantı yok.')];
      await rig.pump(t);
      expect(find.byType(ReservationAreaCard), findsNothing);
      await tapFinder(t, find.text('Tekrar Dene'));
      await settleFor(t, 100);
      expect(find.byType(ReservationAreaCard), findsNWidgets(2));
      expect(find.text('Bağlantı yok.'), findsNothing);
    });

    testWidgets('hata varken eski liste korunur (yenileme hatası listeyi silmez)', (t) async {
      final rig = _rig();
      await rig.pump(t);
      rig.service.failures['listAreas'] = <Object>[ApiException('Yenilenemedi.')];
      await rig.key.currentState!.reload();
      await settleFor(t, 100);
      expect(find.byType(ReservationAreaCard), findsNWidgets(2));
      expect(find.text('Yenilenemedi.'), findsOneWidget);
    });

    testWidgets('alan yoksa boş durum; site yoksa açıklayıcı kart ve sekme yok', (t) async {
      final auth = ReservationFakeAuth();
      final rig = _Rig(FakeReservationService(authService: auth), auth);
      await rig.pump(t);
      expect(find.text('Rezervasyona açık alan yok.'), findsOneWidget);
      await rig.pump(t, sites: const <PeopleSite>[]);
      expect(find.text('Rezervasyon yapabileceğiniz site yok.'), findsOneWidget);
      expect(rzKey('rez_tab_areas'), findsNothing);
    });

    testWidgets('site süzgeci site_code gönderir; yalnız çok siteli sakinde çıkar', (t) async {
      final rig = _rig();
      await rig.pump(t);
      expect(find.text('Tüm siteler'), findsNothing, reason: 'tek sitede süzgeç yok');
      expect(rig.service.listAreasCalls.last, isNull);
      await rig.pump(t, sites: _twoSites);
      await t.tap(find.byType(DropdownButtonFormField<int>));
      await settleFor(t, 100);
      await t.tap(find.text('Mavi Park').last);
      await _settle(t);
      expect(rig.service.listAreasCalls.last, 12);
    });

    testWidgets('rezervasyonlarım: imleçli sayfalama 30 + "Daha fazla yükle" -> 35', (t) async {
      final auth = ReservationFakeAuth();
      final service = FakeReservationService(authService: auth);
      service.areas.add(rzArea(1));
      for (var i = 1; i <= 35; i++) {
        service.reservations.add(rzReservation(i, note: 'Kayıt $i'));
      }
      final rig = _Rig(service, auth);
      await rig.pump(t, height: 16000);
      await _openTab(t, 'rez_tab_mine');
      expect(find.byType(MyReservationCard), findsNWidgets(30));
      await tapFinder(t, find.text('Daha fazla yükle'));
      await settleFor(t, 100);
      expect(find.byType(MyReservationCard), findsNWidgets(35));
      expect(find.text('Daha fazla yükle'), findsNothing);
      expect(service.listMineCalls.last.before, 6, reason: 'imleç son kartın kimliği');
    });
  });

  group('rezervasyon penceresi', () {
    testWidgets('otomatik onay: gün + dilim seç, gönder; gövde doğru; "Rezervasyonlarım"a geçilir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openBooking(t, 1);
      expect(rig.service.availabilityCalls.single.area, 1);
      expect(rig.service.availabilityCalls.single.from, isNull, reason: 'ilk pencere: sunucu varsayılanı');
      expect(find.textContaining('seçtiğiniz anda onaylanır'), findsOneWidget);
      expect(t.widget<ChoiceChip>(rzKey('rez_day_2026-10-20')).selected, isTrue, reason: 'boş dilimi olan ilk gün seçili');
      expect(find.text('10:00 - 11:00 · Dolu'), findsOneWidget);
      expect(t.widget<ChoiceChip>(rzKey('rez_slot_1')).onSelected, isNull, reason: 'dolu dilim pasif');
      expect(rzKey('rez_summary'), findsNothing);

      await _tapKey(t, 'rez_slot_0');
      expect(find.textContaining('09:00-10:00 (1 dilim, 1 saat)'), findsOneWidget);
      expect(rzKey('rez_slot_count_0_1'), findsNothing, reason: 'sonraki dilim dolu: süre seçeneği yok');

      await _type(t, 'rez_note', '  Antrenman  ');
      await _tapKey(t, 'rez_booking_send');
      await _settle(t);
      final sent = rig.service.createCalls.single;
      expect(sent.siteCode, 11);
      expect(sent.areaId, 1);
      expect(sent.date, '2026-10-20');
      expect(sent.start, '09:00');
      expect(sent.slots, 1);
      expect(sent.note.trim(), 'Antrenman');
      expect(rzKey('rez_booking_send'), findsNothing, reason: 'pencere kapandı');
      expect(find.textContaining('Rezervasyonunuz onaylandı'), findsOneWidget);
      expect(t.widget<ChoiceChip>(rzKey('rez_tab_mine')).selected, isTrue);
      expect(find.byType(MyReservationCard), findsNWidgets(3), reason: 'yeni kayıt yaklaşan listede');
    });

    testWidgets('yönetici onaylı alan: bilgi notu, kalan kapasite, "onay bekliyor" mesajı', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openBooking(t, 2);
      expect(find.textContaining('yönetici onayına gönderilir'), findsOneWidget);
      expect(find.text('09:00 - 10:00 · 2 boş'), findsOneWidget, reason: 'kapasite 3, 1 dolu');
      await _tapKey(t, 'rez_slot_0');
      await _tapKey(t, 'rez_booking_send');
      await _settle(t);
      expect(rig.service.createCalls.single.areaId, 2);
      expect(find.textContaining('Yönetici onayı bekleniyor'), findsOneWidget);
      expect(find.text('Onay bekliyor'), findsNWidgets(2));
    });

    testWidgets('birden çok dilim: süre seçilir, özet ve gövde güncellenir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openBooking(t, 1);
      await _tapKey(t, 'rez_day_2026-10-21');
      await _tapKey(t, 'rez_slot_0');
      expect(rzKey('rez_slot_count_0_1'), findsOneWidget);
      await _tapKey(t, 'rez_slot_count_0_1');
      await settleFor(t, 100);
      await t.tap(find.text('2 dilim (2 saat)').last);
      await settleFor(t, 100);
      expect(find.textContaining('09:00-11:00 (2 dilim, 2 saat)'), findsOneWidget);
      await _tapKey(t, 'rez_booking_send');
      await _settle(t);
      final sent = rig.service.createCalls.single;
      expect(sent.date, '2026-10-21');
      expect(sent.slots, 2);
    });

    testWidgets('kapalı gün: açıklama; saat seçmeden gönderim yok', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openBooking(t, 1);
      expect(find.text('Per 22.10 · Kapalı'), findsOneWidget);
      await _tapKey(t, 'rez_day_2026-10-22');
      expect(rzKey('rez_no_slots'), findsOneWidget);
      await _tapKey(t, 'rez_booking_send');
      await _settle(t);
      expect(find.text('Önce bir gün ve saat seçin.'), findsOneWidget);
      expect(rig.service.createCalls, isEmpty);
    });

    testWidgets('çakışma (SLOT_FULL): hata pencerede kalır, boş saatler tazelenir, dolan dilim seçimden düşer', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openBooking(t, 1);
      await _tapKey(t, 'rez_slot_0');
      // Bu arada başkası aynı dilimi aldı.
      final slot = ((rig.service.availabilityDays[1]!.first['slots'] as List).first as Map<String, dynamic>);
      slot
        ..['booked'] = 1
        ..['available'] = false;
      await _tapKey(t, 'rez_booking_send');
      await _settle(t);
      expect(find.textContaining('Seçtiğiniz saat bu arada doldu'), findsOneWidget);
      expect(rzKey('rez_booking_send'), findsOneWidget, reason: 'pencere açık kalır');
      expect(rig.service.availabilityCalls.length, 2, reason: 'boş saatler sessizce yenilendi');
      expect(rzKey('rez_summary'), findsNothing, reason: 'dolan dilim seçimden düştü');
      expect(find.text('09:00 - 10:00 · Dolu'), findsOneWidget);
    });

    testWidgets('boş saatler yüklenemedi: Tekrar Dene yeniden yükler', (t) async {
      final rig = _rig();
      await rig.pump(t);
      rig.service.failures['availability'] = <Object>[ApiException('Boş saatler alınamadı.')];
      await _openBooking(t, 1);
      expect(find.text('Boş saatler alınamadı.'), findsOneWidget);
      expect(rzKey('rez_day_2026-10-20'), findsNothing);
      await tapFinder(t, find.text('Tekrar Dene'));
      await _settle(t);
      expect(find.text('Boş saatler alınamadı.'), findsNothing);
      expect(rzKey('rez_day_2026-10-20'), findsOneWidget);
    });

    testWidgets('alan artık yok (404): düz Türkçe uyarı, gönderim düğmesi yok', (t) async {
      final rig = _rig();
      await rig.pump(t);
      rig.service.failures['availability'] = <Object>[FakeReservationService.error(404, 'AREA_NOT_FOUND')];
      await _openBooking(t, 1);
      expect(rzKey('rez_booking_area_closed'), findsOneWidget);
      expect(rzKey('rez_booking_send'), findsNothing);
    });

    testWidgets('çift gönderim: düğme kapanır, tek istek; geri tuşu gönderim sürerken kapatmaz', (t) async {
      final rig = _rig();
      await rig.pump(t);
      final gate = Completer<void>();
      rig.service.gates['create'] = <Completer<void>>[gate];
      await _openBooking(t, 1);
      await _tapKey(t, 'rez_slot_0');
      await _tapKey(t, 'rez_booking_send');
      expect(find.text('Gönderiliyor...'), findsOneWidget);
      await t.tap(rzKey('rez_booking_send'), warnIfMissed: false);
      await t.pump();
      expect(rig.service.createCalls.length, 1);
      expect(t.widget<ElevatedButton>(rzKey('rez_booking_send')).onPressed, isNull);
      await t.binding.handlePopRoute();
      await t.pump();
      expect(rzKey('rez_booking_send'), findsOneWidget, reason: 'gönderim sürerken kapanmaz');
      gate.complete();
      await settleFor(t, 100);
      await settleFor(t, 500);
      expect(rzKey('rez_booking_send'), findsNothing);
    });

    testWidgets('429: gönder kilitlenir, sunucunun süre metni görünür, süre dolunca açılır', (t) async {
      final rig = _rig();
      await rig.pump(t);
      rig.service.failures['create'] = <Object>[
        ApiException(
          'Bir saat içinde çok fazla rezervasyon yaptınız. 30 saniye sonra tekrar deneyin.',
          statusCode: 429,
          code: 'RESERVATION_RATE_LIMITED',
          retryAfterSeconds: 30,
        ),
      ];
      await _openBooking(t, 1);
      await _tapKey(t, 'rez_slot_0');
      await _tapKey(t, 'rez_booking_send');
      await settleFor(t, 100);
      expect(find.text('Bir saat içinde çok fazla rezervasyon yaptınız. 30 saniye sonra tekrar deneyin.'), findsOneWidget);
      expect(t.widget<ElevatedButton>(rzKey('rez_booking_send')).onPressed, isNull);
      await t.pump(const Duration(seconds: 31));
      expect(t.widget<ElevatedButton>(rzKey('rez_booking_send')).onPressed, isNotNull);
      await _tapKey(t, 'rez_booking_close');
      await settleFor(t, 100);
      expect(rzKey('rez_booking_send'), findsNothing);
    });

    testWidgets('gönderim hatası: seçim ve not korunur, yeniden denemede başarı', (t) async {
      final rig = _rig();
      await rig.pump(t);
      rig.service.failures['create'] = <Object>[
        FakeReservationService.error(409, 'RESERVATION_DAILY_LIMIT', payload: <String, dynamic>{'daily_limit': 2}),
      ];
      await _openBooking(t, 1);
      await _tapKey(t, 'rez_slot_0');
      await _type(t, 'rez_note', 'Not');
      await _tapKey(t, 'rez_booking_send');
      await _settle(t);
      expect(find.text('Bu alanda aynı gün için en çok 2 rezervasyon yapabilirsiniz.'), findsOneWidget);
      expect(find.descendant(of: rzKey('rez_note'), matching: find.text('Not')), findsOneWidget);
      expect(find.textContaining('09:00-10:00'), findsOneWidget, reason: 'seçim korundu');
      await _tapKey(t, 'rez_booking_send');
      await _settle(t);
      expect(rig.service.createCalls.length, 2);
      expect(rzKey('rez_booking_send'), findsNothing);
    });

    testWidgets('Vazgeç: istek atılmaz', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openBooking(t, 1);
      await _tapKey(t, 'rez_booking_close');
      await settleFor(t, 100);
      expect(rzKey('rez_booking_send'), findsNothing);
      expect(rig.service.createCalls, isEmpty);
    });
  });

  group('rezervasyonlarım', () {
    testWidgets('geçmiş sekmesi: tamamlanan ve yönetimce iptal edilen; iptal düğmesi yok, neden görünür', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openTab(t, 'rez_tab_mine');
      expect(rig.service.listMineCalls.last.scope, 'upcoming');
      await _tapKey(t, 'rez_scope_past');
      await _settle(t);
      expect(rig.service.listMineCalls.last.scope, 'past');
      expect([for (final c in t.widgetList<MyReservationCard>(find.byType(MyReservationCard))) c.record.id], <int>[4, 3]);
      expect(find.text('Tamamlandı'), findsOneWidget);
      expect(find.text('İptal edildi'), findsOneWidget);
      expect(find.text('Yönetim iptal etti.'), findsOneWidget);
      expect(find.text('Yönetim notu: Bakım nedeniyle kapalı.'), findsOneWidget);
      expect(rzKey('rez_cancel_3'), findsNothing);
      expect(rzKey('rez_cancel_4'), findsNothing);
    });

    testWidgets('iptal: onay penceresi, vazgeçilince çağrı yok, onayda iptal + liste yenilenir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openTab(t, 'rez_tab_mine');
      await _tapKey(t, 'rez_cancel_1');
      await settleFor(t, 100);
      expect(find.text('Rezervasyon iptal edilsin mi?'), findsOneWidget);
      await _tapKey(t, 'rez_cancel_keep');
      await settleFor(t, 100);
      expect(rig.service.cancelCalls, isEmpty);
      await _tapKey(t, 'rez_cancel_1');
      await settleFor(t, 100);
      await _tapKey(t, 'rez_cancel_confirm');
      await _settle(t);
      expect(rig.service.cancelCalls, <int>[1]);
      expect(find.textContaining('Rezervasyonunuz iptal edildi'), findsWidgets);
      expect(find.byType(MyReservationCard), findsOneWidget, reason: 'iptal edilen yaklaşan listeden düştü');
    });

    testWidgets('iptal süresi dolmuş kayıt: düğme pasif, dokunma çağrı yapmaz', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openTab(t, 'rez_tab_mine');
      await t.ensureVisible(rzKey('rez_cancel_2'));
      await t.tap(rzKey('rez_cancel_2'), warnIfMissed: false);
      await settleFor(t, 100);
      expect(find.text('Rezervasyon iptal edilsin mi?'), findsNothing);
      expect(rig.service.cancelCalls, isEmpty);
    });

    testWidgets('sunucu iptal süresini doldurmuş sayar (409): düz Türkçe mesaj, liste sunucuyla eşitlenir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openTab(t, 'rez_tab_mine');
      final before = rig.service.listMineCalls.length;
      rig.service.failures['cancelMine'] = <Object>[
        FakeReservationService.error(409, 'CANCEL_WINDOW_CLOSED', payload: <String, dynamic>{'cancel_cutoff_hours': 2}),
      ];
      await _tapKey(t, 'rez_cancel_1');
      await settleFor(t, 100);
      await _tapKey(t, 'rez_cancel_confirm');
      await _settle(t);
      expect(find.textContaining('Başlangıca 2 saatten az kaldığı için iptal edilemez'), findsOneWidget);
      expect(rig.service.listMineCalls.length, before + 1);
    });
  });

  group('konsiyerj', () {
    testWidgets('yeni talep: kategori + not gönderilir; liste yenilenir; istenen zaman yoksa gönderilmez', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openTab(t, 'rez_tab_concierge');
      await _tapKey(t, 'cnc_new_request');
      await _settle(t);
      await _type(t, 'cnc_form_note', '  Kargo bekliyor  ');
      await _tapKey(t, 'cnc_form_send');
      await _settle(t);
      final sent = rig.service.createRequestCalls.single;
      expect(sent.siteCode, 11);
      expect(sent.category, ConciergeCategory.paketTeslim);
      expect(sent.note.trim(), 'Kargo bekliyor');
      expect(sent.requestedFor, isNull);
      expect(sent.toJson('rz-12345678').containsKey('requested_for'), isFalse);
      expect(rzKey('cnc_form_send'), findsNothing, reason: 'form kapandı');
      expect(find.textContaining('Talebiniz alındı'), findsOneWidget);
      expect(find.text('Kargo bekliyor'), findsOneWidget, reason: 'yeni talep açık listede');
    });

    testWidgets('"Diğer" kategorisinde açıklama zorunlu; istek atılmaz', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openTab(t, 'rez_tab_concierge');
      await _tapKey(t, 'cnc_new_request');
      await _settle(t);
      await _tapKey(t, 'cnc_form_category');
      await settleFor(t, 100);
      await t.tap(find.text('Diğer').last);
      await settleFor(t, 100);
      await _tapKey(t, 'cnc_form_send');
      await settleFor(t, 100);
      expect(find.text('Diğer talepler için açıklama yazın.'), findsOneWidget);
      expect(find.text('Lütfen işaretli alanları düzeltin.'), findsOneWidget);
      expect(rig.service.createRequestCalls, isEmpty);
    });

    testWidgets('gönderim hatası pencerede kalır, not korunur', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openTab(t, 'rez_tab_concierge');
      rig.service.failures['createRequest'] = <Object>[
        FakeReservationService.error(409, 'CONCIERGE_USER_LIMIT', payload: <String, dynamic>{'user_open_limit': 10}),
      ];
      await _tapKey(t, 'cnc_new_request');
      await _settle(t);
      await _type(t, 'cnc_form_note', 'Paket');
      await _tapKey(t, 'cnc_form_send');
      await _settle(t);
      expect(find.textContaining('en çok 10 açık talebiniz olabilir'), findsOneWidget);
      expect(rzKey('cnc_form_send'), findsOneWidget);
      expect(find.descendant(of: rzKey('cnc_form_note'), matching: find.text('Paket')), findsOneWidget);
    });

    testWidgets('talebi iptal: onay, çağrı, liste yenilenir; vazgeçilince çağrı yok', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openTab(t, 'rez_tab_concierge');
      await _tapKey(t, 'cnc_cancel_1');
      await settleFor(t, 100);
      await _tapKey(t, 'cnc_cancel_keep');
      await settleFor(t, 100);
      expect(rig.service.cancelRequestCalls, isEmpty);
      await _tapKey(t, 'cnc_cancel_1');
      await settleFor(t, 100);
      await _tapKey(t, 'cnc_cancel_confirm');
      await _settle(t);
      expect(rig.service.cancelRequestCalls, <int>[1]);
      expect(rzKey('cnc_cancel_1'), findsNothing);
      expect(find.byType(ConciergeCard), findsOneWidget, reason: 'açık listede yalnız hazırlanıyor kaldı');
    });

    testWidgets('iptal sırasında talep ilerlemiş (409): mesaj + liste sunucuyla eşitlenir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openTab(t, 'rez_tab_concierge');
      final before = rig.service.listMyRequestsCalls.length;
      rig.service.failures['cancelRequest'] = <Object>[FakeReservationService.error(409, 'CONCIERGE_CLOSED')];
      await _tapKey(t, 'cnc_cancel_1');
      await settleFor(t, 100);
      await _tapKey(t, 'cnc_cancel_confirm');
      await _settle(t);
      expect(find.textContaining('Tamamlanmış ya da iptal edilmiş talepte değişiklik yapılamaz'), findsOneWidget);
      expect(rig.service.listMyRequestsCalls.length, before + 1);
    });

    testWidgets('durum süzgeci: Kapanan -> yalnız tamamlanan; sorgu sunucuya gider; boş kapanan mesajı', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openTab(t, 'rez_tab_concierge');
      expect(rig.service.listMyRequestsCalls.last.status, 'open');
      await _tapKey(t, 'cnc_status_closed');
      await _settle(t);
      expect(rig.service.listMyRequestsCalls.last.status, 'closed');
      expect([for (final c in t.widgetList<ConciergeCard>(find.byType(ConciergeCard))) c.record.id], <int>[3]);
      expect(find.text('Tamamlandı'), findsOneWidget);
      rig.service.requests.removeWhere((r) => r['status'] == 'tamamlandi');
      await _tapKey(t, 'cnc_status_all');
      await _tapKey(t, 'cnc_status_closed');
      await _settle(t);
      expect(find.text('Kapanmış talebiniz yok.'), findsOneWidget);
    });

    testWidgets('konsiyerj listesi hatası "talep yok" DEMEZ; modül kapalıysa açıklayıcı kart', (t) async {
      final rig = _rig();
      rig.service.failures['listMyRequests'] = <Object>[ApiException('Talepler alınamadı.')];
      await rig.pump(t);
      await _openTab(t, 'rez_tab_concierge');
      expect(find.text('Talepler alınamadı.'), findsOneWidget);
      expect(find.text('Açık konsiyerj talebiniz yok.'), findsNothing);
      rig.service.failures['listMyRequests'] = <Object>[FakeReservationService.moduleOff()];
      await rig.key.currentState!.reload();
      await _settle(t);
      expect(rzKey('reservation_module_off'), findsOneWidget);
    });
  });

  group('istenen zaman (İstanbul saati)', () {
    // 18 Ekim 2026 03:00 İstanbul (00:00 UTC): 09:00 seçimi gelecektedir.
    DateTime clock() => DateTime.utc(2026, 10, 18, 0, 0);

    Future<FakeReservationService> openForm(WidgetTester t) async {
      final auth = ReservationFakeAuth();
      final service = seededReservation(auth);
      t.view.physicalSize = const Size(800, 1600);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  key: const ValueKey<String>('open_form'),
                  onPressed: () => unawaited(
                    ConciergeRequestFormDialog.show(context, service: service, sites: _oneSite, clock: clock),
                  ),
                  child: const Text('Aç'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(rzKey('open_form'));
      await settleFor(t, 100);
      await settleFor(t, 300);
      return service;
    }

    testWidgets('yalnız gün seçmek yetmez: "hem gün hem saat" uyarısı, istek yok', (t) async {
      final service = await openForm(t);
      await t.tap(rzKey('cnc_form_date'));
      await settleFor(t, 300);
      await t.tap(find.text('OK'));
      await settleFor(t, 300);
      expect(find.text('18.10.2026'), findsOneWidget, reason: 'bugün (İstanbul) varsayılan gün');
      await t.tap(rzKey('cnc_form_send'));
      await settleFor(t, 300);
      expect(find.textContaining('hem gün hem saat'), findsOneWidget);
      expect(service.createRequestCalls, isEmpty);
    });

    testWidgets('gün + saat: istenen an İstanbul saatinden UTC\'ye çevrilip gönderilir', (t) async {
      final service = await openForm(t);
      await t.tap(rzKey('cnc_form_date'));
      await settleFor(t, 300);
      await t.tap(find.text('OK'));
      await settleFor(t, 300);
      await t.tap(rzKey('cnc_form_time'));
      await settleFor(t, 300);
      await t.tap(find.text('OK'));
      await settleFor(t, 300);
      expect(find.text('09:00'), findsOneWidget, reason: 'varsayılan saat');
      await t.tap(rzKey('cnc_form_send'));
      await settleFor(t, 300);
      await settleFor(t, 300);
      final sent = service.createRequestCalls.single;
      expect(sent.requestedFor, DateTime.utc(2026, 10, 18, 6, 0), reason: '09:00 İstanbul = 06:00 UTC');
      expect(sent.toJson('rz-12345678')['requested_for'], '2026-10-18T06:00:00.000Z');
    });
  });
}
