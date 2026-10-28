// Platform modül sistemi Faz 1: model ayrıştırma testleri (docs/PLATFORM_MODUL_SISTEMI.md).
//
// Odak: sunucu alanı yoksa/bozuksa güvenli varsayılanlar (geriye dönük uyum): yönetim türü yoksa
// apartment_site, modül satırı yoksa katalog varsayılanı (yalnız door_control açık), bozuk tarih null.
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/audit_log.dart';
import 'package:site_kapi_kontrol/models/management_type.dart';
import 'package:site_kapi_kontrol/models/module_request.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/staff_role_record.dart';

void main() {
  group('ManagementType', () {
    test('5 değer, Türkçe etiketler ve api değerleri sözleşmeyle aynı', () {
      expect(ManagementType.values.map((t) => t.apiValue), <String>[
        'apartment_site',
        'residence',
        'business_center',
        'cooperative',
        'shopping_mall',
      ]);
      expect(ManagementType.values.map((t) => t.label), <String>[
        'Apartman ve Site',
        'Rezidans',
        'İş Merkezi',
        'Kooperatif',
        'Alışveriş Merkezi',
      ]);
    });

    test('beş yönetim türünün hepsi seçilebilir', () {
      for (final type in ManagementType.values) {
        expect(type.selectable, isTrue, reason: type.apiValue);
      }
    });

    test('fromApi: yok / boş / bilinmeyen / geçersiz tür apartment_site olur', () {
      expect(ManagementType.fromApi(null), ManagementType.apartmentSite);
      expect(ManagementType.fromApi(''), ManagementType.apartmentSite);
      expect(ManagementType.fromApi('uzay_istasyonu'), ManagementType.apartmentSite);
      expect(ManagementType.fromApi(42), ManagementType.apartmentSite);
      expect(ManagementType.fromApi('shopping_mall'), ManagementType.shoppingMall);
      expect(ManagementType.fromApi(' residence '), ManagementType.residence);
    });
  });

  group('SiteRecord yönetim türü', () {
    Map<String, dynamic> base() => <String, dynamic>{
      'id': 5,
      'name': 'Gül Sitesi',
      'approval_status': 'approved',
    };

    test('alan yoksa apartment_site ve "Apartman ve Site" etiketi', () {
      final site = SiteRecord.fromJson(base());
      expect(site.managementType, ManagementType.apartmentSite);
      expect(site.managementTypeLabel, 'Apartman ve Site');
    });

    test('sunucu türü ve etiketi gelirse kullanılır; etiket yoksa türün etiketi', () {
      final withLabel = SiteRecord.fromJson(<String, dynamic>{
        ...base(),
        'management_type': 'residence',
        'management_type_label': 'Rezidans',
      });
      expect(withLabel.managementType, ManagementType.residence);
      expect(withLabel.managementTypeLabel, 'Rezidans');

      final noLabel = SiteRecord.fromJson(<String, dynamic>{
        ...base(),
        'management_type': 'cooperative',
      });
      expect(noLabel.managementTypeLabel, 'Kooperatif');

      final blankLabel = SiteRecord.fromJson(<String, dynamic>{
        ...base(),
        'management_type': 'business_center',
        'management_type_label': '   ',
      });
      expect(blankLabel.managementTypeLabel, 'İş Merkezi');
    });

    test('const kurucu ve copyWith türü korur / değiştirir', () {
      final site = SiteRecord.fromJson(base());
      expect(site.copyWith(name: 'Yeni').managementType, ManagementType.apartmentSite);
      final changed = site.copyWith(
        managementType: ManagementType.residence,
        managementTypeLabel: 'Rezidans',
      );
      expect(changed.managementType, ManagementType.residence);
      expect(changed.managementTypeLabel, 'Rezidans');
    });
  });

  group('PlatformModule', () {
    test('katalog satırı: enabled/toggleable alanları yoksa sunucudaki hesapla aynı varsayılan', () {
      final door = PlatformModule.fromJson(<String, dynamic>{
        'code': 'door_control',
        'name': 'Geçiş Kontrol (SmartKeyPass)',
        'description': 'Kapı açma',
        'core': false,
        'status': 'available',
      });
      expect(door.enabled, isTrue, reason: 'door_control varsayılanı AÇIK');
      expect(door.toggleable, isTrue);
      expect(door.isAvailable, isTrue);

      final people = PlatformModule.fromJson(<String, dynamic>{
        'code': 'people',
        'name': 'Kişi ve Daire Kayıtları',
        'core': true,
        'status': 'coming_soon',
      });
      expect(people.enabled, isFalse,
          reason: 'coming_soon -> hesaplanmış enabled false (sunucu formülü); '
              '"Her sitede açık" çipi core alanından gelir');
      expect(people.core, isTrue);
      expect(people.toggleable, isFalse);
      expect(people.isComingSoon, isTrue);

      final finance = PlatformModule.fromJson(<String, dynamic>{
        'code': 'finance',
        'name': 'Aidat ve Finans',
        'core': false,
        'status': 'coming_soon',
      });
      expect(finance.enabled, isFalse);
      expect(finance.toggleable, isFalse);
    });

    test('site durumu satırı: enabled, toggleable, updated_at, updated_by okunur', () {
      final m = PlatformModule.fromJson(<String, dynamic>{
        'code': 'door_control',
        'name': 'Geçiş Kontrol (SmartKeyPass)',
        'description': '…',
        'core': false,
        'status': 'available',
        'enabled': false,
        'toggleable': true,
        'updated_at': '2026-10-15T09:30:00Z',
        'updated_by': 'Ayşe Yılmaz',
      });
      expect(m.enabled, isFalse);
      expect(m.updatedBy, 'Ayşe Yılmaz');
      expect(m.updatedAt!.toUtc(), DateTime.utc(2026, 10, 15, 9, 30));
      expect(m.copyWith(enabled: true).enabled, isTrue);
    });

    test('bozuk tarih null olur, eksik ad koda düşer', () {
      final m = PlatformModule.fromJson(<String, dynamic>{
        'code': 'metering',
        'updated_at': 'dün',
      });
      expect(m.updatedAt, isNull);
      expect(m.name, 'metering');
      expect(m.description, '');
    });

    test('defaultEnabled: yalnız door_control ve çekirdek modüller açık', () {
      expect(PlatformModule.defaultEnabled('door_control'), isTrue);
      expect(PlatformModule.defaultEnabled('finance'), isFalse);
      expect(PlatformModule.defaultEnabled('people', core: true), isTrue);
      expect(
        PlatformModule.defaultEnabled('people', core: true, status: 'coming_soon'),
        isFalse,
      );
      expect(
        PlatformModule.defaultEnabled('door_control', status: 'coming_soon'),
        isFalse,
      );
    });
  });

  group('SiteModulesState', () {
    test('tam gövde: tür etiketi, modüller ve module(code) araması', () {
      final state = SiteModulesState.fromJson(<String, dynamic>{
        'site_code': 1234567890,
        'site_name': 'Gül Sitesi',
        'management_type': 'apartment_site',
        'management_type_label': 'Apartman ve Site',
        'modules': <Map<String, dynamic>>[
          <String, dynamic>{
            'code': 'door_control',
            'name': 'Geçiş Kontrol (SmartKeyPass)',
            'core': false,
            'status': 'available',
            'enabled': true,
            'toggleable': true,
          },
          <String, dynamic>{
            'code': 'finance',
            'name': 'Aidat ve Finans',
            'core': false,
            'status': 'coming_soon',
            'enabled': false,
            'toggleable': false,
          },
        ],
      });
      expect(state.siteCode, 1234567890);
      expect(state.siteName, 'Gül Sitesi');
      expect(state.managementType, ManagementType.apartmentSite);
      expect(state.modules, hasLength(2));
      expect(state.module('finance')!.isComingSoon, isTrue);
      expect(state.module('yok'), isNull);
    });

    test('tür alanı yoksa apartment_site; modules yoksa boş liste', () {
      final state = SiteModulesState.fromJson(<String, dynamic>{
        'site_code': '77',
        'site_name': 'X',
      });
      expect(state.siteCode, 77);
      expect(state.managementType, ManagementType.apartmentSite);
      expect(state.managementTypeLabel, 'Apartman ve Site');
      expect(state.modules, isEmpty);
    });
  });

  group('MyModulesResult', () {
    test('scope: all (süper kullanıcı) -> isAll, site yok', () {
      final r = MyModulesResult.fromJson(<String, dynamic>{
        'scope': 'all',
        'sites': <dynamic>[],
      });
      expect(r.isAll, isTrue);
      expect(r.sites, isEmpty);
    });

    test('siteler: rol, tür ve modül haritası; eksik kod katalog varsayılanına düşer', () {
      final r = MyModulesResult.fromJson(<String, dynamic>{
        'scope': 'sites',
        'sites': <Map<String, dynamic>>[
          <String, dynamic>{
            'site_code': 1234567890,
            'site_name': 'Gül Sitesi',
            'management_type': 'apartment_site',
            'role': 'manager',
            'modules': <String, dynamic>{'door_control': false, 'finance': false},
          },
          <String, dynamic>{
            'site_code': 99,
            'site_name': 'Eski Sunucu Sitesi',
            // management_type, role ve modules yok
          },
        ],
      });
      expect(r.isAll, isFalse);
      expect(r.sites, hasLength(2));
      final first = r.sites.first;
      expect(first.role, 'manager');
      expect(first.isEnabled('door_control'), isFalse);
      expect(first.isEnabled('people'), isFalse,
          reason: 'listede olmayan kod: katalog varsayılanı (çekirdek bilgisi yoksa kapalı)');
      final legacy = r.sites.last;
      expect(legacy.managementType, ManagementType.apartmentSite);
      expect(legacy.role, 'resident');
      expect(legacy.isEnabled('door_control'), isTrue,
          reason: 'modül bilgisi yoksa door_control varsayılanı açık');
    });

    test('eşitlik: aynı içerik eşit, farklı modül durumu farklı', () {
      Map<String, dynamic> json(bool door) => <String, dynamic>{
        'scope': 'sites',
        'sites': <Map<String, dynamic>>[
          <String, dynamic>{
            'site_code': 1,
            'site_name': 'A',
            'role': 'resident',
            'modules': <String, dynamic>{'door_control': door},
          },
        ],
      };
      expect(MyModulesResult.fromJson(json(true)), MyModulesResult.fromJson(json(true)));
      expect(MyModulesResult.fromJson(json(true)).hashCode,
          MyModulesResult.fromJson(json(true)).hashCode);
      expect(
        MyModulesResult.fromJson(json(true)) == MyModulesResult.fromJson(json(false)),
        isFalse,
      );
    });
  });

  group('PlatformModule: can_toggle ve request_status (Faz 1.1)', () {
    Map<String, dynamic> base() => <String, dynamic>{
      'code': 'finance',
      'name': 'Aidat ve Finans',
      'core': false,
      'status': 'available',
      'enabled': false,
      'toggleable': true,
    };

    test('can_toggle verilirse kullanılır (yönetici: false, süper kullanıcı: true)', () {
      expect(PlatformModule.fromJson(<String, dynamic>{...base(), 'can_toggle': false}).canToggle, isFalse);
      expect(PlatformModule.fromJson(<String, dynamic>{...base(), 'can_toggle': true}).canToggle, isTrue);
      // toggleable katalog özelliği olarak kalır.
      expect(PlatformModule.fromJson(<String, dynamic>{...base(), 'can_toggle': false}).toggleable, isTrue);
    });

    test('can_toggle yoksa (eski sunucu) toggleable kullanılır', () {
      expect(PlatformModule.fromJson(base()).canToggle, isTrue);
      expect(
        PlatformModule.fromJson(<String, dynamic>{...base(), 'toggleable': false}).canToggle,
        isFalse,
      );
      // Katalog satırı: toggleable de yoksa çekirdek / yakında olmayan modül için hesaplanır.
      expect(
        PlatformModule.fromJson(<String, dynamic>{'code': 'door_control', 'status': 'available'}).canToggle,
        isTrue,
      );
      expect(
        PlatformModule.fromJson(<String, dynamic>{'code': 'people', 'core': true, 'status': 'coming_soon'})
            .canToggle,
        isFalse,
      );
      // Doğrudan kurucu: canToggle verilmezse toggleable.
      expect(const PlatformModule(code: 'x', name: 'X', toggleable: true).canToggle, isTrue);
    });

    test('request_status: pending ya da null; boş/yok -> null; hasPendingRequest', () {
      final pending = PlatformModule.fromJson(<String, dynamic>{...base(), 'request_status': 'pending'});
      expect(pending.requestStatus, 'pending');
      expect(pending.hasPendingRequest, isTrue);
      expect(PlatformModule.fromJson(<String, dynamic>{...base(), 'request_status': null}).requestStatus, isNull);
      expect(PlatformModule.fromJson(<String, dynamic>{...base(), 'request_status': ' '}).requestStatus, isNull);
      expect(PlatformModule.fromJson(base()).requestStatus, isNull);
      expect(PlatformModule.fromJson(base()).hasPendingRequest, isFalse);
    });

    test('copyWith talep durumunu ve canToggle değerini korur / temizler; eşitlik alanları ayırt eder', () {
      final m = PlatformModule.fromJson(<String, dynamic>{
        ...base(),
        'can_toggle': false,
        'request_status': 'pending',
      });
      expect(m.copyWith(enabled: true).canToggle, isFalse);
      expect(m.copyWith(enabled: true).requestStatus, 'pending');
      expect(m.copyWith(clearRequestStatus: true).requestStatus, isNull);
      expect(m == m.copyWith(), isTrue);
      expect(m == m.copyWith(clearRequestStatus: true), isFalse);
      expect(
        m == PlatformModule.fromJson(<String, dynamic>{...base(), 'can_toggle': true, 'request_status': 'pending'}),
        isFalse,
      );
    });

    test('SiteModulesState site yöneticisi gövdesi: hiçbir modül can_toggle değil, bekleyen talep işaretli', () {
      final state = SiteModulesState.fromJson(<String, dynamic>{
        'site_code': 11,
        'site_name': 'Gül Sitesi',
        'modules': <Map<String, dynamic>>[
          <String, dynamic>{...base(), 'code': 'door_control', 'enabled': true, 'can_toggle': false},
          <String, dynamic>{...base(), 'can_toggle': false, 'request_status': 'pending'},
        ],
      });
      expect(state.modules.every((m) => !m.canToggle), isTrue);
      expect(state.module('finance')!.hasPendingRequest, isTrue);
      expect(state.module('door_control')!.hasPendingRequest, isFalse);
    });
  });

  group('ModuleRequest / ModuleRequestPage', () {
    Map<String, dynamic> row({String status = 'pending'}) => <String, dynamic>{
      'id': 31,
      'site_code': 1234567890,
      'site_name': 'Gül Sitesi',
      'module_code': 'finance',
      'module_name': 'Aidat ve Finans',
      'status': status,
      'note': 'Aidat takibi için gerekli',
      'requested_by_name': 'Ayşe Yılmaz',
      'created_at': '2026-10-15T09:30:00Z',
      'decided_by_name': null,
      'decided_at': null,
      'decision_note': null,
    };

    test('sözleşmedeki tüm alanlar okunur', () {
      final r = ModuleRequest.fromJson(row());
      expect(r.id, 31);
      expect(r.siteCode, 1234567890);
      expect(r.siteName, 'Gül Sitesi');
      expect(r.moduleCode, 'finance');
      expect(r.moduleLabel, 'Aidat ve Finans');
      expect(r.status, 'pending');
      expect(r.isPending, isTrue);
      expect(r.note, 'Aidat takibi için gerekli');
      expect(r.requestedByName, 'Ayşe Yılmaz');
      expect(r.createdAt!.toUtc(), DateTime.utc(2026, 10, 15, 9, 30));
      expect(r.decidedByName, isNull);
      expect(r.decidedAt, isNull);
      expect(r.decisionNote, isNull);
    });

    test('durum etiketleri Türkçe; bilinmeyen durum ham değerle görünür', () {
      expect(ModuleRequest.fromJson(row(status: 'pending')).statusLabel, 'Bekliyor');
      expect(ModuleRequest.fromJson(row(status: 'approved')).statusLabel, 'Onaylandı');
      expect(ModuleRequest.fromJson(row(status: 'rejected')).statusLabel, 'Reddedildi');
      expect(ModuleRequest.fromJson(row(status: 'cancelled')).statusLabel, 'Geri çekildi');
      expect(ModuleRequest.fromJson(row(status: 'yeni_durum')).statusLabel, 'yeni_durum');
      expect(ModuleRequest.fromJson(row(status: 'approved')).isPending, isFalse);
    });

    test('karar bilgisi, boş metinler null, eksik ad koda düşer, bozuk tarih null', () {
      final r = ModuleRequest.fromJson(<String, dynamic>{
        ...row(status: 'rejected'),
        'module_name': '',
        'note': '  ',
        'decided_by_name': 'Süper Yönetici',
        'decided_at': '2026-10-16T10:05:00Z',
        'decision_note': 'Paket kapsamında değil',
        'created_at': 'dün',
      });
      expect(r.moduleLabel, 'finance');
      expect(r.note, isNull);
      expect(r.decidedByName, 'Süper Yönetici');
      expect(r.decisionNote, 'Paket kapsamında değil');
      expect(r.decidedAt, isNotNull);
      expect(r.createdAt, isNull);
    });

    test('id / site_code metin olarak gelse de okunur; hiç alan yoksa güvenli varsayılan', () {
      final r = ModuleRequest.fromJson(<String, dynamic>{'id': '7', 'site_code': '99'});
      expect(r.id, 7);
      expect(r.siteCode, 99);
      expect(r.status, 'pending');
      expect(r.moduleCode, '');
    });

    test('sayfa: next_before_id ve pending_count (süzgeçten bağımsız toplam)', () {
      final page = ModuleRequestPage.fromJson(<String, dynamic>{
        'items': <Map<String, dynamic>>[row(), <String, dynamic>{...row(), 'id': 30}],
        'next_before_id': 30,
        'pending_count': 4,
      });
      expect(page.items.map((e) => e.id), <int>[31, 30]);
      expect(page.nextBeforeId, 30);
      expect(page.hasMore, isTrue);
      expect(page.pendingCount, 4);

      final last = ModuleRequestPage.fromJson(<String, dynamic>{
        'items': <dynamic>[],
        'next_before_id': null,
        'pending_count': '2',
      });
      expect(last.hasMore, isFalse);
      expect(last.pendingCount, 2);
      expect(const ModuleRequestPage().pendingCount, 0);
      expect(ModuleRequestPage.fromJson(<String, dynamic>{}).items, isEmpty);
    });
  });

  group('door_access (gerçek kapı erişimi) ve "kapalı" kararı', () {
    Map<String, dynamic> site(int code, {required bool door, Object? doorAccess = 'yok'}) =>
        <String, dynamic>{
          'site_code': code,
          'site_name': 'Site $code',
          'role': 'resident',
          'modules': <String, dynamic>{'door_control': door},
          if (doorAccess != 'yok') 'door_access': doorAccess,
        };

    test('alan yoksa (eski sunucu) ya da bool değilse true: fail-open', () {
      expect(MySiteModules.fromJson(site(1, door: false)).doorAccess, isTrue);
      expect(MySiteModules.fromJson(site(1, door: false, doorAccess: 'evet')).doorAccess, isTrue);
      expect(MySiteModules.fromJson(site(1, door: false, doorAccess: true)).doorAccess, isTrue);
      expect(MySiteModules.fromJson(site(1, door: false, doorAccess: false)).doorAccess, isFalse);
      expect(const MySiteModules(siteCode: 1, siteName: 'A').doorAccess, isTrue);
    });

    test('eşitlik door_access farkını ayırt eder', () {
      final a = MySiteModules.fromJson(site(1, door: true, doorAccess: true));
      final b = MySiteModules.fromJson(site(1, door: true, doorAccess: false));
      expect(a == b, isFalse);
      expect(a.hashCode == b.hashCode, isFalse);
    });

    MyModulesResult result(List<Map<String, dynamic>> sites, {String scope = 'sites'}) =>
        MyModulesResult.fromJson(<String, dynamic>{'scope': scope, 'sites': sites});

    test('isDisabledEverywhere(door_control) yalnız door_access=true siteler üzerinden', () {
      // Yalnız kurul/görevli bağı olan sitede kapalı: KAPALI sayılmaz (menü/ekran değişmez).
      expect(
        result([site(1, door: false, doorAccess: false)])
            .isDisabledEverywhere(PlatformModuleCodes.doorControl),
        isFalse,
      );
      // Kapı erişimi olan tek site kapalı: kapalı.
      expect(
        result([site(1, door: false, doorAccess: true)])
            .isDisabledEverywhere(PlatformModuleCodes.doorControl),
        isTrue,
      );
      // Kapı erişimi olan site kapalı, kurul sitesi açık: kapalı (karar yalnız kapı erişimli sitelerden).
      expect(
        result([
          site(1, door: false, doorAccess: true),
          site(2, door: true, doorAccess: false),
        ]).isDisabledEverywhere(PlatformModuleCodes.doorControl),
        isTrue,
      );
      // Kapı erişimi olan site açık, kurul sitesi kapalı: kapalı DEĞİL.
      expect(
        result([
          site(1, door: true, doorAccess: true),
          site(2, door: false, doorAccess: false),
        ]).isDisabledEverywhere(PlatformModuleCodes.doorControl),
        isFalse,
      );
      // Eski sunucu (alan yok) -> hepsi kapı erişimli sayılır.
      expect(
        result([site(1, door: false), site(2, door: false)])
            .isDisabledEverywhere(PlatformModuleCodes.doorControl),
        isTrue,
      );
      // Hiç site ya da süper kullanıcı: kapalı değil.
      expect(result(const []).isDisabledEverywhere(PlatformModuleCodes.doorControl), isFalse);
      expect(
        result(const [], scope: 'all').isDisabledEverywhere(PlatformModuleCodes.doorControl),
        isFalse,
      );
    });

    test('door_control dışındaki modüllerde tüm siteler dikkate alınır', () {
      final r = result([
        <String, dynamic>{
          'site_code': 1,
          'site_name': 'A',
          'modules': <String, dynamic>{'finance': false},
          'door_access': false,
        },
      ]);
      expect(r.isDisabledEverywhere(PlatformModuleCodes.finance), isTrue);
      expect(r.doorAccessSites, isEmpty);
    });
  });

  group('AuditLogEntry / AuditLogPage', () {
    Map<String, dynamic> row(
      int id,
      String action, {
      String? targetType = 'module',
      String? targetId = 'door_control',
      Map<String, dynamic>? details,
    }) => <String, dynamic>{
      'id': id,
      'created_at': '2026-10-15T09:30:00Z',
      'actor_user_code': 1,
      'actor_name': 'Süper Yönetici',
      'actor_role': 'super_user',
      'action': action,
      'site_code': 1234567890,
      'site_name': 'Gül Sitesi',
      'target_type': targetType,
      'target_id': targetId,
      'details': details ?? <String, dynamic>{'enabled': false},
    };

    test('modül eylemleri: Türkçe başlık ve modül adı', () {
      final off = AuditLogEntry.fromJson(row(7, 'module.disabled'));
      expect(off.actionLabel, 'Modül kapatıldı');
      expect(off.targetLabel, 'Geçiş Kontrol (SmartKeyPass)');
      expect(off.siteName, 'Gül Sitesi');
      expect(off.createdAt!.toUtc(), DateTime.utc(2026, 10, 15, 9, 30));
      expect(AuditLogEntry.fromJson(row(8, 'module.enabled')).actionLabel, 'Modül açıldı');
    });

    test('ek rol eylemleri: kişi ve rol adı', () {
      final assigned = AuditLogEntry.fromJson(
        row(
          9,
          'staff_role.assigned',
          targetType: 'user',
          targetId: '42',
          details: <String, dynamic>{'role': 'BOARD_MEMBER'},
        ),
      );
      expect(assigned.actionLabel, 'Ek rol atandı');
      expect(assigned.targetLabel, 'Kullanıcı 42 • Yönetim Kurulu / Denetçi');
      final removed = AuditLogEntry.fromJson(
        row(
          10,
          'staff_role.removed',
          targetType: 'user',
          targetId: '42',
          details: <String, dynamic>{'role': 'STAFF'},
        ),
      );
      expect(removed.actionLabel, 'Ek rol kaldırıldı');
      expect(removed.targetLabel, 'Kullanıcı 42 • Görevli');
    });

    test('module_request.* eylemleri: Türkçe başlık, modül adı ve talep numarası', () {
      Map<String, dynamic> req(String action) => row(
            1,
            action,
            targetType: 'module_request',
            targetId: '31',
            details: <String, dynamic>{'module_code': 'finance'},
          );
      expect(AuditLogEntry.fromJson(req('module_request.created')).actionLabel, 'Talep oluşturuldu');
      expect(AuditLogEntry.fromJson(req('module_request.approved')).actionLabel, 'Talep onaylandı');
      expect(AuditLogEntry.fromJson(req('module_request.rejected')).actionLabel, 'Talep reddedildi');
      expect(AuditLogEntry.fromJson(req('module_request.cancelled')).actionLabel, 'Talep geri çekildi');
      expect(
        AuditLogEntry.fromJson(req('module_request.created')).targetLabel,
        'Aidat ve Finans • Talep #31',
      );
      // module_code yoksa yalnız talep numarası.
      expect(
        AuditLogEntry.fromJson(row(2, 'module_request.created',
                targetType: 'module_request', targetId: '5', details: <String, dynamic>{}))
            .targetLabel,
        'Talep #5',
      );
      // Kataloktan kalkan eski kod (card_payments, 083'te Aidat ve Finans'a katıldı) ham kodla değil okunur adla görünür.
      expect(
        AuditLogEntry.fromJson(row(3, 'module_request.approved',
                targetType: 'module_request',
                targetId: '8',
                details: <String, dynamic>{'module_code': 'card_payments'}))
            .targetLabel,
        'Kart Ödemesi (Aidat ve Finans) • Talep #8',
      );
    });

    test('bilinmeyen eylem "Diğer işlem" olarak görünür (ham kod gösterilmez, kayıt kaybolmaz); eksik alanlar null', () {
      final e = AuditLogEntry.fromJson(<String, dynamic>{
        'id': '11',
        'action': 'site.archived',
        'created_at': 'bozuk',
        'site_code': null,
        'details': 'metin',
      });
      expect(e.id, 11);
      expect(e.actionLabel, 'Diğer işlem');
      expect(e.action, 'site.archived', reason: 'ham kod modelde durur');
      expect(e.createdAt, isNull);
      expect(e.siteCode, isNull);
      expect(e.details, isEmpty);
      expect(e.targetLabel, isNull);
    });

    test('sayfa: next_before_id varsa hasMore, son sayfada null', () {
      final page = AuditLogPage.fromJson(<String, dynamic>{
        'items': <Map<String, dynamic>>[row(7, 'module.disabled'), row(6, 'module.enabled')],
        'next_before_id': 6,
      });
      expect(page.items.map((e) => e.id), <int>[7, 6]);
      expect(page.nextBeforeId, 6);
      expect(page.hasMore, isTrue);

      final last = AuditLogPage.fromJson(<String, dynamic>{
        'items': <dynamic>[],
        'next_before_id': null,
      });
      expect(last.hasMore, isFalse);
      expect(last.items, isEmpty);
      expect(const AuditLogPage().hasMore, isFalse);
    });
  });

  group('StaffRoleRecord / StaffRoleType', () {
    test('ayrıştırma ve rol etiketleri', () {
      final r = StaffRoleRecord.fromJson(<String, dynamic>{
        'user_code': 42,
        'full_name': 'Selin Aydın',
        'email': 'selin@ornek.com',
        'role': 'BOARD_MEMBER',
        'created_at': '2026-10-15T09:30:00Z',
      });
      expect(r.userCode, 42);
      expect(r.roleType, StaffRoleType.boardMember);
      expect(r.roleLabel, 'Yönetim Kurulu / Denetçi');
      expect(r.createdAt, isNotNull);

      final s = StaffRoleRecord.fromJson(<String, dynamic>{
        'user_code': '43',
        'full_name': 'Kemal',
        'email': 'kemal@ornek.com',
        'role': 'STAFF',
      });
      expect(s.userCode, 43);
      expect(s.roleLabel, 'Görevli');
      expect(s.createdAt, isNull);
    });

    test('bilinmeyen rol ham değerle gösterilir', () {
      final r = StaffRoleRecord.fromJson(<String, dynamic>{
        'user_code': 1,
        'role': 'DENETCI',
      });
      expect(r.roleType, isNull);
      expect(r.roleLabel, 'DENETCI');
      expect(StaffRoleType.tryParse('staff'), StaffRoleType.staff);
      expect(StaffRoleType.tryParse(null), isNull);
    });
  });
}
