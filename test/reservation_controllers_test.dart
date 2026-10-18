// Rezervasyon ve Konsiyerj denetleyicileri (lib/ui/views/reservation_controllers.dart): boş saat pencereleri
// (İstanbul takvimi), seçim kuralları, gönderim / çakışma akışı, karar ve konsiyerj güncelleme hata sınıflandırması.
// Ekransız birim testi: yarış (eski yanıt yeni durumu ezmez, dispose sonrası yanıt yok sayılır) ve hata durumları.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/reservation_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/views/reservation_controllers.dart';

import 'screens/reservation_fixtures.dart';

// 18 Ekim 2026 12:00 İstanbul (09:00 UTC).
DateTime _noon() => DateTime.utc(2026, 10, 18, 9);

ReservationBookingController _booking(
  FakeReservationService service, {
  int areaId = 1,
  DateTime Function()? clock,
}) {
  final area = ReservationArea.fromJson(service.areas.firstWhere((a) => a['id'] == areaId));
  return ReservationBookingController(service: service, area: area, clock: clock ?? _noon);
}

FakeReservationService _service() => seededReservation(ReservationFakeAuth());

void main() {
  group('ReservationBookingController: pencere ve seçim', () {
    test('yükleme: boş dilimi olan ilk gün seçilir; ilk pencerede from gönderilmez', () async {
      final service = _service();
      final c = _booking(service);
      await c.load();
      expect(c.loading, isFalse);
      expect(service.availabilityCalls.single.from, isNull);
      expect(c.days.length, 3);
      expect(c.selectedDate, '2026-10-20');
      expect(c.selectedSlot, isNull);
      expect(c.hasPreviousWindow, isFalse);
      c.dispose();
    });

    test('sonraki / önceki pencere İstanbul bugününe göre 7 gün; rezerve edilebilir son günde durur', () async {
      final service = _service();
      final c = _booking(service);
      await c.load();
      expect(c.hasNextWindow, isTrue, reason: '25 Ekim <= 3 Kasım');
      await c.goToWindow(1);
      expect(service.availabilityCalls.last.from, '2026-10-25');
      expect(c.windowIndex, 1);
      expect(c.hasPreviousWindow, isTrue);
      expect(c.hasNextWindow, isTrue, reason: '1 Kasım <= 3 Kasım');
      await c.goToWindow(1);
      expect(service.availabilityCalls.last.from, '2026-11-01');
      expect(c.hasNextWindow, isFalse, reason: '8 Kasım > 3 Kasım');
      await c.goToWindow(-1);
      await c.goToWindow(-1);
      expect(service.availabilityCalls.last.from, isNull);
      expect(c.hasPreviousWindow, isFalse);
      await c.goToWindow(-1);
      expect(service.availabilityCalls.length, 5, reason: 'ilk pencerenin gerisine gidilmez');
      c.dispose();
    });

    test('gün hesabı cihaz saatine değil İstanbul takvimine göredir', () async {
      final service = _service();
      // 18 Ekim 22:30 UTC = 19 Ekim 01:30 İstanbul.
      final c = _booking(service, clock: () => DateTime.utc(2026, 10, 18, 22, 30));
      await c.load();
      await c.goToWindow(1);
      expect(service.availabilityCalls.last.from, '2026-10-26');
      c.dispose();
    });

    test('seçilebilirlik: dolu dilim pasif; süre ardışık boş dilimle ve max_slots ile sınırlı', () async {
      final c = _booking(_service());
      await c.load();
      expect(c.isSelectable(0), isTrue);
      expect(c.isSelectable(1), isFalse, reason: 'dolu');
      expect(c.isSelectable(2), isTrue);
      expect(c.maxCountFrom(0), 1, reason: 'sonraki dilim dolu');
      c.selectSlot(1);
      expect(c.selectedSlot, isNull, reason: 'dolu dilim seçilemez');
      c.selectDate('2026-10-21');
      expect(c.maxRunFrom(0), 3);
      expect(c.maxCountFrom(0), 3);
      expect(c.maxCountFrom(1), 2);
      c.selectSlot(0);
      expect(c.slotCount, 1, reason: 'varsayılan en az dilim');
      c.setSlotCount(9);
      expect(c.slotCount, 3, reason: 'en çok seçilebilir');
      c.setSlotCount(0);
      expect(c.slotCount, 1);
      c.setSlotCount(2);
      expect(c.summary, '21.10.2026 Çarşamba · 09:00-11:00 (2 dilim, 2 saat)');
      c.dispose();
    });

    test('en az dilim 2 olan alan: tek boş dilim başlangıç olamaz', () async {
      final service = _service();
      service.areas.add(rzArea(5, name: 'Sauna', minSlots: 2, maxSlots: 3));
      final c = _booking(service, areaId: 5);
      await c.load();
      expect(c.isSelectable(0), isFalse, reason: 'tek ardışık boş dilim var, en az 2 gerekir');
      c.selectDate('2026-10-21');
      c.selectSlot(0);
      expect(c.slotCount, 2);
      c.dispose();
    });

    test('gün değişince dilim seçimi düşer; kapalı günün dilimi yoktur', () async {
      final c = _booking(_service());
      await c.load();
      c.selectSlot(0);
      expect(c.selectedSlot, 0);
      c.selectDate('2026-10-22');
      expect(c.selectedSlot, isNull);
      expect(c.daySlots, isEmpty);
      expect(c.summary, isNull);
      c.dispose();
    });
  });

  group('ReservationBookingController: gönderim', () {
    test('başarı: gövde seçimden kurulur; created dolar', () async {
      final service = _service();
      final c = _booking(service);
      await c.load();
      c.selectDate('2026-10-21');
      c.selectSlot(1);
      c.setSlotCount(2);
      expect(await c.submit('  Not  '), isTrue);
      final sent = service.createCalls.single;
      expect(sent.siteCode, 11);
      expect(sent.areaId, 1);
      expect(sent.date, '2026-10-21');
      expect(sent.start, '10:00');
      expect(sent.slots, 2);
      expect(sent.note.trim(), 'Not');
      expect(c.created?.reservation.status, ReservationStatus.onaylandi);
      expect(c.busy, isFalse);
      c.dispose();
    });

    test('seçim yoksa istek atılmaz', () async {
      final service = _service();
      final c = _booking(service);
      await c.load();
      expect(await c.submit(''), isFalse);
      expect(c.actionError, 'Önce bir gün ve saat seçin.');
      expect(service.createCalls, isEmpty);
      c.dispose();
    });

    test('409 çakışma: hata düz Türkçe, seçim korunmaz ama boş saatler sessizce tazelenir', () async {
      final service = _service();
      final c = _booking(service);
      await c.load();
      c.selectSlot(0);
      final slot = (service.availabilityDays[1]!.first['slots'] as List).first as Map<String, dynamic>;
      slot
        ..['booked'] = 1
        ..['available'] = false;
      expect(await c.submit(''), isFalse);
      expect(c.actionError, contains('bu arada doldu'));
      expect(c.lastError, isA<ApiException>());
      await Future<void>.delayed(Duration.zero);
      expect(service.availabilityCalls.length, 2, reason: 'sessiz tazeleme');
      expect(c.selectedSlot, isNull, reason: 'dolan dilim seçimden düştü');
      expect(c.loadError, isNull, reason: 'sessiz tazeleme hata kutusu açmaz');
      c.dispose();
    });

    test('çift gönderim: ikinci çağrı yok sayılır', () async {
      final service = _service();
      final gate = Completer<void>();
      service.gates['create'] = <Completer<void>>[gate];
      final c = _booking(service);
      await c.load();
      c.selectSlot(0);
      final first = c.submit('');
      expect(c.busy, isTrue);
      expect(await c.submit(''), isFalse);
      gate.complete();
      expect(await first, isTrue);
      expect(service.createCalls.length, 1);
      c.dispose();
    });

    test('alan kapalı / modül kapalı bayrakları; yükleme hatası mesajı', () async {
      final service = _service();
      service.failures['availability'] = <Object>[FakeReservationService.error(404, 'AREA_NOT_FOUND')];
      final closed = _booking(service);
      await closed.load();
      expect(closed.areaClosed, isTrue);
      expect(closed.loadError, contains('Alan bulunamadı'));
      closed.dispose();

      service.failures['availability'] = <Object>[FakeReservationService.moduleOff()];
      final off = _booking(service);
      await off.load();
      expect(off.moduleClosed, isTrue);
      off.dispose();

      service.failures['availability'] = <Object>[StateError('beklenmeyen')];
      final unknown = _booking(service);
      await unknown.load();
      expect(unknown.loadError, contains('Boş saatler yüklenemedi'));
      await unknown.load();
      expect(unknown.loadError, isNull, reason: 'yeniden deneme hatayı temizler');
      unknown.dispose();
    });

    test('yarış: eski yanıt yeni durumu ezmez; dispose sonrası yanıt yok sayılır', () async {
      final service = _service();
      final slowGate = Completer<void>();
      service.gates['availability'] = <Completer<void>>[slowGate];
      final c = _booking(service);
      final slow = c.load();
      final fast = c.load();
      await fast;
      expect(c.days, isNotEmpty);
      // Yavaş (eski) istek bitince yeni durum bozulmaz.
      final before = c.days;
      slowGate.complete();
      await slow;
      expect(identical(c.days, before), isTrue);

      final gate = Completer<void>();
      service.gates['availability'] = <Completer<void>>[gate];
      final disposed = _booking(service);
      final pending = disposed.load();
      disposed.dispose();
      gate.complete();
      await pending;
      expect(disposed.availability, isNull);
      c.dispose();
    });
  });

  group('ReservationDecisionController', () {
    ReservationRecord pending() => ReservationRecord.fromJson(rzReservation(2, status: 'beklemede'));

    test('ret / iptalde gerekçe zorunlu: istek atılmaz; onayda not isteğe bağlı', () async {
      final service = _service();
      final c = ReservationDecisionController(service: service, siteCode: 11, reservation: pending());
      expect(await c.submit('reject', '   '), isFalse);
      expect(c.actionError, 'Gerekçe zorunludur.');
      expect(service.decideCalls, isEmpty);
      expect(await c.submit('approve', ''), isTrue);
      expect(service.decideCalls.single.note, isNull);
      expect(c.result?.reservation.status, ReservationStatus.onaylandi);
      expect(c.changed, isTrue);
      c.dispose();
    });

    test('gerekçe kırpılıp gönderilir', () async {
      final service = _service();
      final c = ReservationDecisionController(service: service, siteCode: 11, reservation: pending());
      expect(await c.submit('reject', '  Uygun değil.  '), isTrue);
      expect(service.decideCalls.single.note, 'Uygun değil.');
      c.dispose();
    });

    test('404: gone + liste yenilenmeli; 409: liste yenilenmeli; 403 modül: moduleClosed', () async {
      final service = _service();
      service.failures['decide'] = <Object>[FakeReservationService.error(404, 'RESERVATION_NOT_FOUND')];
      final gone = ReservationDecisionController(service: service, siteCode: 11, reservation: pending());
      expect(await gone.submit('approve', ''), isFalse);
      expect(gone.gone, isTrue);
      expect(gone.changed, isTrue);
      gone.dispose();

      service.failures['decide'] = <Object>[FakeReservationService.error(409, 'INVALID_TRANSITION')];
      final conflict = ReservationDecisionController(service: service, siteCode: 11, reservation: pending());
      expect(await conflict.submit('approve', ''), isFalse);
      expect(conflict.gone, isFalse);
      expect(conflict.changed, isTrue);
      expect(conflict.actionError, contains('Başka biri'));
      conflict.dispose();

      service.failures['decide'] = <Object>[FakeReservationService.moduleOff()];
      final off = ReservationDecisionController(service: service, siteCode: 11, reservation: pending());
      expect(await off.submit('approve', ''), isFalse);
      expect(off.moduleClosed, isTrue);
      expect(off.changed, isFalse);
      off.dispose();
    });

    test('hata sonrası yeniden deneme olur (yazma otomatik denenmez ama kullanıcı yineleyebilir)', () async {
      final service = _service();
      service.failures['decide'] = <Object>[ApiException('Bağlantı yok.')];
      final c = ReservationDecisionController(service: service, siteCode: 11, reservation: pending());
      expect(await c.submit('approve', ''), isFalse);
      expect(c.actionError, 'Bağlantı yok.');
      expect(c.busy, isFalse);
      expect(await c.submit('approve', ''), isTrue);
      expect(service.decideCalls.length, 2);
      expect(c.actionError, isNull);
      c.dispose();
    });
  });

  group('ConciergeManageController', () {
    ConciergeRecord initial([int id = 1]) => ConciergeRecord.fromJson(rzRequest(id));

    test('yükleme: geçişler sunucudan; yazma yetkisi yoksa kurul geçişi boş', () async {
      final service = _service();
      final c = ConciergeManageController(service: service, siteCode: 11, canWrite: true, initial: initial());
      await c.load();
      expect(c.loaded, isTrue);
      expect(c.nextStatuses, <ConciergeStatus>[
        ConciergeStatus.hazirlaniyor,
        ConciergeStatus.tamamlandi,
        ConciergeStatus.iptal,
      ]);
      c.dispose();

      service.kind = ReservationSiteAccess.board;
      final board = ConciergeManageController(service: service, siteCode: 11, canWrite: false, initial: initial());
      await board.load();
      expect(board.nextStatuses, isEmpty);
      expect(board.request.requester?.phone, isNull);
      board.dispose();
    });

    test('kaydet: yalnız değişenler; boş not = sil; hiçbir şey yoksa istek atılmaz', () async {
      final service = _service();
      final c = ConciergeManageController(service: service, siteCode: 11, canWrite: true, initial: initial());
      await c.load();
      expect(await c.save(), isFalse);
      expect(service.updateRequestCalls, isEmpty);
      expect(await c.save(status: ConciergeStatus.unknown), isFalse);
      expect(await c.save(status: ConciergeStatus.hazirlaniyor), isTrue);
      expect(service.updateRequestCalls.last.fields, <String, Object?>{'status': 'hazirlaniyor'});
      expect(c.request.status, ConciergeStatus.hazirlaniyor);
      expect(c.nextStatuses, <ConciergeStatus>[ConciergeStatus.tamamlandi, ConciergeStatus.iptal]);
      expect(await c.save(noteChanged: true, note: '   '), isTrue);
      expect(service.updateRequestCalls.last.fields, <String, Object?>{'note': null});
      expect(await c.save(noteChanged: true, note: '  Yolda.  '), isTrue);
      expect(service.updateRequestCalls.last.fields, <String, Object?>{'note': 'Yolda.'});
      expect(c.changed, isTrue);
      c.dispose();
    });

    test('409: sessiz tazeleme + changed; 404: gone; 403 modül: moduleClosed', () async {
      final service = _service();
      final c = ConciergeManageController(service: service, siteCode: 11, canWrite: true, initial: initial());
      await c.load();
      service.failures['updateRequest'] = <Object>[FakeReservationService.error(409, 'CONCIERGE_CLOSED')];
      expect(await c.save(status: ConciergeStatus.tamamlandi), isFalse);
      expect(c.actionError, contains('Tamamlanmış ya da iptal edilmiş'));
      expect(c.changed, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(service.getManagedRequestCalls.length, 2);
      c.dispose();

      service.failures['getManagedRequest'] = <Object>[FakeReservationService.error(404, 'CONCIERGE_NOT_FOUND')];
      final gone = ConciergeManageController(service: service, siteCode: 11, canWrite: true, initial: initial());
      await gone.load();
      expect(gone.gone, isTrue);
      expect(gone.loadError, contains('Talep bulunamadı'));
      gone.dispose();

      service.failures['getManagedRequest'] = <Object>[FakeReservationService.moduleOff()];
      final off = ConciergeManageController(service: service, siteCode: 11, canWrite: true, initial: initial());
      await off.load();
      expect(off.moduleClosed, isTrue);
      off.dispose();
    });
  });
}
