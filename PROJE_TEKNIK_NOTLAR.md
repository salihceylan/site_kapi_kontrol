# PROJE TEKNIK NOTLAR

Tarih: 2026-03-09

Bu dosya, `site_kapi_kontrol` ekosisteminde bugune kadar alinan teknik kararlarin, kurulum adimlarinin ve calisan mimarinin tek yerde toplanmis ozetidir.

## 1. Projenin Amaci

Bu ekosistem 3 ana parcadan olusur:

1. `site_kapi_kontrol`
   Sirketin kullandigi yonetim uygulamasi.
2. `ahbu`
   Son kullaniciya / site yoneticisine dagitilan mobil uygulama.
3. `cihaz_kontrol` + `company_qr_tool`
   ESP32 firmware'i ve cihaz QR / firmware yonetim araci.

Genel hedef:

- Sirket tarafinda kullanici, site ve cihaz yonetimi yapmak
- Site yoneticilerinin kontrollu abonelik talebi olusturmasi
- Daire kullanicilarinin yetkili akislarla sisteme baglanmasi
- ESP32 tabanli kapi cihazlarini guvenli sekilde uygulama ile kontrol etmek
- Her cihaza benzersiz bir QR kod verip sahada eslestirme yapmak

## 2. Roller

Sistemde tek `users` tablosu vardir. Roller ayri tablolar yerine `role` kolonu ile tutulur.

Roller:

- `super_user` (Super Kullanici)
- `site_manager` (Site Yoneticisi)
- `apartment_owner` (Daire Sahibi / Sakin)
- `individual` (Bireysel Kullanici)

Yetki mantigi:

- `super_user`
  - sirket uygulamasina girer
  - super user, site yoneticisi, daire kullanicisi, bireysel kullanici yonetir
  - abonelik taleplerini onaylar / reddeder
  - site ve cihaz kayitlarini olusturur
  - tum kullanicilari yonetir (Kullanici Yonetimi sayfasi)
- `site_manager`
  - `ahbu` uygulamasinda kayit olabilir
  - e-posta dogrulamasindan gecer
  - sirket onayindan sonra giris yapabilir
  - kendine tanimli cihazlari site kapilarina atayabilir
  - bir veya birden fazla siteyi yonetebilir
- `apartment_owner`
  - `ahbu` uygulamasinda kayit ekrani gormez
  - hesaplari yonetici / sistem tarafindan olusturulur
  - daire ve kapilara erisim yetkileri vardir
- `individual`
  - Bireysel kullanici olarak kaydolur (self-service)
  - E-posta dogrulama kodu (6 hane) ile hesap dogrulanir
  - Kutu QR kodu veya seri no ile cihaz sahiplenir
  - Cihazin sahibi olarak site kurucu yoneticisi olur
  - Site katilim QR ile baslattigi uyelik talebi onaylaninca daire ve site erisimi kazanir

## 3. Repo ve Dizin Yapisi

Bu repo:

- Flutter sirket uygulamasi: `lib/`
- Node.js API: `server/`
- ESP32 firmware: `cihaz_kontrol/`
- Sirket icin QR / firmware araci: `company_qr_tool/`

Ilgili ayri repo:

- `ahbu`: `https://github.com/salihceylan/ahbu.git`

Onemli dosyalar:

- Flutter giris noktasi: `lib/main.dart`
- Sirket ana ekran: `lib/ui/pages/home_page.dart`
- Sirket drawer: `lib/ui/widgets/yan_menu.dart`
- Backend ana dosya: `server/src/server.js`
- DB schema bootstrap: `server/src/db.js`
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

- Node.js
- Express
- PostgreSQL
- JWT
- bcrypt
- nodemailer

Ana endpoint gruplari:

- saglik:
  - `GET /health`
- auth:
  - `POST /auth/register`
  - `POST /auth/login`
  - `POST /auth/site-manager/register`
  - `POST /auth/site-manager/verify-email`
  - `POST /auth/site-manager/resend-code`
- profil:
  - `GET /me`
  - `PATCH /me`
- admin:
  - `GET /admin/users`
  - `POST /admin/users`
  - `PATCH /admin/users/:id`
  - `PATCH /admin/users/:id/activation`
  - `DELETE /admin/users/:id`
  - `GET /admin/subscription-requests`
  - `PATCH /admin/subscription-requests/:id`
  - `GET /admin/sites`
  - `POST /admin/sites`
  - `PATCH /admin/sites/:id`
  - `DELETE /admin/sites/:id`
  - `POST /admin/devices`
- manager:
  - `GET /manager/sites`
  - `GET /manager/devices/lookup`
  - `PATCH /manager/devices/:id/assignment`

## 6. Veritabani Tasarimi

### 6.1 users

Temel alanlar:

- `user_code`
  - 5 haneli benzersiz sayisal kod
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

### 6.2 sites

Temel alanlar:

- `site_code`
  - 10 haneli benzersiz sayisal kod
- `name`
- `address`
- `city`
- `district`
- `created_at`

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

Mevcut migrationlar:

- `server/migrations/001_init.sql`
- `server/migrations/004_user_verification_and_approval.sql`
- `server/migrations/005_device_gate_assignment.sql`

Not:

- `server/src/db.js` icindeki `ensureDbSchema()` uygulama ayaga kalkarken eksik kolon / tablo / index olusumunu da yapar.
- PostgreSQL owner / schema yetki sorunlari daha once yasanmistir. Uretimde `public` schema yetkileri `DB_USER` kullanicisi icin dogru verilmelidir.

## 7. Sirket Uygulamasi (`site_kapi_kontrol`)

Sirket uygulamasi sadece `super_user` icindir.

Login ekrani:

- yalnizca super user girisi
- rol secimi yok

Drawer menusu:

- `Panel`
- `Profilim`
- `Yeni Abonelik Talepleri`
- `Super User Yonetimi`
- `Site Yoneticileri Yonetimi`
- `Daire Kullanicilari Yonetimi`
- `Site Yonetimi`
- `Cihaz Ekle`
- `Cikis Yap`

Onemli ekranlar:

- kullanici yonetim ekranlari
  - yatay, dusuk yukseklikli rehber tipi satirlar
  - detaylar tiklandiginda popup
  - aktivasyon switch
  - duzenle / sil ikonlari
- abonelik talepleri
  - e-posta dogrulamasini tamamlayan `site_manager` hesaplarini gosterir
  - onay / red islemine izin verir
- site yonetimi
  - site ekle / guncelle / sil
- cihaz ekle
  - QR okut
  - cihaz unique id'yi al
  - cihazi DB'ye kaydet

Responsive kurallar:

- `SafeArea`
- `LayoutBuilder`
- `ConstrainedBox`
- dar ekranda alt alta yerlesim
- dialog genisligi ekrana gore hesaplanir

### 7.1 Arayuz Tasarim Sistemi ("Cilali Safir") ve Akicilik

- Tasarim sistemi `lib/ui/design/` altindadir: `tokens.dart` (AppSpace, AppRadius, AppMotion, AppPalette ThemeExtension, AppTone), `page_transitions.dart`, `buttons.dart`, `motion_widgets.dart`, `app_card.dart`, `status_chip.dart`, `empty_state.dart`, `app_dialog.dart`, `door_open_button.dart`, `countdown_ring.dart`, `skeleton.dart`, `app_snack.dart`, `login_hero.dart`. Ortak liste parcalari: `lib/ui/widgets/list_parts.dart`.
- Kural: yeni ekran/dialogda ham renk (`Color(0xFF...)`, `Colors.red`), `isDark ?:` uclusu ve sabit fontSize yazilmaz; `context.palette`, `AppTone.<ton>` ve tema TextTheme kullanilir. Metin renkleri iki temada da >= 4,5:1 kontrast olmalidir (`test/design/contrast_test.dart` hakemdir).
- Animasyon sureleri `AppMotion.of(context)` ile alinir (sistemde "animasyonlari azalt" aciksa sifir). `AnimatedSize`/`AnimatedCrossFade` icin sifir sure kullanilmaz (Flutter assert atar; 1 ms verilir). Kararli durumda sonsuz animasyon birakilmaz (rozet nabzi 3 tur sonra durur, iskelet parlamasi yalnizca yuklenirken).
- Dokunma hedefleri >= 44 dp; metin olcegi `lib/app.dart` icinde en cok 2,0 ile sinirlanir; yeni ekranlar 320x640 x 2,0 yazida tasmamalidir (AGENTS.md kural 6, `test/screens/`).
- Tek bilesenler: kapi acma `DoorOpenButton`, QR geri sayimi `CountdownRing`, yukleme `SkeletonBox`/`ShimmerScope`, bos liste `EmptyState`, durum rozeti `StatusChip`, diyalog `AppDialog`/`AppDialogHeader`, bildirim `AppSnack`/`InlineNotice`.
- Akicilik: ag yoklamalari `lib/services/adaptive_poller.dart` ile yapilir (arka planda/ortulu iken durur, hatada ustel geri cekilme, ust uste binmez; HomePage 3 sn, bireysel kapi listesi 15 sn, QR modali 0,8 sn); agir isler (PDF uretimi, >= 64 KB JSON) `lib/services/background_work.dart` ile arka plan izolesinde calisir; GET zaman asimi 20 sn, yazma 45 sn, kapi acma 10 sn.
- Kare suresi olcumu: `integration_test/perf_frames_test.dart` + `test_driver/perf_driver.dart` (komut `SAHA_KONTROL_LISTESI.md` bolum 52); calistirmak proje sahibine aittir.

## 8. Ahbu Uygulamasi

`ahbu` ayri repodadir.

Kullanim mantigi:

- `super_user` girisi kapali
- sadece:
  - `site_manager`
  - `apartment_owner`
  giris yapabilir

Kayit davranisi:

- kayit butonunu sadece `site_manager` gorur
- `apartment_owner` kayit ekranini gormez

Site yoneticisi kayit akisi:

1. Ad Soyad
2. Telefon
3. E-posta
4. Sifre
5. Sifre tekrar
6. Kayit
7. 4 haneli sayisal e-posta dogrulama kodu
8. Kod dogrulama
9. Sirket onayi bekleme

Login kisitlari:

- e-posta dogrulanmadiysa giris engellenir
- abonelik `pending` ise giris engellenir
- abonelik `rejected` ise giris engellenir
- hesap pasif ise giris engellenir

Ahbu drawer:

- `Ana Sayfa`
- `Cihaz Ekle` (yalnizca `site_manager`)
- `Cikis Yap`

Ahbu cihaz ekleme akisi:

1. QR okut
2. `device_uid` al
3. backend'de cihaz lookup yap
4. cihaz sirket hesabinda kayitliysa listele
5. site yoneticisi bir `site` ve `gate_name` secer
6. cihaz o site kapisina atanir

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

Temel topic deseni:

- state: `device/<UID>/state`
- command: `device/<UID>/cmd`
- event: `device/<UID>/event`
- availability: `device/<UID>/availability`

Ornek roller:

- `api_bridge`
- `device_<UID>`

Kurulum ve ACL notlari ayrintili olarak:

- `MQTT_kurulum.txt`

## 11. ESP32 Firmware ve QR Araci

### 11.1 cihaz_kontrol

PlatformIO tabanlidir.

Desteklenen populer env ornekleri:

- `esp32-s3-devkitc-1`
- `esp32dev`
- `esp32doit-devkit-v1`
- `esp32-c3-devkitm-1`
- `lolin_c3_mini`
- `esp32-s2-saola-1`

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

- `/var/www/site_kapi_kontrol`

Backend process:

- `kapi-api`

Health check:

```bash
curl http://127.0.0.1:8080/health
```

Beklenen:

```json
{"ok":true,"database":"connected"}
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

Sirket uygulamasi:

```bash
flutter clean
flutter pub get
flutter analyze
flutter test        # 2357 test
flutter build apk --release
```

Ahbu:

```bash
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Backend:

```bash
cd server
npm install
node --check src/server.js
pm2 restart kapi-api --update-env
```

## 15. Sunucuda Guncelleme Sirasi

Backend degistiğinde:

```bash
cd /var/www/site_kapi_kontrol
git pull origin main

cd server
npm install
pm2 restart kapi-api --update-env
pm2 save
curl http://127.0.0.1:8080/health
```

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

## 17. Acik Tasarim Kararlari / Sonraki Adimlar

Planlanan veya yarim kalan alanlar:

- `site_manager` ile `sites` arasinda daha net sahiplik / yetki baglantisi
- `apartment_owner` aktivasyonunun `ahbu` uzerinden yonetilmesi
- cihaz listesi ve cihaz detay ekranlari
- daha ayrintili audit log
- merkezi teknik dokumanin surekli guncel tutulmasi

## 18. Bu Dosyanin Amaci

Bu dosya, yeni bilgisayarda veya yeni oturumda sohbet gecmisi olmasa bile:

- sistemin ne oldugunu
- nelerin calistigini
- nerede neyin oldugunu
- hangi komutlarla yeniden ayaga kaldirilacagini
- hangi sorunlarin daha once yasandigini

tek yerden anlamayi saglamak icin tutulur.
