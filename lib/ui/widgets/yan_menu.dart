import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/brand/gude_logo_animated.dart';
import 'package:site_kapi_kontrol/config/app_config.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Çekmecede "Panel"in hemen altına eklenen ek eylem (sayfa değiştirmez; dokununca [onTap] çalışır).
///
/// Sade daire sakini ekranında ana ekrandan kaldırılan komutlar (kapıya QR göster, kapı ekranından
/// QR oku, misafir geçişi, sesli komut) böyle toplanır. [onTap] çekmeceyi kapatmayı kendisi yapar
/// (diğer menü öğeleriyle aynı: `Navigator.pop`).
class YanMenuAction {
  const YanMenuAction({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
}

enum SirketMenuItem {
  dashboard,
  profilim,
  ellerSerbest,
  abonelikTalepleri,
  siteOnayTalepleri,
  kullaniciYonetimi,
  superUserYonetimi,
  siteYoneticileriYonetimi,
  daireKullanicilariYonetimi,
  siteler,
  katilimVeKurulum,
  cihazEkle,
  kayitliCihazlar,
  bluetoothWifiKur,

  /// Platform modül sistemi: site başına modül açma/kapama (süper kullanıcı + site yöneticisi).
  moduller,

  /// Platform modül sistemi: denetim kaydı (yalnız süper kullanıcı).
  denetimKaydi,

  /// Platform modül sistemi Faz 1.1: site yöneticilerinin modül talepleri (yalnız süper kullanıcı;
  /// bekleyen sayısı rozetle gösterilir).
  modulTalepleri,

  /// Platform Faz 2a: Kişi ve Daire Kayıtları (Kişiler | Daireler | Araçlar). Site yöneticisi (yönetici
  /// modunda) ve süper kullanıcı için rol listesindedir; kurul üyesi için [YanMenu.additionalItems]
  /// ile eklenir (salt okunur). Görevli (STAFF) için yoktur.
  kisiler,

  /// Platform Faz 3a: Duyurular. Rol listesinde YOKTUR; alıcısı olabilecek rollere (daire sakini,
  /// yönetici / süper kullanıcı, kurul üyesi) [YanMenu.additionalItems] ile eklenir ("Kişiler"in hemen
  /// altına). Yönetici: duyuru yönetimi; sakin: gelen kutusu (okunmamış sayısı rozetle). Görevli
  /// (STAFF) ve bireysel kullanıcı için yoktur.
  duyurular,

  /// Site başvuruları (site yöneticisi olma): bireysel kullanıcıların site kurma başvurularını inceleyen
  /// süper kullanıcı ekranı (yalnız süper kullanıcı; bekleyen sayısı rozetle gösterilir). "Abonelik
  /// Talepleri"nden (site yöneticisi KAYDI onayı) farklıdır.
  siteBasvurulari,

  /// Platform Faz 4a: Finans (aidat, borç, tahsilat, dönemler). Rol listesinde YOKTUR; `finance` modülü AÇIK
  /// olan sitenin yöneticisine / süper kullanıcıya / kurul üyesine (salt okunur) [YanMenu.additionalItems] ile
  /// eklenir ("Duyurular"ın hemen altına). Modül kapalıyken ya da modül verisi yokken eklenmez.
  finans,

  /// Platform Faz 4a: Borcum (sakin). Rol listesinde YOKTUR; alıcısı olabilecek ve `finance` modülü AÇIK sitesi
  /// olan sakine [YanMenu.additionalItems] ile eklenir.
  borcum,

  /// Platform Faz 3b-A: Belgeler (dosya deposu). Rol listesinde YOKTUR; `documents` modülü AÇIK olan sitenin
  /// yöneticisine / süper kullanıcıya / kurul üyesine (salt okunur) ve kitlesinde belge olabilecek sakine
  /// [YanMenu.additionalItems] ile eklenir ("Finans" / "Borcum"un, yoksa "Duyurular"ın altına). Modül kapalıyken
  /// ya da modül verisi yokken eklenmez. Görevli (STAFF) için yoktur.
  belgeler,

  /// İş Takibi (arıza, bakım, talep) yönetim ekranı "Talepler". Rol listesinde YOKTUR; `work_tracking` modülü AÇIK
  /// olan sitenin yöneticisine / görevlisine / süper kullanıcıya / kurul üyesine (salt okunur)
  /// [YanMenu.additionalItems] ile eklenir ("Belgeler"in, yoksa üstteki öğelerin altına). Modül kapalıyken ya da
  /// modül verisi yokken eklenmez.
  talepler,

  /// İş Takibi sakin ekranı "Taleplerim". Rol listesinde YOKTUR; alıcısı olabilecek ve `work_tracking` modülü AÇIK
  /// sitesi olan sakine [YanMenu.additionalItems] ile eklenir ("Talepler"in altına).
  taleplerim,

  /// Rezervasyon ve Konsiyerj yönetim ekranı "Rezervasyonlar". Rol listesinde YOKTUR; `reservation` modülü AÇIK olan
  /// sitenin yöneticisine / görevlisine / süper kullanıcıya / kurul üyesine (salt okunur) [YanMenu.additionalItems]
  /// ile eklenir ("Taleplerim"in, yoksa üstteki öğelerin altına). Modül kapalıyken ya da modül verisi yokken eklenmez.
  rezervasyonlar,

  /// Rezervasyon ve Konsiyerj sakin ekranı "Rezervasyon". Rol listesinde YOKTUR; alıcısı olabilecek ve `reservation`
  /// modülü AÇIK sitesi olan sakine [YanMenu.additionalItems] ile eklenir ("Rezervasyonlar"ın altına).
  rezervasyon,

  /// Satışa hazırlık: Platform Ayarları (uygulama sürümü / bakım, destek iletişim, şirket ve yasal bilgiler).
  /// Yalnız süper kullanıcı (rol listesinde).
  platformAyarlari,

  /// Satışa hazırlık: İstemci Hataları (uygulamalardan gelen hata raporları). Yalnız süper kullanıcı.
  istemciHatalari,

  /// Anket ve Oylama yönetim ekranı "Anket ve Oylama". Rol listesinde YOKTUR; `survey` modülü AÇIK olan sitenin
  /// yöneticisine / süper kullanıcıya / kurul üyesine (salt okunur) [YanMenu.additionalItems] ile eklenir
  /// ("Rezervasyon"un, yoksa üstteki öğelerin altına). Modül kapalıyken ya da modül verisi yokken eklenmez.
  anketler,

  /// Anket ve Oylama sakin ekranı "Anketler". Rol listesinde YOKTUR; alıcısı olabilecek ve `survey` modülü AÇIK
  /// sitesi olan sakine [YanMenu.additionalItems] ile eklenir ("Anket ve Oylama"nın altına).
  anket,

  /// Ziyaretçi ve Kargo yönetim / görevli ekranı. Rol listesinde YOKTUR; `visitor_log` modülü AÇIK olan sitenin
  /// yöneticisine / görevlisine / süper kullanıcıya / kurul üyesine (salt okunur) [YanMenu.additionalItems] ile
  /// eklenir ("Rezervasyon"un, yoksa üstteki öğelerin altına). Modül kapalıyken ya da modül verisi yokken eklenmez.
  ziyaretciKayitlari,

  /// Ziyaretçi ve Kargo sakin ekranı "Ziyaretçilerim" (kendi dairesinin kayıtları; okunmamış sayısı rozetle). Rol
  /// listesinde YOKTUR; alıcısı olabilecek ve `visitor_log` modülü AÇIK sitesi olan sakine [YanMenu.additionalItems] ile
  /// eklenir (yönetim öğesinin altına). Başlığı yönetim öğesinden ("Ziyaretçi ve Kargo") AYRIDIR: kurul üyesinde ikisi
  /// birden görünür, aynı adlı iki öğe / kart olmasın.
  ziyaretcilerim,

  /// Firma ve Sözleşme Takibi ekranı "Sözleşmeler" (Sözleşmeler | Firmalar). Rol listesinde YOKTUR; `contracts` modülü
  /// AÇIK olan sitenin yöneticisine / süper kullanıcıya (yazar) ve kurul üyesine / görevlisine (salt okunur)
  /// [YanMenu.additionalItems] ile eklenir (Ziyaretçi ve Kargo / Anket / Rezervasyon ... öğelerinin altına). Sakin için
  /// yoktur; modül kapalıyken ya da modül verisi yokken eklenmez.
  sozlesmeler,

  /// Sayaç Okuma ve Faturalandırma ekranı "Sayaçlar" (Sayaçlar | Okuma aktar | Faturalandır). Rol listesinde YOKTUR; `metering`
  /// modülü AÇIK olan sitenin yöneticisine (yazar) ve kurul üyesine (salt okunur) [YanMenu.additionalItems] ile eklenir.
  sayaclar,

  /// Karar Defteri yönetim ekranı. Rol listesinde YOKTUR; `decision_book` modülü AÇIK olan sitenin yöneticisine /
  /// süper kullanıcıya (yazar, kesinleştirir) ve kurul üyesine (salt okunur) [YanMenu.additionalItems] ile eklenir
  /// (Sözleşmeler / Ziyaretçi ve Kargo / Anket / ... öğelerinin altına). Görevli için yoktur; modül kapalıyken ya da
  /// modül verisi yokken eklenmez.
  kararDefteri,

  /// Karar Defteri sakin ekranı "Kararlar" (sakinlere açık kesin kararlar). Rol listesinde YOKTUR; alıcısı olabilecek ve
  /// `decision_book` modülü AÇIK sitesi olan sakine [YanMenu.additionalItems] ile eklenir (yönetim öğesinin altına).
  kararlar,

  /// Rehber (sakin ve kurul/görevli): yönetim kadrosu ve faydalı telefonlar. Rol listesinde YOKTUR; `directory` modülü
  /// AÇIK sitesi olan ve bağı bulunan kullanıcıya [YanMenu.additionalItems] ile eklenir (İletişim grubu).
  rehber,
  /// İşletme Projesi (bütçe) yönetim ekranı. Rol listesinde YOKTUR; `budget` modülü AÇIK olan sitenin yöneticisine / süper
  /// kullanıcıya (yazar) ve kurul üyesine (salt okunur) [YanMenu.additionalItems] ile eklenir ("Finans"ın altına).
  isletmeProjesi,
  /// Komşu Panosu (`neighbor_board`): sakin ilan yazar / şikayet eder, yönetici onaylar / kaldırır. Rol listesinde YOKTUR;
  /// modül AÇIK sitesi olan yönetici ya da sakine [YanMenu.additionalItems] ile eklenir.
  komsuPanosu,
  /// Ödeme ve Kamera yönetim ekranı. Rol listesinde YOKTUR; `card_payments` ya da `plate_cameras` modülü AÇIK olan sitenin
  /// yöneticisine / kurul üyesine [YanMenu.additionalItems] ile eklenir. Sakin ve görevli için yoktur.
  odemeKamera,

  /// Kapılar: bugüne dek "Panel"in kendisi olan kapı paneli (durum, kapıyı aç; bireysel kullanıcıda kapılar, daireler,
  /// cihazlar). "Panel" artık modül vitrinidir; kapı paneli bu öğeyle bir dokunuş uzaktadır. Rol listesinde YOKTUR;
  /// [YanMenu.additionalItems] ile eklenir ve her zaman "Panel"in hemen altına gelir. Geçiş Kontrol (`door_control`)
  /// modülü kullanıcının bağlı olduğu TÜM sitelerde kapalıyken ve daire sakini rolünde kapı erişimi / kapısı olmayan
  /// hesapta (yalnız görevli / kurul / site üyeliği bağı) [YanMenu.hiddenItems] ile gizlenir (kapı kartı vitrinde de
  /// görünmez).
  kapilar,
}

/// İP-1D / G2 (karar kaydı 2026-10-21, sözleşme 2.4): çekmece menüsünün başlıkları. Çekmecede yalnız [drawerGroups]
/// (8 başlık) vardır ve kullanıcıya görünür öğesi olmayan başlık çizilmez. [ayarlar] çekmece başlığı DEĞİLDİR: o
/// gruptaki öğeler (profil, kullanıcılar, modüller, cihazlar, denetim kaydı, platform ayarları ...) sağ üstteki
/// dişliden açılan "Ayarlar" panelindedir ([YanMenuAyarlar]).
enum SirketMenuGroup {
  anaSayfa('Ana sayfa'),
  daireler('Daireler'),
  borclar('Borçlar'),
  tahsilat('Tahsilat'),
  giderler('Giderler'),
  iletisim('İletişim'),
  raporlar('Raporlar'),
  siteHizmetleri('Site hizmetleri'),
  ayarlar('Ayarlar');

  const SirketMenuGroup(this.title);

  /// Başlık metni: çekmecede bölüm başlığı, [ayarlar] için Ayarlar panelinin başlığı.
  final String title;

  /// Çekmecedeki 8 başlık, karar G2 sırasıyla (Yol Haritası PDF'teki 7 başlık + bizdeki ek modüller için "Site
  /// hizmetleri"). [ayarlar] burada yoktur.
  static const List<SirketMenuGroup> drawerGroups = <SirketMenuGroup>[
    anaSayfa,
    daireler,
    borclar,
    tahsilat,
    giderler,
    iletisim,
    raporlar,
    siteHizmetleri,
  ];
}

/// Menü öğesinin grubu (sözleşme 2.4). Yeni ekran eklemek = [SirketMenuItem] değeri + buradaki eşleme + görünürlük
/// kuralı (`HomePage._extraMenuItems` / `_canAccessMenu`); `switch` ifadesi eşlemesi yazılmamış öğeyi derletmez.
/// Tahsilat, Giderler ve Raporlar bugün boştur (başlıkları görünmez): dekont / banka dosyası Tahsilat'a, gider analizi
/// Giderler'e, faaliyet raporu / icra dökümü Raporlar'a eklenecektir. Talepler ve anketler yönetimle sakin arasındaki
/// yazışma kanalı olduğundan İletişim'dedir (karar G2'nin "Site hizmetleri" listesinde yoklar).
SirketMenuGroup menuGroupOf(SirketMenuItem item) => switch (item) {
      SirketMenuItem.dashboard => SirketMenuGroup.anaSayfa,
      SirketMenuItem.siteler ||
      SirketMenuItem.daireKullanicilariYonetimi ||
      SirketMenuItem.kisiler ||
      SirketMenuItem.katilimVeKurulum =>
        SirketMenuGroup.daireler,
      SirketMenuItem.finans ||
      SirketMenuItem.borcum ||
      SirketMenuItem.sayaclar => SirketMenuGroup.borclar,
      SirketMenuItem.duyurular ||
      SirketMenuItem.talepler ||
      SirketMenuItem.taleplerim ||
      SirketMenuItem.anketler ||
      SirketMenuItem.rehber ||
      SirketMenuItem.anket =>
      SirketMenuItem.anket ||
      SirketMenuItem.komsuPanosu =>
        SirketMenuGroup.iletisim,
      SirketMenuItem.kapilar ||
      SirketMenuItem.belgeler ||
      SirketMenuItem.rezervasyonlar ||
      SirketMenuItem.rezervasyon ||
      SirketMenuItem.ziyaretciKayitlari ||
      SirketMenuItem.ziyaretcilerim ||
      SirketMenuItem.sozlesmeler ||
      SirketMenuItem.kararDefteri ||
      SirketMenuItem.isletmeProjesi ||
      SirketMenuItem.kararlar =>
      SirketMenuItem.kararlar ||
      SirketMenuItem.odemeKamera =>
        SirketMenuGroup.siteHizmetleri,
      SirketMenuItem.profilim ||
      SirketMenuItem.ellerSerbest ||
      SirketMenuItem.abonelikTalepleri ||
      SirketMenuItem.siteOnayTalepleri ||
      SirketMenuItem.kullaniciYonetimi ||
      SirketMenuItem.superUserYonetimi ||
      SirketMenuItem.siteYoneticileriYonetimi ||
      SirketMenuItem.cihazEkle ||
      SirketMenuItem.kayitliCihazlar ||
      SirketMenuItem.bluetoothWifiKur ||
      SirketMenuItem.moduller ||
      SirketMenuItem.denetimKaydi ||
      SirketMenuItem.modulTalepleri ||
      SirketMenuItem.siteBasvurulari ||
      SirketMenuItem.platformAyarlari ||
      SirketMenuItem.istemciHatalari =>
        SirketMenuGroup.ayarlar,
    };

/// Çekmecenin bir bölümü: başlık + o başlıktaki görünür öğeler (menü sırasıyla). Boş bölüm üretilmez.
@immutable
class YanMenuSection {
  const YanMenuSection(this.group, this.items);

  final SirketMenuGroup group;
  final List<SirketMenuItem> items;
}

/// Site satırında listelenen site.
@immutable
class YanMenuSite {
  const YanMenuSite({required this.code, required this.name});

  final int code;
  final String name;

  /// Görünen ad; ad boşsa teknik site kodu gösterilmez.
  String get label => name.trim().isEmpty ? 'İsimsiz site' : name.trim();
}

/// İP-1D / G2: çekmecenin en üstündeki site satırının verisi. Tek sitede (ya da [onChanged] yokken) yalnız bilgi
/// satırıdır; [onChanged] verilmiş ve en az iki site varsa site seçicidir: "Tüm siteler" (null) ya da bir site.
@immutable
class YanMenuSiteContext {
  const YanMenuSiteContext({required this.sites, this.selectedCode, this.onChanged});

  final List<YanMenuSite> sites;

  /// Seçili site kodu; null = tüm siteler.
  final int? selectedCode;

  /// Seçim değişti (null = tüm siteler). null ise satır seçici değildir.
  final ValueChanged<int?>? onChanged;

  /// Satır dokunulabilir bir seçici mi?
  bool get canSelect => onChanged != null && sites.length >= 2;

  /// Satırda görünen metin: seçili site, tek site, "Tüm siteler (N)" ya da (seçim yokken) "ilk site +N site".
  String get label {
    for (final site in sites) {
      if (site.code == selectedCode) return site.label;
    }
    if (sites.isEmpty) return '';
    if (sites.length == 1) return sites.first.label;
    if (canSelect) return 'Tüm siteler (${sites.length})';
    return '${sites.first.label} +${sites.length - 1} site';
  }
}

class YanMenu extends StatelessWidget {
  const YanMenu({
    super.key,
    required this.fullName,
    required this.userEmail,
    required this.role,
    required this.selectedItem,
    required this.onSelect,
    required this.onLogout,
    this.isResidentMode = false,
    this.onToggleMode,
    this.canToggleMode = false,
    this.extraActions = const <YanMenuAction>[],
    this.hiddenItems = const <SirketMenuItem>{},
    this.badgeCounts = const <SirketMenuItem, int>{},
    this.badgeNouns = const <SirketMenuItem, String>{},
    this.additionalItems = const <SirketMenuItem>{},
    this.onOpenHelp,
    this.siteContext,
  });

  final String fullName;
  final String userEmail;
  final UserRole role;
  final SirketMenuItem selectedItem;
  final ValueChanged<SirketMenuItem> onSelect;
  final VoidCallback onLogout;
  final bool isResidentMode;
  final VoidCallback? onToggleMode;
  final bool canToggleMode;

  /// İP-1D: çekmecenin en üstündeki site satırı (başlığın hemen altında, mod geçişinin ÜSTÜNDE). null: satır yok.
  /// Seçim verilmişse ([YanMenuSiteContext.onChanged], en az iki site) satır site seçicidir.
  final YanMenuSiteContext? siteContext;

  /// "Kapılar"dan (o yoksa "Panel"den) hemen sonra gösterilen ek eylemler (varsayılan boş: menü eskisi gibidir).
  final List<YanMenuAction> extraActions;

  /// Menüden gizlenecek öğeler (varsayılan boş: menü eskisi gibidir). Platform modül sistemi:
  /// Geçiş Kontrol modülü kapalıyken kapıyla ilgili öğeler burada verilir. `HomePage._canAccessMenu`
  /// aynı kümeyi uygular.
  final Set<SirketMenuItem> hiddenItems;

  /// Öğe başına sayı rozeti (örn. bekleyen modül talebi sayısı). 0 ya da yok = rozet yok.
  final Map<SirketMenuItem, int> badgeCounts;

  /// Rozetin ekran okuyucu için sayıdan sonra okunan sözcüğü ("3 okunmamış"); verilmeyen öğede
  /// "bekleyen".
  final Map<SirketMenuItem, String> badgeNouns;

  /// Rolün kendi listesinde olmayan ama kullanıcıya açık ek öğeler (varsayılan boş: menü eskisi gibidir).
  /// Örn. yalnız kurul üyesi olan bir sakine "Kişiler" eklenir ("Site Yönetimi"nin, o yoksa "Panel"in
  /// altına); rol listesinde zaten varsa tekrarlanmaz.
  final Set<SirketMenuItem> additionalItems;

  /// Verilirse listenin sonunda ("Çıkış Yap"ın üstünde) "Yardım ve Destek" girişi gösterilir (varsayılan
  /// null: menü eskisi gibidir). Giriş bir sayfa seçimi DEĞİL, ayrı bir ekran açar; çağıran çekmeceyi kapatır.
  final VoidCallback? onOpenHelp;

  /// Bu yüksekliğin altında (yatay telefon, küçük pencere) başlık, liste ve sürüm satırı TEK
  /// kaydırma alanında akar: sabit başlık + sürüm satırı kısa ekranda listeye yer bırakmaz
  /// (en büyük yazıda 56 dp'ye düşerdi) ve Column ekran yüksekliğini aşıp taşabilirdi.
  static const double _compactHeight = 480;

  /// Çekmecede (ve Panel modül vitrininde) görünen öğelerin sıralı listesi: rol listesi + [additionalItems] - [hiddenItems].
  /// Çekmece de vitrin de AYNI hesaplanmış listeyi kullanır: görünürlük mantığı tek yerdedir, kapalı bir modül ikisinde
  /// de asla görünmez ("fail-closed"). "Panel" (dashboard) listededir; vitrin onu kart yapmaz.
  static List<SirketMenuItem> visibleItems({
    required UserRole role,
    bool isResidentMode = false,
    bool canToggleMode = false,
    Set<SirketMenuItem> additionalItems = const <SirketMenuItem>{},
    Set<SirketMenuItem> hiddenItems = const <SirketMenuItem>{},
  }) {
    final roleItems = _itemsForRole(
      role,
      isResidentMode: isResidentMode,
      canToggleMode: canToggleMode,
    );
    return _withExtras(roleItems, additionalItems)
        .where((item) => !hiddenItems.contains(item))
        .toList(growable: false);
  }

  /// Görünür öğelerin ([visibleItems]) çekmece bölümleri: [SirketMenuGroup.drawerGroups] sırasıyla, yalnız öğesi olan
  /// başlıklar; grup içinde menü sırası korunur. Ayarlar öğeleri burada YOKTUR ([settingsItems]).
  static List<YanMenuSection> drawerSections(List<SirketMenuItem> items) => <YanMenuSection>[
        for (final group in SirketMenuGroup.drawerGroups)
          if (items.any((item) => menuGroupOf(item) == group))
            YanMenuSection(group, <SirketMenuItem>[
              for (final item in items)
                if (menuGroupOf(item) == group) item,
            ]),
      ];

  /// Çekmecede çizilen öğeler, ekrandaki sırayla (bölümler art arda).
  static List<SirketMenuItem> drawerItems(List<SirketMenuItem> items) => <SirketMenuItem>[
        for (final section in drawerSections(items)) ...section.items,
      ];

  /// Sağ üstteki dişliden açılan "Ayarlar" panelinin öğeleri (menü sırasıyla). Çekmece + Ayarlar = görünür öğeler.
  static List<SirketMenuItem> settingsItems(List<SirketMenuItem> items) => <SirketMenuItem>[
        for (final item in items)
          if (menuGroupOf(item) == SirketMenuGroup.ayarlar) item,
      ];

  /// Öğenin çekmecedeki başlığı (vitrin kartı aynı metni kullanır).
  static String titleFor(SirketMenuItem item, [UserRole? role]) => _titleForItem(item, role);

  /// Öğenin çekmecedeki simgesi.
  static IconData iconFor(SirketMenuItem item) => _iconForItem(item);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tone = role.tone;
    final compact = MediaQuery.sizeOf(context).height < _compactHeight;
    final items = visibleItems(
      role: role,
      isResidentMode: isResidentMode,
      canToggleMode: canToggleMode,
      additionalItems: additionalItems,
      hiddenItems: hiddenItems,
    );
    // İP-1D / G2: öğeler başlıklar altında (boş başlık yok); Ayarlar öğeleri çekmecede değil dişli panelindedir.
    final sections = drawerSections(items);
    final drawerOrder = <SirketMenuItem>[for (final section in sections) ...section.items];
    // Ek eylemler (kapı komutları) "Kapılar"ın, o çekmecede yoksa "Panel"in hemen altına gelir.
    final extrasAnchor =
        drawerOrder.contains(SirketMenuItem.kapilar) ? SirketMenuItem.kapilar : SirketMenuItem.dashboard;
    final showToggle = canToggleMode && onToggleMode != null;
    final site = siteContext;

    // Çekmece açılışında ilk 8 satır sırayla belirir (StaggeredEntry): sıra ekrandaki sıradır (site satırı ve başlıklar
    // dahil).
    var entryIndex = 0;
    Widget entry(Key key, Widget child) => StaggeredEntry(key: key, index: entryIndex++, child: child);

    // Header Alanı (Rol Temalı Gradient)
    final header = _DrawerHeader(
      fullName: fullName,
      userEmail: userEmail,
      role: role,
      compact: compact,
    );

    final rows = <Widget>[
      // Site seçici en üstte (mod geçişinin de üstünde).
      if (site != null) entry(const ValueKey<String>('yan_menu_site_giris'), _SiteRow(site: site, tone: tone)),
      if (showToggle)
        entry(
          const ValueKey<String>('yan_menu_gecis'),
          _MenuTile(
            icon: isResidentMode ? Icons.admin_panel_settings_rounded : Icons.home_rounded,
            title: isResidentMode ? 'Yönetici Paneline Geç' : 'Sakin Moduna Geç',
            selected: false,
            tone: isResidentMode ? AppTone.primary : AppTone.success,
            onTap: onToggleMode!,
          ),
        ),
      if (site != null || showToggle) const _MenuDivider(),
    ];
    for (var s = 0; s < sections.length; s++) {
      final section = sections[s];
      rows.add(
        entry(
          ValueKey<String>('yan_menu_grup_${section.group.name}'),
          _GroupHeader(title: section.group.title, first: s == 0),
        ),
      );
      for (final item in section.items) {
        rows.add(
          entry(
            ValueKey<SirketMenuItem>(item),
            _MenuTile(
              icon: _iconForItem(item),
              title: _titleForItem(item, role),
              selected: selectedItem == item,
              tone: tone,
              badge: badgeCounts[item] ?? 0,
              badgeNoun: badgeNouns[item] ?? 'bekleyen',
              onTap: () => onSelect(item),
            ),
          ),
        );
        if (item != extrasAnchor) continue;
        // Ek eylemler "Kapılar"ın (o yoksa "Panel"in) hemen altında.
        for (var k = 0; k < extraActions.length; k++) {
          rows.add(
            entry(
              ValueKey<String>('yan_menu_ek_$k'),
              _MenuTile(
                icon: extraActions[k].icon,
                title: extraActions[k].title,
                selected: false,
                tone: tone,
                onTap: extraActions[k].onTap,
              ),
            ),
          );
        }
      }
    }
    if (onOpenHelp != null) {
      rows.add(
        entry(
          const ValueKey<String>('yan_menu_yardim'),
          _MenuTile(
            icon: Icons.help_outline_rounded,
            title: 'Yardım ve Destek',
            selected: false,
            tone: tone,
            onTap: onOpenHelp!,
          ),
        ),
      );
    }
    rows
      ..add(const _MenuDivider())
      ..add(
        entry(
          const ValueKey<String>('yan_menu_cikis'),
          _MenuTile(
            icon: Icons.logout_rounded,
            title: 'Çıkış Yap',
            selected: false,
            tone: AppTone.danger,
            onTap: onLogout,
          ),
        ),
      );

    // Menü Öğeleri Listesi
    final menuList = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);

    // Alt Sürüm Bilgisi
    final version = Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Center(
        child: Text(
          AppConfig.versionDisplay,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: p.textMuted,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );

    const listPadding = EdgeInsets.symmetric(vertical: 12, horizontal: 10);

    // Yüzey rengi AppTheme.drawerTheme'den gelir (açık beyaz, koyu #0F172A: eski değerlerle aynı).
    return Drawer(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(AppRadius.xl),
          bottomRight: Radius.circular(AppRadius.xl),
        ),
      ),
      child: compact
          ? SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  Padding(padding: listPadding, child: menuList),
                  version,
                ],
              ),
            )
          : Column(
              children: [
                header,
                // Liste kısa (en çok 15 satır) ve öğeler State taşır (giriş animasyonu): tembel
                // ListView yerine SingleChildScrollView; kaydırılıp dönülünce animasyon yinelenmez.
                Expanded(
                  child: SingleChildScrollView(
                    padding: listPadding,
                    child: menuList,
                  ),
                ),
                version,
              ],
            ),
    );
  }
}

/// İP-1D / G2: sağ üstteki dişliden açılan "Ayarlar" paneli (`Scaffold.endDrawer`). Öğeler çekmeceyle AYNI görünürlük
/// kuralından gelir ([YanMenu.visibleItems] içinden [SirketMenuGroup.ayarlar] grubundakiler, menü sırasıyla): kapalı /
/// yetkisiz öğe burada da yoktur. Öğe bileşeni, rozet ve seçili hap çekmeceyle aynıdır. [extraActions] sayfa seçmeyen
/// ayar eylemleridir (örn. "Masaüstüne Widget Ekle"); listenin sonunda durur. Dokunulan öğe için çekmeceyi kapatmak
/// çağıranın işidir (çekmecedeki gibi).
class YanMenuAyarlar extends StatelessWidget {
  const YanMenuAyarlar({
    super.key,
    required this.role,
    required this.selectedItem,
    required this.onSelect,
    this.isResidentMode = false,
    this.canToggleMode = false,
    this.additionalItems = const <SirketMenuItem>{},
    this.hiddenItems = const <SirketMenuItem>{},
    this.badgeCounts = const <SirketMenuItem, int>{},
    this.badgeNouns = const <SirketMenuItem, String>{},
    this.extraActions = const <YanMenuAction>[],
  });

  final UserRole role;
  final SirketMenuItem selectedItem;
  final ValueChanged<SirketMenuItem> onSelect;
  final bool isResidentMode;
  final bool canToggleMode;
  final Set<SirketMenuItem> additionalItems;
  final Set<SirketMenuItem> hiddenItems;
  final Map<SirketMenuItem, int> badgeCounts;
  final Map<SirketMenuItem, String> badgeNouns;
  final List<YanMenuAction> extraActions;

  /// Paneldeki öğeler (menü sırasıyla).
  static List<SirketMenuItem> itemsFor({
    required UserRole role,
    bool isResidentMode = false,
    bool canToggleMode = false,
    Set<SirketMenuItem> additionalItems = const <SirketMenuItem>{},
    Set<SirketMenuItem> hiddenItems = const <SirketMenuItem>{},
  }) =>
      YanMenu.settingsItems(
        YanMenu.visibleItems(
          role: role,
          isResidentMode: isResidentMode,
          canToggleMode: canToggleMode,
          additionalItems: additionalItems,
          hiddenItems: hiddenItems,
        ),
      );

  /// Dişli düğmesinin rozeti: [items] içindeki AYAR öğelerinin rozet toplamı (bekleyen sayılar dişlinin arkasında
  /// kaybolmasın). Çekmecedeki öğelerin rozetleri sayılmaz (onlar çekmecede görünür).
  static int badgeTotal(List<SirketMenuItem> items, Map<SirketMenuItem, int> badgeCounts) {
    var total = 0;
    for (final item in YanMenu.settingsItems(items)) {
      final count = badgeCounts[item] ?? 0;
      if (count > 0) total += count;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final tone = role.tone;
    final compact = MediaQuery.sizeOf(context).height < YanMenu._compactHeight;
    final items = itemsFor(
      role: role,
      isResidentMode: isResidentMode,
      canToggleMode: canToggleMode,
      additionalItems: additionalItems,
      hiddenItems: hiddenItems,
    );
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, item) in items.indexed)
          StaggeredEntry(
            key: ValueKey<SirketMenuItem>(item),
            index: i,
            child: _MenuTile(
              icon: _iconForItem(item),
              title: _titleForItem(item, role),
              selected: selectedItem == item,
              tone: tone,
              badge: badgeCounts[item] ?? 0,
              badgeNoun: badgeNouns[item] ?? 'bekleyen',
              onTap: () => onSelect(item),
            ),
          ),
        if (extraActions.isNotEmpty && items.isNotEmpty) const _MenuDivider(),
        for (var k = 0; k < extraActions.length; k++)
          StaggeredEntry(
            key: ValueKey<String>('yan_menu_ayar_ek_$k'),
            index: items.length + k,
            child: _MenuTile(
              icon: extraActions[k].icon,
              title: extraActions[k].title,
              selected: false,
              tone: tone,
              onTap: extraActions[k].onTap,
            ),
          ),
      ],
    );
    final header = _SettingsHeader(tone: tone, compact: compact);
    const listPadding = EdgeInsets.symmetric(vertical: 12, horizontal: 10);
    return Drawer(
      semanticLabel: SirketMenuGroup.ayarlar.title,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppRadius.xl),
          bottomLeft: Radius.circular(AppRadius.xl),
        ),
      ),
      child: compact
          ? SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [header, Padding(padding: listPadding, child: list)],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                Expanded(child: SingleChildScrollView(padding: listPadding, child: list)),
              ],
            ),
    );
  }
}

/// Ayarlar panelinin başlığı: dişli simgesi + "Ayarlar" (başlık düğümü). Durum çubuğunun altında başlar.
class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({required this.tone, required this.compact});

  final AppTone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SafeArea(
      bottom: false,
      left: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(AppSpace.xl, compact ? AppSpace.md : AppSpace.xl, AppSpace.lg, AppSpace.sm),
        child: Row(
          children: [
            ExcludeSemantics(child: Icon(Icons.settings_rounded, size: 24, color: tone.ink(p))),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  SirketMenuGroup.ayarlar.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: p.text),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Çekmece bölüm başlığı (İP-1D / G2): küçük, kalın, sessiz renk (metin >= 4,5:1: palet sözleşmesi); başlık düğümü.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.first});

  final String title;

  /// İlk başlığın üst boşluğu küçüktür.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = Theme.of(context).textTheme.labelLarge ?? Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpace.lg, first ? AppSpace.xs : AppSpace.md, AppSpace.lg, AppSpace.xs),
      child: Semantics(
        header: true,
        child: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: style?.copyWith(color: p.textMuted, fontWeight: FontWeight.w700, letterSpacing: 0.3),
        ),
      ),
    );
  }
}

/// Site seçimi: seçenek kutusundan dönen değer (null = "Tüm siteler"; kutu kapandıysa seçim yok).
class _SiteChoice {
  const _SiteChoice(this.code);

  final int? code;
}

/// Çekmecenin en üstündeki site satırı (İP-1D / G2 "site seçici en üstte"). Seçici değilse yalnız bilgi verir (dokunma
/// eylemi yok); seçiciyse dokununca alt sayfada "Tüm siteler" ve siteler listelenir. Dokunma hedefi >= 48 dp; ekran
/// okuyucu tek düğüm okur ("Site: Güneş Sitesi").
class _SiteRow extends StatelessWidget {
  const _SiteRow({required this.site, required this.tone});

  final YanMenuSiteContext site;
  final AppTone tone;

  Future<void> _pick(BuildContext context) async {
    final choice = await showModalBottomSheet<_SiteChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _SitePickerSheet(site: site, tone: tone),
    );
    if (choice == null || choice.code == site.selectedCode) return;
    site.onChanged?.call(choice.code);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final interactive = site.canSelect;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
      child: Row(
        children: [
          Icon(Icons.location_city_rounded, size: 22, color: tone.ink(p)),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Site', maxLines: 1, style: th.bodySmall?.copyWith(color: p.textMuted)),
                Text(
                  site.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: th.titleSmall?.copyWith(color: p.text, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          if (interactive) ...[
            const SizedBox(width: AppSpace.sm),
            Icon(Icons.unfold_more_rounded, size: 22, color: p.textSecondary),
          ],
        ],
      ),
    );
    return Semantics(
      key: const ValueKey<String>('yan_menu_site'),
      container: true,
      button: interactive,
      label: 'Site: ${site.label}',
      hint: interactive ? 'Siteyi değiştirmek için dokunun' : null,
      onTap: interactive ? () => _pick(context) : null,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: interactive
            ? Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onTap: () => _pick(context),
                  child: content,
                ),
              )
            : content,
      ),
    );
  }
}

/// Site seçenekleri (alt sayfa): "Tüm siteler" + siteler; seçili olan işaretli. Büyük yazıda kaydırılır.
class _SitePickerSheet extends StatelessWidget {
  const _SitePickerSheet({required this.site, required this.tone});

  final YanMenuSiteContext site;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final options = <(int?, String)>[
      (null, 'Tüm siteler'),
      for (final s in site.sites) (s.code, s.label),
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.sm),
              child: Semantics(
                header: true,
                child: Text('Site seçin', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: p.text)),
              ),
            ),
            for (final (code, label) in options)
              ListTile(
                key: ValueKey<String>('yan_menu_site_secenek_${code ?? 'tum'}'),
                leading: Icon(
                  code == null ? Icons.domain_rounded : Icons.location_city_rounded,
                  color: tone.ink(p),
                ),
                title: Text(label, maxLines: 3, overflow: TextOverflow.ellipsis),
                selected: code == site.selectedCode,
                selectedColor: tone.ink(p),
                trailing: code == site.selectedCode ? Icon(Icons.check_rounded, color: tone.ink(p)) : null,
                onTap: () => Navigator.of(context).pop(_SiteChoice(code)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Çekmece başlığı: rol gradyanı (beyaz metin >= 4,5:1), düz beyaz logo halkası, rol rozeti,
/// ad (en çok 2 satır) ve e-posta. Kısa ekranda ([compact]) üst boşluk azalır.
class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({
    required this.fullName,
    required this.userEmail,
    required this.role,
    required this.compact,
  });

  final String fullName;
  final String userEmail;
  final UserRole role;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, compact ? AppSpace.xl : 56, 20, AppSpace.xl),
      decoration: BoxDecoration(
        gradient: role.tone.gradient,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(AppRadius.xl),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Logo halkası: düz beyaz, gölge yok.
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: const CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.white,
                  // Güde Teknoloji yaprak işareti (vektör, bitmap çözümü yok). Zemin hep beyaz plaka olduğundan
                  // parıltı koyu temada bile açık zemin şiddetinde; başlıkta dekoratif (anlamsal etiket yok).
                  child: AnimatedGudeLeafMark(
                    size: 52,
                    padding: 0.1,
                    semanticLabel: null,
                    darkBackground: false,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      // Gradyan üstünde beyaz %22 zemin beyaz metni ~3,5:1'e düşürür; koyu perde
                      // rozet metnini >= 4,5:1 tutar.
                      color: Colors.black.withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      role.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          Text(
            fullName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            userEmail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ek öğeleri rol listesine yerleştirir: "Site Yönetimi" varsa hemen altına (yönetici sırasıyla tutarlı),
/// yoksa "Panel"in hemen altına; ikisi de yoksa sona. "Duyurular" varsa "Kişiler"in hemen altına gelir.
/// "Finans" ve "Borcum" "Duyurular"ın (yoksa "Kişiler"in) altına, "Borcum" varsa "Finans"ın altına gelir.
/// Rol listesinde zaten olan öğe tekrarlanmaz. Birden çok ek öğe numaralandırma sırasıyla eklenir.
List<SirketMenuItem> _withExtras(
  List<SirketMenuItem> roleItems,
  Set<SirketMenuItem> extras,
) {
  final missing = <SirketMenuItem>[
    for (final item in SirketMenuItem.values)
      if (extras.contains(item) && !roleItems.contains(item)) item,
  ];
  if (missing.isEmpty) return roleItems;
  final result = List<SirketMenuItem>.of(roleItems);
  for (final extra in missing) {
    var anchor = extra == SirketMenuItem.duyurular
        ? result.indexOf(SirketMenuItem.kisiler)
        : -1;
    // "Finans" / "Borcum" "Duyurular"ın (yoksa "Kişiler"in) altına gelir; "Borcum" varsa "Finans"ın altına.
    if (extra == SirketMenuItem.finans || extra == SirketMenuItem.borcum) {
      if (extra == SirketMenuItem.borcum) anchor = result.indexOf(SirketMenuItem.finans);
      if (anchor < 0) anchor = result.indexOf(SirketMenuItem.duyurular);
      if (anchor < 0) anchor = result.indexOf(SirketMenuItem.kisiler);
    }
    // "Belgeler" "Borcum" / "Finans" / "Duyurular" / "Kişiler" sırasıyla ilk bulunanın altına gelir.
    if (extra == SirketMenuItem.belgeler) {
      for (final above in const <SirketMenuItem>[
        SirketMenuItem.borcum,
        SirketMenuItem.finans,
        SirketMenuItem.duyurular,
        SirketMenuItem.kisiler,
      ]) {
        anchor = result.indexOf(above);
        if (anchor >= 0) break;
      }
    }
    // "Talepler" / "Taleplerim" "Belgeler" / "Borcum" / "Finans" / "Duyurular" / "Kişiler" sırasıyla ilk bulunanın
    // altına gelir; "Taleplerim" varsa "Talepler"in altına.
    if (extra == SirketMenuItem.talepler || extra == SirketMenuItem.taleplerim) {
      for (final above in <SirketMenuItem>[
        if (extra == SirketMenuItem.taleplerim) SirketMenuItem.talepler,
        SirketMenuItem.belgeler,
        SirketMenuItem.borcum,
        SirketMenuItem.finans,
        SirketMenuItem.duyurular,
        SirketMenuItem.kisiler,
      ]) {
        anchor = result.indexOf(above);
        if (anchor >= 0) break;
      }
    }
    // "Rezervasyonlar" / "Rezervasyon" "Taleplerim" / "Talepler" / "Belgeler" / "Borcum" / "Finans" / "Duyurular" /
    // "Kişiler" sırasıyla ilk bulunanın altına gelir; "Rezervasyon" varsa "Rezervasyonlar"ın altına.
    if (extra == SirketMenuItem.rezervasyonlar || extra == SirketMenuItem.rezervasyon) {
      for (final above in <SirketMenuItem>[
        if (extra == SirketMenuItem.rezervasyon) SirketMenuItem.rezervasyonlar,
        SirketMenuItem.taleplerim,
        SirketMenuItem.talepler,
        SirketMenuItem.belgeler,
        SirketMenuItem.borcum,
        SirketMenuItem.finans,
        SirketMenuItem.duyurular,
        SirketMenuItem.kisiler,
      ]) {
        anchor = result.indexOf(above);
        if (anchor >= 0) break;
      }
    }
    // "Anket ve Oylama" / "Anketler": "Rezervasyon" / "Rezervasyonlar" / ... sırasıyla ilk bulunanın altına; "Anketler"
    // varsa "Anket ve Oylama"nın altına.
    if (extra == SirketMenuItem.anketler || extra == SirketMenuItem.anket) {
      for (final above in <SirketMenuItem>[
        if (extra == SirketMenuItem.anket) SirketMenuItem.anketler,
        SirketMenuItem.rezervasyon,
        SirketMenuItem.rezervasyonlar,
        SirketMenuItem.taleplerim,
        SirketMenuItem.talepler,
        SirketMenuItem.belgeler,
        SirketMenuItem.borcum,
        SirketMenuItem.finans,
        SirketMenuItem.duyurular,
        SirketMenuItem.kisiler,
      ]) {
        anchor = result.indexOf(above);
        if (anchor >= 0) break;
      }
    }
    // "Ziyaretçi ve Kargo" (yönetim / görevli ve sakin) "Rezervasyon" / "Rezervasyonlar" / "Taleplerim" / "Talepler" /
    // "Belgeler" / "Borcum" / "Finans" / "Duyurular" / "Kişiler" sırasıyla ilk bulunanın altına gelir; sakin öğesi
    // varsa yönetim öğesinin altına.
    if (extra == SirketMenuItem.ziyaretciKayitlari || extra == SirketMenuItem.ziyaretcilerim) {
      for (final above in <SirketMenuItem>[
        if (extra == SirketMenuItem.ziyaretcilerim) SirketMenuItem.ziyaretciKayitlari,
        SirketMenuItem.rezervasyon,
        SirketMenuItem.rezervasyonlar,
        SirketMenuItem.taleplerim,
        SirketMenuItem.talepler,
        SirketMenuItem.belgeler,
        SirketMenuItem.borcum,
        SirketMenuItem.finans,
        SirketMenuItem.duyurular,
        SirketMenuItem.kisiler,
      ]) {
        anchor = result.indexOf(above);
        if (anchor >= 0) break;
      }
    }
    // "Sözleşmeler": "Ziyaretçi ve Kargo" / "Anket" / "Rezervasyon" / ... / "Kişiler" sırasıyla ilk bulunanın altına.
    if (extra == SirketMenuItem.sozlesmeler) {
      for (final above in const <SirketMenuItem>[
        SirketMenuItem.ziyaretcilerim,
        SirketMenuItem.ziyaretciKayitlari,
        SirketMenuItem.anket,
        SirketMenuItem.anketler,
        SirketMenuItem.rezervasyon,
        SirketMenuItem.rezervasyonlar,
        SirketMenuItem.taleplerim,
        SirketMenuItem.talepler,
        SirketMenuItem.belgeler,
        SirketMenuItem.borcum,
        SirketMenuItem.finans,
        SirketMenuItem.duyurular,
        SirketMenuItem.kisiler,
      ]) {
        anchor = result.indexOf(above);
        if (anchor >= 0) break;
      }
    }
    // "Karar Defteri" (yönetim) / "Kararlar" (sakin): "Sözleşmeler" / "Ziyaretçi ve Kargo" / "Anket" / ... / "Kişiler"
    // sırasıyla ilk bulunanın altına; "Kararlar" varsa "Karar Defteri"nin altına.
    if (extra == SirketMenuItem.kararDefteri || extra == SirketMenuItem.kararlar) {
      for (final above in <SirketMenuItem>[
        if (extra == SirketMenuItem.kararlar) SirketMenuItem.kararDefteri,
        SirketMenuItem.sozlesmeler,
        SirketMenuItem.ziyaretcilerim,
        SirketMenuItem.ziyaretciKayitlari,
        SirketMenuItem.anket,
        SirketMenuItem.anketler,
        SirketMenuItem.rezervasyon,
        SirketMenuItem.rezervasyonlar,
        SirketMenuItem.taleplerim,
        SirketMenuItem.talepler,
        SirketMenuItem.belgeler,
        SirketMenuItem.borcum,
        SirketMenuItem.finans,
        SirketMenuItem.duyurular,
        SirketMenuItem.kisiler,
      ]) {
        anchor = result.indexOf(above);
        if (anchor >= 0) break;
      }
    }
    // "Rehber": Anket / Duyurular öğesinin altına (İletişim grubu).
    if (extra == SirketMenuItem.rehber) {
      for (final above in <SirketMenuItem>[SirketMenuItem.anket, SirketMenuItem.anketler, SirketMenuItem.duyurular]) {
    // "İşletme Projesi": "Finans" / "Duyurular" / "Kişiler" sırasıyla ilk bulunanın altına.
    if (extra == SirketMenuItem.isletmeProjesi) {
      for (final above in const <SirketMenuItem>[SirketMenuItem.finans, SirketMenuItem.duyurular, SirketMenuItem.kisiler]) {
    // "Ödeme ve Kamera": "Karar Defteri" / "Sözleşmeler" / ... / "Kişiler" sırasıyla ilk bulunanın altına.
    if (extra == SirketMenuItem.odemeKamera) {
      for (final above in const <SirketMenuItem>[
        SirketMenuItem.kararDefteri,
        SirketMenuItem.sozlesmeler,
        SirketMenuItem.ziyaretciKayitlari,
        SirketMenuItem.anketler,
        SirketMenuItem.rezervasyonlar,
        SirketMenuItem.talepler,
        SirketMenuItem.belgeler,
        SirketMenuItem.finans,
        SirketMenuItem.duyurular,
        SirketMenuItem.kisiler,
      ]) {
        anchor = result.indexOf(above);
        if (anchor >= 0) break;
      }
    }
    // "Kapılar" her zaman "Panel"in hemen altındadır (kapı paneli bir dokunuş uzakta). Numaralandırmada en sonda
    // olduğundan öteki ek öğelerden SONRA eklenir ve "Panel"in altına, onların önüne girer.
    if (extra == SirketMenuItem.kapilar) anchor = result.indexOf(SirketMenuItem.dashboard);
    if (anchor < 0) anchor = result.indexOf(SirketMenuItem.siteler);
    if (anchor < 0) anchor = result.indexOf(SirketMenuItem.dashboard);
    result.insert(anchor < 0 ? result.length : anchor + 1, extra);
  }
  return result;
}

List<SirketMenuItem> _itemsForRole(
  UserRole role, {
  bool isResidentMode = false,
  bool canToggleMode = false,
}) {
  if (canToggleMode && !isResidentMode && (role == UserRole.individual || role == UserRole.apartmentOwner)) {
    return const [
      SirketMenuItem.dashboard,
      SirketMenuItem.profilim,
      SirketMenuItem.siteler,
      SirketMenuItem.kayitliCihazlar,
      SirketMenuItem.katilimVeKurulum,
      SirketMenuItem.bluetoothWifiKur,
    ];
  }
  switch (role) {
    case UserRole.superUser:
      return const [
        SirketMenuItem.dashboard,
        SirketMenuItem.profilim,
        SirketMenuItem.kullaniciYonetimi,
        SirketMenuItem.superUserYonetimi,
        SirketMenuItem.siteYoneticileriYonetimi,
        SirketMenuItem.daireKullanicilariYonetimi,
        SirketMenuItem.siteler,
        SirketMenuItem.kisiler,
        SirketMenuItem.moduller,
        SirketMenuItem.modulTalepleri,
        SirketMenuItem.siteBasvurulari,
        SirketMenuItem.katilimVeKurulum,
        SirketMenuItem.cihazEkle,
        SirketMenuItem.kayitliCihazlar,
        SirketMenuItem.bluetoothWifiKur,
        SirketMenuItem.denetimKaydi,
        SirketMenuItem.platformAyarlari,
        SirketMenuItem.istemciHatalari,
      ];
    case UserRole.siteManager:
      if (isResidentMode) {
        return const [
          SirketMenuItem.dashboard,
          SirketMenuItem.katilimVeKurulum,
          SirketMenuItem.profilim,
          SirketMenuItem.ellerSerbest,
        ];
      }
      return const [
        SirketMenuItem.dashboard,
        SirketMenuItem.profilim,
        SirketMenuItem.siteler,
        SirketMenuItem.kisiler,
        SirketMenuItem.moduller,
        SirketMenuItem.kayitliCihazlar,
        SirketMenuItem.katilimVeKurulum,
        SirketMenuItem.bluetoothWifiKur,
      ];
    case UserRole.apartmentOwner:
      return const [
        SirketMenuItem.dashboard,
        SirketMenuItem.katilimVeKurulum,
        SirketMenuItem.ellerSerbest,
        SirketMenuItem.profilim,
      ];
    case UserRole.individual:
      return const [
        SirketMenuItem.dashboard,
        SirketMenuItem.katilimVeKurulum,
        SirketMenuItem.profilim,
      ];
  }
}

String _titleForItem(SirketMenuItem item, [UserRole? role]) {
  switch (item) {
    case SirketMenuItem.dashboard:
      return 'Panel';
    case SirketMenuItem.profilim:
      return 'Profilim';
    case SirketMenuItem.ellerSerbest:
      return 'Eller Serbest & Kestirmeler';
    case SirketMenuItem.abonelikTalepleri:
      return 'Yeni Abonelik Talepleri';
    case SirketMenuItem.siteOnayTalepleri:
      return 'Site Onay Talepleri';
    case SirketMenuItem.kullaniciYonetimi:
      return 'Kullanıcı Yönetimi';
    case SirketMenuItem.superUserYonetimi:
      return 'Süper Kullanıcı Yönetimi';
    case SirketMenuItem.siteYoneticileriYonetimi:
      return 'Site Yöneticileri Yönetimi';
    case SirketMenuItem.daireKullanicilariYonetimi:
      return 'Daire Sakinleri';
    case SirketMenuItem.siteler:
      return 'Site Yönetimi';
    case SirketMenuItem.katilimVeKurulum:
      return 'Daireye Katıl & Cihaz Ekle';
    case SirketMenuItem.cihazEkle:
      if (role == UserRole.superUser) return 'Şirket Cihazı Kaydet';
      if (role == UserRole.individual) return 'Cihaz Ekle';
      return 'Cihaz Kaydet';
    case SirketMenuItem.kayitliCihazlar:
      if (role == UserRole.superUser) return 'Şirket Cihaz Envanteri';
      return 'Kayıtlı Cihazlar';
    case SirketMenuItem.bluetoothWifiKur:
      return 'Bluetooth ile Wi-Fi Kur';
    case SirketMenuItem.moduller:
      return 'Modüller';
    case SirketMenuItem.denetimKaydi:
      return 'Denetim Kaydı';
    case SirketMenuItem.modulTalepleri:
      return 'Modül Talepleri';
    case SirketMenuItem.kisiler:
      return 'Kişiler';
    case SirketMenuItem.duyurular:
      return 'Duyurular';
    case SirketMenuItem.siteBasvurulari:
      return 'Site Başvuruları';
    case SirketMenuItem.finans:
      return 'Finans';
    case SirketMenuItem.borcum:
      return 'Borcum';
    case SirketMenuItem.belgeler:
      return 'Belgeler';
    case SirketMenuItem.talepler:
      return 'Talepler';
    case SirketMenuItem.taleplerim:
      return 'Taleplerim';
    case SirketMenuItem.rezervasyonlar:
      return 'Rezervasyonlar';
    case SirketMenuItem.rezervasyon:
      return 'Rezervasyon';
    case SirketMenuItem.platformAyarlari:
      return 'Platform Ayarları';
    case SirketMenuItem.istemciHatalari:
      return 'İstemci Hataları';
    case SirketMenuItem.anketler:
      return 'Anket ve Oylama';
    case SirketMenuItem.anket:
      return 'Anketler';
    case SirketMenuItem.ziyaretciKayitlari:
      return 'Ziyaretçi ve Kargo';
    case SirketMenuItem.ziyaretcilerim:
      return 'Ziyaretçilerim';
    case SirketMenuItem.sozlesmeler:
      return 'Sözleşmeler';
    case SirketMenuItem.sayaclar:
      return 'Sayaçlar';
    case SirketMenuItem.kararDefteri:
      return 'Karar Defteri';
    case SirketMenuItem.kararlar:
      return 'Kararlar';
    case SirketMenuItem.rehber:
      return 'Rehber';
    case SirketMenuItem.isletmeProjesi:
      return 'İşletme Projesi';
    case SirketMenuItem.komsuPanosu:
      return 'Komşu Panosu';
    case SirketMenuItem.odemeKamera:
      return 'Ödeme ve Kamera';
    case SirketMenuItem.kapilar:
      return 'Kapılar';
  }
}

IconData _iconForItem(SirketMenuItem item) {
  switch (item) {
    case SirketMenuItem.dashboard:
      return Icons.grid_view_rounded;
    case SirketMenuItem.profilim:
      return Icons.account_circle_outlined;
    case SirketMenuItem.ellerSerbest:
      return Icons.directions_car_filled_rounded;
    case SirketMenuItem.abonelikTalepleri:
      return Icons.mark_email_unread_rounded;
    case SirketMenuItem.siteOnayTalepleri:
      return Icons.verified_user_rounded;
    case SirketMenuItem.kullaniciYonetimi:
      return Icons.manage_accounts_rounded;
    case SirketMenuItem.superUserYonetimi:
      return Icons.admin_panel_settings_rounded;
    case SirketMenuItem.siteYoneticileriYonetimi:
      return Icons.apartment_rounded;
    case SirketMenuItem.daireKullanicilariYonetimi:
      return Icons.groups_2_rounded;
    case SirketMenuItem.siteler:
      return Icons.apartment_rounded;
    case SirketMenuItem.katilimVeKurulum:
      return Icons.add_home_work_rounded;
    case SirketMenuItem.cihazEkle:
      return Icons.add_to_photos_rounded;
    case SirketMenuItem.kayitliCihazlar:
      return Icons.devices_other_rounded;
    case SirketMenuItem.bluetoothWifiKur:
      return Icons.bluetooth_searching_rounded;
    case SirketMenuItem.moduller:
      return Icons.extension_rounded;
    case SirketMenuItem.denetimKaydi:
      return Icons.fact_check_rounded;
    case SirketMenuItem.modulTalepleri:
      return Icons.inbox_rounded;
    case SirketMenuItem.kisiler:
      return Icons.contacts_rounded;
    case SirketMenuItem.duyurular:
      return Icons.campaign_rounded;
    case SirketMenuItem.siteBasvurulari:
      return Icons.domain_add_rounded;
    case SirketMenuItem.finans:
      return Icons.account_balance_wallet_rounded;
    case SirketMenuItem.borcum:
      return Icons.receipt_long_rounded;
    case SirketMenuItem.belgeler:
      return Icons.folder_rounded;
    case SirketMenuItem.talepler:
      return Icons.assignment_rounded;
    case SirketMenuItem.taleplerim:
      return Icons.build_circle_rounded;
    case SirketMenuItem.rezervasyonlar:
      return Icons.event_note_rounded;
    case SirketMenuItem.rezervasyon:
      return Icons.event_available_rounded;
    case SirketMenuItem.platformAyarlari:
      return Icons.tune_rounded;
    case SirketMenuItem.istemciHatalari:
      return Icons.bug_report_rounded;
    case SirketMenuItem.anketler:
      return Icons.poll_rounded;
    case SirketMenuItem.anket:
      return Icons.how_to_vote_rounded;
    case SirketMenuItem.ziyaretciKayitlari:
      return Icons.door_front_door_rounded;
    case SirketMenuItem.ziyaretcilerim:
      return Icons.local_shipping_rounded;
    case SirketMenuItem.sozlesmeler:
      return Icons.handshake_rounded;
    case SirketMenuItem.sayaclar:
      return Icons.speed_rounded;
    case SirketMenuItem.kararDefteri:
      return Icons.gavel_rounded;
    case SirketMenuItem.kararlar:
      return Icons.library_books_rounded;
    case SirketMenuItem.rehber:
      return Icons.contact_phone_rounded;
    case SirketMenuItem.isletmeProjesi:
      return Icons.account_balance_wallet_rounded;
    case SirketMenuItem.komsuPanosu:
      return Icons.forum_rounded;
    case SirketMenuItem.odemeKamera:
      return Icons.videocam_rounded;
    case SirketMenuItem.kapilar:
      return Icons.meeting_room_rounded;
  }
}

/// Menü öğesinin sağındaki sayı rozeti (örn. bekleyen modül talebi, okunmamış duyuru): tehlike tonunun
/// koyu ucu üstünde beyaz sayı (>= 4,5:1). 99'dan büyük sayılar "99+" yazılır. Ekran okuyucuya tek ifade
/// olarak okunur ("3 bekleyen" / "3 okunmamış"). Panel vitrinindeki kart rozetinin noktası da AYNI belirteçtir
/// ([AppTone.danger] `a`): aynı sayı iki yerde aynı renkte görünür.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, this.noun = 'bekleyen'});

  final int count;
  final String noun;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Semantics(
      label: '$count $noun',
      child: ExcludeSemantics(
        child: DecoratedBox(
          key: const ValueKey<String>('yan_menu_rozet'),
          decoration: BoxDecoration(
            color: AppTone.danger.a,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.sm,
              vertical: AppSpace.xs / 2,
            ),
            child: Text(
              label,
              maxLines: 1,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Menü grupları arasındaki ince ayırıcı.
class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpace.sm,
        horizontal: AppSpace.md,
      ),
      child: Divider(color: context.palette.border, height: 1),
    );
  }
}

/// Menü öğesi: `ListTile` (dokunma >= 48 dp). Seçili = ton zemini (hap) + ton mürekkebi (ikon/
/// başlık kalın) + sağda 4x22 dp çubuk (200 ms; hareket azaltmada anında).
///
/// Hap zemini `ListTile.selectedTileColor` ile DEĞİL, ListTile'ı saran bir `AnimatedContainer` ile
/// çizilir: `selectedTileColor` `Ink` olarak en yakın Material'in katmanına boyanır; öğe
/// `StaggeredEntry`nin `Opacity`si 0 iken (`paintsChild` false) ve kaydırma alanı ayrı bir katman
/// olduğundan o Material sonradan yeniden boyanmaz: hap hiç görünmezdi. Widget katmanındaki zemin
/// öğeyle birlikte solar/kayar ve her zaman çizilir. ListTile kendi saydam Material'ine sarılır:
/// dalga/hover (Ink) hapın ÜSTÜNE, öğenin kendi alt ağacına (Opacity/kaydırma içinde) çizilir ve
/// Flutter'ın "arka plan ink'i gizliyor" denetimi (araya renkli kutu girmesi) tetiklenmez.
class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.selected,
    required this.tone,
    required this.onTap,
    this.badge = 0,
    this.badgeNoun = 'bekleyen',
  });

  final IconData icon;
  final String title;
  final bool selected;
  final AppTone tone;
  final VoidCallback onTap;

  /// Sağda gösterilen sayı rozeti (0 = yok).
  final int badge;

  /// Rozetin ekran okuyucu sözcüğü ("3 bekleyen").
  final String badgeNoun;

  /// Seçili çubuğun anahtarı (her öğede bir tane; yalnız seçilide yükseklik 22).
  static const Key selectedBarKey = ValueKey<String>('yan_menu_secili_cubuk');

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ink = tone.ink(p);
    final tint = tone.tint(p);
    final duration = AppMotion.of(context, AppMotion.base);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: AnimatedContainer(
        duration: duration,
        curve: AppMotion.standard,
        decoration: BoxDecoration(
          // Seçili değilken aynı rengin saydamı: geçişte yalnız alfa değişir (siyaha kaymaz).
          color: selected ? tint : tint.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Stack(
            alignment: AlignmentDirectional.centerEnd,
            children: [
              ListTile(
                dense: true,
                selected: selected,
                onTap: onTap,
                selectedColor: ink,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                leading: Icon(
                  icon,
                  size: 22,
                  color: selected ? ink : p.textSecondary,
                ),
                // Başlık kırpılmaz: en büyük yazıda (x2,0) dar çekmecede en çok 3 satıra iner.
                title: Text(
                  title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    color: selected ? p.text : p.textSecondary,
                  ),
                ),
                // Rozetli öğede (en çok bir tane) trailing kullanılır; rozetsiz öğeler başlığa tam
                // genişlik verir (bkz. alttaki çubuk açıklaması).
                trailing: badge > 0 ? _CountBadge(count: badge, noun: badgeNoun) : null,
              ),
              // Çubuk ListTile.trailing yerine üstte çizilir: trailing en az 32 dp yer ayırır ve
              // başlığın genişliğini her öğede daraltırdı (uzun başlıklar gereksiz sarardı).
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: ExcludeSemantics(
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      key: selectedBarKey,
                      duration: duration,
                      curve: AppMotion.standard,
                      width: 4,
                      height: selected ? 22 : 0,
                      decoration: BoxDecoration(
                        color: ink,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
