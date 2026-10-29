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
      expect(WorkStatus.known.length, 7, reason: 'yeni, işlemde, beklemede, firmada (111), çözüldü, kapandı, iptal');
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
      // Kişi kotası: YALNIZ sakin, kayan 30 günlük pencere (sunucu iletisiyle aynı metin); eski fotoğraf silme önerilmez.
      expect(
        WorkAttachmentRules.quotaMessage(site: false),
        'Son 30 günde bu sitede yükleyebileceğiniz fotoğraf sınırına ulaştınız (en çok 200 MB); daha sonra yeniden '
        'deneyin ya da yönetime başvurun.',
      );
      expect(WorkAttachmentRules.quotaMessage(site: false, quotaBytes: 100 * 1024 * 1024), contains('(en çok 100 MB)'));
      expect(WorkAttachmentRules.quotaMessage(site: false, quotaBytes: 1572864), contains('(en çok 1,5 MB)'));
      expect(WorkAttachmentRules.quotaMessage(site: false, windowDays: 7), startsWith('Son 7 günde bu sitede'));
      expect(WorkAttachmentRules.quotaMessage(site: false, windowDays: 0), startsWith('Son 30 günde'));
      expect(WorkAttachmentRules.quotaMessage(site: false).toLowerCase(), isNot(contains('sil')));
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

  group('kategoriler (100)', () {
    test('WorkCategoryOption: sunucu satırı, kullanım sayısı, eksik ad anahtardan; bozuk satır atılır; defaults dört hazır kategori', () {
      final option = WorkCategoryOption.fromJson(wkCategory(703, 'k_su_kacagi', 'Su kaçağı', order: 50, itemCount: 4))!;
      expect(option.id, 703);
      expect(option.key, 'k_su_kacagi');
      expect(option.label, 'Su kaçağı');
      expect(option.isSystem, isFalse);
      expect(option.isActive, isTrue);
      expect(option.itemCount, 4);
      expect(option.isUsed, isTrue);
      expect(option.legacy, WorkCategory.diger, reason: 'özel kategori simge için "diger" gibi çizilir');

      final system = WorkCategoryOption.fromJson(<String, dynamic>{'id': 1, 'key': 'bakim', 'is_system': true})!;
      expect(system.label, 'Bakım', reason: 'ad yoksa varsayılan ad');
      expect(system.itemCount, isNull);
      expect(system.isUsed, isFalse);
      expect(system.legacy, WorkCategory.bakim);
      expect(WorkCategoryOption.fromJson(<String, dynamic>{'key': 'k_x'})!.label, 'k_x', reason: 'bilinmeyen anahtar adsızsa anahtar');
      expect(WorkCategoryOption.fromJson(<String, dynamic>{'id': 4, 'is_active': false}), isNull, reason: 'anahtarsız satır atılır');
      expect(WorkCategoryOption.fromJson('x'), isNull);
      expect(WorkCategoryOption.fromJson(<String, dynamic>{'category': wkCategory(9, 'diger', 'Diğer', system: true, active: false)})!.isActive, isFalse, reason: 'sarmalı gövde');

      final list = WorkCategoryOption.listFrom(<Object?>[wkCategory(1, 'ariza', 'Arıza', system: true), 'bozuk', <String, dynamic>{}, wkCategory(2, 'k_a', 'A')]);
      expect(list.map((c) => c.key), <String>['ariza', 'k_a']);
      expect(WorkCategoryOption.listFrom(null), isEmpty);
      expect(WorkCategoryOption.defaults.map((c) => c.key), <String>['ariza', 'bakim', 'sikayet_oneri', 'diger']);
      expect(WorkCategoryOption.defaults.map((c) => c.label), <String>['Arıza', 'Bakım', 'Şikayet / Öneri', 'Diğer']);
      expect(WorkCategoryOption.defaults.every((c) => c.isSystem && c.isActive), isTrue);
    });

    test('silme sonucu: silindi ya da KULLANILDIĞI için pasife alındı (güncel kategoriyle)', () {
      final gone = WorkCategoryDeleteResult.fromJson(<String, dynamic>{'deleted': true});
      expect([gone.deleted, gone.deactivated, gone.category], <Object?>[true, false, null]);
      final off = WorkCategoryDeleteResult.fromJson(<String, dynamic>{
        'deleted': false,
        'deactivated': true,
        'category': wkCategory(9, 'k_su', 'Su', active: false, itemCount: 3),
      });
      expect([off.deleted, off.deactivated, off.category?.isActive, off.category?.itemCount], <Object?>[false, true, false, 3]);
      expect(WorkCategoryDeleteResult.fromJson(null).deleted, isFalse);
    });

    test('talep kategorisi: anahtar + sunucu adı; ad yoksa varsayılan ad; bilinmeyen anahtar enum için "diger" (eski uygulama çökmez)', () {
      final managed = WorkManagedItem.fromJson(wkManaged(1, category: 'k_su_kacagi', categoryLabel: 'Su kaçağı'));
      expect(managed.categoryKey, 'k_su_kacagi');
      expect(managed.categoryLabel, 'Su kaçağı');
      expect(managed.categoryText, 'Su kaçağı');
      expect(managed.category, WorkCategory.diger);

      final renamed = WorkManagedItem.fromJson(wkManaged(2, category: 'ariza', categoryLabel: 'Teknik arıza'));
      expect(renamed.category, WorkCategory.ariza);
      expect(renamed.categoryText, 'Teknik arıza');

      final oldServer = WorkManagedItem.fromJson(wkManaged(3, category: 'bakim'));
      expect([oldServer.categoryLabel, oldServer.categoryText], <String>['', 'Bakım'], reason: 'eski sunucu: category_label yok');

      final resident = WorkResidentItem.fromJson(wkResident(4, category: 'k_asansor', categoryLabel: 'Asansör'));
      expect([resident.categoryKey, resident.categoryText, resident.category], <Object>['k_asansor', 'Asansör', WorkCategory.diger]);
      expect(resident.copyWith(unread: false).categoryText, 'Asansör', reason: 'copyWith kategori adını korur');
      expect(WorkResidentItem.fromJson(wkResident(5, category: 'sikayet_oneri')).categoryText, 'Şikayet / Öneri');
    });

    test('talep gövdesi: varsayılan kategoride kategori enumu, sitenin kategorisinde k_<ad> gider; imza anahtarı ayırır', () {
      const base = WorkCreateRequest(
        siteCode: 11,
        category: WorkCategory.bakim,
        locationType: WorkLocationType.ortakAlan,
        title: 'Başlık',
        description: 'Açıklama',
      );
      expect(base.categoryApiValue, 'bakim');
      expect(base.toJson('k-12345678')['category'], 'bakim');
      const custom = WorkCreateRequest(
        siteCode: 11,
        category: WorkCategory.diger,
        categoryKey: 'k_su_kacagi',
        locationType: WorkLocationType.ortakAlan,
        title: 'Başlık',
        description: 'Açıklama',
      );
      expect(custom.categoryApiValue, 'k_su_kacagi');
      expect(custom.toJson('k-12345678')['category'], 'k_su_kacagi');
      expect(custom.signature, isNot(base.signature));
      const blank = WorkCreateRequest(
        siteCode: 11,
        category: WorkCategory.ariza,
        categoryKey: '  ',
        locationType: WorkLocationType.ortakAlan,
        title: 'T',
        description: 'D',
      );
      expect(blank.categoryApiValue, 'ariza', reason: 'boş anahtar yok sayılır');
    });

    test('rapor: sitedeki kategori adı (category_label) öncelikli; yoksa varsayılan ad; bilinmeyen anahtar etikette olduğu gibi', () {
      final report = WorkReport.fromJson(<String, dynamic>{
        'by_category': <Object>[
          <String, dynamic>{'category': 'ariza', 'category_label': 'Teknik arıza', 'opened': 2, 'resolved': 1},
          <String, dynamic>{'category': 'bakim', 'opened': 1, 'resolved': 0},
          <String, dynamic>{'category': 'k_su_kacagi', 'category_label': 'Su kaçağı', 'opened': 3, 'resolved': 2},
          <String, dynamic>{'category': 'k_eski', 'opened': 1, 'resolved': 0},
        ],
      });
      expect(report.byCategory.map((c) => c.label), <String>['Teknik arıza', 'Bakım', 'Su kaçağı', 'k_eski']);
    });
  });

  group('fotoğraf uyarıları (100)', () {
    test('WorkPhotoWarning: kod, önem, mesaj, ilgili kayıt kimlikleri; mesajsız / fotoğrafsız uyarı atılır', () {
      final warning = WorkPhotoWarning.fromJson(wkPhotoWarning(12, related: <int>[45, 41]))!;
      expect(warning.code, 'photo_reused_other_location');
      expect(warning.attachmentId, 12);
      expect(warning.severity, WorkPhotoWarningSeverity.warning);
      expect(warning.isWarning, isTrue);
      expect(warning.relatedCount, 2);
      expect(warning.relatedItemIds, <int>[45, 41]);
      expect(warning.message, contains('farklı bir konuma ait'));

      final info = WorkPhotoWarning.fromJson(wkPhotoWarning(3, code: 'photo_reused', severity: 'info', message: 'Aynı konumda.', related: <int>[]))!;
      expect([info.isWarning, info.relatedItemIds], <Object>[false, <int>[]]);
      final unknownSeverity = WorkPhotoWarning.fromJson(<String, dynamic>{'code': 'x', 'attachment_id': 4, 'message': 'Metin'})!;
      expect(unknownSeverity.severity, WorkPhotoWarningSeverity.info, reason: 'bilinmeyen önem bilgi sayılır');

      expect(WorkPhotoWarning.fromJson(<String, dynamic>{'attachment_id': 4, 'message': ''}), isNull);
      expect(WorkPhotoWarning.fromJson(<String, dynamic>{'message': 'Metin'}), isNull);
      expect(WorkPhotoWarning.fromJson(<String, dynamic>{'attachment_id': 0, 'message': 'Metin'}), isNull);
      expect(WorkPhotoWarning.fromJson('x'), isNull);
      final cleaned = WorkPhotoWarning.fromJson(<String, dynamic>{
        'attachment_id': 5,
        'message': 'Metin',
        'related': <Object>[
          <String, dynamic>{'work_item_id': 7},
          <String, dynamic>{'work_item_id': 0},
          'bozuk',
          <String, dynamic>{},
        ],
      })!;
      expect(cleaned.relatedItemIds, <int>[7]);
      expect(WorkPhotoWarning.listFrom(null), isEmpty);
      expect(WorkPhotoWarning.listFrom(<Object?>[wkPhotoWarning(1), 'x', <String, dynamic>{}]).length, 1);
    });

    test('yönetim ayrıntısı: photo_warnings okunur; eski sunucuda yoksa boş (çökmez)', () {
      final item = wkManaged(1);
      final withWarnings = WorkManagedDetail.fromJson(<String, dynamic>{
        'item': item,
        'events': <Object>[],
        'attachments': <Object>[wkAttachment(901), wkAttachment(902)],
        'photo_warnings': <Object>[wkPhotoWarning(902), wkPhotoWarning(901, code: 'photo_duplicate_in_item', severity: 'info', message: 'Aynı fotoğraf bu kayıtta birden fazla kez eklenmiş.', related: <int>[])],
      });
      expect(withWarnings.photoWarnings.map((w) => w.attachmentId), <int>[902, 901]);
      final old = WorkManagedDetail.fromJson(<String, dynamic>{'item': item});
      expect(old.photoWarnings, isEmpty);
      expect(WorkManagedDetail.fromJson(<String, dynamic>{'item': item, 'photo_warnings': 'bozuk'}).photoWarnings, isEmpty);
    });

    test('yükleme tamamlama yanıtı: attachment + photo_warnings; liste satırında ve sakin yanıtında uyarı yok', () {
      final upload = WorkAttachment.fromJson(<String, dynamic>{
        'attachment': wkAttachment(31, workItemId: 5),
        'photo_warnings': <Object>[wkPhotoWarning(31)],
      })!;
      expect(upload.id, 31);
      expect(upload.photoWarnings.map((w) => w.attachmentId), <int>[31]);
      expect(WorkAttachment.fromJson(<String, dynamic>{'attachment': wkAttachment(32)})!.photoWarnings, isEmpty);
      expect(WorkAttachment.fromJson(wkAttachment(33))!.photoWarnings, isEmpty);
      expect(WorkAttachment.listFrom(<Object>[wkAttachment(1), wkAttachment(2)]).every((a) => a.photoWarnings.isEmpty), isTrue);
      final resident = WorkResidentDetail.fromJson(<String, dynamic>{'item': wkResident(1), 'attachments': <Object>[wkAttachment(1)]});
      expect(resident.attachments.single.photoWarnings, isEmpty);
    });
  });
}
