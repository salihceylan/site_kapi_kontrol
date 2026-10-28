import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/person_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/ui/design/module_art.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

// Panel modül vitrininin SAF mantığı (widget yok): hangi öğe hangi karta dönüşür, hangisi ana ızgarada ve hangisi
// ikincil satırda, hangi görsel/açıklama, kaç sütun. Vitrin yan menünün hesapladığı listeden (YanMenu.visibleItems)
// türetilir; görünürlük kuralı burada KOPYALANMAZ: listede olmayan öğenin kartı olamaz ("fail-closed").

/// Vitrinin kim için çizildiği (üst bölüm ve hızlı eylemler buna göre değişir).
enum ShowcaseAudience {
  /// Süper kullanıcı ve yönetici modundaki yönetici: üstte "Dikkat edilmesi gereken iş" barı (yalnız bekleyen sayı
  /// varken), altında modül ızgarası.
  admin,

  /// Daire sakini, kurul üyesi, görevli ve sakin modundaki yönetici: üstte koyu "Güncel borcunuz" (ya da selamlama)
  /// kartı, altında hızlı işlemler, sonra modül ızgarası.
  resident,

  /// Site / daire bağı olmayan bireysel kullanıcı: yalnız modül ızgarası (ve varsa site başvurusu durumu).
  individual,
}

/// Vitrinin kitlesi; [YanMenu] öğe listesinin rol/mod mantığıyla (bkz. `_itemsForRole`) aynı ayrımı yapar.
ShowcaseAudience showcaseAudience({
  required UserRole role,
  required bool isResidentMode,
  required bool canToggleMode,
}) {
  switch (role) {
    case UserRole.superUser:
      return ShowcaseAudience.admin;
    case UserRole.siteManager:
      return isResidentMode ? ShowcaseAudience.resident : ShowcaseAudience.admin;
    case UserRole.apartmentOwner:
      return canToggleMode && !isResidentMode ? ShowcaseAudience.admin : ShowcaseAudience.resident;
    case UserRole.individual:
      return canToggleMode && !isResidentMode ? ShowcaseAudience.admin : ShowcaseAudience.individual;
  }
}

/// Hesap / ayar / sistem türü öğeler: ana ızgarada KART OLMAZ, vitrinin altında küçük ikincil satırda (ya da yalnız
/// çekmecede) durur. Kural bu küme; testle sabittir (`module_showcase_test.dart`). "Panel" (vitrinin kendisi) hiçbir
/// yerde kart değildir.
const Set<SirketMenuItem> showcaseSecondaryItems = <SirketMenuItem>{
  SirketMenuItem.profilim,
  SirketMenuItem.ellerSerbest,
  SirketMenuItem.bluetoothWifiKur,
  SirketMenuItem.denetimKaydi,
  SirketMenuItem.platformAyarlari,
  SirketMenuItem.istemciHatalari,
};

/// Özellik modülleri: ızgarada yönetim araçlarından (site / kullanıcı / cihaz yönetimi) ÖNCE gelir.
const Set<SirketMenuItem> _featureModuleItems = <SirketMenuItem>{
  SirketMenuItem.kisiler,
  SirketMenuItem.duyurular,
  SirketMenuItem.finans,
  SirketMenuItem.borcum,
  SirketMenuItem.belgeler,
  SirketMenuItem.talepler,
  SirketMenuItem.taleplerim,
  SirketMenuItem.rezervasyonlar,
  SirketMenuItem.rezervasyon,
  SirketMenuItem.anketler,
  SirketMenuItem.anket,
  SirketMenuItem.kararDefteri,
  SirketMenuItem.kararlar,
  SirketMenuItem.rehber,
  SirketMenuItem.isletmeProjesi,
  SirketMenuItem.komsuPanosu,
  SirketMenuItem.faaliyetRaporu,
  SirketMenuItem.plakaTanima,
  SirketMenuItem.ziyaretciKayitlari,
  SirketMenuItem.ziyaretcilerim,
  SirketMenuItem.sozlesmeler,
  SirketMenuItem.sayaclar,
  SirketMenuItem.odemeKamera,
  SirketMenuItem.kameraCctv,
  SirketMenuItem.ekipmanBakim,
  SirketMenuItem.acilDurum,
};

const Map<SirketMenuItem, ModuleArtKind> _artKinds = <SirketMenuItem, ModuleArtKind>{
  SirketMenuItem.kapilar: ModuleArtKind.door,
  SirketMenuItem.dairem: ModuleArtKind.people,
  SirketMenuItem.kisiler: ModuleArtKind.people,
  SirketMenuItem.duyurular: ModuleArtKind.announcements,
  SirketMenuItem.finans: ModuleArtKind.finance,
  SirketMenuItem.borcum: ModuleArtKind.myDebt,
  SirketMenuItem.belgeler: ModuleArtKind.documents,
  SirketMenuItem.talepler: ModuleArtKind.workTracking,
  SirketMenuItem.taleplerim: ModuleArtKind.workTracking,
  SirketMenuItem.rezervasyonlar: ModuleArtKind.reservation,
  SirketMenuItem.rezervasyon: ModuleArtKind.reservation,
  SirketMenuItem.anketler: ModuleArtKind.survey,
  SirketMenuItem.anket: ModuleArtKind.survey,
  SirketMenuItem.ziyaretciKayitlari: ModuleArtKind.visitor,
  SirketMenuItem.ziyaretcilerim: ModuleArtKind.visitor,
  SirketMenuItem.sozlesmeler: ModuleArtKind.contracts,
  SirketMenuItem.sayaclar: ModuleArtKind.finance,
  SirketMenuItem.kararDefteri: ModuleArtKind.decisions,
  SirketMenuItem.kararlar: ModuleArtKind.decisions,
  SirketMenuItem.rehber: ModuleArtKind.people,
  SirketMenuItem.isletmeProjesi: ModuleArtKind.finance,
  SirketMenuItem.komsuPanosu: ModuleArtKind.announcements,
  SirketMenuItem.faaliyetRaporu: ModuleArtKind.finance,
  SirketMenuItem.plakaTanima: ModuleArtKind.devices,
  SirketMenuItem.odemeKamera: ModuleArtKind.devices,
  SirketMenuItem.kameraCctv: ModuleArtKind.devices,
  SirketMenuItem.ekipmanBakim: ModuleArtKind.contracts,
  SirketMenuItem.acilDurum: ModuleArtKind.help,
  SirketMenuItem.siteler: ModuleArtKind.sites,
  SirketMenuItem.siteBasvurulari: ModuleArtKind.sites,
  SirketMenuItem.siteOnayTalepleri: ModuleArtKind.sites,
  SirketMenuItem.katilimVeKurulum: ModuleArtKind.sites,
  SirketMenuItem.moduller: ModuleArtKind.modules,
  SirketMenuItem.modulTalepleri: ModuleArtKind.modules,
  SirketMenuItem.abonelikTalepleri: ModuleArtKind.modules,
  SirketMenuItem.kayitliCihazlar: ModuleArtKind.devices,
  SirketMenuItem.cihazEkle: ModuleArtKind.devices,
  SirketMenuItem.bluetoothWifiKur: ModuleArtKind.devices,
  SirketMenuItem.kullaniciYonetimi: ModuleArtKind.users,
  SirketMenuItem.superUserYonetimi: ModuleArtKind.users,
  SirketMenuItem.siteYoneticileriYonetimi: ModuleArtKind.users,
  SirketMenuItem.daireKullanicilariYonetimi: ModuleArtKind.people,
  SirketMenuItem.denetimKaydi: ModuleArtKind.reports,
  SirketMenuItem.istemciHatalari: ModuleArtKind.reports,
  SirketMenuItem.platformAyarlari: ModuleArtKind.settings,
  SirketMenuItem.ellerSerbest: ModuleArtKind.settings,
  SirketMenuItem.profilim: ModuleArtKind.users,
  SirketMenuItem.yeniSite: ModuleArtKind.sites,
};

/// Menü öğesinin vitrin görseli; eşlemesi olmayan (bilinmeyen / yeni) öğe [ModuleArtKind.generic].
ModuleArtKind moduleArtKindFor(SirketMenuItem item) => _artKinds[item] ?? ModuleArtKind.generic;

const Map<SirketMenuItem, String> _descriptions = <SirketMenuItem, String>{
  SirketMenuItem.kapilar: 'Kapı durumu ve kapıyı aç',
  SirketMenuItem.dairem: 'Daire yönetimi, kiracı ve aile üyeleri',
  SirketMenuItem.kisiler: 'Kişiler, daireler ve araçlar',
  SirketMenuItem.duyurular: 'Site duyuruları ve bildirimler',
  SirketMenuItem.finans: 'Aidat, borç ve tahsilat',
  SirketMenuItem.borcum: 'Borç durumunuz ve hareketleriniz',
  SirketMenuItem.belgeler: 'Site belgeleri ve dosyalar',
  SirketMenuItem.talepler: 'Arıza, bakım ve talep takibi',
  SirketMenuItem.taleplerim: 'Arıza bildirin, talebinizi izleyin',
  SirketMenuItem.rezervasyonlar: 'Ortak alan rezervasyonları',
  SirketMenuItem.rezervasyon: 'Ortak alan ayırtın',
  SirketMenuItem.anketler: 'Anket ve oylama yönetimi',
  SirketMenuItem.anket: 'Oy verin, sonuçları görün',
  SirketMenuItem.ziyaretciKayitlari: 'Ziyaretçi ve kargo kayıtları',
  SirketMenuItem.ziyaretcilerim: 'Dairenizin ziyaretçi ve kargoları',
  SirketMenuItem.sozlesmeler: 'Firma ve sözleşme takibi',
  SirketMenuItem.sayaclar: 'Sayaç okuma ve faturalandırma',
  SirketMenuItem.kararDefteri: 'Kurul ve genel kurul kararları',
  SirketMenuItem.kararlar: 'Sitenizin kesinleşen kararları',
  SirketMenuItem.rehber: 'Yönetim kadrosu ve faydalı telefonlar',
  SirketMenuItem.isletmeProjesi: 'Yıllık gider bütçesi ve gerçekleşen',
  SirketMenuItem.komsuPanosu: 'Komşu ilanları ve onay',
  SirketMenuItem.faaliyetRaporu: 'Yıllık rapor taslağı ve PDF',
  SirketMenuItem.plakaTanima: 'Araç plakası kayıtları ve misafir plakası',
  SirketMenuItem.odemeKamera: 'Plaka tanıyan kameralar',
  SirketMenuItem.kameraCctv: 'Kapı olaylarını kamera kayıtlarıyla eşleştirin',
  SirketMenuItem.ekipmanBakim: 'Ekipman, bakım planı ve teklifler',
  SirketMenuItem.acilDurum: '112, yangın ve asansör arızası',
  SirketMenuItem.siteler: 'Site, blok, daire ve kapılar',
  SirketMenuItem.siteBasvurulari: 'Site kurma başvuruları',
  SirketMenuItem.siteOnayTalepleri: 'Onay bekleyen siteler',
  SirketMenuItem.katilimVeKurulum: 'Daireye katılın',
  // Anahtar yalnız süper kullanıcıdadır (Faz 1.1): rol verilmezse açma / kapama vaat edilmez (bkz. [_roleDescription]).
  SirketMenuItem.moduller: 'Tanımlı modüller ve modül talebi',
  SirketMenuItem.modulTalepleri: 'Yöneticilerin modül talepleri',
  SirketMenuItem.abonelikTalepleri: 'Yeni abonelik talepleri',
  SirketMenuItem.kayitliCihazlar: 'Cihaz envanteri ve durumu',
  SirketMenuItem.cihazEkle: 'Yeni cihaz kaydedin',
  SirketMenuItem.bluetoothWifiKur: 'Cihaza Wi-Fi tanımlayın',
  SirketMenuItem.kullaniciYonetimi: 'Tüm kullanıcı hesapları',
  SirketMenuItem.superUserYonetimi: 'Süper kullanıcı hesapları',
  SirketMenuItem.siteYoneticileriYonetimi: 'Site yöneticisi hesapları',
  SirketMenuItem.daireKullanicilariYonetimi: 'Daire sakinleri ve hesapları',
  SirketMenuItem.denetimKaydi: 'Yönetici işlem kayıtları',
  SirketMenuItem.platformAyarlari: 'Sürüm, destek ve yasal bilgiler',
  SirketMenuItem.istemciHatalari: 'Uygulama hata raporları',
  SirketMenuItem.ellerSerbest: 'Eller serbest ve kestirmeler',
  SirketMenuItem.profilim: 'Hesap bilgileriniz',
  SirketMenuItem.yeniSite: 'Yeni site ve apartman kurun veya başvurun',
};

/// Rolüne göre farklı söylenen açıklamalar: kart, kullanıcının o sayfada YAPABİLECEĞİNİ söyler (yetki kuralıyla
/// çelişmez). null: role özel metin yok, [_descriptions] geçerli.
String? _roleDescription(SirketMenuItem item, UserRole? role) {
  switch (item) {
    case SirketMenuItem.moduller:
      // Modülü yalnız süper kullanıcı açıp kapatır; site yöneticisi tanımlı modülleri görür ve talep gönderir.
      return role == UserRole.superUser ? 'Site modüllerini açın ve kapatın' : null;
    case SirketMenuItem.kapilar:
      // Bireysel kullanıcıda Kapılar sayfası bireysel ana ekrandır: kapılar, kayıtlı daireler, cihazlar, başvurular.
      return role == UserRole.individual ? 'Kapılar, daireleriniz ve cihazlarınız' : null;
    default:
      return null;
  }
}

/// Kartın tek satırlık açıklaması (başlık menüdeki başlıktır: [YanMenu.titleFor]). [role] verilirse role özel metin
/// (örn. "Modüller": süper kullanıcıda aç / kapat, site yöneticisinde görüntüle / talep et) önceliklidir.
String showcaseDescription(SirketMenuItem item, [UserRole? role]) =>
    _roleDescription(item, role) ?? _descriptions[item] ?? '';

/// Vitrin kartı: yan menüdeki bir öğenin görünümü.
@immutable
class ShowcaseEntry {
  const ShowcaseEntry({
    required this.item,
    required this.title,
    required this.description,
    required this.art,
    this.badge = 0,
    this.badgeNoun = 'bekleyen',
  });

  /// Dokununca açılacak menü öğesi (çekmecede seçmekle aynı gezinme).
  final SirketMenuItem item;
  final String title;
  final String description;
  final ModuleArtKind art;

  /// Okunmamış / bekleyen sayı (0 = rozet yok); çekmecedeki rozetle aynı kaynaktan.
  final int badge;

  /// Rozetin ekran okuyucu sözcüğü ("3 okunmamış").
  final String badgeNoun;

  /// Ekran okuyucu etiketi: başlık + (varsa) rozet.
  String get semanticLabel => badge > 0 ? '$title, $badge $badgeNoun' : title;
}

/// Vitrin modeli: ana ızgara kartları ve ikincil satır.
@immutable
class ShowcaseModel {
  const ShowcaseModel({required this.grid, required this.secondary});

  final List<ShowcaseEntry> grid;
  final List<ShowcaseEntry> secondary;

  /// Her kartın menü öğesi (ızgara + ikincil), sıralı.
  List<SirketMenuItem> get items => <SirketMenuItem>[
        for (final e in grid) e.item,
        for (final e in secondary) e.item,
      ];
}

/// Yan menünün hesapladığı [menuItems] listesinden vitrin modelini üretir.
///
/// - "Panel" (vitrinin kendisi) kart olmaz.
/// - [showcaseSecondaryItems] ikincil satıra gider; kalanı ana ızgaradır.
/// - Izgara sırası: "Kapılar", sonra özellik modülleri, sonra yönetim araçları; her grupta menü sırası korunur.
/// - Listede olmayan öğeye kart ÜRETİLMEZ; görünürlük kuralı burada yoktur (tek kaynak yan menü listesidir).
ShowcaseModel buildShowcaseModel({
  required List<SirketMenuItem> menuItems,
  required UserRole role,
  Map<SirketMenuItem, int> badgeCounts = const <SirketMenuItem, int>{},
  Map<SirketMenuItem, String> badgeNouns = const <SirketMenuItem, String>{},
}) {
  ShowcaseEntry entry(SirketMenuItem item) => ShowcaseEntry(
        item: item,
        title: YanMenu.titleFor(item, role),
        description: showcaseDescription(item, role),
        art: moduleArtKindFor(item),
        badge: badgeCounts[item] ?? 0,
        badgeNoun: badgeNouns[item] ?? 'bekleyen',
      );

  final seen = <SirketMenuItem>{};
  final doors = <ShowcaseEntry>[];
  final features = <ShowcaseEntry>[];
  final tools = <ShowcaseEntry>[];
  final secondary = <ShowcaseEntry>[];
  for (final item in menuItems) {
    if (item == SirketMenuItem.dashboard || !seen.add(item)) continue;
    if (showcaseSecondaryItems.contains(item)) {
      secondary.add(entry(item));
    } else if (item == SirketMenuItem.kapilar) {
      doors.add(entry(item));
    } else if (_featureModuleItems.contains(item)) {
      features.add(entry(item));
    } else {
      tools.add(entry(item));
    }
  }
  return ShowcaseModel(grid: <ShowcaseEntry>[...doors, ...features, ...tools], secondary: secondary);
}

/// Yönetici vitrinindeki "Dikkat edilmesi gereken iş" satırı: bekleyen sayı + tek düğme (ilgili sayfaya gider).
@immutable
class ShowcaseFocusEntry {
  const ShowcaseFocusEntry({
    required this.item,
    required this.count,
    required this.text,
    required this.action,
  });

  final SirketMenuItem item;
  final int count;
  final String text;
  final String action;

  /// Ekran okuyucu etiketi: satır metni + düğme.
  String get semanticLabel => '$text. $action';
}

String _focusText(SirketMenuItem item, int n) {
  switch (item) {
    case SirketMenuItem.modulTalepleri:
      return '$n bekleyen modül talebi';
    case SirketMenuItem.siteBasvurulari:
      return '$n bekleyen site başvurusu';
    case SirketMenuItem.abonelikTalepleri:
      return '$n bekleyen abonelik talebi';
    case SirketMenuItem.siteOnayTalepleri:
      return '$n site onay talebi bekliyor';
    case SirketMenuItem.duyurular:
      return '$n okunmamış duyuru';
    case SirketMenuItem.ziyaretcilerim:
      return '$n görülmemiş ziyaretçi / kargo kaydı';
    default:
      return '$n bekleyen ${YanMenu.titleFor(item)} işlemi';
  }
}

String _focusAction(SirketMenuItem item) {
  switch (item) {
    case SirketMenuItem.duyurular:
      return 'Oku';
    case SirketMenuItem.ziyaretcilerim:
      return 'Gör';
    default:
      return 'İncele';
  }
}

/// Yönetici vitrininin odak barı satırları: çekmecedeki rozet sayıları ([badgeCounts]) SIFIRDAN BÜYÜK olan ve menüde
/// görünen ([menuItems]) öğeler, menü sırasıyla. Yeni veri kaynağı yoktur: yalnız uygulamada zaten hesaplanan sayılar.
/// Hiç satır yoksa bar çizilmez.
List<ShowcaseFocusEntry> buildFocusEntries({
  required List<SirketMenuItem> menuItems,
  required Map<SirketMenuItem, int> badgeCounts,
}) {
  return <ShowcaseFocusEntry>[
    for (final item in menuItems)
      if ((badgeCounts[item] ?? 0) > 0 && item != SirketMenuItem.dashboard)
        ShowcaseFocusEntry(
          item: item,
          count: badgeCounts[item]!,
          text: _focusText(item, badgeCounts[item]!),
          action: _focusAction(item),
        ),
  ];
}

/// Izgara sütun sayısı: telefonda 2, geniş ekranda 3-4; büyük yazı ölçeğinde sütun azalır (kart başlığı kırılmasın).
///
/// [width] ızgaranın kullanılabilir genişliği (dp), [textScale] yazı ölçeği (1,0 = normal).
int showcaseColumns(double width, double textScale) {
  final cap = width < 600 ? 2 : (width < 900 ? 3 : 4);
  final scale = textScale < 1 ? 1.0 : textScale;
  final minTile = 130 * (1 + (scale - 1) * 0.6);
  final fit = (width / minTile).floor();
  return fit.clamp(1, cap);
}

/// Sakin vitrinindeki borç özeti ([MyFinance] içinden). İki hesap (İP-1A): YALNIZ kişinin KENDİ hesabı sayılır (malik ->
/// ev sahibi hesabı, kiracı -> kiracı hesabı); borç sorumlusu "malik ve kiracı" olan dairede malike gösterilen salt okunur
/// kiracı hesabı tutarı vitrine EKLENMEZ.
@immutable
class DebtSummary {
  const DebtSummary({
    required this.debtMinor,
    required this.creditMinor,
    required this.overdueMinor,
    this.nextDue,
    this.siteName = '',
    this.apartmentTitle = '',
    this.accountLabel = '',
  });

  /// Tek daire varsa kişinin kendi hesabının adı ("Kiracı hesabı"); eski sunucuda ya da birden çok dairede boş.
  final String accountLabel;

  /// Toplam borç (pozitif büyüklük; yalnız borçlu daireler).
  final int debtMinor;

  /// Toplam alacak (pozitif büyüklük).
  final int creditMinor;

  /// Vadesi geçen toplam (borçlu dairelerde).
  final int overdueMinor;

  /// Borçlu dairelerin en yakın vadesi.
  final DateTime? nextDue;

  /// Tek daire varsa site adı / daire başlığı (birden çok dairede boş).
  final String siteName;
  final String apartmentTitle;

  bool get hasDebt => debtMinor > 0;
  bool get hasCredit => creditMinor > 0;
}

/// [finance] içindeki daire bakiyelerinden özet. Boş liste, "borç yok" DEMEZ: çağıran yalnız sunucu yanıtı geldiyse
/// çağırır; yanıt yoksa borç kartı hiç çizilmez.
DebtSummary summarizeMyFinance(MyFinance finance) {
  var debt = 0;
  var credit = 0;
  var overdue = 0;
  DateTime? next;
  for (final item in finance.items) {
    // Kendi hesabı (eski alanlar): salt okunur görünümler ([MyFinanceApartment.readOnlyAccounts]) sayılmaz.
    final own = item.ownAccount;
    if (own.balanceMinor > 0) {
      debt += own.balanceMinor;
      overdue += (own.overdueMinor ?? 0) > 0 ? own.overdueMinor! : 0;
      final due = own.nextDueDate;
      if (due != null && (next == null || due.isBefore(next))) next = due;
    } else if (own.balanceMinor < 0) {
      credit += -own.balanceMinor;
    }
  }
  final single = finance.items.length == 1 ? finance.items.first : null;
  return DebtSummary(
    debtMinor: debt,
    creditMinor: credit,
    overdueMinor: overdue,
    nextDue: next,
    siteName: single?.siteName.trim() ?? '',
    apartmentTitle: single == null ? '' : crmApartmentTitle(single.blockName, single.label),
    accountLabel: single?.accountParty?.label ?? '',
  );
}
