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
      expect(WorkEventType.fromApi('attachment_added'), WorkEventType.attachmentAdded);
      expect(WorkEventType.fromApi('attachment_removed'), WorkEventType.attachmentRemoved);
    });

    test('site erişimi: kurul yazamaz, yönetici ve görevli yazar; ad boşsa "İsimsiz site"', () {
      expect(const WorkTrackingSite(code: 1, name: 'A').canWrite, isTrue);
      expect(const WorkTrackingSite(code: 1, name: 'A', access: WorkSiteAccess.staff).canWrite, isTrue);
      expect(const WorkTrackingSite(code: 1, name: 'A', access: WorkSiteAccess.board).canWrite, isFalse);
      expect(const WorkTrackingSite(code: 1, name: ' ').label, 'İsimsiz site');
    });
  });

  group('fotoğraf ekleri', () {
    test('sakin ayrıntısı: `attachments` talebin yanında; kimlik artan; bozuk satır atılır; sayı türetilir', () {
      final detail = WorkResidentDetail.fromJson(<String, dynamic>{
        'item': wkResident(1),
        'events': <Object>[],
        'attachments': <Object>[
          wkAttachment(5, mine: true),
          wkAttachment(4, status: 'uploading', fileName: 'yari.png', mime: 'image/png'),
          <String, dynamic>{'id': 'x'},
          'bozuk',
        ],
      });
      expect(detail.attachments.map((a) => a.id), <int>[4, 5]);
      expect(detail.attachments.first.isReady, isFalse);
      expect(detail.attachments.first.status, WorkAttachmentStatus.uploading);
      expect(detail.attachments.last.isReady, isTrue);
      expect(detail.attachments.last.uploadedByMe, isTrue);
      expect(detail.attachments.last.mimeType, 'image/jpeg');
      expect(detail.attachments.last.sizeBytes, 204800);
      expect(detail.attachments.last.createdAt, DateTime.utc(2026, 10, 15, 9, 5));
      expect(detail.item.attachmentCount, 2, reason: 'liste alanı yoksa ek sayısından');
    });

    test('liste satırı `attachment_count`; eksik / negatif güvenli; copyWith sayıyı günceller', () {
      final row = wkResident(1)..['attachment_count'] = 3;
      expect(WorkResidentItem.fromJson(row).attachmentCount, 3);
      expect(WorkResidentItem.fromJson(wkResident(1)).attachmentCount, 0);
      expect(WorkResidentItem.fromJson(wkResident(1)..['attachment_count'] = -2).attachmentCount, 0);
      expect(WorkResidentItem.fromJson(row).copyWith(attachmentCount: 1).attachmentCount, 1);
      final managed = wkManaged(3)..['attachment_count'] = '2';
      expect(WorkManagedItem.fromJson(managed).attachmentCount, 2);
    });

    test('yönetim ayrıntısı: `attachments` talep nesnesinin içinde gelse de okunur; yükleyen adı', () {
      final item = wkManaged(3)
        ..['attachments'] = <Object>[wkAttachment(7, uploadedBy: 'Mehmet Usta')];
      final detail = WorkManagedDetail.fromJson(<String, dynamic>{
        'item': item,
        'events': <Object>[],
        'next_statuses': <Object>[],
      });
      expect(detail.attachments.single.uploadedByName, 'Mehmet Usta');
      expect(detail.attachments.single.workItemId, 1);
      expect(detail.item.attachmentCount, 1);
      expect(WorkManagedDetail.fromJson(<String, dynamic>{'item': wkManaged(3)}).attachments, isEmpty);
    });

    test('tek ek yanıtı `{ attachment: {...} }` sarmalı; kimliksiz null; durum bilinmiyor güvenli', () {
      final wrapped = WorkAttachment.fromJson(<String, dynamic>{'attachment': wkAttachment(9, status: 'ready')});
      expect(wrapped?.id, 9);
      expect(wrapped?.label, 'ariza.jpg');
      expect(WorkAttachment.fromJson(<String, dynamic>{'attachment': <String, dynamic>{'file_name': 'x'}}), isNull);
      expect(WorkAttachment.fromJson('bozuk'), isNull);
      expect(WorkAttachment.fromJson(wkAttachment(2, status: 'garip'))?.status, WorkAttachmentStatus.unknown);
      expect(const WorkAttachment(id: 1).label, 'Fotoğraf');
    });

    test('kurallar: uzantı -> tür; tür / boş / boyut ön doğrulaması Türkçe', () {
      expect(WorkAttachmentRules.mimeTypeOf('a.JPG'), 'image/jpeg');
      expect(WorkAttachmentRules.mimeTypeOf('b.jpeg'), 'image/jpeg');
      expect(WorkAttachmentRules.mimeTypeOf('c.png'), 'image/png');
      expect(WorkAttachmentRules.mimeTypeOf('d.webp'), 'image/webp');
      expect(WorkAttachmentRules.mimeTypeOf('e.gif'), isNull);
      expect(WorkAttachmentRules.mimeTypeOf('uzantisiz'), isNull);
      expect(WorkAttachmentRules.validate(fileName: 'e.gif', size: 10), 'Yalnız JPEG, PNG veya WebP; en fazla 5 MB.');
      expect(WorkAttachmentRules.validate(fileName: 'a.jpg', size: 0), contains('boş'));
      final big = WorkAttachmentRules.validate(fileName: 'a.jpg', size: kWorkAttachmentMaxBytes + 1);
      expect(big, contains('çok büyük'));
      expect(big, contains('en fazla 5 MB'));
      expect(WorkAttachmentRules.validate(fileName: 'a.jpg', size: kWorkAttachmentMaxBytes), isNull);
      expect(WorkAttachmentRules.limitMessage, 'En fazla 4 fotoğraf eklenebilir.');
      expect(WorkAttachmentRules.closedMessage, 'Kapanmış talebe fotoğraf eklenemez.');
    });

    test('içerik imzası: JPEG / PNG / WebP tanınır, GIF ve kısa içerik tanınmaz; içerik uzantıdan önce gelir', () {
      expect(WorkAttachmentRules.sniffMimeType(<int>[0xFF, 0xD8, 0xFF, 0xE1, 0]), 'image/jpeg');
      expect(WorkAttachmentRules.sniffMimeType(kWkPng), 'image/png');
      expect(WorkAttachmentRules.sniffMimeType(wkImageBytes('x.webp')), 'image/webp');
      expect(WorkAttachmentRules.sniffMimeType(wkImageBytes('x.gif')), isNull);
      expect(WorkAttachmentRules.sniffMimeType(<int>[0xFF, 0xD8]), isNull);
      expect(WorkAttachmentRules.sniffMimeType(<int>[0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x41, 0x56, 0x49, 0x20]), isNull, reason: 'RIFF ama WEBP değil');
      // İçerik okunduysa tür içerikten: .jpg adlı PNG geçerli, .jpg adlı GIF geçersiz.
      expect(WorkAttachmentRules.validate(fileName: 'foto.jpg', size: kWkPng.length, content: kWkPng), isNull);
      expect(
        WorkAttachmentRules.validate(fileName: 'foto.jpg', size: 10, content: wkImageBytes('x.gif', size: 10)),
        WorkAttachmentRules.typeAndSizeMessage,
      );
      expect(WorkAttachmentRules.validate(fileName: 'uzantisiz', size: kWkPng.length, content: kWkPng), isNull);
    });

    test('çözünürlük: kenar > 12.000 ya da > 40 milyon piksel reddedilir; iletiler', () {
      expect(WorkAttachmentRules.dimensionsTooLarge(12000, 3333), isFalse);
      expect(WorkAttachmentRules.dimensionsTooLarge(12001, 10), isTrue);
      expect(WorkAttachmentRules.dimensionsTooLarge(10, 12001), isTrue);
      expect(WorkAttachmentRules.dimensionsTooLarge(8000, 5000), isFalse, reason: 'tam 40 milyon');
      expect(WorkAttachmentRules.dimensionsTooLarge(8000, 5001), isTrue);
      expect(
        WorkAttachmentRules.validate(fileName: 'a.jpg', size: 100, content: wkImageBytes('a.jpg', size: 100), width: 10000, height: 5000),
        'Fotoğrafın çözünürlüğü çok yüksek; daha küçük bir fotoğraf seçin.',
      );
      expect(
        WorkAttachmentRules.quotaMessage(site: false),
        'Bu sitedeki fotoğraf kotanız doldu (en çok 200 MB). Eski fotoğraflarınızdan silebilir ya da yönetime başvurabilirsiniz.',
      );
      expect(WorkAttachmentRules.quotaMessage(site: false, quotaBytes: 100 * 1024 * 1024), contains('en çok 100 MB'));
      expect(WorkAttachmentRules.quotaMessage(site: true), 'Sitenin fotoğraf depolama alanı doldu; yönetime başvurun.');
      expect(
        WorkAttachmentRules.limitBusyMessage,
        'Bu talebe başka bir fotoğraf yükleniyor olabilir; biraz sonra tekrar deneyin.',
      );
    });

    test('uploaded_by_kind: resident / management; bilinmeyen boş', () {
      final resident = WorkAttachment.fromJson(wkAttachment(1, kind: 'resident'))!;
      final management = WorkAttachment.fromJson(wkAttachment(2, kind: 'MANAGEMENT'))!;
      final unknown = WorkAttachment.fromJson(wkAttachment(3, kind: 'x'))!;
      expect(resident.uploadedByKind, 'resident');
      expect(resident.byManagement, isFalse);
      expect(management.uploadedByKind, 'management');
      expect(management.byManagement, isTrue);
      expect(unknown.uploadedByKind, '');
    });

    test('ek bildirimi gövdesi ve talep sonucunun fotoğraf çıktısı', () {
      const request = WorkAttachmentCreateRequest(fileName: ' foto.jpg ', mimeType: 'IMAGE/JPEG', sizeBytes: 12);
      expect(request.toJson(), <String, dynamic>{'file_name': 'foto.jpg', 'mime_type': 'image/jpeg', 'size_bytes': 12});
      final created = WorkCreateResult.fromJson(<String, dynamic>{'item': wkResident(7), 'replayed': false});
      final outcome = created.withPhotoOutcome(uploaded: 1, failed: 2, cancelled: true);
      expect(outcome.item.id, 7);
      expect(outcome.photosUploaded, 1);
      expect(outcome.photosFailed, 2);
      expect(outcome.photosCancelled, isTrue);
      expect(created.photosFailed, 0);
    });
  });

  group('rapor', () {
    test('tam gövde: toplamlar, görevliler (atanmamış satırı), kategoriler, tarihler', () {
      final report = WorkReport.fromJson(wkReportJson(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 19)));
      expect(report.from, DateTime(2026, 10, 1));
      expect(report.to, DateTime(2026, 10, 19));
      expect(report.generatedAt, DateTime.utc(2026, 10, 19, 11, 2));
      expect(report.totals.opened, 12);
      expect(report.totals.resolved, 7);
      expect(report.totals.closed, 5);
      expect(report.totals.cancelled, 1);
      expect(report.totals.openNow, 4);
      expect(report.totals.overdueNow, 2);
      expect(report.totals.avgResolutionHours, 30.4);
      expect(report.totals.medianResolutionHours, 20);
      expect(report.byAssignee.map((a) => a.label), <String>['Ben Yönetici', 'Mehmet Usta', 'Atanmamış']);
      expect(report.byAssignee.last.userCode, isNull);
      expect(report.byAssignee.first.onTimeRate, 0.75);
      expect(report.byAssignee.last.avgResolutionHours, isNull);
      expect(report.byCategory.map((c) => c.label), <String>['Arıza', 'Bakım', 'Diğer']);
      expect(report.byCategory.first.opened, 8);
      expect(report.isEmpty, isFalse);
    });

    test('boş dönem ve bozuk gövde güvenli; bilinmeyen kategori ham adıyla; adsız atanmamış', () {
      final empty = WorkReport.fromJson(wkReportJson(from: DateTime(2026, 1, 1), to: DateTime(2026, 1, 31), empty: true));
      expect(empty.isEmpty, isTrue);
      expect(empty.totals.avgResolutionHours, isNull);
      final broken = WorkReport.fromJson(<String, dynamic>{
        'totals': 'x',
        'by_assignee': <Object>['bozuk', <String, dynamic>{'user_code': null, 'name': ''}],
        'by_category': <Object>[
          <String, dynamic>{'category': 'temizlik', 'opened': '2', 'resolved': null},
        ],
        'from': 'bozuk',
      });
      expect(broken.totals.isEmpty, isTrue);
      expect(broken.byAssignee.single.label, 'Atanmamış');
      expect(broken.byCategory.single.label, 'temizlik');
      expect(broken.byCategory.single.opened, 2);
      expect(broken.from, isNull);
      expect(WorkReportTotals.fromJson(<String, dynamic>{'avg_resolution_hours': -5}).avgResolutionHours, isNull);
      expect(WorkReportTotals.fromJson(<String, dynamic>{'avg_resolution_hours': 'abc'}).avgResolutionHours, isNull);
    });

    test('süre ve oran metinleri: "x sa" / "x gün y sa"; yüzde', () {
      expect(workHoursText(null), '-');
      expect(workHoursText(0), '0 sa');
      expect(workHoursText(0.4), '1 saatten az');
      expect(workHoursText(5), '5 sa');
      expect(workHoursText(23.6), '1 gün');
      expect(workHoursText(30.4), '1 gün 6 sa');
      expect(workHoursText(48), '2 gün');
      expect(workHoursText(52), '2 gün 4 sa');
      expect(workRateText(null), '-');
      expect(workRateText(0.75), '%75');
      expect(workRateText(0.333), '%33');
      expect(workRateText(1), '%100');
      expect(workRateText(85), '%85', reason: 'sunucu yüzde verirse olduğu gibi');
    });
  });
}
