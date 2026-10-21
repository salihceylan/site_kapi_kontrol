# Flutter uygulama arayüzü — ana panel, kapı kartları, diyaloglar, giriş/kayıt, tema

[← Ana sayfa](../ARIZA_KLAVUZU.md) · [İndeks](../ARIZA_KLAVUZU_INDEKS.md) · [Ekler](../ARIZA_KLAVUZU_EKLER.md) · [Hata mesajları](../ARIZA_KLAVUZU_HATA_MESAJLARI.md)

> ⚠ **Doğrulanmadı:** bu bölümün açıklamaları (olası nedenler, adımlar) ajanlarca kodu okuyarak yazıldı ama bağımsız çürütücü incelemeden GEÇMEDİ. `dosya:satır` bağlantıları ise koddan çözülür ve her çalıştırmada denetlenir (güvenilir). Açıklamayı uygulamadan önce bağlantıdaki koda bakarak teyit edin.

Ekranda görülen arıza (taşma, güncellenmeyen liste, yanlış menü, tepkisiz kapı düğmesi, QR/Wi-Fi/cihaz diyalogları, tema/kontrast) için ilk bakılacak yer `lib/ui/pages/home_page.dart` (rol bazlı kabuk, AppBar, menü seçimi, yoklama) ve onun seçtiği görünüm dosyasıdır (`lib/ui/views/*`, `lib/ui/widgets/*`). Taşma/yazı ölçeği için test düzeneği `test/design/harness.dart` (`pumpAt`) ve `test/screens/dialog_layout_harness.dart` (`layoutMatrix`).

## Dosya haritası

| Dosya | Rol |
| --- | --- |
| [lib/ui/pages/home_page.dart](../../lib/ui/pages/home_page.dart) | Rol bazlı ana kabuk: AppBar, mod hapı, Drawer, menü seçimi, kapı durumu yoklaması, tüm diyalog tetikleyicileri ve işlem sonrası yenileme |
| [lib/ui/pages/login_page.dart](../../lib/ui/pages/login_page.dart) | Giriş ekranı: kullanıcı adı/e-posta + şifre, beni hatırla, şifremi unuttum, oturum sonu bildirimi |
| [lib/ui/pages/register_individual_page.dart](../../lib/ui/pages/register_individual_page.dart) | Bireysel kayıt formu (ad/soyad/e-posta/şifre) ve doğrulama ekranına geçiş |
| [lib/ui/pages/verify_email_code_page.dart](../../lib/ui/pages/verify_email_code_page.dart) | 6 haneli e-posta doğrulama kodu, 30 sn tekrar gönderme bekleme süresi |
| [lib/ui/pages/no_internet_page.dart](../../lib/ui/pages/no_internet_page.dart) | İnternet yok ekranı ve "Tekrar Dene" düğmesi |
| [lib/ui/pages/qr_scan_page.dart](../../lib/ui/pages/qr_scan_page.dart) | Kamera ile QR okuma sayfası (cihaz kutusu, site katılım, Wi-Fi, kapı ekranı) |
| [lib/ui/pages/site_manager_picker_page.dart](../../lib/ui/pages/site_manager_picker_page.dart) | Site oluştururken yönetici seçme sayfası (arama + sonsuz kaydırma) |
| [lib/ui/pages/wifi_provision_page.dart](../../lib/ui/pages/wifi_provision_page.dart) | Bluetooth ile cihaza Wi-Fi yazma sihirbazı ve Wi-Fi karekod ayrıştırıcı |
| [lib/ui/views/dashboard_view.dart](../../lib/ui/views/dashboard_view.dart) | Kapı paneli: sakin için ResidentDoorRemoteCard, yönetici için AdminDoorStatusCard |
| [lib/ui/views/individual_home_view.dart](../../lib/ui/views/individual_home_view.dart) | Bireysel/sakin ana ekranı: yetkili kapılar, dairelerim, başvurular, sahiplenilen cihazlar |
| [lib/ui/views/sites_view.dart](../../lib/ui/views/sites_view.dart) | Site listesi, yapı özeti, yöneticiler, daireler, kapılar |
| [lib/ui/views/all_users_view.dart](../../lib/ui/views/all_users_view.dart) | Süper kullanıcı "Kullanıcı Yönetimi" (arama, rol çipleri, sayfalama, veritabanı bakımı) |
| [lib/ui/views/managed_users_view.dart](../../lib/ui/views/managed_users_view.dart) | Süper kullanıcı / site yöneticisi yönetimi listesi |
| [lib/ui/views/company_devices_view.dart](../../lib/ui/views/company_devices_view.dart) | Şirket cihaz envanteri (atama bekleyen / kapıya atanmış, OTA, PDF) |
| [lib/ui/views/join_and_setup_view.dart](../../lib/ui/views/join_and_setup_view.dart) | Daireye Katıl & Cihaz Ekle ekranı + başvurularım |
| [lib/ui/views/profile_view.dart](../../lib/ui/views/profile_view.dart) | Profil formu ve sakin için salt okunur hesap bilgileri |
| [lib/ui/views/subscription_requests_view.dart](../../lib/ui/views/subscription_requests_view.dart) | Abonelik talepleri listesi (menüden erişim kapalı, bkz. giriş) |
| [lib/ui/views/pending_site_approvals_view.dart](../../lib/ui/views/pending_site_approvals_view.dart) | Site onay talepleri listesi (menüden erişim kapalı) |
| [lib/ui/views/bluetooth_wifi_view.dart](../../lib/ui/views/bluetooth_wifi_view.dart) | Bluetooth Wi-Fi kurulumunu açan basit giriş kartı |
| [lib/ui/widgets/yan_menu.dart](../../lib/ui/widgets/yan_menu.dart) | Sol çekmece (Drawer): rol bazlı öğe listesi, 8 başlıklı gruplama (menuGroupOf), üstteki site satırı ve sağ üstteki dişlinin açtığı Ayarlar paneli (YanMenuAyarlar) |
| [lib/ui/helpers/resident_tabs.dart](../../lib/ui/helpers/resident_tabs.dart) | Sakin alt çubuğunun sekmeleri (Özet, Duyuru, Arıza, Kapı, Belgeler): görünür menü öğelerinden türetilir |
| [lib/ui/widgets/resident_bottom_bar.dart](../../lib/ui/widgets/resident_bottom_bar.dart) | Sakin alt çubuğunun çizimi (Material 3 NavigationBar, rozetler, etiket yazı ölçeği sınırı) |
| [lib/ui/widgets/admin_door_status_card.dart](../../lib/ui/widgets/admin_door_status_card.dart) | Yönetici kapı kontrol kartı: site/kapı seçimi, telemetri, Kapı Aç, QR, geçiş logları |
| [lib/ui/widgets/resident_door_remote_card.dart](../../lib/ui/widgets/resident_door_remote_card.dart) | Daire sakini kumandası ve ResidentDoorUiState (düğme durumu/etiketi) |
| [lib/ui/widgets/individual_door_card.dart](../../lib/ui/widgets/individual_door_card.dart) | Bireysel "Yetkili Kapılarım" kartı ve IndividualDoorCardModel |
| [lib/ui/widgets/dynamic_qr_pass_modal.dart](../../lib/ui/widgets/dynamic_qr_pass_modal.dart) | Dinamik karekod penceresi: 30 sn geri sayım, durum yoklaması, ret nedenleri |
| [lib/ui/widgets/claim_device_dialog.dart](../../lib/ui/widgets/claim_device_dialog.dart) | Cihaz sahiplenme (kutu QR / seri no) diyaloğu |
| [lib/ui/widgets/site_card.dart](../../lib/ui/widgets/site_card.dart) | Site kartı: onay/silme/politika/rapor/QR eylemleri |
| [lib/ui/widgets/company_device_card.dart](../../lib/ui/widgets/company_device_card.dart) | Şirket cihaz kartı: rozetler, arızalı işaretle, depoya al, sil |
| [lib/ui/widgets/door_logs_accordion.dart](../../lib/ui/widgets/door_logs_accordion.dart) | Kapı geçiş logları akordiyonu ve PDF düğmesi |
| [lib/ui/widgets/device_connectivity_logs_accordion.dart](../../lib/ui/widgets/device_connectivity_logs_accordion.dart) | Cihaz bağlantı logları akordiyonu (süper kullanıcı) |
| [lib/ui/widgets/voice_control_modal.dart](../../lib/ui/widgets/voice_control_modal.dart) | Sesli kapı açma alt sayfası |
| [lib/ui/widgets/voice_live_banner.dart](../../lib/ui/widgets/voice_live_banner.dart) | Kartlardaki sesli dinleme canlı banner'ı |
| [lib/ui/widgets/hands_free_settings_dialog.dart](../../lib/ui/widgets/hands_free_settings_dialog.dart) | Eller Serbest & Araba Modu ayarları |
| [lib/ui/widgets/site_security_policy_dialog.dart](../../lib/ui/widgets/site_security_policy_dialog.dart) | Site giriş/güvenlik politikası ve konum çemberi doğrulaması |
| [lib/ui/widgets/list_parts.dart](../../lib/ui/widgets/list_parts.dart) | Liste ortak parçaları: PaginationBar, tonalActionStyle (44 dp), isLargeText |
| [lib/ui/design/tokens.dart](../../lib/ui/design/tokens.dart) | Tasarım tokenları: AppSpace, AppRadius, AppPalette (açık/koyu), AppTone |
| [lib/ui/design/door_open_button.dart](../../lib/ui/design/door_open_button.dart) | Tek "kapıyı aç" bileşeni: ready/opening/offline/disabled + başarı tiki |
| [lib/ui/design/buttons.dart](../../lib/ui/design/buttons.dart) | PrimaryActionButton (48 dp), PressableScale |
| [lib/ui/design/app_dialog.dart](../../lib/ui/design/app_dialog.dart) | Ortak diyalog şablonu AppDialog/AppDialogHeader |
| [lib/ui/design/app_snack.dart](../../lib/ui/design/app_snack.dart) | Tonlu SnackBar yardımcısı AppSnack |
| [lib/ui/design/theme_toggle_button.dart](../../lib/ui/design/theme_toggle_button.dart) | Aydınlık/karanlık tema düğmesi ve ThemeScope |
| [lib/styles/role_theme.dart](../../lib/styles/role_theme.dart) | Rol rengi (accentColor/inkColor) |
| [lib/styles/app_theme.dart](../../lib/styles/app_theme.dart) | Açık/koyu ThemeData (AppPalette uzantısı, input/düğme/snackbar temaları) |
| [lib/menu.dart](../../lib/menu.dart) | yan_menu.dart yeniden dışa aktarımı |
| [test/design/harness.dart](../../test/design/harness.dart) | pumpAt: genişlik x yazı ölçeği x tema taşma matrisi |
| [test/screens/dialog_layout_harness.dart](../../test/screens/dialog_layout_harness.dart) | layoutMatrix/openDialogAt: diyalog taşma testleri düzeneği |

## Bu bölümdeki girişler (56)

- [ui-ust-cubuk-tasma](#ui-ust-cubuk-tasma) — Ana ekranın üst çubuğunda (AppBar) düğmeler taşıyor, sıkışıyor ya da başlık/alt başlık kırpılıyor
- [ui-mod-hapi](#ui-mod-hapi) — "Sakin Modu / Yönetici Paneli" hapı görünmüyor ya da dokununca beklenen panele geçmiyor
- [ui-menu-yanlis-rol](#ui-menu-yanlis-rol) — Çekmece menüsünde yanlış rolün öğeleri görünüyor ya da bir öğe eksik; öğeye dokununca panele düşüyor
- [ui-sakin-alt-cubuk](#ui-sakin-alt-cubuk) — Sakin ekranının altındaki sekme çubuğu (Özet, Duyuru, Arıza, Kapı, Belgeler) görünmüyor, bir sekme eksik ya da geri tuşu beklenmedik sayfaya dönüyor
- [ui-abonelik-site-onay-menude-yok](#ui-abonelik-site-onay-menude-yok) — Abonelik talepleri / Site onay talepleri ekranına menüden ulaşılamıyor
- [ui-kapi-ac-yonetici](#ui-kapi-ac-yonetici) — Yönetici panelinde "Kapı Aç" düğmesi gri/pasif ("Cihaz Çevrimdışı") ya da dokununca hiçbir şey olmuyor
- [ui-kapi-ac-sakin](#ui-kapi-ac-sakin) — Daire sakini kumandasında büyük düğme "ÇEVRİMDIŞI", "KAPALI" ya da "UZAKTAN KAPALI" yazıyor; kapı açılmıyor
- [ui-kapi-durum-yoklama](#ui-kapi-durum-yoklama) — Kapının çevrimiçi/çevrimdışı durumu kendiliğinden güncellenmiyor ya da ekran gereksiz yere yeniden çiziliyor
- [ui-kapi-ac-basari-tiki](#ui-kapi-ac-basari-tiki) — Kapı açma komutundan sonra düğme "Gönderiliyor..." durumunda kalıyor ya da başarı tiki hiç görünmüyor
- [ui-bireysel-ana-ekran-kapilar](#ui-bireysel-ana-ekran-kapilar) — Bireysel/sakin ana ekranında ("Kapılar" sayfası) kapı çevrimdışı görünüyor, liste kendiliğinden yenilenmiyor ya da "çevrimdışı" uyarısı çıkıyor
- [ui-bireysel-kapi-karti-dugmeleri](#ui-bireysel-kapi-karti-dugmeleri) — Bireysel kapı kartında "Kapıyı Aç / Uzaktan Aç", "Kapıya QR Göster", "Kapı Ekranından QR Oku" ya da "Misafir Kodu" düğmesi eksik
- [ui-qr-modal-sure](#ui-qr-modal-sure) — Karekod penceresi "Süresi Dolmuş QR Kod" diyor, yenilenmiyor ya da karekod yerine sürekli yükleniyor/hata görünüyor
- [ui-qr-modal-ret](#ui-qr-modal-ret) — Karekod penceresinde "Kapı Yetkisi Yok", "Karekod Girişi Kapalı", "Kullanılmış Karekod" ya da "Kapı Uyuşmazlığı" uyarısı çıkıyor
- [ui-qr-konum-hatasi](#ui-qr-konum-hatasi) — "Konum Hatası" penceresi çıkıyor ya da QR penceresi "konum doğrulaması zorunludur" uyarısı veriyor
- [ui-ekran-qr-oku](#ui-ekran-qr-oku) — "Kapı Ekranından QR Oku" düğmesi görünmüyor ya da okutunca "Geçiş Reddedildi" çıkıyor
- [ui-qr-tarama-sayfasi](#ui-qr-tarama-sayfasi) — QR tarama sayfası açılmıyor, "bu platformda desteklenmiyor" diyor ya da okunan değer bozuk (büyük harfe dönmüş)
- [ui-misafir-gecis-dugmesi](#ui-misafir-gecis-dugmesi) — "Kurye / Misafir Geçişi" düğmesi görünmüyor ya da link oluşturunca paylaşım penceresi/kopyalama çalışmıyor
- [ui-cihaz-sahiplen](#ui-cihaz-sahiplen) — Cihaz sahiplenme penceresinde hata çıkıyor ("Cihaz sahiplenme sırasında bir hata oluştu") ya da kutu QR okununca cihaz hesaba bağlanmıyor
- [ui-cihaz-ekle-sonrasi](#ui-cihaz-ekle-sonrasi) — Cihaz eklendikten/sahiplenildikten sonra liste ve panel güncellenmiyor ya da site kurulum sihirbazı açılmıyor
- [ui-kurulum-sihirbazi](#ui-kurulum-sihirbazi) — "Site Kurulum Sihirbazı" (ya da site başvurusu) penceresinde blok/kapı eklerken ya da kaydederken hata alınıyor
- [ui-kapi-cihaz-ata](#ui-kapi-cihaz-ata) — Kapıya cihaz atama/çıkarma penceresi hata veriyor ya da işlemden sonra kapı kartı eski cihazı gösteriyor
- [ui-cihaz-degistir](#ui-cihaz-degistir) — "Arızalı Cihazı Değiştir" penceresi hata veriyor ya da değiştirme sonrası kapı hâlâ eski cihazı gösteriyor
- [ui-kapi-yonet-yenilenmiyor](#ui-kapi-yonet-yenilenmiyor) — Kapı eklendikten/düzenlendikten/silindikten sonra site ekranındaki kapı listesi ya da kapı paneli güncellenmiyor
- [ui-wifi-kurulum](#ui-wifi-kurulum) — Bluetooth ile Wi-Fi kurulum ekranında cihaz listesi boş, cihaza bağlanılamıyor ya da Wi-Fi bilgileri cihaza kaydedilemiyor
- [ui-wifi-karekod](#ui-wifi-karekod) — "Geçerli bir Wi-Fi karekodu bulunamadı" uyarısı çıkıyor ya da modem karekodu okununca ağ adı/şifre doğru dolmuyor
- [ui-giris-hata](#ui-giris-hata) — Giriş ekranında "Giriş Yap" sonrası hata mesajı görünmüyor, uzun mesaj kesiliyor ya da düğme dönüp duruyor
- [ui-giris-beni-hatirla](#ui-giris-beni-hatirla) — Giriş ekranında kullanıcı adı hatırlanmıyor ya da "Beni Hatırla" işaretliyken alan boş geliyor
- [ui-sifremi-unuttum](#ui-sifremi-unuttum) — "Şifremi Unuttum" penceresi hata veriyor ya da bağlantı gönderildi mesajı geliyor ama e-posta ulaşmıyor
- [ui-oturum-sonu-bildirimi](#ui-oturum-sonu-bildirimi) — Oturum kendiliğinden kapanıp giriş ekranına dönüyor ve nedeni gösterilmiyor (ya da yanlış gösteriliyor)
- [ui-kayit-formu](#ui-kayit-formu) — Kayıt formunda alanlar sığmıyor/üst üste biniyor, "Kayıt Ol" sonrası doğrulama ekranı açılmıyor ya da hata gösteriliyor
- [ui-dogrulama-kodu](#ui-dogrulama-kodu) — E-posta doğrulama ekranında kod kabul edilmiyor, "Kodu Tekrar Gönder" pasif ya da yeni kod gelmiyor
- [ui-dogrulama-sonrasi-yonlendirme](#ui-dogrulama-sonrasi-yonlendirme) — Kod doğrulandıktan sonra ana ekrana geçilmiyor, geri tuşuyla kayıt sayfasına dönülüyor ya da çıkışta giriş ekranı gelmiyor
- [ui-internet-yok](#ui-internet-yok) — "Internet baglantisi bulunamadi" ekranı geliyor ya da "Tekrar Dene" basınca ekran kapanmıyor
- [ui-tema-gecisi](#ui-tema-gecisi) — Aydınlık/karanlık tema düğmesi görünmüyor, basınca tema değişmiyor ya da yeniden açılınca eski temaya dönüyor
- [ui-koyu-tema-okunmuyor](#ui-koyu-tema-okunmuyor) — Koyu (ya da aydınlık) temada bazı metin, ikon veya düğme okunmuyor; kontrast düşük
- [ui-site-silme-diyaloglari-renk](#ui-site-silme-diyaloglari-renk) — Site silme pencerelerinde (yöntem seçimi, e-posta kodu ile sil) koyu temada renkler solgun ya da okunmuyor
- [ui-site-silme-akisi](#ui-site-silme-akisi) — Siteyi silerken beklenen pencere gelmiyor, "Silme Onayı" bekleyen sitede düğmeler yanlış ya da silme sonrası listeler güncellenmiyor
- [ui-site-yoneticisi-secici](#ui-site-yoneticisi-secici) — "Site Yöneticisi Seç" sayfasında zemin/renkler tema ile uyuşmuyor, arama yavaş ya da seçim forma geri dönmüyor
- [ui-site-duzenle-dialogu](#ui-site-duzenle-dialogu) — Siteyi düzenle/oluştur penceresinde daire sayıları okunamıyor ("Mevcut daire sayıları okunamadı"), "Güncelle" kapalı kalıyor ya da yeni site yerine sihirbaz açılıyor
- [ui-guvenlik-politikasi](#ui-guvenlik-politikasi) — "Giriş & Güvenlik Politikaları" penceresinde kaydet çalışmıyor ("Kaydedilemedi", konum hatası) ya da değişiklik kapıdaki düğmelere yansımıyor
- [ui-kapi-yetkileri](#ui-kapi-yetkileri) — "Kapı Yetki Yönetimi" penceresinde sakin anahtarı değişmiyor, liste boş geliyor ya da toplu blok yetkisi uygulanmıyor
- [ui-site-listesi-yenilenmiyor](#ui-site-listesi-yenilenmiyor) — Site/daire/yönetici/kapı üzerinde işlem yapıldı ama Siteler ekranındaki liste ya da detay eski kalıyor
- [ui-yazi-olcegi-tasma](#ui-yazi-olcegi-tasma) — Büyük sistem yazısında ya da dar ekranda ("A RenderFlex overflowed by N pixels") başlık, çip ya da düğme taşıyor/kırpılıyor
- [ui-cihaz-envanteri](#ui-cihaz-envanteri) — Kayıtlı Cihazlar ekranında cihaz listesi boş/eski, "Atama Bekleyen" grubunda yanlış cihaz var ya da kart eylemi sonrası liste yenilenmiyor
- [ui-katilim-qr-diyalogu](#ui-katilim-qr-diyalogu) — "Site Katılım QR" penceresi açılmıyor, karekod yerine hata gösteriyor ya da yenileme/paylaşma çalışmıyor
- [ui-katilim-talepleri-yonet](#ui-katilim-talepleri-yonet) — "Katılım Talepleri" penceresinde onayla/reddet sonrası liste ya da sakin sayıları güncellenmiyor, talep düğmeleri tepkisiz
- [ui-katilim-basvurusu-gonder](#ui-katilim-basvurusu-gonder) — Sakin "Siteye Katıl" penceresinde kod okutunca site bilgisi gelmiyor ya da başvuru gönderilemiyor ("Lütfen blok ve daire seçiniz")
- [ui-sakin-listesi-akordiyon](#ui-sakin-listesi-akordiyon) — "Sakin Listesi (Akordiyon)" penceresinde arama sonuç vermiyor, pasife al / sil / aile reisi yap sonrası liste eski kalıyor
- [ui-yonetici-daveti](#ui-yonetici-daveti) — "Yönetici Davet Et" penceresi davet göndermiyor, hata veriyor ya da davetten sonra yönetici listesi güncellenmiyor
- [ui-daire-sakini-diyalogu](#ui-daire-sakini-diyalogu) — "Daire Kullanıcı Ayarı" penceresi kaydetmiyor (PIN/e-posta/kullanıcı adı hatası) ya da kayıttan sonra daire kartı eski sakini gösteriyor
- [ui-kullanici-diyalogu-kaydet](#ui-kullanici-diyalogu-kaydet) — Kullanıcı ekle/düzenle penceresi kaydetmiyor, şifre/e-posta alanı yok ya da kayıttan sonra yönetici/süper kullanıcı listesi eski kalıyor
- [ui-hesap-listesi-arama](#ui-hesap-listesi-arama) — "Kullanıcı Yönetimi" listesinde arama/rol süzgeci/sayfalama sonuç getirmiyor ya da süper kullanıcılar listede yok
- [ui-veritabani-bakim-diyalogu](#ui-veritabani-bakim-diyalogu) — "Veritabanı Sağlığı & Bakım" penceresi açılmıyor, "Hata:" gösteriyor ya da çöp temizliği sonrası sayılar değişmiyor
- [ui-cihaz-kayit-formu](#ui-cihaz-kayit-formu) — "Şirket Veritabanına Cihaz Kaydet" ekranında QR/UID ile kayıt sonrası cihaz listede görünmüyor ya da form "UID en az 6 karakter" diyor
- [ui-profil-kaydet](#ui-profil-kaydet) — "Profilim" ekranında kaydet çalışmıyor ("mevcut şifrenizi girin") ya da sakin hesabında düzenleme alanları yok
- [ui-siteler-yetkisiz-dugme](#ui-siteler-yetkisiz-dugme) — Siteler/kapılar ekranında bir kullanıcıya göstermemesi gereken düğme görünüyor ya da gerekli düğme yok

## Girişler

<a id="ui-ust-cubuk-tasma"></a>
### ui-ust-cubuk-tasma · Ana ekranın üst çubuğunda (AppBar) düğmeler taşıyor, sıkışıyor ya da başlık/alt başlık kırpılıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:5586](../../lib/ui/pages/home_page.dart#L5586) | <code>final bottomHeight = 16 + 1.2 * (textScaler.scale(18) + textScaler.scale(12));</code> | Alt başlık bloğunun yüksekliği yazı ölçeğine göre hesaplanır; ölçek büyüyünce çubuk yüksekliği buradan artar |
| [lib/ui/pages/home_page.dart:5649](../../lib/ui/pages/home_page.dart#L5649) | <code>otherActions: 3 + (hasThemeToggle ? 1 : 0),</code> | Mod hapının yanındaki 48 dp düğme sayısı (yenile, çıkış, Ayarlar dişlisi, [tema]); "Masaüstüne Widget Ekle" artık dişlinin açtığı Ayarlar panelinde. Yeni düğme eklenirse bu sayı güncellenmezse hap taşar |
| [lib/ui/pages/home_page.dart:5381](../../lib/ui/pages/home_page.dart#L5381) | <code>Widget _appBarAction({</code> | Tüm AppBar eylem düğmeleri 44 dp minimum hedefle burada üretilir |
| [lib/ui/pages/home_page.dart:5408](../../lib/ui/pages/home_page.dart#L5408) | <code>final maxWidth = (width - 48 - otherActions * 48 - 6 - 16).clamp(44.0, double.infinity).t…</code> | Mod hapına ayrılabilecek en büyük genişlik; aşılırsa etiket üç nokta ile kısalır |
| [lib/ui/design/theme_toggle_button.dart:41](../../lib/ui/design/theme_toggle_button.dart#L41) | <code>constraints: const BoxConstraints(minWidth: 44, minHeight: 44),</code> | Tema düğmesi de AppBar'a 44 dp yer kaplar (ThemeScope varsa) |

**Olası nedenler**
- AppBar'a yeni bir eylem düğmesi eklendi ama `otherActions` sayısı artırılmadı: mod hapı kalan genişliği fazla hesaplar
- Çok büyük sistem yazı ölçeği: AppBar alt başlık yüksekliği `bottomHeight` ile ölçeklenir; satır yüksekliği (height: 1.2) değiştirilirse blok sığmaz
- Dar ekran (< 400 dp) ya da ölçek > 1.3: hap yalnız ikon gösterir; bu davranış kaldırılırsa etiket taşar
- `ThemeScope` yoksa (tek başına kurulum/test) tema düğmesi çizilmez ama `hasThemeToggle` yine false olur; sayı tutarlı kalmalı

**Adım adım kontrol**
- Hangi cihaz genişliği ve yazı ölçeğinde olduğunu not edin (taşma 320 dp x 2,0 ve 360 dp x 1,5 hücrelerinde aranır)
- Taşan satırın hangisi olduğunu hata mesajından okuyun ("A RenderFlex overflowed by N pixels on the right")
- AppBar actions listesindeki öğe sayısını `otherActions` ifadesiyle karşılaştırın
- Testi çalıştırın: flutter test test/screens/home_shell_layout_test.dart

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/screens/home_shell_layout_test.dart
```

**İlgili testler:** [test/screens/home_shell_layout_test.dart](../../test/screens/home_shell_layout_test.dart), [test/design/theme_toggle_button_test.dart](../../test/design/theme_toggle_button_test.dart), [test/design/harness.dart](../../test/design/harness.dart)

**Bkz.:** [ui-mod-hapi](#ui-mod-hapi), [ui-tema-gecisi](#ui-tema-gecisi), [ui-yazi-olcegi-tasma](#ui-yazi-olcegi-tasma)

<a id="ui-mod-hapi"></a>
### ui-mod-hapi · "Sakin Modu / Yönetici Paneli" hapı görünmüyor ya da dokununca beklenen panele geçmiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:516](../../lib/ui/pages/home_page.dart#L516) | <code>bool get _canToggleDualMode {</code> | Hapın görünme kuralı: süper kullanıcı/site yöneticisi her zaman, diğer roller yalnız yönetebildiği site varsa |
| [lib/ui/pages/home_page.dart:5404](../../lib/ui/pages/home_page.dart#L5404) | <code>final label = _isResidentMode ? 'Yönetici Paneli' : 'Sakin Modu';</code> | Hap etiketi; mod `_isResidentMode` bayrağıyla tutulur |
| [lib/ui/pages/home_page.dart:2129](../../lib/ui/pages/home_page.dart#L2129) | <code>_isResidentMode = !_isResidentMode;</code> | Hap dokunuşu: modu çevirir; yönetici paneline dönüşte seçili menü dashboard'a alınır |
| [lib/ui/pages/home_page.dart:5743](../../lib/ui/pages/home_page.dart#L5743) | <code>onToggleMode: () {</code> | Çekmecedeki "Sakin Moduna Geç / Yönetici Paneline Geç" satırı aynı bayrağı çevirir |
| [lib/ui/widgets/yan_menu.dart:439](../../lib/ui/widgets/yan_menu.dart#L439) | <code>title: isResidentMode ? 'Yönetici Paneline Geç' : 'Sakin Moduna Geç',</code> | Çekmece geçiş satırının metni (yalnız `canToggleMode` true iken çizilir) |

**Olası nedenler**
- Bireysel/daire sakini hesabında `_doorControlSitesPage` boş ya da yüklenemedi: `_canToggleDualMode` false döner, hap çizilmez
- `_loadDoorControlSites` hata verdi (ağ/yetki): sayfa null kalır ve hap görünmez; yenileyince gelir
- Mod değişince `_canAccessMenu` farklı liste döndürür; seçili menü yeni modda erişimsizse panele düşer (beklenen)
- Mod hapı yalnız bu sayfanın durumunda tutulur: çıkış/giriş yapınca ya da sayfa yeniden kurulunca sıfırlanır

**Adım adım kontrol**
- Hesabın rolünü ve `_doorControlSitesPage?.sites` doluluğunu doğrulayın (panel yenile: AppBar "Yenile")
- Çekmeceyi açıp "Sakin Moduna Geç" satırının olup olmadığına bakın (canToggleMode)
- Modu çevirince AppBar alt başlığının "Sakin Modu" yazıp yazmadığına bakın (`_isResidentMode`)

**İlgili testler:** [test/screens/home_shell_layout_test.dart](../../test/screens/home_shell_layout_test.dart), [test/screens/yan_menu_layout_test.dart](../../test/screens/yan_menu_layout_test.dart)

**Bkz.:** [ui-menu-yanlis-rol](#ui-menu-yanlis-rol), [ui-ust-cubuk-tasma](#ui-ust-cubuk-tasma)

<a id="ui-menu-yanlis-rol"></a>
### ui-menu-yanlis-rol · Çekmece menüsünde yanlış rolün öğeleri görünüyor ya da bir öğe eksik; öğeye dokununca panele düşüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/yan_menu.dart:1173](../../lib/ui/widgets/yan_menu.dart#L1173) | <code>List&lt;SirketMenuItem&gt; _itemsForRole(</code> | Çekmecede GÖRÜNEN öğeler (rol + sakin modu + çift mod) burada listelenir |
| [lib/ui/widgets/yan_menu.dart:192](../../lib/ui/widgets/yan_menu.dart#L192) | <code>SirketMenuGroup menuGroupOf(SirketMenuItem item) =&gt; switch (item) {</code> | Görünen öğenin hangi çekmece başlığına düştüğü ya da sağ üstteki dişlinin açtığı Ayarlar paneline gittiği; boş başlık çizilmez |
| [lib/ui/pages/home_page.dart:1639](../../lib/ui/pages/home_page.dart#L1639) | <code>bool _canAccessMenu(SirketMenuItem item, UserRole role) {</code> | Seçili menüye ERİŞİM kuralı; çekmece listesinden ayrı yazılmıştır |
| [lib/ui/pages/home_page.dart:6046](../../lib/ui/pages/home_page.dart#L6046) | <code>if (!_canAccessMenu(_selectedMenu, session.role)) {</code> | Erişimsiz menü seçiliyse sessizce dashboard'a çevrilir (öğeye dokunup panele düşme nedeni) |
| [lib/ui/pages/home_page.dart:1644](../../lib/ui/pages/home_page.dart#L1644) | <code>if (item == SirketMenuItem.katilimVeKurulum) {</code> | "Daireye Katıl & Cihaz Ekle" tüm rollere açıktır (rol anahtarından önce) |
| [lib/ui/pages/home_page.dart:2139](../../lib/ui/pages/home_page.dart#L2139) | <code>void _selectMenu(SirketMenuItem item) {</code> | Menü seçimi: öğe tipine göre ilgili listeyi force ile yeniden yükler |
| [lib/ui/pages/home_page.dart:1771](../../lib/ui/pages/home_page.dart#L1771) | <code>String _titleForMenu(SirketMenuItem item) {</code> | AppBar başlığı çekmecedeki başlıktan ayrı tutulur (AppBar başlığı menü öğesinin etiketiyle birebir aynı olmak zorunda değildir) |
| [lib/menu.dart:1](../../lib/menu.dart#L1) | <code>export 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';</code> | Eski içe aktarma yolu; menü tanımı yalnız yan_menu.dart'ta |

**Olası nedenler**
- Menü iki yerde tanımlı: `_itemsForRole` (görünür) ve `_canAccessMenu` (erişim). Biri güncellenip öbürü güncellenmediyse öğe ya hiç görünmez ya da dokununca panele düşer
- Öğe çekmecede değil, sağ üstteki dişlinin açtığı Ayarlar panelinde: `menuGroupOf` onu `SirketMenuGroup.ayarlar` grubuna koyar (profil, cihazlar, modüller, kullanıcı yönetimi gibi)
- Çift modlu rol (bireysel/sakin + yönetilen site var) için `_canToggleDualMode && !_isResidentMode` dalı farklı liste verir
- Yeni SirketMenuItem eklendi: `_titleForMenu`, `_titleForItem`, `_iconForItem` ve `_buildContentView` switch'lerinin hepsi enum'un tüm değerlerini kapsamalıdır (eksikse derleme hatası verir)
- Rol sunucudan değişti: ön plana dönüşte `refreshSession` ile güncellenir; hemen yansımayabilir

**Adım adım kontrol**
- Rolü ve mod bayrağını belirleyin; `_itemsForRole` içinde o rol için dalı bulun
- Aynı rol için `_canAccessMenu` dalında öğenin true döndüğünü doğrulayın
- Öğenin grubunu `menuGroupOf` içinde bulun; grup `ayarlar` ise dişliye dokunup Ayarlar panelinde arayın
- Yeni öğe eklediyseniz enum + başlık + ikon + içerik switch'lerini ve `menuGroupOf` eşlemesini karşılaştırın

**İlgili testler:** [test/screens/yan_menu_layout_test.dart](../../test/screens/yan_menu_layout_test.dart), [test/screens/yan_menu_groups_test.dart](../../test/screens/yan_menu_groups_test.dart), [test/menu_groups_test.dart](../../test/menu_groups_test.dart), [test/screens/home_navigation_test.dart](../../test/screens/home_navigation_test.dart), [test/screens/home_shell_layout_test.dart](../../test/screens/home_shell_layout_test.dart), [test/resident_home_regressions_test.dart](../../test/resident_home_regressions_test.dart)

**Bkz.:** [ui-mod-hapi](#ui-mod-hapi), [ui-abonelik-site-onay-menude-yok](#ui-abonelik-site-onay-menude-yok), [ui-sakin-alt-cubuk](#ui-sakin-alt-cubuk)

<a id="ui-sakin-alt-cubuk"></a>
### ui-sakin-alt-cubuk · Sakin ekranının altındaki sekme çubuğu (Özet, Duyuru, Arıza, Kapı, Belgeler) görünmüyor, bir sekme eksik ya da geri tuşu beklenmedik sayfaya dönüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/helpers/resident_tabs.dart:33](../../lib/ui/helpers/resident_tabs.dart#L33) | <code>List&lt;ResidentTab&gt; residentTabsFor({</code> | Sekmeler çekmecenin görünür öğelerinden türer: kapalı modülün sekmesi yok, Kapı yalnız kapı yetkisiyle |
| [lib/ui/helpers/resident_tabs.dart:43](../../lib/ui/helpers/resident_tabs.dart#L43) | <code>bool showsResidentBar(List&lt;ResidentTab&gt; tabs) =&gt; tabs.length &gt;= 2;</code> | İkiden az sekme varsa çubuk hiç çizilmez |
| [lib/ui/pages/home_page.dart:5549](../../lib/ui/pages/home_page.dart#L5549) | <code>Widget? _residentBottomBar(UserSession session, SirketMenuItem page) {</code> | Çubuk yalnız sakin kitlesinde çizilir; sekmeye dokunmak çekmeceden seçmekle aynı yoldur |
| [lib/ui/pages/home_page.dart:208](../../lib/ui/pages/home_page.dart#L208) | <code>static const double residentBarMinHeight = 480;</code> | Pencere yüksekliği 480 dp altındaysa (yatay telefon) çubuk gizlenir; çekmece her zaman çalışır |
| [lib/ui/pages/home_page.dart:5778](../../lib/ui/pages/home_page.dart#L5778) | <code>canPop: drawerOpen &#124;&#124; effectiveMenu == SirketMenuItem.dashboard,</code> | Geri tuşu: Özet dışındaki sayfada önce Özet'e (Panel) döner; Özet'te uygulamadan çıkar |
| [lib/ui/pages/home_page.dart:2118](../../lib/ui/pages/home_page.dart#L2118) | <code>bool get _awaitsModuleDecision =&gt;</code> | Widget/kısayoldan gelen kapı isteği soğuk açılışta modül verisi gelene kadar bekler (Kapı sekmesi seçili açılır) |
| [lib/ui/pages/home_page.dart:2017](../../lib/ui/pages/home_page.dart#L2017) | <code>if (_doorRequestWaiting &amp;&amp; target != SirketMenuItem.kapilar) widget.doorPanelRequests?.cl…</code> | Beklerken kullanıcı başka sayfaya geçerse (çekmece, sekme, vitrin, mod geçişi, şerit, geri tuşu) bekleyen kapı isteği düşer (geç gelen veri kullanıcıyı Kapı'ya çekmez) |
| [lib/ui/widgets/resident_bottom_bar.dart:16](../../lib/ui/widgets/resident_bottom_bar.dart#L16) | <code>class ResidentBottomBar extends StatelessWidget {</code> | Çubuğun çizimi: etiket yazı ölçeği 1,0 ile sınırlı, Duyuru rozeti okunmamış sayısını gösterir |

**Olası nedenler**
- Hesap yönetici panelinde (Sakin Modu kapalı): çubuk yalnız sakin görünümünde çizilir
- Görünür sekme sayısı ikiden az (ör. modüller kapalı ve kapı yetkisi yok): tek sekmelik çubuk çizilmez
- Pencere yüksekliği 480 dp altında (telefon yatay): içerik sığsın diye çubuk gizlenir
- Kapı sekmesi yok: kullanıcının kapı yetkisi yok ya da kapı modülü o sitede kapalı
- Arıza / Belgeler sekmesi yok: İş Takibi ya da Belgeler modülü kapalı ya da modül verisi yüklenemedi (fail-closed: veri yokken bu sekmeler gösterilmez)
- Duyuru sekmesi yok: hesap hiçbir sitede duyuru alıcısı değil (yalnız görevli bağı) ya da modül verisi de kapı listesi de henüz gelmedi (veri yokken alıcılık yalnız kapı listesinden anlaşılır)
- Widget ile açılışta Kapı sekmesi seçili gelmedi: modül verisi gelmeden kullanıcı başka sayfa açtı (istek bilerek düşer) ya da kapı yetkisi yok

**Adım adım kontrol**
- Hesabın sakin görünümünde (daire sakini ya da Sakin Modundaki yönetici) olduğunu ve pencere yüksekliğini doğrulayın
- Çekmecede ilgili öğe (Duyurular, Taleplerim, Kapılar, Belgeler) görünüyor mu bakın: sekme yalnız görünür öğeden türer
- Testi çalıştırın: flutter test test/screens/home_navigation_test.dart

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/screens/home_navigation_test.dart test/resident_tabs_test.dart
```

**İlgili testler:** [test/screens/home_navigation_test.dart](../../test/screens/home_navigation_test.dart), [test/resident_tabs_test.dart](../../test/resident_tabs_test.dart), [test/screens/resident_bottom_bar_test.dart](../../test/screens/resident_bottom_bar_test.dart)

**Bkz.:** [ui-menu-yanlis-rol](#ui-menu-yanlis-rol), [ui-mod-hapi](#ui-mod-hapi)

<a id="ui-abonelik-site-onay-menude-yok"></a>
### ui-abonelik-site-onay-menude-yok · Abonelik talepleri / Site onay talepleri ekranına menüden ulaşılamıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:1732](../../lib/ui/pages/home_page.dart#L1732) | <code>return item != SirketMenuItem.abonelikTalepleri &amp;&amp;</code> | Süper kullanıcı için abonelikTalepleri, siteOnayTalepleri ve ellerSerbest erişimi bilerek kapalı |
| [lib/ui/widgets/yan_menu.dart:1189](../../lib/ui/widgets/yan_menu.dart#L1189) | <code>case UserRole.superUser:</code> | Süper kullanıcı çekmece listesinde abonelik/site onay öğeleri YOK (enum'da var, listede yok) |
| [lib/ui/pages/home_page.dart:6715](../../lib/ui/pages/home_page.dart#L6715) | <code>return SubscriptionRequestsView(</code> | Görünüm kodda duruyor ama erişim kapalı olduğundan menüden açılamaz |
| [lib/ui/pages/home_page.dart:6747](../../lib/ui/pages/home_page.dart#L6747) | <code>return PendingSiteApprovalsView(</code> | Site onay talepleri görünümü de aynı durumda |
| [lib/ui/views/subscription_requests_view.dart:11](../../lib/ui/views/subscription_requests_view.dart#L11) | <code>class SubscriptionRequestsView extends StatelessWidget {</code> | Talep listesi, onay/ret düğmeleri ve sayfalama |
| [lib/ui/views/pending_site_approvals_view.dart:11](../../lib/ui/views/pending_site_approvals_view.dart#L11) | <code>class PendingSiteApprovalsView extends StatelessWidget {</code> | Bekleyen site onayları listesi |

**Olası nedenler**
- Bu iki menü öğesi `_canAccessMenu` içinde hiçbir role açık değildir ve `_itemsForRole` listelerinde yoktur: ekran koda duruyor ama kullanıcıya sunulmuyor (tasarım gereği ya da kaldırılmış özellik)
- Site onayı bunun yerine Siteler ekranında SiteCard "Onayla/Reddet" düğmeleriyle yapılır (`approvalStatus == pending`)

**Adım adım kontrol**
- Bu ekranları geri açmak istiyorsanız hem `_canAccessMenu` hem `_itemsForRole` dalını güncelleyin (ikisi birlikte)
- Site onayı için Siteler menüsünde ilgili site kartını açıp "Onayla" düğmesine bakın
- AGENTS.md kural 2: kaldırılmış gibi görünen özelliği kullanıcı istemeden değiştirmeyin; önce nedenini sorun

**İlgili testler:** [test/screens/subscription_requests_view_layout_test.dart](../../test/screens/subscription_requests_view_layout_test.dart), [test/screens/pending_site_approvals_view_layout_test.dart](../../test/screens/pending_site_approvals_view_layout_test.dart)

**Bkz.:** [ui-menu-yanlis-rol](#ui-menu-yanlis-rol), [ui-site-listesi-yenilenmiyor](#ui-site-listesi-yenilenmiyor)

<a id="ui-kapi-ac-yonetici"></a>
### ui-kapi-ac-yonetici · Yönetici panelinde "Kapı Aç" düğmesi gri/pasif ("Cihaz Çevrimdışı") ya da dokununca hiçbir şey olmuyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/admin_door_status_card.dart:244](../../lib/ui/widgets/admin_door_status_card.dart#L244) | <code>final commandEnabled = isDeviceAssigned &amp;&amp;</code> | Düğmenin etkin olma koşulu: cihaz atanmış + bulut/yerel çevrimiçi + komut sürmüyor + durum yüklenmiyor |
| [lib/ui/widgets/admin_door_status_card.dart:221](../../lib/ui/widgets/admin_door_status_card.dart#L221) | <code>final isLocalOnline = !isCloudOnline &amp;&amp; widget.canTryLocalDoorOpen;</code> | Yerel ağ yolu: bulut çevrimdışıyken yalnız canTryLocalDoorOpen true ise etkin |
| [lib/ui/widgets/admin_door_status_card.dart:386](../../lib/ui/widgets/admin_door_status_card.dart#L386) | <code>key: const ValueKey&lt;String&gt;('admin_door_open_button'),</code> | Tek DoorOpenButton; etkin değilse DoorOpenState.disabled (dokunma hiçbir şey yapmaz) |
| [lib/ui/pages/home_page.dart:1911](../../lib/ui/pages/home_page.dart#L1911) | <code>bool get _canTryLocalDoorOpenNow =&gt;</code> | Yerel açma bayrağı: cihaz yerelde görünüyor + kapı politikası + geçerli token (üçü birden) |
| [lib/ui/pages/home_page.dart:2767](../../lib/ui/pages/home_page.dart#L2767) | <code>Future&lt;void&gt; _openDoor() async {</code> | Düğme tıklanınca çağrılan akış: authService.openDoor, sonra mesaj ve durum güncelleme |
| [lib/ui/design/door_open_button.dart:29](../../lib/ui/design/door_open_button.dart#L29) | <code>enum DoorOpenState {</code> | ready / opening / offline / disabled anlamları; yalnız ready ve offline dokunmaya yanıt verir |

**Olası nedenler**
- Kapıya cihaz atanmamış: düğme yerine "Bu kapıya henüz cihaz atanmamış" bildirimi çıkar (InlineNotice)
- runtimeStatus.mqttConnected true değil ve yerel ağ yolu da yok: etiket "Cihaz Çevrimdışı", durum disabled
- Durum yüklenirken (`isLoadingStatus`) ya da komut sürerken (`isOpeningDoor`) düğme kapalıdır; arka plan yoklaması yükleme göstermez
- Telefon yerel Wi-Fi'de değil ya da kapı politikası yerel açmaya izin vermiyor: "Yerel Ağda Aktif" çıkmaz
- Sunucu kapı durumu hatası (`doorStatusError`) panelde kırmızı bildirim olarak görünür; yalnız bulut erişilemezliği ve yerel açma mümkünse gizlenir

**Adım adım kontrol**
- Kartta "Detaylar"ı açın: Sunucu MQTT, Kapı Durumu, Yerel Ağ satırları hangi durumda olduğunu söyler
- Aynı kapıyı sakin kartında/başka telefonda deneyin (cihaz gerçekten çevrimdışı mı)
- Düğme metni: "Kapı Aç" (bulut), "Kapı Aç (Yerel Wi-Fi)", "Cihaz Çevrimdışı" — hangisi görünüyor
- Dokununca "Kapı açma komutu gönderildi." mesajı geliyorsa arayüz doğru; sorun cihaz/sunucu tarafında (kapı ve cihaz bölümlerine bakın)

**İlgili testler:** [test/design/door_open_button_test.dart](../../test/design/door_open_button_test.dart), [test/screens/admin_door_status_card_layout_test.dart](../../test/screens/admin_door_status_card_layout_test.dart), [test/home_page_state_test.dart](../../test/home_page_state_test.dart)

**Bkz.:** [ui-kapi-ac-sakin](#ui-kapi-ac-sakin), [ui-kapi-durum-yoklama](#ui-kapi-durum-yoklama), [ui-kapi-ac-basari-tiki](#ui-kapi-ac-basari-tiki)

<a id="ui-kapi-ac-sakin"></a>
### ui-kapi-ac-sakin · Daire sakini kumandasında büyük düğme "ÇEVRİMDIŞI", "KAPALI" ya da "UZAKTAN KAPALI" yazıyor; kapı açılmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/resident_door_remote_card.dart:85](../../lib/ui/widgets/resident_door_remote_card.dart#L85) | <code>bool get commandEnabled =&gt;</code> | Komut koşulu: cihaz atanmış + uzaktan açma izni + çevrimiçi + komut sürmüyor + durum yüklenmiyor |
| [lib/ui/widgets/resident_door_remote_card.dart:92](../../lib/ui/widgets/resident_door_remote_card.dart#L92) | <code>ResidentDoorTap get tap {</code> | Dokunma eylemi: openDoor / showQr / offlineWarning / none |
| [lib/ui/widgets/resident_door_remote_card.dart:123](../../lib/ui/widgets/resident_door_remote_card.dart#L123) | <code>String get buttonLabel {</code> | Etiket kuralı: KAPIYI AÇ, YEREL AĞDAN AÇ, QR KOD İLE AÇ, UZAKTAN KAPALI, ÇEVRİMDIŞI, KAPALI |
| [lib/ui/widgets/resident_door_remote_card.dart:131](../../lib/ui/widgets/resident_door_remote_card.dart#L131) | <code>String get statusText {</code> | Düğmenin altındaki durum cümlesi (cihaz yok, çevrimdışı, yalnız QR, uzaktan kapalı...) |
| [lib/ui/widgets/resident_door_remote_card.dart:323](../../lib/ui/widgets/resident_door_remote_card.dart#L323) | <code>onBlocked: () =&gt; _showOfflineWarning(context),</code> | Çevrimdışıyken dokunuş uyarı snackbar'ı gösterir (komut göndermez) |
| [lib/ui/views/dashboard_view.dart:72](../../lib/ui/views/dashboard_view.dart#L72) | <code>if (session.role == UserRole.apartmentOwner) {</code> | Yalnız apartmentOwner rolü sakin kumandasını görür; diğerleri yönetici kartını |

**Olası nedenler**
- Kapıda uzaktan açma kapalı (`canOpenRemote` false): "UZAKTAN KAPALI"; QR açıksa düğme QR gösterir ("QR KOD İLE AÇ")
- Cihaz atanmamış: "KAPALI" ve "Bu kapıya henüz cihaz atanmamış."
- Cihaz çevrimdışı ve yerel yol yok: "ÇEVRİMDIŞI", dokunuş uyarı gösterir
- Durum yüklenirken durum cümlesi "Cihaz durumu kontrol ediliyor..." olur ve komut verilmez: daha önce çevrimiçi durum alındıysa düğme pasif, hiç durum yoksa düğme ÇEVRİMDIŞI görünür ve dokunuş uyarı gösterir
- Hesap rolü apartmentOwner değilse bu kart çizilmez (bireysel ana ekran IndividualHomeView ya da yönetici kartı kullanılır)

**Adım adım kontrol**
- Durum cümlesini okuyun: hangi koşul düştüğünü doğrudan söyler
- Sorun bir koşul kombinasyonuysa test dosyasındaki tabloyla (ResidentDoorUiState) karşılaştırın
- Düğme çalışıyor ama kapı açılmıyorsa arayüz değil, komut/cihaz zincirine bakın

**İlgili testler:** [test/resident_door_ui_state_test.dart](../../test/resident_door_ui_state_test.dart), [test/screens/resident_door_remote_card_layout_test.dart](../../test/screens/resident_door_remote_card_layout_test.dart), [test/resident_home_regressions_test.dart](../../test/resident_home_regressions_test.dart)

**Bkz.:** [ui-kapi-ac-yonetici](#ui-kapi-ac-yonetici), [ui-bireysel-kapi-karti-dugmeleri](#ui-bireysel-kapi-karti-dugmeleri), [ui-qr-konum-hatasi](#ui-qr-konum-hatasi)

<a id="ui-kapi-durum-yoklama"></a>
### ui-kapi-durum-yoklama · Kapının çevrimiçi/çevrimdışı durumu kendiliğinden güncellenmiyor ya da ekran gereksiz yere yeniden çiziliyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:334](../../lib/ui/pages/home_page.dart#L334) | <code>late final AdaptivePoller _statusPoller = AdaptivePoller(</code> | 3 sn'lik kapı durumu yoklaması; ardışık hatada üstel geri çekilir (tavan 30 sn) |
| [lib/ui/pages/home_page.dart:679](../../lib/ui/pages/home_page.dart#L679) | <code>bool _isStatusPollingActive() {</code> | Yoklamanın çalışma koşulları: kapı seçili, komut sürmüyor, ön planda, sayfa opak sayfanın altında değil, panel görünür |
| [lib/ui/pages/home_page.dart:2660](../../lib/ui/pages/home_page.dart#L2660) | <code>Future&lt;bool?&gt; _loadDoorRuntimeStatus(</code> | Durum + yerel Wi-Fi erişimi + hata gizleme mantığı tek yerde |
| [lib/ui/pages/home_page.dart:2754](../../lib/ui/pages/home_page.dart#L2754) | <code>void _updateDoorPanel(VoidCallback mutate, {required bool scoped}) {</code> | Arka plan yoklaması sonucu yalnız kapı panelini yeniden kurar; sonuç aynıysa hiçbir şey kurmaz |
| [lib/ui/pages/home_page.dart:6779](../../lib/ui/pages/home_page.dart#L6779) | <code>class _DoorPanelSnapshot {</code> | Ekrandaki değerlerin anlık görüntüsü; panelde görünen yeni bir alan buraya EKLENMEZSE değişikliği yeniden çizim tetiklemez |
| [lib/ui/pages/home_page.dart:5844](../../lib/ui/pages/home_page.dart#L5844) | <code>child: ValueListenableBuilder&lt;int&gt;(</code> | Yoklamanın tetiklediği tek dinleyici (Scaffold/AppBar yeniden kurulmaz) |
| [lib/ui/pages/home_page.dart:638](../../lib/ui/pages/home_page.dart#L638) | <code>void didChangeAppLifecycleState(AppLifecycleState state) {</code> | Arka plana alınınca yoklama durur; ön plana dönünce hemen yenilenir ve oturum /me ile eşitlenir |

**Olası nedenler**
- Başka menüde (Profilim, Siteler...) ya da bireysel ana ekranda yoklama bilerek yapılmaz; panele dönünce sürer
- Sayfanın üstünde opak bir sayfa (QR tarama, Wi-Fi kurulum) varsa TickerMode kapalıdır ve yoklama durur
- Ardışık ağ hatasında aralık 30 sn'ye kadar uzar; bağlantı gelince 3 sn'ye döner
- Panele yeni bir alan eklendi ama `_DoorPanelSnapshot`'a eklenmedi: değer değişse de `sameAs` true döner, ekran yenilenmez
- Yarış: kapı/site değişince eski isteğin yanıtı `_doorControlDoor?.id != doorId` ile yok sayılır (beklenen)

**Adım adım kontrol**
- Hangi menüde olduğunuzu ve uygulamanın ön planda olduğunu doğrulayın
- AppBar "Yenile" ya da aşağı çekme (`_handleGlobalRefresh`) durumu hemen yeniler mi, deneyin
- Yeni alan eklediyseniz `_DoorPanelSnapshot.of` ve `sameAs`'ı güncelleyin
- Test: flutter test test/home_polling_test.dart

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/home_polling_test.dart test/home_page_state_test.dart
```

**İlgili testler:** [test/home_polling_test.dart](../../test/home_polling_test.dart), [test/home_page_state_test.dart](../../test/home_page_state_test.dart), [test/home_scroll_paint_test.dart](../../test/home_scroll_paint_test.dart)

**Bkz.:** [ui-kapi-ac-yonetici](#ui-kapi-ac-yonetici), [ui-bireysel-ana-ekran-kapilar](#ui-bireysel-ana-ekran-kapilar)

<a id="ui-kapi-ac-basari-tiki"></a>
### ui-kapi-ac-basari-tiki · Kapı açma komutundan sonra düğme "Gönderiliyor..." durumunda kalıyor ya da başarı tiki hiç görünmüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:2792](../../lib/ui/pages/home_page.dart#L2792) | <code>if (error == null) _doorOpenOkTick++;</code> | Komut hatasız bitince sayaç artar; DoorOpenButton bu artışı başarı sinyali sayar |
| [lib/ui/pages/home_page.dart:2775](../../lib/ui/pages/home_page.dart#L2775) | <code>setState(() =&gt; _isOpeningDoor = true);</code> | `_isOpeningDoor` true iken düğme "opening" (spinner) ve yoklama durur |
| [lib/ui/design/door_open_button.dart:261](../../lib/ui/design/door_open_button.dart#L261) | <code>void didUpdateWidget(DoorOpenButton oldWidget) {</code> | successTick değişimi ya da opening bitişi ile başarı gösterimi başlar; ilk kurulumdaki değer sinyal sayılmaz |
| [lib/ui/design/door_open_button.dart:154](../../lib/ui/design/door_open_button.dart#L154) | <code>static const Duration doneHold = Duration(milliseconds: 1400);</code> | Başarı tiki 1,4 sn kalır ve eski görünüme döner |
| [lib/ui/views/individual_home_view.dart:275](../../lib/ui/views/individual_home_view.dart#L275) | <code>_doorOpenTicks[door.id] = (_doorOpenTicks[door.id] ?? 0) + 1;</code> | Bireysel görünümde kapı başına ayrı sayaç |

**Olası nedenler**
- Komut hata döndü (`error != null`): sayaç artmaz, tik gösterilmez; hata snackbar'ı çıkar
- Başarı sinyali komut hâlâ `opening` iken geldiyse tik komut bitince gösterilir; yeni komut başlarsa süren gösterim biter
- Spinner kalıyorsa `_isOpeningDoor` false'a dönmemiştir: `authService.openDoor` hiç dönmedi (zaman aşımı/ağ) — hizmet bölümüne bakın
- Hareket azaltma açıkken morph/titreme yok ama tik yine gösterilir

**Adım adım kontrol**
- Dokununca snackbar'da "Kapı açma komutu gönderildi." (yönetici) veya "kapısı açılıyor..." (bireysel) çıkıyor mu
- Spinner sonsuza kadar sürüyorsa ağ isteği takılmıştır: günlükte /door/open isteğini arayın (sunucu bölümü)
- Testte: flutter test test/design/door_open_button_test.dart

**İlgili testler:** [test/design/door_open_button_test.dart](../../test/design/door_open_button_test.dart), [test/screens/individual_door_card_test.dart](../../test/screens/individual_door_card_test.dart)

**Bkz.:** [ui-kapi-ac-yonetici](#ui-kapi-ac-yonetici), [ui-kapi-ac-sakin](#ui-kapi-ac-sakin)

<a id="ui-bireysel-ana-ekran-kapilar"></a>
### ui-bireysel-ana-ekran-kapilar · Bireysel/sakin ana ekranında ("Kapılar" sayfası) kapı çevrimdışı görünüyor, liste kendiliğinden yenilenmiyor ya da "çevrimdışı" uyarısı çıkıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/views/individual_home_view.dart:77](../../lib/ui/views/individual_home_view.dart#L77) | <code>late final AdaptivePoller _doorsPoller = AdaptivePoller(</code> | Kapı listesi her 15 sn yoklanır (kural 7: uygulamayı kapatıp açmadan güncel kalır) |
| [lib/ui/views/individual_home_view.dart:164](../../lib/ui/views/individual_home_view.dart#L164) | <code>Future&lt;DoorRecord?&gt; _requireOnlineDoor(DoorRecord door) async {</code> | Önbellekte çevrimdışı görünen kapı için liste bir kez tazelenir; hâlâ çevrimdışıysa uyarı çıkar ve işlem yapılmaz |
| [lib/ui/views/individual_home_view.dart:228](../../lib/ui/views/individual_home_view.dart#L228) | <code>Future&lt;bool&gt; _loadDoors() async {</code> | Liste değişmediyse yeniden kurulmaz (`_sameDoors`), değiştiyse setState |
| [lib/ui/views/individual_home_view.dart:178](../../lib/ui/views/individual_home_view.dart#L178) | <code>Future&lt;void&gt; loadAll() async {</code> | Kapılar, cihazlar, başvurular ve daireler birlikte yeniden çekilir (HomePage global yenileme bunu çağırır) |
| [lib/ui/pages/home_page.dart:690](../../lib/ui/pages/home_page.dart#L690) | <code>bool _showsIndividualHome(UserSession session) {</code> | Bu görünümün ne zaman gösterildiğini belirler (bireysel, sakin modu, kapısız yönetici); görünüm "Kapılar" sayfasındadır (Panel artık modül vitrini; Geçiş Kontrol kapalıysa bölümler vitrinin altında) |
| [lib/ui/pages/home_page.dart:5266](../../lib/ui/pages/home_page.dart#L5266) | <code>await _individualHomeKey.currentState?.loadAll();</code> | Kapılar sayfasında AppBar Yenile / aşağı çekme bireysel görünümü de tazeler (Panel dalında da aynı çağrı vardır) |

**Olası nedenler**
- Kapı kaydındaki `assignedDeviceIsOnline` bayat: 15 sn aralıkla yenilenir; arka planda yoklama durur ve ön plana dönünce hemen yenilenir
- Başka sayfa üstteyken (TickerMode kapalı) yoklama yapılmaz
- Cihaz gerçekten çevrimdışı: kapı açma/QR/ekran-QR işlemleri `_requireOnlineDoor` ile engellenir ve "şu an çevrimdışı" snackbar'ı çıkar
- Bu görünüm yerine yönetici paneli gösteriliyor olabilir (`_showsIndividualHome` false): yanlış ekrana bakıyor olabilirsiniz

**Adım adım kontrol**
- Bölümün sağ üstündeki "Kapıları Yenile" düğmesine basın; durum değişiyor mu
- Çevrimdışı kalıyorsa aynı cihazı yönetici panelinde Detaylar bölümünde karşılaştırın
- Test: flutter test test/individual_home_polling_test.dart

**İlgili testler:** [test/individual_home_polling_test.dart](../../test/individual_home_polling_test.dart), [test/screens/individual_home_view_layout_test.dart](../../test/screens/individual_home_view_layout_test.dart)

**Bkz.:** [ui-kapi-durum-yoklama](#ui-kapi-durum-yoklama), [ui-bireysel-kapi-karti-dugmeleri](#ui-bireysel-kapi-karti-dugmeleri)

<a id="ui-bireysel-kapi-karti-dugmeleri"></a>
### ui-bireysel-kapi-karti-dugmeleri · Bireysel kapı kartında "Kapıyı Aç / Uzaktan Aç", "Kapıya QR Göster", "Kapı Ekranından QR Oku" ya da "Misafir Kodu" düğmesi eksik

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/individual_door_card.dart:116](../../lib/ui/widgets/individual_door_card.dart#L116) | <code>final hasQrPath = door.hasDisplay &#124;&#124; door.canShowQrCode;</code> | QR yolu varsa uzaktan açma ek yol sayılır ("Uzaktan Aç"), yoksa ana yol ("Kapıyı Aç") |
| [lib/ui/widgets/individual_door_card.dart:117](../../lib/ui/widgets/individual_door_card.dart#L117) | <code>final canRemoteOpen = door.canOpenRemote &amp;&amp; !door.isQrOnly;</code> | Uzaktan açma kapalı ya da yalnız QR kapıda "Kapıyı Aç" düğmesi hiç çizilmez |
| [lib/ui/widgets/individual_door_card.dart:136](../../lib/ui/widgets/individual_door_card.dart#L136) | <code>showScanScreenQr: door.hasDisplay,</code> | "Kapı Ekranından QR Oku" yalnız ekranlı cihazda (hasDisplay) |
| [lib/ui/widgets/individual_door_card.dart:137](../../lib/ui/widgets/individual_door_card.dart#L137) | <code>showShowQr: door.canShowQrCode,</code> | "Kapıya QR Göster": özellik açık + QR girişi aktif + fiziksel QR okuyucu |
| [lib/ui/widgets/individual_door_card.dart:138](../../lib/ui/widgets/individual_door_card.dart#L138) | <code>showGuestPass: door.canCreateGuestPass,</code> | "Misafir Kodu" site misafir geçişini kapattıysa gösterilmez |
| [lib/ui/widgets/individual_door_card.dart:140](../../lib/ui/widgets/individual_door_card.dart#L140) | <code>openState: isOpening</code> | Düğme durumu: komut sürüyor opening; cihaz çevrimiçi ready; aksi halde offline |

**Olası nedenler**
- Kapıda site politikası/özellik bayrağı kapalı: `featureRemoteOpenEnabled`, `featureQrEnabled`, `qrEntryActive`, `featureGuestPassEnabled` (site güvenlik politikası, bkz. politika girişi)
- Kapıdaki cihaz C3 ise optik QR okuyucu ve ekran yoktur: QR düğmeleri çıkmaz
- Cihaz atanmamış: kart "Cihaz Yok" rozetiyle gelir ve eylemler kapalıdır
- Sunucu eski sürüm alan göndermiyor: modelde varsayılan değerlerle eksik düğme oluşabilir (modeller başka bölümde)

**Adım adım kontrol**
- Yönetici olarak Siteler > Giriş & Güvenlik Politikaları ekranında ilgili özelliklerin açık olduğunu doğrulayın
- Kapı kartındaki rozetlerden (Çevrimiçi/Çevrimdışı/Cihaz Yok, kapsam) durumu okuyun
- Koşullar IndividualDoorCardModel testinde tablo hâlinde: flutter test test/screens/individual_door_card_model_test.dart

**İlgili testler:** [test/screens/individual_door_card_model_test.dart](../../test/screens/individual_door_card_model_test.dart), [test/screens/individual_door_card_test.dart](../../test/screens/individual_door_card_test.dart)

**Bkz.:** [ui-kapi-ac-sakin](#ui-kapi-ac-sakin), [ui-guvenlik-politikasi](#ui-guvenlik-politikasi), [ui-misafir-gecis-dugmesi](#ui-misafir-gecis-dugmesi)

<a id="ui-qr-modal-sure"></a>
### ui-qr-modal-sure · Karekod penceresi "Süresi Dolmuş QR Kod" diyor, yenilenmiyor ya da karekod yerine sürekli yükleniyor/hata görünüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/dynamic_qr_pass_modal.dart:168](../../lib/ui/widgets/dynamic_qr_pass_modal.dart#L168) | <code>if (status == AnimationStatus.dismissed) {</code> | Geri sayım sıfırlanınca "süresi doldu" durumuna geçilir, yoklama durur ve sesli uyarı verilir |
| [lib/ui/widgets/dynamic_qr_pass_modal.dart:409](../../lib/ui/widgets/dynamic_qr_pass_modal.dart#L409) | <code>Future&lt;void&gt; _fetchQrToken() async {</code> | Token alma/yenileme: durumları sıfırlar, (konum zorunluysa) konum alır, requestDoorQrToken çağırır |
| [lib/ui/widgets/dynamic_qr_pass_modal.dart:237](../../lib/ui/widgets/dynamic_qr_pass_modal.dart#L237) | <code>void _startStatusPolling(String qrToken) {</code> | Okuyucunun kodu kullanıp kullanmadığını 800 ms'de bir yoklar; arka planda durur |
| [lib/ui/widgets/dynamic_qr_pass_modal.dart:289](../../lib/ui/widgets/dynamic_qr_pass_modal.dart#L289) | <code>if (data?['used'] == true) {</code> | Kod kullanıldıysa "Geçiş Başarılı", 3,2 sn sonra pencere kendiliğinden kapanır |
| [lib/ui/widgets/dynamic_qr_pass_modal.dart:200](../../lib/ui/widgets/dynamic_qr_pass_modal.dart#L200) | <code>widget.authService?.revokeMyDoorQr(widget.door.id);</code> | Pencere kullanılmadan kapanınca token iptal edilir (kapatıp açınca eski kod geçersiz olur) |
| [lib/ui/widgets/dynamic_qr_pass_modal.dart:800](../../lib/ui/widgets/dynamic_qr_pass_modal.dart#L800) | <code>label: 'Yeni QR Kod Al',</code> | Süre dolunca yenileme düğmesi (`_fetchQrToken`); geçerliyken "Kodu Yenile" |
| [lib/ui/widgets/dynamic_qr_pass_modal.dart:516](../../lib/ui/widgets/dynamic_qr_pass_modal.dart#L516) | <code>static const Color _qrInk = Color(0xFF0F172A);</code> | Karekod hiçbir temada değişmez: koyu lacivert üstü beyaz (tarayıcı güvenilirliği) |

**Olası nedenler**
- Geri sayım süresi sunucudan gelir (`expires_in_seconds`/`validity_seconds`); yoksa `initialSeconds` (30) kullanılır
- Süre dolduğunda yeni kod otomatik alınmaz: kullanıcı "Yeni QR Kod Al" düğmesine basmalıdır
- `requestDoorQrToken` hata döndü: pencere hata bildirimi + "Tekrar Dene" gösterir (hata metni sunucudan; sunucu/QR bölümüne bakın)
- Yenilemede eski token sunucuda SUPERSEDED olur; eski karekodu gösterirseniz okuyucu reddeder
- Pencere kapatılınca (geçiş olmadıysa) token iptal edilir; aynı kodu tekrar kullanmak mümkün değildir

**Adım adım kontrol**
- Başlık rozetini okuyun: "Güvenli Kapı QR Kodu", "Süresi Dolmuş QR Kod", "Kullanılmış Karekod", "Yenilenmiş Karekod", "Kapı Uyuşmazlığı"
- Hata varsa metnini sunucudaki karşılığıyla eşleştirin (AuthApi.messageForErrorCode kullanılır)
- Test: flutter test test/qr_modal_polling_test.dart test/fix_fx2_qr_modal_test.dart

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/qr_modal_polling_test.dart test/fix_fx2_qr_modal_test.dart
```

**İlgili testler:** [test/qr_modal_polling_test.dart](../../test/qr_modal_polling_test.dart), [test/fix_fx2_qr_modal_test.dart](../../test/fix_fx2_qr_modal_test.dart), [test/screens/dynamic_qr_pass_modal_layout_test.dart](../../test/screens/dynamic_qr_pass_modal_layout_test.dart), [test/design/countdown_ring_test.dart](../../test/design/countdown_ring_test.dart)

**Bkz.:** [ui-qr-modal-ret](#ui-qr-modal-ret), [ui-qr-konum-hatasi](#ui-qr-konum-hatasi)

<a id="ui-qr-modal-ret"></a>
### ui-qr-modal-ret · Karekod penceresinde "Kapı Yetkisi Yok", "Karekod Girişi Kapalı", "Kullanılmış Karekod" ya da "Kapı Uyuşmazlığı" uyarısı çıkıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/dynamic_qr_pass_modal.dart:46](../../lib/ui/widgets/dynamic_qr_pass_modal.dart#L46) | <code>QrDenialInfo? qrDenialInfoFor(String? reason) {</code> | Sunucunun last_denial_reason kodunun kullanıcıya gösterilen başlık/mesaj/sesli metin karşılığı |
| [lib/ui/widgets/dynamic_qr_pass_modal.dart:373](../../lib/ui/widgets/dynamic_qr_pass_modal.dart#L373) | <code>final denial = qrDenialInfoFor(lastDenial);</code> | Aynı ret olayı (neden + zaman) bir kez gösterilir; kalıcı retlerde yoklama durur |
| [lib/ui/widgets/dynamic_qr_pass_modal.dart:351](../../lib/ui/widgets/dynamic_qr_pass_modal.dart#L351) | <code>if (lastDenial == 'DOOR_MISMATCH' &amp;&amp; !_isDoorMismatch) {</code> | Başka kapının karekodu okutuldu: 4 sn uyarı sonra yeniden denemeye döner |
| [lib/ui/widgets/dynamic_qr_pass_modal.dart:315](../../lib/ui/widgets/dynamic_qr_pass_modal.dart#L315) | <code>if (lastDenial == 'ALREADY_USED' &amp;&amp; !_isAlreadyUsed) {</code> | Tek kullanımlık kod tekrar okutuldu |
| [lib/ui/widgets/dynamic_qr_pass_modal.dart:333](../../lib/ui/widgets/dynamic_qr_pass_modal.dart#L333) | <code>if (lastDenial == 'SUPERSEDED' &amp;&amp; !_isSuperseded) {</code> | Kod yenilendiği için eski karekod hükümsüz |
| [lib/ui/widgets/dynamic_qr_pass_modal.dart:492](../../lib/ui/widgets/dynamic_qr_pass_modal.dart#L492) | <code>({String title, AppTone tone}) _headerState(QrDenialInfo? denial) {</code> | Başlık önceliği: geçiş başarılı > ret nedeni > kullanılmış > yenilenmiş > uyuşmazlık > süresi dolmuş > geçerli |

**Olası nedenler**
- ACCESS_REVOKED/QR_DISABLED/QR_ENTRY_INACTIVE/TOKEN_OR_USER_INACTIVE/ADMIN_REVOKED kalıcı retlerdir: yoklama durur, yeni kod alınabilir ama aynı politika sürerse yine reddedilir
- PULSE_FAILED geçicidir: kod hâlâ geçerli, okuyucuya tekrar gösterilmelidir (5 sn sonra uyarı kalkar)
- Kullanıcının kendi iptali (REVOKED/USER_REVOKED) ve bilinmeyen nedenler için ek uyarı gösterilmez (null döner)
- Yeni bir sunucu ret kodu eklendi ama `qrDenialInfoFor` içine eklenmedi: kullanıcı hiçbir açıklama görmez

**Adım adım kontrol**
- Ret kodunu sunucu karşılığıyla eşleştirin (QR kapısı/okuyucu bölümü) ve `qrDenialInfoFor` switch'inde olup olmadığına bakın
- Kalıcı retse site güvenlik politikasında "QR ile giriş" açık mı, kapıda QR girişi aktif mi, kullanıcının kapı yetkisi var mı kontrol edin
- Test: flutter test test/fix_fx2_qr_modal_test.dart

**İlgili testler:** [test/fix_fx2_qr_modal_test.dart](../../test/fix_fx2_qr_modal_test.dart), [test/qr_modal_polling_test.dart](../../test/qr_modal_polling_test.dart)

**Bkz.:** [ui-qr-modal-sure](#ui-qr-modal-sure), [ui-guvenlik-politikasi](#ui-guvenlik-politikasi), [ui-kapi-yetkileri](#ui-kapi-yetkileri)

<a id="ui-qr-konum-hatasi"></a>
### ui-qr-konum-hatasi · "Konum Hatası" penceresi çıkıyor ya da QR penceresi "konum doğrulaması zorunludur" uyarısı veriyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/resident_door_actions.dart:41](../../lib/ui/widgets/resident_door_actions.dart#L41) | <code>static Future&lt;void&gt; showQrPass(</code> | QR açmadan önce çevrimiçi kontrolü ve (gerekliyse) geofence doğrulaması; sakin kartı ve çekmece ("Kapıya QR Göster") bunu çağırır |
| [lib/ui/widgets/resident_door_actions.dart:53](../../lib/ui/widgets/resident_door_actions.dart#L53) | <code>if (door.requireGeofence) {</code> | requireGeofence true ise verifyWithinGeofence çağrılır; izin verilmezse "Konum Hatası" diyaloğu |
| [lib/ui/views/individual_home_view.dart:290](../../lib/ui/views/individual_home_view.dart#L290) | <code>Future&lt;void&gt; _openQrModal(DoorRecord requestedDoor) async {</code> | Bireysel görünümde aynı doğrulama; QR penceresi alt sayfa (bottom sheet) olarak açılır |
| [lib/ui/widgets/dynamic_qr_pass_modal.dart:439](../../lib/ui/widgets/dynamic_qr_pass_modal.dart#L439) | <code>if (widget.door.requireGeofence) {</code> | Token istemeden önce doğrulanmış konum alınır; alınamazsa pencere hata metnini gösterir |
| [lib/ui/widgets/dynamic_qr_pass_modal.dart:707](../../lib/ui/widgets/dynamic_qr_pass_modal.dart#L707) | <code>label: 'Konum Korumalı (~${door.geofenceRadiusMeters}m)',</code> | Konum korumalı kapıda pencerede bilgi rozeti |

**Olası nedenler**
- Telefon GPS/konum izni kapalı ya da konum bayat/yetersiz doğrulukta; sahte konum (mock) algılandı (GeofenceService, hizmetler bölümü)
- Kullanıcı kapı çevresi dışında (kapı yarıçapı: site güvenlik politikasında 10-2000 m)
- Politikada merkez koordinatı yanlış girildi: kapıya yakın olsa bile reddedilir
- Konum zorunlu değilse (requireGeofence false) bu adım hiç çalışmaz

**Adım adım kontrol**
- Telefonda konum servisini ve uygulama konum iznini açın; açık alanda tekrar deneyin
- Yönetici: Siteler > Giriş & Güvenlik Politikaları > konum merkezi ve mesafeyi doğrulayın ("Mevcut konumu kullan")
- Hata metni diyalogda tam gösterilir; sunucu kodlarıyla eşleştirin

**İlgili testler:** [test/geofence_and_site_policy_test.dart](../../test/geofence_and_site_policy_test.dart), [test/site_security_policy_dialog_test.dart](../../test/site_security_policy_dialog_test.dart), [test/screens/dynamic_qr_pass_modal_layout_test.dart](../../test/screens/dynamic_qr_pass_modal_layout_test.dart)

**Bkz.:** [ui-qr-modal-sure](#ui-qr-modal-sure), [ui-guvenlik-politikasi](#ui-guvenlik-politikasi), [ui-ekran-qr-oku](#ui-ekran-qr-oku)

<a id="ui-ekran-qr-oku"></a>
### ui-ekran-qr-oku · "Kapı Ekranından QR Oku" düğmesi görünmüyor ya da okutunca "Geçiş Reddedildi" çıkıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/resident_door_remote_card.dart:395](../../lib/ui/widgets/resident_door_remote_card.dart#L395) | <code>if (door?.hasDisplay == true) ...[</code> | Düğme yalnız ekranlı cihaz takılı kapıda görünür (hasDisplay) |
| [lib/ui/widgets/resident_door_actions.dart:98](../../lib/ui/widgets/resident_door_actions.dart#L98) | <code>static Future&lt;void&gt; scanScreenQr(</code> | Çevrimiçi kontrolü, QR tarama sayfası, sonra sunucuya karekod gönderimi |
| [lib/ui/widgets/resident_door_actions.dart:148](../../lib/ui/widgets/resident_door_actions.dart#L148) | <code>final (result, error) = await aService.openDoorWithScannedQr(</code> | Konum zorunluysa (requiresLocationForQrScan) AuthService konumu alır; reddedilirse nedeni diyalogda çıkar |
| [lib/ui/widgets/resident_door_actions.dart:159](../../lib/ui/widgets/resident_door_actions.dart#L159) | <code>title: 'Geçiş Reddedildi',</code> | Sunucu retleri bu diyalogda tam metinle gösterilir |
| [lib/ui/views/individual_home_view.dart:343](../../lib/ui/views/individual_home_view.dart#L343) | <code>Future&lt;void&gt; _handleScanScreenQr(DoorRecord requestedDoor) async {</code> | Bireysel görünümdeki aynı akış (başarıda loadAll + onRefreshAll ile liste tazelenir) |

**Olası nedenler**
- Kapıdaki cihaz ekranlı değil (C3): `hasDisplay` false olduğundan düğme çizilmez
- Cihaz çevrimdışı: dokunuş "şu an çevrimdışı" uyarısı verir, tarama açılmaz
- Başarıda ikinci bir "kapı aç" komutu bilerek gönderilmez (sunucu zaten açar; çift tetik/çift log olmasın)
- Sunucu karekodu, yetkiyi ya da konumu reddetti: metin "Geçiş Reddedildi" diyaloğunda tam olarak çıkar (sunucu bölümüne bakın)

**Adım adım kontrol**
- Kapı kartında donanım rozeti ESP32-WROOM mu (ekranlı) kontrol edin
- Kapı ekranında karekod görünüyor mu (ekran cihaz tarafında), tarama sayfasındaki talimat metni: "Cihazın 2.4" ekranındaki karekodu kameranıza gösterin."
- Reddetme metnini sunucu günlüğüyle eşleştirin

**İlgili testler:** [test/screens/resident_door_remote_card_layout_test.dart](../../test/screens/resident_door_remote_card_layout_test.dart), [test/screens/individual_door_card_test.dart](../../test/screens/individual_door_card_test.dart)

**Bkz.:** [ui-qr-tarama-sayfasi](#ui-qr-tarama-sayfasi), [ui-qr-konum-hatasi](#ui-qr-konum-hatasi)

<a id="ui-qr-tarama-sayfasi"></a>
### ui-qr-tarama-sayfasi · QR tarama sayfası açılmıyor, "bu platformda desteklenmiyor" diyor ya da okunan değer bozuk (büyük harfe dönmüş)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/qr_scan_page.dart:37](../../lib/ui/pages/qr_scan_page.dart#L37) | <code>bool get _isSupportedPlatform {</code> | Android, iOS, macOS ve web desteklenir; Windows/Linux/Fuchsia'da kamera taraması kapalıdır |
| [lib/ui/pages/qr_scan_page.dart:106](../../lib/ui/pages/qr_scan_page.dart#L106) | <code>'Bu platformda kamera ile QR tarama desteklenmiyor. Şirket uygulamasını Android veya iPho…</code> | Desteklenmeyen platformda çıkan düz metin ekranı |
| [lib/ui/pages/qr_scan_page.dart:72](../../lib/ui/pages/qr_scan_page.dart#L72) | <code>widget.preserveCase ? rawValue : rawValue.toUpperCase(),</code> | Okunan değer varsayılan olarak BÜYÜK HARFE çevrilir; Wi-Fi gibi büyük/küçük harf duyarlı içerikte preserveCase true olmalı |
| [lib/ui/pages/qr_scan_page.dart:31](../../lib/ui/pages/qr_scan_page.dart#L31) | <code>detectionSpeed: DetectionSpeed.noDuplicates,</code> | Aynı kod tekrar tetiklenmez; ilk geçerli değerle sayfa kapanır (`_handled`) |
| [lib/ui/pages/wifi_provision_page.dart:263](../../lib/ui/pages/wifi_provision_page.dart#L263) | <code>preserveCase: true,</code> | Wi-Fi karekodu için harf duyarlılığı korunur |
| [lib/ui/dialogs/submit_join_request_dialog.dart:79](../../lib/ui/dialogs/submit_join_request_dialog.dart#L79) | <code>final clean = scanned.replaceAll(RegExp(r'^SITE_JOIN:', caseSensitive: false), '').trim();</code> | Site katılım QR'ı "SITE_JOIN:" önekiyle gelir ve burada temizlenir; QrScanPage değeri büyük harfe çevirdiği için önek regex'i büyük/küçük harf duyarsızdır |

**Olası nedenler**
- Masaüstü (Windows) derlemesinde kamera taraması bilerek kapalıdır: metin ekranı çıkar
- Kamera izni: sayfada izin reddi için özel bir ekran yoktur (mobile_scanner paketi yönetir); telefon ayarlarından uygulamanın kamera iznine bakın
- Yeni bir tarama akışında `preserveCase` verilmedi: şifre/SSID gibi değerler büyük harfe dönüşür
- QR içeriği bu akışın beklediği biçimde değil: ilgili diyalog kendi hata metnini gösterir

**Adım adım kontrol**
- Cihaz platformunu doğrulayın (telefon mu, masaüstü mü)
- Telefon ayarlarında uygulamanın kamera iznini kontrol edin
- Wi-Fi karekodu için ayrıştırıcı testi: flutter test test/wifi_qr_parser_test.dart

**İlgili testler:** [test/wifi_qr_parser_test.dart](../../test/wifi_qr_parser_test.dart), [test/screens/claim_device_dialog_layout_test.dart](../../test/screens/claim_device_dialog_layout_test.dart)

**Bkz.:** [ui-wifi-karekod](#ui-wifi-karekod), [ui-cihaz-sahiplen](#ui-cihaz-sahiplen)

<a id="ui-misafir-gecis-dugmesi"></a>
### ui-misafir-gecis-dugmesi · "Kurye / Misafir Geçişi" düğmesi görünmüyor ya da link oluşturunca paylaşım penceresi/kopyalama çalışmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/admin_door_status_card.dart:405](../../lib/ui/widgets/admin_door_status_card.dart#L405) | <code>if (door.canCreateGuestPass)</code> | Yönetici kartında yalnız site misafir geçişini kapatmadıysa gösterilir |
| [lib/ui/widgets/resident_door_remote_card.dart:408](../../lib/ui/widgets/resident_door_remote_card.dart#L408) | <code>if (door?.canCreateGuestPass == true) ...[</code> | Sakin kartında aynı kural |
| [lib/ui/pages/home_page.dart:6117](../../lib/ui/pages/home_page.dart#L6117) | <code>onCreateGuestPass: () {</code> | Panel düğmesi: seçili kapı yoksa hiçbir şey yapmaz |
| [lib/ui/dialogs/create_guest_pass_dialog.dart:120](../../lib/ui/dialogs/create_guest_pass_dialog.dart#L120) | <code>final (passType, durationMinutes, maxUses) = switch (_selectedPreset) {</code> | Ön ayarlar: tek kullanımlık 30 dk (1), 2 saat (5 kullanım), 12 saat (10 kullanım) |
| [lib/ui/dialogs/create_guest_pass_dialog.dart:67](../../lib/ui/dialogs/create_guest_pass_dialog.dart#L67) | <code>await SharePlus.instance.share(</code> | Paylaşım başarısızsa mesaj panoya kopyalanır (yedek akış) |
| [lib/ui/dialogs/create_guest_pass_dialog.dart:54](../../lib/ui/dialogs/create_guest_pass_dialog.dart#L54) | <code>Clipboard.setData(ClipboardData(text: pass.webUrl));</code> | "Linki Kopyala" düğmesi |

**Olası nedenler**
- Site politikasında misafir geçişi kapalı (`featureGuestPassEnabled`): düğme hiç çizilmez; link açılışta da reddedilirdi
- Kapı seçili değil: panel düğmesi sessizce bir şey yapmaz
- Sunucu link üretirken hata döndürdü: diyalog içinde hata metni (`_error`) gösterilir
- Paylaşım sayfası bazı cihazlarda açılmaz: kod yedek olarak panoya kopyalar ve mesaj çıkarır

**Adım adım kontrol**
- Yönetici: Siteler > Giriş & Güvenlik Politikaları > Misafir/Kurye geçişi açık mı
- Diyalogdaki ön ayarı değiştirip tekrar oluşturun; hata metnini not edin
- Test: flutter test test/create_guest_pass_dialog_test.dart

**İlgili testler:** [test/create_guest_pass_dialog_test.dart](../../test/create_guest_pass_dialog_test.dart), [test/screens/create_guest_pass_dialog_layout_test.dart](../../test/screens/create_guest_pass_dialog_layout_test.dart)

**Bkz.:** [ui-bireysel-kapi-karti-dugmeleri](#ui-bireysel-kapi-karti-dugmeleri), [ui-guvenlik-politikasi](#ui-guvenlik-politikasi)

<a id="ui-cihaz-sahiplen"></a>
### ui-cihaz-sahiplen · Cihaz sahiplenme penceresinde hata çıkıyor ("Cihaz sahiplenme sırasında bir hata oluştu") ya da kutu QR okununca cihaz hesaba bağlanmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/widgets/claim_device_dialog.dart:50](../../lib/ui/widgets/claim_device_dialog.dart#L50) | <code>Future&lt;void&gt; _submitClaim(String deviceInput) async {</code> | Girdiyi kırpar, boşsa uyarır, claimDevice çağırır; başarıda diyalog cihaz UID'si ile kapanır |
| [lib/ui/widgets/claim_device_dialog.dart:65](../../lib/ui/widgets/claim_device_dialog.dart#L65) | <code>final res = await widget.authService.claimDevice(deviceInput: clean);</code> | Sunucu çağrısı; ApiException mesajı doğrudan kullanıcıya gösterilir |
| [lib/ui/widgets/claim_device_dialog.dart:83](../../lib/ui/widgets/claim_device_dialog.dart#L83) | <code>_errorMessage = 'Cihaz sahiplenme sırasında bir hata oluştu.';</code> | ApiException dışındaki her hata (ağ, ayrıştırma) bu genel metne düşer |
| [lib/ui/widgets/claim_device_dialog.dart:93](../../lib/ui/widgets/claim_device_dialog.dart#L93) | <code>title: 'Kutu QR Kodunu Tara',</code> | QR tarama sayfasının başlığı; okunan değer büyük harfe çevrilip claim'e gider |
| [lib/ui/widgets/claim_device_dialog.dart:211](../../lib/ui/widgets/claim_device_dialog.dart#L211) | <code>onSubmitted: (val) =&gt; _submitClaim(val),</code> | Elle UID girişinde Enter da gönderir |

**Olası nedenler**
- Cihaz başka hesapta sahipli, kayıtsız ya da UID yanlış: sunucu ApiException mesajıyla reddeder (sunucu bölümü)
- QR kutu etiketinden farklı içerik okundu: sunucu cihazı tanımaz
- Ağ hatası/zaman aşımı: genel "hata oluştu" metni çıkar
- Diyalog sonrası liste güncellenmiyorsa çağıran taraf yenilemiyor (bkz. cihaz ekleme sonrası yenileme girişi)

**Adım adım kontrol**
- Seri no/UID'yi elle girerek deneyin ("Seri No / UID ile Elle Ekle")
- Hata metnini sunucu günlüğüyle eşleştirin (claim isteği)
- Test: flutter test test/screens/claim_device_dialog_layout_test.dart

**İlgili testler:** [test/screens/claim_device_dialog_layout_test.dart](../../test/screens/claim_device_dialog_layout_test.dart), [test/deep_link_dialogs_test.dart](../../test/deep_link_dialogs_test.dart)

**Bkz.:** [ui-cihaz-ekle-sonrasi](#ui-cihaz-ekle-sonrasi), [ui-qr-tarama-sayfasi](#ui-qr-tarama-sayfasi)

<a id="ui-cihaz-ekle-sonrasi"></a>
### ui-cihaz-ekle-sonrasi · Cihaz eklendikten/sahiplenildikten sonra liste ve panel güncellenmiyor ya da site kurulum sihirbazı açılmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:4240](../../lib/ui/pages/home_page.dart#L4240) | <code>Future&lt;void&gt; _openClaimDeviceFlow() async {</code> | Sahiplenme sonrası cihaz listesi + kapı paneli yenilenir; hiç site yoksa SetupSiteDialog açılır |
| [lib/ui/pages/home_page.dart:4257](../../lib/ui/pages/home_page.dart#L4257) | <code>final hasSites = _doorControlSitesPage?.sites.isNotEmpty ?? false;</code> | Sihirbaz yalnız yönettiği site olmayan kullanıcıya açılır |
| [lib/ui/pages/home_page.dart:4443](../../lib/ui/pages/home_page.dart#L4443) | <code>_showMessage('Cihaz başarıyla kaydedildi.');</code> | Süper kullanıcı/yönetici elle kayıt: cihaz, site ve panel listeleri yeniden yüklenir |
| [lib/ui/views/individual_home_view.dart:467](../../lib/ui/views/individual_home_view.dart#L467) | <code>Future&lt;void&gt; _openClaimDialog() async {</code> | Bireysel görünümde sahiplenme sonrası loadAll + onRefreshAll, ardından kurulum sihirbazı |
| [lib/ui/views/individual_home_view.dart:510](../../lib/ui/views/individual_home_view.dart#L510) | <code>Future&lt;void&gt; _openSetupSite([String? uid]) async {</code> | Kurulum başarılıysa onRefreshAll (HomePage `_loadInitialData`) çağrılır |
| [lib/ui/views/join_and_setup_view.dart:54](../../lib/ui/views/join_and_setup_view.dart#L54) | <code>widget.onOpenClaimDevice();</code> | Katıl & Cihaz Ekle ekranında akış HomePage'e devredilir, ardından başvurular yeniden yüklenir |

**Olası nedenler**
- Yeni bir diyalog akışı eklendi ama sonunda ilgili yükleyici (`_loadCompanyDevices`, `_loadSites`, `_loadDoorControlSites`) çağrılmadı (AGENTS.md kural 7)
- Kullanıcının zaten yönettiği site var (`hasSites` true): kurulum sihirbazı bilerek açılmaz
- Cihaz envanteri sayfalıdır (sayfa başına 10): `_loadCompanyDevices(force: true)` sayfa 1'i çeker; yeni cihaz başka sayfada kalmış olabilir
- Sihirbaz iptal edildi (`false`): yenileme çağrılmaz

**Adım adım kontrol**
- AppBar "Yenile" ya da aşağı çekme ile elle yenileyin: veri geliyorsa eksik olan otomatik yenilemedir
- İlgili `_open...Flow` fonksiyonunun sonunda yükleyici çağrılarını inceleyin
- Test: flutter test test/join_and_setup_view_test.dart test/screens/join_and_setup_view_layout_test.dart

**İlgili testler:** [test/join_and_setup_view_test.dart](../../test/join_and_setup_view_test.dart), [test/screens/join_and_setup_view_layout_test.dart](../../test/screens/join_and_setup_view_layout_test.dart), [test/home_page_state_test.dart](../../test/home_page_state_test.dart)

**Bkz.:** [ui-cihaz-sahiplen](#ui-cihaz-sahiplen), [ui-kurulum-sihirbazi](#ui-kurulum-sihirbazi), [ui-cihaz-envanteri](#ui-cihaz-envanteri)

<a id="ui-kurulum-sihirbazi"></a>
### ui-kurulum-sihirbazi · "Site Kurulum Sihirbazı" (ya da site başvurusu) penceresinde blok/kapı eklerken ya da kaydederken hata alınıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/dialogs/setup_site_dialog.dart:439](../../lib/ui/dialogs/setup_site_dialog.dart#L439) | <code>Future&lt;void&gt; _submit() async {</code> | Doğrulama, blok/kapı yüklerini hazırlar; anlık kipte authService.setupSite, başvuru kipinde createSiteApplication çağırır |
| [lib/ui/dialogs/setup_site_dialog.dart:373](../../lib/ui/dialogs/setup_site_dialog.dart#L373) | <code>void _addBlock() {</code> | Yeni blok adı mevcutlarla çakışmayacak ilk "<harf> Blok" olarak seçilir (sunucu yinelenen adı 400 ile reddeder) |
| [lib/ui/dialogs/setup_site_dialog.dart:431](../../lib/ui/dialogs/setup_site_dialog.dart#L431) | <code>String? _validateApartmentCount(String? value) {</code> | Daire sayısı 1 ile 5000 arasında olmalı; geçersizse alan altında uyarı çıkar ve gönderim yapılmaz |
| [lib/ui/dialogs/setup_site_dialog.dart:512](../../lib/ui/dialogs/setup_site_dialog.dart#L512) | <code>await widget.authService.setupSite(</code> | Sunucu çağrısı; ApiException mesajı `_error` ile diyalogda gösterilir |
| [lib/ui/dialogs/setup_site_dialog.dart:544](../../lib/ui/dialogs/setup_site_dialog.dart#L544) | <code>final switchToApplication = !_isApplication &amp;&amp; e.code == 'APPLICATION_REQUIRED';</code> | Anlık kurulum kapalıysa (409 APPLICATION_REQUIRED) pencere başvuru kipine geçer, girilen bilgiler korunur |
| [lib/ui/dialogs/setup_site_dialog.dart:590](../../lib/ui/dialogs/setup_site_dialog.dart#L590) | <code>: 'Site kurulumu sırasında bir hata oluştu.';</code> | ApiException dışı hata genel metne düşer (başvuru kipinde "Başvuru gönderilemedi. ...") |
| [lib/ui/dialogs/setup_site_dialog.dart:276](../../lib/ui/dialogs/setup_site_dialog.dart#L276) | <code>if (_blocks.isEmpty) _blocks.add(_BlockDraft(name: 'A Blok', apartmentCount: 10));</code> | Başlangıç değeri 1 blok x 10 daire, 1 kapı |

**Olası nedenler**
- Aynı blok adı iki kez girildi: sunucu reddeder
- Daire sayısı boş ya da 1-5000 dışında ("Daire sayısı 1 ile 5000 arasında olmalı.") ya da toplam daire 5000'i aşıyor ("Toplam daire sayısı en fazla 5000 olabilir."): gönderim yapılmaz
- Hesap anında site kuramıyor (sunucu 409 APPLICATION_REQUIRED): pencere "Site eklemek için başvuru yapmanız gerekiyor..." deyip başvuru kipine geçer; "Başvuruyu Gönder" ile devam edilir
- Pencere bir cihaz UID değeriyle açıldıysa (`deviceUid`) bu değer kuruluma iletilir; cihazla ilgili ret sunucudan hata metniyle gelir (sunucu bölümüne bakın)

**Adım adım kontrol**
- Diyalogdaki kırmızı hata bildirimini okuyun
- Test: flutter test test/fix_fx2_widgets_test.dart (blok adı çakışması) ve test/screens/setup_site_dialog_layout_test.dart

**İlgili testler:** [test/screens/setup_site_dialog_layout_test.dart](../../test/screens/setup_site_dialog_layout_test.dart), [test/fix_fx2_widgets_test.dart](../../test/fix_fx2_widgets_test.dart)

**Bkz.:** [ui-cihaz-ekle-sonrasi](#ui-cihaz-ekle-sonrasi), [ui-site-listesi-yenilenmiyor](#ui-site-listesi-yenilenmiyor)

<a id="ui-kapi-cihaz-ata"></a>
### ui-kapi-cihaz-ata · Kapıya cihaz atama/çıkarma penceresi hata veriyor ya da işlemden sonra kapı kartı eski cihazı gösteriyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:4137](../../lib/ui/pages/home_page.dart#L4137) | <code>Future&lt;void&gt; _assignDoorDevice(DoorRecord door) async {</code> | Atama/çıkarma sonucu burada işlenir ve site yapısı, kapı paneli, cihaz envanteri yeniden yüklenir |
| [lib/ui/pages/home_page.dart:4148](../../lib/ui/pages/home_page.dart#L4148) | <code>await widget.authService.unassignDoorDevice(doorId: door.id);</code> | Çıkarma ucu; hata metni "Cihaz kapıdan çıkarılamadı: ..." snackbar'ı |
| [lib/ui/dialogs/door_device_dialog.dart:272](../../lib/ui/dialogs/door_device_dialog.dart#L272) | <code>validator: (value) =&gt; (value ?? '').trim().length &lt; 6</code> | UID en az 6 karakter; sonuç büyük harfe çevrilerek döner |
| [lib/ui/dialogs/door_device_dialog.dart:284](../../lib/ui/dialogs/door_device_dialog.dart#L284) | <code>final success = await ReplaceDeviceDialog.show(</code> | Pencereden "Arızalı Cihazı Değiştir" akışı; başarıda atama penceresi de kapanır |
| [lib/ui/dialogs/door_device_dialog.dart:322](../../lib/ui/dialogs/door_device_dialog.dart#L322) | <code>class DeviceDoorAssignDialog extends StatefulWidget {</code> | Cihaz envanterinden "Kapıya Ata": site seç > kapı seç; site yoksa Ata düğmesi kapalı |
| [lib/ui/widgets/door_card.dart:166](../../lib/ui/widgets/door_card.dart#L166) | <code>label: Text(hasDevice ? 'Değiştir' : 'Cihaz Ata'),</code> | Kapı kartındaki ana düğme |

**Olası nedenler**
- UID sunucuda yok ya da başka kapıya/sahibe bağlı: sunucu mesajı snackbar'da (`_showMessage`) görünür
- Atanabilir cihaz listesi boş: "Kullanılabilir Cihazlarınız" bölümü çıkmaz; UID elle girilir
- İşlem başarılı ama sonrasında `_selectSite`/`_loadDoorControlSites` çağrılmazsa kart eski kalır (kural 7)
- `DeviceDoorAssignDialog` site listesi boş verildi: `_loadSites` açılışta yalnız site yöneticisi/süper kullanıcı için çağrılır; bireysel/sakin rolünde "Siteler" menüsü açılmadan "Kapıya Ata" boş site listesiyle açılır ve Ata düğmesi pasif kalır

**Adım adım kontrol**
- Siteler ekranında ilgili sitenin yapısını yenileyin (aşağı çekme)
- Cihaz envanterinde cihazın "Kapıya atanmış" grubunda olup olmadığına bakın
- Snackbar metnini sunucu tarafındaki atama ucu mesajıyla eşleştirin

**İlgili testler:** [test/screens/door_device_dialog_layout_test.dart](../../test/screens/door_device_dialog_layout_test.dart), [test/screens/replace_device_dialog_layout_test.dart](../../test/screens/replace_device_dialog_layout_test.dart)

**Bkz.:** [ui-cihaz-degistir](#ui-cihaz-degistir), [ui-cihaz-envanteri](#ui-cihaz-envanteri), [ui-kapi-yonet-yenilenmiyor](#ui-kapi-yonet-yenilenmiyor)

<a id="ui-cihaz-degistir"></a>
### ui-cihaz-degistir · "Arızalı Cihazı Değiştir" penceresi hata veriyor ya da değiştirme sonrası kapı hâlâ eski cihazı gösteriyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/dialogs/replace_device_dialog.dart:116](../../lib/ui/dialogs/replace_device_dialog.dart#L116) | <code>final res = await widget.authService.replaceDoorDevice(</code> | Yeni cihazın QR/seri no'su ile kapıdaki cihaz değiştirilir (yetkiler ve ayarlar sunucuda korunur) |
| [lib/ui/dialogs/replace_device_dialog.dart:72](../../lib/ui/dialogs/replace_device_dialog.dart#L72) | <code>return uid != currentUid;</code> | Kapıdaki mevcut cihaz atanabilir listeden çıkarılır |
| [lib/ui/dialogs/replace_device_dialog.dart:32](../../lib/ui/dialogs/replace_device_dialog.dart#L32) | <code>barrierDismissible: false,</code> | Dışarı dokunarak kapatılamaz; "Vazgeç" düğmesi gerekir |
| [lib/ui/pages/home_page.dart:4349](../../lib/ui/pages/home_page.dart#L4349) | <code>Future&lt;void&gt; _openReplaceDeviceDialog(DoorRecord door) async {</code> | Başarıda site yapısı, kapı paneli ve cihaz envanteri yenilenir |
| [lib/ui/widgets/door_card.dart:224](../../lib/ui/widgets/door_card.dart#L224) | <code>const Flexible(child: Text('Arızalı Cihazı Değiştir')),</code> | Menü öğesi yalnız kapıda cihaz varsa ve `onReplaceDevice` verilmişse görünür |

**Olası nedenler**
- Yeni cihaz başka sahibe bağlı ya da UID tanınmıyor: ApiException mesajı diyalogda gösterilir
- Kapıda cihaz yoksa menü öğesi hiç çizilmez (`hasDevice` false)
- Yenileme çağrılarından biri atlanırsa kapı kartı/panel eski cihazı gösterir

**Adım adım kontrol**
- Hata bildirimini okuyun ve cihaz UID'sini envanterde arayın
- Başarı snackbar'ı çıktıysa Siteler ve Kayıtlı Cihazlar ekranlarını yenileyin

**İlgili testler:** [test/screens/replace_device_dialog_layout_test.dart](../../test/screens/replace_device_dialog_layout_test.dart)

**Bkz.:** [ui-kapi-cihaz-ata](#ui-kapi-cihaz-ata), [ui-cihaz-envanteri](#ui-cihaz-envanteri)

<a id="ui-kapi-yonet-yenilenmiyor"></a>
### ui-kapi-yonet-yenilenmiyor · Kapı eklendikten/düzenlendikten/silindikten sonra site ekranındaki kapı listesi ya da kapı paneli güncellenmiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:4180](../../lib/ui/pages/home_page.dart#L4180) | <code>Future&lt;void&gt; _openDoorDialog({DoorRecord? door}) async {</code> | Atanabilir cihazlar çekilir, DoorEditDialog açılır, başarıda site yapısı ve panel yenilenir |
| [lib/ui/pages/home_page.dart:4199](../../lib/ui/pages/home_page.dart#L4199) | <code>_showMessage(door == null ? 'Yeni kapı oluşturuldu.' : 'Kapı güncellendi.');</code> | Başarıdan hemen sonra `_selectSite(site)` ve `_loadDoorControlSites()` çağrılır |
| [lib/ui/pages/home_page.dart:4205](../../lib/ui/pages/home_page.dart#L4205) | <code>Future&lt;void&gt; _deleteDoor(DoorRecord door) async {</code> | Silme onayı sonrası `deleteDoor`; başarıda site yapısı ve kapı paneli yeniden yüklenir, atanmış cihaz serbest kalır |
| [lib/ui/dialogs/door_edit_dialog.dart:102](../../lib/ui/dialogs/door_edit_dialog.dart#L102) | <code>await widget.authService.createDoor(</code> | Yeni kapı oluşturma çağrısı; hata diyalogda kalır, başarıda true ile kapanır |
| [lib/ui/dialogs/door_edit_dialog.dart:123](../../lib/ui/dialogs/door_edit_dialog.dart#L123) | <code>_errorMessage = 'İşlem sırasında bir hata oluştu: $e';</code> | ApiException dışı hata ham istisna metniyle gösterilir |
| [lib/ui/widgets/door_card.dart:39](../../lib/ui/widgets/door_card.dart#L39) | <code>final hasMenu = (hasDevice &amp;&amp; onReplaceDevice != null) &#124;&#124;</code> | Kapı kartındaki ... menüsü yalnız en az bir eylem verilmişse çizilir |

**Olası nedenler**
- Diyalog sonucu `true` değilse (iptal/hata) yenileme çağrılmaz: yalnız başarıda `_selectSite` ve `_loadDoorControlSites` çalışır
- Kapsam (SITE_COMMON / BLOCK) ve blok seçimi diyalogda yapılır; BLOCK dışında blockId gönderilmez (`_selectedScope == BLOCK ? _selectedBlockId : null`)
- Silmede sunucu hatası: snackbar "Kapı silinemedi: ..." ve liste değişmez
- Bireysel görünümde kapı listesi ayrı yüklenir (`listMyDoors`) ve 15 sn yoklanır; sakin kumandasında kapı listesi yalnız açılış/yenilemede yüklenir

**Adım adım kontrol**
- Siteler ekranında ilgili siteyi seçip aşağı çekin (`_handleGlobalRefresh` siteyi ve yapısını yeniler)
- Snackbar metnini okuyun ("Yeni kapı oluşturuldu." / "Kapı güncellendi." / "Kapı silindi.")
- Test: flutter test test/screens/door_edit_dialog_layout_test.dart test/screens/sites_view_layout_test.dart

**İlgili testler:** [test/screens/door_edit_dialog_layout_test.dart](../../test/screens/door_edit_dialog_layout_test.dart), [test/screens/sites_view_layout_test.dart](../../test/screens/sites_view_layout_test.dart)

**Bkz.:** [ui-kapi-cihaz-ata](#ui-kapi-cihaz-ata), [ui-site-listesi-yenilenmiyor](#ui-site-listesi-yenilenmiyor)

<a id="ui-wifi-kurulum"></a>
### ui-wifi-kurulum · Bluetooth ile Wi-Fi kurulum ekranında cihaz listesi boş, cihaza bağlanılamıyor ya da Wi-Fi bilgileri cihaza kaydedilemiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:4750](../../lib/ui/pages/home_page.dart#L4750) | <code>Future&lt;void&gt; _openWifiProvision() async {</code> | Sayfayı açar ve rol rengini (accentColor/surfaceColor) geçirir |
| [lib/ui/views/bluetooth_wifi_view.dart:54](../../lib/ui/views/bluetooth_wifi_view.dart#L54) | <code>onPressed: onOpenWifiProvision,</code> | Menüdeki kart yalnız bu düğmeyle kurulum sayfasını açar |
| [lib/ui/pages/wifi_provision_page.dart:159](../../lib/ui/pages/wifi_provision_page.dart#L159) | <code>Future&lt;void&gt; _scanDevices() async {</code> | Açılışta otomatik BLE taraması; cihaz yoksa "Kurulum modunda cihaz bulunamadı" mesajı |
| [lib/ui/pages/wifi_provision_page.dart:190](../../lib/ui/pages/wifi_provision_page.dart#L190) | <code>Future&lt;void&gt; _connectDevice(BleProvisionDevice device) async {</code> | Cihaza bağlanır, durum ve son sonucu okur; cihaz kurulum modunda değilse uyarır |
| [lib/ui/pages/wifi_provision_page.dart:293](../../lib/ui/pages/wifi_provision_page.dart#L293) | <code>Future&lt;void&gt; _saveWifi() async {</code> | Önce cihazın unique id'sini okur, sonra sunucudan MQTT kimliği alır, sonra SSID/şifre ile birlikte cihaza yazar |
| [lib/ui/pages/wifi_provision_page.dart:324](../../lib/ui/pages/wifi_provision_page.dart#L324) | <code>await authService.getDeviceMqttCredentials(deviceUid: deviceUid);</code> | Cihaz hesaba kayıtlı değilse burada hata döner (kayıt sırası talimatın 2. adımıdır) |
| [lib/ui/pages/wifi_provision_page.dart:470](../../lib/ui/pages/wifi_provision_page.dart#L470) | <code>if (!_service.isSupportedPlatform)</code> | Masaüstü derlemelerinde BLE kurulumu kapalıdır; bilgi metni gösterilir |
| [lib/ui/pages/wifi_provision_page.dart:800](../../lib/ui/pages/wifi_provision_page.dart#L800) | <code>static Color _barColorFor(Color accent) {</code> | Rol renginden okunur başlık çubuğu rengi seçilir (kontrast >= 4,5:1) |

**Olası nedenler**
- Cihaz kurulum modunda değil (Wi-Fi ayarı kayıtlı): cihazdaki butona 3 sn basılarak sıfırlanmalıdır (ekranda yazar)
- Telefonda Bluetooth/konum izni kapalı: BleProvisionException mesajı snackbar'da görünür (servis ayrı bölümde)
- Cihaz şirket/kullanıcı hesabına kayıtlı değil: MQTT kimliği alınamaz, "MQTT cihaz kimliği alınamadı" benzeri hata
- Oturum yok (`authService == null`): "MQTT kimliği alınacak oturum bulunamadı."
- Seçili ağ için şifre boş: "Seçilen ağ için şifre girin." (kaydetmeden döner)
- Masaüstünde açıldı: BLE desteklenmediği için liste boş kalır

**Adım adım kontrol**
- Ekrandaki durum kutusunu okuyun: Unique ID, Kayıtlı SSID, Wi-Fi Durumu, IP, MQTT Kimliği (Hazır / Eksik)
- "Durumu Yenile" düğmesiyle cihaz durumunu yeniden okuyun
- Snackbar metnini cihaz/firmware tarafındaki BLE sonuç mesajlarıyla eşleştirin (firmware bölümü)
- Test: flutter test test/wifi_provision_page_layout_test.dart test/ble_wifi_provision_service_test.dart

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/wifi_provision_page_layout_test.dart test/ble_wifi_provision_service_test.dart
```

**İlgili testler:** [test/wifi_provision_page_layout_test.dart](../../test/wifi_provision_page_layout_test.dart), [test/screens/wifi_provision_screen_layout_test.dart](../../test/screens/wifi_provision_screen_layout_test.dart), [test/ble_wifi_provision_service_test.dart](../../test/ble_wifi_provision_service_test.dart), [test/screens/bluetooth_wifi_view_layout_test.dart](../../test/screens/bluetooth_wifi_view_layout_test.dart)

**Bkz.:** [ui-wifi-karekod](#ui-wifi-karekod), [ui-qr-tarama-sayfasi](#ui-qr-tarama-sayfasi)

<a id="ui-wifi-karekod"></a>
### ui-wifi-karekod · "Geçerli bir Wi-Fi karekodu bulunamadı" uyarısı çıkıyor ya da modem karekodu okununca ağ adı/şifre doğru dolmuyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/wifi_provision_page.dart:31](../../lib/ui/pages/wifi_provision_page.dart#L31) | <code>static WifiQrCredentials? tryParse(String? raw) {</code> | Karekod metnini ağ bilgisine çevirir (standart WIFI: biçimi, yedek olarak JSON) |
| [lib/ui/pages/wifi_provision_page.dart:37](../../lib/ui/pages/wifi_provision_page.dart#L37) | <code>if (text.toLowerCase().startsWith('wifi:')) {</code> | Standart WIFI:T:WPA;S:ad;P:şifre;H:false;; biçimi; kaçışlı karakterler (\; \: \\) çözülür |
| [lib/ui/pages/wifi_provision_page.dart:79](../../lib/ui/pages/wifi_provision_page.dart#L79) | <code>if (text.startsWith('{') &amp;&amp; text.endsWith('}')) {</code> | Yedek biçim: {"ssid":..., "password":...} JSON |
| [lib/ui/pages/wifi_provision_page.dart:256](../../lib/ui/pages/wifi_provision_page.dart#L256) | <code>Future&lt;void&gt; _scanWifiQr() async {</code> | QR sayfasını açar, sonucu ayrıştırır, SSID ve şifre alanlarını doldurur |
| [lib/ui/pages/wifi_provision_page.dart:275](../../lib/ui/pages/wifi_provision_page.dart#L275) | <code>'Geçerli bir Wi-Fi karekodu bulunamadı. Lütfen modem veya Wi-Fi paylaşım karekodu okutun.…</code> | Ayrıştırma null dönünce kullanıcıya gösterilen uyarı |

**Olası nedenler**
- Karekod Wi-Fi paylaşım biçiminde değil (örn. cihaz/site QR'ı okutuldu)
- Karekodda SSID (S:) yok: tryParse null döner
- Okuma büyük harfe çevrildi: `preserveCase: true` verilmezse şifre bozulurdu (şu an verilir)
- Ağ açık (şifresiz) ise şifre boş gelir; kaydetme adımı yine şifre ister

**Adım adım kontrol**
- Aynı karekodu telefonun kamerasıyla okuyup içerik biçimine bakın (WIFI:... ile başlamalı)
- Ayrıştırıcı testi: flutter test test/wifi_qr_parser_test.dart

**İlgili testler:** [test/wifi_qr_parser_test.dart](../../test/wifi_qr_parser_test.dart), [test/wifi_provision_page_layout_test.dart](../../test/wifi_provision_page_layout_test.dart)

**Bkz.:** [ui-wifi-kurulum](#ui-wifi-kurulum), [ui-qr-tarama-sayfasi](#ui-qr-tarama-sayfasi)

<a id="ui-giris-hata"></a>
### ui-giris-hata · Giriş ekranında "Giriş Yap" sonrası hata mesajı görünmüyor, uzun mesaj kesiliyor ya da düğme dönüp duruyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/login_page.dart:101](../../lib/ui/pages/login_page.dart#L101) | <code>Future&lt;void&gt; _submit() async {</code> | Form doğrulaması, yükleme bayrağı ve sonuç işleme |
| [lib/ui/pages/login_page.dart:112](../../lib/ui/pages/login_page.dart#L112) | <code>final errorMessage = await widget.authService.login(</code> | Hata metni AuthService'ten gelir (null = başarı; başarıda oturum kurulur ve kök rota HomePage olur) |
| [lib/ui/pages/login_page.dart:121](../../lib/ui/pages/login_page.dart#L121) | <code>AppSnack.show(context, errorMessage, kind: AppSnackKind.error, maxLines: 8);</code> | Uzun mesajlar (örn. hesap kilidi) 8 satıra kadar gösterilir; sonrası üç nokta |
| [lib/ui/pages/login_page.dart:370](../../lib/ui/pages/login_page.dart#L370) | <code>label: 'Giriş Yap',</code> | Yüklenirken düğme etiketi spinner olur ve dokunma kapanır (`loading`) |
| [lib/ui/pages/login_page.dart:293](../../lib/ui/pages/login_page.dart#L293) | <code>return 'Lütfen e-posta veya kullanıcı adınızı girin.';</code> | Boş alan doğrulaması (e-posta veya kullanıcı adı; ikisi de kabul edilir) |

**Olası nedenler**
- Form doğrulaması başarısız: alan altında kırmızı metin çıkar, istek gönderilmez
- Kimlik bilgisi/kilit/ağ hatası: mesaj AuthService'ten gelir (kimlik doğrulama bölümü); arayüz yalnız gösterir
- `_isLoading` true kalırsa düğme spinner'da kalır: `authService.login` dönmemiştir (zaman aşımı)
- ScaffoldMessenger yoksa AppSnack sessizce hiçbir şey göstermez (yalnız özel test kurulumunda)

**Adım adım kontrol**
- Hata snackbar'ının tam metnini kaydedin; sunucu günlüğünde /auth/login yanıtıyla eşleştirin
- Aynı hesapla başka cihazda deneyin (hesap kilitli mi)
- Test: flutter test test/verify_and_profile_ui_test.dart test/screens/login_layout_test.dart

**İlgili testler:** [test/verify_and_profile_ui_test.dart](../../test/verify_and_profile_ui_test.dart), [test/screens/login_layout_test.dart](../../test/screens/login_layout_test.dart)

**Bkz.:** [ui-sifremi-unuttum](#ui-sifremi-unuttum), [ui-oturum-sonu-bildirimi](#ui-oturum-sonu-bildirimi), [ui-giris-beni-hatirla](#ui-giris-beni-hatirla)

<a id="ui-giris-beni-hatirla"></a>
### ui-giris-beni-hatirla · Giriş ekranında kullanıcı adı hatırlanmıyor ya da "Beni Hatırla" işaretliyken alan boş geliyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/login_page.dart:31](../../lib/ui/pages/login_page.dart#L31) | <code>static const String _savedIdentifierKey = 'saved_login_identifier';</code> | Yalnız kullanıcı adı/e-posta saklanır, ŞİFRE saklanmaz |
| [lib/ui/pages/login_page.dart:61](../../lib/ui/pages/login_page.dart#L61) | <code>Future&lt;void&gt; _loadSavedCredentials() async {</code> | Açılışta okunur; işaret kapalıysa alan doldurulmaz; okuma hatası sessizce yutulur |
| [lib/ui/pages/login_page.dart:80](../../lib/ui/pages/login_page.dart#L80) | <code>Future&lt;void&gt; _saveCredentials(String identifier) async {</code> | Yalnız BAŞARILI girişten sonra çağrılır; işaret kapalıysa kayıtlı değer silinir |
| [lib/ui/pages/login_page.dart:347](../../lib/ui/pages/login_page.dart#L347) | <code>'Beni Hatırla (Kullanıcı adını kaydet)',</code> | Onay kutusu etiketi (tüm satır dokunma alanı) |

**Olası nedenler**
- Başarısız girişte kayıt yapılmaz: yanlış parolayla denenen kullanıcı adı saklanmaz
- SharedPreferences okunamadı/yazılamadı: hata yutulur, kayıt olmaz
- Uygulama verisi temizlendi ya da kullanıcı işareti kaldırdı
- Şifre hiçbir zaman saklanmaz (tasarım gereği)

**Adım adım kontrol**
- Bir kez başarılı giriş yapın, çıkış yapın, giriş ekranında alanı kontrol edin
- İşaret kutusunun açık olduğunu doğrulayın

**İlgili testler:** [test/screens/login_layout_test.dart](../../test/screens/login_layout_test.dart)

**Bkz.:** [ui-giris-hata](#ui-giris-hata)

<a id="ui-sifremi-unuttum"></a>
### ui-sifremi-unuttum · "Şifremi Unuttum" penceresi hata veriyor ya da bağlantı gönderildi mesajı geliyor ama e-posta ulaşmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/login_page.dart:130](../../lib/ui/pages/login_page.dart#L130) | <code>Future&lt;void&gt; _showForgotPasswordDialog() async {</code> | Alandaki değer e-posta ise (@ içeriyorsa) pencereye hazır doldurulur |
| [lib/ui/pages/login_page.dart:164](../../lib/ui/pages/login_page.dart#L164) | <code>final error = await widget.authService.forgotPassword(</code> | Sunucu çağrısı; hata pencere içinde InlineNotice ile gösterilir |
| [lib/ui/pages/login_page.dart:181](../../lib/ui/pages/login_page.dart#L181) | <code>'Bu e-posta adresiyle kayıtlı bir hesap varsa şifre sıfırlama bağlantısı gönderildi. Lütf…</code> | Başarı mesajı hesap varlığını ele vermez (hesap yoksa da aynı metin) |
| [lib/ui/pages/login_page.dart:228](../../lib/ui/pages/login_page.dart#L228) | <code>return 'Geçerli bir e-posta adresi girin.';</code> | Yalnız basit doğrulama (@ ve nokta içermeli) |

**Olası nedenler**
- Başarı mesajı kullanıcı varlığını doğrulamaz: hesap yoksa e-posta hiç gönderilmez (güvenlik gereği aynı metin)
- E-posta teslimi gecikebilir ya da spam klasörüne düşebilir (mesajda da yazar)
- Kullanıcı adıyla (e-posta değil) giriş yapan hesap bu akışta e-posta girmelidir
- Sunucu e-posta gönderemiyorsa (SMTP) arayüz fark edemez; sunucu günlüğüne bakın

**Adım adım kontrol**
- Doğru e-posta ile tekrar deneyin ve spam klasörünü kontrol edin
- Sunucuda e-posta gönderim günlüğünü inceleyin (sunucu/e-posta bölümü)

**İlgili testler:** [test/screens/login_layout_test.dart](../../test/screens/login_layout_test.dart), [test/verify_and_profile_ui_test.dart](../../test/verify_and_profile_ui_test.dart)

**Bkz.:** [ui-giris-hata](#ui-giris-hata)

<a id="ui-oturum-sonu-bildirimi"></a>
### ui-oturum-sonu-bildirimi · Oturum kendiliğinden kapanıp giriş ekranına dönüyor ve nedeni gösterilmiyor (ya da yanlış gösteriliyor)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/login_page.dart:49](../../lib/ui/pages/login_page.dart#L49) | <code>final notice = widget.authService.takeSessionNotice();</code> | Giriş ekranı ilk karede sunucu kaynaklı oturum sonu nedenini BİR KEZ okur ve gösterir |
| [lib/ui/pages/login_page.dart:54](../../lib/ui/pages/login_page.dart#L54) | <code>kind: AppSnackKind.warning,</code> | Uyarı tonlu, 6 sn, en çok 8 satır |
| [lib/ui/pages/home_page.dart:641](../../lib/ui/pages/home_page.dart#L641) | <code>unawaited(widget.authService.refreshSession());</code> | Ön plana dönüşte oturum /me ile eşitlenir (hesap pasif/rol değişimi burada yakalanır) |
| [lib/ui/pages/home_page.dart:5661](../../lib/ui/pages/home_page.dart#L5661) | <code>onPressed: () =&gt; widget.authService.logout(),</code> | AppBar çıkış düğmesi (kullanıcı kaynaklı çıkışta bildirim olmaz) |

**Olası nedenler**
- Kullanıcı kendi çıkış yaptıysa bildirim üretilmez (beklenen)
- Bildirim yalnız bir kez gösterilir; ekran yeniden kurulursa tekrar çıkmaz
- Oturum sonu nedeni AuthService'te üretilir (oturum/yenileme bölümü); arayüz yalnız gösterir

**Adım adım kontrol**
- Uygulamayı ön plana alıp giriş ekranına düşme anında snackbar'ı arayın
- Test: flutter test test/verify_and_profile_ui_test.dart (oturum bildirimi grubu)

**İlgili testler:** [test/verify_and_profile_ui_test.dart](../../test/verify_and_profile_ui_test.dart), [test/auth_service_session_test.dart](../../test/auth_service_session_test.dart)

**Bkz.:** [ui-giris-hata](#ui-giris-hata)

<a id="ui-kayit-formu"></a>
### ui-kayit-formu · Kayıt formunda alanlar sığmıyor/üst üste biniyor, "Kayıt Ol" sonrası doğrulama ekranı açılmıyor ya da hata gösteriliyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/register_individual_page.dart:72](../../lib/ui/pages/register_individual_page.dart#L72) | <code>Future&lt;void&gt; _submit() async {</code> | Form doğrulaması, kayıt çağrısı, başarıda doğrulama ekranına geçiş |
| [lib/ui/pages/register_individual_page.dart:87](../../lib/ui/pages/register_individual_page.dart#L87) | <code>final error = await widget.authService.registerIndividual(</code> | Hata metni sayfada InlineNotice ile gösterilir (SnackBar değil) |
| [lib/ui/pages/register_individual_page.dart:112](../../lib/ui/pages/register_individual_page.dart#L112) | <code>builder: (_) =&gt; VerifyEmailCodePage(</code> | Başarıda e-posta ve ad-soyad ile 6 haneli doğrulama sayfası push edilir |
| [lib/ui/pages/register_individual_page.dart:189](../../lib/ui/pages/register_individual_page.dart#L189) | <code>final sideBySide = box.maxWidth &gt;= 380 &amp;&amp; textScale &lt;= 1.15;</code> | Ad/Soyad yan yana yalnız geniş kartta ve küçük yazıda; aksi halde alt alta (taşmayı önler) |
| [lib/ui/pages/register_individual_page.dart:276](../../lib/ui/pages/register_individual_page.dart#L276) | <code>validator: (val) =&gt; PasswordPolicy.validate(</code> | İstemci şifre kuralı (PasswordPolicy, sunucuyla aynı): en az 8 karakter, e-posta ya da adla aynı olamaz, yaygın şifre reddedilir; tekrar alanı eşleşmeli |

**Olası nedenler**
- E-posta zaten kayıtlıysa ya da sunucu kuralı ihlal edildiyse hata sayfada kırmızı bildirimle gelir (sunucu kayıt bölümü)
- Form doğrulaması: ad, soyad, e-posta (@ ve nokta), şifre ilkesi (en az 8 karakter, e-posta / adla aynı değil, yaygın değil), şifre tekrar eşleşmesi
- Dar ekran/büyük yazıda alanlar alt alta dizilir; sabit genişlik eklenirse taşar (320 dp x 2,0)
- Doğrulama sayfasına geçiş yalnız hatasız başarıda yapılır; hata varsa aynı sayfada kalınır

**Adım adım kontrol**
- Hata bildirimini okuyun; e-posta küçük harfe çevrilerek gönderilir (`toLowerCase`)
- Test: flutter test test/screens/register_individual_layout_test.dart

**İlgili testler:** [test/screens/register_individual_layout_test.dart](../../test/screens/register_individual_layout_test.dart), [test/fix_fx1_ui_test.dart](../../test/fix_fx1_ui_test.dart), [test/password_policy_test.dart](../../test/password_policy_test.dart)

**Bkz.:** [ui-dogrulama-kodu](#ui-dogrulama-kodu), [ui-dogrulama-sonrasi-yonlendirme](#ui-dogrulama-sonrasi-yonlendirme)

<a id="ui-dogrulama-kodu"></a>
### ui-dogrulama-kodu · E-posta doğrulama ekranında kod kabul edilmiyor, "Kodu Tekrar Gönder" pasif ya da yeni kod gelmiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/verify_email_code_page.dart:20](../../lib/ui/pages/verify_email_code_page.dart#L20) | <code>static const int codeLength = 6;</code> | İstemci kod uzunluğu (sunucu da 6 haneli üretir); farklıysa "eksiksiz giriniz" hatası |
| [lib/ui/pages/verify_email_code_page.dart:25](../../lib/ui/pages/verify_email_code_page.dart#L25) | <code>static const int resendCooldownSeconds = 30;</code> | Tekrar gönderme 30 sn bekleme süresi: sunucu daha erken isteği sessizce yok sayar |
| [lib/ui/pages/verify_email_code_page.dart:29](../../lib/ui/pages/verify_email_code_page.dart#L29) | <code>static const int codeValidityMinutes = 30;</code> | Kod geçerlilik süresi (sunucudaki VERIFICATION_CODE_TTL_MINUTES ile aynı olmalı) |
| [lib/ui/pages/verify_email_code_page.dart:78](../../lib/ui/pages/verify_email_code_page.dart#L78) | <code>Future&lt;void&gt; _verifyCode() async {</code> | Uzunluk kontrolü, verifyIndividualCode çağrısı, hata/başarı işleme |
| [lib/ui/pages/verify_email_code_page.dart:118](../../lib/ui/pages/verify_email_code_page.dart#L118) | <code>Future&lt;void&gt; _resendCode() async {</code> | Bekleme sürerken ya da gönderim sürerken çalışmaz; başarıda geri sayım yeniden başlar |
| [lib/ui/pages/verify_email_code_page.dart:141](../../lib/ui/pages/verify_email_code_page.dart#L141) | <code>'Bu e-posta adresi için bekleyen bir doğrulama varsa yeni ${VerifyEmailCodePage.codeLengt…</code> | Tekrar gönderme başarı metni teslimat garanti etmez (sunucu kullanıcı varlığını ele vermez) |

**Olası nedenler**
- Birden fazla kod istendi: yalnız EN SON e-postadaki kod geçerlidir (metinde yazar); eski kodlar geçersiz olur
- 30 dakikalık süre doldu: yeni kod istenmelidir
- Tekrar gönderme düğmesi 30 sn pasiftir (geri sayım düğmede görünür); sunucu bu süre içindeki isteği yok sayar
- E-posta gecikmeli/spam klasöründe: ekranda uyarı metni vardır
- İstemci ile sunucu kod uzunluğu uyuşmazlığı: bu dosyadaki `codeLength` sunucuyla aynı olmalı

**Adım adım kontrol**
- Hata metnini okuyun (InlineNotice); kod alanı hata varken kırmızı kenarlı olur
- Test: flutter test test/verify_and_profile_ui_test.dart test/screens/verify_email_code_layout_test.dart
- Sunucu tarafı kod üretimi/TTL için sunucu kimlik doğrulama bölümüne bakın

**İlgili testler:** [test/verify_and_profile_ui_test.dart](../../test/verify_and_profile_ui_test.dart), [test/screens/verify_email_code_layout_test.dart](../../test/screens/verify_email_code_layout_test.dart)

**Bkz.:** [ui-kayit-formu](#ui-kayit-formu), [ui-dogrulama-sonrasi-yonlendirme](#ui-dogrulama-sonrasi-yonlendirme)

<a id="ui-dogrulama-sonrasi-yonlendirme"></a>
### ui-dogrulama-sonrasi-yonlendirme · Kod doğrulandıktan sonra ana ekrana geçilmiyor, geri tuşuyla kayıt sayfasına dönülüyor ya da çıkışta giriş ekranı gelmiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/verify_email_code_page.dart:114](../../lib/ui/pages/verify_email_code_page.dart#L114) | <code>Navigator.of(context).popUntil((route) =&gt; route.isFirst);</code> | Yalnız Kayıt + Doğrulama sayfaları kapanır; kök rota (oturuma tepki veren home) kalır |
| [lib/ui/pages/verify_email_code_page.dart:95](../../lib/ui/pages/verify_email_code_page.dart#L95) | <code>final error = await widget.authService.verifyIndividualCode(</code> | Başarıda AuthService oturumu kurar; ekran değişimi oturum dinleyicisiyle olur |
| [lib/ui/pages/login_page.dart:385](../../lib/ui/pages/login_page.dart#L385) | <code>builder: (_) =&gt; RegisterIndividualPage(</code> | Kayıt sayfası giriş sayfasının ÜSTÜNE push edilir (kök rota değişmez) |

**Olası nedenler**
- Kök rota pushAndRemoveUntil(... false) ile silinirse çıkışta giriş ekranı dönmez ve ikinci bir HomePage açılır (kodda uyarı notu var): bu satır değiştirilmemeli
- AuthService oturumu kurmadıysa (otomatik giriş başarısız) kök rota giriş ekranında kalır
- Doğrulama hatalı: sayfa kapanmaz, hata bildirimi gösterilir

**Adım adım kontrol**
- Doğrulamadan sonra uygulamanın HomePage'e düştüğünü ve çıkışta giriş ekranına döndüğünü deneyin
- Test: flutter test test/fix_fx1_ui_test.dart (kök rota korunur)

**İlgili testler:** [test/fix_fx1_ui_test.dart](../../test/fix_fx1_ui_test.dart), [test/verify_and_profile_ui_test.dart](../../test/verify_and_profile_ui_test.dart)

**Bkz.:** [ui-dogrulama-kodu](#ui-dogrulama-kodu), [ui-kayit-formu](#ui-kayit-formu)

<a id="ui-internet-yok"></a>
### ui-internet-yok · "Internet baglantisi bulunamadi" ekranı geliyor ya da "Tekrar Dene" basınca ekran kapanmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/no_internet_page.dart:51](../../lib/ui/pages/no_internet_page.dart#L51) | <code>'Internet baglantisi bulunamadi',</code> | Başlık; bu sayfadaki metinler ASCII (Türkçe karaktersiz) yazılmıştır |
| [lib/ui/pages/no_internet_page.dart:64](../../lib/ui/pages/no_internet_page.dart#L64) | <code>onPressed: isChecking ? null : onRetry,</code> | Kontrol sürerken düğme pasif ve "Kontrol Ediliyor..." etiketi; asıl kontrol çağıranın (kök uygulama) onRetry'ındadır |
| [lib/ui/pages/no_internet_page.dart:14](../../lib/ui/pages/no_internet_page.dart#L14) | <code>final Future&lt;void&gt; Function() onRetry;</code> | Bağlantı denetimi bu sayfada yapılmaz; sayfa yalnız durumu gösterir (denetim kökte, app.dart bölümünde) |

**Olası nedenler**
- Bağlantı kontrolü (kök uygulama) hâlâ başarısız: sayfa kapanmaz; arayüz tarafı yalnız gösterir
- Telefonda Wi-Fi bağlı ama internet yok ya da sunucuya erişilemiyor: kontrol yöntemi kökte tanımlıdır
- Metinlerin Türkçe karaktersiz olması bilinçli/eski bir tercihtir; düzeltme istenirse test metinleri de güncellenmeli

**Adım adım kontrol**
- Telefonun internetini ve api.gudeteknoloji.com.tr erişimini tarayıcıdan deneyin
- Test: flutter test test/screens/no_internet_layout_test.dart

**İlgili testler:** [test/screens/no_internet_layout_test.dart](../../test/screens/no_internet_layout_test.dart), [test/cold_start_test.dart](../../test/cold_start_test.dart)

**Bkz.:** [ui-giris-hata](#ui-giris-hata)

<a id="ui-tema-gecisi"></a>
### ui-tema-gecisi · Aydınlık/karanlık tema düğmesi görünmüyor, basınca tema değişmiyor ya da yeniden açılınca eski temaya dönüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/design/theme_toggle_button.dart:15](../../lib/ui/design/theme_toggle_button.dart#L15) | <code>static ThemeService? maybeOf(BuildContext context) {</code> | Düğme ThemeService'i bu kapsamdan alır; kapsam yoksa null |
| [lib/ui/design/theme_toggle_button.dart:33](../../lib/ui/design/theme_toggle_button.dart#L33) | <code>if (service == null) {</code> | ThemeScope yoksa (kök dışı kurulum/test) düğme hiç çizilmez |
| [lib/ui/design/theme_toggle_button.dart:38](../../lib/ui/design/theme_toggle_button.dart#L38) | <code>final label = isDark ? 'Aydınlık temaya geç' : 'Koyu temaya geç';</code> | İkon GÖRÜNEN temayı değil geçilecek temayı anlatır; aynı metin tooltip ve anlamsal etiket |
| [lib/ui/design/theme_toggle_button.dart:50](../../lib/ui/design/theme_toggle_button.dart#L50) | <code>onPressed: () =&gt; service.toggle(brightness),</code> | Görünen parlaklığın tersi seçilir (sistem modunda da); tercih cihazda saklanır |
| [lib/ui/pages/home_page.dart:5652](../../lib/ui/pages/home_page.dart#L5652) | <code>const ThemeToggleButton(iconSize: 20),</code> | Ana sayfada AppBar'da (yalnız ThemeScope varsa yer ayrılır) |
| [lib/ui/pages/login_page.dart:269](../../lib/ui/pages/login_page.dart#L269) | <code>child: ThemeToggleButton(),</code> | Giriş kartının sağ üst köşesi |
| [lib/ui/pages/register_individual_page.dart:134](../../lib/ui/pages/register_individual_page.dart#L134) | <code>actions: const [ThemeToggleButton(), SizedBox(width: AppSpace.sm)],</code> | Kayıt ve doğrulama sayfalarının AppBar'ında |

**Olası nedenler**
- Tema düğmesi yalnız ana sayfa, giriş, kayıt ve doğrulama ekranlarında vardır; internet yok, Wi-Fi kurulum, QR tarama ve yönetici seçme sayfalarında YOKTUR (tasarım)
- ThemeScope MaterialApp'in üstünde kurulmamışsa (lib/app.dart bölümü) düğme hiç görünmez
- Tercih SharedPreferences'ta `app_theme_mode` anahtarıyla saklanır; depolama hatasında tercih yalnız oturumluk olur; değer bozuksa sistem temasına döner
- Sistem modunda ilk dokunuş görünen temanın tersini seçer; "hiçbir şey olmadı" gibi görünürse sistem teması ile seçilen aynı olabilir

**Adım adım kontrol**
- Cihaz sistem temasını ve uygulamadaki düğme ikonunu (ay/güneş) karşılaştırın
- Test: flutter test test/design/theme_toggle_button_test.dart test/theme_service_test.dart test/design/app_shell_test.dart

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/design/theme_toggle_button_test.dart test/theme_service_test.dart test/design/app_shell_test.dart
```

**İlgili testler:** [test/design/theme_toggle_button_test.dart](../../test/design/theme_toggle_button_test.dart), [test/theme_service_test.dart](../../test/theme_service_test.dart), [test/design/app_shell_test.dart](../../test/design/app_shell_test.dart)

**Bkz.:** [ui-koyu-tema-okunmuyor](#ui-koyu-tema-okunmuyor), [ui-ust-cubuk-tasma](#ui-ust-cubuk-tasma)

<a id="ui-koyu-tema-okunmuyor"></a>
### ui-koyu-tema-okunmuyor · Koyu (ya da aydınlık) temada bazı metin, ikon veya düğme okunmuyor; kontrast düşük

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/design/tokens.dart:161](../../lib/ui/design/tokens.dart#L161) | <code>static const AppPalette dark = AppPalette._(</code> | Koyu palet; metin/zemin çiftlerinin tamamı >= 4,5:1 olacak biçimde seçilmiştir |
| [lib/ui/design/tokens.dart:314](../../lib/ui/design/tokens.dart#L314) | <code>enum AppTone {</code> | Anlamsal tonlar: ink (metin), a/b (beyaz metinli dolgu), tint (soluk zemin); ham ton rengi METİN için kullanılmaz |
| [lib/ui/design/tokens.dart:297](../../lib/ui/design/tokens.dart#L297) | <code>AppPalette get palette {</code> | Bileşenler rengi context.palette ile alır; Colors.* ham renk tema geçişinde uyum bozar |
| [lib/styles/role_theme.dart:53](../../lib/styles/role_theme.dart#L53) | <code>Color inkColor(AppPalette palette) =&gt; tone.ink(palette);</code> | Rol rengini METİN olarak kullanırken bu kullanılmalı (accentColor açık zeminde yetersiz kontrast) |
| [lib/styles/app_theme.dart:261](../../lib/styles/app_theme.dart#L261) | <code>static ThemeData dark() {</code> | Koyu ThemeData: input, düğme, snackbar, drawer temaları |
| [lib/ui/widgets/device_connectivity_logs_accordion.dart:129](../../lib/ui/widgets/device_connectivity_logs_accordion.dart#L129) | <code>color: p.surfaceMuted,</code> | Akordiyon paneli artık palet yüzeyiyle çizilir (eski elle yazılmış isDark rengi kaldırıldı) |
| [lib/ui/pages/home_page.dart:3639](../../lib/ui/pages/home_page.dart#L3639) | <code>color: Colors.black87,</code> | E-posta kodu ile site silme penceresinde sabit koyu metin rengi (koyu temada soluk zeminle birlikte okunurluk riski) |

**Olası nedenler**
- Ham `Colors.red/grey/white` ya da sabit `Color(0xFF...)` kullanılan bileşen tema paletine uymaz: koyu temada okunmaz (örnekler: site silme pencereleri, site yöneticisi seçme sayfası)
- Rol rengi (`accentColor`) metin olarak kullanıldı: açık zeminde yetersiz kontrast; `inkColor`/`tone.ink(p)` kullanılmalı
- Yeni renk eklendi ve `test/design/contrast_test.dart` güncellenmedi: sözleşme (>= 4,5:1) doğrulanmaz
- Yeni eklenen ekran Scaffold zeminini kendisi boyuyor: sayfa zemini kökte tek kez boyanır (lib/app.dart)

**Adım adım kontrol**
- Sorunlu metnin hangi widget olduğunu bulun ve rengini kaynakta arayın (ham renk mi, palet mi)
- Palet veya ton eklediyseniz: flutter test test/design/contrast_test.dart
- Düzeltme: renk yerine `context.palette` (surface/text/textSecondary) ve `AppTone.xxx.ink(p)` kullanın

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/design/contrast_test.dart
```

**İlgili testler:** [test/design/contrast_test.dart](../../test/design/contrast_test.dart), [test/design/app_card_test.dart](../../test/design/app_card_test.dart), [test/design/status_chip_test.dart](../../test/design/status_chip_test.dart)

**Bkz.:** [ui-tema-gecisi](#ui-tema-gecisi), [ui-site-silme-diyaloglari-renk](#ui-site-silme-diyaloglari-renk), [ui-site-yoneticisi-secici](#ui-site-yoneticisi-secici)

<a id="ui-site-silme-diyaloglari-renk"></a>
### ui-site-silme-diyaloglari-renk · Site silme pencerelerinde (yöntem seçimi, e-posta kodu ile sil) koyu temada renkler solgun ya da okunmuyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:3372](../../lib/ui/pages/home_page.dart#L3372) | <code>title: Text('${site.name} Sitesini Sil'),</code> | Süper kullanıcıya yöntem seçtiren pencere: kutu renkleri sabit (FEF2F2, FFFBEB) ve metin renkleri sabittir |
| [lib/ui/pages/home_page.dart:3558](../../lib/ui/pages/home_page.dart#L3558) | <code>Future&lt;void&gt; _deleteSiteWithEmailVerification(SiteRecord site) async {</code> | 6 haneli silme kodu penceresi: kod alanı ve kutu renkleri sabit (Colors.black87, grey.shade50) |
| [lib/ui/pages/home_page.dart:3649](../../lib/ui/pages/home_page.dart#L3649) | <code>fillColor: Colors.grey.shade50,</code> | Koyu temada açık gri dolgu üzerinde palet metni değil sabit koyu metin kullanılır |
| [lib/ui/pages/home_page.dart:3772](../../lib/ui/pages/home_page.dart#L3772) | <code>Future&lt;void&gt; _approveDeleteSite(SiteRecord site) async {</code> | Silme onayı penceresi: düz AlertDialog (AppDialog değil); onay düğmesi tehlike stili filledToneStyle(ctx, tone: AppTone.danger), beyaz metin 4,70:1 |

**Olası nedenler**
- Bu pencereler AppDialog/palet yerine elle yazılmış sabit renklerle çizilir; açık zeminli kutular koyu temada parlak kalır
- Metin renkleri (`Color(0xFF991B1B)`, `Colors.black87`) tema değişse de sabit kalır

**Adım adım kontrol**
- Pencereyi her iki temada açıp karşılaştırın
- İstenirse AppDialog + `AppTone.danger.tint/ink(p)` ile palete bağlayın; mevcut davranış ve metinler değişmemeli (AGENTS.md kural 2)

**İlgili testler:** [test/design/contrast_test.dart](../../test/design/contrast_test.dart), [test/screens/site_security_policy_dialog_layout_test.dart](../../test/screens/site_security_policy_dialog_layout_test.dart)

**Bkz.:** [ui-site-silme-akisi](#ui-site-silme-akisi), [ui-koyu-tema-okunmuyor](#ui-koyu-tema-okunmuyor)

<a id="ui-site-silme-akisi"></a>
### ui-site-silme-akisi · Siteyi silerken beklenen pencere gelmiyor, "Silme Onayı" bekleyen sitede düğmeler yanlış ya da silme sonrası listeler güncellenmiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:3363](../../lib/ui/pages/home_page.dart#L3363) | <code>Future&lt;void&gt; _deleteSite(SiteRecord site) async {</code> | Rol/yönetici durumuna göre akış: süper kullanıcı yöntem seçer; diğerleri talep oluşturur; yöneticisiz sitede doğrudan kalıcı silme |
| [lib/ui/pages/home_page.dart:3832](../../lib/ui/pages/home_page.dart#L3832) | <code>Future&lt;void&gt; _rejectDeleteSite(SiteRecord site) async {</code> | Talebi iptal (isteyen taraf) ya da reddet (karşı taraf); başlık ve düğme metni buna göre değişir |
| [lib/ui/widgets/site_card.dart:281](../../lib/ui/widgets/site_card.dart#L281) | <code>final isUserApprovalRequired =</code> | Bekleyen silme talebinde onay sırası kimde (kullanıcıda mı karşı tarafta mı) buradan belirlenir |
| [lib/ui/widgets/site_card.dart:236](../../lib/ui/widgets/site_card.dart#L236) | <code>label: const Text('E-Posta Koduyla Sil'),</code> | Yalnız süper kullanıcıda ve bekleyen silme yokken görünür |
| [lib/ui/views/sites_view.dart:206](../../lib/ui/views/sites_view.dart#L206) | <code>deleteBusy: busyDeleteSites.contains(site.id),</code> | İşlem sürerken kart düğmeleri pasif (`_busyDeleteSites`) |

**Olası nedenler**
- Silme başarılı olunca hem `_loadSites` hem `_loadDoorControlSites` ve ilgili kullanıcı listeleri yeniden yüklenir; biri atlanırsa panel eski siteyi gösterir
- Seçili site silindiyse `_selectedSite`/`_doorControlSite` sıfırlanır; sıfırlama atlanırsa boş yapı gösterilir
- Silme talebi iletildiğinde (`deleted` false) site kalır ve kartta "Silme Onayı" rozeti çıkar (beklenen)
- Rol uyuşmazlığı: onay düğmesi yalnız onay sırası kullanıcıdaysa görünür (`isUserApprovalRequired`)

**Adım adım kontrol**
- Kartta "Silme Onayı" rozeti ve uyarı kutusu metnini okuyun: kimin onayı bekleniyor yazar
- Siteler ekranını yenileyin ve Kayıtlı Cihazlar/Kapı panelini kontrol edin
- Sunucudaki silme akışı için site yönetimi sunucu bölümüne bakın

**İlgili testler:** [test/screens/sites_view_layout_test.dart](../../test/screens/sites_view_layout_test.dart), [test/home_page_state_test.dart](../../test/home_page_state_test.dart)

**Bkz.:** [ui-site-silme-diyaloglari-renk](#ui-site-silme-diyaloglari-renk), [ui-site-listesi-yenilenmiyor](#ui-site-listesi-yenilenmiyor)

<a id="ui-site-yoneticisi-secici"></a>
### ui-site-yoneticisi-secici · "Site Yöneticisi Seç" sayfasında zemin/renkler tema ile uyuşmuyor, arama yavaş ya da seçim forma geri dönmüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/site_manager_picker_page.dart:207](../../lib/ui/pages/site_manager_picker_page.dart#L207) | <code>child: InlineNotice(</code> | Hata kutusu (tema duyarlı InlineNotice), "Tekrar Dene" ile yeniden yükler; sayfa zemini artık uygulama kökünden gelir |
| [lib/ui/pages/site_manager_picker_page.dart:73](../../lib/ui/pages/site_manager_picker_page.dart#L73) | <code>_searchDebounce = Timer(const Duration(milliseconds: 300), () {</code> | Arama 300 ms gecikmeli çalışır, sayfa 1'den başlar |
| [lib/ui/pages/site_manager_picker_page.dart:132](../../lib/ui/pages/site_manager_picker_page.dart#L132) | <code>).pop(SiteManagerPickerResult(manager: manager)),</code> | Seçim sonucu SiteDialog'a bu nesneyle döner |
| [lib/ui/dialogs/site_dialog.dart:266](../../lib/ui/dialogs/site_dialog.dart#L266) | <code>Future&lt;void&gt; _selectExistingManager() async {</code> | Seçilen yönetici forma yazılır (`_selectedManagerUserCode`) |

**Olası nedenler**
- Sayfa AppDialog/palet yerine sabit AppColors ve Colors.* ile çizilir: tema değişince uyum bozulur
- Liste her kaydırmada sonraki sayfayı (20 kayıt) yükler; tümü yüklenmeden yönetici bulunamayabilir: arama kullanılmalı
- Hata varsa liste yerine kırmızı metin ve "Tekrar Dene" görünür

**Adım adım kontrol**
- Siteyi düzenleyen/oluşturan süper kullanıcı olarak sayfayı iki temada açıp karşılaştırın
- Aranan yöneticiyi ad, e-posta veya telefonla arayın

**İlgili testler:** [test/screens/site_dialog_layout_test.dart](../../test/screens/site_dialog_layout_test.dart), [test/fix_fx2_widgets_test.dart](../../test/fix_fx2_widgets_test.dart)

**Bkz.:** [ui-koyu-tema-okunmuyor](#ui-koyu-tema-okunmuyor), [ui-site-duzenle-dialogu](#ui-site-duzenle-dialogu)

<a id="ui-site-duzenle-dialogu"></a>
### ui-site-duzenle-dialogu · Siteyi düzenle/oluştur penceresinde daire sayıları okunamıyor ("Mevcut daire sayıları okunamadı"), "Güncelle" kapalı kalıyor ya da yeni site yerine sihirbaz açılıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:3103](../../lib/ui/pages/home_page.dart#L3103) | <code>Future&lt;void&gt; _openSiteDialog({SiteRecord? site}) async {</code> | Site yöneticisi "Yeni Site" derse SetupSiteDialog (sihirbaz), süper kullanıcı SiteDialog açar; sonuçlar burada sunucuya gönderilir |
| [lib/ui/pages/home_page.dart:3216](../../lib/ui/pages/home_page.dart#L3216) | <code>_showMessage('Site güncellendi.');</code> | Başarıda `_loadSites` ve `_loadDoorControlSites` (preferredSiteId) ile listeler yenilenir |
| [lib/ui/dialogs/site_dialog.dart:167](../../lib/ui/dialogs/site_dialog.dart#L167) | <code>Future&lt;void&gt; _loadStructureCounts() async {</code> | Mevcut blok/daire sayıları yapı ucundan okunur; okunamazsa sessiz varsayılan KULLANILMAZ |
| [lib/ui/dialogs/site_dialog.dart:180](../../lib/ui/dialogs/site_dialog.dart#L180) | <code>_structureCountsError = error ?? 'Mevcut daire sayıları okunamadı.';</code> | Okunamayınca hata gösterilir ve tekrar deneme sunulur (güncelleme kapalı kalır) |
| [lib/ui/dialogs/site_dialog.dart:246](../../lib/ui/dialogs/site_dialog.dart#L246) | <code>final safeCount = blockCount.clamp(1, 50);</code> | Blok sayısı 1-50 aralığına sıkıştırılır |

**Olası nedenler**
- Yapı ucu hata verdi: sayılar okunamaz ve yanlış daire sayısı yazılmasın diye güncelleme kapalı tutulur (düzeltme: tekrar dene)
- Rol site yöneticisiyse yeni site akışı kurulum sihirbazıdır (davranış bilinçli)
- Yönetici adayı listesi `listManagedUsers` ile 100 kayıtla yüklenir; daha fazla yönetici için seçici sayfa kullanılır

**Adım adım kontrol**
- Penceredeki hata kutusunda "Tekrar Dene" ile sayıları yeniden yükleyin
- Test: flutter test test/fix_fx2_widgets_test.dart test/screens/site_dialog_layout_test.dart

**İlgili testler:** [test/fix_fx2_widgets_test.dart](../../test/fix_fx2_widgets_test.dart), [test/screens/site_dialog_layout_test.dart](../../test/screens/site_dialog_layout_test.dart)

**Bkz.:** [ui-site-yoneticisi-secici](#ui-site-yoneticisi-secici), [ui-kurulum-sihirbazi](#ui-kurulum-sihirbazi)

<a id="ui-guvenlik-politikasi"></a>
### ui-guvenlik-politikasi · "Giriş & Güvenlik Politikaları" penceresinde kaydet çalışmıyor ("Kaydedilemedi", konum hatası) ya da değişiklik kapıdaki düğmelere yansımıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:3337](../../lib/ui/pages/home_page.dart#L3337) | <code>Future&lt;void&gt; _openSiteSecurityPolicyDialog(SiteRecord site) async {</code> | Pencereyi açar; başarıda siteler ve kapı paneli (_loadSites/_loadDoorControlSites) yeniden yüklenir |
| [lib/ui/widgets/site_security_policy_dialog.dart:244](../../lib/ui/widgets/site_security_policy_dialog.dart#L244) | <code>Future&lt;void&gt; _handleSave() async {</code> | Kaydet: konum zorunluysa form doğrulanır; erişim kipinden remote/QR bayrakları türetilir; hata snackbar'a düşer |
| [lib/ui/widgets/site_security_policy_dialog.dart:274](../../lib/ui/widgets/site_security_policy_dialog.dart#L274) | <code>final isQrActive = _accessMode != 'app_only';</code> | Kip -> bayrak: app_only QR'ı, qr_only uzaktan açmayı kapatır; hibritte ikisi de açık |
| [lib/ui/widgets/site_security_policy_dialog.dart:152](../../lib/ui/widgets/site_security_policy_dialog.dart#L152) | <code>radiusError = 'Mesafe 10 ile 2000 metre arasında olmalı.';</code> | Konum doğrulaması: enlem -90..90, boylam -180..180, (0,0) tanımsız, mesafe 10-2000 m |
| [lib/ui/widgets/site_security_policy_dialog.dart:499](../../lib/ui/widgets/site_security_policy_dialog.dart#L499) | <code>onChanged: widget.isSuperUser</code> | QR yenilenme süresi seçicisi yalnız süper kullanıcıda etkin (misafir geçişi anahtarı da aynı kurala bağlıdır) |
| [lib/services/auth_service.dart:917](../../lib/services/auth_service.dart#L917) | <code>Future&lt;String?&gt; updateSiteSecurityPolicy({</code> | Kayıt sunucuya buradan gider; hata metni döner (pencere "Kaydedilemedi:" ile gösterir) |

**Olası nedenler**
- Konum doğrulaması açık ama enlem/boylam boş ya da (0,0): kaydetme bilerek engellenir, alan altında kırmızı hata çıkar
- GPS izni kapalı: "Mevcut Konumu Al" "Konum alınamadı" der; koordinatlar elle girilebilir
- Sunucu reddetti (yetki, geçersiz değer): pencere kapanmaz, "Kaydedilemedi: ..." snackbar'ı görünür
- Kayıt başarılı ama kapı kartı eski: panel `_loadDoorControlSites` ile yenilenmediyse eski bayraklar görünür (kural 7)
- Site yöneticisi QR yenilenme süresini ve misafir geçişi anahtarını değiştiremez (yalnız süper kullanıcı)

**Adım adım kontrol**
- Pencerede alanın altındaki kırmızı doğrulama metnini okuyun
- Kaydettikten sonra kapı kartında "Kapıyı Aç" / QR düğmelerinin beklenen şekilde değiştiğini doğrulayın
- Sunucuya gelen istek hatasını günlükte arayın (sunucu site politika ucu)

**İlgili testler:** [test/site_security_policy_dialog_test.dart](../../test/site_security_policy_dialog_test.dart), [test/geofence_and_site_policy_test.dart](../../test/geofence_and_site_policy_test.dart), [test/screens/site_security_policy_dialog_layout_test.dart](../../test/screens/site_security_policy_dialog_layout_test.dart)

**Bkz.:** [ui-bireysel-kapi-karti-dugmeleri](#ui-bireysel-kapi-karti-dugmeleri), [ui-qr-konum-hatasi](#ui-qr-konum-hatasi), [ui-site-listesi-yenilenmiyor](#ui-site-listesi-yenilenmiyor)

<a id="ui-kapi-yetkileri"></a>
### ui-kapi-yetkileri · "Kapı Yetki Yönetimi" penceresinde sakin anahtarı değişmiyor, liste boş geliyor ya da toplu blok yetkisi uygulanmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:4364](../../lib/ui/pages/home_page.dart#L4364) | <code>Future&lt;void&gt; _openDoorPermissionsDialog(DoorRecord door) async {</code> | Pencere yalnız kapıyı alır; yetki verisi pencerenin kendi içinde yüklenir |
| [lib/ui/dialogs/door_permissions_dialog.dart:66](../../lib/ui/dialogs/door_permissions_dialog.dart#L66) | <code>Future&lt;void&gt; _loadPermissions() async {</code> | Pencere açılınca ve her başarılı işlemden sonra getDoorPermissions ile liste yeniden çekilir |
| [lib/ui/dialogs/door_permissions_dialog.dart:102](../../lib/ui/dialogs/door_permissions_dialog.dart#L102) | <code>Future&lt;void&gt; _toggleResidentAccess(DoorResidentPermission resident) async {</code> | Anahtar: görünen durumun TERSİ yazılır (varsayılan erişim + ek izin/engel kaydı birlikte değerlendirilir) |
| [lib/ui/dialogs/door_permissions_dialog.dart:87](../../lib/ui/dialogs/door_permissions_dialog.dart#L87) | <code>bool _hasDefaultAccess(DoorResidentPermission resident) {</code> | Ortak kapı herkese, blok kapısı yalnız kendi bloğuna varsayılan açıktır |
| [lib/ui/dialogs/door_permissions_dialog.dart:148](../../lib/ui/dialogs/door_permissions_dialog.dart#L148) | <code>Future&lt;void&gt; _applyBulkBlockAccess(DoorBlockPermission block, bool? isAllowed) async {</code> | Blok için toplu izin/engel/sıfırlama (isAllowed null = kayıtları sil) |
| [lib/ui/dialogs/door_permissions_dialog.dart:374](../../lib/ui/dialogs/door_permissions_dialog.dart#L374) | <code>title: 'Bu sitede kayıtlı blok veya sakin bulunamadı.',</code> | Veri boşsa çıkan boş durum |
| [lib/ui/dialogs/door_permissions_dialog.dart:568](../../lib/ui/dialogs/door_permissions_dialog.dart#L568) | <code>AppTone _statusTone(DoorResidentPermission resident) {</code> | Satır rozet rengi accessSource değerinden (SITE_COMMON, BLOCK_DEFAULT, OVERRIDE_ALLOWED, OVERRIDE_DENIED, NO_ACCESS) gelir |

**Olası nedenler**
- İşlem sunucuda reddedildi: kırmızı snackbar çıkar ve anahtar eski durumda kalır (liste yeniden çekilmez)
- İşlem sürerken satırda spinner vardır (`_busyUserCodes`); aynı sakine ikinci dokunuş anahtar yerine spinner görür
- Kapı bir bloğa bağlıysa ve sakin başka blokta ise varsayılan erişimi yoktur: anahtar kapalı görünür (beklenen)
- Arama yalnız daire no, ad, telefon ve e-postada çalışır; eşleşmeyen blok gizlenir
- Sakinin yetki kaydı yoksa NO_ACCESS: anahtara dokunmak açıkça izin kaydı yazar

**Adım adım kontrol**
- Sakin satırındaki rozeti okuyun (yetki kaynağını söyler)
- Başarı mesajından sonra liste yenilendi mi; yenilenmediyse `_loadPermissions` çağrısını doğrulayın
- Kapının kapsamını (site ortak / blok) rozetten kontrol edin
- Aynı sakin telefonunda kapı listesinde kapı görünüyor mu (bireysel ana ekran)

**İlgili testler:** [test/screens/door_permissions_dialog_layout_test.dart](../../test/screens/door_permissions_dialog_layout_test.dart)

**Bkz.:** [ui-qr-modal-ret](#ui-qr-modal-ret), [ui-bireysel-ana-ekran-kapilar](#ui-bireysel-ana-ekran-kapilar), [ui-yazi-olcegi-tasma](#ui-yazi-olcegi-tasma)

<a id="ui-site-listesi-yenilenmiyor"></a>
### ui-site-listesi-yenilenmiyor · Site/daire/yönetici/kapı üzerinde işlem yapıldı ama Siteler ekranındaki liste ya da detay eski kalıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:2256](../../lib/ui/pages/home_page.dart#L2256) | <code>Future&lt;void&gt; _loadSites({</code> | `force` verilmezse yükleme sürerken çağrı sessizce atlanır; eski yanıtlar `_sitesRequestToken` ile yok sayılır |
| [lib/ui/pages/home_page.dart:2271](../../lib/ui/pages/home_page.dart#L2271) | <code>if (!mounted &#124;&#124; requestToken != _sitesRequestToken) return;</code> | Daha yeni bir yükleme başladıysa eski yanıt çöpe gider |
| [lib/ui/pages/home_page.dart:2301](../../lib/ui/pages/home_page.dart#L2301) | <code>_selectedSite = currentInList;</code> | Yenilemede seçili site nesnesi yeni kayıtla DEĞİŞTİRİLİR; yoksa politika/ad eski kalırdı |
| [lib/ui/pages/home_page.dart:2344](../../lib/ui/pages/home_page.dart#L2344) | <code>Future&lt;void&gt; _selectSite(SiteRecord site) async {</code> | Seçimde yapı ve yöneticiler yeniden çekilir; başka site seçilirse eski yanıt yok sayılır |
| [lib/ui/pages/home_page.dart:5238](../../lib/ui/pages/home_page.dart#L5238) | <code>Future&lt;void&gt; _handleGlobalRefresh() async {</code> | AppBar yenile ve aşağı çekme: menüye göre ilgili listeyi force ile çeker |
| [lib/ui/views/sites_view.dart:20](../../lib/ui/views/sites_view.dart#L20) | <code>class SitesView extends StatelessWidget {</code> | Liste yalnız home_page'in verdiği `sitesPage`i çizer; kendi başına yenilemez |

**Olası nedenler**
- Bir eylemden sonra `_loadSites(force: true)` çağrılmadı: yeni bir eylem eklenirken en sık unutulan adımdır (AGENTS.md kural 7)
- `force` verilmeden çağrı, önceki yükleme sürerken atlandı
- Sunucu hatası: yalnız `force` ile çağrıldıysa mesaj gösterilir, aksi halde sessiz kalır
- İşlem başka kullanıcının sitesindeyse (ör. süper kullanıcı) liste sayfası farklı olabilir: sayfalama kontrol edilmeli

**Adım adım kontrol**
- AppBar "Yenile" ile liste düzeliyorsa eksik olan, eylem sonrası otomatik yenilemedir
- İlgili eylemin sonunda `_loadSites(force: true)` ve (kapı etkilendiyse) `_loadDoorControlSites` çağrısı var mı
- Hata mesajı çıkıyor mu; çıkmıyorsa çağrı `force`suz yapılmış olabilir

**İlgili testler:** [test/screens/sites_view_layout_test.dart](../../test/screens/sites_view_layout_test.dart), [test/home_page_state_test.dart](../../test/home_page_state_test.dart)

**Bkz.:** [ui-site-silme-akisi](#ui-site-silme-akisi), [ui-kapi-yonet-yenilenmiyor](#ui-kapi-yonet-yenilenmiyor), [ui-guvenlik-politikasi](#ui-guvenlik-politikasi)

<a id="ui-yazi-olcegi-tasma"></a>
### ui-yazi-olcegi-tasma · Büyük sistem yazısında ya da dar ekranda ("A RenderFlex overflowed by N pixels") başlık, çip ya da düğme taşıyor/kırpılıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/app.dart:387](../../lib/app.dart#L387) | <code>maxScaleFactor: 2.0,</code> | Uygulama genelinde yazı ölçeği 2,0 ile sınırlı; taşma testleri bu sınırda biter |
| [lib/ui/widgets/list_parts.dart:18](../../lib/ui/widgets/list_parts.dart#L18) | <code>bool isLargeText(BuildContext context) =&gt;</code> | >= 1,75x ölçekte dekoratif öğeler gizlenir, metne yer açılır |
| [lib/ui/widgets/list_parts.dart:22](../../lib/ui/widgets/list_parts.dart#L22) | <code>EdgeInsets listCardPadding(BuildContext context) =&gt; EdgeInsets.all(</code> | Dar ekranda (< 360 dp) kart iç boşluğu küçülür |
| [lib/ui/views/company_devices_view.dart:202](../../lib/ui/views/company_devices_view.dart#L202) | <code>class _GroupLabel extends StatelessWidget {</code> | Örnek çözüm: büyük yazıda çip yerine sarmalanan düz metin |
| [lib/ui/dialogs/door_permissions_dialog.dart:181](../../lib/ui/dialogs/door_permissions_dialog.dart#L181) | <code>final compactHeader = MediaQuery.textScalerOf(context).scale(1) &gt; 1.3;</code> | Örnek çözüm: büyük yazıda alt başlık sabit başlıktan kaydırılan alana taşınır |
| [test/design/harness.dart:33](../../test/design/harness.dart#L33) | <code>Future&lt;void&gt; pumpAt(</code> | Genişlik x yazı ölçeği x tema hücrelerinde taşmayı yakalayan düzenek (ağaçta istisna varsa test düşer) |
| [test/screens/dialog_layout_harness.dart:26](../../test/screens/dialog_layout_harness.dart#L26) | <code>void layoutMatrix(</code> | Diyalog taşma matrisi; yeni diyalog buraya eklenmelidir |

**Olası nedenler**
- Satırda sabit genişlikli çocuklar var ve `Expanded`/`Flexible`/`Wrap` kullanılmamış
- Yeni metin ya da düğme eklendi ve 320 dp x 2,0 hücresinde denenmedi
- Dikdörtgen sınırlar içinde `Row` yerine `Wrap` gerekir; uzun metinde `maxLines`/`overflow` verilmemiş
- Diyalog yüksekliği ekrandan büyük: içerik kaydırılabilir olmalı (diyaloglar CustomScrollView/SingleChildScrollView kullanır)

**Adım adım kontrol**
- Hata satırında hangi widget'ın taştığı ve piksel miktarı yazar; o widget'ı `pumpAt(width: 320, scale: 2.0)` ile tek başına kurun
- Aynı hücreyi koyu temada da deneyin
- Çözüm kalıbı: isLargeText ile süsü gizle, Wrap/Expanded kullan, minimum dokunma hedefini (44 dp) koru

**Komutlar**
```bash
C:\Users\fingonancalime\SDK\flutter\bin\flutter.bat test test/design/pump_at_test.dart
```

**İlgili testler:** [test/design/pump_at_test.dart](../../test/design/pump_at_test.dart), [test/design/harness.dart](../../test/design/harness.dart), [test/screens/dialog_layout_harness.dart](../../test/screens/dialog_layout_harness.dart)

**Bkz.:** [ui-ust-cubuk-tasma](#ui-ust-cubuk-tasma), [ui-koyu-tema-okunmuyor](#ui-koyu-tema-okunmuyor)

<a id="ui-cihaz-envanteri"></a>
### ui-cihaz-envanteri · Kayıtlı Cihazlar ekranında cihaz listesi boş/eski, "Atama Bekleyen" grubunda yanlış cihaz var ya da kart eylemi sonrası liste yenilenmiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/views/company_devices_view.dart:71](../../lib/ui/views/company_devices_view.dart#L71) | <code>final unassignedDevices = devices</code> | Gruplama: assignedDoorId boş/0 ise "Atama Bekleyen", doluysa "Kapıya Atanmış" |
| [lib/ui/views/company_devices_view.dart:137](../../lib/ui/views/company_devices_view.dart#L137) | <code>title: 'Şirket hesabına kayıtlı cihaz bulunamadı.',</code> | Liste boşsa gösterilen durum; süper kullanıcıya ekleme yönergesi verilir |
| [lib/ui/views/company_devices_view.dart:185](../../lib/ui/views/company_devices_view.dart#L185) | <code>PaginationBar(</code> | Sayfalama: sayfa başına 10 kayıt (home_page yükleyicisinde pageSize: 10) |
| [lib/ui/pages/home_page.dart:2977](../../lib/ui/pages/home_page.dart#L2977) | <code>Future&lt;void&gt; _loadCompanyDevices({int page = 1, bool force = false}) async {</code> | Liste yükleyici; hata yalnız snackbar ile bildirilir, eski liste kalır |
| [lib/ui/pages/home_page.dart:4594](../../lib/ui/pages/home_page.dart#L4594) | <code>Future&lt;void&gt; _toggleDeviceDefect(DeviceRecord device) async {</code> | Arızalı işaretle/kaldır; başarıda liste force ile yenilenir |
| [lib/ui/pages/home_page.dart:4652](../../lib/ui/pages/home_page.dart#L4652) | <code>Future&lt;void&gt; _releaseDeviceOwnership(DeviceRecord device) async {</code> | Depoya al: kapı ve sahip atamaları kalkar; cihaz, site ve kapı listeleri birlikte yenilenir |
| [lib/ui/pages/home_page.dart:4528](../../lib/ui/pages/home_page.dart#L4528) | <code>Future&lt;void&gt; _deleteCompanyDevice(DeviceRecord device) async {</code> | Cihaz silme; başarıda cihaz, site ve kapı paneli yenilenir |
| [lib/ui/widgets/company_device_card.dart:53](../../lib/ui/widgets/company_device_card.dart#L53) | <code>class CompanyDeviceCard extends StatefulWidget {</code> | Kart rozetleri ve eylem düğmeleri (rol bazlı) |

**Olası nedenler**
- İşlem sunucuda reddedildi: mesaj snackbar'da çıkar, liste değişmez
- Yenileme `_loadCompanyDevices(force: true)` ile yapılmadı: sürmekte olan yükleme yeni isteği atlar
- Cihazın kapı ataması kaldırıldığı halde site/kapı ekranı eski: `_loadSites` ve `_loadDoorControlSites` de çağrılmalı
- Sayfa 1'den farklı bir sayfada eylem yapıldı: yenileme 1. sayfaya döner (varsayılan page = 1)
- Site yöneticisi ve süper kullanıcı için düğmeler farklıdır (`isSuperUser`): yetkisiz düğme beklenmez

**Adım adım kontrol**
- AppBar "Yenile" ile liste düzeliyorsa eylem sonrası yenileme eksiktir
- Cihazın atandığı kapıyı Siteler ekranında kontrol edin
- Hata mesajı sunucudan geliyorsa sunucu cihaz uçlarının günlüğüne bakın

**İlgili testler:** [test/screens/company_devices_view_layout_test.dart](../../test/screens/company_devices_view_layout_test.dart), [test/screens/device_dialog_layout_test.dart](../../test/screens/device_dialog_layout_test.dart)

**Bkz.:** [ui-kapi-cihaz-ata](#ui-kapi-cihaz-ata), [ui-cihaz-degistir](#ui-cihaz-degistir), [ui-site-listesi-yenilenmiyor](#ui-site-listesi-yenilenmiyor), [ui-cihaz-ekle-sonrasi](#ui-cihaz-ekle-sonrasi)

<a id="ui-katilim-qr-diyalogu"></a>
### ui-katilim-qr-diyalogu · "Site Katılım QR" penceresi açılmıyor, karekod yerine hata gösteriyor ya da yenileme/paylaşma çalışmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/views/sites_view.dart:312](../../lib/ui/views/sites_view.dart#L312) | <code>label: const Text('Site Katılım QR'),</code> | Düğme yalnız `onShowSiteJoinQr` verilmişse çizilir |
| [lib/ui/pages/home_page.dart:4372](../../lib/ui/pages/home_page.dart#L4372) | <code>Future&lt;void&gt; _openSiteJoinQrDialog(SiteRecord site) async {</code> | Pencereyi açar; sonuç beklenmez |
| [lib/ui/dialogs/site_join_qr_dialog.dart:61](../../lib/ui/dialogs/site_join_qr_dialog.dart#L61) | <code>Future&lt;void&gt; _loadToken() async {</code> | Mevcut katılım belirteci getSiteJoinToken ile okunur; hata ekranda metin olarak kalır |
| [lib/ui/dialogs/site_join_qr_dialog.dart:85](../../lib/ui/dialogs/site_join_qr_dialog.dart#L85) | <code>Future&lt;void&gt; _rotateToken() async {</code> | Onay sonrası belirteç yenilenir; eski asılmış/paylaşılmış kodlar geçersiz olur |
| [lib/ui/dialogs/site_join_qr_dialog.dart:158](../../lib/ui/dialogs/site_join_qr_dialog.dart#L158) | <code>Future&lt;void&gt; _shareQrCode() async {</code> | Önce karekod PNG'si ile paylaşım denenir, olmazsa yalnız metinle; ikisi de olmazsa "Paylaşım başlatılamadı" |
| [lib/ui/dialogs/site_join_qr_dialog.dart:236](../../lib/ui/dialogs/site_join_qr_dialog.dart#L236) | <code>debugPrint('QR resim export hatası: $e');</code> | Resim üretimi hatası sessizce metin paylaşımına düşer; yalnızca hata ayıklama çıktısına yazılır |

**Olası nedenler**
- Sunucu belirteç uç noktası hata verdi (yetki, ağ): pencere hata metnini gösterir; sunucu katılım uçlarına bakın
- Yenileme sonrası eski karekod hâlâ asılı: eski kod katılım için kullanılamaz, yeni kodu paylaşmak gerekir
- Bu karekod kapıyı açmaz; yalnız sakinlerin siteye katılım başvurusu içindir (pencerede yazar)
- Paylaşım sayfası masaüstü/web platformunda desteklenmiyorsa "Paylaşım başlatılamadı" çıkar

**Adım adım kontrol**
- Pencerede görünen hata metnini okuyun
- "Kodu Kopyala" ile kod metnini alıp başvuru diyaloğuna elle yapıştırarak deneyin
- Test: flutter test test/site_join_qr_dialog_test.dart test/screens/site_join_qr_dialog_layout_test.dart

**İlgili testler:** [test/site_join_qr_dialog_test.dart](../../test/site_join_qr_dialog_test.dart), [test/screens/site_join_qr_dialog_layout_test.dart](../../test/screens/site_join_qr_dialog_layout_test.dart)

**Bkz.:** [ui-katilim-talepleri-yonet](#ui-katilim-talepleri-yonet), [ui-katilim-basvurusu-gonder](#ui-katilim-basvurusu-gonder)

<a id="ui-katilim-talepleri-yonet"></a>
### ui-katilim-talepleri-yonet · "Katılım Talepleri" penceresinde onayla/reddet sonrası liste ya da sakin sayıları güncellenmiyor, talep düğmeleri tepkisiz

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:4380](../../lib/ui/pages/home_page.dart#L4380) | <code>Future&lt;void&gt; _openManageJoinRequestsDialog(SiteRecord site) async {</code> | Pencere kapanınca sonuç kullanılmaz: Siteler/sakin listeleri burada YENİLENMEZ |
| [lib/ui/dialogs/manage_join_requests_dialog.dart:57](../../lib/ui/dialogs/manage_join_requests_dialog.dart#L57) | <code>Future&lt;void&gt; _loadRequests() async {</code> | Pencere açılınca ve her işlemden sonra talepler getSiteJoinRequests ile yeniden çekilir |
| [lib/ui/dialogs/manage_join_requests_dialog.dart:78](../../lib/ui/dialogs/manage_join_requests_dialog.dart#L78) | <code>Future&lt;void&gt; _approve(JoinRequestRecord request) async {</code> | Onay: satır meşgul işaretlenir; hata kırmızı snackbar, başarıda liste yenilenir |
| [lib/ui/dialogs/manage_join_requests_dialog.dart:102](../../lib/ui/dialogs/manage_join_requests_dialog.dart#L102) | <code>Future&lt;void&gt; _reject(JoinRequestRecord request) async {</code> | Ret: isteğe bağlı gerekçe ile; başarıda uyarı tonlu snackbar |
| [lib/ui/dialogs/manage_join_requests_dialog.dart:172](../../lib/ui/dialogs/manage_join_requests_dialog.dart#L172) | <code>final pendingCount = _requests.where((r) =&gt; r.isPending).length;</code> | Başlıktaki bekleyen sayısı yalnız bu pencerenin yüklediği listeden hesaplanır |

**Olası nedenler**
- Sunucu onay/ret isteğini reddetti: snackbar metni sunucudan gelir ve liste değişmez
- Onaydan sonra Siteler ekranındaki daire/sakin bilgisi eski: `home_page` bu pencerenin sonucunu kullanmaz, elle Yenile gerekir (yenileme eklenecekse `_openManageJoinRequestsDialog` içine)
- Satır işlem sürerken (`_busyRequestIds`) tekrar basış yok sayılır
- Başvuru zaten başka yönetici tarafından işlendi: yeniden yüklenen listede durumu değişmiş olur

**Adım adım kontrol**
- Snackbar metnini okuyun; sunucu cevabını yansıtır
- AppBar "Yenile" ile Siteler ekranını yenileyip sakinin dairede göründüğünü doğrulayın
- Sakin tarafında "Başvurularım" ekranında durumu karşılaştırın

**İlgili testler:** [test/screens/manage_join_requests_dialog_layout_test.dart](../../test/screens/manage_join_requests_dialog_layout_test.dart)

**Bkz.:** [ui-katilim-qr-diyalogu](#ui-katilim-qr-diyalogu), [ui-katilim-basvurusu-gonder](#ui-katilim-basvurusu-gonder), [ui-site-listesi-yenilenmiyor](#ui-site-listesi-yenilenmiyor)

<a id="ui-katilim-basvurusu-gonder"></a>
### ui-katilim-basvurusu-gonder · Sakin "Siteye Katıl" penceresinde kod okutunca site bilgisi gelmiyor ya da başvuru gönderilemiyor ("Lütfen blok ve daire seçiniz")

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:4339](../../lib/ui/pages/home_page.dart#L4339) | <code>Future&lt;void&gt; _openJoinRequestFlow() async {</code> | Başvuru başarılıysa `_loadInitialData` ile ekran verileri yeniden yüklenir |
| [lib/ui/dialogs/submit_join_request_dialog.dart:72](../../lib/ui/dialogs/submit_join_request_dialog.dart#L72) | <code>Future&lt;void&gt; _scanQr() async {</code> | QR sayfası açılır; okunan değerden `SITE_JOIN:` ön eki atılır |
| [lib/ui/dialogs/submit_join_request_dialog.dart:84](../../lib/ui/dialogs/submit_join_request_dialog.dart#L84) | <code>Future&lt;void&gt; _fetchInfo(String token) async {</code> | Kodla fetchSiteJoinInfo çağrılır; blok/daire listesi gelir, ilk blok ve ilk daire otomatik seçilir |
| [lib/ui/dialogs/submit_join_request_dialog.dart:119](../../lib/ui/dialogs/submit_join_request_dialog.dart#L119) | <code>setState(() =&gt; _errorMessage = 'Lütfen blok ve daire seçiniz.');</code> | Site bilgisi ya da daire yokken gönderme engellenir |
| [lib/ui/dialogs/submit_join_request_dialog.dart:128](../../lib/ui/dialogs/submit_join_request_dialog.dart#L128) | <code>final (res, error) = await widget.authService.submitJoinRequest(</code> | Başvuru gönderilir; hata pencerede InlineNotice olarak kalır, başarıda pencere true ile kapanır |

**Olası nedenler**
- Kod yanlış/yenilenmiş (yönetici karekodu yeniledi): site bilgisi alınamaz, hata pencerede görünür
- Sitede blok ya da daire tanımlı değil: seçim listesi boş kalır
- Aynı daireye zaten bekleyen/onaylı başvuru var ya da sunucu başvuruyu reddetti: sunucu metni gösterilir
- Kamera taraması desteklenmeyen platform (masaüstü): kodu elle yazmak gerekir

**Adım adım kontrol**
- Kodu elle girip "Site Bilgilerini Getir" düğmesine basın
- Hata metnini sunucu üyelik uçlarının yanıtıyla eşleştirin
- Başvuru gittiyse yöneticinin Katılım Talepleri penceresinde göründüğünü kontrol edin

**İlgili testler:** [test/submit_join_request_dialog_test.dart](../../test/submit_join_request_dialog_test.dart), [test/screens/submit_join_request_dialog_layout_test.dart](../../test/screens/submit_join_request_dialog_layout_test.dart), [test/join_and_setup_view_test.dart](../../test/join_and_setup_view_test.dart)

**Bkz.:** [ui-katilim-qr-diyalogu](#ui-katilim-qr-diyalogu), [ui-katilim-talepleri-yonet](#ui-katilim-talepleri-yonet), [ui-qr-tarama-sayfasi](#ui-qr-tarama-sayfasi)

<a id="ui-sakin-listesi-akordiyon"></a>
### ui-sakin-listesi-akordiyon · "Sakin Listesi (Akordiyon)" penceresinde arama sonuç vermiyor, pasife al / sil / aile reisi yap sonrası liste eski kalıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:4388](../../lib/ui/pages/home_page.dart#L4388) | <code>Future&lt;void&gt; _openSiteResidentsAccordionDialog(SiteRecord site) async {</code> | Pencere yalnız site verilerini alır; ağaç verisi pencerede yüklenir |
| [lib/ui/dialogs/site_residents_accordion_dialog.dart:88](../../lib/ui/dialogs/site_residents_accordion_dialog.dart#L88) | <code>Future&lt;void&gt; _loadData() async {</code> | getSiteResidentsTree: pencere açılışında ve her başarılı işlemden sonra |
| [lib/ui/dialogs/site_residents_accordion_dialog.dart:54](../../lib/ui/dialogs/site_residents_accordion_dialog.dart#L54) | <code>static const Duration _searchDebounce = Duration(milliseconds: 220);</code> | Arama 220 ms gecikmeli süzülür; anlık değişmemesi beklenen davranıştır |
| [lib/ui/dialogs/site_residents_accordion_dialog.dart:107](../../lib/ui/dialogs/site_residents_accordion_dialog.dart#L107) | <code>Future&lt;void&gt; _toggleMemberStatus(SiteResidentApartment apt, SiteResidentMember resident) …</code> | Üyeliği pasife al/aktif et: yalnız daire üyeliği ve kapı erişimi etkilenir, kullanıcı hesabı değil |
| [lib/ui/dialogs/site_residents_accordion_dialog.dart:168](../../lib/ui/dialogs/site_residents_accordion_dialog.dart#L168) | <code>Future&lt;void&gt; _deleteMember(SiteResidentApartment apt, SiteResidentMember resident) async {</code> | Sakini daireden siler (onaylı); başarıda ağaç yeniden çekilir |
| [lib/ui/dialogs/site_residents_accordion_dialog.dart:219](../../lib/ui/dialogs/site_residents_accordion_dialog.dart#L219) | <code>Future&lt;void&gt; _setPrimaryAdmin(SiteResidentApartment apt, SiteResidentMember resident) asy…</code> | Aile reisi değişimi: önceki daire yöneticisi standart üyeye döner |
| [lib/ui/dialogs/site_residents_accordion_dialog.dart:510](../../lib/ui/dialogs/site_residents_accordion_dialog.dart#L510) | <code>(r.loginName != null &amp;&amp; r.loginName!.toLowerCase().contains(_searchQuery)));</code> | Arama alanları: daire etiketi, ad, telefon, e-posta, kullanıcı adı |

**Olası nedenler**
- Sunucu işlemi reddetti: snackbar metni sunucudan gelir; liste değişmez
- Arama yalnız yukarıdaki alanlarda eşleşir (ör. kapı adı ya da blok adı aranmaz)
- Pasife alınan sakinin hesabı açık kalır; yalnız daire üyeliği/kapı erişimi durur (tasarım)
- Sonuç Siteler ekranına yansımadı: bu pencere kapanınca ana listeyi yenilemez, elle Yenile gerekir

**Adım adım kontrol**
- Aramayı temizleyip tüm listenin geldiğini doğrulayın
- Snackbar metnini okuyun (başarı/hata)
- Test: flutter test test/residents_search_debounce_test.dart test/fix_fx2_residents_dialog_test.dart

**İlgili testler:** [test/residents_search_debounce_test.dart](../../test/residents_search_debounce_test.dart), [test/fix_fx2_residents_dialog_test.dart](../../test/fix_fx2_residents_dialog_test.dart), [test/screens/site_residents_accordion_dialog_layout_test.dart](../../test/screens/site_residents_accordion_dialog_layout_test.dart)

**Bkz.:** [ui-katilim-talepleri-yonet](#ui-katilim-talepleri-yonet), [ui-daire-sakini-diyalogu](#ui-daire-sakini-diyalogu), [ui-kapi-yetkileri](#ui-kapi-yetkileri)

<a id="ui-yonetici-daveti"></a>
### ui-yonetici-daveti · "Yönetici Davet Et" penceresi davet göndermiyor, hata veriyor ya da davetten sonra yönetici listesi güncellenmiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:3228](../../lib/ui/pages/home_page.dart#L3228) | <code>Future&lt;void&gt; _openInviteSiteManagerDialog() async {</code> | Seçili site yoksa hiçbir şey olmaz; başarıda yönetici listesi `_loadSiteManagers` ile yenilenir |
| [lib/ui/dialogs/invite_site_manager_dialog.dart:57](../../lib/ui/dialogs/invite_site_manager_dialog.dart#L57) | <code>Future&lt;void&gt; _submit() async {</code> | Form doğrulanır, inviteSiteManager çağrılır; hata pencerede kalır, başarıda true ile kapanır |
| [lib/ui/dialogs/invite_site_manager_dialog.dart:150](../../lib/ui/dialogs/invite_site_manager_dialog.dart#L150) | <code>return 'Geçerli bir e-posta adresi girin.';</code> | E-posta biçimi doğrulaması (zorunlu alan) |
| [lib/ui/dialogs/invite_site_manager_dialog.dart:130](../../lib/ui/dialogs/invite_site_manager_dialog.dart#L130) | <code>'Davet edilen kişi kayıtlıysa anında bu siteye yönetici olarak atanır. '</code> | Kayıtlı kullanıcı anında atanır; kayıtsızsa e-postaya davet gider ve kayıtta otomatik yönetici olur |
| [lib/ui/pages/home_page.dart:3328](../../lib/ui/pages/home_page.dart#L3328) | <code>_showMessage(message ?? 'Davet iptal edildi.');</code> | Bekleyen davet iptali |

**Olası nedenler**
- E-posta biçimi geçersiz: gönderim yapılmaz, alan altında hata çıkar
- Sunucu daveti reddetti (yetki, zaten yönetici): metin pencerede gösterilir
- Kayıtsız kişiye e-posta gönderimi sunucu SMTP ayarına bağlıdır: ulaşmıyorsa sunucu e-posta bölümüne bakın
- Pencere gönderim sürerken kapatılamaz (barrierDismissible false, düğmeler pasif)

**Adım adım kontrol**
- Pencerede kırmızı hata metni var mı
- Davet sonrası Siteler > Site Yöneticileri bölümünde bekleyen davet/yönetici görünüyor mu
- Sunucu günlüğünde davet isteğini arayın

**İlgili testler:** [test/screens/invite_site_manager_dialog_layout_test.dart](../../test/screens/invite_site_manager_dialog_layout_test.dart)

**Bkz.:** [ui-site-yoneticisi-secici](#ui-site-yoneticisi-secici), [ui-site-listesi-yenilenmiyor](#ui-site-listesi-yenilenmiyor)

<a id="ui-daire-sakini-diyalogu"></a>
### ui-daire-sakini-diyalogu · "Daire Kullanıcı Ayarı" penceresi kaydetmiyor (PIN/e-posta/kullanıcı adı hatası) ya da kayıttan sonra daire kartı eski sakini gösteriyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:3974](../../lib/ui/pages/home_page.dart#L3974) | <code>Future&lt;void&gt; _openApartmentResidentDialog(ApartmentRecord apartment) async {</code> | Form sonucu burada sunucuya (upsertApartmentResident) gönderilir; başarıda seçili site yeniden seçilerek yapı tazelenir |
| [lib/ui/dialogs/apartment_resident_dialog.dart:94](../../lib/ui/dialogs/apartment_resident_dialog.dart#L94) | <code>void _submit() {</code> | Doğrulama geçerse sonuçla kapanır; kayıtlı sakin varsa şifre alanı boş gönderilir |
| [lib/ui/dialogs/apartment_resident_dialog.dart:197](../../lib/ui/dialogs/apartment_resident_dialog.dart#L197) | <code>: 'PIN 4 haneli sayısal olmalı.',</code> | Yeni sakin için ilk PIN yalnız 4 hane rakamdır |
| [lib/ui/dialogs/apartment_resident_dialog.dart:155](../../lib/ui/dialogs/apartment_resident_dialog.dart#L155) | <code>return 'Kullanıcı adı en az 3 karakter olmalı.';</code> | Kullanıcı adı alt sınırı |
| [lib/ui/dialogs/apartment_resident_dialog.dart:223](../../lib/ui/dialogs/apartment_resident_dialog.dart#L223) | <code>: 'Güvenlik gereği kayıtlı sakinlerin şifresi yöneticiler tarafından değiştirilemez. Saki…</code> | Kayıtlı sakinde şifre alanı hiç gösterilmez (daire hesabında not "PIN sıfırlama" düğmesine yönlendirir) |
| [lib/ui/pages/home_page.dart:4035](../../lib/ui/pages/home_page.dart#L4035) | <code>Future&lt;void&gt; _deleteApartmentResident(ApartmentRecord apartment) async {</code> | Sakini silip daireyi boşa çıkarma (onaylı) |

**Olası nedenler**
- PIN 4 haneli rakam değil ya da kullanıcı adı 3 karakterden kısa: gönderim yapılmaz
- Sunucu kullanıcı adı/e-posta çakışması gibi bir hata döndürdü: metin snackbar'da çıkar
- Kayıtlı sakinin şifresini yönetici değiştiremez: alan yoktur (tasarım)
- Başarıdan sonra yapı yeniden çekilmezse kart eski kalır (`_selectSite` çağrısı kontrol edilmeli)

**Adım adım kontrol**
- Alan altındaki kırmızı doğrulama metnini okuyun
- Snackbar'daki sunucu hata metnini kaydedin
- Siteler > ilgili dairede sakin adının güncellendiğini doğrulayın

**İlgili testler:** [test/screens/apartment_resident_dialog_layout_test.dart](../../test/screens/apartment_resident_dialog_layout_test.dart)

**Bkz.:** [ui-sakin-listesi-akordiyon](#ui-sakin-listesi-akordiyon), [ui-site-listesi-yenilenmiyor](#ui-site-listesi-yenilenmiyor)

<a id="ui-kullanici-diyalogu-kaydet"></a>
### ui-kullanici-diyalogu-kaydet · Kullanıcı ekle/düzenle penceresi kaydetmiyor, şifre/e-posta alanı yok ya da kayıttan sonra yönetici/süper kullanıcı listesi eski kalıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:4844](../../lib/ui/pages/home_page.dart#L4844) | <code>Future&lt;void&gt; _openManagedUserDialog({</code> | Yeni/düzenle akışı: sonuç createManagedUser ya da updateManagedUser ile gönderilir, ardından `_loadManagedUsers(role, force: true)` |
| [lib/ui/dialogs/managed_user_dialog.dart:108](../../lib/ui/dialogs/managed_user_dialog.dart#L108) | <code>void _submit() {</code> | E-posta küçük harfe çevrilir; rol seçimi yalnız allowRoleSelection ile (Kullanıcı Yönetimi ekranı) |
| [lib/ui/dialogs/managed_user_dialog.dart:243](../../lib/ui/dialogs/managed_user_dialog.dart#L243) | <code>validator: (value) =&gt; PasswordPolicy.validate(</code> | Yeni kullanıcıda şifre ilkesi (PasswordPolicy): en az 8 karakter, e-posta ya da adla aynı olamaz, yaygın şifre reddedilir |
| [lib/ui/dialogs/managed_user_dialog.dart:233](../../lib/ui/dialogs/managed_user_dialog.dart#L233) | <code>if (!_isEditing) ...[</code> | Şifre alanı yalnız YENİ kullanıcıda var; düzenlemede bilgi kutusu çıkar |
| [lib/ui/views/managed_users_view.dart:80](../../lib/ui/views/managed_users_view.dart#L80) | <code>label: Text('Yeni ${_roleTitle(role)}'),</code> | Liste ekranındaki ekle düğmesi |
| [lib/ui/pages/home_page.dart:4950](../../lib/ui/pages/home_page.dart#L4950) | <code>Future&lt;void&gt; _toggleUserActivation({</code> | Aktif/pasif anahtarı: işlem sürerken kullanıcı meşgul işaretlenir, başarıda liste yenilenir |

**Olası nedenler**
- Düzenlemede e-posta ve şifre değiştirilemez: güvenlik gereği şifre yalnız "Profilim"den değişir (kullanıcı kendi hesabında)
- Telefon biçimi geçersiz (10-20 karakter, rakam/boşluk/+/-/parantez) ya da ad 3 karakterden kısa: gönderim yapılmaz
- Sunucu hatası (e-posta zaten kayıtlı vb.): snackbar metni sunucudan gelir ve liste yenilenmez
- Rol değişince hem eski hem yeni rolün listesi yenilenmelidir (Kullanıcı Yönetimi akışı bunu yapar)

**Adım adım kontrol**
- Alan altındaki doğrulama metnini okuyun
- Snackbar metnini sunucu kullanıcı uçlarının yanıtıyla eşleştirin
- Elle "Yenile" ile liste düzeliyorsa eksik olan eylem sonrası yenilemedir

**İlgili testler:** [test/screens/managed_user_dialog_layout_test.dart](../../test/screens/managed_user_dialog_layout_test.dart), [test/screens/managed_users_view_layout_test.dart](../../test/screens/managed_users_view_layout_test.dart)

**Bkz.:** [ui-hesap-listesi-arama](#ui-hesap-listesi-arama), [ui-profil-kaydet](#ui-profil-kaydet)

<a id="ui-hesap-listesi-arama"></a>
### ui-hesap-listesi-arama · "Kullanıcı Yönetimi" listesinde arama/rol süzgeci/sayfalama sonuç getirmiyor ya da süper kullanıcılar listede yok

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/views/all_users_view.dart:83](../../lib/ui/views/all_users_view.dart#L83) | <code>void _onSearchChanged(String query) {</code> | Arama 400 ms gecikmeli çalışır ve 1. sayfaya döner |
| [lib/ui/views/all_users_view.dart:120](../../lib/ui/views/all_users_view.dart#L120) | <code>void _fetchData() {</code> | Rol, sayfa, sayfa boyutu ve aramayı `onLoadPage` ile üst bileşene iletir |
| [lib/ui/views/all_users_view.dart:612](../../lib/ui/views/all_users_view.dart#L612) | <code>final displayUsers = widget.users.where((u) =&gt; u.role != UserRole.superUser).toList();</code> | Süper kullanıcılar bu listede bilerek gösterilmez |
| [lib/ui/pages/home_page.dart:2864](../../lib/ui/pages/home_page.dart#L2864) | <code>Future&lt;void&gt; _loadAllUsers({</code> | `force` yoksa ve yükleme sürüyorsa çağrı HİÇ işlenmez: yeni arama/süzgeç/sayfa kaybolabilir |
| [lib/ui/pages/home_page.dart:2871](../../lib/ui/pages/home_page.dart#L2871) | <code>final sanitizedRole = role == UserRole.superUser ? null : role;</code> | Süper kullanıcı rol süzgeci yok sayılır; sorgu ayrıca excludeRole: superUser gönderir |
| [lib/ui/pages/home_page.dart:2899](../../lib/ui/pages/home_page.dart#L2899) | <code>Future&lt;void&gt; _updateDirectoryUser(</code> | Düzenleme sonrası aynı süzgeç/sayfa ile liste force yenilenir |
| [lib/ui/views/all_users_view.dart:735](../../lib/ui/views/all_users_view.dart#L735) | <code>label: const Text('Filtreleri Temizle'),</code> | Süzgeçle sonuç boşsa çıkan temizleme düğmesi |

**Olası nedenler**
- Yazarken önceki yükleme sürüyordu: `_loadAllUsers` force olmadan geri döner, son arama uygulanmaz (yeniden yazın ya da Yenile)
- Süper kullanıcıları aramak için bu ekran değil "Süper Kullanıcı Yönetimi" menüsü kullanılır
- Sayfa boyutu 15/25/50 seçicisiyle değişir ve 1. sayfaya döner
- Sunucu hatası: snackbar ile bildirilir, eski liste kalır

**Adım adım kontrol**
- "Filtreleri Temizle" ile süzgeçsiz listeyi getirin
- Aranan kişinin rolünü kontrol edin (süper kullanıcı mı)
- Sunucu günlüğünde kullanıcı listesi isteğini arayın (arama ve sayfa parametreleri)

**İlgili testler:** [test/screens/all_users_view_layout_test.dart](../../test/screens/all_users_view_layout_test.dart)

**Bkz.:** [ui-kullanici-diyalogu-kaydet](#ui-kullanici-diyalogu-kaydet), [ui-veritabani-bakim-diyalogu](#ui-veritabani-bakim-diyalogu)

<a id="ui-veritabani-bakim-diyalogu"></a>
### ui-veritabani-bakim-diyalogu · "Veritabanı Sağlığı & Bakım" penceresi açılmıyor, "Hata:" gösteriyor ya da çöp temizliği sonrası sayılar değişmiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/views/all_users_view.dart:410](../../lib/ui/views/all_users_view.dart#L410) | <code>Future&lt;void&gt; _showDbMaintenanceDialog() async {</code> | İki geri çağrı (sağlık, temizlik) yoksa pencere hiç açılmaz |
| [lib/ui/pages/home_page.dart:6332](../../lib/ui/pages/home_page.dart#L6332) | <code>onGetDatabaseHealth: widget.authService.getDatabaseHealth,</code> | Sağlık sorgusu sunucuya buradan bağlanır |
| [lib/ui/views/all_users_view.dart:465](../../lib/ui/views/all_users_view.dart#L465) | <code>message: 'Hata: $errorMessage',</code> | Sağlık verisi alınamayınca pencere hata metnini gösterir |
| [lib/ui/views/all_users_view.dart:560](../../lib/ui/views/all_users_view.dart#L560) | <code>label: Text(isCleaning ? 'Temizleniyor...' : 'Çöp Temizliği Yap'),</code> | Temizlik düğmesi; işlem sürerken pasif, bitince `onRefresh` ile liste yenilenir |

**Olası nedenler**
- Süper kullanıcı değil ya da sunucu uçları yanıt vermiyor: "Hata:" metni görünür
- Temizlik atık yoksa "temiz" der; sayılar değişmemesi normaldir
- Temizlik hatası da aynı mesaj alanında "Hata:" ile yazılır

**Adım adım kontrol**
- Hata metnini sunucu yönetim uçlarının günlüğüyle eşleştirin
- Temizlikten sonra sağlık penceresini kapatıp tekrar açın

**İlgili testler:** [test/screens/all_users_view_layout_test.dart](../../test/screens/all_users_view_layout_test.dart)

**Bkz.:** [ui-hesap-listesi-arama](#ui-hesap-listesi-arama)

<a id="ui-cihaz-kayit-formu"></a>
### ui-cihaz-kayit-formu · "Şirket Veritabanına Cihaz Kaydet" ekranında QR/UID ile kayıt sonrası cihaz listede görünmüyor ya da form "UID en az 6 karakter" diyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/views/device_add_view.dart:46](../../lib/ui/views/device_add_view.dart#L46) | <code>final isCompact = constraints.maxWidth &lt; 680;</code> | Dar genişlikte iki eylem karosu alt alta dizilir |
| [lib/ui/pages/home_page.dart:4396](../../lib/ui/pages/home_page.dart#L4396) | <code>Future&lt;void&gt; _openDeviceRegistrationFlow() async {</code> | QR okutulur, okunan UID forma aktarılır |
| [lib/ui/pages/home_page.dart:4412](../../lib/ui/pages/home_page.dart#L4412) | <code>Future&lt;void&gt; _openManualDeviceRegistrationFlow({String? initialUid}) async {</code> | Form sonucu createDevice ile gönderilir; başarıda cihaz, site ve kapı panelleri yenilenir |
| [lib/ui/dialogs/device_dialog.dart:126](../../lib/ui/dialogs/device_dialog.dart#L126) | <code>validator: (value) =&gt; (value ?? '').trim().length &lt; 6</code> | UID en az 6 karakter; kullanıcı ID ve Site ID isteğe bağlı sayıdır |
| [lib/ui/dialogs/device_dialog.dart:183](../../lib/ui/dialogs/device_dialog.dart#L183) | <code>class DeviceEditDialog extends StatefulWidget {</code> | Düzenleme formu (kullanıcı ID, site ID, kapı etiketi); sonuç `_editCompanyDevice` ile gönderilir |
| [lib/ui/pages/home_page.dart:4450](../../lib/ui/pages/home_page.dart#L4450) | <code>Future&lt;void&gt; _editCompanyDevice(DeviceRecord device) async {</code> | Güncelleme sonrası cihaz/site/kapı listeleri yenilenir |

**Olası nedenler**
- UID kısa/yanlış okundu ya da QR başka bir içerik taşıyor
- UID zaten kayıtlı veya sunucu reddetti: snackbar sunucu metnini gösterir, liste değişmez
- Bireysel kullanıcı bu ekranın yerine "Yönetici Olarak Cihaz Ekle" (sahiplenme) akışını görür
- Kullanıcı/Site ID sayı değil: alan doğrulaması gönderimi engeller

**Adım adım kontrol**
- Kayıttan sonra Kayıtlı Cihazlar ekranına gidip Yenile ile cihazı arayın
- Snackbar metnini okuyun
- Test: flutter test test/screens/device_dialog_layout_test.dart test/screens/device_add_view_layout_test.dart

**İlgili testler:** [test/screens/device_dialog_layout_test.dart](../../test/screens/device_dialog_layout_test.dart), [test/screens/device_add_view_layout_test.dart](../../test/screens/device_add_view_layout_test.dart), [test/screens/device_action_tile_layout_test.dart](../../test/screens/device_action_tile_layout_test.dart)

**Bkz.:** [ui-cihaz-envanteri](#ui-cihaz-envanteri), [ui-cihaz-sahiplen](#ui-cihaz-sahiplen), [ui-cihaz-ekle-sonrasi](#ui-cihaz-ekle-sonrasi)

<a id="ui-profil-kaydet"></a>
### ui-profil-kaydet · "Profilim" ekranında kaydet çalışmıyor ("mevcut şifrenizi girin") ya da sakin hesabında düzenleme alanları yok

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:4774](../../lib/ui/pages/home_page.dart#L4774) | <code>Future&lt;void&gt; _saveProfile() async {</code> | Sakin rolü güncelleyemez; form doğrulanır; updateMyProfile çağrılır; başarıda şifre alanları temizlenir |
| [lib/ui/pages/home_page.dart:6170](../../lib/ui/pages/home_page.dart#L6170) | <code>return ResidentProfileView(</code> | Daire sakini için düzenlenebilir form yerine salt okunur hesap bilgileri |
| [lib/ui/views/profile_view.dart:119](../../lib/ui/views/profile_view.dart#L119) | <code>return 'Şifre değiştirmek için mevcut şifrenizi girin.';</code> | Yeni şifre yazıldıysa mevcut şifre zorunlu |
| [lib/ui/views/profile_view.dart:134](../../lib/ui/views/profile_view.dart#L134) | <code>validator: (value) =&gt; PasswordPolicy.validate(</code> | Yeni şifre (boş bırakılabilir) ilkeye uymalı: en az 8 karakter, e-posta ya da adla aynı olamaz, yaygın şifre reddedilir |
| [lib/ui/views/profile_view.dart:85](../../lib/ui/views/profile_view.dart#L85) | <code>labelText: 'E-posta (Değiştirilemez)',</code> | E-posta alanı pasiftir; değiştirilemez |

**Olası nedenler**
- Yeni şifre girilip mevcut şifre boş bırakıldı
- Mevcut şifre yanlış ya da sunucu reddetti: snackbar sunucu metnini gösterir
- Hesap daire sakini: bu ekran bilerek salt okunurdur ("Daire sakinleri profil bilgilerini güncelleyemez.")
- Ad 3 karakterden kısa
- Yeni şifre ilkeye uymuyor (8 karakterden kısa, e-posta ya da adla aynı, yaygın): alan altında ileti çıkar; sunucu da 400 WEAK_PASSWORD ile reddeder

**Adım adım kontrol**
- Alan altındaki doğrulama metnini okuyun
- Rolü kontrol edin (apartmentOwner mı)
- Test: flutter test test/verify_and_profile_ui_test.dart test/screens/profile_view_layout_test.dart

**İlgili testler:** [test/verify_and_profile_ui_test.dart](../../test/verify_and_profile_ui_test.dart), [test/screens/profile_view_layout_test.dart](../../test/screens/profile_view_layout_test.dart)

**Bkz.:** [ui-kullanici-diyalogu-kaydet](#ui-kullanici-diyalogu-kaydet), [ui-giris-hata](#ui-giris-hata)

<a id="ui-siteler-yetkisiz-dugme"></a>
### ui-siteler-yetkisiz-dugme · Siteler/kapılar ekranında bir kullanıcıya göstermemesi gereken düğme görünüyor ya da gerekli düğme yok

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [lib/ui/pages/home_page.dart:6212](../../lib/ui/pages/home_page.dart#L6212) | <code>canManageSites:</code> | Yönetim bayrağı rolden türetilir (süper kullanıcı ve site yöneticisi) |
| [lib/ui/views/sites_view.dart:138](../../lib/ui/views/sites_view.dart#L138) | <code>label: Text(addSiteLabel),</code> | "Yeni Site" (başvurusu gereken yöneticide "Site Başvurusu") yalnız canManageSites iken |
| [lib/ui/views/sites_view.dart:209](../../lib/ui/views/sites_view.dart#L209) | <code>onEdit: canManageSites ? () =&gt; onEditSite(site) : null,</code> | Düzenle/sil/onayla/reddet bayrağa bağlıdır; `canManageApartmentUsers` ve `canAssignDoorDevices` bu görünümde okunmaz |
| [lib/ui/views/sites_view.dart:653](../../lib/ui/views/sites_view.dart#L653) | <code>onManagePermissions: onManageDoorPermissions != null</code> | Kapı yetki düğmesi geri çağrı verilirse çizilir |
| [lib/ui/widgets/site_card.dart:229](../../lib/ui/widgets/site_card.dart#L229) | <code>if (widget.isSuperUser &amp;&amp;</code> | Karttaki bazı eylemler yalnız süper kullanıcıya |
| [lib/ui/pages/home_page.dart:1639](../../lib/ui/pages/home_page.dart#L1639) | <code>bool _canAccessMenu(SirketMenuItem item, UserRole role) {</code> | Ekrana erişim kuralı; asıl yetki kontrolü sunucudadır |

**Olası nedenler**
- Düğme geri çağrısı rolden bağımsız verildi (ör. `onConfigurePolicy` her zaman verilir): görünürlük menü erişimine dayanır
- Yeni düğme eklenirken `canManageSites` ya da isSuperUser koşulu unutuldu
- `canManageApartmentUsers`/`canAssignDoorDevices` alanları kodda tanımlı ama görünüm içinde koşul olarak kullanılmıyor
- Arayüz düğmeyi gizlese bile yetki sunucuda zorlanır (sunucu 403 verir); yalnız arayüz gizlemesine güvenilmez

**Adım adım kontrol**
- Hesabın rolünü doğrulayın ve ilgili düğmenin koşulunu `sites_view.dart` / `site_card.dart` içinde bulun
- Düğme çalışıyorsa sunucu yanıtının 403 olup olmadığına bakın (yetki yalnız sunucuda güvenilir)
- Test: flutter test test/screens/sites_view_layout_test.dart

**İlgili testler:** [test/screens/sites_view_layout_test.dart](../../test/screens/sites_view_layout_test.dart)

**Bkz.:** [ui-menu-yanlis-rol](#ui-menu-yanlis-rol), [ui-guvenlik-politikasi](#ui-guvenlik-politikasi)

