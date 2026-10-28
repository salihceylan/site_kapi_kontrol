# Ekran envanteri (istemci, `lib/`)

Bu belge Flutter istemcisindeki ana ekranların listesidir: **ad**, **yol (rota)** ve **hangi rolün hangi koşulda gördüğü**.
Her satır koddan çıkarılmıştır (2026-10-28 itibarıyla); kaynaklar sayfa sonundaki "Kaynak ve doğrulama" bölümündedir.
Kardeş belge: `docs/DURUM_SOZLUGU.md` (rol, durum ve terim sözlüğü).

## 1. "Rota" ne demek? (adlandırılmış rota yoktur)

İstemcide `routes:` tablosu, `onGenerateRoute` ya da `pushNamed` **yoktur** (`grep` ile doğrulandı). Ekranlara iki yoldan gidilir:

1. **Menü anahtarı.** Oturum açıkken tek kabuk vardır (`HomePage`). Kabuğun gövdesi `SirketMenuItem` (48 değer, `lib/ui/widgets/yan_menu.dart`)
   değerine göre değişir. Kullanıcı öğeyi soldaki **çekmeceden** (8 başlık) ya da sağ üstteki **dişliden açılan Ayarlar panelinden** seçer;
   Panel'deki (modül vitrini) kart da aynı seçimi yapar. Bu belgede "Rota (anahtar)" sütunu bu değerdir (testler ve kod bu adı kullanır).
2. **İtilen tam ekran sayfalar** (`MaterialPageRoute`): giriş öncesi sayfalar, QR tarayıcı, içe aktarma, yardım vb. (Bölüm 4).

Yeni ekran eklemenin kuralı (`yan_menu.dart` başlık yorumu): `SirketMenuItem` değeri + `menuGroupOf` eşlemesi + başlık/simge +
görünürlük kuralı (`HomePage._extraMenuItems` ve `_canAccessMenu`) + `_buildContentView` kolu; ardından **bu belgeye satır eklenir**.
Rol başına e2e ekran kayıt defteri: `integration_test/support/screens_*.dart`.

## 2. Roller ve koşullar (sütunlarda kullanılan dil)

| Terim | Anlamı (kodda karşılığı) |
| --- | --- |
| **Süper** | Hesap rolü `super_user` (`UserRole.superUser`). Modül süzgeci yoktur; ekranlar tüm siteleri çeker. |
| **Yönetici** | Hesap rolü `site_manager`, **yönetici modunda** (`!_isResidentMode`), ilgili sitede yönetici bağı (`my-modules` rolü `manager`). Yazma yetkisi yalnız bundadır (`_canManagePeople`). |
| **Sakin** | `apartment_owner` ya da **sakin modundaki** `site_manager`; ilgili sitede "alıcı" bağı (`_isRecipientSite`: rol `staff` değilse ya da kapı erişimi varsa). |
| **Kurul** | O sitede `board_member` bağı (Yönetim Kurulu / Denetçi): çoğu ekranda **salt okunur**. |
| **Görevli** | O sitede `staff` bağı (kapıcı, teknik görevli, danışma...). Çoğu ekranda yok; bazılarında salt okunur ya da dar iş. |
| **Bireysel** | Hesap rolü `individual`. |
| **Modül** | Ekran, ilgili modül o sitede **açıkken** görünür (`my-modules`). "çekirdek" = her sitede hep açık (`catalog.js`, `core: true`); "seçmeli" = süper açar ya da yönetici talep eder. Modül verisi hiç gelmediyse menü **açılmaz** ("fail-closed"). |

`my-modules` bağ rolü önceliği (sunucu `module_service.js`): `manager` (4) > `board_member` (3) > `staff` (2) > `resident` (1).
Kapı erişimi (`door_access`) yalnız yönetici, aktif daire üyeliği/sakin ve `is_allowed` kapı izni olan bağlarda `true`'dur; `board_member`,
`staff` ve yalnız `RESIDENT` site üyeliği kapı erişimi **sağlamaz**.

### Rol başına taban menü (modül koşulu uygulanmadan önce; `_itemsForRole`)

| Kitle | Taban liste |
| --- | --- |
| Süper (19) | Panel, Profilim, Kullanıcı Yönetimi, Süper Kullanıcı Yönetimi, Site Yöneticileri Yönetimi, Daire Sakinleri, Site Yönetimi, Kişiler, Modüller, Modül Talepleri, Site Başvuruları, Daireye Katıl, Yeni Site Oluştur, Şirket Cihazı Kaydet, Şirket Cihaz Envanteri, Bluetooth ile Wi-Fi Kur, Denetim Kaydı, Platform Ayarları, İstemci Hataları |
| Yönetici, yönetici modu (9) | Panel, Profilim, Site Yönetimi, Kişiler, Modüller, Kayıtlı Cihazlar, Daireye Katıl, Yeni Site Oluştur, Bluetooth ile Wi-Fi Kur |
| Yönetici, sakin modu (5) | Panel, Daireye Katıl, Yeni Site Oluştur, Profilim, Eller Serbest & Kestirmeler |
| Daire sakini (5) | Panel, Daireye Katıl, Yeni Site Oluştur, Eller Serbest & Kestirmeler, Profilim |
| Bireysel (4) | Panel, Daireye Katıl, Yeni Site Oluştur, Profilim |
| Yönetici moduna geçebilen sakin/bireysel hesap, yönetici modunda (7) | Panel, Profilim, Site Yönetimi, Kayıtlı Cihazlar, Daireye Katıl, Yeni Site Oluştur, Bluetooth ile Wi-Fi Kur |

Bunlara `HomePage._extraMenuItems` ile modül/bağ koşullu **ek öğeler** eklenir (Bölüm 3'teki tablolar). `kapilar` her rolde ek öğedir.
Moda geçiş (`_canToggleDualMode`): `site_manager` ve süper için her zaman; sakin/bireysel hesap için yalnız `GET /manager/sites` boş değilse
(sunucu `requireSiteManager`: `site_manager_sites` bağı ya da aktif `SITE_OWNER` / `SITE_ADMIN` üyeliği). Geçiş AppBar'daki hapla yapılır;
hapta geçilecek mod yazar: **Sakin Modu** ↔ **Yönetici Paneli**.

## 3. Menü ekranları

Sütunlar: **Ekran** (çekmece/panelde görünen ad) · **Rota (anahtar)** (`SirketMenuItem` değeri) · **Sınıf** (`lib/ui/views/` altındaki ekran) ·
**Modül** · **Kim görür / not**.

### 3.1 Çekmece: Ana sayfa

| Ekran | Rota (anahtar) | Sınıf | Modül | Kim görür / not |
| --- | --- | --- | --- | --- |
| Panel | `dashboard` | `ModuleShowcaseView` (`HomePage._buildShowcase`) | — | Herkes. Modül vitrinidir; kartlar çekmecenin görünür öğelerinden türer. Üç kitle: **yönetici** (üstte dikkat barı), **sakin** ("Güncel borcunuz" kartı + hızlı işlemler), **bireysel** (yalnız kart ızgarası + site başvurusu durumu). Kapı paneli artık Panel değil "Kapılar"dadır. |

### 3.2 Çekmece: Daireler

| Ekran | Rota (anahtar) | Sınıf | Modül | Kim görür / not |
| --- | --- | --- | --- | --- |
| Site Yönetimi | `siteler` | `SitesView` | — | Süper, Yönetici; yönetici moduna geçebilen sakin/bireysel hesap. Site, blok, daire, kapı, yönetici daveti, katılım QR'ı, Excel'den yükleme girişleri buradadır. |
| Daire Sakinleri | `daireKullanicilariYonetimi` | `SitesView` (`apartmentMode`) | — | Yalnız Süper. |
| Kişiler | `kisiler` | `PeopleView` — sekmeler: Kişiler · Daireler · Araçlar · Kadro | `people` (çekirdek) | Süper ve Yönetici (yazma); herhangi bir sitede Kurul (salt okunur). Görevli ve sakin görmez. |
| Dairem | `dairem` | `MyApartmentView` | — (modül gerekmez) | Daire sakini, Bireysel ve sakin modundaki yönetici. Bağlı daire yoksa bunu açıkça söyler. |
| Daireye Katıl | `katilimVeKurulum` | `JoinAndSetupView` | — | Her rol (erişim denetimi hep `true`). QR/kodla katılma isteği ve kurulum başvurusu durumu. |

### 3.3 Çekmece: Borçlar

| Ekran | Rota (anahtar) | Sınıf | Modül | Kim görür / not |
| --- | --- | --- | --- | --- |
| Finans | `finans` | `FinanceView` — sekmeler: Daireler · Tanımlar · Dönemler · Kasa · Giderler · Raporlar · Grafikler · Dekontlar | `finance` (çekirdek) | Süper; Yönetici (yazma); Kurul (salt okunur). |
| Borcum | `borcum` | `MyFinanceView` | `finance` (çekirdek) | Sakin. Süper ve Bireysel görmez. |
| Sayaçlar | `sayaclar` | `MetersView` — sekmeler: Sayaçlar · Okuma aktar · Faturalandır | `metering` (seçmeli) | Yönetici (yazma); Kurul (salt okunur); Görevli yalnız fotoğrafla okuma ekranını görür. Süper'de menü açılmaz. |

### 3.4 Çekmece: İletişim

| Ekran | Rota (anahtar) | Sınıf | Modül | Kim görür / not |
| --- | --- | --- | --- | --- |
| Duyurular | `duyurular` | `AnnouncementsView` | `announcements` (çekirdek) | Süper ve Yönetici (yönetim); Kurul (salt okunur); Sakin (gelen kutusu, okunmamış rozeti). Görevli ve Bireysel görmez. |
| Talepler | `talepler` | `WorkManagerView` — Liste · Rapor | `work_tracking` (seçmeli) | Süper; Yönetici, Görevli, Kurul (salt okunur). |
| Taleplerim | `taleplerim` | `WorkResidentView` | `work_tracking` | Sakin. |
| Anket ve Oylama | `anketler` | `SurveyManagerView` | `survey` (çekirdek) | Süper; Yönetici (yazar), Kurul (salt okunur). Görevli ve sakin görmez. |
| Anketler | `anket` | `SurveyResidentView` | `survey` | Sakin. |
| Rehber | `rehber` | `DirectoryView` | `directory` (seçmeli) | Sakin (yönetim kadrosu ve faydalı telefonlar). |
| Komşu Panosu | `komsuPanosu` | `NeighborBoardView` | `neighbor_board` (çekirdek) | Yönetici (onay/kaldırma); sitede alıcı olan sakin ve kurul (ilan yazar/şikayet eder). Süper'de menü açılmaz. |

### 3.5 Çekmece: Site hizmetleri

| Ekran | Rota (anahtar) | Sınıf | Modül | Kim görür / not |
| --- | --- | --- | --- | --- |
| Kapılar | `kapilar` | `DashboardView` (kapı paneli) · `IndividualHomeView` (bireysel/sakin kapı ekranı) · `DoorControlDisabledCard` | `door_control` (seçmeli) | Her rolde ek öğe. Bağlı **tüm** sitelerde Geçiş Kontrol kapalıysa ya da daire sakininin kapı erişimi/kapısı yoksa **gizlenir** (`hiddenMenuItemsFor`). Süper'de seçili site kapalıysa "modül kapalı" bilgi kartı çıkar. Daire sakininde (`apartment_owner`) çekmecede bu öğenin altına, kapı izinlerine göre, kısayollar eklenir: Sesli Kapı Açma, Kapıya QR Göster, Kapı Ekranından QR Oku, Kurye / Misafir Geçiş Linki Oluştur. |
| Yeni Site Oluştur | `yeniSite` | `YeniSiteView` | — | Her rol. Bireysel/daire hesabı **başvuru** yapar (anlık kurulum yalnız `site_manager` ve Süper'dedir). |
| Dosya Deposu | `belgeler` | `DocumentsView` | `drive_storage` (çekirdek) | Süper; Yönetici (yazar); Kurul (salt okunur); Sakin (paylaşılan belgeler). Görevli ve Bireysel görmez. Belgeler ayrı modül değildir; bu modülün parçasıdır (migration 084). |
| Rezervasyonlar | `rezervasyonlar` | `ReservationManagerView` — Rezervasyonlar · Konsiyerj · Alanlar | `reservation` (seçmeli) | Süper; Yönetici (alan tanımlar, karar verir); Görevli (karar verir); Kurul (salt okunur). |
| Rezervasyon | `rezervasyon` | `ReservationResidentView` | `reservation` | Sakin. |
| Ziyaretçi ve Kargo | `ziyaretciKayitlari` | `VisitorManagerView` | `visitor_log` (seçmeli) | Süper; Yönetici, Görevli (kayıt girer/kapatır); Kurul (salt okunur). |
| Ziyaretçilerim | `ziyaretcilerim` | `VisitorResidentView` | `visitor_log` | Sakin (kendi dairesinin kayıtları; "görülmemiş" rozeti). |
| Sözleşmeler | `sozlesmeler` | `ContractsView` — Sözleşmeler · Firmalar | `contracts` (seçmeli) | Süper; Yönetici (yazar); Kurul ve Görevli (salt okunur). Sakin görmez. |
| Karar Defteri | `kararDefteri` | `DecisionManagerView` | `decision_book` (seçmeli) | Süper; Yönetici (yazar, kesinleştirir); Kurul (taslaklar dahil salt okunur). Görevli ve sakin görmez. |
| Kararlar | `kararlar` | `DecisionResidentView` | `decision_book` | Sakin (sakinlere açık kesin kararlar). |
| İşletme Projesi | `isletmeProjesi` | `BudgetView` (+ `BudgetDetailPage`) | `budget` (seçmeli) | Süper; Yönetici (yazar); Kurul (salt okunur). |
| Faaliyet Raporu | `faaliyetRaporu` | `AnnualReportView` | `annual_report` (çekirdek) | Yalnız Yönetici. Süper'de menü açılmaz. |
| Plaka Tanıma | `plakaTanima` | `PlateRecognitionView` — Olaylar · Misafir izinleri · Kara liste · Ayarlar | `plate_recognition` (seçmeli) | Yönetici (yönetir); Kurul ve Görevli (salt okunur); Sakin yalnız kendi dairesi için "Misafir plakası" verir. Süper'de menü açılmaz. |
| Kamera ve Plaka | `odemeKamera` | `DeviceIntegrationsView` | `plate_cameras` (seçmeli) | Yönetici (yazar); Kurul (salt okunur). Sakin ve Görevli görmez; Süper'de menü açılmaz. Enum adı eskidir (eski ad "Ödeme ve Kamera"; kart ödemesi Aidat ve Finans'a taşındı). |
| Kamera (CCTV) | `kameraCctv` | `CctvView` — Kameralar · Olaylar | `cctv_link` (seçmeli) | Yönetici (yazar); Kurul ve Görevli (salt okunur). Sakin görmez; Süper'de menü açılmaz. |
| Ekipman ve Bakım | `ekipmanBakim` | `EquipmentView` — Ekipman · Bakım takvimi · Teklifler · Gider kırılımı | `equipment` (çekirdek) | Yönetici (yazar); Kurul ve Görevli (salt okunur). Sakin görmez; Süper'de menü açılmaz. |

Not: **Tahsilat**, **Giderler** ve **Raporlar** çekmece başlıkları tanımlıdır (`SirketMenuGroup`) ama bugün hiçbir öğe bu gruplara bağlı değildir;
öğesi olmayan başlık çizilmez. Çekmecede 8 başlık vardır: Ana sayfa, Daireler, Borçlar, Tahsilat, Giderler, İletişim, Raporlar, Site hizmetleri.
"Ayarlar" çekmece başlığı değildir; öğeleri sağ üstteki dişliden açılan panelde durur.

### 3.6 Ayarlar paneli (sağ üst dişli)

| Ekran | Rota (anahtar) | Sınıf | Modül | Kim görür / not |
| --- | --- | --- | --- | --- |
| Profilim | `profilim` | `ProfileView`; daire sakininde `ResidentProfileView` (salt okunur hesap bilgisi) | — | Her rol. Hesabı silme (`AccountDeletionView`) ve veri dışa aktarma buradaki gizlilik bölümündedir. |
| Eller Serbest & Kestirmeler | `ellerSerbest` | **Sayfa değil**: `HandsFreeSettingsDialog` açar (sesli kapı açma ayarı); sayfa değişmez | `door_control` | Daire sakini listesinde yer alır; Geçiş Kontrol kapalıyken gizlenir. |
| Kullanıcı Yönetimi | `kullaniciYonetimi` | `AllUsersView` | — | Yalnız Süper. |
| Süper Kullanıcı Yönetimi | `superUserYonetimi` | `ManagedUsersView` (rol: süper) | — | Yalnız Süper. |
| Site Yöneticileri Yönetimi | `siteYoneticileriYonetimi` | `ManagedUsersView` (rol: site yöneticisi) | — | Yalnız Süper. |
| Modüller | `moduller` | `ModulesView` (+ "Platform kuralları" kartı) | — | Süper (açıp kapatır); Yönetici (yönetici modunda; modül **talep** eder). |
| Modül Talepleri | `modulTalepleri` | `ModuleRequestsView` | — | Yalnız Süper (bekleyen sayı rozeti). |
| Site Başvuruları | `siteBasvurulari` | `SiteApplicationsView` | — | Yalnız Süper (bekleyen sayı rozeti). Site yöneticisi olma başvurularını inceler. |
| Şirket Cihazı Kaydet | `cihazEkle` | `DeviceAddView` | — | Yalnız Süper. (Kodda başlık rol dalları da vardır — "Cihaz Kaydet", bireysel için "Cihaz Ekle" — ama öğe Süper dışında hiçbir rolün listesinde yoktur; cihaz ekleme Yönetici'de "Kayıtlı Cihazlar" içindeki "Yeni Cihaz Kaydet" düğmesiyle yapılır.) |
| Şirket Cihaz Envanteri / Kayıtlı Cihazlar | `kayitliCihazlar` | `CompanyDevicesView` | `door_control` | Süper ("Şirket Cihaz Envanteri"); Yönetici ve yönetici moduna geçebilen hesap ("Kayıtlı Cihazlar"). Geçiş Kontrol kapalıyken gizlenir. |
| Bluetooth ile Wi-Fi Kur | `bluetoothWifiKur` | `BluetoothWifiView` (→ `WifiProvisionPage`) | `door_control` | Süper, Yönetici, yönetici moduna geçebilen hesap. Geçiş Kontrol kapalıyken gizlenir. |
| Denetim Kaydı | `denetimKaydi` | `AuditLogView` | — | Yalnız Süper. |
| Platform Ayarları | `platformAyarlari` | `PlatformSettingsView` | — | Yalnız Süper (uygulama sürümü/bakım, destek iletişimi, şirket ve yasal bilgiler). |
| İstemci Hataları | `istemciHatalari` | `ClientErrorsView` | — | Yalnız Süper. |
| Yönetim Firması *(panel eylemi)* | — | `ManagementCompanyScreen` (içinde "Marka teması" → `BrandThemeScreen`) | — | Süper ya da bir yönetim firması üyesi. |
| Masaüstüne Widget Ekle *(panel eylemi)* | — | Sayfa değil; widget ekleme isteği gönderir | — | Mobilde ve Süper dışında. |

### 3.7 Menüde yer almayan değerler

`abonelikTalepleri` ("Yeni Abonelik Talepleri", `SubscriptionRequestsView`) ve `siteOnayTalepleri` ("Site Onay Talepleri",
`PendingSiteApprovalsView`) `SirketMenuItem` içinde ve `_buildContentView` switch'inde durur, ama **hiçbir rolün taban listesinde yoktur**
ve `_canAccessMenu` onları her rol için reddeder (Süper için açıkça dışlanmıştır): menüden **erişilemezler**. Yerlerini Site Başvuruları ve
Modül Talepleri almıştır.

### 3.8 İstemcide ekranı olmayan modüller

Katalogda (`server/src/modules/catalog.js`) olup istemcide menü öğesi/ekranı bulunmayanlar: **Kartlı Geçiş** (`card_access`; yalnız sunucu
uçları var, istemcide yalnız denetim kaydı etiketi), **Online Tahsilat ve Banka Bağlantısı** (`online_payment`, `coming_soon`),
**HGS Geçişi** (`hgs_access`, `coming_soon`).

## 4. Giriş öncesi ve itilen tam ekran sayfalar

### 4.1 Açılış sırası (`lib/main.dart`, `lib/app.dart`)

| Sıra | Ekran | Sınıf | Ne zaman |
| --- | --- | --- | --- |
| 1 | Açılış kapısı | `AppGate` → `MaintenanceView` / `UpdateRequiredView` / yumuşak güncelleme uyarısı | Sunucudaki `/public/app-config` yanıtına göre; yapılandırma yüklenemezse uygulamayı **engellemez**. Kayıtlı oturum Süper ise bakım ve zorunlu güncelleme engelleri geçilir. |
| 2 | Açılış ekranı | `StartupSplash` | Oturum ya da ağ durumu belli olana dek. |
| 3 | İnternet yok | `NoInternetPage` | Oturum yokken ağ yoksa. |
| 4 | Giriş | `LoginPage` | Oturum yokken. E-posta/giriş adı + parola, "Beni Hatırla", "Şifremi Unuttum?" penceresi, Google/Apple düğmeleri, "Telefonla giriş (SMS)", "Hesabınız yok mu?". |
| 5 | Yasal onay kapısı | `LegalConsentGate` → `LegalConsentPage` | Oturum açıkken bekleyen yasal onay varsa ana sayfanın üstüne tam ekran biner; hata/zaman aşımında kilitlemez. |
| 6 | Ana sayfa | `HomePage` | Oturum açıkken tek kabuk: AppBar (başlık = ekran adı; altında "ad • rol / Sakin Modu"; mod hapı, tema düğmesi, Yenile, Çıkış Yap, Ayarlar), çekmece (`YanMenu`: site seçici satırı, mod geçişi, 8 başlık, Yardım ve Destek, Çıkış Yap), Ayarlar paneli, acil duyuru şeridi, **sakin alt çubuğu**. |

Sakin alt çubuğu (`ResidentTab`): **Özet · Duyuru · Arıza · Kapı · Dosyalar** (sırasıyla `dashboard`, `duyurular`, `taleplerim`, `kapilar`, `belgeler`);
her sekme çekmecede görünür olan öğeye bağlıdır, en az iki sekme yoksa çubuk çizilmez ve "Kapı" kapı yetkisinin olumlu kanıtını ister.

### 4.2 İtilen sayfalar (`MaterialPageRoute`)

| Sayfa | Sınıf | Nereden açılır |
| --- | --- | --- |
| SMS ile giriş | `SmsLoginPage` | Giriş ekranı → "Telefonla giriş (SMS)". |
| Bireysel kayıt | `RegisterIndividualPage` | Giriş ekranı → "Hesabınız yok mu?" |
| E-posta kodu doğrulama | `VerifyEmailCodePage` | Bireysel kayıttan sonra (6 haneli kod). |
| QR tarayıcı | `QrScanPage` | Kapı ekranından QR okuma, bireysel ana ekran, cihaz kaydı, daireye katılma isteği, cihaz değiştirme, Wi-Fi kurulumu. |
| Site yöneticisi seç | `SiteManagerPickerPage` | Site oluşturma/düzenleme penceresi. |
| Wi-Fi kurulumu (BLE) | `WifiProvisionPage` | Bluetooth ile Wi-Fi Kur. |
| Banka dosyası içe aktar | `BankImportView` | Finans → Kasa sekmesi, hesap kartından. |
| Banka satırları | `BankLinesView` | Finans dikkat barı ve banka içe aktarma. |
| Toplu yükleme (Excel/CSV) | `BulkImportView` | Kişiler, Site Yönetimi ve Finans açılış bakiyesi girişleri. |
| İşletme projesi ayrıntısı | `BudgetDetailPage` | İşletme Projesi listesi. |
| Sayaç saha okuma | `MeterFieldView` | Sayaçlar → "Fotoğrafla oku"; Görevli için doğrudan. |
| Platform kuralları | `PlatformRulesScreen` | Modüller ve Platform Ayarları'ndaki "Platform kuralları" kartı. |
| Yönetim firması / marka teması | `ManagementCompanyScreen` / `BrandThemeScreen` | Ayarlar paneli → Yönetim Firması. |
| Yardım ve Destek | `HelpView` | Çekmece → "Yardım ve Destek" ve Panel yardım bağlantısı. |
| Yasal belge okuma | `LegalDocumentView` | Giriş altbilgisi, kayıt/onay alanları, Yardım. |
| İlk kullanım turu | `OnboardingTourPage` | Giriş sonrası ilk açılışta bir kez (`OnboardingTour.maybeShow`); sonra Yardım'dan. |
| Hesabı silme | `AccountDeletionView` | Profilim → gizlilik bölümü → "Hesabımı Sil". |

## 5. Kaynak ve doğrulama

| Konu | Dosya |
| --- | --- |
| Menü öğeleri, başlıklar, gruplar, rol taban listeleri | `lib/ui/widgets/yan_menu.dart` (`SirketMenuItem`, `menuGroupOf`, `_itemsForRole`, `_titleForItem`) |
| Ek öğe, erişim ve modül kuralları, gövde seçimi | `lib/ui/pages/home_page.dart` (`_extraMenuItems`, `_canAccessMenu`, `_xxxSites`, `_buildContentView`, `_openMenuItem`) |
| Kapı öğelerini gizleme | `lib/ui/helpers/module_menu.dart` (`hiddenMenuItemsFor`) |
| Panel kitleleri ve kartlar | `lib/ui/helpers/module_showcase.dart` (`ShowcaseAudience`) |
| Sakin alt çubuğu | `lib/ui/helpers/resident_tabs.dart` |
| Açılış sırası | `lib/main.dart`, `lib/app.dart`, `lib/ui/views/app_gate_view.dart` |
| Bağ rolü ve modül durumu (sunucu) | `server/src/modules/module_service.js` (`/app/my-modules`), `server/src/modules/catalog.js` |

Sayılar (kodla sayıldı): `SirketMenuItem` 48 değer; bunların 2'si menüden erişilemez (Bölüm 3.7), 1'i sayfa değil iletişim kutusudur
(`ellerSerbest`).
