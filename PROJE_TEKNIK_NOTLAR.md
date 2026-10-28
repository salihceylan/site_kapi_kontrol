# PROJE TEKNIK NOTLAR

Tarih: 2026-10-28 (ilk surum: 2026-03-09; bu surum koda karsi dogrulanarak guncellendi)

Bu dosya, `site_kapi_kontrol` ekosisteminde bugune kadar alinan teknik kararlarin, kurulum adimlarinin ve calisan mimarinin tek yerde toplanmis ozetidir.
Ayrintili ve guncel konu belgeleri `docs/` altindadir (rol/durum sozlugu: `docs/DURUM_SOZLUGU.md`, ekran listesi: `docs/EKRAN_ENVANTERI.md`,
platform modulleri: `docs/PLATFORM_*.md`). Bu dosya ile kod celisirse kod gecerlidir; celiskiyi duzeltin.

## 1. Projenin Amaci

Bu depo "Site ve Toplu Yasam Yonetim Sistemi" platformunun (uygulamanin gorunen adi; kapi kontrol urunu SmartKeyPass bir moduldur) parcalarini icerir:

1. Flutter istemci (`lib/`)
   TEK uygulama: `super_user`, `site_manager`, `apartment_owner` ve `individual` rollerinin hepsi ayni uygulamadan girer. Android uygulama kimligi
   `tr.com.gudeteknoloji.siteyonetim` (`android/app/build.gradle*`), gorunen ad "Site ve Toplu Yasam Yonetim Sistemi" (`AndroidManifest.xml`,
   `AppConfig.appName`). Hedefler: Android, iOS, Windows, web (linux/macos kabuklari da vardir).
2. Node.js API (`server/`) + PostgreSQL + MQTT koprusu.
3. Cihaz tarafi: `cihaz_kontrol/` (ESP32 firmware), `ekran_yazilimi/` (dokunmatik ekran firmware'i), `company_qr_tool/` (cihaz QR / firmware araci).

Not: Notlarin ilk surumunde anilan ayri `ahbu` mobil uygulamasi bu depoda yoktur; bu depodaki istemci tum rolleri karsilar. `AHBU` adi bugun yalnizca
degismeyen protokol kimliklerinde (bkz. 11.3) ve Ev Otomasyonu urununde kalmistir.

Genel hedef:

- Sirket tarafinda kullanici, site ve cihaz yonetimi yapmak (`super_user`)
- Bireysel kullanicilarin site basvurusu ile (super user onayiyla) site yoneticisi olmasi
- Daire kullanicilarinin yetkili akislarla sisteme baglanmasi
- ESP32 tabanli kapi cihazlarini guvenli sekilde uygulama ile kontrol etmek
- Her cihaza benzersiz bir QR kod verip sahada eslestirme yapmak
- Siteler icin acilip kapatilabilen modullerle (finans, duyuru, is takibi, rezervasyon ... toplam 23 modul, 8'i cekirdek) toplu yasam yonetimi

## 2. Roller

Sistemde tek `users` tablosu vardir. Roller ayri tablolar yerine `role` kolonu ile tutulur (`users.role`: `server/migrations/017_users_role_individual.sql`).

Roller:

- `super_user` (Super Kullanici)
- `site_manager` (Site Yoneticisi)
- `apartment_owner` (Daire Sahibi / Sakin)
- `individual` (Bireysel Kullanici)

Yetki mantigi:

- `super_user`
  - tum platformu yonetir: Kullanici Yonetimi, Super Kullanici Yonetimi, Site Yoneticileri Yonetimi, Daire Sakinleri, Site Yonetimi, Moduller,
    Sirket Cihaz Envanteri, Denetim Kaydi, Platform Ayarlari, Istemci Hatalari
  - site basvurularini (Site Basvurulari) ve modul taleplerini (Modul Talepleri) onaylar / reddeder; eski "Yeni Abonelik Talepleri" ve
    "Site Onay Talepleri" ekranlari menuden kalkmistir (`/admin/subscription-requests` uclari sunucuda durur)
  - site, cihaz ve kullanici kayitlarini olusturur (anlik site kurulumu yalnizca super user ve site yoneticisinde vardir)
- `site_manager`
  - kendi kendine kayit OLMAZ (`/auth/register` ve `/auth/site-manager/*` kapatildi, 410): bireysel kullanici olarak kaydolur, site basvurusu yapar ve
    super user onaylayinca site yoneticisi olur (`docs/PLATFORM_SITE_BASVURUSU.md`); ya da super user / mevcut yonetici davetiyle olusur
  - e-posta dogrulamasi, onay ve aktiflik kapilari girisi engeller (bkz. `docs/DURUM_SOZLUGU.md` B1)
  - cihazlari site kapilarina atayabilir ve cihaz ekleyebilir (cihaz ekleme yalnizca super user ve site yoneticisindedir; digerleri 403)
  - bir veya birden fazla siteyi yonetebilir; "Yonetici Paneli" ile "Sakin Modu" arasinda gecer
- `apartment_owner`
  - kayit ekrani yoktur; hesaplar daire servisi (`server/src/services/apartment_service.js`) ile yonetici / sistem tarafindan olusturulur
    (kullanici adi + PIN; yonetici `send-credentials` / `reset-pin` uclariyla gonderir ya da sifirlar)
  - daire ve kapilara erisim yetkileri vardir; sakin ekranlarini (Borcum, Dairem, Taleplerim, Rezervasyon ...) gorur
- `individual`
  - Bireysel kullanici olarak kaydolur (self-service): `/auth/register-individual`
  - E-posta dogrulama kodu (6 hane, 30 dk gecerli; `membership_rules.js`) ile hesap dogrulanir (`docs/EPOSTA_DOGRULAMA.md`)
  - Site kurmak icin basvurur (anlik kurulum bu role kapali: 409 `APPLICATION_REQUIRED`) ya da site katilim QR / kodu ile bir siteye katilma istegi yollar
  - Cihaz ekleyemez (`lib/ui/helpers/device_add_gate.dart`; sunucu `DEVICE_ADD_FORBIDDEN`)

Bir sitedeki baglar (`site_memberships.role`: `SITE_OWNER`, `SITE_ADMIN`, `RESIDENT`, `BOARD_MEMBER`, `STAFF`) ve daire baglari (`APARTMENT_ADMIN`,
`FAMILY_MEMBER`) hesap rolunden ayridir; hesap rolu "kim" oldugunu, bag rolu "bir sitede ne" oldugunu soyler. Ayrinti: `docs/DURUM_SOZLUGU.md` (Bolum A).

## 3. Repo ve Dizin Yapisi

Bu repo:

- Flutter uygulamasi (tum roller): `lib/`
- Node.js API: `server/`
- ESP32 firmware: `cihaz_kontrol/`; ekran firmware'i: `ekran_yazilimi/`
- Sirket icin QR / firmware araci: `company_qr_tool/`
- Canli dagitim betikleri: `deploy/`; arac betikleri: `tools/` (`klavuz`, `deneme_listesi`, `demo_seed`)
- Belgeler: `docs/`

Onemli dosyalar:

- Flutter giris noktasi: `lib/main.dart`, uygulama koku `lib/app.dart`
- Ana ekran (tek kabuk): `lib/ui/pages/home_page.dart`
- Menu (cekmece + Ayarlar paneli): `lib/ui/widgets/yan_menu.dart`
- Backend ana dosya: `server/src/server.js`
- DB schema bootstrap: `server/src/db.js`; migration calistirici: `server/scripts/migrate.js`
- Modul katalogu: `server/src/modules/catalog.js`
- Mail gonderimi: `server/src/mailer.js`
- MQTT kurulum notlari: `MQTT_kurulum.txt`
- Sunucu kurulum notlari: `sunucu_kurulum.txt`

## 4. Domain ve Uretim Bilgileri

Kullanilan canli domainler:

- API: `https://api.gudeteknoloji.com.tr`
- MQTT broker: `mqtt.gudeteknoloji.com.tr`

VPS:

- Host IP: `178.210.161.55`
- SSH port: `22667`

API sunum yapisi:

- Nginx reverse proxy
- Node.js / Express API
- PostgreSQL
- PM2 process yonetimi

## 5. Backend Mimarisi

Teknolojiler:

- Node.js (>= 20.19)
- Express 4
- PostgreSQL (`pg`)
- JWT
- bcryptjs
- nodemailer
- MQTT (`mqtt`), Web Push (`web-push`), PDF okuma (`pdfjs-dist`, banka ekstresi)

Kaynak yerlesimi: `server/src/routes/` (cekirdek: auth, admin, manager, membership, kapi, misafir gecisi, firmware), `server/src/modules/`
(platform ozellikleri: finans, duyuru, is takibi, rezervasyon, anket, belgeler/Dosya Deposu ... her biri `*_routes.js`, `*_service.js`, `*_schema.js`),
`services/`, `middlewares/`, `config/`, `utils/`, `security/`.

Ana endpoint gruplari (yol on ekleri; tam liste kodda):

- saglik:
  - `GET /health` (yanit: `ok`, `database`, `mqtt`)
- auth:
  - `POST /auth/register-individual`, `POST /auth/verify-code`, `POST /auth/resend-code` (bireysel kayit, 6 haneli e-posta kodu)
  - `POST /auth/login`
  - `POST /auth/forgot-password`, `GET|POST /auth/reset-password`
  - Google / Apple girisi ve SMS girisi: `server/src/modules/oauth_routes.js`, `notify_channels_routes.js`
  - KAPALI (410): `POST /auth/register`, `POST /auth/site-manager/register`, `/auth/site-manager/verify-email`, `/auth/site-manager/resend-code`
- profil:
  - `GET /me`
  - `PATCH /me`
  - hesap silme / veri disa aktarma: `/me/account-deletion`, `/me/data-export`
- admin (super user):
  - `GET|POST /admin/users`, `PATCH|DELETE /admin/users/:id`, `PATCH /admin/users/:id/activation`
  - `GET /admin/subscription-requests`, `PATCH /admin/subscription-requests/:id`
  - `GET|POST /admin/sites`, `PATCH|DELETE /admin/sites/:id`
  - `GET|POST /admin/devices`, `PATCH|DELETE /admin/devices/:id`
  - site basvurulari ve modul talepleri: `/admin/site-applications`, `/admin/module-requests`
- manager (site yoneticisi):
  - `GET|POST /manager/sites`, `PATCH|DELETE /manager/sites/:id`
  - `GET /manager/devices/lookup`, `PATCH /manager/devices/:id/assignment`, `PATCH /manager/doors/:id/device`
  - katilim istekleri: `/manager/join-requests/:requestId/approve|reject`
- uye / site basvurusu: `/membership/*` (cihaz sahiplenme, site kurulumu, `site-applications`)
- sakin ve modul uclari: `/app/*` (ornek: `GET /app/my-modules`), yonetici modul uclari `/manager/sites/:siteCode/...`
- cihaz firmware / OTA: `GET /firmware/:target/manifest.json`

## 6. Veritabani Tasarimi

Sema `server/migrations/` altindaki ardisik numarali `NNN_ad.sql` dosyalariyla kurulur (2026-10-28: 001-084). Asagidaki uc tablo ilk
sema parcalaridir; platform buyudukce 100'den fazla tablo eklenmistir (finans, duyuru, daire yonetimi, ...). Guncel sema icin migration dosyalarina ve
`docs/PLATFORM_*.md` belgelerine bakin.

### 6.1 users

Temel alanlar:

- `user_code`
  - 5 haneli benzersiz sayisal kod (`generate_unique_user_code`, 10000-99999)
- `full_name`
- `email`
- `role`
- `is_active`
- `phone_number`
- `password_hash`
- `created_at`

Abonelik / dogrulama alanlari:

- `email_verified`
- `approval_status`
  - `pending`
  - `approved`
  - `rejected`
- `email_verification_code_hash`
- `email_verification_expires_at`

Sonradan eklenenler (ornekler): `login_name` (giris adi), `must_change_password` (migration 077). Bireysel kayitta e-posta dogrulanana kadar
`users` satiri acilmaz; bekleyen kayit `pending_registrations` tablosunda tutulur (migration 028).

### 6.2 sites

Temel alanlar:

- `site_code`
  - 10 haneli benzersiz sayisal kod
- `name`
- `address`
- `city`
- `district`
- `created_at`

Sonradan eklenenler (ornekler): `management_type` (apartment_site, residence, business_center, cooperative, shopping_mall), `approval_status`.

### 6.3 devices

Temel alanlar:

- `id`
- `device_uid`
  - cihazdan okunan benzersiz kimlik
- `assigned_user_code`
  - opsiyonel
- `site_code`
  - opsiyonel
- `gate_name`
  - opsiyonel, sonradan eklendi
- `created_at`

### 6.4 Migration dosyalari

- Kaynak: `server/migrations/001_init.sql` ... `084_documents_into_drive_storage.sql` (ardisik, bosluk yok).
- Takip tablosu `schema_migrations`; calistirici `node scripts/migrate.js --status | --apply | --baseline` (kendiliginden calismaz; ayrinti `sunucu_kurulum.txt`).
- Bos veri dizininde `docker compose up` ile `server/migrations/*.sql` otomatik uygulanir (`docker-compose.yml`, `initdb.d`).

Not:

- `server/src/db.js` icindeki `ensureDbSchema()` uygulama ayaga kalkarken eksik kolon / tablo / index olusumunu da yapar (ekleyici ve idempotent).
- PostgreSQL owner / schema yetki sorunlari daha once yasanmistir. Uretimde `public` schema yetkileri `DB_USER` kullanicisi icin dogru verilmelidir.

## 7. Flutter Istemci (`lib/`)

Tek uygulama tum roller icindir. Oturum acilinca tek kabuk (`HomePage`) acilir; govde soldaki cekmeceden (8 baslik) ya da sag ustteki dislinin actigi
Ayarlar panelinden secilen menu ogesine (`SirketMenuItem`) gore degisir. Ilk ekran "Panel"dir (modul vitrini); kapi paneli "Kapilar" ogesindedir.
Hangi rolun hangi ekrani hangi modul kosuluyla gordugu `docs/EKRAN_ENVANTERI.md` belgesindedir.

Login ekrani:

- e-posta veya giris adi + parola; "Beni Hatirla", "Sifremi Unuttum?", Google / Apple dugmeleri, "Telefonla giris (SMS)", "Hesabiniz yok mu?" (bireysel kayit)
- rol secimi yoktur: rol sunucudan gelen kullanicidan okunur

Responsive kurallar:

- `SafeArea`
- `LayoutBuilder`
- `ConstrainedBox`
- dar ekranda alt alta yerlesim
- dialog genisligi ekrana gore hesaplanir

### 7.1 Arayuz Tasarim Sistemi ("Sade") ve Akicilik

- Kurallar ve bilesenler `docs/TASARIM_DILI.md` belgesindedir (karar G6 + G7: duz acik zemin, ince kenarli beyaz kart, durum metnin solunda nokta; onceki "Cilali Safir" cila / golge stili sayfa iceriginden kalkti).
- Tasarim sistemi `lib/ui/design/` altindadir: `tokens.dart` (AppSpace, AppRadius, AppMotion, AppPalette ThemeExtension, AppTone), `page_transitions.dart`, `buttons.dart`, `motion_widgets.dart`, `app_card.dart`, `status_chip.dart`, `empty_state.dart`, `app_dialog.dart`, `door_open_button.dart`, `countdown_ring.dart`, `skeleton.dart`, `app_snack.dart`, `login_hero.dart`. Ortak liste parcalari: `lib/ui/widgets/list_parts.dart`.
- Kural: yeni ekran/dialogda ham renk (`Color(0xFF...)`, `Colors.red`), `isDark ?:` uclusu ve sabit fontSize yazilmaz; `context.palette`, `AppTone.<ton>` ve tema TextTheme kullanilir. Metin renkleri iki temada da >= 4,5:1 kontrast olmalidir (`test/design/contrast_test.dart` hakemdir).
- Animasyon sureleri `AppMotion.of(context)` ile alinir (sistemde "animasyonlari azalt" aciksa sifir). `AnimatedSize`/`AnimatedCrossFade` icin sifir sure kullanilmaz (Flutter assert atar; 1 ms verilir). Kararli durumda sonsuz animasyon birakilmaz (rozet nabzi 3 tur sonra durur, iskelet parlamasi yalnizca yuklenirken).
- Dokunma hedefleri >= 44 dp; metin olcegi `lib/app.dart` icinde en cok 2,0 ile sinirlanir; yeni ekranlar 320x640 x 2,0 yazida tasmamalidir (AGENTS.md kural 6, `test/screens/`).
- Tek bilesenler: kapi acma `DoorOpenButton`, QR geri sayimi `CountdownRing`, yukleme `SkeletonBox`/`ShimmerScope`, bos liste `EmptyState`, durum rozeti `StatusChip`, diyalog `AppDialog`/`AppDialogHeader`, bildirim `AppSnack`/`InlineNotice`.
- Akicilik: ag yoklamalari `lib/services/adaptive_poller.dart` ile yapilir (arka planda/ortulu iken durur, hatada ustel geri cekilme, ust uste binmez; HomePage kapi durumu 3 sn, bireysel kapi listesi 15 sn, QR modali 0,8 sn); agir isler (PDF uretimi, >= 64 KB JSON) `lib/services/background_work.dart` ile arka plan izolesinde calisir; GET zaman asimi 20 sn, yazma 45 sn, kapi acma 10 sn.
- Kare suresi olcumu: `integration_test/perf_frames_test.dart` + `test_driver/perf_driver.dart` (komut `SAHA_KONTROL_LISTESI.md` bolum 52); calistirmak proje sahibine aittir.

## 8. Kapi Urunu: SmartKeyPass (Gecis Kontrol Modulu) Akislari

Kapi kontrol, platformun `door_control` modulu ("Gecis Kontrol (SmartKeyPass)") olarak ayni uygulamanin icindedir; ayri bir SmartKeyPass uygulamasi
bu depoda yoktur. Modul kapaliyken telefondan kapi acma, QR ve misafir gecisi durur; kapi menu ogeleri gizlenir (`docs/PLATFORM_MODUL_SISTEMI.md`).

Kayit ve giris:

- Yeni hesap bireysel kayitla acilir: ad soyad, e-posta, parola -> 6 haneli e-posta kodu -> dogrulama (bekleyen kayit; `docs/EPOSTA_DOGRULAMA.md`)
- Giris engelleri: e-posta dogrulanmadiysa (403), `approval_status` `pending` / `rejected` ise (403), hesap pasifse (403)
- Site yoneticisi olmak icin site basvurusu yapilir; super user onaylayinca rol `site_manager` olur

Cihaz ekleme ve kapiya atama (yalnizca super user ve site yoneticisi):

- Super user: "Sirket Cihazi Kaydet" (QR veya elle kayit) -> `POST /admin/devices`
- Site yoneticisi: "Kayitli Cihazlar" -> "Yeni Cihaz Kaydet" (kutu QR / seri no) -> `POST /membership/claim-device`
- Kapiya atama: `PATCH /manager/doors/:id/device` (yonetici) / `PATCH /admin/doors/:id/device` (super user); kaldirma `POST /manager/doors/:id/unassign-device`; degistirme `POST /manager/doors/:id/replace-device`
- Cihaz kimligi (`device_uid`) QR'dan ya da seri no'dan okunur. Eski `GET /manager/devices/lookup` ve `PATCH /manager/devices/:id/assignment` uclari sunucuda durur
  (`PATCH .../assignment` istemcide hala cagriliyor); `lookup`'i istemci artik cagirmaz

## 9. E-Posta Dogrulama

Mail gonderimi backend tarafinda `nodemailer` ile yapilir.

Gerekli `.env` alanlari:

```env
SMTP_HOST=...
SMTP_PORT=587
SMTP_USER=kodver@gudeteknoloji.com.tr
SMTP_PASSWORD=...
SMTP_FROM=kodver@gudeteknoloji.com.tr
```

Dogrulama akisi (bekleyen kayit, 30 dk kod, durust hata) ve isletim notlari: `docs/EPOSTA_DOGRULAMA.md`.

Not (2026-10-02 olcumu): `mint.trdns.com:587` ve `mail.gudeteknoloji.com.tr:587` her ikisi de (ayni IP 77.245.149.47)
~0,3 sn'de baglanti + TLS + kimlik dogrulamayi gecti; daha once not edilen TLS hostname uyusmazligi artik gozlenmiyor.
`mint.trdns.com` guvenli tercih olarak kalabilir.

SMTP testi icin kullanilan komut:

```bash
node --input-type=module -e "import nodemailer from 'nodemailer'; const t = nodemailer.createTransport({ host: 'mint.trdns.com', port: 587, secure: false, requireTLS: true, auth: { user: 'kodver@gudeteknoloji.com.tr', pass: '***' } }); t.verify().then(() => console.log('SMTP OK')).catch(err => { console.error(err); process.exit(1); });"
```

## 10. MQTT Altyapisi

Broker:

- `mqtt.gudeteknoloji.com.tr`

TLS port:

- `8883`

Kullanim mantigi:

- Mobil uygulama kapi komutunu API'ye gonderir
- API `api_bridge` MQTT kullanicisi ile cihaz komut topic'ine yazar
- ESP32 kendi cihaz kullanicisi ile sadece kendi topic'lerini dinler/yazar

Temel topic deseni (`server/src/mqtt_acl_sync.js`):

- komut (API -> cihaz): `device/<UID>/cmd`, QR sonucu `device/<UID>/qr_result`
- cihazdan: `device/<UID>/state`, `device/<UID>/event`, `device/<UID>/availability`, `device/<UID>/qr_verify`, `device/<UID>/screen_qr`, `device/<UID>/logs`

Ornek roller:

- `api_bridge`
- `device_<UID>`

Kurulum ve ACL notlari ayrintili olarak:

- `MQTT_kurulum.txt`

## 11. ESP32 Firmware ve QR Araci

### 11.1 cihaz_kontrol

PlatformIO tabanlidir (Arduino cercevesi, `espressif32`). Uretim hedefleri (`cihaz_kontrol/platformio.ini`):

- `lolin_c3_mini` (ESP32-C3 Super Mini)
- `esp32_relay_wroom` (ESP32-WROOM roleli kart)

Ekran firmware'i (`ekran_yazilimi/platformio.ini`): `esp32c3_display`. Baska ESP32 aileleri sonradan eklenebilir; bugun bu uc hedef vardir.

### 11.2 company_qr_tool

Amaci:

- takilan ESP32 cihazini bulmak
- benzersiz id'sini okumak
- ortasinda logo olan QR kod uretmek
- firmware derlemek
- firmware surumlemek
- secilen cihaza firmware yuklemek

Firmware cikti klasorleri:

- derleme: `cihaz_kontrol/.pio/build/<env>/`
- surumleme: `cihaz_kontrol/firmware_releases/`

Yerel (LAN) kapi kontrolu: UDP 8765, protokol v2 (challenge'a bagli HMAC-SHA256; token ag uzerinde gonderilmez, HTTP `/ahbu/open` kaldirildi). Sozlesme: `docs/YEREL_KONTROL_V2.md`. Firmware ve uygulama birlikte guncellenmelidir.

Firmware ana makine testleri (donanimsiz, Windows + MSVC): `cihaz_kontrol/host_test/` (`python run_all.py`, 719 dogrulama; ayrinti `cihaz_kontrol/host_test/README.md`).

### 11.3 Urun adi: SmartKeyPass (eski adi AHBU)

2026-10-16'dan beri kapi (Gecis Kontrol) urununun adi **SmartKeyPass**'tir; ad her yerde tam olarak `SmartKeyPass` yazilir. Modul adi "Gecis Kontrol (SmartKeyPass)". Ev otomasyonu urunu AHBU adini korur.

- Firmware WROOM 5.2.2 / C3 4.3.3 / ekran 1.1.3 ve sonrasi: BLE adi `SmartKeyPass<UID>`, mDNS adi `smartkeypass-<uid>`, MQTT istemci kimligi `SmartKeyPass-<UID>`, ekran ana sayfa markasi `SmartKeyPass`. Ad calisma aninda uretilir (NVS'te tutulmaz); eski bir kart bu firmware ile (USB ya da OTA) yeniden yuklenince SmartKeyPass olur. OTA yalniz artan surumu kabul ettigi icin yeni adli kart eski adli surume geri donmez. WROOM 5.2.1 / C3 4.3.2 / ekran 1.1.2 ara surumdur, hicbir karta yuklenmedi.
- BLE adi 24 karakterdir: tarama yanitina sigar, ama 128-bit servis UUID'li reklam paketinde kisaltilir ("SmartKey..."). Bu yuzden uygulama `SmartKey` ve `AHBU` oneklerini tanir (`isBleProvisionDeviceName`); sahadaki eski kartlar `AHBU<UID>` gorunmeye devam eder.
- company_qr_tool: karekod ve rapor logosu `assets/smartkeypass_logo.png`, USB paketi `flash_smartkeypass_usb.bat`.
- Logo karari (2026-10-17): Tum uygulama, site ve ikonlarda Gude Teknoloji logosu kullanilir; AHBU logosu kaldirildi. Kapi urununun adi SmartKeyPass olarak kalir. company_qr_tool karekod/rapor rozeti yukaridaki `smartkeypass_logo.png` dosyasini kullanmaya devam eder.
- DEGISMEYEN protokol kimlikleri (sahadaki cihazlarla uyum): karekod `AHBU:DOOR:<uid>:<token>`, `X-AHBU-Device-UID` basligi, `GET /ahbu/status`, mDNS servis turu `_ahbu._tcp`, ekranin seri kimligi `AHBU_DEVICE:DISPLAY`, NVS ad alani `ahbu_sys`, dahili hesap alani `@ahbu.local`, derleme bayraklari `AHBU_*`, company_qr_tool ortam degiskenleri `AHBU_*`. Bunlari degistirmek sahadaki kartlari ve mevcut `.env` dosyalarini bozar.

## 12. Uretim Sunucu Kurulumu

Detaylar:

- `sunucu_kurulum.txt`

Kisa ozet:

- VPS
- SSH port degisikligi
- UFW
- DNS
- Nginx
- SSL
- Docker PostgreSQL
- PM2

Canli dizin:

- `/var/www/site_kapi_kontrol` (API: `/var/www/site_kapi_kontrol/server`)

Backend process:

- `kapi-api` (`server/ecosystem.config.cjs`; tek kopya, cluster modu YOK)

Health check:

```bash
curl http://127.0.0.1:8080/health
```

Beklenen (`mqtt` alani MQTT koprusu durumunu da icerir):

```json
{"ok":true,"database":"connected","mqtt":{ ... }}
```

## 13. Uretimde Yapilan Kritik Duzeltmeler

1. PostgreSQL owner / schema yetki sorunlari

- `users` tablosu owner'i `DB_USER` olmali
- `public` schema icin `GRANT ALL` gerekli olabiliyor

2. PM2 restart sonrasi `EADDRINUSE`

- bazen eski process portu tutarken yeni baslatma denenmis
- `health` calisiyorsa aktif process ayakta demektir

3. SMTP TLS hostname uyusmazligi

- `mail.gudeteknoloji.com.tr` sertifika alani ile eslesmedi
- sertifika `mint.trdns.com` icindi
- (2026-10-02: her iki host da dogrulama testini gecti; bkz. `docs/EPOSTA_DOGRULAMA.md`)

4. Flutter dialog / lifecycle hatalari

- kayit sonrasi dialog kapatma akislarinda `disposed` / `_dependents.isEmpty` sorunlari goruldu
- dialoglar parent state uzerinden yonetilecek sekilde duzeltildi

## 14. Build ve Test Notlari

Flutter istemci (tum roller):

```bash
flutter clean
flutter pub get
flutter analyze
flutter test        # test sayisi icin komut ciktisina bakin; bu dosyada sayi tutulmaz
flutter build apk --release
```

Bu depoda ayri bir SmartKeyPass (`ahbu`) uygulamasi yoktur; tek istemci yukaridaki komutlarla derlenir (web / windows / ios icin `flutter build web|windows|ios`).

Backend (`cd server`, Node >= 20.19):

```bash
npm ci
npm test            # node --test
npm run lint        # eslint src
node --check src/server.js
```

Canliya alma: Bolum 15 (`deploy/README.md`).

## 15. Sunucuda Guncelleme Sirasi

Canli dagitim `git pull` ile DEGIL, `deploy/` betikleriyle yapilir (ayrinti ve komutlar: `deploy/README.md`, AGENTS.md kural 8):

1. Yerel dogrulama: `cd server && npm test && npm run lint`
2. Paket (src, scripts, migrations, package.json, package-lock.json, ecosystem.config.cjs, .env.example) + `sha256sum`
3. Yukleme (`scp`), ardindan hazirlik: yedek (`~/backups/kapi_<TS>/`), `node --check`, asamali `npm ci --omit=dev` (`prepare`)
4. Migration iceriyorsa sema provasi (`remote_rehearse_schema.sh`)
5. Etkinlestirme (`activate`): kodu yerlestirir, `pm2 restart kapi-api --update-env`, `/health` bekler; saglik basarisizsa otomatik geri alir
6. Dogrulama (`remote_verify.sh`, `pm2 logs kapi-api`); gerekirse geri alma (`rollback`)

Gerekirse DB yetki komutlari:

```bash
DB_USER=$(grep '^DB_USER=' /var/www/site_kapi_kontrol/server/.env | cut -d= -f2)

docker exec -it site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol -c "ALTER SCHEMA public OWNER TO $DB_USER;"
docker exec -it site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol -c "GRANT ALL ON SCHEMA public TO $DB_USER;"
docker exec -it site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;"
docker exec -it site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;"
docker exec -it site_kapi_kontrol_postgres psql -U postgres -d site_kapi_kontrol -c "GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO $DB_USER;"
```

## 16. Guvenlik Notlari

- Gercek sirlar repo icine yazilmaz
- `.env` uretimde sunucuda tutulur
- DB portu disariya acik birakilmaz
- SSH ayarlari degistirilirken ikinci terminalden baglanti testi yapilir
- Tam yetkili ikinci kullanicilar `sudo` alirsa tum sisteme mudahale edebilir

## 17. Acik Isler ve Karar Kaydi

Guncel acik isler ve yol haritasi tek yerde tutulur: `BEKLEYEN_ISLER.md` (saha/surum), `docs/PLATFORM_YOL_HARITASI.md` (urun kararlari) ve
`docs/superpowers/plans/` (calisma programlari). Notlarin ilk surumundeki acik maddelerin durumu:

- `site_manager` ile `sites` arasinda net sahiplik / yetki baglantisi: YAPILDI (`site_manager_sites` ve `site_memberships` `SITE_OWNER` / `SITE_ADMIN`)
- cihaz listesi ve cihaz detay ekranlari: YAPILDI ("Kayitli Cihazlar" / "Sirket Cihaz Envanteri", `CompanyDevicesView`)
- daha ayrintili audit log: YAPILDI ("Denetim Kaydi", `AuditLogView`, `server/src/modules/audit_service.js`)
- `apartment_owner` aktivasyonunun yonetilmesi: YAPILDI (Kullanici Yonetimi ekraninda `PATCH /admin/users/:id/activation`)
- merkezi teknik dokumanin surekli guncel tutulmasi: SUREKLI; ekran ve rol/durum listeleri `docs/EKRAN_ENVANTERI.md` ve `docs/DURUM_SOZLUGU.md` icindedir

## 18. Bu Dosyanin Amaci

Bu dosya, yeni bilgisayarda veya yeni oturumda sohbet gecmisi olmasa bile:

- sistemin ne oldugunu
- nelerin calistigini
- nerede neyin oldugunu
- hangi komutlarla yeniden ayaga kaldirilacagini
- hangi sorunlarin daha once yasandigini

tek yerden anlamayi saglamak icin tutulur.
