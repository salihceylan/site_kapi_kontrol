# Yayın Hazırlığı: Google Play ve App Store (2026-10-16)

Bu belge, "Site ve Toplu Yaşam Yönetim Sistemi" mobil uygulamasını mağazalara yüklemek için gerekenleri toplar.
Sahibi: F3 (Flutter/mobil). Sunucu tarafı sözleşmesi: `docs/PLATFORM_SATISA_HAZIRLIK.md`.

> Doğrulama notu: Aşağıdaki mağaza alanı uzunlukları, görsel boyutları ve hesap şartları yazarın bilgisine
> dayanır; Play Console ve App Store Connect'te canlı olarak DOĞRULANMADI. Yüklemeden önce ilgili konsolun
> güncel şartlarını kontrol edin. Doğrulanamayanlar "doğrulanmadı" diye işaretlidir.

## 1. Kalıcı kimlikler

| Alan | Değer |
|---|---|
| Android `applicationId` / `namespace` | `tr.com.gudeteknoloji.siteyonetim` |
| iOS `PRODUCT_BUNDLE_IDENTIFIER` | `tr.com.gudeteknoloji.siteyonetim` (testler: `….RunnerTests`) |
| Widget uygulama grubu (iOS, ileride) | `group.tr.com.gudeteknoloji.siteyonetim` |
| MethodChannel (Android Wi-Fi yardımcısı) | `tr.com.gudeteknoloji.siteyonetim/wifi_helper` |
| Özel bağlantı şeması (kapı kısayolları) | `sitekapi://` (değişmedi) |
| Dart paket adı | `site_kapi_kontrol` (değişmedi; yalnız içe aktarma adı) |

Paket kimliği mağazaya ilk yüklemeden sonra DEĞİŞTİRİLEMEZ. `test/release_identity_test.dart` Android, iOS,
Kotlin paketi, kanal adı ve gizlilik bildiriminin tek kimlikte buluştuğunu sınar; `com.example.*` kalıntısı
bulunursa kırılır.

## 2. Sürüm numarası

- Kaynak: `pubspec.yaml` içindeki `version: 1.0.0+1`. `+` öncesi kullanıcıya görünen sürüm, `+` sonrası
  derleme numarasıdır (Android `versionCode`, iOS `CFBundleVersion`).
- Her mağaza yüklemesinde derleme numarası ARTMALIDIR (örn. `1.0.1+2`).
- Uygulama sürümü `package_info_plus` ile okunur; sunucudaki `min_supported_version` / `latest_version` ile
  `major.minor.patch` olarak karşılaştırılır (derleme numarası yok sayılır).

### Sunucu tarafı sürüm kapısı (Platform Ayarları ekranı, süper kullanıcı)

| Ayar | Anlamı |
|---|---|
| `app.min_supported_version` | Bunun altındaki sürümler tam ekran "Güncelleme gerekli" görür |
| `app.latest_version` | Bunun altındaki sürümler kapatılabilir "Yeni sürüm hazır" uyarısı görür |
| `app.update_url_android` | `https://play.google.com/store/apps/details?id=tr.com.gudeteknoloji.siteyonetim` |
| `app.update_url_ios` | `https://apps.apple.com/app/id<APPLE_UYGULAMA_NO>` (uygulama no, App Store Connect'te oluşunca bilinir) |
| `app.maintenance_active` / `app.maintenance_message` | Bakım ekranı ve iletisi |

Kurallar:
- `min_supported_version` değerini YALNIZ yeni sürüm iki mağazada da kullanıcıya ulaştıktan sonra yükseltin;
  aksi hâlde kullanıcılar güncelleyemeyeceği bir ekranda kilitlenir.
- Yapılandırma okunamazsa (ağ yok, sunucu hatası, 4 sn zaman aşımı) uygulama ENGELLENMEZ.
- URL'ler yalnız `https://` olabilir; başka şema istemcide de açılmaz.
- **Süper kullanıcı kendini kilitlemez**: cihazda kayıtlı oturum `super_user` ise bakım ve zorunlu güncelleme
  engelleri GEÇİLİR (altta "yönetici görünümü" şeridi görünür); böylece bakımı kapatacak Platform Ayarları'na
  her zaman girilebilir. Oturum yoksa engel ekranındaki "Yönetici girişi" düğmesi giriş ekranını geçici açar;
  giriş yapılan hesap süper kullanıcı değilse engel geri gelir. Bu cihazda başka rolün oturumu açıksa düğme
  açıklama gösterir (oturumu kapatmak için uygulama verisini temizlemek ya da başka cihaz gerekir). Bu bir
  istemci kolaylığıdır, güvenlik sınırı değildir (yetkiyi sunucu uygular). Kaçış kalıcı bir mandal değildir:
  kayıtlı oturum 2 sn'de bir yoklanır; süper kullanıcı çıkış yapıp başka rolden biri girerse (ardışık 2 yoklamada
  süper kullanıcı oturumu görülmezse) engel geri gelir.
- Bakım/güncelleme ekranı açıkken gelen kapı derin bağlantıları ve kısayolları YOK SAYILIR. Soğuk açılışta
  bağlantı kapının ilk kararından önce gelebilir; işleyici ilk denetimin bitmesini en çok 5 sn bekler
  (kapı ağaçta değilse beklenmez, bağlantı yutulmaz).
- Yumuşak güncelleme uyarısı ve yönetici şeridi alttaki uygulama düğmelerinin ÜZERİNE binmez (uygulama kalan
  alanı kullanır; alt güvenli alan çift sayılmaz); ekranın en çok %35'i kadardır, aşarsa kayar; klavye açıkken gizlenir.
- Çökme raporlarındaki kişisel veri temizleme (CrashSanitizer) doğrusal zamanlıdır ve üst sınırla "yarım"
  maskelemez: çok uzun JWT/Bearer/anahtar-değer/e-posta/kullanıcı dizini tamamı maskelenir.
- Entegrasyon/ölçüm koşuları (`integration_test/support/e2e_driver.dart`) çökme raporlamayı `CrashReporter.suppress()`
  ile kapatır; `--dart-define=CRASH_REPORTING=false` yayın/profil derlemesinde de raporlamayı kapatır.

## 3. Anahtar yönetimi (Android yükleme anahtarı)

| Öğe | Konum / değer |
|---|---|
| Yükleme anahtarı (upload keystore) | `G:\site\_anahtarlar\siteyonetim-upload.jks` (repo DIŞINDA) |
| Gradle ayarları | `android\key.properties` (`.gitignore`'da; anahtarlar: `storeFile`, `storePassword`, `keyAlias`, `keyPassword`) |
| Takma ad (alias) | `upload` |
| Tür / algoritma | PKCS12, RSA 4096, SHA384withRSA, geçerlilik 10000 gün (2054'e kadar) |
| Yükleme sertifikası SHA-1 | `1E:43:D8:DF:5F:6C:26:A5:E8:55:2D:24:1A:1B:58:C1:09:BC:E3:AF` |
| Yükleme sertifikası SHA-256 | `4E:9C:66:FD:5E:64:36:51:48:60:50:E3:FD:73:E0:5E:F7:BF:56:95:5A:C9:E1:71:5C:69:D3:FF:0F:98:1E:3D` |

Parmak izleri herkese açık sertifika bilgisidir (sır değildir); Play Console'daki "yükleme sertifikası" ile
karşılaştırmak için kullanılır. Parolalar YALNIZ `android\key.properties` içindedir.

**Önemli uyarılar**
1. `.jks` dosyasını ve `key.properties` dosyasını **güvenli yere yedekleyin** (parola yöneticisi + şifreli
   harici yedek; iki ayrı konum). Dosyalar git'e girmez, sohbete/e-postaya konmaz.
2. Anahtar KAYBOLURSA: Play App Signing açıksa Play Console > Uygulama bütünlüğü > "Yükleme anahtarı
   sıfırlama" ile Google'dan yeni yükleme anahtarı kaydı istenir (günler sürebilir, sürüm yayını gecikir).
   Play App Signing KULLANILMAZSA anahtar kaybı uygulamayı güncellenemez kılar. Bu yüzden yeni uygulamada
   Play App Signing'i kabul edin (varsayılan).
3. Başka bilgisayarda derlerken iki dosyayı kopyalayın ve `key.properties` içindeki `storeFile` yolunu o
   makineye göre düzeltin (mutlak yol, `/` ayraçlı).
4. `key.properties` yoksa `flutter build ... --release` DEBUG anahtarıyla imzalar ve derleme çıktısına
   büyük bir UYARI basar. Böyle bir paket mağazaya yüklenemez; geliştirici derlemelerini bozmamak için
   bu davranış bilinçli bırakıldı. `key.properties` var ama eksik/bozuksa derleme HATA verir (yanlış imzalı
   paketin sessizce çıkmasını önlemek için).
5. Parolayı değiştirmek gerekirse: `keytool -storepasswd` ve `-keypasswd` (PKCS12'de ikisi aynı olmalı), sonra
   `key.properties` güncellenir.

Yeni anahtar üretimi (yalnız ilk kez; mevcut dosyanın ÜZERİNE YAZMAYIN):

```
keytool -genkeypair -keystore <yol>\siteyonetim-upload.jks -storetype PKCS12 -alias upload ^
  -keyalg RSA -keysize 4096 -validity 10000
```

Sertifika bilgisini görmek (parola sorar): `keytool -list -v -keystore <yol>\siteyonetim-upload.jks -alias upload`.

## 4. Derleme komutları

Android (Play Store AAB ister; test için APK):
```
flutter build appbundle --release          # build\app\outputs\bundle\release\app-release.aab  (Play'e yüklenir)
flutter build apk --release                # build\app\outputs\flutter-apk\app-release.apk     (doğrudan kurulum/test)
```
Derleme sırasında BAŞKA bir `flutter` komutu (özellikle `flutter test`, `flutter pub get`) çalıştırmayın:
eklenti kayıt dosyasını (`GeneratedPluginRegistrant.java`) yeniden yazıp release derlemesini
`integration_test` bulunamadı hatasıyla düşürebilir (2026-10-16'da yaşandı).

İmza doğrulama (Windows): `apksigner verify --print-certs app-release.apk` (Android SDK `build-tools\<sürüm>\apksigner.bat`)
çıktısındaki sertifika SHA-256'sı, bölüm 3'teki yükleme sertifikasıyla AYNI olmalıdır (`keytool -printcert -jarfile` v2/v3-only
APK'da "Not a signed jar file" verir; kullanmayın); debug sertifikası (`CN=Android Debug`) görünüyorsa paket yayına UYGUN DEĞİLDİR.

iOS (yalnız macOS + Xcode; Windows'ta derlenemez ve bu çalışmada DERLENMEDİ):
```
flutter build ipa --release
```
Ardından Xcode Organizer veya Transporter ile App Store Connect'e yükleyin.

Hata ayıklama sembolleri (isteğe bağlı): `--obfuscate --split-debug-info=build/symbols/<sürüm>` ile derlenirse
çökme raporlarındaki yığınlar çözülemez hâle gelir; kullanılacaksa sembol klasörünü her sürüm için arşivleyin
ve `flutter symbolize` ile çözün. Varsayılan derleme (bu seçenekler olmadan) okunabilir yığın verir.

## 5. Google Play Console kontrol listesi

**Hesap**: Geliştirici hesabı (kullanıcıdan gerekir). Kurumsal hesapta D-U-N-S numarası istenebilir; yeni kişisel
hesaplarda yayın öncesi kapalı test şartı olabilir (doğrulanmadı; konsoldaki güncel şartı kontrol edin).

**Uygulama oluştur**: Ad (≤30 karakter, doğrulanmadı), varsayılan dil Türkçe, Uygulama (oyun değil), Ücretsiz.

**Mağaza girişi**
- Kısa açıklama ≤80, tam açıklama ≤4000 karakter (doğrulanmadı).
- Uygulama simgesi 512×512 PNG; öne çıkan görsel 1024×500; telefon ekran görüntüsü en az 2 (en çok 8),
  her kenar 320–3840 px, uzun kenar kısa kenarın 2 katını geçmesin (doğrulanmadı).
- Tablet ekran görüntüsü (7"/10") zorunlu değildir ama tablet uyumluluğu için önerilir.
- Destek e-postası (zorunlu), web sitesi (isteğe bağlı), telefon (isteğe bağlı).

**Uygulama içeriği (App content)**
| Form | Cevap |
|---|---|
| Gizlilik politikası URL'si | `https://api.gudeteknoloji.com.tr/legal/privacy` |
| Hesap silme URL'si (Veri silme) | `https://api.gudeteknoloji.com.tr/legal/account-deletion` (uygulama içinde de: Profil > Hesabı sil) |
| Reklam | Hayır |
| Uygulamaya erişim | Giriş gerekir: inceleme için test hesabı bilgilerini (e-posta/parola, rol) forma yazın |
| Hedef kitle | 18 yaş ve üzeri (konut/site yönetimi) |
| İçerik derecelendirme | Anket: şiddet/cinsellik/kumar yok; kullanıcı etkileşimi yok (duyurular yöneticiden sakinlere tek yönlü) |
| Finansal özellikler | Uygulama içi ödeme/kredi yok; yalnız yönetici girişli aidat KAYITLARI görüntülenir: "finansal özellik yok" |
| Sağlık, haber, devlet uygulaması | Hayır |
| COVID-19 / diğer beyanlar | Hayır |

**İzinler (AndroidManifest)** ve gerekçeleri (hepsi kodda kullanılıyor; gereksiz izin yok):
| İzin | Gerekçe |
|---|---|
| `INTERNET`, `ACCESS_NETWORK_STATE` | Bulut API, bağlantı kontrolü, ağa bağlama |
| `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`, `CHANGE_NETWORK_STATE` | Yerel ağda kapı kontrol cihazı keşfi (UDP yayını) ve Wi-Fi ağına bağlanma |
| `CAMERA` | QR kod okuma (cihaz ekleme, kapı QR, site katılım) |
| `RECORD_AUDIO` | Sesle kapı açma |
| `BLUETOOTH*`, `BLUETOOTH_SCAN/CONNECT` | Yeni cihaza Bluetooth ile Wi-Fi ayarı gönderme |
| `ACCESS_FINE/COARSE_LOCATION` | Kapıya yakınlık doğrulaması (geofence), Android ≤11'de BLE taraması |
Arka plan konumu, SMS, arama kaydı, `QUERY_ALL_PACKAGES` YOKTUR; özel izin beyan formu gerekmez
(doğrulanmadı: konsol uyarılarına bakın).

**Hedef API / teknik**
- Flutter 3.47.2 varsayılanı: `compileSdk 36`, `targetSdk 36`, `minSdk 24`. Play'in güncel hedef API şartı
  burada DOĞRULANMADI; yükleme sırasında Play Console uyarı verirse `flutter` sürümünü/`targetSdk`'yı güncelleyin.
- Android 16 (API 36) hedefli uygulamalarda büyük ekranlarda (≥600 dp) `screenOrientation="portrait"`
  kısıtı yok sayılabilir; arayüz yatay/geniş düzende bozulmamalıdır (kapı ekranları yatayda test edildi).
- Dağıtım biçimi: AAB. Play App Signing: kabul edin.
- R8 küçültme açık (Flutter varsayılanı) ve `android/app/proguard-rules.pro` var. R8'li release paketi bu
  çalışmada cihazda DENENMEDİ (kural eksikliği ancak cihazda görülür); BLE, widget, QR ve ses akışlarını
  yayından önce bir cihazda deneyin.

### Veri güvenliği formu (Data safety) taslağı

Kodla doğrulanmış gerçek veri akışları (kanıt: dosya):
| Veri türü (Play) | Toplanıyor mu | Amaç | Üçüncü tarafla paylaşım | Zorunlu mu | Kanıt |
|---|---|---|---|---|---|
| Ad, e-posta, telefon | Evet | Uygulama işlevi, hesap yönetimi | Hayır | Ad/e-posta zorunlu, telefon isteğe bağlı | `lib/services/auth_api.dart` (`/auth/*`), `lib/models/user_session.dart` |
| Kullanıcı kimlikleri | Evet | Uygulama işlevi | Hayır | Zorunlu | `user_code`, oturum belirteci |
| Kesin konum | Evet (yalnız kapı açma / dinamik QR isteğinde ve site güvenlik ayarında) | Uygulama işlevi (kapıya yakınlık) | Hayır | Siteye göre; konum kapalı politikalı kapıda gönderilmez | `lib/services/geofence_service.dart`, sunucuda `qr_access_tokens.request_latitude/longitude` SAKLANIR |
| Diğer finansal bilgi | Evet | Aidat borç/ödeme kayıtlarının görüntülenmesi (kart/banka bilgisi YOK) | Hayır | Siteye göre | `lib/models/finance.dart` |
| Diğer kullanıcı içeriği | Evet | Araç plakaları, duyurular, notlar | Hayır | İsteğe bağlı | `lib/models/vehicle_record.dart` |
| Diğer eylemler / uygulama etkinliği | Evet | Kapı geçiş ve denetim kayıtları | Hayır | Zorunlu (güvenlik) | `lib/models/door_access_log_record.dart`, `lib/models/audit_log.dart` |
| Kilitlenme günlükleri / tanılama | Evet | Hata ayıklama, uygulama işlevi | Hayır | Otomatik | `lib/services/crash_reporter.dart` (kişisel veri temizlenir, 90 gün sonra silinir) |
| Cihaz veya diğer kimlikler | Evet (kuruluma özgü rastgele `install_id`, reklam kimliği DEĞİL) | Hata raporlarının tekilleştirilmesi | Hayır | Otomatik | `lib/services/crash_reporter.dart` |
| Ses kaydı | Uygulama kaydetmez/göndermez; ses tanıma cihazın konuşma servisinde işlenir | Sesle kapı açma | (İşletim sistemi servisi) | İsteğe bağlı | `lib/services/voice_door_service.dart` |

Genel cevaplar: Veriler aktarım sırasında şifrelenir (HTTPS/TLS; MQTT TLS). Kullanıcı veri silme isteyebilir
(uygulama içi + web URL'si). Veri satılmaz, reklam/izleme/analitik SDK'sı yoktur (kodla doğrulandı: bağımlılıklarda
Firebase, reklam veya analitik paketi yok). Konuşma tanımanın Google/Apple servislerine ses gönderip
göndermediği cihaza/ayara göre değişir: hukuk ajanı ile birlikte "ses verisi" beyanını gözden geçirin.

## 6. App Store Connect kontrol listesi

**Hesap**: Apple Developer Program üyeliği ve **Team ID** (kullanıcıdan gerekir; depoya YAZILMADI,
`DEVELOPMENT_TEAM` boş).

**Xcode / imza**: Runner hedefinde Signing > Team seçin; paket kimliği `tr.com.gudeteknoloji.siteyonetim`.
App Store Connect'te aynı kimlikle App ID ve uygulama kaydı oluşturun. Dağıtım sertifikası + profil
(otomatik imza yeterli). Minimum iOS 15.0 (home_widget eklentisi ≥14 ister; Flutter 3.47 şablonu 15.0).

**Info.plist (hazır)**: kamera, mikrofon, konuşma tanıma, Bluetooth, konum (kullanımda) ve **yerel ağ**
(`NSLocalNetworkUsageDescription`) açıklamaları Türkçedir. `ITSAppUsesNonExemptEncryption = false`
(yalnız standart HTTPS/TLS, MQTT-TLS ve kimlik doğrulama amaçlı HMAC-SHA256 kullanılıyor: kodla doğrulandı;
nihai ihracat uyumu beyanı sizindir). Face ID/fotoğraf/kişiler/izleme izinleri KODDA KULLANILMADIĞI için
eklenmedi. ATS: uygulama yalnız HTTPS çağırır, yerel ağ HTTP'si yoktur; bu yüzden `NSAllowsLocalNetworking`
eklenmedi. iPad: çoklu görev doğrulaması için dört yönelim bildirildi (iPhone yalnız dikey; kod dikeye kilitler).

**Gizlilik bildirimi**: `ios/Runner/PrivacyInfo.xcprivacy` (Runner kaynaklarına bağlı): izleme YOK; toplanan
türler yukarıdaki tabloyla aynı (ad, e-posta, telefon, kullanıcı kimliği, kesin konum, diğer kullanıcı içeriği,
diğer finansal bilgi, diğer kullanım verisi, cihaz kimliği, kilitlenme verisi). Gizlilik manifesti olmayan
eklentiler (flutter_tts, home_widget, printing, reactive_ble_mobile, speech_to_text) kaynağında tarandı;
yalnız `home_widget` zorunlu-neden API'si kullanıyor (UserDefaults, neden `CA92.1`: projede App Group yetkisi
YOKTUR, veri yalnız uygulamaya açıktır) ve uygulama manifestinde bildirildi. İleride iOS widget uzantısı + App Group
eklenirse (`com.apple.security.application-groups`) `1C8F.1` nedeni de eklenmelidir. Apple'ın doğrulaması macOS'ta
yükleme sırasında görülür (BU ÇALIŞMADA DERLENMEDİ).

**Yerel ağ yayını (önemli risk, doğrulanmadı)**: Yerel kapı kontrolü UDP yayın/çok noktaya yayın kullanır
(`lib/services/local_door_service.dart`). iOS 14+ yayın/çok noktaya yayın için Apple'dan
`com.apple.developer.networking.multicast` yetkisi ister (başvuru gerekir). Yetki yoksa iOS'ta yerel
keşif çalışmayabilir; bulut/MQTT yolu etkilenmez. Yetki alınırsa `Runner.entitlements` eklenmelidir (şimdi
EKLENMEDİ: profil olmadan imzayı bozar). Yayından önce gerçek iPhone'da yerel kapı açmayı deneyin.

**App Store Connect alanları**
| Alan | Değer / not |
|---|---|
| Ad, alt başlık, anahtar sözcükler | 30 / 30 / 100 karakter sınırı (doğrulanmadı) |
| Kategori | Yardımcı Programlar veya Yaşam Tarzı |
| Gizlilik politikası URL'si (zorunlu) | `https://api.gudeteknoloji.com.tr/legal/privacy` |
| Destek URL'si (zorunlu) | Destek sayfası veya `…/legal/privacy` dışında bir iletişim sayfası |
| Uygulama gizliliği (etiketler) | Bölüm 5'teki tabloyla aynı: izleme yok |
| Yaş derecelendirmesi | 4+ (içerik yok) |
| Hesap silme | Uygulama içinde mevcut (Profil > Hesabı sil) ve web: `…/legal/account-deletion` |
| Üçüncü taraf giriş | Yok (yalnız e-posta/parola); "Apple ile giriş" şartı doğmaz |
| Uygulama İnceleme bilgisi | Demo hesap (e-posta + parola + rol), donanım notu: "Kapı kontrol cihazı olmadan kapı açma simülasyonu görülemez; arayüz demo hesabıyla gezilebilir" |
| AB Dijital Hizmetler Yasası (DSA) satıcı beyanı | AB'de dağıtılacaksa gerekir |

## 7. Ekran görüntüsü gereksinimleri (doğrulanmadı; konsolda kontrol edin)

| Mağaza | Gereken |
|---|---|
| Google Play | Telefon: en az 2 (dikey 9:16 önerilir, her kenar 320–3840 px). Simge 512×512, öne çıkan görsel 1024×500 |
| App Store | iPhone: 6.9" (1320×2868 veya 1290×2796) en az 1 set; 6.5" (1284×2778) yedek. iPad desteklendiği için iPad 13" (2064×2752 veya 2048×2732) seti de gerekir. Her set 1–10 görsel |

iPad ekran görüntüsünden kaçınmak isterseniz Xcode'da `TARGETED_DEVICE_FAMILY` değerini `1` (yalnız iPhone) yapın.
Ekran görüntülerinde gerçek kişi verisi (ad, telefon, plaka, adres) olmasın; demo hesap kullanın.

## 8. Kullanıcıdan gerekenler (kontrol listesi)

- [ ] `G:\site\_anahtarlar\siteyonetim-upload.jks` ve `android\key.properties` dosyalarını güvenli, ayrı iki yere yedekleyin.
- [ ] Google Play geliştirici hesabı; Play App Signing'i kabul etme; uygulama kaydı.
- [ ] Apple Developer üyeliği; **Team ID**; App Store Connect uygulama kaydı; (gerekirse) multicast yetkisi başvurusu.
- [ ] `/admin/platform-config` ile yasal şirket alanlarını doldurun (unvan, adres, e-posta, telefon; MERSİS ve KEP varsa):
      zorunlu alanlar dolmadan gizlilik/silme sayfaları `[……]` yer tutucularıyla ve "tamamlanmamış" yayımlanır, mağaza incelemesi
      reddedebilir. MERSİS ve KEP boş kalabilir (karar H1, 2026-10-21): boşken metinlerde hiç görünmez. Durum:
      `docs/yasal/KULLANICIDAN_GEREKENLER.md` bölüm 1 "Durum".
- [ ] Destek bilgileri (e-posta, telefon, saatler, web) aynı ekranda.
- [ ] Mağaza metinleri, ekran görüntüleri, simge ve öne çıkan görsel.
- [ ] İnceleme için demo hesaplar (her rol için, gerçek veri içermeyen).
- [ ] Yayından sonra `app.update_url_android` / `app.update_url_ios` ve `latest_version` değerlerini girin.
- [ ] Gizlilik politikasında çökme raporlamayı belirtin (hukuk ajanı metni): rastgele kurulum kimliği, sürüm,
      işletim sistemi sürümü, temizlenmiş hata metni; hesapla ilişkilendirilmez; 90 gün sonra silinir.
- [ ] Bölüm 5 ve 6'daki sorulara karar verin: ses verisi beyanı, finansal bilgi beyanı, iPad desteği.

## 9. Yayın öncesi son doğrulama

1. `flutter analyze` (tüm proje) ve `flutter test` (tüm süit) temiz.
2. `flutter build appbundle --release` `key.properties` ile; çıktıda "UYARI: key.properties bulunamadı" YOK.
3. `apksigner verify --print-certs <apk>` SHA-256 = bölüm 3'teki yükleme sertifikası (debug sertifikası `CN=Android Debug` görünüyorsa YENİDEN derleyin; `build/app/outputs/flutter-apk/app-release.apk` anahtar oluşturulmadan önce üretilmişse debug imzalıdır).
4. Cihazda (R8'li release): giriş, kapı açma (bulut), QR okuma, ses, BLE kurulum, ana ekran widget'ı, deep link.
5. Sunucuda `GET /public/app-config` yanıtı (`min_supported_version` <= yüklenen sürüm), `GET /legal/privacy` ve
   `GET /legal/account-deletion` HTTP 200 ve "tamamlanmamış" yer tutucu içermiyor.
6. Çökme raporlama canlı denemesi: yayın derlemesinde zorla bir hata üretip `GET /admin/client-errors` listesinde görün
   (debug derlemede kapalıdır; geliştirici için `--dart-define=CRASH_REPORTING=true`).

## 10. Açık noktalar / doğrulanamadı

- iOS projesi (pbxproj, Info.plist, PrivacyInfo) Windows'ta DERLENMEDİ; yalnız biçim/çapraz referans denetimi yapıldı.
- Play'in güncel hedef-API şartı, mağaza alan sınırları ve ekran görüntüsü boyutları doğrulanmadı.
- R8'li release paketinin cihazda davranışı denenmedi.
- Ses tanıma beyanı ve iOS multicast yetkisi karar/başvuru bekliyor.
- Bağlantı denetimi, API `/health` yanıt vermezse yedek olarak `https://clients3.google.com/generate_204`
  adresine istek atar (kullanıcı verisi içermez ama IP adresi Google'a görünür); gizlilik metninde belirtmek veya
  yedeği kaldırmak değerlendirilmeli.
