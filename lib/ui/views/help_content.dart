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
    'İşletme Projesi',
    'Komşu Panosu',
    'Ekipman ve Bakım',
    'Kamera (CCTV)',
    'Faaliyet Raporu',
    'Plaka Tanıma',
    'Kapılar',
    'Dairem',
    'Profilim',
    'Eller Serbest & Kestirmeler',
    'Kullanıcı Yönetimi',
    'Süper Kullanıcı Yönetimi',
    'Site Yöneticileri Yönetimi',
    'Daire Sakinleri',
    'Site Yönetimi',
    'Daireye Katıl',
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
    'Rehber',
  };

  /// Menü dışı ekran içi etiketler (düğme, bölüm, sekme adları; kodda aynen geçer).
  static const Set<String> knownScreenLabels = <String>{
    // Dairem (daire sahipliği ve yönetimi, güvenlik ve destek)
    'Kiracı ekle',
    'Sistemden ara',
    'Aile üyesi ekle',
    'Araçlarım',
    'Araç ekle',
    'Notu düzenle',
    'Aracı çıkar',
    'Daireyi devret / Çıkış',
    'Bağlantıyı kes talebi',
    'Bu daireden ayrıl',
    'Güvenlik ve destek',
    'Site yönetimine gizli talep gönder',
    // Daire kartı: eski sakinler / adli kayıt (yalnız site yöneticisi)
    'Eski sakinler / Adli kayıt',
    // Site Yönetimi > Daireler: daire admini + aile üyeleri akordiyonu ve "Daire kartı" düğmesi
    'Aile üyeleri',
    'Daire kartı',
    'Malik (oturmuyor)',
    'Kayıtları göster',
    'Adli bilgi dökümü al',
    // Banka dosyası (2C) ve liste dışa aktarımı (3E)
    'Kasa',
    'Banka dosyası yükle',
    'Sütunları eşleyin',
    'Satırları göster',
    'Kontrol edin',
    'İşle',
    'Eşleşmeyen banka satırları',
    "Bu IBAN'ı kaydet",
    'Geçmiş yüklemeler',
    'Excel’e aktar',
    'Daha fazla',
    // Dekont bildirimi (2B)
    'Dekont yükle',
    'Dekont bildir',
    'Paylaş',
    'Gönder',
    'İnceleniyor',
    'Dekontlar',
    'Onayla',
    'İptal et',
    'Elden giriş',
    'Açık döneme yaz',
    'Devir bakiyesi',
    'Sistem taslağına dön',
    'Hesapla',
    'Taslağı kaydet',
    "Excel'den yükle",
    'Hesap',
    'Geri al',
    'Toplu Yükle',
    'Hepsi bir arada',
    'İlişki',
    'Borç Sorumlusu',
    'Dosya Deposu (Google Drive)',
    'Google Drive bağla',
    'Telefonla giriş (SMS)',
    'Yakında…',
    'Öde',
    'Kopyala',
    'Geri çekildi',
    'Bu ay',
    '×',
    'KAPIYI AÇ',
    'Yeni proje',
    'Geçici proje',
    'Kalemleri kaydet',
    'Tebliğ et',
    'Kesinleştir',
    'İtiraz: taslağa al',
    'PDF',
    'YEREL AĞDAN AÇ',
    'QR KOD İLE AÇ',
    'QR / Kod ile Daireye Katıl',
    'Katılım Başvurularım',
    'Görev ver',
    'Uygulamaya davet et',
    'Kadro',
    'Site Kurulumu',
    'Yeni Cihaz Kaydet',
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
    // Yönetim firması (Y1/Y2)
    'Yönetim Firması',
    'Aylık ortaklık payı',
    'Personel Ekle',
    'Deneme süresi',
    'Marka teması',
    // İki hesap (İP-1A): hesap adları, ekstre penceresi, tahsilat "Daire hesabı" bölümü ve "Kim öder" seçimi
    'Ev sahibi hesabı',
    'Kiracı hesabı',
    'Hesap Ekstresi',
    'Gider Analizi',
    'Raporu Getir',
    'Tablo olarak göster',
    'Gider türü',
    'Gelecek yıl tahmini',
    'Daire hesabı',
    // İki kasa: tanım / ek borç / tahsilat / gider formlarındaki "Kasa" seçimi (menü başlığı 'Kasa' yukarıda) ve kasa adları
    'İşletme Projesi (Aidat) Hesabı',
    'Yatırım ve Demirbaş (Fon) Hesabı',
    'Kasalar Arası Aktarım',
    // İP-1D / G3: sakin alt çubuğunun sekmeleri ve site seçici.
    'Özet',
    'Duyuru',
    'Arıza',
    'Kapı',
    'Tüm siteler',
  };

  // --- Konular ----------------------------------------------------------------------------------

  /// Dairem: daire sahipliği ve yönetimi (kim yönetir, kiracı, aile üyeleri, ayrılma).
  static const HelpTopic _apartmentManagement = HelpTopic(
    id: 'apartment_management',
    title: 'Dairemi kim yönetir?',
    icon: Icons.manage_accounts_rounded,
    steps: <String>[
      'Menüden “Dairem” ekranını açın; üstte dairenizin yönetimini kimin yaptığı yazar.',
      'Kiracı yoksa daireyi malik yönetir. Malik “Kiracı ekle” ile yeni kişi ekler ya da “Sistemden ara” ile kayıtlı birini seçer. Dairede kiracı varsa daire yöneticisi her zaman kiracıdır; malik ve kiracı birlikte kayıtlı kalır ve yönetim kiracı çıkana kadar kiracıda sürer.',
      'Daire yöneticisi “Aile üyesi ekle” ile aile üyelerini ekler. Yetişkin bir üyeyi tek başına çıkaramaz; üyeye onay isteği gider. 18 yaşından küçükler için ekleme sırasında işaretleme yapılır.',
      'Kiracı “Daireyi devret / Çıkış” ile ayrılır; yönetim malike döner. Malik ile kiracı arasındaki bağı “Bağlantıyı kes talebi” ile, karşı tarafın onayıyla kesebilirsiniz.',
      'Herkes “Bu daireden ayrıl” ile kendi bağını onaysız keser; diğer üyelere bildirim gitmez.',
    ],
    note: 'Aile üyeleri borç bilgisini görmez. Anlaşmazlıkta kararı site yönetimi verir.',
  );

  /// Araçlarım: daire yöneticisi dairenin araçlarını ekler / düzenler / çıkarır; diğer üyeler yalnız görür.
  static const HelpTopic _myVehicles = HelpTopic(
    id: 'my_vehicles',
    title: 'Araçlarımı nasıl eklerim?',
    icon: Icons.directions_car_rounded,
    steps: <String>[
      'Menüden “Dairem” ekranını açın ve dairenizin kartında “Araçlarım” bölümüne gidin.',
      'Daire yöneticisiyseniz “Araç ekle” ile plakayı (örnek: 34 ABC 123) ve isterseniz marka, model, renk notunu yazın. Araç sahibi olarak dairenin aktif sakinlerinden birini seçebilirsiniz; varsayılan siz olursunuz.',
      '“Notu düzenle” ile notu değiştirin, “Aracı çıkar” ile aracı kaldırın (kayıt silinmez, pasifleşir). Plaka değişmez; yanlışsa aracı çıkarıp doğru plakayla yeniden ekleyin.',
      'Aile üyeleri ve daire yöneticisi olmayan malik ya da kiracı dairenin araçlarını yalnızca görür.',
    ],
    note: 'Dairenize en fazla 4 araç kaydedilebilir; daha fazlası için site yönetimine başvurun. Eklediğiniz plaka, sitede plaka tanıma açıksa yetkili araç sayılır; bu yüzden yalnızca kendi dairenizin araçlarını ekleyin. Aynı plaka başka bir kayıtta varsa site yönetimiyle görüşün.',
  );

  /// Güvenlik ve destek: yardım hatları, gizli talep, koruma kararı.
  static const HelpTopic _apartmentSafety = HelpTopic(
    id: 'apartment_safety',
    title: 'Güvenlik ve destek',
    icon: Icons.shield_outlined,
    steps: <String>[
      '“Dairem” ekranında dairenizin kartında “Güvenlik ve destek” bölümünü açın.',
      'Acil tehlikede 112’yi arayın. ALO 183 Sosyal Destek Hattı, KADES uygulaması ve ŞÖNİM destek verir.',
      'İsterseniz “Site yönetimine gizli talep gönder” ile durumunuzu yalnızca site yöneticisine iletin; daire yöneticisi, malik ve diğer üyeler görmez ve haberdar edilmez.',
      'Uzaklaştırma ya da koruma kararınız varsa belgeyi site yönetimine bildirin; site yöneticisi gerekirse kişinin kapı erişimini askıya alabilir.',
    ],
    note: 'Uygulama polisin ya da mahkemenin yerine geçmez. Sistem iddiayı doğrulayamaz ve otomatik kilitleme yapmaz; kararı site yöneticisi verir.',
  );

  /// Site yöneticisi: eski sakin / adli kayıt (sakin yardımına EKLENMEZ; kayıt sakinlere gösterilmez).
  static const HelpTopic _formerResidentRecords = HelpTopic(
    id: 'former_resident_records',
    title: 'Eski sakin kayıtları',
    icon: Icons.history_edu_rounded,
    steps: <String>[
      'Menüden “Kişiler” ekranını açın, “Daireler” listesinden dairenin kartına girin.',
      'Kartta “Eski sakinler / Adli kayıt” bölümünde “Kayıtları göster” ile daireden ayrılan kiracı, malik ve aile üyelerinin kaydını görürsünüz: kim, hangi rolde, hangi dönemde, nasıl ayrıldı ve işlemi kim yaptı.',
      'Resmî talep (mahkeme, kolluk) gelirse “Adli bilgi dökümü al” ile PDF ya da CSV alın; gerekçeyi seçmeniz ve kısa bir not yazmanız zorunludur, döküm alma denetim kaydına yazılır.',
    ],
    note:
        'Bu kayıt yalnız resmî talep halinde bilgi amaçlıdır. Yalnız site yöneticisi görür; kurul, görevli, daire yöneticisi, malik, kiracı ve yeni kiracı göremez. Kayıtta telefon, e-posta ve kimlik numarası bulunmaz; kayıt değiştirilemez ve silinemez.',
  );

  static const HelpTopic _joinApartment = HelpTopic(
    id: 'join_apartment',
    title: 'Daireme nasıl katılırım?',
    icon: Icons.qr_code_scanner_rounded,
    steps: <String>[
      'Menüden “Daireye Katıl” ekranını açın.',
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
      'Yetkili kapılarınız ve katılım başvurularınız “Kapılar” ekranındadır; bir siteye katılmak için “Daireye Katıl” kartını kullanın.',
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
    _apartmentManagement,
    _myVehicles,
    _apartmentSafety,
    HelpTopic(
      id: 'payment_notice_resident',
      title: 'Ödememi nasıl bildiririm (dekont)?',
      icon: Icons.receipt_long_rounded,
      steps: <String>[
        'Borcum kartında “Öde”ye dokunun, IBAN ve açıklama kodunu kopyalayıp bankanızdan ödemeyi yapın.',
        '“Dekont yükle”ye dokunun; dekontun PDF’ini ya da fotoğrafını seçin, tutarı ve ödeme tarihini kontrol edip “Gönder”e dokunun. Android’de banka uygulamasından “Paylaş” menüsünde “Dekont bildir”i de seçebilirsiniz.',
        'Yönetim dekontu kontrol edinceye kadar kartta tutarla birlikte “İnceleniyor” görünür. Onaylanınca borcunuzdan düşer ve makbuzunuz oluşur.',
        'Kabul edilmezse nedenini kartın altında görürsünüz; düzeltip yeniden gönderebilirsiniz.',
      ],
      note: 'Dekont ad ve IBAN gibi kişisel veri içerebilir; yalnız site yönetimi görür. Fotoğraflardaki konum bilgisi silinir. Bu özellik sitede açık değilse “Dekont yükle” görünmez.',
    ),
    HelpTopic(
      id: 'neighbor_board',
      title: 'Komşu panosuna nasıl ilan veririm?',
      icon: Icons.forum_rounded,
      steps: <String>[
        'Menüden “Komşu Panosu” ekranını açın (site yöneticisi modülü açtıysa görünür).',
        'Yeni ilan düğmesine dokunup başlık ve metni yazın; ilan yönetici onayına gider.',
        'Onaylanınca komşularınız ilanı görür. Uygunsuz bir ilanı Şikayet et düğmesiyle yöneticiye bildirebilirsiniz.',
      ],
      note: 'Yönetici reddederse gerekçeyi ilanınızın altında görürsünüz. İlanınızı istediğiniz an geri çekebilirsiniz.',
    ),
    HelpTopic(
      id: 'guest_plate',
      title: 'Misafirimin aracı için plaka izni nasıl veririm?',
      icon: Icons.directions_car_rounded,
      steps: <String>[
        'Plaka Tanıma modülü sitenizde açıksa menüden “Plaka Tanıma” ekranını açın.',
        'Misafir plakası ekle düğmesine dokunup plakayı yazın (örneğin 34 ABC 123), süreyi seçin (1 gün, 1 hafta ya da en çok 30 gün) ve kaydedin.',
        'İzin süresi dolunca kendiliğinden biter; erken bitirmek için listedeki iptal düğmesine dokunun.',
      ],
      note: 'Bir günde en çok 5 misafir plakası tanımlayabilirsiniz; yalnız kendi daireniz için. Kapı açma Yakında…: şimdilik plaka kamerada tanınınca yönetim ekranında izinli olarak görünür.',
    ),
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
        'Okunmamış duyuru Panel’in en üstünde kart olarak çıkar; okuyunca karttan kalkar, “Duyurular”da durur. Duyuruyu listenizden kaldırmak için satırdaki “×” düğmesine dokunun; 8 saniye içinde “Geri al” diyebilirsiniz.',
        'E-posta ile duyuru alıp almayacağınızı “Profilim” ekranındaki “Bildirim Tercihleri” bölümünden seçersiniz.',
      ],
    ),
    HelpTopic(
      id: 'my_balance',
      title: 'Borcumu nasıl görürüm?',
      icon: Icons.receipt_long_rounded,
      steps: <String>[
        'Sitenizde Finans modülü açıksa menünün “Borçlar” başlığında “Borcum” ekranı görünür.',
        'Bu ekranda daireniz için yazılan aidat ve diğer borçları ile yapılan ödemeleri görürsünüz.',
        'Her dairenin iki ayrı hesabı vardır: “Ev sahibi hesabı” ve “Kiracı hesabı”. Ekranda yalnız kendi hesabınızın borcu ve '
            'hareketleri görünür; malik ve kiracı borçları birbirine karışmaz.',
        'Borçtan malik ve kiracının birlikte sorumlu olduğu dairede malik, kiracı hesabını da salt okunur olarak görür; bu tutar '
            'malikin kendi borcuna eklenmez.',
        'Borcunuz varsa “Öde” düğmesine dokunun: alıcı adı, IBAN ve açıklama kodu görünür, her birinin yanındaki “Kopyala” ile '
            'kopyalayıp bankanızdan FAST ya da havale yapın. Açıklamaya kodu (örn. GUL-A2-1026) yazarsanız ödemeniz dairenize işlenir. '
            'Kartla ödeme yakında gelecek.',
      ],
      note: 'Menüde “Borcum” yoksa sitenizde Finans modülü açık değildir.',
    ),
    _residentProfile,
  ];

  static const List<HelpTopic> _individual = <HelpTopic>[
    _apartmentManagement,
    _myVehicles,
    _apartmentSafety,
    _panelIndividual,
    _navigationIndividual,
    HelpTopic(
      id: 'add_device',
      title: 'Sisteme cihazı kim ekler?',
      icon: Icons.add_to_photos_rounded,
      steps: <String>[
        'Sisteme cihazı yalnız site yöneticisi ekleyebilir, o da yalnızca sitesinde Geçiş Kontrol modülü açıkken.',
        'Daire sakini ve bireysel kullanıcılar cihaz eklemez; sitenizin kapısını açmak için yöneticinizin tanımladığı yetkiyi kullanırsınız.',
        'Kendi sitenizi kurmak istiyorsanız “Site Kurulumu” kartındaki “Site Kurmak İçin Başvur” ile başvurun; site kurulunca cihazı siz eklersiniz.',
      ],
      note: 'Zaten hesabınıza tanımlı cihazlarınız ve kapı açma yetkileriniz aynen çalışmaya devam eder.',
    ),
    HelpTopic(
      id: 'site_application',
      title: 'Site yöneticisi olmak için nasıl başvururum?',
      icon: Icons.domain_add_rounded,
      steps: <String>[
        'Menüden “Daireye Katıl” ekranını açın; “Site Kurulumu” kartındaki “Site Kurmak İçin Başvur” düğmesine dokunun.',
        'Site adını, bloklarla daire sayılarını ve kapıları girin. Cihaz seçimi isteğe bağlıdır; cihazı site kurulduktan sonra siz (site yöneticisi) eklersiniz.',
        'Veri İşleme Sözleşmesi kutusunu işaretleyip başvuruyu gönderin.',
        'Süper kullanıcı onaylayınca siteniz kurulur ve site yöneticisi olursunuz. Onaylanmadan önce başvurunuzu iptal edebilirsiniz.',
      ],
    ),
    _joinApartment,
    _profile,
  ];

  static const List<HelpTopic> _siteManager = <HelpTopic>[
    HelpTopic(
      id: 'payment_notice_manager',
      title: 'Sakinlerin dekontlarını nasıl onaylarım?',
      icon: Icons.receipt_long_rounded,
      steps: <String>[
        'Finans Ayarları > Ödeme bilgisi bölümünden dekont yüklemeyi açın (varsayılan kapalıdır).',
        'Finans ekranındaki “Dekontlar” sekmesinde bekleyen dekontlar listelenir. Birine dokununca solda dekont, sağda sakinin bildirdikleri, daire bilgisi ve uyarılar görünür.',
        '“Onayla”ya dokunun: tahsilat dekont tarihiyle deftere yazılır ve makbuz oluşur. Önemli uyarı varsa her birini gözden geçirdiğinizi işaretlemeden onay açılmaz.',
        '“İptal et”te nedeni seçin; sakin nedeni görür. Yanlış daireye yapılmışsa iptal edip tahsilatı doğru daireye elle girin. Birden çok dekontu kutucuklarla seçip toplu onaylayabilirsiniz.',
        'Elden aldığınız parayı “Elden giriş” ile kaydedin; o da aynı yoldan onaylanır.',
      ],
      note: 'Dekontun ayı kapatılmışsa “Açık döneme yaz” ile bugünün tarihine işleyebilirsiniz. Onaydan sonra geri almak için tahsilat kaydını iptal edin (ters kayıt).',
    ),
    HelpTopic(
      id: 'equipment',
      title: 'Ekipman, bakım ve teklifleri nasıl takip ederim?',
      icon: Icons.build_circle_rounded,
      steps: <String>[
        'Menüden “Ekipman ve Bakım” ekranını açın (süper kullanıcı modülü açtıysa görünür). Ekipman ekle ile asansör, interkom, kamera gibi ekipmanları kaydedin.',
        'Ekipmana dokunup Plan ekle ile aylık, 3, 6 ya da 12 aylık bakım planı kurun. Asansör gibi yasal kontrolü olan ekipmanda Yasal kontrol planı yıllık hatırlatma tarihi açar.',
        'Bakım yapılınca Yapıldı ya da Bakım kaydı ile tarih, firma ve maliyeti girin; plan bir sonraki tarihe ilerler. Bakım takvimi sekmesi yaklaşan ve geciken bakımları listeler.',
        'Teklifler sekmesinde aynı konudaki teklifleri karşılaştırın (en düşük tutar işaretlenir). Kabul ettiğiniz teklif gider ya da sözleşme olarak kaydedilir. Gider kırılımı sekmesi giderleri ekipman bazında gösterir.',
      ],
      note: 'Telefon / e-posta ile otomatik hatırlatma ve teklife belge yükleme Yakında…',
    ),
    HelpTopic(
      id: 'cctv',
      title: 'Kapı olaylarını kamera kayıtlarıyla nasıl eşleştiririm?',
      icon: Icons.videocam_rounded,
      steps: <String>[
        'Menüden “Kamera (CCTV)” ekranını açın (süper kullanıcı modülü açtıysa görünür). Kameralar sekmesinde Kamera ekle ile kamerayı ya da kayıt cihazını (NVR) tanıtın; ad, konum ve eşleşecek kapıları seçin.',
        'Kayıt bağlantı şablonuna kayıt sisteminin oynatma adresini https ile yazın; {start}, {end}, {channel} ve {camera} yer tutucuları olay anında doldurulur. Kamera herkese açık bir https adresinden görüntü veriyorsa anlık görüntü adresini de ekleyebilirsiniz.',
        'Olaylar sekmesinde son kapı olayları görünür. Olayın kapısına eşlenmiş kamerada Kaydı aç, olaydan 30 sn önce ile 30 sn sonrasını kayıt sisteminde açar; kayıt sistemine yalnız site ağından ulaşılabilir.',
      ],
      note: 'Kamera görüntüsü kişisel veridir; her anlık görüntü ve kayıt bağlantısı açma denetim kaydına yazılır. Video bu uygulamada saklanmaz.',
    ),
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
      id: 'apartment_residents',
      title: 'Dairenin sakinleri nerede görünür?',
      icon: Icons.groups_2_rounded,
      steps: <String>[
        'Menüden “Site Yönetimi” ekranını açın, sitenizi seçin ve “Daireler” bölümünü açın. Daire satırında dairedeki kişi sayısı görünür.',
        'Daireye dokununca üstte daire admini, altında “Aile üyeleri” akordiyonu görünür; akordiyona dokununca dairedeki herkes listelenir. Kiracı oturan dairede malik ayrı satırda “Malik (oturmuyor)” olarak yazar.',
        'Bir kişiye dokununca kişi kartı açılır. Daire adminini değiştirmek, kapı erişimini askıya almak ve eski sakinlere (“Eski sakinler / Adli kayıt”) bakmak için “Daire kartı”na dokunun.',
      ],
      note: 'Telefon, hesap durumu ve çocuk bilgisi yalnız site yöneticisi ve sistem yöneticisi içindir; kurul üyesi yalnız ad ve ilişkiyi görür.',
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
      id: 'team',
      title: 'Kurul, kapıcı gibi görevlileri ve uygulamaya daveti nasıl yönetirim?',
      icon: Icons.badge_rounded,
      steps: <String>[
        'Menüden “Kişiler” ekranını açın, kişinin kartında “Görev ver”e dokunun ve görevi seçin (kurul üyesi, denetçi, kapıcı, teknik görevli, danışma, diğer).',
        'Kişinin e-postası var ama uygulamada hesabı yoksa kartındaki “Uygulamaya davet et” ile 7 gün geçerli bir bağlantı gönderin; kişi bağlantıdan hesabını açınca görev yetkisi kendiliğinden açılır.',
        'Tüm kadroyu “Kişiler” ekranındaki “Kadro” sekmesinde görür, faydalı telefonları (su arıza, asansör servisi gibi) oradan eklersiniz.',
        'Sakinlerin kadroyu ve telefonları görmesi için “Rehber” modülü açık olmalıdır (Modüller ekranından talep edin).',
      ],
      note: 'Görev vermezseniz ilgili işler sizde kalır. Rehberde görünecek telefonu sakinlere göstermeden önce kişinin onayını alın.',
    ),
    HelpTopic(
      id: 'announce',
      title: 'Duyuru nasıl yayınlarım?',
      icon: Icons.campaign_rounded,
      steps: <String>[
        'Menüden “Duyurular” ekranını açın.',
        'Yönetim görünümünde yeni duyuru oluşturun, alıcıları seçin ve yayınlayın.',
        'Geri çek: duyuru sakinlerden kalkar, sizde “Geri çekildi” olarak durur. Sil: iki listeden de kalkar, kayıt yasal saklama süresince saklanır; yayındaki duyuruyu silmek onu aynı anda geri çeker ve geri alınamaz.',
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
        'Sitenin dosyalarını kendi Google Drive hesabında saklamak için “Dosya Deposu (Google Drive)” modülünü açın; aynı ekrandaki “Google Drive bağla” düğmesi Google onayına götürür. Bağlantı henüz hazır değilse Yakında… yazar.',
      ],
    ),
    HelpTopic(
      id: 'budget',
      title: 'İşletme projesini (bütçe) nasıl hazırlarım?',
      icon: Icons.account_balance_wallet_rounded,
      steps: <String>[
        'İşletme Projesi modülü açıkken menüden “İşletme Projesi” ekranını açın ve “Yeni proje” ile yılı seçin; onaylı proje yokken “Geçici proje” seçeneğini işaretleyin.',
        'Proje ekranında her gider kategorisi için yıllık tutarı girip “Kalemleri kaydet”e basın.',
        '“Tebliğ et” ile tebliğ tarihini girin; itiraz süresi bitince “Kesinleştir” açılır. İtiraz gelirse “İtiraz: taslağa al” ile projeyi düzeltin.',
        'Aynı ekranda planlanan ve gerçekleşen giderleri kategori bazında görür, “PDF” ile indirirsiniz.',
      ],
      note: 'Geçici projenin kalan günü listede görünür. Süreleri sistem yöneticisi “Kurallar”dan belirler; yasal adımları kendi karar defterinizle birlikte takip edin.',
    ),
    HelpTopic(
      id: 'annual_report',
      title: 'Yıllık faaliyet raporunu nasıl hazırlarım?',
      icon: Icons.assignment_rounded,
      steps: <String>[
        'Faaliyet Raporu modülü açıkken menüden “Faaliyet Raporu” ekranını açıp rapor yılını seçin; dokuz bölüm kayıtlarınızdan otomatik dolar.',
        'Bir bölümü açıp metni dilediğiniz gibi düzenleyin; “Sistem taslağına dön” bölümü yeniden kayıtlardan doldurur.',
        '“Gelecek yıl tahmini” bölümüne gider artış yüzdesini yazıp “Hesapla”ya basın.',
        '“Taslağı kaydet” düzenlemelerinizi saklar, “PDF” raporu verir.',
      ],
      note: 'Kapalı modüllerin bölümleri boş kalır. Düzenlemediğiniz bölüm her açılışta güncel kayıtlardan gelir. Ekipman envanteri “Yakında…”.',
    ),
    HelpTopic(
      id: 'plate_recognition',
      title: 'Plaka kayıtlarını, misafir plakalarını ve kara listeyi nasıl yönetirim?',
      icon: Icons.directions_car_rounded,
      steps: <String>[
        'Plaka Tanıma modülü açıkken menüden “Plaka Tanıma” ekranını açın. Olaylar sekmesi kameradan gelen plakaları ve kararı (izinli, engelli, bilinmiyor) nedeniyle gösterir.',
        'Kalıcı yetkili araçlar Araçlar ekranından yönetilir. Geçici misafirler için Misafir izinleri sekmesinde daire seçip plakayı ve süreyi (en çok 30 gün) girin; izni istediğiniz an iptal edebilirsiniz.',
        'Kara liste sekmesine eklediğiniz plaka, araç listesinde ya da misafir izninde olsa bile hiçbir zaman izinli sayılmaz.',
        'Ayarlar sekmesinde kameranın baktığı kapıyı eşleyin. Plakayla otomatik açma varsayılan olarak kapalıdır; açarken risk uyarısını onaylamanız gerekir.',
      ],
      note: 'Kapı açma Yakında…: otomatik açma açık kapıda izinli okumalar şimdilik yalnız "açılırdı" diye kaydedilir. Plaka kişisel veridir; yalnız güvenlik amacıyla kullanın.',
    ),
    HelpTopic(
      id: 'metering',
      title: 'Sayaç okumalarını nasıl girer ve faturalandırırım?',
      icon: Icons.speed_rounded,
      steps: <String>[
        'Sayaç modülü sitenizde açıksa menünün Borçlar başlığında Sayaçlar ekranı görünür. Önce Sayaçlar sekmesinden daire, tür (su, elektrik, ısı, sıcak su) ve seri numarasıyla sayacı ekleyin.',
        'Okumayı sayaca dokunarak elle girin ya da uzaktan okuyan sayaçların CSV / Excel dosyasını Okuma aktar sekmesinden yükleyin: ilk sütun daire kodu ya da seri no, ikinci sütun değer. Aktarmadan önce Kontrol et ile sorunlu satırları görürsünüz.',
        'Görevli ya da yönetici "Fotoğrafla oku" ile kamerayı açar: ekranın üstünde sıradaki daire yazar, fotoğraf çekilince değer telefonda okunur, siz onaylar ya da düzeltirsiniz ve kamera sıradaki daire için açık kalır. İnternet yoksa okuma ve fotoğraf telefonda bekler (Bekleyen: N), gelince kendiliğinden gönderilir.',
        'Faturalandır sekmesinde tür, yöntem (birim fiyat, fatura tutarı ya da ısı için ölçüm + alan payı) ve iki tarihi seçip Önizle deyin; tutarlar uygunsa Borçlandır ile her dairenin oturanının hesabına borç yazılır.',
      ],
      note:
          'Okunan değeri sayaçla karşılaştırmadan onaylamayın; fotoğraf Drive bağlıysa Drive a, değilse sunucuya kaydedilir. Webde kamera yok, değer elle yazılır. Borçlandırma için Aidat ve Finans modülü de açık olmalıdır; yanlış borç Finans ekranından ters kayıtla düzeltilir.',
    ),
    HelpTopic(
      id: 'management_company',
      title: 'Yönetim firması ve “Tüm siteler” tablosu',
      icon: Icons.apartment_rounded,
      steps: <String>[
        'Bir yönetim firmasının sahibi ya da personeliyseniz sağ üstteki “Ayarlar” düğmesinde “Yönetim Firması” görünür.',
        'Firma sahibi “Tüm siteler” bölümünde firmaya bağlı her sitenin daire sayısını, bu ayki tahsilat oranını, açık borcunu ve borçlu daire sayısını görür; tahsilat oranı en düşük site en üstte durur.',
        '“Aylık ortaklık payı” bölümü yalnızca bilgi içindir; fatura ya da ödeme oluşturmaz. Deneme süresindeki sitelerde pay hesaplanmaz.',
        'Firma sahibi “Personel Ekle” ile uygulamaya kayıtlı birini e-posta adresiyle ekler; personel “Tüm siteler” tablosunu görmez.',
        'Yeni açılan sitelere varsayılan olarak 60 gün “Deneme süresi” tanınır; süreyi ve firmaya site bağlamayı sistem yöneticisi yapar.',
        'Firma sahibi “Marka teması” bölümünden firmanın (ya da tek bir sitenin) uygulama rengini, logosunu ve adını belirler; renkler okunaklı değilse kaydedilmez. Kayıt yoksa Güde teması kullanılır, kullanıcılar yeniden giriş yaptığında yeni temayı görür.',
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
        'Aidat tanımında ve ek borçta “Kasa” seçilir: “İşletme Projesi (Aidat) Hesabı” (dairede oturan öder, kiracı varsa kiracı) '
            'ya da “Yatırım ve Demirbaş (Fon) Hesabı” (malik öder). Aylık aidatta varsayılan Aidat Hesabı, ek borçta Fon Hesabı’dır.',
        'Tahsilat eklerken “Kasa” bölümünden ödemenin hangi kasanın borcuna uygulanacağını seçebilirsiniz; seçmezseniz tahsilat '
            'en eski vadeden başlayarak otomatik dağıtılır ve kayıttan sonra dağılım gösterilir.',
        'Finans > Kasa sekmesinin üstünde iki kasanın bakiyesi görünür; “Kasalar Arası Aktarım” ile bir kasadan diğerine bakiye '
            'aktarılır. Yanlış aktarım silinmez, listeden gerekçeyle ters çevrilir.',
      ],
      note:
          'Daire sorumlusu kiracı ya da malik ve kiracıysa ve dairede kiracı varsa aidat kiracı hesabına yazılır. Malik ve '
          'kiracının birlikte sorumlu olduğu dairede malik, kiracı hesabını salt okunur görür.',
    ),
    HelpTopic(
      id: 'bank_import',
      title: 'Banka dosyasından tahsilatları nasıl işlerim?',
      icon: Icons.account_balance_rounded,
      steps: <String>[
        '“Finans” > “Kasa” sekmesinde banka hesabının altındaki “Banka dosyası yükle”ye dokunun ve bankanızdan indirdiğiniz ekstreyi (XLSX, CSV ya da MT940) seçin.',
        'İlk seferde “Sütunları eşleyin” penceresi açılır; tarih, açıklama ve tutar sütunlarını seçin. Seçim bu hesap için hatırlanır.',
        'PDF ekstre: bankanın indirdiğiniz PDF hesap ekstresini de seçebilirsiniz. Metni sunucuda okunur (sütun eşleme sorulmaz), dosya saklanmaz. “Satırları göster”den tarih ve tutarları ekstreyle karşılaştırın; okunması belirsiz satırlar işaretlidir ve otomatik işlenmez. Taranmış (resim) PDF okunamaz; bankanın Excel ya da CSV dökümünü yükleyin.',
        'Açıklamada daire numarası ve kişi adı birlikte yazılıysa (ör. ‘A blok 5 Ahmet Yılmaz ekim aidatı’) satır tanınır; yalnız numara ya da yalnız ad varsa “Kontrol edin”e düşer ve onayınızı bekler. Açıklamadaki ay (ör. ‘ekim’) satırda dönem olarak gösterilir; mahsup yine en eski vadeden yapılır.',
        'Özet ekranında kaç satırın tanındığı, kaçının kontrol edeceğiniz, kaçının daha önce yüklendiği görünür. “İşle”ye dokununca tanınan tahsilatlar makbuzuyla yazılır.',
        'Tanınmayan ya da kontrol isteyen satırlar “Eşleşmeyen banka satırları” ekranında bekler: daireye işleyin, “Bu IBAN\'ı kaydet”le sonraki dosyada otomatik tanınmasını sağlayın ya da gider, banka masrafı, faiz gibi gelir/gider olarak ayırın.',
        'Yanlış dosya yüklediyseniz “Geçmiş yüklemeler” listesinden “Geri al”a dokunun; tahsilatlar ters kayıtla iptal edilir.',
      ],
      note:
          'Aynı dosya aynı hesaba ikinci kez yüklenemez; daha önce el ile girdiğiniz tahsilatlar ikinci kez yazılmaz, bankadaki satıra bağlanır. '
          'Ekstre fotoğrafı (resim) desteklenmiyor; PDF yalnızca metin katmanı olan (bankanın indirdiği) dosyalarda okunur.',
    ),
    HelpTopic(
      id: 'opening_balances',
      title: 'Devir bakiyesini nasıl yüklerim?',
      icon: Icons.upload_file_rounded,
      steps: <String>[
        "“Finans” ekranında “Daireler” sekmesindeki “Devir bakiyesi” düğmesine dokunun, ardından “Excel'den yükle”yi seçin.",
        'Şablonu indirip her daire için blok, daire no ve tutarı (TL) yazın; kiracının borcu için “Hesap” hücresinde açılan listeden Kiracı’yı seçin, boşsa ev sahibi hesabına yazılır.',
        'Önizlemede devir tarihini seçin ve toplamı kontrol edin; onayda tutarları eski kayıtlarla karşılaştırdığınızı işaretleyin.',
        'Yanlış yüklediyseniz aynı pencerede ilgili yüklemenin yanındaki “Geri al”a dokunun; neden yazılır ve ters kayıt eklenir, eski kayıtlar silinmez.',
      ],
      note: 'Eksi (alacaklı) devir desteklenmez. Aynı dosyayı ikinci kez yüklemek bir şey değiştirmez.',
    ),
    HelpTopic(
      id: 'bulk_all_in_one',
      title: 'Daire ve sakinleri tek dosyada nasıl yüklerim?',
      icon: Icons.table_chart_rounded,
      steps: <String>[
        '“Kişiler” ekranında “Toplu Yükle”ye dokunun ve “Hepsi bir arada”yı seçin.',
        'Şablonda daire bilgisi, sakin adı, ilişki, telefon, e-posta, taşınma tarihi, plaka ve not tek satırdadır; bir dairenin birden çok sakini alt alta yazılır.',
        '“İlişki” ve “Borç Sorumlusu” hücreleri Excel’de açılır listedir: hücreye dokunup ok işaretiyle listeden seçin, elle yazmayın. CSV dosyasında liste yoktur; aynı sözcükleri yazın.',
        'Şablonda kullanıcı adı sütunu yoktur. Dosyayı yükleyince kullanıcı adlarını sistem Ad Soyad’dan verir ve tabloda gösterir; başka bir sitede ya da dosyada aynı ad varsa sonuna _2, _3 ekler. İsterseniz hücreye dokunup değiştirebilirsiniz; yazdığınız ad sistemde kullanılmıyorsa kabul edilir.',
        'Aynı dairenin satırlarında daire bilgisi (kat, tip) farklıysa o satır hata olur; tek değer bırakın.',
      ],
    ),
    HelpTopic(
      id: 'expense_analysis',
      title: 'Gider analizi ve gelecek yıl tahmini',
      icon: Icons.insights_rounded,
      steps: <String>[
        '“Finans” ekranının “Raporlar” sekmesinde “Gider Analizi”ni seçin; 1, 3, 6 ya da 12 aylık dönemi ve bitiş ayını belirleyip “Raporu Getir”e dokunun.',
        'Grafikte her ay için rutin ve beklenmedik giderler ile gelir görünür; “Tablo olarak göster” aynı rakamları liste olarak verir. Önceki aynı uzunluktaki dönemle karşılaştırma ve kategori kırılımı altındadır.',
        'Gider eklerken “Gider türü” (Rutin / Beklenmedik) önerisiyle gelir; aktif sözleşmesi olan firma ve son aylarda tekrar eden giderler rutin sayılır. Önerinin nedeni altında yazar, isterseniz değiştirebilirsiniz.',
        '“Gelecek yıl tahmini”, son 12 tam aydaki rutin giderlere yazdığınız artış oranını uygular; beklenmedik giderler yıllık ortalamayla alınır. Oranı boş bırakırsanız kurallar tablosundaki varsayılan kullanılır.',
      ],
      note: 'Tahmin bir öngörüdür, taahhüt değildir. Veri 12 aydan azsa yıllığa çevrilir ve bu ekranda belirtilir.',
    ),
    HelpTopic(
      id: 'devices',
      title: 'Cihaz ve Wi-Fi kurulumu',
      icon: Icons.bluetooth_searching_rounded,
      steps: <String>[
        'Cihazlarınızı sağ üstteki “Ayarlar” düğmesindeki “Kayıtlı Cihazlar” ekranında görürsünüz.',
        'Yeni cihazı Wi-Fi ağına bağlamak için aynı yerdeki “Bluetooth ile Wi-Fi Kur” ekranını kullanın.',
        'Kutudaki QR kodu / Seri No ile yeni cihaz eklemek için “Kayıtlı Cihazlar” ekranındaki “Yeni Cihaz Kaydet” düğmesini kullanın; cihazı yalnız site yöneticisi, sitede Geçiş Kontrol modülü açıkken ekleyebilir.',
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
    _formerResidentRecords,
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
      id: 'finance_enforcement',
      title: 'İcra dökümünü ve avukat listesini nasıl hazırlarım?',
      icon: Icons.gavel_rounded,
      steps: <String>[
        'Finans ekranında “Raporlar” sekmesinden İcra dökümü seçilir ve borçlu hesapları getiren düğmeye basılır; bugün vadesi geçmiş borcu olan ev sahibi ve kiracı hesapları ayrı ayrı listelenir.',
        'Hesaplar işaretlenir; isterseniz kesinleşmiş işletme projesi ya da kurul kararı bilgisi yazılır (boş bırakılırsa PDF’te elle doldurulacak bir alan çıkar).',
        'PDF yazdırma ya da paylaşma düğmesi her hesap için ayrı sayfa üretir: ödenmemiş kalemler vade sırasıyla, varsa gecikme tazminatı ve toplam. Avukat Excel listesi düğmesi seçilen hesapları tek tabloda verir.',
        'Döküm bilgi amaçlıdır; icra takibini başlatmaz. Takipten önce avukata kontrol ettirin.',
      ],
    ),
    HelpTopic(
      id: 'list_excel',
      title: 'Listeleri nasıl arar ve Excel’e aktarırım?',
      icon: Icons.table_chart_rounded,
      steps: <String>[
        'Duyurular, iş talepleri, ziyaretçi / kargo, rezervasyonlar, anketler, firmalar, sözleşmeler, kararlar ve belgeler listelerinde arama kutusu ve süzgeçler bulunur.',
        'Liste başlığındaki tablo simgesi “Excel’e aktar” işlemini açar; dosya, ekranda yüklü ve süzülmüş kayıtlarla hazırlanır. Daha fazla kayıt için önce “Daha fazla” ile listeyi yükleyin.',
        'Mali raporlar: Aylık özet, Yıllık hesap, Daire ekstresi ve İcra dökümü; borç yazma ve banka / kasa kontrolü de Finans ekranındadır.',
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
      question: 'Telefonla (SMS ile) nasıl giriş yaparım?',
      answer:
          'Giriş ekranında “Telefonla giriş (SMS)” seçeneğine dokunun, hesabınızdaki telefon numarasını yazın ve gelen '
          '6 haneli kodu girin. Kod 5 dakika geçerlidir. SMS hizmeti açık değilse ekran “Yakında…” der; '
          'e-posta ve parolanızla girebilirsiniz. Başka bir giriş yöntemi henüz yoktur.',
    ),
    HelpFaq(
      question: 'Kargom geldiğinde nasıl haberdar olurum?',
      answer:
          'Görevli dairenize kargo kaydı girince size e-posta gider; telefon uygulaması ya da tarayıcı bildirimi açıksa '
          'oraya da bildirim düşer. Tarayıcı bildirimini Bildirim Tercihleri bölümünden açabilirsiniz.',
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
      'veri bölümünü kullanın. Hesap silme geri alınamaz; silmeden önce ekrandaki uyarıları okuyun. '
      'Ödenmemiş borcunuz varsa ya da bir sitenin tek yöneticisiyseniz hesap silinemez; ekran nedenini ve yolunu (Borcum, site devri ya da kapatma talebi) gösterir.';
}
