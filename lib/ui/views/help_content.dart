import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';

/// "Yardım ve Destek" ekranının içeriği. Her madde uygulamadaki GERÇEK menü adlarına ve ekran
/// etiketlerine dayanır (lib/ui/widgets/yan_menu.dart, lib/ui/pages/home_page.dart); uygulamada olmayan
/// bir özellik yazılmaz. Arayüz adları metinde “çift tırnak” içinde verilir; test
/// (test/help_content_test.dart) tırnaklı her adın bilinen menü/etiket listesinde olduğunu denetler.
/// Menü ya da ekran adı değişirse bu dosya ve o test birlikte güncellenir.

/// Yardımın hangi kullanıcı grubuna hitap ettiği.
enum HelpAudience { resident, individual, siteManager, superUser }

/// Bir "Nasıl yapılır" konusu: başlık + numaralı adımlar (+ isteğe bağlı not).
class HelpTopic {
  const HelpTopic({
    required this.id,
    required this.title,
    required this.icon,
    required this.steps,
    this.note,
  });

  final String id;
  final String title;
  final IconData icon;
  final List<String> steps;
  final String? note;
}

/// Sık sorulan soru.
class HelpFaq {
  const HelpFaq({required this.question, required this.answer});

  final String question;
  final String answer;
}

abstract final class HelpContent {
  /// Hesap rolünden yardım grubu. Sakin moduna geçmiş site yöneticisi, daire sakini gibi kapı kullanır.
  static HelpAudience audienceFor(UserRole role, {bool residentMode = false}) {
    switch (role) {
      case UserRole.superUser:
        return HelpAudience.superUser;
      case UserRole.siteManager:
        return residentMode ? HelpAudience.resident : HelpAudience.siteManager;
      case UserRole.apartmentOwner:
        return HelpAudience.resident;
      case UserRole.individual:
        return HelpAudience.individual;
    }
  }

  /// Gruba göre "Nasıl yapılır" konuları.
  static List<HelpTopic> howToFor(HelpAudience audience) {
    switch (audience) {
      case HelpAudience.resident:
        return _resident;
      case HelpAudience.individual:
        return _individual;
      case HelpAudience.siteManager:
        return _siteManager;
      case HelpAudience.superUser:
        return _superUser;
    }
  }

  /// Yan menüdeki başlıklar (yan_menu.dart ile birebir) ve çekmecedeki eylemler. "Panel" modül vitrinidir; kapı
  /// paneli (kapı durumu, kapıyı aç) "Kapılar" ekranındadır.
  static const Set<String> knownMenuTitles = <String>{
    'Panel',
    'Kapılar',
    'Profilim',
    'Eller Serbest & Kestirmeler',
    'Kullanıcı Yönetimi',
    'Süper Kullanıcı Yönetimi',
    'Site Yöneticileri Yönetimi',
    'Daire Sakinleri',
    'Site Yönetimi',
    'Daireye Katıl & Cihaz Ekle',
    'Şirket Cihazı Kaydet',
    'Şirket Cihaz Envanteri',
    'Kayıtlı Cihazlar',
    'Bluetooth ile Wi-Fi Kur',
    'Modüller',
    'Modül Talepleri',
    'Denetim Kaydı',
    'Kişiler',
    'Duyurular',
    'Site Başvuruları',
    'Finans',
    'Borcum',
    'Yardım ve Destek',
    'Platform Ayarları',
    'İstemci Hataları',
    'Sakin Moduna Geç',
    'Yönetici Paneline Geç',
    'Sesli Kapı Açma',
    'Kapıya QR Göster',
    'Kapı Ekranından QR Oku',
    'Kurye / Misafir Geçiş Linki Oluştur',
    // İP-1D / G2: çekmece başlıkları, sağ üstteki dişli ("Ayarlar") ve oradaki eylem; ekran adları.
    'Ana sayfa',
    'Borçlar',
    'Tahsilat',
    'Giderler',
    'İletişim',
    'Raporlar',
    'Site hizmetleri',
    'Ayarlar',
    'Masaüstüne Widget Ekle',
    'Belgeler',
    'Taleplerim',
  };

  /// Menü dışı ekran içi etiketler (düğme, bölüm, sekme adları; kodda aynen geçer).
  static const Set<String> knownScreenLabels = <String>{
    'KAPIYI AÇ',
    'YEREL AĞDAN AÇ',
    'QR KOD İLE AÇ',
    'QR / Kod ile Daireye Katıl',
    'Katılım Başvurularım',
    'Site Kurulumu & Cihaz',
    'Cihaz Ekle',
    'Site Kurmak İçin Başvur',
    'Kendi Bilgilerini Düzenle',
    'Mevcut Şifre',
    'Yeni Şifre',
    'Profili Kaydet',
    'Hesap Bilgilerim',
    'Kayıtlarım',
    'Bildirim Tercihleri',
    'Modül Taleplerim',
    'Daireler',
    'Tanımlar',
    'Dönemler',
    'Araçlar',
    'Şifremi Unuttum?',
    'Kodu Tekrar Gönder',
    'Yasal belgeler',
    'Yönetim görünümü',
    'Destek',
    'Destek bilgisi yakında',
    // Kurallar tablosu (G11): Platform Ayarları ve Modüller ekranlarındaki giriş kartı.
    'Kurallar',
    'Kuralları Aç',
    'Kuralları Görüntüle',
    // İki hesap (İP-1A): hesap adları, ekstre penceresi, tahsilat "Daire hesabı" bölümü ve "Kim öder" seçimi
    'Ev sahibi hesabı',
    'Kiracı hesabı',
    'Hesap Ekstresi',
    'Daire hesabı',
    'Kim öder',
    'Dairede oturan',
    'Ev sahibi',
    // İP-1D / G3: sakin alt çubuğunun sekmeleri ve site seçici.
    'Özet',
    'Duyuru',
    'Arıza',
    'Kapı',
    'Tüm siteler',
  };

  // --- Konular ----------------------------------------------------------------------------------

  static const HelpTopic _joinApartment = HelpTopic(
    id: 'join_apartment',
    title: 'Daireme nasıl katılırım?',
    icon: Icons.qr_code_scanner_rounded,
    steps: <String>[
      'Menüden “Daireye Katıl & Cihaz Ekle” ekranını açın.',
      '“QR / Kod ile Daireye Katıl” düğmesine dokunun.',
      'Yöneticinizin paylaştığı site katılım QR kodunu okutun ya da katılım kodunu girin; blok ve daireyi seçip başvurun.',
      'Başvurunuzu yönetici onaylayınca kapılarınız “Kapılar” ekranında görünür. Durumu “Katılım Başvurularım” bölümünden izleyebilirsiniz.',
    ],
    note: 'Başvuru reddedilirse gerekçesi aynı bölümde yazar; bilgileri düzeltip yeniden başvurabilirsiniz.',
  );

  static const HelpTopic _profile = HelpTopic(
    id: 'profile',
    title: 'Profilimi ve şifremi nasıl değiştiririm?',
    icon: Icons.account_circle_outlined,
    steps: <String>[
      'Sağ üstteki “Ayarlar” düğmesine (dişli) dokunun ve “Profilim” ekranını açın.',
      '“Kendi Bilgilerini Düzenle” bölümünde ad soyadınızı ve telefonunuzu güncelleyin.',
      'Şifrenizi değiştirmek için “Mevcut Şifre” ve “Yeni Şifre” alanlarını doldurun (en az 8 karakter).',
      '“Profili Kaydet” düğmesine dokunun.',
    ],
    note: 'E-posta adresi güvenlik nedeniyle değiştirilemez.',
  );

  /// Daire sakini hesabı: bilgiler yönetici tarafından yönetilir (Profilim salt okunurdur).
  static const HelpTopic _residentProfile = HelpTopic(
    id: 'profile_resident',
    title: 'Hesap bilgilerimi nerede görürüm?',
    icon: Icons.account_circle_outlined,
    steps: <String>[
      'Sağ üstteki “Ayarlar” düğmesine (dişli) dokunun ve “Profilim” ekranını açın.',
      '“Hesap Bilgilerim”, “Kayıtlarım” ve “Bildirim Tercihleri” bölümlerinde hesabınızı, daire kayıtlarınızı ve e-posta tercihlerinizi görürsünüz.',
    ],
    note:
        'Daire sakini hesaplarının bilgileri site yöneticisi tarafından yönetilir; değişiklik gerekiyorsa '
        'yöneticinize başvurun.',
  );

  // "Panel" artık MODÜL VİTRİNİDİR (girişte açılan ekran): kapı paneli "Kapılar" kartının / menü öğesinin arkasındadır.
  // Her grup bunu kendi diliyle anlatan bir konu alır.

  static const HelpTopic _panelResident = HelpTopic(
    id: 'panel',
    title: 'Panel ekranında neler var?',
    icon: Icons.grid_view_rounded,
    steps: <String>[
      'Girişte açılan “Panel” ekranı modül vitrinidir: sitenizde size açık her modül bir kart olarak dizilir; karta dokununca o ekran açılır.',
      'Kapıyı açmak için “Kapılar” kartına dokunun; kapı düğmesi “Kapılar” ekranındadır.',
      'Kapalı ya da size açık olmayan bir modülün kartı ne “Panel” ekranında ne menüde görünür.',
    ],
  );

  static const HelpTopic _panelIndividual = HelpTopic(
    id: 'panel',
    title: 'Panel ekranında neler var?',
    icon: Icons.grid_view_rounded,
    steps: <String>[
      'Girişte açılan “Panel” ekranı modül vitrinidir: hesabınıza açık ekranlar kart olarak dizilir; karta dokununca o ekran açılır.',
      'Yetkili kapılarınız ve katılım başvurularınız “Kapılar” ekranındadır; bir siteye katılmak ya da cihaz eklemek için “Daireye Katıl & Cihaz Ekle” kartını kullanın.',
    ],
    note:
        'Kapı modülü kapalıysa “Kapılar” görünmez; dairelerinizin ve başvurularınızın bölümleri o zaman “Panel” '
        'ekranının altında gösterilir.',
  );

  static const HelpTopic _panelAdmin = HelpTopic(
    id: 'panel',
    title: 'Panel ekranında neler var?',
    icon: Icons.grid_view_rounded,
    steps: <String>[
      'Girişte açılan “Panel” ekranı modül vitrinidir: yetkinize açık modüller ve yönetim ekranları kart olarak dizilir; karta dokununca o ekran açılır.',
      'Kapı durumu, kapıyı açma ve geçiş kayıtları “Kapılar” ekranındadır.',
    ],
  );

  // İP-1D (G2 + G3): menü başlıklar altında, ayarlar sağ üstteki dişlide, sakinde alt çubuk. Her grup kendi diliyle.

  static const HelpTopic _navigationResident = HelpTopic(
    id: 'navigation',
    title: 'Menü, alt çubuk ve ayarlar nerede?',
    icon: Icons.menu_rounded,
    steps: <String>[
      'Ekranın altındaki çubukta “Özet”, “Duyuru”, “Arıza”, “Kapı” ve “Belgeler” sekmeleri vardır. “Özet” girişte açılan “Panel” ekranıdır; sitenizde kapalı olan ya da size açık olmayan sekme görünmez, kapı yetkiniz yoksa “Kapı” sekmesi çıkmaz. İkiden az sekme kalırsa ya da telefon yatay tutulurken çubuk görünmez; ekranlara menüden ulaşırsınız.',
      'Sol üstteki menü düğmesi menüyü açar: ekranlar “Ana sayfa”, “Daireler”, “Borçlar”, “İletişim” ve “Site hizmetleri” gibi başlıklar altında toplanır. Size açık ekranı olmayan başlık görünmez; menünün en üstünde bağlı olduğunuz site yazar.',
      'Sağ üstteki “Ayarlar” düğmesi (dişli) “Profilim” ve “Eller Serbest & Kestirmeler” gibi hesap ve ayar ekranlarını açar.',
      'Geri tuşu bir sekmeden ya da ekrandan “Özet” sekmesine döner; “Özet” sekmesindeyken uygulamadan çıkar.',
    ],
  );

  static const HelpTopic _navigationIndividual = HelpTopic(
    id: 'navigation',
    title: 'Menü ve ayarlar nerede?',
    icon: Icons.menu_rounded,
    steps: <String>[
      'Sol üstteki menü düğmesi menüyü açar: ekranlar “Ana sayfa”, “Daireler” ve “Site hizmetleri” gibi başlıklar altında toplanır; size açık ekranı olmayan başlık görünmez.',
      'Sağ üstteki “Ayarlar” düğmesi (dişli) “Profilim” gibi hesap ve ayar ekranlarını açar.',
    ],
  );

  static const HelpTopic _navigationManager = HelpTopic(
    id: 'navigation',
    title: 'Menü, site seçici ve ayarlar nerede?',
    icon: Icons.menu_rounded,
    steps: <String>[
      'Sol üstteki menü düğmesi menüyü açar: ekranlar “Ana sayfa”, “Daireler”, “Borçlar”, “İletişim” ve “Site hizmetleri” gibi başlıklar altında toplanır; yetkinize açık ekranı olmayan başlık görünmez (“Tahsilat”, “Giderler” ve “Raporlar” başlıklarında henüz ekran yoktur).',
      'Birden çok siteniz varsa menünün en üstündeki site satırına dokunup bir site seçin: menü ve Panel o sitenin açık modülleriyle sınırlanır. “Tüm siteler” seçimi hepsini geri getirir.',
      'Sağ üstteki “Ayarlar” düğmesi (dişli) “Profilim”, “Modüller”, “Kayıtlı Cihazlar” ve “Bluetooth ile Wi-Fi Kur” gibi ayar ekranlarını açar.',
    ],
  );

  static const HelpTopic _navigationSuperUser = HelpTopic(
    id: 'navigation',
    title: 'Menü ve ayarlar nerede?',
    icon: Icons.menu_rounded,
    steps: <String>[
      'Sol üstteki menü düğmesi menüyü açar: ekranlar “Ana sayfa”, “Daireler”, “Borçlar”, “İletişim” ve “Site hizmetleri” gibi başlıklar altında toplanır.',
      'Sağ üstteki “Ayarlar” düğmesi (dişli) kullanıcı yönetimi, “Modüller”, “Modül Talepleri”, “Site Başvuruları”, cihaz ekranları, “Denetim Kaydı”, “Platform Ayarları” ve “İstemci Hataları” ekranlarını açar.',
      'Bekleyen modül talebi ve site başvurusu sayıları “Ayarlar” düğmesinde ve ilgili ekranın yanında rozetle görünür.',
    ],
  );

  static const List<HelpTopic> _resident = <HelpTopic>[
    HelpTopic(
      id: 'open_door',
      title: 'Kapıyı nasıl açarım?',
      icon: Icons.lock_open_rounded,
      steps: <String>[
        '“Panel” ekranındaki “Kapılar” kartına ya da alttaki “Kapı” sekmesine dokunun; menüden “Kapılar” ekranını da açabilirsiniz.',
        'Kapı kartındaki “KAPIYI AÇ” düğmesine dokunun. Telefonunuz site ağındaysa düğme “YEREL AĞDAN AÇ” olur.',
        'Sitenizde yalnızca QR ile giriş açıksa düğmenin adı “QR KOD İLE AÇ” olur.',
        'Kapı modülü açıksa menüdeki “Sesli Kapı Açma” eylemiyle sesle de açabilirsiniz.',
      ],
      note:
          '“Panel” ekranında “Kapılar” kartı, menüde de “Kapılar” yoksa sitenizde kapı modülü kapalıdır ya da '
          'hesabınızın kapı yetkisi yoktur (örneğin henüz bir daireye bağlı değilsiniz); site yöneticinize başvurun.',
    ),
    _panelResident,
    _navigationResident,
    HelpTopic(
      id: 'qr_and_guest',
      title: 'QR ile giriş ve misafir geçişi',
      icon: Icons.qr_code_2_rounded,
      steps: <String>[
        'Menüdeki “Kapıya QR Göster” eylemiyle kapı okuyucusuna QR gösterebilirsiniz.',
        'Ekranlı kapı cihazlarında “Kapı Ekranından QR Oku” eylemiyle kapının ekranındaki karekodu okutabilirsiniz.',
        '“Kurye / Misafir Geçiş Linki Oluştur” eylemiyle kurye ve misafirleriniz için süreli bir geçiş bağlantısı paylaşabilirsiniz.',
      ],
      note: 'Bu eylemler yetkinize ve sitenizin kapı donanımına göre menüde görünür; görünmüyorsa yöneticinize sorun.',
    ),
    _joinApartment,
    HelpTopic(
      id: 'announcements',
      title: 'Duyuruları nasıl görürüm?',
      icon: Icons.campaign_rounded,
      steps: <String>[
        'Alttaki “Duyuru” sekmesine dokunun ya da menüden “Duyurular” ekranını açın; yönetimin gönderdiği duyurular gelen kutunuzda listelenir.',
        'Okunmamış duyuru sayısı menüde ve “Duyuru” sekmesinde rozetle görünür.',
        'E-posta ile duyuru alıp almayacağınızı “Profilim” ekranındaki “Bildirim Tercihleri” bölümünden seçersiniz.',
      ],
    ),
    HelpTopic(
      id: 'my_balance',
      title: 'Borcumu nasıl görürüm?',
      icon: Icons.receipt_long_rounded,
      steps: <String>[
        'Sitenizde Finans modülü açıksa menünün “Borçlar” başlığında “Borcum” ekranı görünür.',
        'Bu ekranda daireniz için tahakkuk eden aidat ve diğer borçları ile yapılan ödemeleri görürsünüz.',
        'Her dairenin iki ayrı hesabı vardır: “Ev sahibi hesabı” ve “Kiracı hesabı”. Ekranda yalnız kendi hesabınızın borcu ve '
            'hareketleri görünür; malik ve kiracı borçları birbirine karışmaz.',
        'Borçtan malik ve kiracının birlikte sorumlu olduğu dairede malik, kiracı hesabını da salt okunur olarak görür; bu tutar '
            'malikin kendi borcuna eklenmez.',
      ],
      note: 'Menüde “Borcum” yoksa sitenizde Finans modülü açık değildir.',
    ),
    _residentProfile,
  ];

  static const List<HelpTopic> _individual = <HelpTopic>[
    _panelIndividual,
    _navigationIndividual,
    HelpTopic(
      id: 'add_device',
      title: 'Cihazımı hesabıma nasıl eklerim?',
      icon: Icons.add_to_photos_rounded,
      steps: <String>[
        'Menüden “Daireye Katıl & Cihaz Ekle” ekranını açın.',
        '“Site Kurulumu & Cihaz” kartındaki “Cihaz Ekle” düğmesine dokunun.',
        'Kutunun üzerindeki QR kodu okutun ya da Seri No / UID kodunu elle girin.',
      ],
      note: 'Cihaz eklemek sizi site yöneticisi yapmaz; site yöneticisi olmak için site başvurusu gerekir.',
    ),
    HelpTopic(
      id: 'site_application',
      title: 'Site yöneticisi olmak için nasıl başvururum?',
      icon: Icons.domain_add_rounded,
      steps: <String>[
        'Menüden “Daireye Katıl & Cihaz Ekle” ekranını açın; “Site Kurulumu & Cihaz” kartındaki “Site Kurmak İçin Başvur” düğmesine dokunun.',
        'Site adını, bloklarla daire sayılarını ve kapıları girin. Cihazınız yoksa cihaz seçimini boş bırakabilirsiniz.',
        'Veri İşleme Sözleşmesi kutusunu işaretleyip başvuruyu gönderin.',
        'Süper kullanıcı onaylayınca siteniz kurulur ve site yöneticisi olursunuz. Onaylanmadan önce başvurunuzu iptal edebilirsiniz.',
      ],
    ),
    _joinApartment,
    _profile,
  ];

  static const List<HelpTopic> _siteManager = <HelpTopic>[
    _panelAdmin,
    _navigationManager,
    HelpTopic(
      id: 'manage_site',
      title: 'Sitemi, bloklarımı ve kapılarımı nasıl yönetirim?',
      icon: Icons.apartment_rounded,
      steps: <String>[
        'Menüden “Site Yönetimi” ekranını açın ve sitenizi seçin.',
        'Seçili sitede blokları, daireleri, kapıları ve daire sakini hesaplarını yönetirsiniz.',
        'Site katılım QR kodunu gösterebilir, gelen katılım başvurularını onaylayabilir ya da reddedebilirsiniz.',
      ],
    ),
    HelpTopic(
      id: 'people',
      title: 'Kişi, daire ve araç kayıtlarını nasıl tutarım?',
      icon: Icons.contacts_rounded,
      steps: <String>[
        'Menüden “Kişiler” ekranını açın ve siteyi seçin.',
        '“Kişiler”, “Daireler” ve “Araçlar” sekmelerinden ilgili kayıtları ekleyin ya da düzenleyin.',
      ],
    ),
    HelpTopic(
      id: 'announce',
      title: 'Duyuru nasıl yayınlarım?',
      icon: Icons.campaign_rounded,
      steps: <String>[
        'Menüden “Duyurular” ekranını açın.',
        'Yönetim görünümünde yeni duyuru oluşturun, alıcıları seçin ve yayınlayın.',
      ],
      note:
          'Hem yönetim hem gelen kutusu görünüyorsa ekrandaki “Yönetim görünümü” seçimiyle yönetim ekranına geçin.',
    ),
    HelpTopic(
      id: 'modules',
      title: 'Modülleri nasıl açarım?',
      icon: Icons.extension_rounded,
      steps: <String>[
        'Sağ üstteki “Ayarlar” düğmesinden “Modüller” ekranını açın ve siteyi seçin.',
        'Kapalı bir modül için talep gönderin; talebinizi “Modül Taleplerim” bölümünden izleyebilirsiniz.',
        'Finans modülü açılınca menüde “Finans” ekranı (“Daireler”, “Tanımlar” ve “Dönemler” sekmeleri) görünür.',
        'Finans açıkken ana sayfada “Bu ay” bölümü görünür: yazılan, toplanan, geciken daire ve kasa sayıları, beş adımlı aylık döngü ve son hareketler. Ay kapatmak isteğe bağlıdır; “Dönemler” sekmesinden istediğiniz ayı seçince o aya kadar açık aylar birlikte kapanır.',
        'Sitenizde geçerli kuralları (gecikme tazminatı üst sınırı, işletme projesi ve saklama süreleri) aynı ekrandaki “Kurallar” bölümünde “Kuralları Görüntüle” ile görürsünüz; değerleri sistem yöneticisi belirler.',
      ],
    ),
    HelpTopic(
      id: 'finance_accounts',
      title: 'Malik ve kiracı hesapları nasıl çalışır?',
      icon: Icons.account_balance_wallet_rounded,
      steps: <String>[
        'Her dairenin iki ayrı hesabı vardır: “Ev sahibi hesabı” ve “Kiracı hesabı”. Bakiyeler birbirine karışmaz; bir hesabın '
            'alacağı diğerinin borcunu kapatmaz.',
        '“Finans” ekranında daireye dokununca açılan “Hesap Ekstresi” penceresinde, dairede kiracı varsa ya da olduysa iki sekme '
            'görünür: “Kiracı hesabı” ve “Ev sahibi hesabı”.',
        'Tahsilat eklerken “Daire hesabı” bölümünden tahsilatın hangi hesaba yazılacağını seçin; ödeme yalnız o hesabın borcundan düşer.',
        'Aidat tanımında ve ek borçta “Kim öder” seçilir: “Dairede oturan” ya da “Ev sahibi”. Aylık aidatta varsayılan dairede '
            'oturan, ek borçta ev sahibidir.',
      ],
      note:
          'Daire sorumlusu kiracı ya da malik ve kiracıysa ve dairede kiracı varsa aidat kiracı hesabına yazılır. Malik ve '
          'kiracının birlikte sorumlu olduğu dairede malik, kiracı hesabını salt okunur görür.',
    ),
    HelpTopic(
      id: 'devices',
      title: 'Cihaz ve Wi-Fi kurulumu',
      icon: Icons.bluetooth_searching_rounded,
      steps: <String>[
        'Cihazlarınızı sağ üstteki “Ayarlar” düğmesindeki “Kayıtlı Cihazlar” ekranında görürsünüz.',
        'Yeni cihazı Wi-Fi ağına bağlamak için aynı yerdeki “Bluetooth ile Wi-Fi Kur” ekranını kullanın.',
      ],
    ),
    HelpTopic(
      id: 'resident_mode',
      title: 'Kendi daireme sakin olarak nasıl girerim?',
      icon: Icons.home_rounded,
      steps: <String>[
        'Menünün üst kısmında (site satırının hemen altında) görünüyorsa “Sakin Moduna Geç” seçeneğine dokunun.',
        'Yönetici paneline dönmek için aynı yerdeki “Yönetici Paneline Geç” seçeneğini kullanın.',
      ],
      note: 'Bu seçenek yalnız hem yönetici hem sakin olarak kayıtlı hesaplarda görünür.',
    ),
    _profile,
  ];

  static const List<HelpTopic> _superUser = <HelpTopic>[
    _panelAdmin,
    _navigationSuperUser,
    HelpTopic(
      id: 'users',
      title: 'Kullanıcıları nasıl yönetirim?',
      icon: Icons.manage_accounts_rounded,
      steps: <String>[
        'Sağ üstteki “Ayarlar” düğmesindeki “Kullanıcı Yönetimi” ekranı tüm kullanıcıları listeler.',
        '“Süper Kullanıcı Yönetimi”, “Site Yöneticileri Yönetimi” ve “Daire Sakinleri” ekranlarından rol bazında ekleme, düzenleme ve pasife alma yaparsınız.',
      ],
    ),
    HelpTopic(
      id: 'applications',
      title: 'Site başvurularını ve modül taleplerini nasıl değerlendiririm?',
      icon: Icons.inbox_rounded,
      steps: <String>[
        '“Site Başvuruları” ekranı bireysel kullanıcıların site kurma başvurularını listeler; inceleyip onaylayın ya da reddedin.',
        '“Modül Talepleri” ekranı site yöneticilerinin modül taleplerini gösterir. Bekleyen sayılar “Ayarlar” düğmesinde rozetle görünür.',
      ],
    ),
    HelpTopic(
      id: 'sites_modules',
      title: 'Siteleri, modülleri ve denetim kaydını nerede görürüm?',
      icon: Icons.extension_rounded,
      steps: <String>[
        '“Site Yönetimi” ekranı tüm siteleri, “Modüller” ekranı site başına modül durumunu gösterir.',
        '“Denetim Kaydı” ekranı modül ve yönetim işlemlerinin kaydını tutar.',
        '“Kişiler” ve “Finans” ekranları sitelerin kayıt ve mali verilerini gösterir.',
      ],
    ),
    HelpTopic(
      id: 'platform',
      title: 'Uygulama ayarlarını ve hata raporlarını nerede görürüm?',
      icon: Icons.tune_rounded,
      steps: <String>[
        '“Platform Ayarları” ekranında uygulama sürümü ve bakım ayarlarını, destek iletişim bilgilerini ve şirket / yasal bilgileri girersiniz.',
        '“Platform Ayarları” ekranındaki “Kurallar” bölümünden (“Kuralları Aç”) gecikme tazminatı üst sınırı, işletme projesi süreleri, ısınma payı ve saklama süreleri gibi kuralları sınırları içinde değiştirirsiniz; her değişiklik denetim kaydına yazılır.',
        'Destek bilgileri, kullanıcıların “Yardım ve Destek” ekranındaki “Destek” bölümünde görünür; boş bırakılırsa orada “Destek bilgisi yakında” yazar.',
        '“İstemci Hataları” ekranında uygulamalardan gelen hata raporlarını izlersiniz.',
      ],
    ),
    HelpTopic(
      id: 'device_inventory',
      title: 'Şirket cihazlarını nasıl yönetirim?',
      icon: Icons.devices_other_rounded,
      steps: <String>[
        '“Şirket Cihazı Kaydet” ekranıyla yeni cihazı envantere ekleyin.',
        '“Şirket Cihaz Envanteri” ekranında cihazları listeler, siteye atar ya da düzenlersiniz.',
      ],
    ),
    _profile,
  ];

  // --- Sık sorulan sorular ---------------------------------------------------------------------

  /// Tüm roller için ortak sık sorulan sorular.
  static const List<HelpFaq> faqs = <HelpFaq>[
    HelpFaq(
      question: 'Şifremi unuttum, ne yapmalıyım?',
      answer:
          'Giriş ekranında “Şifremi Unuttum?” bağlantısına dokunun ve kayıtlı e-posta adresinizi girin. '
          'Hesap varsa şifre sıfırlama bağlantısı gönderilir; gelen kutunuza ve gereksiz klasörüne bakın.',
    ),
    HelpFaq(
      question: 'Doğrulama kodu e-postama gelmedi.',
      answer:
          'Önce gereksiz (spam) klasörüne bakın. Kod 30 dakika geçerlidir; gelmediyse doğrulama ekranındaki '
          '“Kodu Tekrar Gönder” düğmesiyle yenisini isteyin.',
    ),
    HelpFaq(
      question: 'Kapı açılmıyor.',
      answer:
          'İnternet bağlantınızı kontrol edin. Sitenizde konum doğrulaması varsa konum iznini ve konum servisini '
          'açın, kapıya yakın olduğunuzdan emin olun. Kapı çevrimdışı görünüyorsa cihazın elektrik ve ağ '
          'bağlantısı kontrol edilmelidir; sorun sürerse site yöneticinize başvurun.',
    ),
    HelpFaq(
      question: 'Oturumum neden kapandı?',
      answer:
          'Güvenlik için oturum süresi dolduğunda, şifreniz değiştirildiğinde ya da hesabınız pasife alındığında '
          'oturum kapanır. Yeniden giriş yapmanız yeterlidir.',
    ),
    HelpFaq(
      question: 'Kişisel verilerim nasıl korunuyor?',
      answer:
          'Verileriniz Gizlilik Politikası ve KVKK Aydınlatma Metni kapsamında işlenir. Belgelerin tamamını bu '
          'ekrandaki “Yasal belgeler” bölümünden okuyabilirsiniz.',
    ),
  ];

  /// "Hesabım ve verilerim" bilgilendirmesi (silme/dışa aktarma adımları Profilim ekranındadır).
  static const String accountAndDataText =
      'Kişisel verilerinizin bir kopyasını almak ve hesabınızı silmek için “Profilim” ekranındaki hesap ve '
      'veri bölümünü kullanın. Hesap silme geri alınamaz; silmeden önce ekrandaki uyarıları okuyun.';
}
