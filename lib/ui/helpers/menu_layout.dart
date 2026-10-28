import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

// K8 (P1-16): YETENEK ile MENÜ YERLEŞİMİ ayrı katmandır. Bu dosya menü yerleşiminin SAF kurallarıdır (widget yok).
//
//  - Yetenek: hangi modülün sitede açık olduğu. Sunucu kataloğu belirler; temel (core) modüller her sitede açık kalır.
//    Görünürlük kuralı `HomePage._extraMenuItems` / `YanMenu.visibleItems` içindedir ve BURADA kopyalanmaz.
//  - Yerleşim: görünür öğelerden hangileri ana menüde (çekmece + Panel vitrini) öne çıkar = "kompakt menü". Kümede olmayan görünür
//    öğe KAYBOLMAZ: "Tüm işlemler" ekranı görünür öğelerin TAMAMINI listeler (kümeden bağımsız).
//  - Hiçbir kural bir modülü açıp kapatmaz; kompakt menüyü yalnız site yöneticisi değiştirir (docs/PLATFORM_MENU_KATMANI.md).

/// Menü öğesinin YETENEĞİ = sunucu modül kodu. Eşlemesi olmayan öğe (Panel, Kapılar, Dairem, Site Yönetimi, Daireye Katıl, Yeni Site ve
/// bütün hesap / ayar öğeleri) modüle bağlı olmayan sabit öğedir: kompakt menüden ETKİLENMEZ, her zaman ana menüdedir.
/// "Kapılar" bilerek eşlenmez: kapı açma ürünün ana eylemidir ve kompakt kümeye bağlı değildir.
const Map<SirketMenuItem, String> menuModuleCodes = <SirketMenuItem, String>{
  SirketMenuItem.kisiler: PlatformModuleCodes.people,
  SirketMenuItem.duyurular: PlatformModuleCodes.announcements,
  SirketMenuItem.finans: PlatformModuleCodes.finance,
  SirketMenuItem.borcum: PlatformModuleCodes.finance,
  SirketMenuItem.sayaclar: PlatformModuleCodes.metering,
  SirketMenuItem.isletmeProjesi: PlatformModuleCodes.budget,
  SirketMenuItem.belgeler: PlatformModuleCodes.driveStorage,
  SirketMenuItem.talepler: PlatformModuleCodes.workTracking,
  SirketMenuItem.taleplerim: PlatformModuleCodes.workTracking,
  SirketMenuItem.rezervasyonlar: PlatformModuleCodes.reservation,
  SirketMenuItem.rezervasyon: PlatformModuleCodes.reservation,
  SirketMenuItem.anketler: PlatformModuleCodes.survey,
  SirketMenuItem.anket: PlatformModuleCodes.survey,
  SirketMenuItem.ziyaretciKayitlari: PlatformModuleCodes.visitorLog,
  SirketMenuItem.ziyaretcilerim: PlatformModuleCodes.visitorLog,
  SirketMenuItem.sozlesmeler: PlatformModuleCodes.contracts,
  SirketMenuItem.kararDefteri: PlatformModuleCodes.decisionBook,
  SirketMenuItem.kararlar: PlatformModuleCodes.decisionBook,
  SirketMenuItem.rehber: PlatformModuleCodes.directory,
  SirketMenuItem.komsuPanosu: PlatformModuleCodes.neighborBoard,
  SirketMenuItem.faaliyetRaporu: PlatformModuleCodes.annualReport,
  SirketMenuItem.plakaTanima: PlatformModuleCodes.plateRecognition,
  SirketMenuItem.odemeKamera: PlatformModuleCodes.plateCameras,
  SirketMenuItem.kameraCctv: PlatformModuleCodes.cctvLink,
  SirketMenuItem.ekipmanBakim: PlatformModuleCodes.equipment,
};

/// [item]'ın bağlı olduğu modül kodu; sabit öğede null.
String? menuModuleCodeOf(SirketMenuItem item) => menuModuleCodes[item];

/// [code] modülünün menü öğeleri (yönetim + sakin ekranı olabilir); menü yüzeyi olmayan modülde boş.
List<SirketMenuItem> menuItemsOfModule(String code) => <SirketMenuItem>[
      for (final entry in menuModuleCodes.entries)
        if (entry.value == code) entry.key,
    ];

/// Menü düzeni ekranında seçilebilen modül kodları: menü yüzeyi (en az bir menü öğesi) olanlar, eşleme sırasıyla.
List<String> get selectableMenuModules {
  final seen = <String>{};
  return <String>[
    for (final code in menuModuleCodes.values)
      if (seen.add(code)) code,
  ];
}

/// Kompakt menüde ÖNE ÇIKAN öğeler ([visible] içinden). null: kompakt menü uygulanmaz, her görünür öğe öne çıkar.
///
/// Uygulanmaz: süper kullanıcı, modül verisi hiç gelmemiş (fail-open) ve hiçbir sitenin `menu_layout` alanı yok (eski sunucu).
/// Aksi hâlde sabit öğeler (modüle bağlı olmayanlar) ve Ayarlar grubu hep öne çıkar; modüle bağlı öğe, o modülün AÇIK olduğu sitelerden
/// en az birinin kompakt kümesinde varsa öne çıkar (kümesi bilinmeyen site "hepsi öne çıkar" sayılır). Modülün hiçbir sitede açık olduğu
/// bilinmiyorsa (kanıt yok) öğe GİZLENMEZ. Kapsam: [ModuleAccess.result] site seçici kapsamına göredir.
Set<SirketMenuItem>? featuredMenuItems({
  required List<SirketMenuItem> visible,
  required ModuleAccess access,
}) {
  if (!access.isFiltering) return null;
  final sites = access.result!.sites;
  if (!sites.any((site) => site.menuLayout != null)) return null;
  return <SirketMenuItem>{
    for (final item in visible)
      if (_isFeatured(item, sites)) item,
  };
}

bool _isFeatured(SirketMenuItem item, List<MySiteModules> sites) {
  final code = menuModuleCodeOf(item);
  if (code == null || menuGroupOf(item) == SirketMenuGroup.ayarlar) return true;
  final open = sites.where((site) => site.isEnabled(code)).toList(growable: false);
  if (open.isEmpty) return true;
  return open.any((site) => site.menuLayout == null || site.menuLayout!.features(code));
}

// Öne çıkmayan ("Tüm işlemler"e giden) öğeler ve rozet toplamı `YanMenu.itemsBeyondCompact` / `YanMenu.badgeTotalOf`'tadır: çekmece ve
// Panel vitrini aynı hesabı kullanır.

/// "Tüm işlemler" ekranının bir kategorisi: grup başlığı + o gruptaki görünür öğeler (menü sırasıyla).
class AllActionsSection {
  const AllActionsSection(this.group, this.items);

  final SirketMenuGroup group;
  final List<SirketMenuItem> items;
}

/// Görünür TÜM öğelerin ([visible]) kategorili listesi: Panel hariç, çekmece başlıkları sırasıyla, en sonda Ayarlar. Kompakt küme
/// BURADA etkili değildir (tam liste); boş kategori üretilmez.
List<AllActionsSection> allActionsSections(List<SirketMenuItem> visible) => <AllActionsSection>[
      for (final group in <SirketMenuGroup>[...SirketMenuGroup.drawerGroups, SirketMenuGroup.ayarlar])
        if (visible.any((item) => item != SirketMenuItem.dashboard && menuGroupOf(item) == group))
          AllActionsSection(group, <SirketMenuItem>[
            for (final item in visible)
              if (item != SirketMenuItem.dashboard && menuGroupOf(item) == group) item,
          ]),
    ];

/// Arama karşılaştırma metni: küçük harf + Türkçe katlama (ç→c, ğ→g, ı/İ→i, ö→o, ş→s, ü→u); noktalama ve fazla boşluk tek boşluk.
String foldSearchText(String value) {
  final out = StringBuffer();
  var pendingSpace = false;
  for (final rune in value.runes) {
    final mapped = _foldRune(rune);
    if (mapped == null) {
      pendingSpace = true;
      continue;
    }
    if (pendingSpace && out.isNotEmpty) out.write(' ');
    pendingSpace = false;
    out.write(mapped);
  }
  return out.toString();
}

String? _foldRune(int r) {
  if (r >= 0x61 && r <= 0x7A) return String.fromCharCode(r);
  if (r >= 0x41 && r <= 0x5A) return String.fromCharCode(r + 32);
  if (r >= 0x30 && r <= 0x39) return String.fromCharCode(r);
  switch (r) {
    case 0xC7 || 0xE7:
      return 'c';
    case 0x11E || 0x11F:
      return 'g';
    case 0x130 || 0x131:
      return 'i';
    case 0xD6 || 0xF6:
      return 'o';
    case 0x15E || 0x15F:
      return 's';
    case 0xDC || 0xFC:
      return 'u';
    default:
      return null;
  }
}

/// [sections] içinden [query]'ye uyan öğeler. Boş sorgu tam listeyi döner. Her sorgu sözcüğü (boşlukla ayrılmış) öğenin başlığında,
/// açıklamasında ya da kategori adında geçmelidir (katlanmış metinde). Eşleşmeyen kategori düşer.
List<AllActionsSection> filterAllActions({
  required List<AllActionsSection> sections,
  required String query,
  required String Function(SirketMenuItem item) titleOf,
  required String Function(SirketMenuItem item) descriptionOf,
}) {
  final words = foldSearchText(query).split(' ').where((w) => w.isNotEmpty).toList(growable: false);
  if (words.isEmpty) return sections;
  final result = <AllActionsSection>[];
  for (final section in sections) {
    final groupText = foldSearchText(section.group.title);
    final matched = <SirketMenuItem>[
      for (final item in section.items)
        if (_matchesAll(words, '${foldSearchText(titleOf(item))} ${foldSearchText(descriptionOf(item))} $groupText')) item,
    ];
    if (matched.isNotEmpty) result.add(AllActionsSection(section.group, matched));
  }
  return result;
}

bool _matchesAll(List<String> words, String haystack) => words.every(haystack.contains);
