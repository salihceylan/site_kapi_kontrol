// Ziyaretçi ve Kargo modelleri (lib/models/visitor_log_models.dart): sözleşme gövdelerinin ayrıştırılması,
// bozuk / eksik alanlarda güvenli varsayılanlar, rol farkları (sakin / yönetim / kurul) ve istek gövdeleri.
// Sözleşme: docs/PLATFORM_ZIYARETCI_KARGO.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/visitor_log_models.dart';

import 'screens/visitor_fixtures.dart';

void main() {
  group('Entry', () {
    test('yönetim gövdesi: tür, durum, geçişler, daire etiketi, görevli adları, zaman damgaları', () {
      final entry = VisitorEntry.fromJson(
        vkEntry(5, kind: 'cargo', name: 'Aras Kargo', company: 'Takip 1', note: 'Koli'),
      );
      expect(entry.id, 5);
      expect(entry.kind, VisitorKind.cargo);
      expect(entry.status, VisitorStatus.bekliyor);
      expect(entry.status.isOpen, isTrue);
      expect(entry.status.isTerminal, isFalse);
      expect(entry.nextStatuses, <VisitorStatus>[VisitorStatus.teslimEdildi, VisitorStatus.iptal]);
      expect(entry.apartmentId, 301);
      expect(entry.placeText, 'A Blok / 5', reason: 'etiket blok adıyla başlıyorsa blok yinelenmez');
      expect(entry.displayName, 'Aras Kargo');
      expect(entry.company, 'Takip 1');
      expect(entry.note, 'Koli');
      expect(entry.recordedByName, 'Kapıcı Hasan');
      expect(entry.completedByName, isNull);
      expect(entry.arrivedAt, DateTime.utc(2026, 10, 18, 9, 15));
      expect(entry.completedAt, isNull);
      expect(entry.unread, isTrue, reason: 'resident_seen_at null = görülmemiş');
    });

    test('sonlanmış kayıt: geçiş yok, kapanış damgası ve kapatan adı', () {
      final entry = VisitorEntry.fromJson(vkEntry(6, kind: 'visitor', status: 'ayrildi', seenAt: '2026-10-18T12:00:00Z'));
      expect(entry.status, VisitorStatus.ayrildi);
      expect(entry.status.isTerminal, isTrue);
      expect(entry.nextStatuses, isEmpty);
      expect(entry.completedAt, isNotNull);
      expect(entry.completedByName, 'Kapıcı Hasan');
      expect(entry.unread, isFalse);
    });

    test('ortak alan ziyaretçisi: daire yok -> "Ortak alan"; blok ayrı verilirse "Blok / daire"', () {
      final common = VisitorEntry.fromJson(vkEntry(7, apartmentId: null, apartmentLabel: null, blockName: null));
      expect(common.apartmentId, isNull);
      expect(common.placeText, 'Ortak alan');
      final blocked = VisitorEntry.fromJson(vkEntry(8, apartmentLabel: '5', blockName: 'B Blok'));
      expect(blocked.placeText, 'B Blok / 5');
    });

    test('bozuk / eksik gövde çökmez: güvenli varsayılanlar; bilinmeyen durum / tür', () {
      final entry = VisitorEntry.fromJson(<String, dynamic>{
        'id': '9',
        'kind': 'drone',
        'status': 'bilinmeyen',
        'next_statuses': <Object>['uydurma', 'iptal', 42],
        'arrived_at': 'bozuk',
        'visitor_name': '   ',
      });
      expect(entry.id, 9);
      expect(entry.kind, VisitorKind.visitor);
      expect(entry.status, VisitorStatus.unknown);
      expect(entry.status.label, 'Durum bilinmiyor');
      expect(entry.nextStatuses, <VisitorStatus>[VisitorStatus.iptal], reason: 'bilinmeyen geçiş atılır');
      expect(entry.arrivedAt, isNull);
      expect(entry.displayName, 'İsimsiz ziyaretçi');
      expect(VisitorEntry.fromJson(<String, dynamic>{'id': 3, 'kind': 'cargo'}).displayName, 'İsimsiz kargo');
    });

    test('`item` / `entry` sarmalı kabul edilir; kimliksiz satırlar listeden atılır', () {
      expect(VisitorEntry.fromJson(<String, dynamic>{'item': vkEntry(4)}).id, 4);
      expect(VisitorEntry.fromJson(<String, dynamic>{'entry': vkEntry(2)}).id, 2);
      final list = VisitorEntry.listFrom(<Object>[vkEntry(1), 'metin', <String, dynamic>{'id': 'x'}, vkEntry(2)]);
      expect(list.map((e) => e.id), <int>[1, 2]);
      expect(VisitorEntry.listFrom(null), isEmpty);
    });

    test('copyWith: yalnız görüldü damgası değişir', () {
      final entry = VisitorEntry.fromJson(vkEntry(3));
      final seen = entry.copyWith(residentSeenAt: DateTime.utc(2026, 10, 18, 13));
      expect(seen.unread, isFalse);
      expect(seen.id, entry.id);
      expect(seen.visitorName, entry.visitorName);
      expect(seen.status, entry.status);
      expect(entry.unread, isTrue, reason: 'özgün nesne değişmez');
    });
  });

  group('sayfalar', () {
    test('yönetim sayfası: items + total; total eksikse ya da küçükse kayıt sayısı', () {
      final page = VisitorManagedPage.fromJson(<String, dynamic>{
        'items': <Object>[vkEntry(2), vkEntry(1)],
        'total': 7,
      });
      expect(page.items.map((e) => e.id), <int>[2, 1]);
      expect(page.total, 7);
      expect(VisitorManagedPage.fromJson(<String, dynamic>{'items': <Object>[vkEntry(1)]}).total, 1);
      expect(VisitorManagedPage.fromJson(<String, dynamic>{'items': <Object>[vkEntry(1), vkEntry(2)], 'total': 1}).total, 2);
      expect(VisitorManagedPage.fromJson(const <String, dynamic>{}).items, isEmpty);
    });

    test('sakin sayfası: site alanları ve imleç; görevli adları sakine gelmez', () {
      final row = vkEntry(4)
        ..remove('recorded_by_name')
        ..remove('completed_by_name');
      final page = VisitorResidentPage.fromJson(<String, dynamic>{
        'items': <Object>[row],
        'next_before_id': '4',
      });
      expect(page.nextBeforeId, 4);
      final entry = page.items.single;
      expect(entry.siteCode, 11);
      expect(entry.siteName, 'Gül Sitesi');
      expect(entry.recordedByName, isNull);
      expect(entry.completedByName, isNull);
      expect(VisitorResidentPage.fromJson(<String, dynamic>{'next_before_id': 'abc'}).nextBeforeId, isNull);
    });
  });

  group('istek gövdesi', () {
    test('create: tür + ad zorunlu; boş firma / not ve daire gönderilmez; metinler kırpılır', () {
      const request = VisitorCreateRequest(kind: VisitorKind.cargo, visitorName: '  Aras Kargo  ', company: '  ', note: '');
      expect(request.toJson(), <String, dynamic>{'kind': 'cargo', 'visitor_name': 'Aras Kargo'});
      const full = VisitorCreateRequest(
        kind: VisitorKind.visitor,
        visitorName: 'Ayşe',
        apartmentId: 301,
        company: ' Temizlik ',
        note: ' Not ',
      );
      expect(full.toJson(), <String, dynamic>{
        'kind': 'visitor',
        'apartment_id': 301,
        'visitor_name': 'Ayşe',
        'company': 'Temizlik',
        'note': 'Not',
      });
    });
  });

  group('sabitler ve site erişimi', () {
    test('durum: api değerleri, etiketler, eylem etiketleri, bilinen liste', () {
      expect(VisitorStatus.fromApi(' TESLIM_EDILDI '), VisitorStatus.teslimEdildi);
      expect(VisitorStatus.fromApi(''), VisitorStatus.unknown);
      expect(VisitorStatus.fromApi(null), VisitorStatus.unknown);
      expect(VisitorStatus.teslimEdildi.actionLabel, 'Teslim edildi');
      expect(VisitorStatus.ayrildi.actionLabel, 'Ayrıldı');
      expect(VisitorStatus.iptal.actionLabel, 'İptal');
      expect(VisitorStatus.known.map((s) => s.apiValue), <String>['bekliyor', 'iceride', 'teslim_edildi', 'ayrildi', 'iptal']);
      expect(VisitorKind.fromApi('Cargo'), VisitorKind.cargo);
      expect(VisitorKind.fromApi('x'), VisitorKind.visitor);
      expect(VisitorKind.cargo.label, 'Kargo');
    });

    test('VisitorSite: kurul yazamaz, görevli ve yönetici yazar; boş ad "İsimsiz site"', () {
      const board = VisitorSite(code: 1, name: ' ', access: VisitorSiteAccess.board);
      expect(board.canWrite, isFalse);
      expect(board.label, 'İsimsiz site');
      expect(const VisitorSite(code: 1, name: 'Gül', access: VisitorSiteAccess.staff).canWrite, isTrue);
      expect(const VisitorSite(code: 1, name: 'Gül').canWrite, isTrue);
      expect(const VisitorSite(code: 1, name: 'Gül'), const VisitorSite(code: 1, name: 'Gül'));
      expect(const VisitorSite(code: 1, name: 'Gül'), isNot(board));
    });
  });
}
