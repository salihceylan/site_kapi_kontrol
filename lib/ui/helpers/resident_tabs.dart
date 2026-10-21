import 'package:flutter/material.dart' show IconData;
import 'package:phosphor_glyphs/phosphor_glyphs.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

// İP-1D / G3 (karar kaydı 2026-10-21): daire sakini alt çubuğunun SAF kuralları (widget yok). Sekmeler çekmecenin
// görünür öğe listesinden (YanMenu.visibleItems) türetilir; görünürlük kuralı burada KOPYALANMAZ: menüde olmayan
// (kapalı / yetkisiz) öğenin sekmesi olamaz ("fail-closed").

/// Alt çubuğun sekmeleri, karar G3 sırasıyla: Özet · Duyuru · Arıza · Kapı · Belgeler. Her sekme bir menü öğesidir;
/// sekmeye dokunmak çekmecede o öğeyi seçmekle AYNI gezinmedir. Özet = Panel (modül vitrini, borç kartı üstte).
enum ResidentTab {
  ozet(SirketMenuItem.dashboard, 'Özet', PhosphorIconsRegular.squaresFour, PhosphorIconsRegular.squaresFour),
  duyuru(SirketMenuItem.duyurular, 'Duyuru', PhosphorIconsRegular.megaphone, PhosphorIconsRegular.megaphone),
  ariza(SirketMenuItem.taleplerim, 'Arıza', PhosphorIconsRegular.wrench, PhosphorIconsRegular.wrench),
  kapi(SirketMenuItem.kapilar, 'Kapı', PhosphorIconsRegular.doorOpen, PhosphorIconsRegular.doorOpen),
  belgeler(SirketMenuItem.belgeler, 'Belgeler', PhosphorIconsRegular.folder, PhosphorIconsRegular.folder);

  const ResidentTab(this.item, this.label, this.icon, this.selectedIcon);

  /// Sekmenin açtığı menü öğesi.
  final SirketMenuItem item;

  /// Sekme etiketi (kısa; ekran okuyucu da bunu okur).
  final String label;

  /// Seçili değilken ve seçiliyken simge.
  final IconData icon;
  final IconData selectedIcon;
}

/// Çubuğun sekmeleri: [menuItems] (çekmecenin görünür öğeleri) içinde olanlar, karar sırasıyla. "Kapı" ayrıca kapı
/// yetkisinin olumlu kanıtını ister ([hasDoorAccess]: kapı listesi dolu ya da modül verisinde kapı erişimli site);
/// "Kapılar" menüde olsa bile (örn. modül verisi gelmediğinde fail-open) yetki yoksa Kapı sekmesi çizilmez.
List<ResidentTab> residentTabsFor({
  required List<SirketMenuItem> menuItems,
  required bool hasDoorAccess,
}) =>
    <ResidentTab>[
      for (final tab in ResidentTab.values)
        if (menuItems.contains(tab.item) && (tab != ResidentTab.kapi || hasDoorAccess)) tab,
    ];

/// Çubuk çizilir mi: en az iki sekme (yalnız Özet kalan hesapta çubuk yok).
bool showsResidentBar(List<ResidentTab> tabs) => tabs.length >= 2;

/// Ekrandaki sayfanın sekmesi: sayfa bir sekmeyse o; değilse (Borcum, Rezervasyon, Profilim ... ya da çizilmeyen Kapı
/// sekmesinin sayfası) Özet. Bu sayfalara Özet'teki vitrinden ya da çekmeceden gelinir.
ResidentTab residentTabFor(SirketMenuItem page, List<ResidentTab> tabs) {
  for (final tab in tabs) {
    if (tab.item == page) return tab;
  }
  return ResidentTab.ozet;
}
