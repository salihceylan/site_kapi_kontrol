// Platform: site başvurusu (site yöneticisi olma) modelleri (docs/PLATFORM_SITE_BASVURUSU.md).
//
// Sunucu gövdesinin ayrıştırılması (savunmacı: eksik sayaçlar listelerden türer, bilinmeyen alanlar yok
// sayılır), `mine` yanıtında "başvuru yok" yanılgısına karşı koruma, onay yanıtı (`device_attached`) ve
// denetim kaydı etiketleri.
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/audit_log.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/views/audit_log_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/audit_log_card.dart';

Map<String, dynamic> _row({
  int id = 7,
  String status = 'pending',
  Map<String, dynamic> extra = const <String, dynamic>{},
}) => <String, dynamic>{
  'id': id,
  'status': status,
  'site_name': 'Gül Sitesi',
  'city': 'İstanbul',
  'district': 'Kadıköy',
  'address': 'Moda Cad. No 5',
  'management_type': 'apartment_site',
  'management_type_label': 'Apartman ve Site',
  'block_count': 2,
  'apartment_count': 30,
  'door_count': 2,
  'blocks': <Map<String, dynamic>>[
    <String, dynamic>{'name': 'A Blok', 'apartment_count': 10},
    <String, dynamic>{'name': 'B Blok', 'apartment_count': 20},
  ],
  'doors': <Map<String, dynamic>>[
    <String, dynamic>{'name': 'Ana Giriş'},
    <String, dynamic>{'name': 'Otopark'},
  ],
  'device_uid': 'ESP32_C3_ABC',
  'note': 'Acil kurulum',
  'plan_code': 'manual_approval',
  'payment_status': 'not_required',
  'decision_note': null,
  'decided_at': null,
  'site_code': null,
  'created_at': '2026-10-16T11:30:00.000Z',
  ...extra,
};

void main() {
  group('SiteApplication.fromJson', () {
    test('tam gövde ayrışır; alanlar ve etiketler doğru', () {
      final a = SiteApplication.fromJson(_row());
      expect(a.id, 7);
      expect(a.isPending, isTrue);
      expect(a.statusLabel, 'Bekliyor');
      expect(a.siteName, 'Gül Sitesi');
      expect(a.locationLabel, 'İstanbul / Kadıköy');
      expect(a.structureLabel, '2 blok • 30 daire • 2 kapı');
      expect(a.blocks.map((b) => '${b.name}:${b.apartmentCount}'), <String>['A Blok:10', 'B Blok:20']);
      expect(a.doors.map((d) => d.name), <String>['Ana Giriş', 'Otopark']);
      expect(a.deviceUid, 'ESP32_C3_ABC');
      expect(a.hasDevice, isTrue);
      expect(a.note, 'Acil kurulum');
      expect(a.managementTypeLabel, 'Apartman ve Site');
      expect(a.createdAt, DateTime.utc(2026, 10, 16, 11, 30));
      // Başvurana verilmeyen süper kullanıcı alanları yoktur.
      expect(a.applicant, isNull);
      expect(a.deviceAvailable, isNull);
      expect(a.decisionSource, isNull);
    });

    test('süper kullanıcı alanları: başvuran, karar veren, cihaz uygunluğu', () {
      final a = SiteApplication.fromJson(
        _row(
          status: 'approved',
          extra: <String, dynamic>{
            'applicant': <String, dynamic>{
              'user_code': 41,
              'full_name': 'Ayşe Yılmaz',
              'email': 'ayse@example.com',
              'phone': '+905551112233',
              'role': 'individual',
            },
            'decision_source': 'super_user',
            'decided_by_name': 'Süper Yönetici',
            'decided_at': '2026-10-16T12:00:00Z',
            'site_code': 1234567890,
            'device_available': false,
          },
        ),
      );
      expect(a.isApproved, isTrue);
      expect(a.statusLabel, 'Onaylandı');
      expect(a.applicant!.userCode, 41);
      expect(a.applicant!.displayName, 'Ayşe Yılmaz');
      expect(a.applicant!.email, 'ayse@example.com');
      expect(a.applicant!.phone, '+905551112233');
      expect(a.decidedByName, 'Süper Yönetici');
      expect(a.decisionSource, 'super_user');
      expect(a.siteCode, 1234567890);
      expect(a.deviceAvailable, isFalse);
    });

    test('eksik / tanınmayan durum BEKLEYEN sayılmaz: "Durum bilinmiyor", eylem sunulmaz', () {
      final missing = SiteApplication.fromJson(<String, dynamic>{'id': 3, 'site_name': 'X'});
      expect(missing.status, SiteApplicationStatus.unknown);
      expect(missing.isPending, isFalse);
      expect(missing.hasKnownStatus, isFalse);
      expect(missing.statusLabel, 'Durum bilinmiyor');
      expect(const SiteApplication(id: 1).isPending, isFalse, reason: 'yapıcı varsayılanı da bekleyen değil');
      // Eksik durumlu kayıt `mine` içinde bekleyen sayılıp "iptal et" sunmaz.
      final mine = MySiteApplications.fromJson(<String, dynamic>{
        'pending': null,
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'id': 3, 'site_name': 'X'},
        ],
      });
      expect(mine.pending, isNull);
      expect(mine.latest!.hasKnownStatus, isFalse);
    });

    test('eksik sayaçlar listelerden türetilir; boş ad "Adsız site"; bilinmeyen alan yok sayılır', () {
      final a = SiteApplication.fromJson(<String, dynamic>{
        'id': '9',
        'site_name': '   ',
        'blocks': <Map<String, dynamic>>[
          <String, dynamic>{'name': 'A Blok', 'apartmentCount': 12},
          <String, dynamic>{'name': 'B Blok', 'apartment_count': 8},
        ],
        'doors': <Map<String, dynamic>>[<String, dynamic>{'name': 'K1'}],
        'yeni_alan': 123,
      });
      expect(a.id, 9);
      expect(a.status, SiteApplicationStatus.unknown);
      expect(a.siteNameLabel, 'Adsız site');
      expect(a.blockCount, 2);
      expect(a.apartmentCount, 20, reason: 'camelCase ve snake_case daire sayısı okunur');
      expect(a.doorCount, 1);
      expect(a.locationLabel, isNull);
      expect(a.deviceUid, isNull);
      expect(a.createdAt, isNull);
    });

    test('bilinmeyen durum ham kodla DEĞİL "Durum bilinmiyor" olarak görünür (kayıt kaybolmaz)', () {
      final a = SiteApplication.fromJson(_row(status: 'on_hold'));
      expect(a.statusLabel, 'Durum bilinmiyor');
      expect(a.statusLabel.contains('on_hold'), isFalse);
      expect(a.isPending, isFalse);
      expect(
        SiteApplication.fromJson(_row(status: 'rejected')).statusLabel,
        'Reddedildi',
      );
      expect(
        SiteApplication.fromJson(_row(status: 'cancelled')).statusLabel,
        'İptal edildi',
      );
    });

    test('bozuk liste öğeleri atlanır, çökmez', () {
      final a = SiteApplication.fromJson(<String, dynamic>{
        'id': 1,
        'blocks': <Object?>['x', null, <String, dynamic>{'name': 'A', 'apartment_count': 3}],
        'doors': 'yok',
        'applicant': 'bozuk',
      });
      expect(a.blocks, hasLength(1));
      expect(a.doors, isEmpty);
      expect(a.applicant, isNull);
    });
  });

  group('MySiteApplications', () {
    test('bekleyen yoksa son başvuru "latest"tir', () {
      final mine = MySiteApplications.fromJson(<String, dynamic>{
        'pending': null,
        'items': <Map<String, dynamic>>[_row(id: 3, status: 'rejected'), _row(id: 2, status: 'cancelled')],
      });
      expect(mine.pending, isNull);
      expect(mine.latest!.id, 3);
      expect(mine.items, hasLength(2));
    });

    test('pending alanı boş gelse de listede bekleyen varsa "başvuru yok" denmez', () {
      final mine = MySiteApplications.fromJson(<String, dynamic>{
        'pending': null,
        'items': <Map<String, dynamic>>[_row(id: 5), _row(id: 4, status: 'rejected')],
      });
      expect(mine.pending, isNotNull);
      expect(mine.pending!.id, 5);
      expect(mine.latest!.isPending, isTrue);
    });

    test('hiç başvuru yok: latest null (yalnız pending:null + items:[] meşru boş); alan yoksa hata', () {
      final mine = MySiteApplications.fromJson(<String, dynamic>{'pending': null, 'items': <Object>[]});
      expect(mine.latest, isNull);
      expect(mine.requiresApplication, isNull);
      expect(() => MySiteApplications.fromJson(const <String, dynamic>{}), throwsFormatException);
      expect(() => SiteApplicationPage.fromJson(const <String, dynamic>{}), throwsFormatException);
      // Biri varsa yanıt anlaşılır.
      expect(MySiteApplications.fromJson(<String, dynamic>{'items': <Object>[]}).latest, isNull);
    });

    test('requires_application: true / false okunur; bool değilse null', () {
      expect(
        MySiteApplications.fromJson(<String, dynamic>{'pending': null, 'items': <Object>[], 'requires_application': true})
            .requiresApplication,
        isTrue,
      );
      expect(
        MySiteApplications.fromJson(<String, dynamic>{'pending': null, 'items': <Object>[], 'requires_application': false})
            .requiresApplication,
        isFalse,
      );
      expect(
        MySiteApplications.fromJson(<String, dynamic>{'pending': null, 'items': <Object>[], 'requires_application': 'evet'})
            .requiresApplication,
        isNull,
      );
    });
  });

  group('SiteApplicationPage / SiteApplicationDecision', () {
    test('sayfa: total yoksa öğe sayısı', () {
      final page = SiteApplicationPage.fromJson(<String, dynamic>{
        'items': <Map<String, dynamic>>[_row(id: 2), _row(id: 1)],
        'total': 41,
      });
      expect(page.items, hasLength(2));
      expect(page.total, 41);
      expect(
        SiteApplicationPage.fromJson(<String, dynamic>{
          'items': <Map<String, dynamic>>[_row()],
        }).total,
        1,
      );
    });

    test('onay yanıtı: site ve cihaz bağlandı bilgisi (üst düzey ya da site içinde)', () {
      final a = SiteApplicationDecision.fromJson(<String, dynamic>{
        'application': _row(status: 'approved', extra: <String, dynamic>{'site_code': 77}),
        'site': <String, dynamic>{'site_code': 77, 'name': 'Gül Sitesi'},
        'device_attached': false,
      });
      expect(a.application.isApproved, isTrue);
      expect(a.siteCode, 77);
      expect(a.siteName, 'Gül Sitesi');
      expect(a.deviceAttached, isFalse);

      final b = SiteApplicationDecision.fromJson(<String, dynamic>{
        'application': _row(status: 'approved'),
        'site': <String, dynamic>{'id': 78, 'device_attached': true},
      });
      expect(b.siteCode, 78);
      expect(b.deviceAttached, isTrue);

      final c = SiteApplicationDecision.fromJson(<String, dynamic>{'application': _row(status: 'approved')});
      expect(c.deviceAttached, isNull, reason: 'alan yoksa bilinmiyor');
    });
  });

  group('Denetim kaydı etiketleri', () {
    test('site_application.* ve platform_settings.updated Türkçe etiket alır; ham kod görünmez', () {
      expect(siteApplicationActionLabel('site_application.created'), 'Site başvurusu yapıldı');
      expect(siteApplicationActionLabel('site_application.cancelled'), 'Site başvurusu iptal edildi');
      expect(siteApplicationActionLabel('site_application.approved'), 'Site başvurusu onaylandı');
      expect(siteApplicationActionLabel('site_application.rejected'), 'Site başvurusu reddedildi');
      expect(siteApplicationActionLabel('platform_settings.updated'), 'Platform ayarı güncellendi');
      expect(siteApplicationActionLabel('site_application.xyz'), isNull);
      expect(
        AuditLogEntry.fromJson(<String, dynamic>{'id': 1, 'action': 'site_application.approved'}).actionLabel,
        'Site başvurusu onaylandı',
      );
      expect(
        AuditLogEntry.fromJson(<String, dynamic>{'id': 2, 'action': 'site_application.xyz'}).actionLabel,
        'Diğer işlem',
      );
    });

    test('denetim ekranı süzgeçleri: 5 yeni eylem, etiketleri kayıt etiketiyle aynı', () {
      const actions = <String>[
        'site_application.created',
        'site_application.approved',
        'site_application.rejected',
        'site_application.cancelled',
        'platform_settings.updated',
      ];
      for (final action in actions) {
        final filter = AuditLogView.actionFilters.where((f) => f.$1 == action).toList();
        expect(filter, hasLength(1), reason: action);
        expect(filter.single.$2, siteApplicationActionLabel(action), reason: action);
      }
      // Eylem süzgeci değerleri yinelenmez.
      final values = AuditLogView.actionFilters.map((f) => f.$1).toList();
      expect(values.toSet().length, values.length);
    });

    test('denetim kartı tonu: onay success, red danger, iptal nötr, oluşturma / ayar info', () {
      expect(auditToneOf('site_application.approved'), AppTone.success);
      expect(auditToneOf('site_application.rejected'), AppTone.danger);
      expect(auditToneOf('site_application.cancelled'), AppTone.neutral);
      expect(auditToneOf('site_application.created'), AppTone.info);
      expect(auditToneOf('platform_settings.updated'), AppTone.info);
    });

    test('platform_setting (tekil, sunucunun yazdığı) ve platform_settings (çoğul) aynı etiketi verir', () {
      for (final type in const ['platform_setting', 'platform_settings']) {
        final entry = AuditLogEntry.fromJson(<String, dynamic>{
          'id': 9,
          'action': 'platform_settings.updated',
          'target_type': type,
          'target_id': 'site_onboarding',
        });
        expect(entry.targetLabel, 'Site açılış modu', reason: type);
        expect(entry.targetLabel!.contains('site_onboarding'), isFalse, reason: 'ham anahtar görünmez');
        final other = AuditLogEntry.fromJson(<String, dynamic>{
          'id': 10,
          'action': 'platform_settings.updated',
          'target_type': type,
          'target_id': 'baska_ayar',
        });
        expect(other.targetLabel, 'Platform ayarı', reason: type);
      }
    });

    test('hedef etiketi: başvuru numarası; ayar anahtarı ham gösterilmez', () {
      final app = AuditLogEntry.fromJson(<String, dynamic>{
        'id': 1,
        'action': 'site_application.created',
        'target_type': 'site_application',
        'target_id': '14',
      });
      expect(app.targetLabel, 'Başvuru #14');
      final setting = AuditLogEntry.fromJson(<String, dynamic>{
        'id': 2,
        'action': 'platform_settings.updated',
        'target_type': 'platform_settings',
        'target_id': 'site_onboarding',
      });
      expect(setting.targetLabel, 'Site açılış modu');
      final other = AuditLogEntry.fromJson(<String, dynamic>{
        'id': 3,
        'action': 'platform_settings.updated',
        'target_type': 'platform_settings',
        'target_id': 'baska_ayar',
      });
      expect(other.targetLabel, 'Platform ayarı');
      expect(app.targetLabel!.contains('_'), isFalse);
    });
  });
}
