// Platform Faz 3a (Duyuru ve Bildirim): modeller, İstanbul saati ve saat girişi yardımcıları.
//
// Sunucunun GERÇEK yanıt biçimi (server/src/modules/announcement_*.js) kullanılır: alan yok / bozuk ise
// güvenli varsayılan; zaman damgaları cihaz saat diliminden bağımsız İstanbul (UTC+3) olarak gösterilir.
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/models/audit_log.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/time_input.dart';
import 'package:site_kapi_kontrol/ui/widgets/module_card.dart';

Map<String, dynamic> _summaryJson({Map<String, dynamic> extra = const <String, dynamic>{}}) =>
    <String, dynamic>{
      'id': 41,
      'title': 'Asansör bakımı',
      'body_preview': 'Yarın 10:00-12:00 arası asansör hizmet vermeyecek.',
      'importance': 'urgent',
      'status': 'published',
      'target_type': 'blocks',
      'publish_at': null,
      'published_at': '2026-10-15T21:30:00.000Z',
      'edited_at': '2026-10-16T06:00:00.000Z',
      'send_email': true,
      'recipient_count': 48,
      'read_count': 12,
      'created_at': '2026-10-15T20:00:00.000Z',
      'created_by_name': 'Site Yöneticisi',
      ...extra,
    };

Map<String, dynamic> _detailJson() => <String, dynamic>{
  ..._summaryJson(),
  'body': 'Yarın 10:00-12:00 arası asansör hizmet vermeyecek.\nAnlayışınız için teşekkürler.',
  'target': <String, dynamic>{
    'type': 'blocks',
    'block_ids': <int>[3, 4],
    'apartment_ids': <int>[],
    'labels': <String>['A Blok', 'B Blok'],
  },
  'stats': <String, dynamic>{
    'recipients': 48,
    'read': 12,
    'unread': 36,
    'email': <String, dynamic>{
      'requested': 40,
      'sent': 32,
      'failed': 1,
      'no_address': 4,
      'skipped_pref': 2,
      'capped': 0,
      'duplicate': 1,
      'pending': 0,
    },
  },
};

void main() {
  group('enum çözümleme', () {
    test('durum: bilinen değerler Türkçe etiketli; bilinmeyen / eksik "unknown" (yazma eylemi yok)', () {
      expect(AnnouncementStatus.fromApi('draft').label, 'Taslak');
      expect(AnnouncementStatus.fromApi('scheduled').label, 'Zamanlanmış');
      expect(AnnouncementStatus.fromApi(' PUBLISHED ').label, 'Yayında');
      expect(AnnouncementStatus.fromApi('withdrawn').label, 'Geri çekildi');
      expect(AnnouncementStatus.fromApi('arşivlendi'), AnnouncementStatus.unknown);
      expect(AnnouncementStatus.fromApi(null), AnnouncementStatus.unknown);
      expect(AnnouncementStatus.unknown.isEditable, isFalse);
      expect(AnnouncementStatus.draft.isEditable, isTrue);
      expect(AnnouncementStatus.scheduled.isEditable, isTrue);
      expect(AnnouncementStatus.published.isEditable, isFalse);
    });

    test('önem: yalnız "urgent" acildir; eksik / bilinmeyen normaldir', () {
      expect(AnnouncementImportance.fromApi('urgent'), AnnouncementImportance.urgent);
      expect(AnnouncementImportance.fromApi('normal'), AnnouncementImportance.normal);
      expect(AnnouncementImportance.fromApi('kritik'), AnnouncementImportance.normal);
      expect(AnnouncementImportance.fromApi(null), AnnouncementImportance.normal);
      expect(AnnouncementImportance.urgent.label, 'Acil');
    });

    test('hedef türü ve alıcı e-posta durumu', () {
      expect(AnnouncementTargetType.fromApi('apartments'), AnnouncementTargetType.apartments);
      expect(AnnouncementTargetType.fromApi('x'), AnnouncementTargetType.site);
      expect(<String>[for (final t in AnnouncementTargetType.values) t.label], <String>[
        'Tüm site',
        'Bloklar',
        'Daireler',
      ]);
      expect(EmailDelivery.fromApi('no_address'), EmailDelivery.noAddress);
      expect(EmailDelivery.fromApi('skipped_pref'), EmailDelivery.skippedPref);
      expect(EmailDelivery.fromApi('???'), EmailDelivery.none);
      expect(EmailDelivery.sent.label, 'E-posta gönderildi');
    });
  });

  group('AnnouncementSummary / AnnouncementDetail', () {
    test('sunucu özet satırı alan alan ayrışır (UTC an olarak)', () {
      final s = AnnouncementSummary.fromJson(_summaryJson());
      expect(s.id, 41);
      expect(s.title, 'Asansör bakımı');
      expect(s.importance, AnnouncementImportance.urgent);
      expect(s.status, AnnouncementStatus.published);
      expect(s.targetType, AnnouncementTargetType.blocks);
      expect(s.sendEmail, isTrue);
      expect(s.recipientCount, 48);
      expect(s.readCount, 12);
      expect(s.hasAudience, isTrue);
      expect(s.createdByName, 'Site Yöneticisi');
      expect(s.publishedAt, DateTime.utc(2026, 10, 15, 21, 30));
      expect(s.publishedAt!.isUtc, isTrue);
      expect(s.publishAt, isNull);
    });

    test('eksik / bozuk alanlarda güvenli varsayılan (sayfa çökmez)', () {
      final s = AnnouncementSummary.fromJson(<String, dynamic>{
        'id': '7',
        'title': null,
        'status': 42,
        'published_at': 'bozuk-tarih',
        'recipient_count': 'x',
      });
      expect(s.id, 7);
      expect(s.title, '');
      expect(s.status, AnnouncementStatus.unknown);
      expect(s.importance, AnnouncementImportance.normal);
      expect(s.publishedAt, isNull);
      expect(s.recipientCount, 0);
      expect(s.readCount, 0);
      expect(s.sendEmail, isFalse);
      expect(s.hasAudience, isFalse);
    });

    test('ayrıntı: metin, hedef, istatistik ve e-posta sayıları; "requested" sayı ya da bayrak olabilir', () {
      final d = AnnouncementDetail.fromJson(_detailJson());
      expect(d.body, contains('teşekkürler'));
      expect(d.target.type, AnnouncementTargetType.blocks);
      expect(d.target.blockIds, <int>[3, 4]);
      expect(d.target.labels, <String>['A Blok', 'B Blok']);
      expect(d.target.summary(), 'A Blok, B Blok');
      expect(d.stats.recipients, 48);
      expect(d.stats.read, 12);
      expect(d.stats.unread, 36);
      expect(d.stats.email.requested, isTrue);
      expect(d.stats.email.sent, 32);
      expect(
        d.stats.email.summary,
        '32 gönderildi, 1 gönderilemedi, 4 kişinin e-postası yok, 2 kişinin e-posta tercihi kapalı, 1 aynı adres, tekrar gönderilmedi',
      );
      // bayrak biçimi
      final flag = AnnouncementStats.fromJson(<String, dynamic>{
        'recipients': 3,
        'read': 1,
        'email': <String, dynamic>{'requested': true, 'sent': 0},
      });
      expect(flag.email.requested, isTrue);
      expect(flag.unread, 2, reason: 'unread yoksa alıcı - okuyan');
      expect(const AnnouncementEmailStats().summary, isNull);
    });

    test('G3: kurul + küçük hedef: read_count / stats.read / unread / email.* null -> 0 SAYILMAZ, gizli', () {
      final hiddenSummary = AnnouncementSummary.fromJson(_summaryJson(extra: <String, dynamic>{
        'recipient_count': 3,
        'read_count': null,
      }));
      expect(hiddenSummary.readCount, isNull, reason: 'null -> 0 yapılmaz');
      expect(hiddenSummary.readHidden, isTrue);
      expect(hiddenSummary.hasAudience, isTrue);

      final detail = AnnouncementDetail.fromJson(<String, dynamic>{
        ..._detailJson(),
        'recipient_count': 3,
        'read_count': null,
        'stats': <String, dynamic>{
          'recipients': 3,
          'read': null,
          'unread': null,
          'email': <String, dynamic>{
            'requested': null,
            'sent': null,
            'failed': null,
            'no_address': null,
            'skipped_pref': null,
            'capped': null,
            'duplicate': null,
            'pending': null,
          },
        },
      });
      expect(detail.readCount, isNull);
      expect(detail.readHidden, isTrue);
      expect(detail.stats.read, isNull);
      expect(detail.stats.unread, isNull);
      expect(detail.stats.readHidden, isTrue);
      expect(detail.stats.recipients, 3);
      expect(detail.stats.email.hidden, isTrue);
      expect(detail.stats.email.summary, isNull);
    });

    test('G3: alan HİÇ yoksa (eski sunucu) 0 sayılır; sayı varsa olduğu gibi (gizli sayılmaz)', () {
      final noKey = AnnouncementSummary.fromJson(<String, dynamic>{'id': 3, 'recipient_count': 4});
      expect(noKey.readCount, 0);
      expect(noKey.readHidden, isFalse);
      final zero = AnnouncementSummary.fromJson(_summaryJson(extra: <String, dynamic>{'read_count': 0}));
      expect(zero.readCount, 0);
      expect(zero.readHidden, isFalse);
      final stats = AnnouncementStats.fromJson(<String, dynamic>{'recipients': 4});
      expect(stats.read, 0);
      expect(stats.readHidden, isFalse);
      // e-posta nesnesi boş: gizli DEĞİL (sayı yok = sıfır)
      expect(AnnouncementEmailStats.fromJson(<String, dynamic>{}).hidden, isFalse);
    });

    test('G18a: target.blocks / apartments (kimlik + ad) ayrışır; bozuk satır atlanır; eski sunucuda boş liste', () {
      final target = AnnouncementTarget.fromJson(<String, dynamic>{
        'type': 'apartments',
        'block_ids': <int>[],
        'apartment_ids': <int>[11, 12, 13],
        'labels': <String>['A - 1', 'A - 2'],
        'blocks': <dynamic>[],
        'apartments': <dynamic>[
          <String, dynamic>{'id': 11, 'label': 'A Blok - 1'},
          <String, dynamic>{'id': '12', 'label': 'A Blok - 2'},
          <String, dynamic>{'id': 13, 'label': ''},
          <String, dynamic>{'label': 'kimliksiz'},
          'bozuk',
        ],
      });
      expect(<int>[for (final a in target.apartments) a.id], <int>[11, 12]);
      expect(<String>[for (final a in target.apartments) a.label], <String>['A Blok - 1', 'A Blok - 2']);
      expect(target.blocks, isEmpty);
      final blocks = AnnouncementTarget.fromJson(<String, dynamic>{
        'type': 'blocks',
        'block_ids': <int>[3],
        'blocks': <dynamic>[
          <String, dynamic>{'id': 3, 'name': 'A Blok'},
        ],
      });
      expect(blocks.blocks.single.id, 3);
      expect(blocks.blocks.single.name, 'A Blok');
      final legacy = AnnouncementTarget.fromJson(<String, dynamic>{
        'type': 'blocks',
        'block_ids': <int>[3],
        'labels': <String>['A Blok'],
      });
      expect(legacy.blocks, isEmpty);
      expect(legacy.apartments, isEmpty);
      expect(legacy.blockIds, <int>[3]);
    });

    test('düz ya da { announcement: {...} } sarmalı yanıt aynı sonucu verir', () {
      final plain = AnnouncementDetail.fromJson(_detailJson());
      final wrapped = AnnouncementDetail.fromJson(<String, dynamic>{'announcement': _detailJson()});
      expect(wrapped.id, plain.id);
      expect(wrapped.body, plain.body);
      expect(wrapped.target.labels, plain.target.labels);
    });

    test('hedef özeti: site, etiket yokken sayı, uzun listede "ve N daha"', () {
      expect(const AnnouncementTarget().summary(), 'Tüm site');
      expect(
        const AnnouncementTarget(
          type: AnnouncementTargetType.apartments,
          apartmentIds: <int>[1, 2, 3],
        ).summary(),
        '3 daire',
      );
      final many = AnnouncementTarget(
        type: AnnouncementTargetType.apartments,
        apartmentIds: List<int>.generate(9, (i) => i + 1),
        labels: List<String>.generate(9, (i) => 'A - ${i + 1}'),
      );
      expect(many.summary(), 'A - 1, A - 2, A - 3, A - 4, A - 5, A - 6 ve 3 daire daha');
      expect(const AnnouncementTarget(type: AnnouncementTargetType.blocks).summary(), 'Seçili blok yok');
    });
  });

  group('alıcılar, önizleme, hedef gövdesi', () {
    test('alıcı satırı ve sayfa', () {
      final page = AnnouncementRecipientPage.fromJson(<String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'person_id': 5,
            'full_name': 'Ayşe Yılmaz',
            'apartments': <String>['A Blok - 5'],
            'has_account': true,
            'read_at': '2026-10-16T05:15:00Z',
            'email_status': 'sent',
          },
          <String, dynamic>{'person_id': 6, 'full_name': null, 'has_account': false, 'email_status': 'bilinmeyen'},
        ],
        'total': 9,
      });
      expect(page.total, 9);
      final first = page.items.first;
      expect(first.isRead, isTrue);
      expect(first.apartments, <String>['A Blok - 5']);
      expect(first.emailStatus, EmailDelivery.sent);
      final second = page.items.last;
      expect(second.isRead, isFalse);
      expect(second.fullName, '');
      expect(second.emailStatus, EmailDelivery.none);
      expect(second.apartments, isEmpty);
    });

    test('kitle önizlemesi', () {
      final p = AudiencePreview.fromJson(<String, dynamic>{
        'people': 48,
        'apartments': 30,
        'with_account': 40,
        'with_email': 44,
        'without_email': 4,
      });
      expect((p.people, p.apartments, p.withAccount, p.withEmail, p.withoutEmail), (48, 30, 40, 44, 4));
      expect(AudiencePreview.fromJson(<String, dynamic>{}).people, 0);
    });

    test('hedef gövdesi yalnız seçili türün kimliklerini taşır', () {
      expect(const AnnouncementTargetInput().toJson(), <String, dynamic>{'type': 'site'});
      expect(
        const AnnouncementTargetInput(
          type: AnnouncementTargetType.blocks,
          blockIds: <int>[1, 2],
          apartmentIds: <int>[9],
        ).toJson(),
        <String, dynamic>{'type': 'blocks', 'block_ids': <int>[1, 2]},
      );
      expect(
        const AnnouncementTargetInput(
          type: AnnouncementTargetType.apartments,
          blockIds: <int>[1],
          apartmentIds: <int>[9, 10],
        ).toJson(),
        <String, dynamic>{'type': 'apartments', 'apartment_ids': <int>[9, 10]},
      );
    });
  });

  group('sakin modelleri ve bildirim', () {
    test('gelen kutusu satırı ve sayfa (next_before_id)', () {
      final page = ResidentAnnouncementPage.fromJson(<String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 41,
            'site_code': 11,
            'site_name': 'Gül Sitesi',
            'title': 'Su kesintisi',
            'body_preview': 'Yarın su yok.',
            'importance': 'urgent',
            'published_at': '2026-10-16T08:00:00Z',
            'edited_at': null,
            'is_read': false,
          },
          <String, dynamic>{'id': 40, 'site_name': null, 'is_read': true},
        ],
        'next_before_id': 40,
      });
      expect(page.hasMore, isTrue);
      expect(page.nextBeforeId, 40);
      final first = page.items.first;
      expect(first.isUrgent, isTrue);
      expect(first.isRead, isFalse);
      expect(first.isEdited, isFalse);
      expect(first.previewOrBody, 'Yarın su yok.');
      expect(first.copyWith(isRead: true).isRead, isTrue);
      expect(page.items.last.siteName, '');
      expect(ResidentAnnouncementPage.fromJson(<String, dynamic>{'items': <dynamic>[]}).hasMore, isFalse);
    });

    test('ayrıntı: tam metin ve düzenlendi zamanı', () {
      final d = ResidentAnnouncement.fromJson(<String, dynamic>{
        'id': 41,
        'title': 'Su kesintisi',
        'body': 'Tam metin',
        'edited_at': '2026-10-16T09:00:00Z',
        'is_read': true,
        'read_at': '2026-10-16T09:05:00Z',
      });
      expect(d.body, 'Tam metin');
      expect(d.isEdited, isTrue);
      expect(d.previewOrBody, 'Tam metin');
    });

    test('bildirim özeti: negatif / tutarsız sayılar düzeltilir; imza numara + yayın zamanını içerir', () {
      final s = NotificationSummary.fromJson(<String, dynamic>{
        'unread_announcements': 2,
        'unread_urgent': 5,
        'latest_announcement_id': 41,
        'latest_published_at': '2026-10-16T08:00:00Z',
        'server_time': '2026-10-16T08:01:00Z',
      });
      expect(s.unreadAnnouncements, 2);
      expect(s.unreadUrgent, 2, reason: 'acil sayısı toplamı aşamaz');
      expect(s.latestAnnouncementId, 41);
      expect(s.latestPublishedAt, DateTime.utc(2026, 10, 16, 8));
      expect(s.latestSignature, '41|${DateTime.utc(2026, 10, 16, 8).millisecondsSinceEpoch}');
      final empty = NotificationSummary.fromJson(<String, dynamic>{'unread_announcements': -3});
      expect(empty.unreadAnnouncements, 0);
      expect(empty.latestAnnouncementId, isNull);
      expect(empty.latestSignature, '|');
      expect(s == NotificationSummary.fromJson(<String, dynamic>{
        'unread_announcements': 2,
        'unread_urgent': 2,
        'latest_announcement_id': 41,
        'latest_published_at': '2026-10-16T08:00:00Z',
      }), isTrue);
    });

    test('bildirim tercihleri: kayıt yoksa e-posta açık, telefon bildirimi yok', () {
      final prefs = NotificationPrefs.fromJson(<String, dynamic>{
        'email_announcements': false,
        'push_announcements': true,
        'push_available': false,
      });
      expect(prefs.emailAnnouncements, isFalse);
      expect(prefs.pushAvailable, isFalse);
      final defaults = NotificationPrefs.fromJson(<String, dynamic>{});
      expect(defaults.emailAnnouncements, isTrue);
      expect(defaults.pushAvailable, isFalse);
      // PUT yanıtında alan yoksa istenen değer geçerli sayılır.
      expect(NotificationPrefs.fromJson(<String, dynamic>{}, fallbackEmail: false).emailAnnouncements, isFalse);
      expect(prefs.copyWith(emailAnnouncements: true).emailAnnouncements, isTrue);
    });
  });

  group('zaman: İstanbul (UTC+3), cihaz saat diliminden bağımsız', () {
    test('announcementInstant: Z, ofset ve zonesuz metin (UTC sayılır)', () {
      expect(announcementInstant('2026-10-16T08:00:00Z'), DateTime.utc(2026, 10, 16, 8));
      expect(announcementInstant('2026-10-16T11:00:00+03:00'), DateTime.utc(2026, 10, 16, 8));
      expect(announcementInstant('2026-10-16T05:00:00-03:00'), DateTime.utc(2026, 10, 16, 8));
      expect(announcementInstant('2026-10-16 08:00:00'), DateTime.utc(2026, 10, 16, 8));
      expect(announcementInstant('2026-10-16T08:00:00.123456Z'), DateTime.utc(2026, 10, 16, 8, 0, 0, 123, 456));
      expect(announcementInstant(null), isNull);
      expect(announcementInstant(''), isNull);
      expect(announcementInstant('dün'), isNull);
    });

    test('gösterim: gün sınırını aşan an doğru İstanbul gününe düşer', () {
      // 15.10 21:30 UTC = 16.10 00:30 İstanbul.
      final instant = DateTime.utc(2026, 10, 15, 21, 30);
      expect(formatIstanbulDate(instant), '16.10.2026');
      expect(formatIstanbulTime(instant), '00:30');
      expect(formatIstanbulDateTime(instant), '16.10.2026 00:30');
      expect(formatIstanbulDateTime(null), '-');
      // Yerel (toLocal) bir nesne verilse de sonuç aynıdır: cihaz saat dilimine bakılmaz.
      expect(formatIstanbulDateTime(instant.toLocal()), '16.10.2026 00:30');
      expect(formatIstanbulDateTime(DateTime.utc(2026, 1, 1, 20, 59)), '01.01.2026 23:59');
      expect(formatIstanbulDateTime(DateTime.utc(2026, 12, 31, 21, 0)), '01.01.2027 00:00');
    });

    test('istanbulInstantOf: İstanbul duvar saatinden gerçek ana, gidiş-dönüş tutarlı', () {
      final instant = istanbulInstantOf(DateTime(2026, 10, 20), 0, 30);
      expect(instant, DateTime.utc(2026, 10, 19, 21, 30));
      expect(instant.isUtc, isTrue);
      expect(formatIstanbulDateTime(instant), '20.10.2026 00:30');
      expect(istanbulWallClock(instant), DateTime.utc(2026, 10, 20, 0, 30));
      expect(istanbulNow(DateTime.utc(2026, 10, 16, 21, 30)), DateTime.utc(2026, 10, 17, 0, 30));
    });

    test('G17: istanbulCalendarYearAfter İstanbul duvar saatinden TAKVİM olarak 1 yıl sonradır (365 gün değil)', () {
      // 16.10.2026 21:30 UTC = 17.10.2026 00:30 İstanbul -> 17.10.2027 00:30 İstanbul = 16.10.2027 21:30 UTC
      expect(istanbulCalendarYearAfter(DateTime.utc(2026, 10, 16, 21, 30)), DateTime.utc(2027, 10, 16, 21, 30));
      // artık yıl aşan aralıkta 365 gün sonrası bir gün eksik kalırdı: 2027-11-01 + 1 yıl = 2028-11-01
      expect(istanbulCalendarYearAfter(DateTime.utc(2027, 11, 1, 9)), DateTime.utc(2028, 11, 1, 9));
      // 29 Şubat -> 1 Mart (sunucudaki setFullYear(+1) ile aynı)
      expect(istanbulCalendarYearAfter(DateTime.utc(2028, 2, 29, 9)), DateTime.utc(2029, 3, 1, 9));
      expect(istanbulCalendarYearAfter(DateTime.utc(2026, 10, 16)).isUtc, isTrue);
    });
  });

  group('saat girişi (SS:DD)', () {
    test('parseTimeField / validateTimeField', () {
      expect(parseTimeField('14:30'), (hour: 14, minute: 30));
      expect(parseTimeField(' 00:00 '), (hour: 0, minute: 0));
      expect(parseTimeField('23:59'), (hour: 23, minute: 59));
      for (final bad in <String?>['24:00', '12:60', '9:30', '1430', '14:3', 'aa:bb', '', null, '-1:00']) {
        expect(parseTimeField(bad), isNull, reason: '$bad');
      }
      expect(validateTimeField(''), isNull, reason: 'boş serbest (gerekliliği çağıran belirler)');
      expect(validateTimeField('14:30'), isNull);
      expect(validateTimeField('14'), 'Saati SS:DD biçiminde girin (örn. 14:30).');
      expect(validateTimeField('aa:bb'), 'Saati SS:DD biçiminde girin (örn. 14:30).');
    });

    test('G13: biçim doğru ama değer geçersiz -> "Geçersiz saat" (25:00, 12:61)', () {
      for (final bad in <String>['25:00', '24:00', '12:61', '23:60', '99:99']) {
        expect(
          validateTimeField(bad),
          'Geçersiz saat. Saat 00-23, dakika 00-59 olmalı (örn. 14:30).',
          reason: bad,
        );
      }
    });

    TextEditingValue type(String oldText, String newText, {int? caret}) {
      const formatter = TimeInputFormatter();
      return formatter.formatEditUpdate(
        TextEditingValue(text: oldText, selection: TextSelection.collapsed(offset: oldText.length)),
        TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: caret ?? newText.length),
        ),
      );
    }

    test('yazarken iki noktayı kendisi koyar', () {
      expect(type('', '1').text, '1');
      expect(type('1', '14').text, '14');
      expect(type('14', '143').text, '14:3');
      expect(type('14:3', '14:30').text, '14:30');
      expect(type('9', '9:').text, '09:');
      expect(type('', '1430').text, '14:30');
    });

    test('yapıştırma normalize edilir; 4 rakamdan fazlası REDDEDİLİR (kırpılmaz)', () {
      expect(type('', '9:30').text, '09:30');
      expect(type('', '09.30').text, '09:30');
      expect(type('14:30', '14:305').text, '14:30');
      expect(type('14:30', '14:30').text, '14:30');
    });

    test('G10: yapıştırma eklenen parçadan algılanır: "9:30", "930", "9.30", "0930"', () {
      expect(type('', '9:30').text, '09:30');
      expect(type('', '930').text, '09:30');
      expect(type('', '9.30').text, '09:30');
      expect(type('', '0930').text, '09:30');
      // geçersiz yapıştırma: alan değişmez
      expect(type('', 'abc').text, '');
      expect(type('14', '14abc').text, '14');
      expect(type('', '9:3000').text, '');
    });

    test('G10: dolu alana yapıştırma eklenen parçayı normalize eder, mevcut metni bozmaz', () {
      // "14:" sonuna "30" yapıştırılırsa 4 rakam: "14:30"
      expect(type('14:', '14:30').text, '14:30');
      // mevcut tam saatin sonuna fazladan rakam eklenemez
      expect(type('14:30', '14:301').text, '14:30');
      // yazarken tek rakam ekleme normal yazmadır (yapıştırma sayılmaz)
      expect(type('0', '09').text, '09');
    });

    test('G10: tüm metin SEÇİLİ iken üstüne yapıştırma: eklenen parça seçili aralığa göre bulunur', () {
      const formatter = TimeInputFormatter();
      TextEditingValue paste(String oldText, String pasted, {required int start, required int end}) {
        final text = oldText.replaceRange(start, end, pasted);
        return formatter.formatEditUpdate(
          TextEditingValue(text: oldText, selection: TextSelection(baseOffset: start, extentOffset: end)),
          TextEditingValue(text: text, selection: TextSelection.collapsed(offset: start + pasted.length)),
        );
      }

      // "09:30" tamamen seçili, "930" yapıştırılır: ortak önek / sonek yöntemi eklenen parçayı boş sanırdı.
      expect(paste('09:30', '930', start: 0, end: 5).text, '09:30');
      expect(paste('12:00', '9:30', start: 0, end: 5).text, '09:30');
      expect(paste('12:00', '8.15', start: 0, end: 5).text, '08:15');
      // yalnız dakika kısmı seçili: "12:00" -> "12:" + "45"
      expect(paste('12:00', '45', start: 3, end: 5).text, '12:45');
      // geçersiz yapıştırma seçili metni bozmaz
      expect(paste('12:00', 'ab', start: 0, end: 5).text, '12:00');
    });

    test('ortadan düzeltmede imleç sona atlamaz', () {
      // "14:30" -> kullanıcı "4"ü silip "1" bırakır: imleç 1. rakamın sonunda kalır.
      final v = type('14:30', '1:30', caret: 1);
      expect(v.text, '13:0');
      expect(v.selection.baseOffset, 1);
    });
  });

  group('bildirim tercihleri (email_suppressed)', () {
    test('etkin değer: bastırılmışken email_announcements ASLA açık değil; alan yoksa (eski sunucu) bastırma yok', () {
      final suppressed = NotificationPrefs.fromJson(<String, dynamic>{
        'email_announcements': false,
        'push_announcements': true,
        'push_available': false,
        'email_suppressed': true,
      });
      expect(suppressed.emailAnnouncements, isFalse);
      expect(suppressed.emailSuppressed, isTrue);
      // Savunmacı: sunucu çelişkili dönse bile bastırılmış adres "açık" gösterilmez.
      final contradictory = NotificationPrefs.fromJson(<String, dynamic>{
        'email_announcements': true,
        'email_suppressed': true,
      });
      expect(contradictory.emailAnnouncements, isFalse);
      final normal = NotificationPrefs.fromJson(<String, dynamic>{
        'email_announcements': true,
        'email_suppressed': false,
      });
      expect(normal.emailAnnouncements, isTrue);
      expect(normal.emailSuppressed, isFalse);
      final legacy = NotificationPrefs.fromJson(<String, dynamic>{'email_announcements': true});
      expect(legacy.emailAnnouncements, isTrue);
      expect(legacy.emailSuppressed, isFalse);
      final off = NotificationPrefs.fromJson(<String, dynamic>{'email_announcements': false});
      expect(off.emailAnnouncements, isFalse);
      expect(off.emailSuppressed, isFalse);
    });

    test('copyWith: açarken bastırma bayrağı ayrıca kaldırılabilir', () {
      const prefs = NotificationPrefs(emailAnnouncements: false, emailSuppressed: true);
      expect(prefs.copyWith(emailAnnouncements: true).emailSuppressed, isTrue);
      final opened = prefs.copyWith(emailAnnouncements: true, emailSuppressed: false);
      expect(opened.emailAnnouncements, isTrue);
      expect(opened.emailSuppressed, isFalse);
    });
  });

  group('modül kartı: Duyuru ve Bildirim', () {
    test('sunucu kataloğunda status: available -> "Her sitede açık", simgesi duyuru, varsayılan olarak açık', () {
      final module = PlatformModule.fromJson(<String, dynamic>{
        'code': 'announcements',
        'name': 'Duyuru ve Bildirim',
        'description': 'Sakinlere duyuru ve bildirim gönderme.',
        'core': true,
        'status': 'available',
      });
      expect(module.isAvailable, isTrue);
      expect(module.enabled, isTrue, reason: 'çekirdek + available: her sitede hep açık');
      expect(module.toggleable, isFalse);
      final status = moduleStatusOf(module);
      expect(status.label, 'Her sitede açık');
      expect(status.icon, Icons.verified_rounded);
      expect(moduleIconOf(PlatformModuleCodes.announcements), Icons.campaign_rounded);
      expect(
        PlatformModule.defaultEnabled('announcements', core: true, status: 'available'),
        isTrue,
      );
    });

    test('eski sunucu (coming_soon) yanıtı da güvenle okunur: kart yine "Her sitede açık", modül kapalı sayılır', () {
      final legacy = PlatformModule.fromJson(<String, dynamic>{
        'code': 'announcements',
        'name': 'Duyuru ve Bildirim',
        'core': true,
        'status': 'coming_soon',
      });
      expect(legacy.isAvailable, isFalse);
      expect(legacy.enabled, isFalse);
      expect(moduleStatusOf(legacy).label, 'Her sitede açık');
    });
  });

  group('denetim kaydı ve hata mesajları', () {
    test('duyuru eylemlerinin Türkçe etiketi; hedef "Duyuru #n"', () {
      expect(announcementActionLabel('announcement.published'), 'Duyuru yayınlandı');
      expect(announcementActionLabel('announcement.deleted'), 'Duyuru silindi');
      expect(announcementActionLabel('baska'), isNull);
      final entry = AuditLogEntry.fromJson(<String, dynamic>{
        'id': 5,
        'action': 'announcement.scheduled',
        'target_type': 'announcement',
        'target_id': '41',
        'details': <String, dynamic>{'publish_at': '2026-10-20T10:00:00Z'},
      });
      expect(entry.actionLabel, 'Duyuru zamanlandı');
      expect(entry.targetLabel, 'Duyuru #41');
      expect(AuditLogEntry.fromJson(<String, dynamic>{'id': 6, 'action': 'announcement.xyz'}).actionLabel, 'Diğer işlem');
    });

    test('hata kodları Türkçe, kısa ve teknik ifade içermez', () {
      for (final code in <String>[
        'ANNOUNCEMENT_NOT_FOUND',
        'INVALID_STATE',
        'NO_RECIPIENTS',
        'INVALID_TARGET',
        'INVALID_SCHEDULE',
        'ANNOUNCEMENT_EMAIL_LIMIT',
      ]) {
        final message = AuthApi.messageForErrorCode(code);
        expect(message, isNotNull, reason: code);
        expect(message!.length, lessThan(140), reason: code);
        expect(message.contains('_'), isFalse, reason: code);
        expect(AuthApi.sanitizeServerMessage(message), message, reason: '$code: jargon sanılmamalı');
      }
      expect(AuthApi.messageForErrorCode('INVALID_BODY'), isNull, reason: 'sunucunun etiketli metni kullanılır');
    });
  });
}
