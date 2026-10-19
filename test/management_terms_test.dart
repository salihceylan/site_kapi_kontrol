// F9 terim katmanı: ManagementTerms / ManagementTypeInfo ayrıştırma ve varsayılanlar.
//
// Odak (AGENTS.md kural 2, geriye dönük uyum): eski sunucu `management_terms`, `recommended_modules`,
// `recommended` göndermez; o zaman Daire / Sakin / Malik / Aidat / Blok ve "önerilen yok" kullanılır.
// Sunucu tablosu (`server/src/modules/management_type_terms.js`) ile yerleşik tablo aynı olmalıdır.
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/management_terms.dart';
import 'package:site_kapi_kontrol/models/management_type.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';

const Map<String, dynamic> _mallTerms = <String, dynamic>{
  'unit': 'Mağaza',
  'unit_plural': 'Mağazalar',
  'resident': 'Kiracı firma',
  'resident_plural': 'Kiracı firmalar',
  'owner': 'Mal sahibi',
  'fee': 'Ortak gider',
  'block': 'Kat',
  'block_plural': 'Katlar',
};

Map<String, dynamic> _siteJson({Map<String, dynamic>? terms, String type = 'apartment_site'}) =>
    <String, dynamic>{
      'id': 101,
      'name': 'Güneş Sitesi',
      'block_count': 1,
      'apartment_count': 10,
      'door_count': 1,
      'approval_status': 'approved',
      'block_apartment_counts': <int>[10],
      'management_type': type,
      'management_terms': ?terms,
    };

void main() {
  group('ManagementTerms.fromJson', () {
    test('tam nesne: sekiz alan okunur, boşluklar kırpılır', () {
      final t = ManagementTerms.fromJson(<String, dynamic>{
        ..._mallTerms,
        'unit': '  Mağaza ',
      });
      expect(t.unit, 'Mağaza');
      expect(t.unitPlural, 'Mağazalar');
      expect(t.resident, 'Kiracı firma');
      expect(t.residentPlural, 'Kiracı firmalar');
      expect(t.owner, 'Mal sahibi');
      expect(t.fee, 'Ortak gider');
      expect(t.block, 'Kat');
      expect(t.blockPlural, 'Katlar');
      expect(t.isDefault, isFalse);
      expect(t, ManagementTerms.forType(ManagementType.shoppingMall));
    });

    test('alan yok (eski sunucu): null / liste / sayı -> varsayılan Daire / Sakin / Malik / Aidat / Blok', () {
      for (final raw in <Object?>[null, 'x', 5, <String>['unit']]) {
        final t = ManagementTerms.fromJson(raw);
        expect(t, ManagementTerms.defaults, reason: '$raw');
        expect(t.isDefault, isTrue);
      }
      expect(ManagementTerms.defaults.unit, 'Daire');
      expect(ManagementTerms.defaults.unitPlural, 'Daireler');
      expect(ManagementTerms.defaults.resident, 'Sakin');
      expect(ManagementTerms.defaults.residentPlural, 'Sakinler');
      expect(ManagementTerms.defaults.owner, 'Malik');
      expect(ManagementTerms.defaults.fee, 'Aidat');
      expect(ManagementTerms.defaults.block, 'Blok');
      expect(ManagementTerms.defaults.blockPlural, 'Bloklar');
    });

    test('kısmi nesne: eksik / boş / yanlış tipli alan için yalnız o alan varsayılan', () {
      final t = ManagementTerms.fromJson(<String, dynamic>{
        'unit': 'Ofis',
        'unit_plural': '   ',
        'resident': 7,
        'fee': null,
      });
      expect(t.unit, 'Ofis');
      expect(t.unitPlural, 'Daireler');
      expect(t.resident, 'Sakin');
      expect(t.fee, 'Aidat');
      expect(t.block, 'Blok');
      expect(t.isDefault, isFalse);
    });

    test('forType: beş türün yerleşik terimleri sunucu tablosuyla aynı', () {
      expect(ManagementTerms.forType(ManagementType.apartmentSite), ManagementTerms.defaults);
      expect(ManagementTerms.forType(ManagementType.residence), ManagementTerms.defaults);
      final b = ManagementTerms.forType(ManagementType.businessCenter);
      expect(
        <String>[b.unit, b.unitPlural, b.resident, b.residentPlural, b.owner, b.fee, b.block, b.blockPlural],
        <String>['Ofis', 'Ofisler', 'Firma', 'Firmalar', 'Mal sahibi', 'Ortak gider', 'Kat', 'Katlar'],
      );
      final c = ManagementTerms.forType(ManagementType.cooperative);
      expect(
        <String>[c.unit, c.unitPlural, c.resident, c.residentPlural, c.owner, c.fee, c.block, c.blockPlural],
        <String>['Hisse', 'Hisseler', 'Üye', 'Üyeler', 'Üye', 'Üye aidatı', 'Blok', 'Bloklar'],
      );
      final m = ManagementTerms.forType(ManagementType.shoppingMall);
      expect(
        <String>[m.unit, m.unitPlural, m.resident, m.residentPlural, m.owner, m.fee, m.block, m.blockPlural],
        <String>[
          'Mağaza',
          'Mağazalar',
          'Kiracı firma',
          'Kiracı firmalar',
          'Mal sahibi',
          'Ortak gider',
          'Kat',
          'Katlar',
        ],
      );
    });

    test('changeSummary / tooltipText / küçük harf', () {
      expect(ManagementTerms.defaults.changeSummary, '');
      expect(
        ManagementTerms.forType(ManagementType.businessCenter).changeSummary,
        'Daire → Ofis, Sakin → Firma, Malik → Mal sahibi, Aidat → Ortak gider, Blok → Kat',
      );
      expect(
        ManagementTerms.forType(ManagementType.cooperative).changeSummary,
        'Daire → Hisse, Sakin → Üye, Malik → Üye, Aidat → Üye aidatı',
      );
      expect(
        ManagementTerms.forType(ManagementType.shoppingMall).tooltipText,
        'Terimler: Mağaza, Kiracı firma, Mal sahibi, Ortak gider, Kat',
      );
      expect(ManagementTerms.lowerTr('İş Merkezi'), 'iş merkezi');
      expect(ManagementTerms.lowerTr('ISPARTA'), 'ısparta');
      final m = ManagementTerms.fromJson(_mallTerms);
      expect(m.unitLower, 'mağaza');
      expect(m.blockLower, 'kat');
      expect(m.blockPluralLower, 'katlar');
    });
  });

  group('ManagementTypeInfo', () {
    test('builtInAll: beş tür sunucu sırasında; özetler Türkçe ve "Yakında" demez; öneriler sözleşmeyle aynı', () {
      final all = ManagementTypeInfo.builtInAll;
      expect(all.map((i) => i.code), ManagementType.values.map((t) => t.apiValue));
      for (final info in all) {
        expect(info.summary, isNotEmpty, reason: info.code);
        expect(info.summary.toLowerCase(), isNot(contains('yakında')), reason: info.code);
        expect(info.selectable, isTrue);
        expect(info.label, info.type.label);
        expect(info.terms, ManagementTerms.forType(info.type));
      }
      expect(all[0].recommendedModules, <String>['door_control', 'finance', 'documents', 'announcements']);
      expect(all[1].recommendedModules, <String>[
        'reservation',
        'visitor_log',
        'work_tracking',
        'door_control',
        'finance',
      ]);
      expect(all[2].recommendedModules, <String>['work_tracking', 'visitor_log', 'finance', 'documents']);
      expect(all[3].recommendedModules, <String>['finance', 'documents', 'announcements', 'survey']);
      expect(all[4].recommendedModules, <String>['finance', 'work_tracking', 'visitor_log', 'documents']);
    });

    test('recommendedModuleNames: katalogda olmayan kod (survey, visitor_log) atlanır, sıra korunur', () {
      final coop = ManagementTypeInfo.builtIn(ManagementType.cooperative);
      expect(coop.recommendedModuleNames, <String>['Aidat ve Finans', 'Belgeler', 'Duyuru ve Bildirim']);
      final mall = ManagementTypeInfo.builtIn(ManagementType.shoppingMall);
      expect(mall.recommendedModuleNames, <String>['Aidat ve Finans', 'İş Takibi', 'Belgeler']);
    });

    test('fromJson: sunucu öğesi (code, label, selectable, terms, recommended_modules, summary)', () {
      final info = ManagementTypeInfo.fromJson(<String, dynamic>{
        'code': 'shopping_mall',
        'label': 'AVM',
        'selectable': true,
        'terms': _mallTerms,
        'recommended_modules': <Object>['finance', 'survey', 7, 'documents'],
        'summary': 'Alışveriş merkezleri için ortak gider ve iş takibi.',
      });
      expect(info.type, ManagementType.shoppingMall);
      expect(info.label, 'AVM');
      expect(info.terms, ManagementTerms.fromJson(_mallTerms));
      expect(info.recommendedModules, <String>['finance', 'survey', 'documents']);
      expect(info.summary, 'Alışveriş merkezleri için ortak gider ve iş takibi.');
    });

    test('fromJson: yalnız code (alanlar yok) -> yerleşik etiket / terimler / öneriler / özet', () {
      final info = ManagementTypeInfo.fromJson(<String, dynamic>{'code': 'business_center'});
      final builtIn = ManagementTypeInfo.builtIn(ManagementType.businessCenter);
      expect(info.label, 'İş Merkezi');
      expect(info.terms, builtIn.terms);
      expect(info.recommendedModules, builtIn.recommendedModules);
      expect(info.summary, builtIn.summary);
      expect(info.selectable, isTrue);
    });
  });

  group('ekleyici alanlar (eski sunucuyla uyum)', () {
    test('SiteRecord: management_terms yoksa varsayılan, varsa ayrıştırılır (copyWith korur)', () {
      final old = SiteRecord.fromJson(_siteJson());
      expect(old.managementTerms, ManagementTerms.defaults);
      final mall = SiteRecord.fromJson(_siteJson(terms: _mallTerms, type: 'shopping_mall'));
      expect(mall.managementTerms.unit, 'Mağaza');
      expect(mall.copyWith(name: 'X').managementTerms, mall.managementTerms);
      expect(mall.managementType, ManagementType.shoppingMall);
    });

    test('PlatformModule: recommended yoksa false; true okunur; copyWith korur', () {
      final plain = PlatformModule.fromJson(<String, dynamic>{'code': 'finance', 'name': 'Aidat ve Finans'});
      expect(plain.recommended, isFalse);
      final rec = PlatformModule.fromJson(<String, dynamic>{
        'code': 'finance',
        'name': 'Aidat ve Finans',
        'recommended': true,
      });
      expect(rec.recommended, isTrue);
      expect(rec.copyWith(enabled: true).recommended, isTrue);
      expect(
        PlatformModule.fromJson(<String, dynamic>{'code': 'x', 'name': 'x', 'recommended': 'true'}).recommended,
        isFalse,
      );
    });

    test('MySiteModules: management_terms / recommended_modules yoksa varsayılan ve boş; varsa okunur', () {
      final old = MySiteModules.fromJson(<String, dynamic>{
        'site_code': 11,
        'site_name': 'Gül Sitesi',
        'role': 'manager',
        'modules': <String, dynamic>{'door_control': true},
      });
      expect(old.managementTerms, ManagementTerms.defaults);
      expect(old.recommendedModules, isEmpty);
      final mall = MySiteModules.fromJson(<String, dynamic>{
        'site_code': 11,
        'site_name': 'AVM',
        'role': 'board_member',
        'modules': <String, dynamic>{'door_control': true},
        'management_terms': _mallTerms,
        'recommended_modules': <Object>['finance', 'visitor_log', 3, 'documents'],
      });
      expect(mall.managementTerms.resident, 'Kiracı firma');
      expect(mall.recommendedModules, <String>['finance', 'visitor_log', 'documents']);
      expect(mall.isEnabled('door_control'), isTrue);
    });

    test('SiteModulesState: management_terms yoksa varsayılan, varsa ayrıştırılır', () {
      final old = SiteModulesState.fromJson(<String, dynamic>{
        'site_code': 11,
        'site_name': 'Gül Sitesi',
        'modules': <Map<String, dynamic>>[],
      });
      expect(old.managementTerms, ManagementTerms.defaults);
      final mall = SiteModulesState.fromJson(<String, dynamic>{
        'site_code': 11,
        'site_name': 'AVM',
        'management_type': 'shopping_mall',
        'management_terms': _mallTerms,
        'modules': <Map<String, dynamic>>[
          <String, dynamic>{'code': 'finance', 'name': 'Aidat ve Finans', 'recommended': true},
        ],
      });
      expect(mall.managementTerms.unitPlural, 'Mağazalar');
      expect(mall.module('finance')?.recommended, isTrue);
    });
  });
}
