// İş Takibi modelleri (lib/models/work_tracking_models.dart): sözleşme gövdelerinin ayrıştırılması,
// bozuk / eksik alanlarda güvenli varsayılanlar, rol farkları (sakin / yönetim / kurul) ve istek gövdeleri.
// Sözleşme: docs/PLATFORM_IS_TAKIBI.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';

import 'screens/work_fixtures.dart';

void main() {
  group('sakin görünümü', () {
    test('liste sayfası: kayıtlar, imleç ve okunmamış güncelleme sayısı', () {
      final page = WorkResidentPage.fromJson(<String, dynamic>{
        'items': <Object>[
          wkResident(9, unread: true, urgent: true, hasAssignee: true, dueDate: '2026-10-25'),
          wkResident(8, status: 'kapandi', location: 'daire', apartmentLabel: 'A Blok / 5'),
        ],
        'next_before_id': 8,
        'unread_updates': 2,
      });
      expect(page.items.map((i) => i.id), <int>[9, 8]);
      expect(page.nextBeforeId, 8);
      expect(page.unreadUpdates, 2);
      final first = page.items.first;
      expect(first.status, WorkStatus.yeni);
      expect(first.unread, isTrue);
      expect(first.urgent, isTrue);
      expect(first.hasAssignee, isTrue);
      expect(first.canCancel, isTrue);
      expect(first.canComment, isTrue);
      expect(first.dueDate, DateTime(2026, 10, 25));
      expect(first.locationText, 'Ortak alan');
      final second = page.items.last;
      expect(second.status.isTerminal, isTrue);
      expect(second.canCancel, isFalse);
      expect(second.canComment, isFalse);
      expect(second.locationText, 'A Blok / 5');
      expect(second.closedAt, isNotNull);
    });

    test('bozuk / eksik gövde çökmez: güvenli varsayılanlar', () {
      final page = WorkResidentPage.fromJson(<String, dynamic>{
        'items': <Object>[
          <String, dynamic>{'id': 'x'},
          'metin',
          <String, dynamic>{'id': 5, 'status': 'bilinmeyen', 'category': 'z', 'created_at': 'bozuk'},
        ],
        'next_before_id': 'abc',
        'unread_updates': null,
      });
      expect(page.items.map((i) => i.id), <int>[5], reason: 'kimliksiz satır atılır');
      expect(page.items.single.status, WorkStatus.unknown);
      expect(page.items.single.category, WorkCategory.diger);
      expect(page.items.single.createdAt, isNull);
      expect(page.nextBeforeId, isNull);
      expect(page.unreadUpdates, 0);
      expect(WorkResidentPage.fromJson(const <String, dynamic>{}).items, isEmpty);
    });

    test('ayrıntı: yalnız public olaylar; sakin görünümünde yönetim "management"', () {
      final detail = WorkResidentDetail.fromJson(<String, dynamic>{
        'item': wkResident(3),
        'events': <Object>[
          <String, dynamic>{'id': 12, 'type': 'status_changed', 'visibility': 'public', 'actor_kind': 'management', 'from': 'yeni', 'to': 'islemde', 'created_at': '2026-10-16T10:00:00Z'},
          <String, dynamic>{'id': 11, 'type': 'created', 'visibility': 'public', 'actor_kind': 'resident', 'to': 'yeni', 'created_at': '2026-10-15T09:00:00Z'},
        ],
      });
      expect(detail.events.map((e) => e.id), <int>[11, 12], reason: 'eskiden yeniye');
      expect(detail.events.first.type, WorkEventType.created);
      expect(detail.events.first.byResident, isTrue);
      expect(detail.events.last.type, WorkEventType.statusChanged);
      expect(detail.events.last.actorName, isNull, reason: 'sakine ad verilmez');
      expect(detail.events.any((e) => e.internal), isFalse);
    });

    test('kopya: yalnız "okundu" işareti değişir', () {
      final item = WorkResidentItem.fromJson(wkResident(4, unread: true));
      final seen = item.copyWith(unread: false);
      expect(seen.unread, isFalse);
      expect(seen.id, item.id);
      expect(seen.title, item.title);
      expect(seen.canCancel, item.canCancel);
    });

    test('create: sarmalı açar; replayed bayrağı okunur', () {
      final result = WorkCreateResult.fromJson(<String, dynamic>{
        'item': wkResident(7),
        'replayed': true,
      });
      expect(result.item.id, 7);
      expect(result.replayed, isTrue);
    });
  });

  group('yönetim görünümü', () {
    test('liste: sayaçlar, atanan, öncelik ve iletişim bilgisi', () {
      final page = WorkManagedPage.fromJson(<String, dynamic>{
        'items': <Object>[
          wkManaged(3, priority: 'acil', residentUrgent: true, assignedCode: 7, assignedName: 'Ben Yönetici', dueDate: '2026-10-25'),
        ],
        'next_before_id': null,
        'counts': <String, dynamic>{'yeni': 4, 'islemde': 2, 'beklemede': 0, 'cozuldu': 1, 'kapandi': 9, 'iptal': 3},
      });
      final item = page.items.single;
      expect(item.priority, WorkPriority.acil);
      expect(item.residentUrgent, isTrue);
      expect(item.assignedTo?.userCode, 7);
      expect(item.assignedTo?.name, 'Ben Yönetici');
      expect(item.requester.name, 'Ayşe Yılmaz');
      expect(item.requester.phone, '+905551112233');
      expect(item.requester.userCode, 4001);
      expect(item.dueDate, DateTime(2026, 10, 25));
      expect(page.counts[WorkStatus.yeni], 4);
      expect(page.counts[WorkStatus.iptal], 3);
      expect(page.counts.length, 6);
      expect(page.nextBeforeId, isNull);
    });

    test('kurul: yalnız ad gelir (telefon ve kullanıcı kodu yok) ve izin verilen geçiş yok', () {
      final row = wkManaged(3);
      row['requester'] = <String, dynamic>{'name': 'Ayşe Yılmaz'};
      final detail = WorkManagedDetail.fromJson(<String, dynamic>{
        'item': row,
        'events': <Object>[],
        'next_statuses': <Object>[],
      });
      expect(detail.item.requester.name, 'Ayşe Yılmaz');
      expect(detail.item.requester.phone, isNull);
      expect(detail.item.requester.userCode, isNull);
      expect(detail.nextStatuses, isEmpty);
    });

    test('ayrıntı: next_statuses sunucudan; bilinmeyen değer atılır; iç olaylar ve atama etiketleri', () {
      final detail = WorkManagedDetail.fromJson(<String, dynamic>{
        'item': wkManaged(3),
        'events': <Object>[
          wkEvent(2, type: 'assigned', visibility: 'internal', actorKind: 'manager', actorName: 'Ben Yönetici', fromLabel: null, toLabel: 'Mehmet Usta'),
          wkEvent(1, type: 'comment', visibility: 'internal', actorKind: 'staff', actorName: 'Mehmet Usta', body: 'Parça sipariş edildi.'),
        ],
        'next_statuses': <Object>['islemde', 'cozuldu', 'uydurma', 'iptal'],
      });
      expect(detail.nextStatuses, <WorkStatus>[WorkStatus.islemde, WorkStatus.cozuldu, WorkStatus.iptal]);
      expect(detail.events.map((e) => e.id), <int>[1, 2]);
      final note = detail.events.first;
      expect(note.internal, isTrue);
      expect(note.actorName, 'Mehmet Usta');
      expect(note.actorKind, 'staff');
      final assigned = detail.events.last;
      expect(assigned.type, WorkEventType.assigned);
      expect(assigned.fromLabel, isNull);
      expect(assigned.toLabel, 'Mehmet Usta');
    });

    test('atanabilir kişiler: kullanıcı kodsuz satır atılır; etiket rolü söyler', () {
      final list = WorkAssignee.listFrom(<Object>[
        <String, dynamic>{'user_code': 7, 'name': 'Ben', 'role': 'manager'},
        <String, dynamic>{'name': 'Kodsuz'},
        <String, dynamic>{'user_code': 9, 'name': 'Usta', 'role': 'staff'},
        'bozuk',
      ]);
      expect(list.map((a) => a.userCode), <int>[7, 9]);
      expect(list.first.label, 'Ben (Yönetici)');
      expect(list.last.label, 'Usta (Görevli)');
      expect(WorkAssignee.listFrom(null), isEmpty);
    });
  });

  group('istekler ve yardımcılar', () {
    test('create gövdesi: ortak alanda daire gönderilmez; acil yalnız doluysa; anahtar eklenir', () {
      const common = WorkCreateRequest(
        siteCode: 11,
        category: WorkCategory.bakim,
        locationType: WorkLocationType.ortakAlan,
        title: '  Bahçe  ',
        description: ' Işık yok ',
        apartmentId: 301,
      );
      final body = common.toJson('wk-abc12345');
      expect(body, <String, dynamic>{
        'site_code': 11,
        'category': 'bakim',
        'location_type': 'ortak_alan',
        'title': 'Bahçe',
        'description': 'Işık yok',
        'idempotency_key': 'wk-abc12345',
      });
      const flat = WorkCreateRequest(
        siteCode: 11,
        category: WorkCategory.ariza,
        locationType: WorkLocationType.daire,
        title: 'Musluk',
        description: 'Akıyor',
        apartmentId: 301,
        urgent: true,
      );
      final flatBody = flat.toJson('wk-xyz98765');
      expect(flatBody['apartment_id'], 301);
      expect(flatBody['urgent'], isTrue);
      expect(flatBody['location_type'], 'daire');
    });

    test('imza: aynı veri aynı imza; veri değişince imza değişir (boşluklar ve ortak alan dairesi yok sayılır)', () {
      const a = WorkCreateRequest(siteCode: 1, category: WorkCategory.ariza, locationType: WorkLocationType.ortakAlan, title: 'T', description: 'D', apartmentId: 5);
      const b = WorkCreateRequest(siteCode: 1, category: WorkCategory.ariza, locationType: WorkLocationType.ortakAlan, title: ' T ', description: 'D ');
      const c = WorkCreateRequest(siteCode: 1, category: WorkCategory.ariza, locationType: WorkLocationType.ortakAlan, title: 'T', description: 'D', urgent: true);
      expect(a.signature, b.signature);
      expect(a.signature, isNot(c.signature));
    });

    test('tarih ve konum özetleri', () {
      expect(workDateText('2026-10-05'), '05.10.2026');
      expect(workDateText(null), isNull);
      expect(workDateText('bozuk'), isNull);
      expect(workLocationSummary(WorkLocationType.ortakAlan, null, const WorkPlace(id: 2, label: 'B Blok')), 'Ortak alan · B Blok');
      expect(workLocationSummary(WorkLocationType.daire, null, null), 'Daire');
      expect(workLocationSummary(WorkLocationType.daire, const WorkPlace(id: 1, label: 'A / 5'), null), 'A / 5');
    });

    test('durum ve sabit değerler: bilinen listesi, son durumlar, bilinmeyen güvenli', () {
      expect(WorkStatus.known.length, 6);
      expect(WorkStatus.kapandi.isTerminal && WorkStatus.iptal.isTerminal, isTrue);
      expect(WorkStatus.cozuldu.isTerminal, isFalse);
      expect(WorkStatus.fromApi('YENI'), WorkStatus.yeni);
      expect(WorkStatus.fromApi(null), WorkStatus.unknown);
      expect(WorkPriority.fromApi('x'), WorkPriority.normal);
      expect(WorkLocationType.fromApi('x'), WorkLocationType.ortakAlan);
      expect(WorkEventType.fromApi('x'), WorkEventType.unknown);
    });

    test('site erişimi: kurul yazamaz, yönetici ve görevli yazar; ad boşsa "İsimsiz site"', () {
      expect(const WorkTrackingSite(code: 1, name: 'A').canWrite, isTrue);
      expect(const WorkTrackingSite(code: 1, name: 'A', access: WorkSiteAccess.staff).canWrite, isTrue);
      expect(const WorkTrackingSite(code: 1, name: 'A', access: WorkSiteAccess.board).canWrite, isFalse);
      expect(const WorkTrackingSite(code: 1, name: ' ').label, 'İsimsiz site');
    });
  });
}
