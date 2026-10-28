// K8 (P1-16): YETENEK ile MENÜ YERLEŞİMİ ayrı katman. Saf kurallar + model: kompakt menü kümesi menüyü (çekmece + Panel) değiştirir,
// "Tüm işlemler" listesi kümeden BAĞIMSIZ olarak tam kalır; hiçbir kural modülü açıp kapatmaz (temel modüller her sitede açık kalır).
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/audit_log.dart';
import 'package:site_kapi_kontrol/models/menu_layout.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/menu_layout.dart';
import 'package:site_kapi_kontrol/ui/helpers/module_showcase.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

/// Sunucunun 8 temel modülü (AGENTS.md Kural 25): her sitede AÇIK, kapatılamaz.
const List<String> _coreCodes = <String>[
  'people',
  'announcements',
  'finance',
  'survey',
  'neighbor_board',
  'equipment',
  'annual_report',
  'drive_storage',
];

MySiteModules _site(
  int code, {
  String role = 'manager',
  Set<String> open = const <String>{},
  SiteMenuLayout? layout,
  bool withLayout = true,
}) {
  final modules = <String, bool>{for (final c in _coreCodes) c: true, for (final c in open) c: true};
  return MySiteModules(
    siteCode: code,
    siteName: 'Site $code',
    role: role,
    modules: modules,
    menuLayout: withLayout ? (layout ?? const SiteMenuLayout(compactModules: <String>['people', 'announcements', 'finance'])) : null,
  );
}

Future<ModuleAccess> _access(List<MySiteModules> sites, {bool superUser = false, bool load = true}) async {
  final access = ModuleAccess(
    fetch: () async => MyModulesResult(scope: superUser ? 'all' : 'sites', sites: sites),
    isSuperUser: () => superUser,
  );
  addTearDown(access.dispose);
  if (load) await access.refresh();
  return access;
}

/// Yönetici modunda çekmecenin hesapladığı görünür liste (tüm temel modül ekranları açık sayılır).
List<SirketMenuItem> _managerVisible() => YanMenu.visibleItems(
      role: UserRole.siteManager,
      additionalItems: const <SirketMenuItem>{
        SirketMenuItem.kapilar,
        SirketMenuItem.kisiler,
        SirketMenuItem.duyurular,
        SirketMenuItem.finans,
        SirketMenuItem.belgeler,
        SirketMenuItem.anketler,
        SirketMenuItem.komsuPanosu,
        SirketMenuItem.faaliyetRaporu,
        SirketMenuItem.ekipmanBakim,
        SirketMenuItem.talepler,
      },
    );

void main() {
  group('SiteMenuLayout modeli', () {
    test('alan yok ya da bozuk (eski sunucu): null, menü KISALTILMAZ', () {
      expect(SiteMenuLayout.tryParse(null), isNull);
      expect(SiteMenuLayout.tryParse('x'), isNull);
      expect(SiteMenuLayout.tryParse(<String, dynamic>{'customized': true}), isNull);
      expect(SiteMenuLayout.tryParse(<String, dynamic>{'compact_modules': 'finance'}), isNull);
    });

    test('küme ve özelleştirme bayrağı okunur; metin olmayan kod atılır', () {
      final layout = SiteMenuLayout.tryParse(<String, dynamic>{
        'compact_modules': <Object?>['finance', 5, 'people', null],
        'customized': true,
      })!;
      expect(layout.compactModules, <String>['finance', 'people']);
      expect(layout.customized, isTrue);
      expect(layout.features('finance'), isTrue);
      expect(layout.features('survey'), isFalse);
      expect(SiteMenuLayout.tryParse(<String, dynamic>{'compact_modules': <Object>[]})!.customized, isFalse);
    });

    test('MySiteModules.fromJson menu_layout okur; eşitlik küme değişimini görür (menü hemen yenilensin)', () {
      Map<String, dynamic> json(List<String> compact) => <String, dynamic>{
            'site_code': 1,
            'site_name': 'Güneş',
            'modules': <String, dynamic>{'finance': true},
            'menu_layout': <String, dynamic>{'compact_modules': compact, 'customized': true},
          };
      final a = MySiteModules.fromJson(json(<String>['finance']));
      final b = MySiteModules.fromJson(json(<String>['finance']));
      final c = MySiteModules.fromJson(json(<String>['finance', 'survey']));
      expect(a.menuLayout!.compactModules, <String>['finance']);
      expect(a, b);
      expect(a == c, isFalse, reason: 'küme değişince ModuleAccess "değişti" demeli');
      expect(MySiteModules.fromJson(<String, dynamic>{'site_code': 1}).menuLayout, isNull);
    });

    test('yönetici ekranı modeli: yetenek (enabled) ile yerleşim (compact) ayrı alanlardır', () {
      final state = SiteMenuLayoutState.fromJson(<String, dynamic>{
        'site_code': 7,
        'site_name': 'Gül',
        'management_type_label': 'Apartman ve Site',
        'customized': true,
        'compact_modules': <String>['finance'],
        'default_compact_modules': <String>['finance', 'people'],
        'modules': <Object>[
          <String, dynamic>{'code': 'survey', 'name': 'Anket ve Oylama', 'core': true, 'enabled': true, 'compact': false, 'recommended': false},
          <String, dynamic>{'code': 'finance', 'name': 'Aidat ve Finans', 'core': true, 'enabled': true, 'compact': true, 'recommended': true},
        ],
      });
      expect(state.siteCode, 7);
      expect(state.customized, isTrue);
      expect(state.defaultCompactModules, <String>['finance', 'people']);
      final survey = state.modules.first;
      expect([survey.core, survey.enabled, survey.compact], [true, true, false]);
    });
  });

  group('denetim kaydı', () {
    test('menü düzeni eylemleri Türkçe etiketlenir ("Diğer işlem" değil); hedef ham kod değil açıklamadır', () {
      final updated = AuditLogEntry.fromJson(<String, dynamic>{
        'id': 1,
        'action': 'menu_layout.updated',
        'target_type': 'menu_layout',
        'target_id': '7',
        'details': <String, dynamic>{'compact_modules': <String>['finance']},
      });
      expect(updated.actionLabel, 'Ana menü düzeni güncellendi');
      expect(updated.targetLabel, 'Ana menü düzeni');
      final reset = AuditLogEntry.fromJson(<String, dynamic>{'id': 2, 'action': 'menu_layout.reset', 'target_type': 'menu_layout', 'target_id': '7'});
      expect(reset.actionLabel, 'Ana menü düzeni önerilene döndürüldü');
    });
  });

  group('menü öğesi -> modül eşlemesi', () {
    test('Panel, Kapılar, Dairem, site yönetimi ve tüm Ayarlar öğeleri modüle bağlı DEĞİL (hep ana menüde)', () {
      for (final item in <SirketMenuItem>[
        SirketMenuItem.dashboard,
        SirketMenuItem.kapilar,
        SirketMenuItem.dairem,
        SirketMenuItem.siteler,
        SirketMenuItem.katilimVeKurulum,
        SirketMenuItem.yeniSite,
      ]) {
        expect(menuModuleCodeOf(item), isNull, reason: item.name);
      }
      for (final item in SirketMenuItem.values) {
        if (menuGroupOf(item) == SirketMenuGroup.ayarlar) {
          expect(menuModuleCodeOf(item), isNull, reason: '${item.name} Ayarlar grubunda: kompakt menüden etkilenmez');
        }
      }
    });

    test('yönetim + sakin ekranı aynı modülde; seçilebilir modüller menü yüzeyi olanlardır', () {
      expect(menuItemsOfModule('finance'), <SirketMenuItem>[SirketMenuItem.finans, SirketMenuItem.borcum]);
      expect(menuItemsOfModule('work_tracking'), containsAll(<SirketMenuItem>[SirketMenuItem.talepler, SirketMenuItem.taleplerim]));
      expect(menuItemsOfModule('door_control'), isEmpty, reason: 'kapı açma kompakt kümeye bağlı değildir');
      expect(menuItemsOfModule('hgs_access'), isEmpty);
      final selectable = selectableMenuModules;
      expect(selectable.toSet().length, selectable.length, reason: 'tekrar yok');
      expect(selectable, containsAll(_coreCodes));
      for (final code in selectable) {
        expect(menuItemsOfModule(code), isNotEmpty, reason: code);
      }
    });

    test('eşlenen her modül kodu bilinen katalog kodudur (yazım hatası yok)', () {
      const known = <String>{
        PlatformModuleCodes.people,
        PlatformModuleCodes.announcements,
        PlatformModuleCodes.finance,
        PlatformModuleCodes.reservation,
        PlatformModuleCodes.workTracking,
        PlatformModuleCodes.metering,
        PlatformModuleCodes.survey,
        PlatformModuleCodes.visitorLog,
        PlatformModuleCodes.contracts,
        PlatformModuleCodes.equipment,
        PlatformModuleCodes.cctvLink,
        PlatformModuleCodes.decisionBook,
        PlatformModuleCodes.directory,
        PlatformModuleCodes.budget,
        PlatformModuleCodes.driveStorage,
        PlatformModuleCodes.neighborBoard,
        PlatformModuleCodes.annualReport,
        PlatformModuleCodes.plateCameras,
        PlatformModuleCodes.plateRecognition,
      };
      expect(menuModuleCodes.values.toSet(), known);
    });
  });

  group('kompakt menü (featuredMenuItems)', () {
    test('süper kullanıcı, veri yok ve eski sunucu (menu_layout yok): kompakt menü UYGULANMAZ (null = her şey öne çıkar)', () async {
      final visible = _managerVisible();
      expect(featuredMenuItems(visible: visible, access: await _access(const <MySiteModules>[], superUser: true)), isNull);
      expect(featuredMenuItems(visible: visible, access: await _access(<MySiteModules>[_site(1)], load: false)), isNull);
      expect(featuredMenuItems(visible: visible, access: await _access(<MySiteModules>[_site(1, withLayout: false)])), isNull);
    });

    test('küme dışındaki modül öğeleri öne çıkmaz; sabit öğeler ve Ayarlar öğeleri HEP öne çıkar', () async {
      final visible = _managerVisible();
      // İş takibi bu sitede AÇIK ama kümede değil (kapalı modül "kanıt yok" sayılıp gizlenmez; açık ve kümede olmayan gizlenir).
      final featured = featuredMenuItems(
        visible: visible,
        access: await _access(<MySiteModules>[_site(1, open: const <String>{'work_tracking'})]),
      )!;
      expect(featured, containsAll(<SirketMenuItem>[
        SirketMenuItem.dashboard,
        SirketMenuItem.kapilar,
        SirketMenuItem.siteler,
        SirketMenuItem.katilimVeKurulum,
        SirketMenuItem.yeniSite,
        SirketMenuItem.profilim,
        SirketMenuItem.moduller,
        SirketMenuItem.kisiler,
        SirketMenuItem.duyurular,
        SirketMenuItem.finans,
      ]));
      for (final hidden in <SirketMenuItem>[
        SirketMenuItem.belgeler,
        SirketMenuItem.anketler,
        SirketMenuItem.komsuPanosu,
        SirketMenuItem.faaliyetRaporu,
        SirketMenuItem.ekipmanBakim,
        SirketMenuItem.talepler,
      ]) {
        expect(featured.contains(hidden), isFalse, reason: '${hidden.name} kümede değil');
      }
    });

    test('KÜME DEĞİŞİNCE MENÜ DEĞİŞİR ama "Tüm işlemler" TAM KALIR; hiçbir işlem kaybolmaz', () async {
      final visible = _managerVisible();
      final base = await _access(<MySiteModules>[_site(1)]);
      final wide = await _access(<MySiteModules>[
        _site(1, layout: const SiteMenuLayout(compactModules: <String>['people', 'announcements', 'finance', 'survey', 'equipment'], customized: true)),
      ]);
      final none = await _access(<MySiteModules>[
        _site(1, layout: const SiteMenuLayout(customized: true)),
      ]);

      final a = featuredMenuItems(visible: visible, access: base)!;
      final b = featuredMenuItems(visible: visible, access: wide)!;
      final c = featuredMenuItems(visible: visible, access: none)!;
      expect(a, isNot(equals(b)), reason: 'küme değişince çekmece / Panel öğeleri değişir');
      expect(b, containsAll(<SirketMenuItem>[SirketMenuItem.anketler, SirketMenuItem.ekipmanBakim]));
      expect(a.contains(SirketMenuItem.anketler), isFalse);
      expect(c.contains(SirketMenuItem.finans), isFalse, reason: 'boş küme: yalnız sabit öğeler');
      expect(c.contains(SirketMenuItem.kapilar), isTrue);

      // "Tüm işlemler": her durumda görünür listenin TAMAMI (Panel hariç) kategorili.
      List<SirketMenuItem> all(Set<SirketMenuItem> _) =>
          allActionsSections(visible).expand((s) => s.items).toList();
      final expected = visible.where((i) => i != SirketMenuItem.dashboard).toSet();
      for (final featured in <Set<SirketMenuItem>>[a, b, c]) {
        expect(all(featured).toSet(), expected, reason: 'Tüm işlemler kümeden bağımsız tam');
        expect(all(featured).length, expected.length, reason: 'tekrar yok');
      }
      // Çekmece (kompakt) + Tüm işlemler'e giden = görünür liste: ikisinin birleşimi hiçbir öğeyi kaybetmez.
      for (final featured in <Set<SirketMenuItem>>[a, b, c]) {
        final shown = YanMenu.compactItems(visible, featured);
        final beyond = YanMenu.itemsBeyondCompact(visible, featured);
        expect(<SirketMenuItem>{...shown, ...beyond}, visible.toSet());
        expect(shown.toSet().intersection(beyond.toSet()), isEmpty);
      }
    });

    test('çok site: modül, AÇIK olduğu sitelerden en az birinin kümesindeyse öne çıkar; kapalı sitenin kümesi sayılmaz', () async {
      final visible = _managerVisible();
      final a = _site(1, layout: const SiteMenuLayout(compactModules: <String>['survey'], customized: true));
      final b = _site(2, layout: const SiteMenuLayout(compactModules: <String>['equipment'], customized: true));
      final featured = featuredMenuItems(visible: visible, access: await _access(<MySiteModules>[a, b]))!;
      expect(featured.contains(SirketMenuItem.anketler), isTrue);
      expect(featured.contains(SirketMenuItem.ekipmanBakim), isTrue);
      expect(featured.contains(SirketMenuItem.komsuPanosu), isFalse);

      // Anket yalnız kümesi seçen sitede KAPALI olsaydı (başka sitede açık, orada kümede değil) öne çıkmazdı.
      final closed = MySiteModules(
        siteCode: 3,
        siteName: 'Kapalı',
        role: 'manager',
        modules: const <String, bool>{'survey': false, 'work_tracking': true},
        menuLayout: const SiteMenuLayout(compactModules: <String>['survey'], customized: true),
      );
      final open = _site(4, open: const <String>{'work_tracking'}, layout: const SiteMenuLayout(compactModules: <String>['finance'], customized: true));
      final access = await _access(<MySiteModules>[closed, open]);
      final f2 = featuredMenuItems(visible: <SirketMenuItem>[SirketMenuItem.talepler, SirketMenuItem.anketler], access: access)!;
      expect(f2.contains(SirketMenuItem.talepler), isFalse, reason: 'iş takibi açık sitenin kümesinde yok');
      expect(f2.contains(SirketMenuItem.anketler), isFalse, reason: 'anket kümesi KAPALI sitede; açık sitede (temel) kümede yok');
    });

    test('kümesi bilinmeyen site "hepsi öne çıkar" sayılır; modülün açık olduğu site bilinmiyorsa öğe GİZLENMEZ', () async {
      final visible = <SirketMenuItem>[SirketMenuItem.anketler, SirketMenuItem.talepler, SirketMenuItem.kararDefteri];
      final access = await _access(<MySiteModules>[
        _site(1, layout: const SiteMenuLayout(customized: true)),
        _site(2, withLayout: false),
      ]);
      final featured = featuredMenuItems(visible: visible, access: access)!;
      expect(featured.contains(SirketMenuItem.anketler), isTrue, reason: 'eski sunucudaki site: kısaltma yok');
      expect(featured.contains(SirketMenuItem.kararDefteri), isTrue, reason: 'hiçbir sitede açık değil: kanıt yok, gizlenmez');
    });

    test('site seçici kapsamı: seçilen sitenin kümesi geçerlidir', () async {
      final visible = _managerVisible();
      final a = _site(1, layout: const SiteMenuLayout(compactModules: <String>['survey'], customized: true));
      final b = _site(2, layout: const SiteMenuLayout(compactModules: <String>['equipment'], customized: true));
      final access = await _access(<MySiteModules>[a, b]);
      access.setScopeSiteCode(2);
      final featured = featuredMenuItems(visible: visible, access: access)!;
      expect(featured.contains(SirketMenuItem.ekipmanBakim), isTrue);
      expect(featured.contains(SirketMenuItem.anketler), isFalse, reason: 'kapsam dışı sitenin kümesi sayılmaz');
    });
  });

  group('YanMenu kompakt yardımcıları', () {
    test('compactItems: Panel ve Ayarlar öğeleri kümeden düşmez; null küme listeyi aynen verir', () {
      final visible = _managerVisible();
      expect(identical(YanMenu.compactItems(visible, null), visible), isTrue);
      final shown = YanMenu.compactItems(visible, const <SirketMenuItem>{});
      expect(shown, contains(SirketMenuItem.dashboard));
      expect(shown, contains(SirketMenuItem.profilim));
      expect(shown, contains(SirketMenuItem.moduller));
      expect(shown, isNot(contains(SirketMenuItem.finans)));
    });

    test('itemsBeyondCompact: Panel ve Ayarlar hiçbir zaman "Tüm işlemler\'e giden" sayılmaz', () {
      final visible = _managerVisible();
      final beyond = YanMenu.itemsBeyondCompact(visible, const <SirketMenuItem>{});
      expect(beyond, isNot(contains(SirketMenuItem.dashboard)));
      for (final item in beyond) {
        expect(menuGroupOf(item), isNot(SirketMenuGroup.ayarlar));
      }
      expect(YanMenu.itemsBeyondCompact(visible, null), isEmpty);
    });

    test('badgeTotalOf: gizlenen işlerin bekleyen sayıları toplanır (kompakt menü sinyali gizlemez)', () {
      expect(
        YanMenu.badgeTotalOf(
          const <SirketMenuItem>[SirketMenuItem.duyurular, SirketMenuItem.anket, SirketMenuItem.talepler],
          const <SirketMenuItem, int>{SirketMenuItem.duyurular: 3, SirketMenuItem.talepler: 2, SirketMenuItem.finans: 9},
        ),
        5,
      );
      expect(YanMenu.badgeTotalOf(const <SirketMenuItem>[], const <SirketMenuItem, int>{SirketMenuItem.duyurular: 3}), 0);
    });
  });

  group('Tüm işlemler: kategori + arama', () {
    test('kategoriler çekmece başlıkları sırasıyla, en sonda Ayarlar; Panel yok; boş kategori yok', () {
      final sections = allActionsSections(_managerVisible());
      final groups = sections.map((s) => s.group).toList();
      expect(groups.last, SirketMenuGroup.ayarlar);
      expect(groups, isNot(contains(SirketMenuGroup.anaSayfa)), reason: 'Panel listelenmez, Ana sayfa kategorisi boş');
      expect(groups, containsAll(<SirketMenuGroup>[SirketMenuGroup.daireler, SirketMenuGroup.borclar, SirketMenuGroup.iletisim, SirketMenuGroup.siteHizmetleri]));
      for (final s in sections) {
        expect(s.items, isNotEmpty);
        expect(s.items.every((i) => menuGroupOf(i) == s.group), isTrue);
      }
    });

    test('foldSearchText: Türkçe katlama ve küçük harf', () {
      expect(foldSearchText('ÇAĞRI Işık İÖŞÜ'), 'cagri isik iosu');
      expect(foldSearchText('  Anket   ve-Oylama '), 'anket ve oylama');
      expect(foldSearchText(''), '');
    });

    test('filterAllActions: boş sorgu tam liste; sözcükler başlıkta, açıklamada ya da kategoride aranır; eşleşmeyen kategori düşer', () {
      final sections = allActionsSections(_managerVisible());
      String title(SirketMenuItem i) => YanMenu.titleFor(i, UserRole.siteManager);
      String desc(SirketMenuItem i) => showcaseDescription(i, UserRole.siteManager);
      List<SirketMenuItem> search(String q) => filterAllActions(sections: sections, query: q, titleOf: title, descriptionOf: desc)
          .expand((s) => s.items)
          .toList();

      expect(identical(filterAllActions(sections: sections, query: '  ', titleOf: title, descriptionOf: desc), sections), isTrue);
      expect(search('ANKET'), contains(SirketMenuItem.anketler), reason: 'büyük/küçük harf');
      expect(search('komsu'), contains(SirketMenuItem.komsuPanosu), reason: 'Türkçe katlama: "komşu"');
      expect(search('aidat'), contains(SirketMenuItem.finans), reason: 'açıklamada geçer');
      expect(search('borclar'), containsAll(<SirketMenuItem>[SirketMenuItem.finans]), reason: 'kategori adıyla');
      expect(search('aidat borc'), contains(SirketMenuItem.finans), reason: 'her sözcük bir yerde geçmeli');
      expect(search('zzzz'), isEmpty);
      final filtered = filterAllActions(sections: sections, query: 'anket', titleOf: title, descriptionOf: desc);
      expect(filtered.every((s) => s.items.isNotEmpty), isTrue);
    });
  });
}
