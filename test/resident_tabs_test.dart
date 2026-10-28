// İP-1D / G3: daire sakini alt çubuğunun sekmeleri (SAF türetim). Sekme = görünür menü öğesi: Özet=Panel,
// Duyuru=Duyurular, Arıza=Taleplerim, Kapı=Kapılar, Belgeler=Belgeler (karar sırasıyla). Kapı ayrıca kapı yetkisi ister;
// modülü kapalı (menüde olmayan) öğenin sekmesi yoktur; iki sekmeden azsa çubuk çizilmez.
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/helpers/resident_tabs.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

const List<SirketMenuItem> _all = <SirketMenuItem>[
  SirketMenuItem.dashboard,
  SirketMenuItem.kapilar,
  SirketMenuItem.katilimVeKurulum,
  SirketMenuItem.duyurular,
  SirketMenuItem.borcum,
  SirketMenuItem.belgeler,
  SirketMenuItem.taleplerim,
  SirketMenuItem.rezervasyon,
  SirketMenuItem.profilim,
];

void main() {
  test('sekmeler ve etiketler karar G3 sırasıyla; her sekme bir menü öğesidir', () {
    expect(ResidentTab.values.map((t) => t.label).toList(), <String>['Özet', 'Duyuru', 'Arıza', 'Kapı', 'Dosyalar']);
    expect(ResidentTab.values.map((t) => t.item).toList(), <SirketMenuItem>[
      SirketMenuItem.dashboard,
      SirketMenuItem.duyurular,
      SirketMenuItem.taleplerim,
      SirketMenuItem.kapilar,
      SirketMenuItem.belgeler,
    ]);
  });

  group('matris: görünür öğe × kapı yetkisi', () {
    final cases = <(String, List<SirketMenuItem>, bool, List<ResidentTab>)>[
      ('hepsi açık + kapı yetkisi', _all, true, ResidentTab.values),
      (
        'kapı yetkisi yok: PDF\'teki dört sekme',
        _all,
        false,
        <ResidentTab>[ResidentTab.ozet, ResidentTab.duyuru, ResidentTab.ariza, ResidentTab.belgeler],
      ),
      (
        'Geçiş Kontrol kapalı (Kapılar menüde yok) — yetki bayrağı açık olsa da Kapı yok',
        <SirketMenuItem>[for (final i in _all) if (i != SirketMenuItem.kapilar) i],
        true,
        <ResidentTab>[ResidentTab.ozet, ResidentTab.duyuru, ResidentTab.ariza, ResidentTab.belgeler],
      ),
      (
        'İş Takibi ve Belgeler kapalı',
        <SirketMenuItem>[SirketMenuItem.dashboard, SirketMenuItem.kapilar, SirketMenuItem.duyurular],
        true,
        <ResidentTab>[ResidentTab.ozet, ResidentTab.duyuru, ResidentTab.kapi],
      ),
      (
        'yalnız Panel + Kapılar (kapı yetkisi var): iki sekme',
        <SirketMenuItem>[SirketMenuItem.dashboard, SirketMenuItem.kapilar],
        true,
        <ResidentTab>[ResidentTab.ozet, ResidentTab.kapi],
      ),
      (
        'yalnız Panel: tek sekme',
        <SirketMenuItem>[SirketMenuItem.dashboard, SirketMenuItem.profilim],
        false,
        <ResidentTab>[ResidentTab.ozet],
      ),
      (
        'görevli (yalnız yönetim öğeleri): tek sekme',
        <SirketMenuItem>[SirketMenuItem.dashboard, SirketMenuItem.talepler, SirketMenuItem.katilimVeKurulum],
        false,
        <ResidentTab>[ResidentTab.ozet],
      ),
    ];
    for (final (label, items, door, expected) in cases) {
      test(label, () {
        final tabs = residentTabsFor(menuItems: items, hasDoorAccess: door);
        expect(tabs, expected);
        expect(showsResidentBar(tabs), expected.length >= 2, reason: 'iki sekmeden azsa çubuk yok');
      });
    }
  });

  group('ekrandaki sayfanın sekmesi', () {
    final tabs = residentTabsFor(menuItems: _all, hasDoorAccess: true);
    final noDoor = residentTabsFor(menuItems: _all, hasDoorAccess: false);

    test('sekme sayfası kendi sekmesidir', () {
      for (final tab in tabs) {
        expect(residentTabFor(tab.item, tabs), tab);
      }
    });

    test('sekme olmayan sayfa (Borcum, Rezervasyon, Profilim) Özet altındadır', () {
      for (final page in <SirketMenuItem>[SirketMenuItem.borcum, SirketMenuItem.rezervasyon, SirketMenuItem.profilim]) {
        expect(residentTabFor(page, tabs), ResidentTab.ozet, reason: page.name);
      }
    });

    test('Kapı sekmesi çizilmiyorsa Kapılar sayfası da Özet altındadır', () {
      expect(residentTabFor(SirketMenuItem.kapilar, noDoor), ResidentTab.ozet);
    });
  });
}
