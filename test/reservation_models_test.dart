// Rezervasyon ve Konsiyerj modelleri (lib/models/reservation_models.dart): sözleşmedeki yanıt şekilleri, güvenli
// varsayılanlar (bozuk / eksik veri çökmez), bilinmeyen sabitler, kurul görünümü (telefon yok), saat yardımcıları ve
// yazma gövdeleri / idempotency imzaları.
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/reservation_models.dart';

import 'screens/reservation_fixtures.dart';

void main() {
  group('saat ve süre yardımcıları', () {
    test('hhmmToMinutes: geçerli, 24:00 yalnız izinliyse, bozuk null', () {
      expect(hhmmToMinutes('09:30'), 570);
      expect(hhmmToMinutes('9:05'), 545);
      expect(hhmmToMinutes('00:00'), 0);
      expect(hhmmToMinutes('24:00'), isNull);
      expect(hhmmToMinutes('24:00', allow24: true), 1440);
      expect(hhmmToMinutes('24:30', allow24: true), isNull);
      expect(hhmmToMinutes('12:60'), isNull);
      expect(hhmmToMinutes('abc'), isNull);
      expect(hhmmToMinutes(null), isNull);
      expect(minutesToHhmm(570), '09:30');
      expect(minutesToHhmm(1440), '24:00');
    });

    test('süre metni ve gün adları', () {
      expect(reservationDurationText(45), '45 dk');
      expect(reservationDurationText(60), '1 saat');
      expect(reservationDurationText(90), '1 saat 30 dk');
      expect(reservationWeekdayLabel(1), 'Pzt');
      expect(reservationWeekdayLabel(7, long: true), 'Pazar');
      expect(reservationWeekdayLabel(0), '');
      expect(reservationDateText('2026-10-20'), '20.10.2026');
      expect(reservationDateText('bozuk'), isNull);
    });
  });

  group('sabit değerler', () {
    test('durumlar: bilinmeyen -> unknown; sonlar ve yer tutanlar', () {
      expect(ReservationStatus.fromApi('onaylandi'), ReservationStatus.onaylandi);
      expect(ReservationStatus.fromApi('  TAMAMLANDI '), ReservationStatus.tamamlandi);
      expect(ReservationStatus.fromApi('x'), ReservationStatus.unknown);
      expect(ReservationStatus.fromApi(null), ReservationStatus.unknown);
      expect(ReservationStatus.beklemede.isActive, isTrue);
      expect(ReservationStatus.onaylandi.isActive, isTrue);
      for (final status in <ReservationStatus>[
        ReservationStatus.reddedildi,
        ReservationStatus.iptal,
        ReservationStatus.tamamlandi,
      ]) {
        expect(status.isTerminal, isTrue, reason: '$status');
        expect(status.isActive, isFalse, reason: '$status');
      }
      expect(ReservationStatus.beklemede.label, 'Onay bekliyor');
    });

    test('onay modu: bilinmeyen değer anında onay vaat etmez', () {
      expect(ReservationApproval.fromApi('otomatik'), ReservationApproval.otomatik);
      expect(ReservationApproval.fromApi('yonetici_onayli'), ReservationApproval.yoneticiOnayli);
      expect(ReservationApproval.fromApi('?'), ReservationApproval.yoneticiOnayli);
    });

    test('konsiyerj kategorisi ve durumu', () {
      expect(ConciergeCategory.fromApi('misafir_hazirlik'), ConciergeCategory.misafirHazirlik);
      expect(ConciergeCategory.fromApi('x'), ConciergeCategory.diger);
      expect(ConciergeStatus.fromApi('hazirlaniyor'), ConciergeStatus.hazirlaniyor);
      expect(ConciergeStatus.fromApi(null), ConciergeStatus.unknown);
      expect(ConciergeStatus.tamamlandi.isTerminal, isTrue);
      expect(ConciergeStatus.iptal.isTerminal, isTrue);
      expect(ConciergeStatus.yeni.isTerminal, isFalse);
    });

    test('iptal eden metni', () {
      expect(reservationCancelledByText('resident', selfView: true), 'Siz iptal ettiniz.');
      expect(reservationCancelledByText('resident'), 'Sakin iptal etti.');
      expect(reservationCancelledByText('management'), 'Yönetim iptal etti.');
      expect(reservationCancelledByText('system'), contains('Hesap silindiği için'));
      expect(reservationCancelledByText(null), isNull);
    });
  });

  group('ReservationArea', () {
    test('sözleşme alanları okunur; açık saatler sıralı, bozuk girdi atılır; satırlar günlere göre', () {
      final area = ReservationArea.fromJson(<String, dynamic>{
        ...rzArea(7, name: '  Spor Salonu '),
        'weekly_hours': <Object>[
          <String, dynamic>{'weekday': 2, 'start': '14:00', 'end': '18:00'},
          <String, dynamic>{'weekday': 2, 'start': '09:00', 'end': '12:00'},
          <String, dynamic>{'weekday': 9, 'start': '09:00', 'end': '12:00'},
          <String, dynamic>{'weekday': 3, 'start': 'x', 'end': '12:00'},
          <String, dynamic>{'weekday': 7, 'start': '10:00', 'end': '24:00'},
          'bozuk',
        ],
      });
      expect(area.id, 7);
      expect(area.name, 'Spor Salonu');
      expect(area.siteName, 'Gül Sitesi');
      expect(area.capacity, 1);
      expect(area.slotMinutes, 60);
      expect(area.maxSlots, 3);
      expect(area.approvalMode, ReservationApproval.otomatik);
      expect(area.isActive, isTrue);
      expect(area.weeklyHours.map((h) => h.rangeText), <String>['09:00-12:00', '14:00-18:00', '10:00-24:00']);
      expect(area.hoursLines, <String>['Salı: 09:00-12:00, 14:00-18:00', 'Pazar: 10:00-24:00']);
    });

    test('boş / bozuk gövde çökmez: güvenli varsayılanlar', () {
      final area = ReservationArea.fromJson(const <String, dynamic>{});
      expect(area.id, 0);
      expect(area.label, 'İsimsiz alan');
      expect(area.weeklyHours, isEmpty);
      expect(area.hoursLines, isEmpty);
      expect(area.isActive, isFalse, reason: 'is_active yalnız true ise etkin');
      expect(area.approvalMode, ReservationApproval.yoneticiOnayli);
    });

    test('liste: kimliksiz kayıtlar atılır; active_count yoksa hesaplanır', () {
      final list = ReservationAreaList.fromJson(<String, dynamic>{
        'items': <Object>[rzArea(1), rzArea(2, active: false), <String, dynamic>{'name': 'Kimliksiz'}],
      });
      expect(list.items.map((a) => a.id), <int>[1, 2]);
      expect(list.activeCount, 1);
      expect(ReservationAreaList.fromJson(<String, dynamic>{'items': <Object>[rzArea(1)], 'active_count': 5}).activeCount, 5);
    });
  });

  group('ReservationRecord', () {
    test('sakin görünümü: yerel gün / saat olduğu gibi, iptal süresi UTC an', () {
      final r = ReservationRecord.fromJson(<String, dynamic>{
        'reservation': rzReservation(5, status: 'beklemede', note: 'Not', decisionNote: 'Tamam', cancelledBy: 'management'),
        'replayed': false,
      });
      expect(r.id, 5);
      expect(r.areaId, 1);
      expect(r.areaName, 'Spor Salonu');
      expect(r.date, '2026-10-20');
      expect(r.start, '18:00');
      expect(r.end, '19:00');
      expect(r.status, ReservationStatus.beklemede);
      expect(r.note, 'Not');
      expect(r.decisionNote, 'Tamam');
      expect(r.cancelledBy, 'management');
      expect(r.apartment?.label, 'A Blok / 5');
      expect(r.canCancel, isTrue);
      expect(r.cancelDeadline, DateTime.utc(2026, 10, 20, 13));
      expect(r.startsAt, DateTime.utc(2026, 10, 20, 15), reason: '18:00 İstanbul = 15:00 UTC');
      expect(r.startsAt!.isUtc, isTrue);
    });

    test('türetilmiş "tamamlandi" durumu olduğu gibi okunur; bilinmeyen durum unknown', () {
      expect(ReservationRecord.fromJson(rzReservation(1, status: 'tamamlandi')).status, ReservationStatus.tamamlandi);
      expect(ReservationRecord.fromJson(<String, dynamic>{'id': 1, 'status': 'ucuk'}).status, ReservationStatus.unknown);
    });

    test('yönetim görünümü: başvuran, karar veren, can_decide; kurulda telefon / kullanıcı kodu yok', () {
      final manager = ReservationRecord.fromJson(<String, dynamic>{
        ...rzReservation(2, status: 'beklemede'),
        'decided_by': <String, dynamic>{'user_code': 7, 'name': 'Ben Yönetici'},
        'can_decide': true,
      });
      expect(manager.requester?.name, 'Ayşe Yılmaz');
      expect(manager.requester?.userCode, 4001);
      expect(manager.requester?.phone, '+905551112233');
      expect(manager.decidedBy?.name, 'Ben Yönetici');
      expect(manager.canDecide, isTrue);

      final board = ReservationRecord.fromJson(<String, dynamic>{
        ...rzReservation(2),
        'requester': <String, dynamic>{'name': 'Ayşe Yılmaz'},
        'decided_by': <String, dynamic>{'name': 'Ben Yönetici'},
      });
      expect(board.requester?.phone, isNull);
      expect(board.requester?.userCode, isNull);
      expect(board.decidedBy?.userCode, isNull);
    });

    test('boş gövde çökmez; zaman damgası bozuksa null', () {
      final r = ReservationRecord.fromJson(const <String, dynamic>{});
      expect(r.id, 0);
      expect(r.areaLabel, 'İsimsiz alan');
      expect(r.startsAt, isNull);
      expect(r.canCancel, isFalse);
      expect(ReservationRecord.fromJson(<String, dynamic>{'id': 3, 'starts_at': 'bozuk'}).startsAt, isNull);
    });

    test('sayfa: imleçler (before_id / opak cursor), sayaç; kimliksiz kayıt atılır', () {
      final page = ReservationPage.fromJson(<String, dynamic>{
        'items': <Object>[rzReservation(9), <String, dynamic>{'status': 'iptal'}],
        'next_before_id': 9,
        'next_cursor': 'abc123',
        'pending_count': 4,
      });
      expect(page.items.map((r) => r.id), <int>[9]);
      expect(page.nextBeforeId, 9);
      expect(page.nextCursor, 'abc123');
      expect(page.pendingCount, 4);
      expect(ReservationPage.fromJson(const <String, dynamic>{}).items, isEmpty);
    });

    test('karar ve oluşturma sonuçları', () {
      final decided = ReservationDecisionResult.fromJson(<String, dynamic>{'reservation': rzReservation(3), 'changed': false});
      expect(decided.changed, isFalse);
      expect(decided.reservation.id, 3);
      expect(ReservationDecisionResult.fromJson(<String, dynamic>{'reservation': rzReservation(3)}).changed, isTrue);
      final created = ReservationCreateResult.fromJson(<String, dynamic>{'reservation': rzReservation(4), 'replayed': true});
      expect(created.replayed, isTrue);
    });
  });

  group('boş saatler', () {
    test('günler, dilimler (sıralı), kapasite / dolu bilgisi, rezerve edilebilir son gün', () {
      final result = ReservationAvailability.fromJson(<String, dynamic>{
        'area': rzArea(1),
        'days': <Object>[
          <String, dynamic>{
            'date': '2026-10-20',
            'weekday': 2,
            'slots': <Object>[
              <String, dynamic>{'start': '10:00', 'end': '11:00', 'booked': 1, 'capacity': 1, 'available': false},
              <String, dynamic>{'start': '09:00', 'end': '10:00', 'starts_at': '2026-10-20T06:00:00Z', 'booked': 0, 'capacity': 1, 'available': true},
              <String, dynamic>{'start': 'x', 'end': '11:00'},
            ],
          },
          <String, dynamic>{'date': 'bozuk', 'slots': <Object>[]},
          <String, dynamic>{'date': '2026-10-22', 'weekday': 4},
        ],
        'bookable_until': '2026-11-03',
      });
      expect(result.area.id, 1);
      expect(result.bookableUntil, '2026-11-03');
      expect(result.days.map((d) => d.date), <String>['2026-10-20', '2026-10-22'], reason: 'bozuk gün atılır');
      final day = result.days.first;
      expect(day.slots.map((s) => s.start), <String>['09:00', '10:00'], reason: 'bozuk dilim atılır, başlangıca göre sıralı');
      expect(day.slots.first.available, isTrue);
      expect(day.slots.last.available, isFalse);
      expect(day.slots.last.booked, 1);
      expect(day.slots.first.startsAt, DateTime.utc(2026, 10, 20, 6));
      expect(day.shortLabel, 'Sal 20.10');
      expect(day.longLabel, '20.10.2026 Salı');
      expect(result.days.last.slots, isEmpty);
    });

    test('boş gövde çökmez', () {
      final result = ReservationAvailability.fromJson(const <String, dynamic>{});
      expect(result.days, isEmpty);
      expect(result.area.id, 0);
      expect(result.bookableUntil, isNull);
    });
  });

  group('konsiyerj', () {
    test('sakin ve yönetim görünümü; istenen zaman UTC; kurulda telefon yok', () {
      final r = ConciergeRecord.fromJson(<String, dynamic>{
        'request': rzRequest(4, category: 'temizlik', status: 'hazirlaniyor', staffNote: 'Yolda.', requestedFor: '2026-10-21T12:00:00Z'),
      });
      expect(r.category, ConciergeCategory.temizlik);
      expect(r.status, ConciergeStatus.hazirlaniyor);
      expect(r.staffNote, 'Yolda.');
      expect(r.requestedFor, DateTime.utc(2026, 10, 21, 12));
      expect(r.canCancel, isFalse);
      expect(r.requester?.phone, '+905551112233');
      expect(r.apartment?.label, 'A Blok / 5');
      final board = ConciergeRecord.fromJson(<String, dynamic>{
        ...rzRequest(4),
        'requester': <String, dynamic>{'name': 'Ayşe'},
      });
      expect(board.requester?.phone, isNull);
      expect(ConciergeRecord.fromJson(rzRequest(5, status: 'yeni')).canCancel, isTrue);
    });

    test('sayfa: sayaçlar yalnız bilinen durumlardan; ayrıntı: yalnız bilinen geçişler', () {
      final page = ConciergePage.fromJson(<String, dynamic>{
        'items': <Object>[rzRequest(2), <String, dynamic>{'note': 'kimliksiz'}],
        'next_before_id': 2,
        'counts': <String, dynamic>{'yeni': 3, 'hazirlaniyor': 1, 'uydurma': 9},
      });
      expect(page.items.map((r) => r.id), <int>[2]);
      expect(page.nextBeforeId, 2);
      expect(page.counts, <ConciergeStatus, int>{ConciergeStatus.yeni: 3, ConciergeStatus.hazirlaniyor: 1});
      final detail = ConciergeDetail.fromJson(<String, dynamic>{
        'request': rzRequest(2),
        'next_statuses': <Object>['hazirlaniyor', 'ucuk', 'iptal'],
        'changed': true,
      });
      expect(detail.nextStatuses, <ConciergeStatus>[ConciergeStatus.hazirlaniyor, ConciergeStatus.iptal]);
      expect(detail.changed, isTrue);
      expect(ConciergeDetail.fromJson(<String, dynamic>{'request': rzRequest(2)}).changed, isFalse);
    });
  });

  group('yazma gövdeleri', () {
    const request = ReservationCreateRequest(
      siteCode: 11,
      areaId: 3,
      date: '2026-10-20',
      start: '18:00',
      slots: 2,
      note: '  Doğum günü  ',
    );

    test('rezervasyon: gövde sözleşmeye uyar; boş not ve daire gönderilmez', () {
      final body = request.toJson('rz-0123456789abcdef');
      expect(body, <String, dynamic>{
        'site_code': 11,
        'area_id': 3,
        'date': '2026-10-20',
        'start': '18:00',
        'slots': 2,
        'note': 'Doğum günü',
        'idempotency_key': 'rz-0123456789abcdef',
      });
      const bare = ReservationCreateRequest(siteCode: 11, areaId: 3, date: '2026-10-20', start: '18:00', slots: 1);
      final bareBody = bare.toJson('rz-0123456789abcdef');
      expect(bareBody.containsKey('note'), isFalse);
      expect(bareBody.containsKey('apartment_id'), isFalse);
      const withApartment = ReservationCreateRequest(siteCode: 11, areaId: 3, date: '2026-10-20', start: '18:00', slots: 1, apartmentId: 301);
      expect(withApartment.toJson('rz-0123456789abcdef')['apartment_id'], 301);
    });

    test('imza: aynı veri = aynı imza (not boşlukları önemsiz); herhangi bir alan değişince farklı', () {
      const same = ReservationCreateRequest(siteCode: 11, areaId: 3, date: '2026-10-20', start: '18:00', slots: 2, note: 'Doğum günü');
      expect(request.signature, same.signature);
      for (final changed in <ReservationCreateRequest>[
        const ReservationCreateRequest(siteCode: 12, areaId: 3, date: '2026-10-20', start: '18:00', slots: 2, note: 'Doğum günü'),
        const ReservationCreateRequest(siteCode: 11, areaId: 4, date: '2026-10-20', start: '18:00', slots: 2, note: 'Doğum günü'),
        const ReservationCreateRequest(siteCode: 11, areaId: 3, date: '2026-10-21', start: '18:00', slots: 2, note: 'Doğum günü'),
        const ReservationCreateRequest(siteCode: 11, areaId: 3, date: '2026-10-20', start: '19:00', slots: 2, note: 'Doğum günü'),
        const ReservationCreateRequest(siteCode: 11, areaId: 3, date: '2026-10-20', start: '18:00', slots: 3, note: 'Doğum günü'),
        const ReservationCreateRequest(siteCode: 11, areaId: 3, date: '2026-10-20', start: '18:00', slots: 2, note: 'Başka'),
      ]) {
        expect(changed.signature, isNot(request.signature));
      }
    });

    test('konsiyerj: istenen zaman UTC ISO; boş alanlar gönderilmez; imza istenen zamanı içerir', () {
      final when = DateTime.utc(2026, 10, 21, 6);
      final withTime = ConciergeCreateRequest(
        siteCode: 11,
        category: ConciergeCategory.tasima,
        note: ' Koltuk ',
        requestedFor: when,
      );
      expect(withTime.toJson('rz-0123456789abcdef'), <String, dynamic>{
        'site_code': 11,
        'category': 'tasima',
        'note': 'Koltuk',
        'requested_for': '2026-10-21T06:00:00.000Z',
        'idempotency_key': 'rz-0123456789abcdef',
      });
      const bare = ConciergeCreateRequest(siteCode: 11, category: ConciergeCategory.paketTeslim);
      final bareBody = bare.toJson('rz-0123456789abcdef');
      expect(bareBody.containsKey('note'), isFalse);
      expect(bareBody.containsKey('requested_for'), isFalse);
      expect(withTime.signature, isNot(bare.signature));
      expect(
        ConciergeCreateRequest(siteCode: 11, category: ConciergeCategory.tasima, note: 'Koltuk', requestedFor: when).signature,
        withTime.signature,
      );
    });
  });

  group('site erişimi', () {
    test('yazma ve alan tanımlama yetkisi erişim türünden türer; eşitlik değere göre', () {
      const manager = ReservationSite(code: 1, name: 'A');
      const staff = ReservationSite(code: 1, name: 'A', access: ReservationSiteAccess.staff);
      const board = ReservationSite(code: 1, name: 'A', access: ReservationSiteAccess.board);
      expect(manager.canWrite && manager.canDefineAreas, isTrue);
      expect(staff.canWrite, isTrue);
      expect(staff.canDefineAreas, isFalse);
      expect(board.canWrite, isFalse);
      expect(board.canDefineAreas, isFalse);
      expect(manager, const ReservationSite(code: 1, name: 'A'));
      expect(manager == staff, isFalse);
      expect(const ReservationSite(code: 1, name: ' ').label, 'İsimsiz site');
    });
  });

  group('okunmamış karar / güncelleme (sakin rozeti)', () {
    test('rezervasyon: unread yalnız true ise; alan yoksa (eski sunucu) false; copyWith bayrağı siler, kalanı korur', () {
      expect(ReservationRecord.fromJson(rzReservation(1, unread: true)).unread, isTrue);
      expect(ReservationRecord.fromJson(rzReservation(1)).unread, isFalse);
      expect(ReservationRecord.fromJson(rzReservation(1)..remove('unread')).unread, isFalse);
      expect(ReservationRecord.fromJson(<String, dynamic>{'id': 1, 'unread': 'true'}).unread, isFalse, reason: 'yalnız gerçek bool');
      expect(ReservationRecord.fromJson(<String, dynamic>{'reservation': rzReservation(2, unread: true)}).unread, isTrue, reason: 'sarılı gövde');
      final seen = ReservationRecord.fromJson(rzReservation(1, unread: true, note: 'Not', decisionNote: 'Tamam')).copyWith(unread: false);
      expect(seen.unread, isFalse);
      expect(seen.id, 1);
      expect(seen.areaName, 'Spor Salonu');
      expect(seen.note, 'Not');
      expect(seen.decisionNote, 'Tamam');
      expect(seen.canCancel, isTrue);
      expect(seen.cancelDeadline, DateTime.utc(2026, 10, 20, 13));
      expect(seen.copyWith().unread, isFalse);
    });

    test('rezervasyon sayfası: unread_count okunur; yoksa 0', () {
      final page = ReservationPage.fromJson(<String, dynamic>{
        'items': <Object>[rzReservation(1, unread: true), rzReservation(2)],
        'next_before_id': null,
        'unread_count': 3,
      });
      expect(page.unreadCount, 3);
      expect(page.items.map((r) => r.unread), <bool>[true, false]);
      expect(ReservationPage.fromJson(<String, dynamic>{'items': <Object>[rzReservation(1)]}).unreadCount, 0);
      expect(ReservationPage.fromJson(const <String, dynamic>{}).unreadCount, 0);
    });

    test('konsiyerj: unread, copyWith ve sayfa unread_count; alan yoksa false / 0', () {
      expect(ConciergeRecord.fromJson(rzRequest(2, unread: true)).unread, isTrue);
      expect(ConciergeRecord.fromJson(rzRequest(2)).unread, isFalse);
      expect(ConciergeRecord.fromJson(rzRequest(2)..remove('unread')).unread, isFalse);
      expect(ConciergeRecord.fromJson(<String, dynamic>{'request': rzRequest(2, unread: true)}).unread, isTrue);
      final seen = ConciergeRecord.fromJson(rzRequest(2, unread: true, staffNote: 'Yolda.', status: 'hazirlaniyor')).copyWith(unread: false);
      expect(seen.unread, isFalse);
      expect(seen.id, 2);
      expect(seen.staffNote, 'Yolda.');
      expect(seen.status, ConciergeStatus.hazirlaniyor);
      expect(seen.category, ConciergeCategory.paketTeslim);
      final page = ConciergePage.fromJson(<String, dynamic>{'items': <Object>[rzRequest(2, unread: true)], 'unread_count': 1});
      expect(page.unreadCount, 1);
      expect(page.items.single.unread, isTrue);
      expect(ConciergePage.fromJson(<String, dynamic>{'items': <Object>[rzRequest(2)]}).unreadCount, 0);
    });
  });
}
